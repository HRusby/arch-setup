load ../../tests/helpers

setup() {
    sandbox
    SYSUPDATE="$REPO_ROOT/base/.local/bin/sysupdate"
    # Only fakes and basic tools on PATH: real sudo/pacman/snapper can never run.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed chmod mkdir awk mktemp rm find sort date dirname; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    fake sudo < /dev/null
    fake paru < /dev/null
    fake pacdiff < /dev/null
    # pacman -Qdtq: no orphans by default (exit 1, no output), like the real one.
    fake pacman <<< '[[ "$1" == -Qdtq ]] && exit 1; exit 0'
}

orphans() {
    fake pacman <<< 'if [[ "$1" == -Qdtq ]]; then echo orphan-a; echo orphan-b; exit 0; fi; exit 0'
}

# sudo_fails <pattern> — fake sudo that fails when its arguments contain pattern.
sudo_fails() {
    fake sudo <<< '[[ "$*" == *'"$1"'* ]] && exit 1; exit 0'
}

@test "runs steps in order" {
    run "$SYSUPDATE" --yes
    [ "$status" -eq 0 ]
    expected='sudo snapper -c root create -d sysupdate pre --cleanup-algorithm number
sudo reflector @/etc/xdg/reflector/reflector.conf
sudo pacman -Syu
paru -Sua
pacman -Qdtq
pacdiff -o'
    [ "$(grep -v '^$' "$CALLS")" = "$expected" ]
}

@test "no orphans is not an error" {
    run "$SYSUPDATE"
    [ "$status" -eq 0 ]
    [ -z "$(calls 'sudo pacman -Rns')" ]
    [[ "$output" != *"sysupdate:"* ]]
}

@test "orphans removed only after yes" {
    orphans
    run "$SYSUPDATE" <<< 'n'
    [ "$status" -eq 0 ]
    [[ "$output" == *orphan-a* ]]
    [ -z "$(calls 'sudo pacman -Rns')" ]
    run "$SYSUPDATE" <<< 'y'
    [ "$status" -eq 0 ]
    [ "$(calls 'sudo pacman -Rns')" = "sudo pacman -Rns orphan-a orphan-b" ]
}

@test "--yes skips orphan prompt" {
    orphans
    run "$SYSUPDATE" --yes < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls 'sudo pacman -Rns')" = "sudo pacman -Rns orphan-a orphan-b" ]
}

@test "failed snapshot stops before pacman -Syu" {
    sudo_fails snapper
    run "$SYSUPDATE" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"sysupdate: snapshot failed"* ]]
    [ -z "$(calls 'sudo pacman')" ]
    [ -z "$(calls reflector)" ]
}

@test "failed reflector stops before pacman -Syu" {
    sudo_fails reflector
    run "$SYSUPDATE" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"sysupdate: mirrors failed"* ]]
    [ -z "$(calls 'sudo pacman')" ]
}

@test "failed pacman -Syu stops before paru" {
    sudo_fails -Syu
    run "$SYSUPDATE" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"sysupdate: pacman failed"* ]]
    [ -z "$(calls paru)" ]
}

@test "failed paru stops before orphan check" {
    fake paru <<< 'exit 1'
    run "$SYSUPDATE" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"sysupdate: aur failed"* ]]
    [ -z "$(calls pacman)" ]
}

@test "rejects unknown options" {
    run "$SYSUPDATE" --bogus
    [ "$status" -eq 2 ]
}
