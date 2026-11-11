load ../../tests/helpers

setup() {
    sandbox
    INSTALL="$REPO_ROOT/session/install.sh"
    mkdir -p "$FAKE_DIR/sys" "$FAKE_DIR/root"
    for c in bash env cat grep sed chmod mkdir mktemp rm find sort dirname cmp cp tr ln; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    export USER=alice
    # sudo only logs, except `install`, which it copies under $FAKE_DIR/root
    # so the installed content can be checked. Nothing runs as root.
    fake sudo <<'EOF'
if [[ $1 == install ]]; then
    dest="$FAKE_DIR/root${*: -1}"
    mkdir -p "$(dirname "$dest")"
    cp "${@: -2:1}" "$dest"
fi
EOF
    printf '#\n# ~/.bash_profile\n#\n\n[[ -f ~/.bashrc ]] && . ~/.bashrc\n' > "$FAKE_DIR/skel_bash_profile"
    export SKEL_BASH_PROFILE="$FAKE_DIR/skel_bash_profile"
    export SNAPPER_ROOT_CONFIG="$FAKE_DIR/snapper-root"
    : > "$SNAPPER_ROOT_CONFIG"
    export PROC_CMDLINE="$FAKE_DIR/proc-cmdline"
    echo 'cryptdevice=PARTUUID=abcd:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs' > "$PROC_CMDLINE"
    export KERNEL_CMDLINE_FILE="$FAKE_DIR/kernel-cmdline"
    # findmnt: /.snapshots mounted / listed in fstab only when the test says so.
    fake findmnt <<'EOF2'
[[ " $* " == *" --fstab "* ]] && exit "${SNAPSHOTS_IN_FSTAB:-1}"
exit "${SNAPSHOTS_MOUNTED:-1}"
EOF2
}

@test "substitutes the user into autologin" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    conf="$FAKE_DIR/root/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    [ "$(cat "$conf")" = "[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin alice %I \$TERM" ]
}

@test "refuses a user name that is not a plain login name" {
    USER='al/ice' run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(calls sudo)" ]
}

@test "installs the uk console keymap and the plymouth mkinitcpio drop-in" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_DIR/root/etc/vconsole.conf")" = "KEYMAP=uk" ]
    cmp "$REPO_ROOT/session/system/etc/mkinitcpio.conf.d/plymouth.conf" \
        "$FAKE_DIR/root/etc/mkinitcpio.conf.d/plymouth.conf"
    cmp "$REPO_ROOT/session/system/etc/mkinitcpio.conf.d/btrfs-overlayfs.conf" \
        "$FAKE_DIR/root/etc/mkinitcpio.conf.d/btrfs-overlayfs.conf"
}

@test "rebuilds the initramfs and boot entries after installing system files" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    last_install=$(grep -n '^sudo install ' "$CALLS" | sed -n '$s/:.*//p')
    rebuild=$(grep -n '^sudo limine-update$' "$CALLS" | sed 's/:.*//')
    [ -n "$rebuild" ]
    [ "$rebuild" -gt "$last_install" ]
}

@test "skips snapper create when config exists" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(grep '^sudo snapper' "$CALLS" || true)" ]
}

@test "creates the snapper root config when missing" {
    rm "$SNAPPER_ROOT_CONFIG"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(grep "^sudo snapper " "$CALLS")" = "sudo snapper -c root create-config /" ]
    [ -z "$(grep -E '^sudo (umount|btrfs)' "$CALLS" || true)" ]
}

@test "moves a mounted /.snapshots subvolume aside for snapper and remounts it" {
    rm "$SNAPPER_ROOT_CONFIG"
    SNAPSHOTS_MOUNTED=0 SNAPSHOTS_IN_FSTAB=0 run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(grep -E '^sudo (umount|rmdir|snapper|btrfs|mkdir|mount|chmod) ' "$CALLS")" = "sudo umount /.snapshots
sudo rmdir /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount /.snapshots
sudo chmod 750 /.snapshots" ]
}

@test "remounts /.snapshots when snapper fails, then stops" {
    rm "$SNAPPER_ROOT_CONFIG"
    fake sudo <<'EOF2'
[[ $1 == snapper ]] && exit 1
exit 0
EOF2
    SNAPSHOTS_MOUNTED=0 SNAPSHOTS_IN_FSTAB=0 run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(grep '^sudo btrfs' "$CALLS" || true)" ]
    [ "$(grep -E '^sudo (mkdir|mount) ' "$CALLS")" = "sudo mkdir -p /.snapshots
sudo mount /.snapshots" ]
    [ -z "$(grep '^sudo systemctl' "$CALLS" || true)" ]
}

@test "remounts /.snapshots when the empty mount point cannot be removed" {
    rm "$SNAPPER_ROOT_CONFIG"
    fake sudo <<'EOF2'
[[ $1 == rmdir ]] && exit 1
exit 0
EOF2
    SNAPSHOTS_MOUNTED=0 SNAPSHOTS_IN_FSTAB=0 run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(grep '^sudo snapper' "$CALLS" || true)" ]
    [ "$(grep -E '^sudo (mkdir|mount) ' "$CALLS")" = "sudo mkdir -p /.snapshots
sudo mount /.snapshots" ]
}

@test "refuses to touch a mounted /.snapshots that fstab does not list" {
    rm "$SNAPPER_ROOT_CONFIG"
    SNAPSHOTS_MOUNTED=0 run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(grep -E '^sudo (umount|snapper)' "$CALLS" || true)" ]
}

@test "pins the running kernel cmdline, with splash, for limine-entry-tool" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$FAKE_DIR/root$KERNEL_CMDLINE_FILE")" = "cryptdevice=PARTUUID=abcd:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs quiet splash" ]
}

