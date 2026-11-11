#!/usr/bin/env bash
# Runs after every module is stowed: set the default theme.
set -euo pipefail

theme_set=$HOME/.local/bin/theme-set
[[ -x $theme_set ]] || {
    echo "session: $theme_set not found; stow the theme module, then run: theme-set gruvbox-dark" >&2
    exit 1
}
"$theme_set" gruvbox-dark
