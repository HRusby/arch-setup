load ../../tests/helpers

setup() {
    MOD="$REPO_ROOT/hyprland"
    HYPR="$MOD/.config/hypr"
}

# spec — run the binds_spec.lua case named like this test.
spec() {
    run lua "$MOD/tests/binds_spec.lua" "$BATS_TEST_DESCRIPTION"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every bind has a non-empty description" { spec; }
@test "no key combination is bound twice" { spec; }
@test "bind() errors without a description" { spec; }
@test "bind() runs strings via uwsm-app and passes dispatchers through" { spec; }
@test "required binds exist" { spec; }
@test "no bind references omarchy" { spec; }
@test "config loads without generated colors.lua" { spec; }
@test "border colours come from colors.lua" { spec; }
@test "monitors match spec" { spec; }
@test "input uses the gb layout" { spec; }
@test "autostart launches the session via uwsm-app" { spec; }

@test "every .lua file parses" {
    shopt -s globstar nullglob
    files=("$MOD"/**/*.lua)
    [ "${#files[@]}" -gt 0 ]
    run luac -p "${files[@]}"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "no file references omarchy" {
    run grep -rli omarchy "$HYPR"
    [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "hyprlock takes its colours from the generated palette" {
    grep -qx 'source = ~/.config/theme/generated/colors.conf' "$HYPR/hyprlock.conf"
}

@test "hypridle dims at 150s, locks at 300s, blanks at 330s" {
    f="$HYPR/hypridle.conf"
    grep -q 'lock_cmd = pidof hyprlock || hyprlock' "$f"
    for t in 150 300 330; do grep -qE "timeout = $t\b" "$f"; done
    grep -A2 'timeout = 300' "$f" | grep -q 'on-timeout = loginctl lock-session'
    grep -A2 'timeout = 330' "$f" | grep -q 'action = "disable"'
}

@test "hyprpaper has ipc on" {
    grep -qE '^ipc = (true|on)$' "$HYPR/hyprpaper.conf"
}

# Hyprland's own parser checks config keys, rule fields and dispatcher names.
# --verify-config never starts a compositor; HOME and the runtime dir are
# sandboxed so it can't see the real session or config.
verify_config() {
    command -v Hyprland > /dev/null || skip "Hyprland is not installed"
    local home="$BATS_TEST_TMPDIR/home" run_dir="$BATS_TEST_TMPDIR/run"
    mkdir -p "$home" "$run_dir"
    chmod 700 "$run_dir"
    run env -i PATH=/usr/bin HOME="$home" XDG_RUNTIME_DIR="$run_dir" \
        Hyprland --verify-config -c "$HYPR/hyprland.lua"
    [[ $output == *"config ok"* ]] || { echo "$output"; false; }
}

@test "Hyprland accepts the config without a palette" {
    verify_config
}

@test "Hyprland accepts the config with a palette" {
    mkdir -p "$BATS_TEST_TMPDIR/home/.config/theme/generated"
    cp "$MOD/tests/fixture/theme/generated/colors.lua" "$BATS_TEST_TMPDIR/home/.config/theme/generated/"
    verify_config
}
