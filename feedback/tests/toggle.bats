load ../../tests/helpers

setup() {
    sandbox
    TOGGLE="$REPO_ROOT/feedback/.local/bin/toggle"
    # Only the fakes and the basic tools below are on PATH, so the real
    # makoctl/hyprctl/pkill/notify-send can never run.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed head tail chmod rm; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    fake pkill < /dev/null
    fake notify-send < /dev/null
    fake uwsm-app < /dev/null
    mako_mode ""
    sunset_temp 6000
    fake pgrep --no-log <<< 'exit 1'
}

# mako_mode <modes> — fake makoctl: `mode` prints these; other calls only log.
mako_mode() {
    fake makoctl <<< "[[ \$1 == mode && \$# -eq 1 ]] && printf '%s\n' $(printf '%q' "$1"); exit 0"
}

# sunset_temp <K> — fake hyprctl: `hyprsunset temperature` prints K; sets only log.
sunset_temp() {
    fake hyprctl <<< "[[ \$* == 'hyprsunset temperature' ]] && echo $1; exit 0"
}

# hypridle_running — pgrep -x hypridle succeeds.
hypridle_running() {
    fake pgrep --no-log <<< '[[ "$*" == "-x hypridle" ]]'
}

@test "dnd flips via makoctl mode -t do-not-disturb" {
    run "$TOGGLE" dnd
    [ "$status" -eq 0 ]
    [ "$(calls makoctl | tail -n1)" = "makoctl mode -t do-not-disturb" ]
}

@test "dnd status reads makoctl mode" {
    mako_mode "default"
    run "$TOGGLE" dnd status
    [ "$output" = off ]
    mako_mode $'default\ndo-not-disturb'
    run "$TOGGLE" dnd status
    [ "$output" = on ]
}

@test "dnd on when already on does nothing" {
    mako_mode "do-not-disturb"
    run "$TOGGLE" dnd on
    [ "$status" -eq 0 ]
    [ -z "$(calls makoctl | grep -- '-t')" ]
    [ -z "$(calls pkill)" ]
}

@test "dnd on is silent but signals waybar" {
    run "$TOGGLE" dnd on
    [ -z "$(calls notify-send)" ]
    [ "$(calls pkill)" = "pkill -RTMIN+8 waybar" ]
}

@test "dnd off confirms with a notification" {
    mako_mode "do-not-disturb"
    run "$TOGGLE" dnd off
    [ "$(calls makoctl | tail -n1)" = "makoctl mode -t do-not-disturb" ]
    [ "$(calls notify-send)" = "notify-send -t 2000 Notifications on" ]
}

@test "status reads live state and changes nothing" {
    sunset_temp 4000
    run "$TOGGLE" nightlight status
    [ "$output" = on ]
    sunset_temp 6500
    run "$TOGGLE" nightlight status
    [ "$output" = off ]
    sunset_temp 6000
    run "$TOGGLE" nightlight status
    [ "$output" = off ]
    run "$TOGGLE" idle status
    [ "$output" = off ]
    hypridle_running
    run "$TOGGLE" idle status
    [ "$output" = on ]
    [ -z "$(calls pkill)" ]
    [ -z "$(calls notify-send)" ]
}

@test "nightlight status is off when hyprsunset gives no answer" {
    fake hyprctl <<< 'exit 1'
    run "$TOGGLE" nightlight status
    [ "$output" = off ]
}

@test "nightlight on sets 4000K without touching gamma" {
    run "$TOGGLE" nightlight on
    [ "$status" -eq 0 ]
    [ "$(calls hyprctl | tail -n1)" = "hyprctl hyprsunset temperature 4000" ]
    [ -z "$(calls hyprctl | grep -E 'gamma|identity')" ]
    [ "$(calls notify-send)" = "notify-send -t 2000 Night light on" ]
}

@test "nightlight off sets 6500K without touching gamma" {
    sunset_temp 4000
    run "$TOGGLE" nightlight off
    [ "$(calls hyprctl | tail -n1)" = "hyprctl hyprsunset temperature 6500" ]
    [ -z "$(calls hyprctl | grep -E 'gamma|identity')" ]
    [ "$(calls notify-send)" = "notify-send -t 2000 Night light off" ]
}

@test "nightlight flips from the live temperature" {
    sunset_temp 4000
    run "$TOGGLE" nightlight
    [ "$(calls hyprctl | tail -n1)" = "hyprctl hyprsunset temperature 6500" ]
    : > "$CALLS"
    sunset_temp 6000
    run "$TOGGLE" nightlight
    [ "$(calls hyprctl | tail -n1)" = "hyprctl hyprsunset temperature 4000" ]
}

@test "idle off kills hypridle" {
    hypridle_running
    run "$TOGGLE" idle off
    [ "$status" -eq 0 ]
    [[ "$(calls pkill)" == *"pkill -x hypridle"* ]]
    [ -z "$(calls uwsm-app)" ]
    [ "$(calls notify-send)" = "notify-send -t 2000 Idle lock off" ]
}

@test "idle on starts hypridle as a uwsm service, so it returns" {
    run "$TOGGLE" idle on
    [ "$status" -eq 0 ]
    [ "$(calls uwsm-app)" = "uwsm-app -t service -- hypridle" ]
    [ "$(calls notify-send)" = "notify-send -t 2000 Idle lock on" ]
}

@test "idle flips from the live process state" {
    hypridle_running
    run "$TOGGLE" idle
    [[ "$(calls pkill)" == *"pkill -x hypridle"* ]]
    : > "$CALLS"
    fake pgrep --no-log <<< 'exit 1'
    run "$TOGGLE" idle
    [ "$(calls uwsm-app)" = "uwsm-app -t service -- hypridle" ]
}

@test "every change signals waybar RTMIN+8" {
    for t in nightlight idle dnd; do
        : > "$CALLS"
        run "$TOGGLE" "$t" on
        [[ "$(calls pkill)" == *"pkill -RTMIN+8 waybar"* ]]
    done
}

@test "a failing notify-send does not fail the toggle" {
    fake notify-send <<< 'exit 1'
    run "$TOGGLE" nightlight on
    [ "$status" -eq 0 ]
}

@test "unknown toggle exits 2" {
    run "$TOGGLE" coffee
    [ "$status" -eq 2 ]
    [[ "$output" == *coffee* ]]
    run "$TOGGLE"
    [ "$status" -eq 2 ]
}

@test "unknown action exits 2" {
    run "$TOGGLE" dnd sideways
    [ "$status" -eq 2 ]
    [ -z "$(calls pkill)" ]
}

# A failed change must exit non-zero, say so, and neither signal nor notify.
assert_failed_cleanly() {
    [ "$status" -ne 0 ]
    [[ "$output" == *"toggle: $1 failed"* ]]
    [ -z "$(calls pkill | grep RTMIN)" ]
    [ -z "$(calls notify-send)" ]
}

@test "a failing hyprctl set fails nightlight cleanly" {
    fake hyprctl <<< '[[ $* == "hyprsunset temperature" ]] && echo 6000 && exit 0; exit 1'
    run "$TOGGLE" nightlight on
    assert_failed_cleanly nightlight
}

@test "a failing makoctl mode -t fails dnd cleanly" {
    fake makoctl <<< '[[ $* == mode ]] && echo do-not-disturb && exit 0; exit 1'
    run "$TOGGLE" dnd off
    assert_failed_cleanly dnd
}

@test "a failing uwsm-app fails idle on cleanly" {
    fake uwsm-app <<< 'exit 1'
    run "$TOGGLE" idle on
    assert_failed_cleanly idle
}
