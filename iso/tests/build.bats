load ../../tests/helpers

# iso/build.sh against a fixture releng profile. A copy of iso/ lives in the
# sandbox so builds never touch the repo's iso/work or iso/out. Fake sudo runs
# its command; fake mkarchiso writes an empty ISO into its -o directory.

setup() {
    sandbox
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed awk rm find mkdir cp chmod dirname touch sort cmp head; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"

    cp -r "$REPO_ROOT/iso" "$REPO/iso"
    rm -rf "$REPO/iso/work" "$REPO/iso/out" "$REPO/iso/tests"
    BUILD="$REPO/iso/build.sh"
    PROFILE="$REPO/iso/work/profile"

    export RELENG_DIR="$FAKE_DIR/releng"
    mkdir -p "$RELENG_DIR/airootfs/root" "$RELENG_DIR/airootfs/etc"
    cat > "$RELENG_DIR/profiledef.sh" <<'EOF'
#!/usr/bin/env bash
iso_name="archlinux"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
)
EOF
    printf '%s\n' base archinstall sudo > "$RELENG_DIR/packages.x86_64"
    printf '%s\n' '# releng login' '~/.automated_script.sh' > "$RELENG_DIR/airootfs/root/.zlogin"
    echo releng > "$RELENG_DIR/airootfs/etc/motd"

    fake sudo <<< 'exec "$@"'
    fake mkarchiso <<'EOF'
while (( $# )); do
    [[ $1 == -o ]] && { mkdir -p "$2"; touch "$2/archlinux-test-x86_64.iso"; }
    shift
done
EOF
}

@test "adds the extra packages to releng's list once" {
    run "$BUILD"
    [ "$status" -eq 0 ]
    [ "$(grep -cx archinstall "$PROFILE/packages.x86_64")" -eq 1 ]
    grep -qx git "$PROFILE/packages.x86_64"
    grep -qx jq "$PROFILE/packages.x86_64"
    grep -qx base "$PROFILE/packages.x86_64"
}

@test "overlays the installer onto releng's airootfs" {
    run "$BUILD"
    [ "$status" -eq 0 ]
    cmp -s "$REPO/iso/profile/airootfs/usr/local/bin/install-arch" "$PROFILE/airootfs/usr/local/bin/install-arch"
    [ -f "$PROFILE/airootfs/root/archinstall/user_configuration.json" ]
    [ "$(cat "$PROFILE/airootfs/etc/motd")" = releng ]
}

@test "appends the install-arch hook to releng's .zlogin" {
    run "$BUILD"
    [ "$status" -eq 0 ]
    [ "$(head -n 2 "$PROFILE/airootfs/root/.zlogin")" = "$(cat "$RELENG_DIR/airootfs/root/.zlogin")" ]
    grep -q 'install-arch' "$PROFILE/airootfs/root/.zlogin"
    grep -q '/dev/tty1' "$PROFILE/airootfs/root/.zlogin"
}

@test "marks install-arch executable in profiledef.sh" {
    run "$BUILD"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC1091
    perms=$(declare -A file_permissions; source "$PROFILE/profiledef.sh"; echo "${file_permissions[/usr/local/bin/install-arch]}:${file_permissions[/root]}")
    [ "$perms" = "0:0:755:0:0:750" ]
}

@test "runs mkarchiso through sudo and prints the ISO path" {
    run "$BUILD"
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo mkarchiso -v -r -w $REPO/iso/work/build -o $REPO/iso/out $PROFILE" ]
    [ "${lines[-1]}" = "$REPO/iso/out/archlinux-test-x86_64.iso" ]
}

@test "--out sets the output directory" {
    run "$BUILD" --out "$FAKE_DIR/isos"
    [ "$status" -eq 0 ]
    [[ "$(calls mkarchiso)" == *" -o $FAKE_DIR/isos "* ]]
    [ "${lines[-1]}" = "$FAKE_DIR/isos/archlinux-test-x86_64.iso" ]
}

@test "rebuilds from a fresh releng copy" {
    mkdir -p "$PROFILE/airootfs/etc"
    echo stale > "$PROFILE/airootfs/etc/stale"
    run "$BUILD"
    [ "$status" -eq 0 ]
    [ ! -e "$PROFILE/airootfs/etc/stale" ]
    [ "$(grep -c 'install-arch' "$PROFILE/airootfs/root/.zlogin")" -ge 1 ]
    [ "$(grep -cx git "$PROFILE/packages.x86_64")" -eq 1 ]
}

@test "fails before sudo when releng is missing" {
    export RELENG_DIR="$FAKE_DIR/nowhere"
    run "$BUILD"
    [ "$status" -ne 0 ]
    [[ "$output" == *"archiso"* ]]
    [ -z "$(calls sudo)" ]
}

@test "rejects unknown options" {
    run "$BUILD" --bogus
    [ "$status" -ne 0 ]
    [ -z "$(calls sudo)" ]
}
