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

@test "leaves paru to bootstrap.sh" {
    run "$INSTALL"
    [ "$status" -eq 0 ]
    [ -z "$(calls git)" ]
    [ -z "$(calls makepkg)" ]
    [ -z "$(grep -n 'paru-bin\|makepkg' "$INSTALL" || true)" ]
}

@test "installs system files under / with sudo install -Dm644" {
    run "$INSTALL"
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo install -Dm644 $REPO_ROOT/base/system/etc/xdg/reflector/reflector.conf /etc/xdg/reflector/reflector.conf" ]
}

@test "reflector.conf options are single-token values" {
    conf="$REPO_ROOT/base/system/etc/xdg/reflector/reflector.conf"
    while read -r line; do
        [[ -z $line || $line == \#* ]] && continue
        [[ $line =~ ^--[a-z-]+(\ [^\ ]+)?$ ]] || { echo "bad line: $line"; return 1; }
    done < "$conf"
}
