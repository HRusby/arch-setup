#!/usr/bin/env bash
# Build the installer ISO: the installed archiso's releng profile plus this
# repo's overlay (iso/profile), assembled fresh in iso/work/profile.
# Usage: iso/build.sh [--out DIR]    (default iso/out; prints the ISO path)
#
# The overlay: packages.x86_64.extra is added to releng's package list;
# airootfs/** replaces releng's files, except root/.zlogin, which is appended
# so releng's own login steps still run. RELENG_DIR overrides the releng
# location (tests).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
releng=${RELENG_DIR:-/usr/share/archiso/configs/releng}
overlay=$here/profile
work=$here/work
profile=$work/profile
out=$here/out

die() {
    echo "build: $*" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        --out) [[ $# -ge 2 ]] || die "--out needs a directory"
            out=$2; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -f $releng/profiledef.sh ]] || die "no releng profile at $releng (install archiso)"

rm -rf "$profile"
mkdir -p "$work"
cp -a --no-preserve=ownership "$releng" "$profile"

while read -r pkg; do
    grep -qxF "$pkg" "$profile/packages.x86_64" || echo "$pkg" >> "$profile/packages.x86_64"
done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$overlay/packages.x86_64.extra" | grep -v '^$')

while read -r file; do
    rel=${file#"$overlay/airootfs/"}
    dest=$profile/airootfs/$rel
    mkdir -p "$(dirname "$dest")"
    if [[ $rel == root/.zlogin ]]; then
        cat "$file" >> "$dest"
    else
        cp --no-preserve=ownership "$file" "$dest"
    fi
done < <(find "$overlay/airootfs" -type f | sort)

# mkarchiso doesn't keep file modes from airootfs; profiledef.sh sets them.
echo 'file_permissions["/usr/local/bin/install-arch"]="0:0:755"' >> "$profile/profiledef.sh"

sudo mkarchiso -v -r -w "$work/build" -o "$out" "$profile"

iso=''
for f in "$out"/*.iso; do
    [[ -f $f && ( -z $iso || $f -nt $iso ) ]] && iso=$f
done
[[ -n $iso ]] || die "mkarchiso wrote no ISO to $out"
echo "$iso"
