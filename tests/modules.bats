load helpers

setup() {
    sandbox
    mkdir -p "$HOME/.config/theme/generated"
}

# render_fixtures — a rendered colours.lua and foot-colors.ini under $HOME.
render_fixtures() {
    local gen="$HOME/.config/theme/generated"
    cat > "$gen/colors.lua" <<'LUA'
return {
  bg = "282828", bg1 = "3c3836", bg2 = "504945", bg3 = "665c54",
  fg = "ebdbb2", fg_dim = "bdae93", grey = "928374",
  red = "fb4934", green = "b8bb26", yellow = "fabd2f", blue = "83a598",
  purple = "d3869b", aqua = "8ec07c", orange = "fe8019", accent = "fabd2f",
}
LUA
    sed -E 's/\{\{([a-z_0-9]+)\.hex\}\}/aabbcc/' \
        "$REPO_ROOT/theme/.config/theme/templates/foot-colors.ini.tpl" > "$gen/foot-colors.ini"
}

@test "foot.ini includes generated colours" {
    grep -qx 'include=~/.config/theme/generated/foot-colors.ini' "$REPO_ROOT/foot/.config/foot/foot.ini"
}

@test "foot --check-config passes against the module file" {
    command -v foot > /dev/null || skip "foot is not installed"
    render_fixtures
    mkdir -p "$HOME/.config/foot"
    cp "$REPO_ROOT/foot/.config/foot/foot.ini" "$HOME/.config/foot/foot.ini"
    XDG_CONFIG_HOME="$HOME/.config" run foot --check-config
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "nvim colourscheme loads headless" {
    command -v nvim > /dev/null || skip "nvim is not installed"
    render_fixtures
    run nvim --headless -u NONE -i NONE \
        --cmd "set rtp+=$REPO_ROOT/nvim/.config/nvim" \
        -c 'colorscheme palette' \
        -c 'lua if vim.g.colors_name ~= "palette" then vim.cmd("cquit 1") end' \
        -c 'lua if vim.api.nvim_get_hl(0, {name = "Normal"}).bg ~= 0x282828 then vim.cmd("cquit 2") end' \
        -c 'lua if vim.api.nvim_get_hl(0, {name = "DiagnosticError"}).fg ~= 0xfb4934 then vim.cmd("cquit 3") end' \
        -c q
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "apps install.sh sets firefox and nvim defaults" {
    fake xdg-mime < /dev/null
    run "$REPO_ROOT/apps/install.sh"
    [ "$status" -eq 0 ]
    [ "$(calls xdg-mime)" = "xdg-mime default firefox.desktop x-scheme-handler/http x-scheme-handler/https text/html
xdg-mime default nvim.desktop text/plain" ]
}

@test "no module ships a stowed mimeapps.list" {
    [ -z "$(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -path '*/.config/mimeapps.list' -print)" ]
}

@test "mail module is in no install list" {
    ! grep -qx mail "$REPO_ROOT"/modules.*
}

@test "mail install.sh sets thunderbird as default for mail types" {
    fake xdg-mime < /dev/null
    run "$REPO_ROOT/mail/install.sh"
    [ "$status" -eq 0 ]
    [ "$(calls xdg-mime)" = "xdg-mime default org.mozilla.Thunderbird.desktop x-scheme-handler/mailto message/rfc822 x-scheme-handler/mid" ]
}

@test "mail autostarts proton bridge hidden" {
    grep -qx 'Exec=protonmail-bridge --no-window' "$REPO_ROOT/mail/.config/autostart/protonmail-bridge.desktop"
    grep -qx 'protonmail-bridge' "$REPO_ROOT/mail/packages.txt"
}
