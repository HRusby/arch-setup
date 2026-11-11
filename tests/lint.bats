load helpers

# Lint runs against the real repo, not the sandbox fixture.

@test "no colour literals outside palettes" {
    cd "$REPO_ROOT"
    hits=$(git ls-files -co --exclude-standard -z |
        grep -zv -e '^docs/' -e '^tests/' -e '^iso/' -e '^\.superpowers/' \
            -e '^theme/\.config/theme/palettes/' -e '^[^/]*$' |
        xargs -0 -r grep -InE '#[0-9a-fA-F]{6}\b|rgba?\([0-9a-fA-F]{6,8}\)' || true)
    [ -z "$hits" ] || { echo "$hits"; false; }
}

@test "every script is shellcheck clean" {
    cd "$REPO_ROOT"
    shopt -s nullglob
    files=(bootstrap.sh iso/*.sh */.local/bin/*)
    run shellcheck -x "${files[@]}"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}
