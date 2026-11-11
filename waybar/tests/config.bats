load ../../tests/helpers

# strip_comments — drop // line comments (config.jsonc keeps them on their own lines).
strip_comments() { sed -E 's@^[[:space:]]*//.*$@@' "$1"; }

@test "config.jsonc parses as JSON once comments are stripped" {
    run jq -e . <<< "$(strip_comments "$REPO_ROOT/waybar/.config/waybar/config.jsonc")"
    [ "$status" -eq 0 ]
}

@test "bar layout matches the spec" {
    cfg=$(strip_comments "$REPO_ROOT/waybar/.config/waybar/config.jsonc")
    [ "$(jq -c '."modules-left"' <<< "$cfg")" = '["custom/menu","hyprland/workspaces"]' ]
    [ "$(jq -c '."modules-center"' <<< "$cfg")" = '["clock","custom/indicators"]' ]
    [ "$(jq -c '."modules-right"' <<< "$cfg")" = '["tray","bluetooth","network","pulseaudio","cpu","memory","custom/weather"]' ]
    [ "$(jq -r '."custom/indicators".signal' <<< "$cfg")" = 8 ]
    [ "$(jq -r '."custom/indicators".interval' <<< "$cfg")" = 30 ]
    [ "$(jq -r '."custom/weather".interval' <<< "$cfg")" = 900 ]
}

@test "style.css imports the generated colours" {
    css="$REPO_ROOT/waybar/.config/waybar/style.css"
    grep -q '^@import url("../theme/generated/colors.css");' "$css"
}

@test "on-click commands launch through uwsm-app, like the binds" {
    cfg=$(strip_comments "$REPO_ROOT/waybar/.config/waybar/config.jsonc")
    clicks=$(jq -r '.[] | objects | ."on-click" // empty | select(. != "activate")' <<< "$cfg" | sort)
    [ "$clicks" = "uwsm-app -- foot -e bluetui
uwsm-app -- foot -e btop
uwsm-app -- foot -e btop
uwsm-app -- foot -e wiremix
uwsm-app -- menu
uwsm-app -- nm-menu
uwsm-app -- waybar-indicators click" ] || { echo "$clicks"; false; }
}
