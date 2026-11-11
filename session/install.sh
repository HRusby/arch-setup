#!/usr/bin/env bash
# Login and boot setup: tty1 autologin, console keymap, Plymouth, snapper
# snapshots in Limine, a Limine Windows entry and network/bluetooth services.
# Runs before the session module is stowed; safe to re-run. The theme is set
# by post-install.sh, once every module is stowed.
# SKEL_BASH_PROFILE, SNAPPER_ROOT_CONFIG, PROC_CMDLINE and KERNEL_CMDLINE_FILE
# override paths (tests).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skel_bash_profile=${SKEL_BASH_PROFILE:-/etc/skel/.bash_profile}
snapper_root_config=${SNAPPER_ROOT_CONFIG:-/etc/snapper/configs/root}
proc_cmdline=${PROC_CMDLINE:-/proc/cmdline}
kernel_cmdline=${KERNEL_CMDLINE_FILE:-/etc/kernel/cmdline}
user=${USER:-}

die() {
    echo "session: $*" >&2
    exit 1
}

# The name is substituted into a systemd unit, so only allow a plain login name.
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || die "refusing autologin for user '$user'"

# archinstall copies /etc/skel/.bash_profile; an untouched copy would only
# block stowing ours. A modified one is kept and stow reports the conflict.
if [[ -f $HOME/.bash_profile && ! -L $HOME/.bash_profile ]]; then
    if [[ -f $skel_bash_profile ]] && cmp -s "$skel_bash_profile" "$HOME/.bash_profile"; then
        rm -f "$HOME/.bash_profile"
    else
        echo "session: keeping your modified ~/.bash_profile; stow will report it as a conflict" >&2
    fi
fi

# System files (session/system/** -> /), with the autologin user filled in.
# Includes the mkinitcpio drop-ins that add the plymouth and btrfs-overlayfs hooks.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
while read -r file; do
    sed "s/__USER__/$user/g" "$file" > "$tmp"
    sudo install -Dm644 "$tmp" "/${file#"$here/system/"}"
done < <(find "$here/system" -type f | sort)

# limine-entry-tool takes the kernel cmdline from /etc/kernel/cmdline, else
# /proc/cmdline. Pin the one this system booted with (plus the Plymouth
# splash), so a kernel update made while booted into a snapshot can't write
# the snapshot's cmdline into the normal entries.
if [[ ! -e $kernel_cmdline ]]; then
    cmdline=$(< "$proc_cmdline")
    if [[ $cmdline == *.snapshots* ]]; then
        echo "session: booted from a snapshot; not pinning $kernel_cmdline" >&2
    else
        for word in quiet splash; do
            [[ " $cmdline " == *" $word "* ]] || cmdline+=" $word"
        done
        printf '%s\n' "$cmdline" > "$tmp"
        sudo install -Dm644 "$tmp" "$kernel_cmdline"
    fi
fi

# Rebuild the initramfs with the new hooks and regenerate the Limine entries.
# From here on limine-mkinitcpio-hook puts kernels only under
# ${ESP_PATH}/<machine-id>/, so its entries must be the ones Limine boots.
update_rc=0
update_out=$(sudo limine-update 2>&1) || update_rc=$?
[[ -z $update_out ]] || printf '%s\n' "$update_out"
(( update_rc == 0 )) || die "limine-update failed (exit $update_rc); see above"
if grep -qi 'skipping' <<< "$update_out"; then
    echo "session: WARNING: limine-update skipped something (see above); check the Limine entries before rebooting" >&2
fi

# One limine.conf, the managed one, without archinstall's stale kernel entries.
sudo "$here/.local/bin/limine-tidy-entries" ||
    die "the Limine config was not tidied (see above); fix it before rebooting or upgrading the kernel"

# create_snapper_config — snapper creates /.snapshots as a nested subvolume
# and fails if it already exists. archinstall may mount an @.snapshots
# subvolume there: move it aside, let snapper write its config, drop the
# nested subvolume snapper made and remount @.snapshots from fstab.
# --no-dbus: bootstrap runs in arch-chroot, with no system bus or snapperd.
create_snapper_config() {
    if ! findmnt -n --mountpoint /.snapshots > /dev/null; then
        sudo snapper --no-dbus -c root create-config / || die "snapper could not create the root config"
        return 0
    fi
    findmnt -n --fstab --mountpoint /.snapshots > /dev/null ||
        die "/.snapshots is mounted but not listed in fstab; set up snapper by hand"
    sudo umount /.snapshots
    if ! { sudo rmdir /.snapshots && sudo snapper --no-dbus -c root create-config /; }; then
        sudo mkdir -p /.snapshots
        sudo mount /.snapshots
        die "snapper could not create the root config; /.snapshots remounted"
    fi
    { sudo btrfs subvolume delete /.snapshots && sudo mkdir /.snapshots &&
        sudo mount /.snapshots && sudo chmod 750 /.snapshots; } ||
        die "snapper config created, but remounting @.snapshots failed; fix /.snapshots by hand"
}

if [[ ! -e $snapper_root_config ]]; then
    create_snapper_config
fi
sudo systemctl enable limine-snapper-sync.service snapper-cleanup.timer

# A missing Windows entry never makes the system unbootable: report and go on.
sudo "$here/.local/bin/limine-windows-entry" ||
    echo "session: limine-windows-entry failed (see above); re-run: sudo limine-windows-entry [--partuuid <uuid>]" >&2

sudo systemctl enable NetworkManager bluetooth
