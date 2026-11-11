#!/usr/bin/env bash
# Login and boot setup: tty1 autologin, console keymap, Plymouth, snapper
# snapshots in Limine, a Limine Windows entry, network/bluetooth services and
# the default theme. Runs before the session module is stowed; safe to re-run.
# SKEL_BASH_PROFILE, SNAPPER_ROOT_CONFIG and THEME_SET override paths (tests).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
skel_bash_profile=${SKEL_BASH_PROFILE:-/etc/skel/.bash_profile}
snapper_root_config=${SNAPPER_ROOT_CONFIG:-/etc/snapper/configs/root}
theme_set=${THEME_SET:-$HOME/.local/bin/theme-set}
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
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
while read -r file; do
    sed "s/__USER__/$user/g" "$file" > "$tmp"
    sudo install -Dm644 "$tmp" "/${file#"$here/system/"}"
done < <(find "$here/system" -type f | sort)

# Plymouth: the mkinitcpio.conf.d drop-in above adds the hook; rebuild with it.
sudo mkinitcpio -P

if [[ ! -e $snapper_root_config ]]; then
    sudo snapper -c root create-config / ||
        die "snapper could not create the root config (does /.snapshots already exist?)"
fi
sudo systemctl enable limine-snapper-sync.service snapper-cleanup.timer

sudo "$here/.local/bin/limine-windows-entry"

sudo systemctl enable NetworkManager bluetooth

if [[ -x $theme_set ]]; then
    "$theme_set" gruvbox-dark
else
    echo "session: $theme_set not found yet; after bootstrap run: theme-set gruvbox-dark" >&2
fi
