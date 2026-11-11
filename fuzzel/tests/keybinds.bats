setup() {
    load fuzzel_helpers
    fuzzel_sandbox
    KEYBINDS="$REPO_ROOT/fuzzel/.local/bin/keybinds"
}

# bind <mouse> <modmask> <key> <description> [keycode] — a bind in `hyprctl binds -j` shape.
bind() {
    jq -n --argjson mouse "$1" --argjson mod "$2" --arg key "$3" --arg d "$4" --argjson code "${5:-0}" '{
        locked: false, mouse: $mouse, release: false, repeat: false, longPress: false,
        non_consuming: false, auto_consuming: false, has_description: ($d != ""),
        modmask: $mod, submap: "", submap_universal: "false", key: $key, keycode: $code,
        catch_all: false, description: $d, allow_input_capture: false,
        dispatcher: "__lua", arg: "1"}'
}

# hypr_binds <bind...> — fake hyprctl serving these as `binds -j`.
hypr_binds() {
    printf '%s\n' "$@" | jq -s . > "$FAKE_DIR/binds.json"
    fake hyprctl --no-log <<< '[[ "$*" == "binds -j" ]] && cat "$FAKE_DIR/binds.json"'
}

@test "super bind renders as MODS + KEY  description" {
    hypr_binds "$(bind false 64 K Keybindings)"
    run "$KEYBINDS"
    [ "$status" -eq 0 ]
    [ "$(shown 1)" = "SUPER + K  Keybindings" ]
}

@test "modmask is decoded and ordered" {
    hypr_binds "$(bind false 65 B Browser)" "$(bind false 4 F5 Ctrl)" "$(bind false 8 F6 Alt)" \
        "$(bind false 77 X All)" "$(bind false 0 XF86AudioMute Mute)"
    run "$KEYBINDS"
    [ "$(shown 1)" = $'ALT + F6  Alt
CTRL + F5  Ctrl
SUPER + SHIFT + B  Browser
SUPER + SHIFT + CTRL + ALT + X  All
XF86AudioMute  Mute' ]
}

@test "lock modifier bits are ignored" {
    hypr_binds "$(bind false 67 L Lock)"
    run "$KEYBINDS"
    [ "$(shown 1)" = "SUPER + SHIFT + L  Lock" ]
}

@test "empty description shows (no description)" {
    hypr_binds "$(bind false 64 J '')"
    run "$KEYBINDS"
    [ "$(shown 1)" = "SUPER + J  (no description)" ]
}

@test "mouse and switch binds are excluded" {
    hypr_binds "$(bind true 64 mouse:272 Move)" "$(bind false 64 mouse_down Scroll)" \
        "$(bind false 0 'switch:on:Lid Switch' Lid)" "$(bind false 64 K Keybindings)"
    run "$KEYBINDS"
    [ "$(shown 1)" = "SUPER + K  Keybindings" ]
}

@test "output is sorted" {
    hypr_binds "$(bind false 64 Z Zed)" "$(bind false 64 A Aye)"
    run "$KEYBINDS"
    [ "$(shown 1)" = $'SUPER + A  Aye\nSUPER + Z  Zed' ]
}

@test "escape exits 0" {
    hypr_binds "$(bind false 64 K Keybindings)"
    run "$KEYBINDS"
    [ "$status" -eq 0 ]
}

@test "code: binds show the key they stand for" {
    hypr_binds "$(bind false 64 '' 'Workspace 1' 10)" "$(bind false 64 '' 'Workspace 10' 19)" \
        "$(bind false 64 '' 'Expand left' 20)" "$(bind false 64 '' 'Shrink left' 21)" \
        "$(bind false 65 '' 'System menu' 201)"
    run "$KEYBINDS"
    [ "$status" -eq 0 ]
    [ "$(shown 1)" = $'SUPER + 0  Workspace 10
SUPER + 1  Workspace 1
SUPER + SHIFT + code:201  System menu
SUPER + equal  Shrink left
SUPER + minus  Expand left' ]
}
