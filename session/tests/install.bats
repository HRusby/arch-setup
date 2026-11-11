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
}

@test "rebuilds the initramfs after installing system files" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    last_install=$(grep -n '^sudo install ' "$CALLS" | sed -n '$s/:.*//p')
    rebuild=$(grep -n '^sudo mkinitcpio -P$' "$CALLS" | sed 's/:.*//')
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

@test "sets the default theme with theme-set" {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/bash\necho "theme-set $*" >> "$CALLS"\n' > "$HOME/.local/bin/theme-set"
    chmod +x "$HOME/.local/bin/theme-set"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls theme-set)" = "theme-set gruvbox-dark" ]
}

@test "tolerates a missing theme-set with a clear message" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [[ $output == *"theme-set gruvbox-dark"* ]]
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
    [ "$(cat "$REPO_ROOT/session/packages.aur.txt")" = "limine-snapper-sync" ]
}
