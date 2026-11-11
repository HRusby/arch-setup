load ../../tests/helpers

setup() {
    sandbox
    REMIND="$REPO_ROOT/base/.local/bin/remind"
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed chmod mkdir awk mktemp rm find sort date dirname; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    fake systemd-run < /dev/null
    fake systemctl < /dev/null
}

@test "schedules a user timer with the message" {
    run "$REMIND" 10 stand up and stretch
    [ "$status" -eq 0 ]
    line="$(calls systemd-run)"
    [[ "$line" =~ ^systemd-run\ --user\ --on-active=10m\ --unit=remind-[0-9]+\ --description=stand\ up\ and\ stretch\ notify-send\ -u\ critical\ Reminder\ stand\ up\ and\ stretch$ ]]
}

@test "rejects non-numeric minutes" {
    run "$REMIND" soon call mum
    [ "$status" -eq 2 ]
    run "$REMIND" 5
    [ "$status" -eq 2 ]
    [ -z "$(calls systemd-run)" ]
}

@test "list shows remind timers" {
    fake systemctl --no-log <<< 'echo "remind-1.timer remind-2.timer"'
    run "$REMIND" list
    [ "$status" -eq 0 ]
    [[ "$output" == *remind-1* ]]
}

@test "clear stops all remind timers" {
    fake systemctl <<< '[[ "$*" == *list-units* ]] && printf "remind-1.timer\nremind-2.timer\n"; exit 0'
    run "$REMIND" clear
    [ "$status" -eq 0 ]
    [ "$(calls systemctl | grep -c -- '--user stop remind-')" -eq 2 ]
    [[ "$(calls systemctl)" == *"--user stop remind-1.timer"* ]]
    [[ "$(calls systemctl)" == *"--user stop remind-2.timer"* ]]
}
