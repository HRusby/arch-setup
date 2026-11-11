load ../../tests/helpers

setup() {
    sandbox
    CAPTURE="$REPO_ROOT/capture/.local/bin/capture"
    # Only the fakes and the basic tools below are on PATH, so the real
    # grim/slurp/satty/gpu-screen-recorder/pkill/wl-copy can never run.
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed head tail chmod rm date mkdir tr cut sleep; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    export CLIP="$FAKE_DIR/clipboard"
    fake grimblast < /dev/null
    fake satty < /dev/null
    fake notify-send < /dev/null
    fake pkill < /dev/null
    fake gpu-screen-recorder < /dev/null
    fake hyprctl <<< 'echo "[{\"name\":\"DP-1\",\"focused\":false},{\"name\":\"HDMI-A-1\",\"focused\":true}]"'
    fake jq <<< 'echo HDMI-A-1'
    # Real slurp prints "X,Y WxH" by default and honours -f.
    fake slurp <<< '[[ $* == *-f* ]] && echo 300x200+10+20 || echo "10,20 300x200"'
    fake grim < /dev/null
    fake tesseract <<< 'echo "hello from the screen"'
    fake wl-copy <<< 'cat > "$CLIP"'
    fake hyprpicker < /dev/null
    export CAPTURE_WAIT_STEP=0 CAPTURE_START_TRIES=3 CAPTURE_STOP_TRIES=3
    # The recorder counts as running once the fake recorder has been launched.
    fake pgrep --no-log <<< '[[ $* == *gpu-screen-recorder* ]] && grep -q "^gpu-screen-recorder " "$CALLS"'
}

# recorder_running [path] — pgrep sees a recorder (-af prints a cmdline).
recorder_running() {
    fake pgrep --no-log <<< "[[ \$1 == -af ]] && echo '4242 gpu-screen-recorder -w screen -o ${1:-/v/x.mp4}'; exit 0"
}

@test "region screenshot calls grimblast area" {
    run "$CAPTURE" screenshot region
    [ "$status" -eq 0 ]
    [ "$(calls grimblast)" = "grimblast save area -" ]
}

@test "window and screen map to active and output" {
    "$CAPTURE" screenshot window
    "$CAPTURE" screenshot screen
    [ "$(calls grimblast | sed -n 1p)" = "grimblast save active -" ]
    [ "$(calls grimblast | sed -n 2p)" = "grimblast save output -" ]
}

@test "screenshot annotates with satty and the generated config" {
    mkdir -p "$HOME/.config/theme/generated"
    : > "$HOME/.config/theme/generated/satty.toml"
    run "$CAPTURE" screenshot region
    [ "$status" -eq 0 ]
    line=$(calls satty)
    [[ $line == *"--config $HOME/.config/theme/generated/satty.toml"* ]]
    [[ $line == *"--filename -"* ]]
    [[ $line == *"--output-filename $HOME/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png"* ]]
    [[ $line == *"--copy-command wl-copy"* ]]
    [[ $line == *"--early-exit"* ]]
    [ -d "$HOME/Pictures/Screenshots" ]
}

@test "screenshot works without a generated satty config" {
    run "$CAPTURE" screenshot screen
    [ "$status" -eq 0 ]
    [[ $(calls satty) != *"--config"* ]]
}

@test "cancelled selection exits 0 silently" {
    fake grimblast <<< 'exit 1'
    run "$CAPTURE" screenshot region
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$(calls notify-send)" ]
}

@test "satty failure is reported" {
    fake satty <<< 'exit 3'
    run "$CAPTURE" screenshot region
    [ "$status" -eq 3 ]
}

@test "record start uses slurp region" {
    run "$CAPTURE" record start
    [ "$status" -eq 0 ]
    [ "$(calls slurp)" = "slurp -f %wx%h+%x+%y" ]
    line=$(calls gpu-screen-recorder)
    [[ $line == "gpu-screen-recorder -w region -region 300x200+10+20 "* ]]
    [[ $line == *" -f 60 "* ]]
    [[ $line == *" -a default_output "* ]]
    [[ $line == *" -o $HOME/Videos/Recordings/"*.mp4 ]]
    [ -d "$HOME/Videos/Recordings" ]
}

@test "Escape in slurp records the focused output" {
    fake slurp <<< 'exit 1'
    run "$CAPTURE" record start
    [ "$status" -eq 0 ]
    [[ $(calls gpu-screen-recorder) == "gpu-screen-recorder -w HDMI-A-1 "* ]]
}

@test "Escape with no monitor info falls back to screen" {
    fake slurp <<< 'exit 1'
    fake jq <<< 'exit 0'
    "$CAPTURE" record start
    [[ $(calls gpu-screen-recorder) == "gpu-screen-recorder -w screen "* ]]
}

@test "record start does nothing when already recording" {
    recorder_running
    run "$CAPTURE" record start
    [ "$status" -eq 0 ]
    [ -z "$(calls gpu-screen-recorder)" ]
}

@test "record status follows the process not a file" {
    run "$CAPTURE" record start
    [ "$status" -eq 0 ]
    fake pgrep --no-log <<< 'exit 1'
    run "$CAPTURE" record status
    [ "$output" = off ]
    recorder_running
    run "$CAPTURE" record status
    [ "$output" = on ]
    # nothing but the recordings themselves may be written as state
    [ -z "$(ls -A "$HOME/.local/state" "$HOME/.cache" 2> /dev/null)" ]
}

