#!/usr/bin/env bash
# Install and stow dotfile modules.
# Usage: bootstrap.sh [--modules a,b,...] [--lists base,desktop] [--adopt] [--dry-run]
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Module metadata that must never be linked into $HOME.
STOW_IGNORES=(
    --ignore='^/packages\.txt$'
    --ignore='^/packages\.aur\.txt$'
    --ignore='^/install\.sh$'
    --ignore='^/post-install\.sh$'
    --ignore='^/tests$'
    --ignore='^/system$'
)

modules=()
lists=(base desktop)
explicit=0
adopt=0
dry=0

die() {
    echo "bootstrap: $*" >&2
    exit 1
}

# entries <file> — names in a list file; '#' comments and blank lines dropped.
entries() {
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# need_paru — true when AUR packages are wanted and paru is not installed yet.
need_paru() {
    (( ${#aur_pkgs[@]} )) && ! command -v paru > /dev/null
}

# build_paru — build and install paru-bin from the AUR (needs base-devel, git).
build_paru() (
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    cd "$tmp/paru-bin"
    makepkg -si --noconfirm
)

while (( $# )); do
    case "$1" in
        --modules) [[ $# -ge 2 ]] || die "--modules needs a value"
            IFS=, read -r -a modules <<< "$2"; explicit=1; shift 2 ;;
        --lists) [[ $# -ge 2 ]] || die "--lists needs a value"
            IFS=, read -r -a lists <<< "$2"; shift 2 ;;
        --adopt) adopt=1; shift ;;
        --dry-run) dry=1; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

if (( ! explicit )); then
    for l in "${lists[@]}"; do
        [[ -f $REPO/modules.$l ]] || die "unknown list: $l"
        mapfile -t -O "${#modules[@]}" modules < <(entries "$REPO/modules.$l")
    done
fi

for m in "${modules[@]}"; do
    [[ -d $REPO/$m ]] || die "unknown module: $m"
done

repo_pkgs=()
aur_pkgs=()
for m in "${modules[@]}"; do
    [[ -f $REPO/$m/packages.txt ]] && mapfile -t -O "${#repo_pkgs[@]}" repo_pkgs < <(entries "$REPO/$m/packages.txt")
    [[ -f $REPO/$m/packages.aur.txt ]] && mapfile -t -O "${#aur_pkgs[@]}" aur_pkgs < <(entries "$REPO/$m/packages.aur.txt")
done

stow_args=(--dir="$REPO" --target="$HOME" --no-folding "${STOW_IGNORES[@]}")
(( adopt )) && stow_args+=(--adopt)

if (( dry )); then
    echo "modules: ${modules[*]}"
    (( ${#repo_pkgs[@]} )) && echo "pacman: ${repo_pkgs[*]}"
    if need_paru; then echo "build paru-bin: paru is not installed"; fi
    (( ${#aur_pkgs[@]} )) && echo "paru: ${aur_pkgs[*]}"
    for m in "${modules[@]}"; do
        [[ -x $REPO/$m/install.sh ]] && echo "install: $m/install.sh"
    done
    for m in "${modules[@]}"; do echo "stow: $m"; done
    for m in "${modules[@]}"; do
        [[ -x $REPO/$m/post-install.sh ]] && echo "post-install: $m/post-install.sh"
    done
    exit 0
fi

(( ${#repo_pkgs[@]} )) && sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
if need_paru; then
    build_paru
    command -v paru > /dev/null || die "paru is still missing after building paru-bin"
fi
(( ${#aur_pkgs[@]} )) && paru -S --needed --noconfirm "${aur_pkgs[@]}"

for m in "${modules[@]}"; do
    [[ -x $REPO/$m/install.sh ]] && "$REPO/$m/install.sh"
done

# Simulate first so a conflict aborts before anything is linked (--adopt resolves them).
if (( ! adopt )); then
    conflicts=""
    for m in "${modules[@]}"; do
        rc=0
        out=$(stow --no --verbose "${stow_args[@]}" --restow "$m" 2>&1) || rc=$?
        if (( rc )); then
            found=$(grep -E '^[[:space:]]*\* ' <<< "$out" || true)
            conflicts+="${found:-$out}"$'\n'
        fi
    done
    if [[ -n $conflicts ]]; then
        echo "bootstrap: stow conflicts, nothing stowed (re-run with --adopt to take over these files):" >&2
        printf '%s' "$conflicts" >&2
        exit 1
    fi
fi

for m in "${modules[@]}"; do
    stow "${stow_args[@]}" --restow "$m"
done

# Steps that need every module's files in place (e.g. theme-set from theme).
for m in "${modules[@]}"; do
    if [[ -x $REPO/$m/post-install.sh ]]; then
        "$REPO/$m/post-install.sh"
    fi
done
