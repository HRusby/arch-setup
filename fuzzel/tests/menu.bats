setup() {
    load fuzzel_helpers
    fuzzel_sandbox
    MENU="$REPO_ROOT/fuzzel/.local/bin/menu"
    export MENU_TSV="$REPO_ROOT/fuzzel/.config/menu/menu.tsv"
    fake theme-set --no-log <<< '[[ $1 == --list ]] && printf "nord\ngruvbox\n"'
}

@test "top level shows spec entries in order" {
    run "$MENU"
    [ "$status" -eq 0 ]
    [ "$(shown 1)" = $'Apps\nTheme\nCapture\nToggles\nClipboard\nKeybinds\nReminder\nNetwork\nUpdate\nPower' ]
}

@test "@path opens submenu" {
    picks Capture
    run "$MENU"
    [ "$status" -eq 0 ]
    [[ "$(shown 2)" == *"Screenshot region"* ]]
    [[ "$(shown 2)" != *Clipboard* ]]
}

@test "named submenu opens directly, with or without slash" {
    run "$MENU" toggles
    run "$MENU" /toggles
    [ "$(shown 1)" = "$(shown 2)" ]
    [[ "$(shown 1)" == *"Do not disturb"* ]]
}

@test "capture and toggles entries run their commands through uwsm-app" {
    picks "Screenshot window"
    run "$MENU" capture
    picks "Night light"
    run "$MENU" toggles
    [ "$(calls uwsm-app)" = $'uwsm-app -- capture screenshot window\nuwsm-app -- toggle nightlight' ]
}

@test "escape exits 0 and runs nothing" {
    run "$MENU"
    [ "$status" -eq 0 ]
    [ -z "$(calls uwsm-app)" ]
    run "$MENU" power
    [ "$status" -eq 0 ]
    [ -z "$(calls uwsm-app)" ]
}

@test "theme submenu lists themes and runs theme-set" {
    picks gruvbox
    run "$MENU" theme
    [ "$status" -eq 0 ]
    [ "$(shown 1)" = $'nord\ngruvbox' ]
    [ "$(calls uwsm-app)" = "uwsm-app -- theme-set gruvbox" ]
}

@test "power submenu has Lock, Suspend, Logout, Reboot, Shutdown" {
    run "$MENU" power
    [ "$(shown 1)" = $'Lock\nSuspend\nLogout\nReboot\nShutdown' ]
    local label cmd
    while IFS='|' read -r label cmd; do
        : > "$CALLS"
        picks "$label"
        run "$MENU" power
        [ "$(calls uwsm-app)" = "uwsm-app -- $cmd" ] || { echo "$label: $(cat "$CALLS")"; false; }
    done <<< $'Lock|loginctl lock-session\nSuspend|systemctl suspend\nLogout|uwsm stop\nReboot|systemctl reboot\nShutdown|systemctl poweroff'
}

@test "Update opens a terminal running sysupdate" {
    picks Update
    run "$MENU"
    [ "$(calls uwsm-app)" = "uwsm-app -- foot -e sysupdate" ]
}

@test "apps runs fuzzel in app mode" {
    run "$MENU" apps
    [ "$status" -eq 0 ]
    [ "$(calls fuzzel)" = "fuzzel " ]
}

@test "Apps entry from the top level opens the app picker" {
    picks Apps
    run "$MENU"
    [ "$(calls fuzzel | tail -n1)" = "fuzzel " ]
}

@test "reminder prompts minutes then message and runs remind" {
    picks 15 "stand up and stretch"
    run "$MENU" reminder
    [ "$status" -eq 0 ]
    [ "$(calls fuzzel | wc -l)" -eq 2 ]
    calls fuzzel | head -n1 | grep -q 'Remind in'
    calls fuzzel | tail -n1 | grep -q 'Message'
    [ "$(calls uwsm-app)" = "uwsm-app -- remind 15 stand up and stretch" ]
}

@test "reminder rejects non-numeric minutes" {
    picks soon "x"
    run "$MENU" reminder
    [ "$status" -ne 0 ]
    [ -z "$(calls uwsm-app)" ]
    [ -n "$(calls notify-send)" ]
}

@test "reminder with escape does nothing" {
    picks 10
    run "$MENU" reminder
    [ "$status" -eq 0 ]
    [ -z "$(calls uwsm-app)" ]
}

@test "unknown submenu fails" {
    run "$MENU" nope
    [ "$status" -ne 0 ]
}
