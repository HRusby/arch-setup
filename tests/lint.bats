load helpers

COLOUR_RE='#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?\b|rgba?\([0-9a-fA-F]{6,8}\)|rgba?\([0-9 ,.%]+\)'

# colour_hits <root> — colour literals in module files under a git work tree.
colour_hits() {
    (
        cd "$1"
        git ls-files -co --exclude-standard -z |
            grep -zv -e '^docs/' -e '^tests/' -e '^[^/]*/tests/' -e '^\.superpowers/' \
                -e '^theme/\.config/theme/palettes/' -e '^[^/]*$' |
            xargs -0 -r grep -InE "$COLOUR_RE" || true
    )
}

# fixture <line> — temp git repo with one module file holding <line>.
fixture() {
    local root="$BATS_TEST_TMPDIR/lintfix"
    rm -rf "$root"
    mkdir -p "$root/mod/.config"
    git -C "$root" init -q
    printf '%s\n' "$1" > "$root/mod/.config/f"
    echo "$root"
}

@test "no colour literals outside palettes" {
    hits=$(colour_hits "$REPO_ROOT")
    [ -z "$hits" ] || { echo "$hits"; false; }
}

@test "colour lint catches literal forms" {
    for line in 'c = #aabbcc' 'c = #aabbccdd' 'c = rgba(30, 30, 46, 0.8)' 'c = rgb(255,0,0)' 'c = rgb(aabbcc)'; do
        [ -n "$(colour_hits "$(fixture "$line")")" ] || { echo "missed: $line"; false; }
    done
}

@test "colour lint catches literals in iso/" {
    root=$(fixture "x")
    mkdir -p "$root/iso/airootfs"
    echo 'c = #aabbcc' > "$root/iso/airootfs/f"
    [ -n "$(colour_hits "$root")" ]
}

@test "colour lint allows palette-built colours" {
    for line in 'c = "rgb(" .. c.accent .. ")"' 'c = rgb({{bg.hex}})'; do
        [ -z "$(colour_hits "$(fixture "$line")")" ] || { echo "flagged: $line"; false; }
    done
}

@test "every script is shellcheck clean" {
    cd "$REPO_ROOT"
    shopt -s nullglob
    files=(bootstrap.sh iso/*.sh iso/profile/airootfs/usr/local/bin/* */install.sh */post-install.sh */.local/bin/*)
    run shellcheck -x "${files[@]}"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "README gives the full test suite command" {
    grep -qF 'bats -r tests */tests' "$REPO_ROOT/README.md"
}
