#!/usr/bin/env bash
# btop rewrites btop.conf on exit, so it is never stowed (a link would get the
# repo file overwritten). Point btop at the generated palette theme instead,
# keeping every other setting btop has written.
set -euo pipefail

conf=$HOME/.config/btop/btop.conf
setting='color_theme = "palette"'

# A link from an older stow of this module: btop's settings live in a real file.
if [[ -L $conf ]]; then
    rm -f "$conf"
fi

mkdir -p "$(dirname "$conf")"
if [[ ! -f $conf ]]; then
    printf '%s\n' "$setting" > "$conf"
elif grep -q '^[[:space:]]*color_theme[[:space:]]*=' "$conf"; then
    sed -i "s|^[[:space:]]*color_theme[[:space:]]*=.*|$setting|" "$conf"
else
    printf '%s\n' "$setting" >> "$conf"
fi