@test "record stop interrupts the recorder and notifies the file" {
    recorder_running /v/clip.mp4
    run "$CAPTURE" record stop
    [ "$status" -eq 0 ]
    [[ $(calls pkill) == *"pkill -SIGINT -f "*gpu-screen-recorder* ]]
    [[ $(calls notify-send) == *"/v/clip.mp4"* ]]
}

# running_for <n> — plain pgrep -f succeeds for the first n calls, then fails.
running_for() {
    echo 0 > "$FAKE_DIR/n"
    fake pgrep --no-log <<< "[[ \$1 == -af ]] && { echo '4242 gpu-screen-recorder -w screen -o /v/clip.mp4'; exit 0; }
n=\$(( \$(cat $FAKE_DIR/n) + 1 )); echo \$n > $FAKE_DIR/n; ((n <= $1))"
}

@test "record stop waits for the recorder to exit before signalling" {
    running_for 3
    run "$CAPTURE" record stop
    [ "$status" -eq 0 ]
    [[ $(calls notify-send) == *"Recording saved /v/clip.mp4"* ]]
    [ "$(calls pkill | tail -n1)" = "pkill -RTMIN+8 waybar" ]
    [ "$(cat "$FAKE_DIR/n")" -ge 3 ]
}

@test "record stop that times out says it is still finalising and signals" {
    recorder_running /v/clip.mp4
    run "$CAPTURE" record stop
    [ "$status" -eq 0 ]
    [[ $(calls notify-send) == *"still finalising"* ]]
    [[ $(calls notify-send) != *"saved"* ]]
    [ "$(calls pkill | tail -n1)" = "pkill -RTMIN+8 waybar" ]
}

@test "record start fails loudly when the recorder never appears" {
    fake pgrep --no-log <<< 'exit 1'
    run "$CAPTURE" record start
    [ "$status" -eq 1 ]
    [[ $(calls notify-send) == *"Recording failed to start"* ]]
    [ -z "$(calls pkill)" ]
}

@test "record start signals waybar only after the recorder is up" {
    echo 0 > "$FAKE_DIR/n"
    fake pgrep --no-log <<< "n=\$(( \$(cat $FAKE_DIR/n) + 1 )); echo \$n > $FAKE_DIR/n; ((n >= 3))"
    run "$CAPTURE" record start
    [ "$status" -eq 0 ]
    [ "$(calls pkill)" = "pkill -RTMIN+8 waybar" ]
    [ -z "$(calls notify-send)" ]
}

@test "record stop when idle does nothing" {
    run "$CAPTURE" record stop
    [ "$status" -eq 0 ]
    [ -z "$(calls pkill)" ]
}

@test "toggle stops when running" {
    recorder_running
    run "$CAPTURE" record toggle
    [ "$status" -eq 0 ]
    [ -n "$(calls pkill | grep -- '-SIGINT')" ]
    [ -z "$(calls gpu-screen-recorder)" ]
}

@test "toggle starts when idle" {
    run "$CAPTURE" record toggle
    [ "$status" -eq 0 ]
    [ -n "$(calls gpu-screen-recorder)" ]
}

@test "every record change signals waybar" {
    "$CAPTURE" record start
    [ "$(calls pkill | grep -c -- '-RTMIN+8 waybar')" -eq 1 ]
    recorder_running
    "$CAPTURE" record stop
    [ "$(calls pkill | grep -c -- '-RTMIN+8 waybar')" -eq 2 ]
}

@test "ocr pipes to wl-copy" {
    run "$CAPTURE" ocr
    [ "$status" -eq 0 ]
    [ "$(calls grim)" = "grim -g 10,20 300x200 -" ]
    [ "$(calls tesseract)" = "tesseract - - -l eng" ]
    [ "$(cat "$CLIP")" = "hello from the screen" ]
    [[ $(calls notify-send) == *"hello from the screen"* ]]
}

@test "ocr notifies only the first 60 characters" {
    fake tesseract <<< 'printf "%s\n" "0123456789012345678901234567890123456789012345678901234567890123456789"'
    "$CAPTURE" ocr
    [[ $(calls notify-send) == *"012345678901234567890123456789012345678901234567890123456789"* ]]
    [[ $(calls notify-send) != *"0123456789012345678901234567890123456789012345678901234567890"* ]]
}

@test "ocr cancelled selection exits 0 silently" {
    fake slurp <<< 'exit 1'
    run "$CAPTURE" ocr
    [ "$status" -eq 0 ]
    [ -z "$(calls grim)" ]
    [ -z "$(calls notify-send)" ]
}

@test "ocr with no text copies nothing" {
    fake tesseract <<< 'echo ""'
    run "$CAPTURE" ocr
    [ "$status" -eq 0 ]
    [ ! -e "$CLIP" ]
}

@test "colour runs hyprpicker with autocopy" {
    run "$CAPTURE" colour
    [ "$status" -eq 0 ]
    [ "$(calls hyprpicker)" = "hyprpicker -a" ]
}

@test "colour toggles hyprpicker off when running" {
    fake pgrep --no-log <<< '[[ $* == "-x hyprpicker" ]]'
    run "$CAPTURE" colour
    [ "$status" -eq 0 ]
    [ "$(calls pkill)" = "pkill hyprpicker" ]
    [ -z "$(calls hyprpicker)" ]
}

@test "unknown subcommand exits 2" {
    run "$CAPTURE" frobnicate
    [ "$status" -eq 2 ]
    run "$CAPTURE" screenshot nowhere
    [ "$status" -eq 2 ]
    run "$CAPTURE" record explode
    [ "$status" -eq 2 ]
    run "$CAPTURE"
    [ "$status" -eq 2 ]
}