@test "keeps an existing kernel cmdline file" {
    echo 'mine' > "$KERNEL_CMDLINE_FILE"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_DIR/root$KERNEL_CMDLINE_FILE" ]
}

@test "does not pin a cmdline booted from a snapshot" {
    echo 'root=/dev/mapper/root rootflags=subvol=/@/.snapshots/3/snapshot rw' > "$PROC_CMDLINE"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_DIR/root$KERNEL_CMDLINE_FILE" ]
    [[ $output == *snapshot* ]]
}

@test "removes untouched skel .bash_profile but keeps a modified one" {
    cp "$SKEL_BASH_PROFILE" "$HOME/.bash_profile"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.bash_profile" ]

    { cat "$SKEL_BASH_PROFILE"; echo 'export EDITOR=nvim'; } > "$HOME/.bash_profile"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -f "$HOME/.bash_profile" ]
    grep -q 'EDITOR=nvim' "$HOME/.bash_profile"
    [[ $output == *".bash_profile"* ]]
}

@test "leaves a stowed .bash_profile symlink alone" {
    ln -s "$SKEL_BASH_PROFILE" "$HOME/.bash_profile"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -L "$HOME/.bash_profile" ]
}

@test "enables snapshot sync, network and bluetooth" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    grep -qx 'sudo systemctl enable limine-snapper-sync.service snapper-cleanup.timer' "$CALLS"
    grep -qx 'sudo systemctl enable NetworkManager bluetooth' "$CALLS"
}

@test "runs limine-windows-entry from the module as root" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    grep -qx "sudo $REPO_ROOT/session/.local/bin/limine-windows-entry" "$CALLS"
}

@test "tidies the Limine config after limine-update and before the Windows entry" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    update=$(grep -n '^sudo limine-update$' "$CALLS" | sed 's/:.*//')
    tidy=$(grep -nx "sudo $REPO_ROOT/session/.local/bin/limine-tidy-entries" "$CALLS" | sed 's/:.*//')
    windows=$(grep -nx "sudo $REPO_ROOT/session/.local/bin/limine-windows-entry" "$CALLS" | sed 's/:.*//')
    [ -n "$update" ] && [ -n "$tidy" ] && [ -n "$windows" ]
    [ "$update" -lt "$tidy" ]
    [ "$tidy" -lt "$windows" ]
}

@test "stops when the Limine config cannot be tidied" {
    fake sudo <<'EOF2'
[[ $1 == */limine-tidy-entries ]] && exit 1
exit 0
EOF2
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [[ $output == *"Limine config was not tidied"* ]]
    [ -z "$(grep 'limine-windows-entry' "$CALLS" || true)" ]
}

@test "warns loudly when limine-update skipped something" {
    fake sudo <<'EOF2'
[[ $1 == limine-update ]] && echo "Skipping kernel linux: no initramfs found"
exit 0
EOF2
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [[ $output == *"Skipping kernel linux"* ]]
    [[ $output == *"WARNING"*"limine-update skipped"* ]]
}

@test "stops when limine-update fails" {
    fake sudo <<'EOF2'
[[ $1 == limine-update ]] && { echo "boom"; exit 1; }
exit 0
EOF2
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [[ $output == *boom* ]]
    [ -z "$(grep 'limine-tidy-entries' "$CALLS" || true)" ]
}

@test "a failed limine-windows-entry is reported but does not stop the install" {
    fake sudo <<'EOF2'
[[ $1 == */limine-windows-entry ]] && exit 2
exit 0
EOF2
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [[ $output == *"limine-windows-entry"* ]]
    grep -qx 'sudo systemctl enable NetworkManager bluetooth' "$CALLS"
}

@test "install.sh leaves the theme to post-install.sh" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(calls theme-set)" ]
    [ -z "$(grep -n 'theme-set' "$INSTALL" || true)" ]
}

@test "post-install sets the default theme with the stowed theme-set" {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/bash\necho "theme-set $*" >> "$CALLS"\n' > "$HOME/.local/bin/theme-set"
    chmod +x "$HOME/.local/bin/theme-set"
    run "$REPO_ROOT/session/post-install.sh" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls theme-set)" = "theme-set gruvbox-dark" ]
}

@test "post-install fails clearly when theme-set is missing" {
    run "$REPO_ROOT/session/post-install.sh" < /dev/null
    [ "$status" -ne 0 ]
    [[ $output == *"theme-set"*"theme module"* ]]
}

