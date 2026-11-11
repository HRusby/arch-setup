setup() {
    load fuzzel_helpers
    fuzzel_sandbox
    NM_MENU="$REPO_ROOT/fuzzel/.local/bin/nm-menu"
    # Fake nmcli: one connected WPA network, one known, one open, one new secured.
    fake nmcli <<'FAKE'
case "$*" in
    "-t -f IN-USE,SSID,SECURITY,SIGNAL dev wifi list")
        printf '%s\n' '*:Home:WPA2:80' ' :Cafe:WPA2:60' ' :Library:--:50' ' :Neighbour\:5G:WPA3:40' ;;
    "--ask device wifi connect"*) cat > "$FAKE_DIR/nmcli.stdin"; exit 0 ;;
    "-t -f NAME connection show") printf '%s\n' Home Cafe 'Wired connection 1' ;;
    "-t -f TYPE,STATE,DEVICE device status") printf '%s\n' 'ethernet:connected:enp3s0' 'wifi:connected:wlan0' ;;
esac
exit 0
FAKE
}

@test "connected network marked" {
    run "$NM_MENU"
    [ "$status" -eq 0 ]
    shown 1 | grep -q '^\* Home  WPA2 80%$'
    ! shown 1 | grep -q '^\* Cafe'
    shown 1 | grep -q '^  Cafe  WPA2 60%$'
}

@test "wired status and actions are listed" {
    run "$NM_MENU"
    shown 1 | grep -q 'Wired: connected (enp3s0)'
    shown 1 | grep -qx 'Rescan'
    shown 1 | grep -qx 'Disconnect'
}

@test "known network connects without password prompt" {
    picks "  Cafe  WPA2 60%"
    run "$NM_MENU"
    [ "$status" -eq 0 ]
    [ "$(calls nmcli | tail -n1)" = "nmcli connection up id Cafe" ]
    [ "$(calls fuzzel | grep -c -- --password)" -eq 0 ]
}

@test "open new network connects without password prompt" {
    picks "  Library  open 50%"
    run "$NM_MENU"
    [ "$(calls nmcli | tail -n1)" = "nmcli device wifi connect Library" ]
}

@test "secured new network prompts for password" {
    picks "  Neighbour:5G  WPA3 40%" "hunter2"
    run "$NM_MENU"
    [ "$status" -eq 0 ]
    [ -n "$(calls fuzzel | grep -- '--password')" ]
    [ "$(calls nmcli | tail -n1)" = "nmcli --ask device wifi connect Neighbour:5G" ]
    [ "$(cat "$FAKE_DIR/nmcli.stdin")" = hunter2 ]
    ! grep -q hunter2 "$CALLS"
}

@test "escape at the password prompt connects nothing" {
    picks "  Neighbour:5G  WPA3 40%"
    run "$NM_MENU"
    [ "$status" -eq 0 ]
    [ -z "$(calls nmcli | grep 'device wifi connect')" ]
}

@test "Disconnect drops the wifi device" {
    picks Disconnect
    run "$NM_MENU"
    [ "$(calls nmcli | tail -n1)" = "nmcli device disconnect wlan0" ]
}

@test "Rescan rescans then lists again" {
    picks Rescan
    run "$NM_MENU"
    [ "$(calls nmcli | grep rescan)" = "nmcli device wifi rescan" ]
    [ "$(calls fuzzel | wc -l)" -eq 2 ]
}

@test "escape exits 0 and runs nothing" {
    run "$NM_MENU"
    [ "$status" -eq 0 ]
    [ -z "$(calls nmcli | grep -e 'device wifi' -e disconnect)" ]
}
