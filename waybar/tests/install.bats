load ../../tests/helpers

setup() {
    sandbox
    INSTALL="$REPO_ROOT/waybar/install.sh"
    CONF="$HOME/.config/btop/btop.conf"
}

@test "creates btop.conf with the palette theme when missing" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$CONF")" = 'color_theme = "palette"' ]
}

@test "sets color_theme in an existing btop.conf, keeping other settings" {
    mkdir -p "$(dirname "$CONF")"
    printf '%s\n' '#? Config file for btop v.1.4.5' 'color_theme = "Default"' 'theme_background = True' > "$CONF"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$CONF")" = '#? Config file for btop v.1.4.5
color_theme = "palette"
theme_background = True' ]
}

@test "replaces an unquoted or single-quoted color_theme" {
    mkdir -p "$(dirname "$CONF")"
    printf '%s\n' "color_theme='Default'" 'x = 1' > "$CONF"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$CONF")" = 'color_theme = "palette"
x = 1' ]
    printf '%s\n' 'color_theme = /usr/share/btop/themes/nord.theme' > "$CONF"
    run "$INSTALL" < /dev/null
    [ "$(cat "$CONF")" = 'color_theme = "palette"' ]
}

@test "adds color_theme to a btop.conf that lacks it" {
    mkdir -p "$(dirname "$CONF")"
    echo 'theme_background = True' > "$CONF"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$CONF")" = 'theme_background = True
color_theme = "palette"' ]
}

@test "is idempotent" {
    run "$INSTALL" < /dev/null
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$CONF")" = 'color_theme = "palette"' ]
}

@test "btop.conf is not stowed (btop rewrites it through the link)" {
    [ ! -e "$REPO_ROOT/waybar/.config/btop/btop.conf" ]
}

@test "replaces a btop.conf link left by an older stow with a real file" {
    mkdir -p "$(dirname "$CONF")" "$FAKE_DIR/old"
    ln -s "$FAKE_DIR/old/btop.conf" "$CONF"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ ! -L "$CONF" ]
    [ ! -e "$FAKE_DIR/old/btop.conf" ]
    [ "$(cat "$CONF")" = 'color_theme = "palette"' ]
}