@test "is idempotent: a second run succeeds and makes the same calls" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    first=$(cat "$CALLS"); : > "$CALLS"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(sed 's/tmp\.[A-Za-z0-9]*/TMP/g' "$CALLS")" = "$(sed 's/tmp\.[A-Za-z0-9]*/TMP/g' <<< "$first")" ]
}

# hooks_after <HOOKS...> — HOOKS after sourcing the plymouth drop-in twice
# (mkinitcpio sources drop-ins more than once).
hooks_after() {
    bash -c 'HOOKS=("$@"); . "$0"; . "$0"; echo "${HOOKS[*]}"' \
        "$REPO_ROOT/session/system/etc/mkinitcpio.conf.d/plymouth.conf" "$@"
}

# overlay_after <HOOKS...> — same for the btrfs-overlayfs drop-in.
overlay_after() {
    bash -c 'HOOKS=("$@"); . "$0"; . "$0"; echo "${HOOKS[*]}"' \
        "$REPO_ROOT/session/system/etc/mkinitcpio.conf.d/btrfs-overlayfs.conf" "$@"
}

@test "btrfs-overlayfs hook goes right after filesystems, once" {
    [ "$(overlay_after base udev plymouth block encrypt filesystems fsck)" = "base udev plymouth block encrypt filesystems btrfs-overlayfs fsck" ]
}

@test "systemd initramfs gets sd-btrfs-overlayfs instead" {
    [ "$(overlay_after base systemd plymouth block sd-encrypt filesystems fsck)" = "base systemd plymouth block sd-encrypt filesystems sd-btrfs-overlayfs fsck" ]
}

@test "overlayfs drop-in leaves HOOKS that already have it alone" {
    [ "$(overlay_after base udev filesystems btrfs-overlayfs fsck)" = "base udev filesystems btrfs-overlayfs fsck" ]
}

@test "plymouth hook goes right after udev, once" {
    [ "$(hooks_after base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)" = \
        "base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck" ]
}

@test "plymouth hook goes right after systemd, before sd-encrypt" {
    [ "$(hooks_after base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)" = \
        "base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck" ]
}

@test "plymouth drop-in leaves HOOKS that already have plymouth alone" {
    [ "$(hooks_after base udev keyboard plymouth block encrypt filesystems)" = "base udev keyboard plymouth block encrypt filesystems" ]
}

@test "bash_profile starts hyprland through uwsm when uwsm may start" {
    fake uwsm <<< '[[ $1 == check ]] && exit "${MAY_START:-1}"; exit 0'
    MAY_START=0 run bash --noprofile --norc -c ". '$REPO_ROOT/session/.bash_profile'; echo after"
    [ "$(calls uwsm)" = "uwsm check may-start
uwsm start hyprland.desktop" ]
    [[ $output != *after* ]]
}

@test "bash_profile does nothing more when uwsm may not start" {
    fake uwsm <<< '[[ $1 == check ]] && exit "${MAY_START:-1}"; exit 0'
    run bash --noprofile --norc -c ". '$REPO_ROOT/session/.bash_profile'; echo after"
    [ "$status" -eq 0 ]
    [ "$(calls uwsm)" = "uwsm check may-start" ]
    [ "$output" = "after" ]
}

@test "packages are listed" {
    [ "$(tr '\n' ' ' < "$REPO_ROOT/session/packages.txt")" = "plymouth limine snapper snap-pac bluez bluez-utils " ]
    [ "$(tr '\n' ' ' < "$REPO_ROOT/session/packages.aur.txt")" = "limine-snapper-sync limine-mkinitcpio-hook " ]
}

@test "bash_profile puts ~/.local/bin on PATH before uwsm starts the session" {
    fake uwsm <<< '[[ $1 == start ]] && echo "PATH=$PATH" >> "$CALLS"; [[ $1 == check ]] && exit 0; exit 0'
    run bash --noprofile --norc -c ". '$REPO_ROOT/session/.bash_profile'"
    [ "$status" -eq 0 ]
    [[ "$(grep '^PATH=' "$CALLS")" == "PATH=$HOME/.local/bin:"* ]]
}

@test "bash_profile exports ~/.local/bin on PATH once" {
    fake uwsm <<< 'exit 1'
    run bash --noprofile --norc -c "PATH='$HOME/.local/bin:$PATH'; . '$REPO_ROOT/session/.bash_profile'; . '$REPO_ROOT/session/.bash_profile'; bash -c 'echo \"\$PATH\"'"
    [ "$status" -eq 0 ]
    [ "$(tr ':' '\n' <<< "$output" | grep -cx "$HOME/.local/bin")" -eq 1 ]

    run bash --noprofile --norc -c ". '$REPO_ROOT/session/.bash_profile'; . '$REPO_ROOT/session/.bash_profile'; bash -c 'echo \"\$PATH\"'"
    [ "$status" -eq 0 ]
    [[ $output == "$HOME/.local/bin:"* ]]
    [ "$(tr ':' '\n' <<< "$output" | grep -cx "$HOME/.local/bin")" -eq 1 ]
}
