#!/usr/bin/env bash
# Bootstrap paru and install base's system files (base/system/** -> /).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v paru > /dev/null; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
fi

while read -r file; do
    sudo install -Dm644 "$file" "/${file#"$here/system/"}"
done < <(find "$here/system" -type f | sort)
