load ../../tests/helpers

setup() {
    sandbox
    WEATHER="$REPO_ROOT/waybar/.local/bin/waybar-weather"
    # Only the fakes and the basic tools below are on PATH, so the real
    # curl can never run.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat jq chmod sed grep tail rm; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    # wttr.in j1 format, trimmed to the fields the script reads.
    cat > "$FAKE_DIR/j1.json" <<'JSON'
{"current_condition":[{"temp_C":"17","weatherCode":"296","weatherDesc":[{"value":"Light rain"}]}],
 "nearest_area":[{"areaName":[{"value":"Edinburgh"}]}]}
JSON
    fake curl <<< 'cat "$FAKE_DIR/j1.json"'
}

@test "formats fixture JSON" {
    run "$WEATHER" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(jq -r .text <<< "$output")" = $' 17°C' ]
    [ "$(jq -r .tooltip <<< "$output")" = "Edinburgh: Light rain" ]
    [ "$(calls curl)" = "curl -fsS wttr.in/?format=j1" ]
}

@test "unknown weather code falls back to a cloud icon" {
    sed -i 's/296/999/' "$FAKE_DIR/j1.json"
    run "$WEATHER" < /dev/null
    [ "$(jq -r .text <<< "$output")" = $' 17°C' ]
}

@test "prints empty text on network failure" {
    fake curl <<< 'echo "curl: (6) Could not resolve host" >&2; exit 6'
    run "$WEATHER" < /dev/null
    [ "$status" -eq 0 ]
    [ "$output" = '{"text":""}' ]
}

@test "prints empty text on malformed response" {
    fake curl <<< 'echo "<html>rate limited</html>"'
    run "$WEATHER" < /dev/null
    [ "$status" -eq 0 ]
    [ "$output" = '{"text":""}' ]
}
