load ../../tests/helpers

setup() {
    sandbox
    IND="$REPO_ROOT/waybar/.local/bin/waybar-indicators"
    # Only the fakes and the basic tools below are on PATH, so the real
    # toggle/capture/menu can never run.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat jq chmod sed grep tail rm; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    # State per feature lives in a file named after it; missing means off.
    # idle "on" means hypridle runs, so idle-inhibited is idle status off.
    fake toggle --no-log <<< 'echo "$(cat "$FAKE_DIR/state.$1" 2>/dev/null || echo off)"'
    fake capture <<< '[[ $* == "record status" ]] && echo "$(cat "$FAKE_DIR/state.record" 2>/dev/null || echo off)"; exit 0'
    fake menu < /dev/null
    echo on > "$FAKE_DIR/state.idle"
}

@test "no active states → empty text" {
    run "$IND" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(jq -r .text <<< "$output")" = "" ]
    [ "$(jq -c .class <<< "$output")" = "[]" ]
}

@test "recording + dnd → both icons and classes" {
    echo on > "$FAKE_DIR/state.record"
    echo on > "$FAKE_DIR/state.dnd"
    run "$IND" < /dev/null
    [ "$status" -eq 0 ]
    text=$(jq -r .text <<< "$output")
    [[ $text == *$''* ]]
    [[ $text == *$''* ]]
    [[ $text != *$''* ]]
    [ "$(jq -c .class <<< "$output")" = '["recording","dnd"]' ]
}

@test "nightlight and idle inhibit show when active" {
    echo on > "$FAKE_DIR/state.nightlight"
    echo off > "$FAKE_DIR/state.idle"
    run "$IND" < /dev/null
    [ "$(jq -c .class <<< "$output")" = '["nightlight","idle"]' ]
}

@test "reads recording state from capture record status" {
    echo on > "$FAKE_DIR/state.record"
    run "$IND" < /dev/null
    [ "$(jq -c .class <<< "$output")" = '["recording"]' ]
    [ "$(calls capture)" = "capture record status" ]
}

@test "click stops a recording" {
    echo on > "$FAKE_DIR/state.record"
    run "$IND" click < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls capture | tail -n1)" = "capture record toggle" ]
    [ -z "$(calls menu)" ]
}

@test "click opens the toggles menu when not recording" {
    run "$IND" click < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls menu)" = "menu /toggles" ]
    [ -z "$(calls capture | grep toggle || true)" ]
}
