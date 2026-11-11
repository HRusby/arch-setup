load ../../tests/helpers

setup() {
    sandbox
    THEME_SET="$REPO_ROOT/theme/.local/bin/theme-set"
    export THEME_DIR="$HOME/.config/theme"
    mkdir -p "$THEME_DIR/palettes" "$THEME_DIR/templates" "$THEME_DIR/wallpapers"
    cp "$REPO_ROOT"/theme/.config/theme/palettes/*.toml "$THEME_DIR/palettes/"
    # Hide the real hyprctl/pkill/gsettings/...: only the fakes and the
    # basic tools below are on PATH, so a test can never touch the session.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed mktemp mv rm ln mkdir basename readlink touch cp chmod; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    fake pgrep --no-log <<< 'exit 1'
}

# running <proc...> — pgrep succeeds only for these process names.
running() {
    local body='for p in '"$*"'; do [[ "$*" == *"$p"* ]] && exit 0; done; exit 1'
    fake pgrep --no-log <<< "$body"
}

use_real_templates() {
    cp "$REPO_ROOT"/theme/.config/theme/templates/*.tpl "$THEME_DIR/templates/"
}

@test "renders placeholders" {
    echo 'a={{bg}} b={{bg.hex}}' > "$THEME_DIR/templates/t.conf.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(cat "$THEME_DIR/generated/t.conf")" = "a=#282828 b=282828" ]
}

@test "renders every template in the templates dir" {
    echo '{{fg}}' > "$THEME_DIR/templates/one.tpl"
    echo '{{red.hex}}' > "$THEME_DIR/templates/two.ini.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(cat "$THEME_DIR/generated/one")" = "#ebdbb2" ]
    [ "$(cat "$THEME_DIR/generated/two.ini")" = "fb4934" ]
}

@test "unknown placeholder fails naming it and writes nothing" {
    echo 'ok={{bg}}' > "$THEME_DIR/templates/a.tpl"
    echo 'bad={{nope}}' > "$THEME_DIR/templates/b.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 1 ]
    [[ "$output" == *nope* ]]
    [ ! -e "$THEME_DIR/generated/a" ]
    [ ! -e "$THEME_DIR/generated/b" ]
    [ ! -e "$THEME_DIR/current" ]
}

@test "missing required key fails naming the key" {
    grep -v '^purple' "$THEME_DIR/palettes/gruvbox-dark.toml" > "$THEME_DIR/palettes/broken.toml"
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" broken
    [ "$status" -eq 1 ]
    [[ "$output" == *purple* ]]
    [ ! -e "$THEME_DIR/generated/a" ]
}

@test "malformed colour value fails" {
    sed 's/#fb4934/red/' "$THEME_DIR/palettes/gruvbox-dark.toml" > "$THEME_DIR/palettes/bad.toml"
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" bad
    [ "$status" -eq 1 ]
    [[ "$output" == *red* ]]
}

@test "unknown theme exits 2" {
    run "$THEME_SET" no-such-theme
    [ "$status" -eq 2 ]
    run "$THEME_SET" ../palettes/gruvbox-dark
    [ "$status" -eq 2 ]
    run "$THEME_SET"
    [ "$status" -eq 2 ]
}

@test "--list prints gruvbox-dark" {
    run "$THEME_SET" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *gruvbox-dark* ]]
}

@test "current symlink points at chosen palette" {
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(readlink "$THEME_DIR/current")" = "$THEME_DIR/palettes/gruvbox-dark.toml" ]
}

@test "btop theme is linked into the btop themes dir" {
    use_real_templates
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.config/btop/themes/palette.theme")" = "$THEME_DIR/generated/btop.theme" ]
}

@test "renders and exits 0 when no tools are running" {
    use_real_templates
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    for f in colors.css colors.lua colors.conf foot-colors.ini fuzzel-colors.ini btop.theme satty.toml mako.conf; do
        [ -s "$THEME_DIR/generated/$f" ]
    done
    [ ! -s "$CALLS" ]
}

@test "reloads nothing when tools exist but are not running" {
    use_real_templates
    fake hyprctl < /dev/null
    fake pkill < /dev/null
    fake makoctl < /dev/null
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "reloads only running tools" {
    fake hyprctl < /dev/null
    fake pkill < /dev/null
    fake makoctl < /dev/null
    running waybar
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(calls pkill)" = "pkill -SIGUSR2 waybar" ]
    [ -z "$(calls makoctl)" ]
    [ -z "$(calls hyprctl)" ]
}

@test "reloads hyprland and mako when running" {
    fake hyprctl < /dev/null
    fake makoctl < /dev/null
    running Hyprland mako
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(calls hyprctl)" = "hyprctl reload" ]
    [ "$(calls makoctl)" = "makoctl reload" ]
}

@test "a failing reload does not stop the others or the exit status" {
    fake hyprctl < /dev/null
    fake pkill < /dev/null
    fake gsettings < /dev/null
    fake makoctl <<< 'exit 1'
    running Hyprland waybar mako hyprpaper
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    echo 'wallpaper = "wall.png"' >> "$THEME_DIR/palettes/gruvbox-dark.toml"
    touch "$THEME_DIR/wallpapers/wall.png"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ -n "$(calls makoctl)" ]
    [[ "$(calls hyprctl)" == *"hyprpaper wallpaper"* ]]
    [ -n "$(calls gsettings)" ]
    [ -f "$THEME_DIR/generated/a" ]
}

@test "does not call a running tool that is not installed" {
    running waybar Hyprland mako
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "sets wallpaper only if file exists" {
    fake hyprctl < /dev/null
    running hyprpaper
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    echo 'wallpaper = "wall.png"' >> "$THEME_DIR/palettes/gruvbox-dark.toml"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ -z "$(calls hyprctl)" ]
    touch "$THEME_DIR/wallpapers/wall.png"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(calls hyprctl)" = "hyprctl hyprpaper wallpaper ,$THEME_DIR/wallpapers/wall.png" ]
}

@test "sets dark colour scheme when gsettings exists" {
    fake gsettings < /dev/null
    echo '{{bg}}' > "$THEME_DIR/templates/a.tpl"
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    [ "$(calls gsettings)" = "gsettings set org.gnome.desktop.interface color-scheme prefer-dark" ]
}

@test "gruvbox-dark palette has every required key" {
    for k in bg bg1 bg2 bg3 fg fg_dim grey red green yellow blue purple aqua orange accent; do
        grep -Eq "^$k = \"#[0-9a-f]{6}\"" "$REPO_ROOT/theme/.config/theme/palettes/gruvbox-dark.toml" || { echo "missing $k"; false; }
    done
}

@test "shipped templates render without leftover placeholders" {
    use_real_templates
    run "$THEME_SET" gruvbox-dark
    [ "$status" -eq 0 ]
    ! grep -r '{{' "$THEME_DIR/generated"
}

@test "shipped templates have the documented shapes" {
    use_real_templates
    run "$THEME_SET" gruvbox-dark
    g="$THEME_DIR/generated"
    grep -qx '@define-color bg #282828;' "$g/colors.css"
    grep -q 'bg = "282828"' "$g/colors.lua"
    grep -q '^return {' "$g/colors.lua"
    grep -qx '$bg = rgb(282828)' "$g/colors.conf"
    grep -q '^\[colors-dark\]' "$g/foot-colors.ini"
    grep -q '^background=282828' "$g/foot-colors.ini"
    grep -q '^\[colors\]' "$g/fuzzel-colors.ini"
    grep -q '^background=282828' "$g/fuzzel-colors.ini"
    grep -q 'theme\[main_bg\]="#282828"' "$g/btop.theme"
    grep -q '^background-color=#282828' "$g/mako.conf"
}
