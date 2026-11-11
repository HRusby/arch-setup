setup() {
    load fuzzel_helpers
    fuzzel_sandbox
    CLIPMENU="$REPO_ROOT/fuzzel/.local/bin/clipmenu"
    # cliphist list prints entries; decode logs what it was given and echoes the payload.
    fake cliphist --no-log <<'FAKE'
case $1 in
    list) printf '2\tsecond copy\n1\tfirst copy\n' ;;
    decode) read -r line; echo "decode $line" >> "$CALLS"; echo "payload of ${line%%$'\t'*}" ;;
esac
FAKE
    fake wl-copy --no-log <<< 'echo "wl-copy $(cat)" >> "$CALLS"'
}

@test "pipes selection through decode into wl-copy" {
    picks $'1\tfirst copy'
    run "$CLIPMENU"
    [ "$status" -eq 0 ]
    [ "$(shown 1)" = $'2\tsecond copy\n1\tfirst copy' ]
    [ "$(grep -v '^fuzzel ' "$CALLS")" = $'decode 1\tfirst copy\nwl-copy payload of 1' ]
}

@test "escape copies nothing" {
    run "$CLIPMENU"
    [ "$status" -eq 0 ]
    [ -z "$(grep -v '^fuzzel ' "$CALLS")" ]
}
