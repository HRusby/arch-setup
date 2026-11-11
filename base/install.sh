#!/usr/bin/env bash
# Install base's system files (base/system/** -> /). paru is built by bootstrap.sh.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

while read -r file; do
    sudo install -Dm644 "$file" "/${file#"$here/system/"}"
done < <(find "$here/system" -type f | sort)
