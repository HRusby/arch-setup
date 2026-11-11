load ../../tests/helpers

@test "mako config takes its colours from the generated theme file" {
    # include must come before any [section] so it applies globally
    first=$(grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/feedback/.config/mako/config" | head -n1)
    [ "$first" = "include=~/.config/theme/generated/mako.conf" ]
}

@test "mako config hides notifications in do-not-disturb mode" {
    grep -Pzq '\[mode=do-not-disturb\]\s*\n\s*invisible=1' "$REPO_ROOT/feedback/.config/mako/config"
}

@test "mako config sets no colours of its own" {
    ! grep -E '^[[:space:]]*[a-z-]*color[a-z-]*=' "$REPO_ROOT/feedback/.config/mako/config"
}

@test "swayosd style imports the generated colour definitions" {
    grep -qx '@import url("../theme/generated/colors.css");' "$REPO_ROOT/feedback/.config/swayosd/style.css"
}

@test "packages are listed" {
    [ "$(tr "\n" " " < "$REPO_ROOT/feedback/packages.txt")" = "mako swayosd libnotify playerctl " ]
}
