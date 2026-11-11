load ../../tests/helpers

setup() {
    sandbox
    INSTALL="$REPO_ROOT/base/install.sh"
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed chmod mkdir awk mktemp rm find sort date dirname; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    fake sudo < /dev/null
    fake git <<< 'mkdir -p "${@: -1}"'
    fake makepkg < /dev/null
}

@test "skips paru build when paru exists" {
    fake paru < /dev/null
    run "$INSTALL"
    [ "$status" -eq 0 ]
    [ -z "$(calls git)" ]
    [ -z "$(calls makepkg)" ]
}

@test "builds paru-bin from the AUR when paru is missing" {
    run "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$(calls git)" == "git clone https://aur.archlinux.org/paru-bin.git "* ]]
    [ "$(calls makepkg)" = "makepkg -si --noconfirm" ]
}

@test "installs system files under / with sudo install -Dm644" {
    fake paru < /dev/null
    run "$INSTALL"
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo install -Dm644 $REPO_ROOT/base/system/etc/xdg/reflector/reflector.conf /etc/xdg/reflector/reflector.conf" ]
}
