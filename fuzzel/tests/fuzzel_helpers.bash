# Shared sandbox for the fuzzel module tests. Only the fakes and the basic
# tools below are on PATH, so the real fuzzel/nmcli/hyprctl/cliphist/wl-copy
# can never run.

fuzzel_sandbox() {
    source "$BATS_TEST_DIRNAME/../../tests/helpers.bash"
    sandbox
    mkdir -p "$FAKE_DIR/sys"
    local c
    for c in bash env cat grep sed head tail chmod rm sort cut tr jq mktemp wc; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    export PICKS="$FAKE_DIR/picks" FUZZEL_IN="$FAKE_DIR/fuzzel.in"
    : > "$PICKS"
    : > "$FUZZEL_IN"
    # Fake fuzzel: appends its stdin (plus a "--" separator) to $FUZZEL_IN and
    # prints the next queued pick. An empty queue acts like Escape (exit 1).
    fake fuzzel <<'FAKE'
# Read the list from stdin only in --dmenu mode with a list: app mode and
# --prompt-only never read it, and must not block on an open tty or pipe.
if [[ " $* " == *" --dmenu "* && " $* " != *" --prompt-only "* ]]; then
    cat >> "$FUZZEL_IN"
fi
echo '--' >> "$FUZZEL_IN"
[[ " $* " == *" --dmenu "* ]] || exit 0
[[ -s $PICKS ]] || exit 1
pick=$(head -n1 "$PICKS")
sed -i 1d "$PICKS"
printf '%s\n' "$pick"
FAKE
    fake uwsm-app < /dev/null
    fake notify-send < /dev/null
}

# picks <line...> — what successive fuzzel calls will return.
picks() {
    printf '%s\n' "$@" >> "$PICKS"
}

# shown <n> — the n-th (1-based) list handed to fuzzel on stdin.
shown() {
    local n=$1 i=1 line
    while IFS= read -r line; do
        if [[ $line == -- ]]; then
            ((i++))
        elif ((i == n)); then
            printf '%s\n' "$line"
        fi
    done < "$FUZZEL_IN"
}
