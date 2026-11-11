load ../../tests/helpers

# The live ISO's installer, run against a fake target tree:
#   $TARGET        what archinstall mounted at /mnt: etc/passwd with harry
#                  (UID 1000) and the limine.conf archinstall wrote
#   $FAKE_DIR/net  /sys/class/net: eth0 (wired) and wlan0 (wireless)
#   $FAKE_DIR/routes  JSON that fake `ip -j -4 route show default` prints
#   $FAKE_DIR/online  exists = fake ping reaches archlinux.org
#   $FAKE_DIR/mounted exists = fake mountpoint says $TARGET is mounted (an
#                     install from an earlier run); absent by default
# Only fakes and basic tools are on PATH; every test feeds stdin explicitly.

CMDLINE="cryptdevice=PARTUUID=1234:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs"

setup() {
    sandbox
    INSTALL="$REPO_ROOT/iso/profile/airootfs/usr/local/bin/install-arch"
    mkdir -p "$FAKE_DIR/sys" "$FAKE_DIR/tmp"
    for c in bash env cat grep sed awk mktemp rm find mkdir install chmod stat jq touch basename dirname wc cut; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    export TMPDIR="$FAKE_DIR/tmp"
    export TARGET="$FAKE_DIR/mnt"
    export ARCHINSTALL_CONFIG="$FAKE_DIR/user_configuration.json"
    export SYS_CLASS_NET="$FAKE_DIR/net"
    export INSTALL_ARCH_NO_ROOT_CHECK=1

    mkdir -p "$TARGET/etc" "$TARGET/home/harry" "$TARGET/boot/EFI/arch-limine" \
        "$SYS_CLASS_NET/eth0" "$SYS_CLASS_NET/wlan0/wireless"
    printf '%s\n' 'root:x:0:0::/root:/bin/bash' 'harry:x:1000:1000::/home/harry:/bin/bash' > "$TARGET/etc/passwd"
    printf 'timeout: 5\n\n/Arch Linux (linux)\n    protocol: linux\n    cmdline: %s\n' "$CMDLINE" \
        > "$TARGET/boot/EFI/arch-limine/limine.conf"
    echo '{}' > "$ARCHINSTALL_CONFIG"

    wired
    fake ip <<< 'cat "$FAKE_DIR/routes"'
    fake ping <<< '[[ -e "$FAKE_DIR/online" ]]'
    fake iwctl <<< 'touch "$FAKE_DIR/online"'
    fake sleep < /dev/null
    fake archinstall < /dev/null
    fake visudo < /dev/null
    fake reboot < /dev/null
    fake mountpoint <<< '[[ -e "$FAKE_DIR/mounted" ]]'
    # The bootstrap run records what it could see while it ran.
    fake arch-chroot <<'EOF'
if [[ "$*" == *bootstrap.sh* ]]; then
    sudoers="$TARGET/etc/sudoers.d/99-bootstrap"
    [[ -f $sudoers ]] && echo "sudoers $(stat -c %a "$sudoers") $(cat "$sudoers")" >> "$CALLS"
    cmdline_file="$TARGET/var/tmp/install-arch.cmdline"
    [[ -f $cmdline_file ]] && echo "cmdline $(cat "$cmdline_file")" >> "$CALLS"
    exit "${BOOTSTRAP_RC:-0}"
fi
EOF
}

# wired / not_wired — default route via eth0 and online, or no default route and offline.
wired() {
    echo '[{"dst":"default","gateway":"10.0.0.1","dev":"eth0","protocol":"dhcp"}]' > "$FAKE_DIR/routes"
    touch "$FAKE_DIR/online"
}

not_wired() {
    echo '[]' > "$FAKE_DIR/routes"
    rm -f "$FAKE_DIR/online"
}

chroot_calls() {
    calls arch-chroot
}

@test "wired link skips Wi-Fi" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(calls iwctl)" ]
    [ -n "$(calls archinstall)" ]
}

@test "no wired link opens iwctl" {
    not_wired
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls iwctl)" = "iwctl " ]
    [[ "$output" == *"station wlan0 connect"* ]]
    iwctl_line=$(grep -n '^iwctl' "$CALLS" | cut -d: -f1)
    archinstall_line=$(grep -n '^archinstall' "$CALLS" | cut -d: -f1)
    [ "$iwctl_line" -lt "$archinstall_line" ]
}

@test "default route over a wireless interface is not a wired link" {
    not_wired
    echo '[{"dst":"default","gateway":"10.0.0.1","dev":"wlan0"}]' > "$FAKE_DIR/routes"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -n "$(calls iwctl)" ]
}

@test "reopens iwctl until archlinux.org answers" {
    not_wired
    fake iwctl <<< '[[ -e "$FAKE_DIR/tried" ]] && touch "$FAKE_DIR/online"; touch "$FAKE_DIR/tried"'
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls iwctl | wc -l)" -eq 2 ]
}

@test "wired link that never gets online falls back to Wi-Fi" {
    rm -f "$FAKE_DIR/online"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -n "$(calls iwctl)" ]
}

@test "runs archinstall with the saved config, never silently" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls archinstall)" = "archinstall --config $ARCHINSTALL_CONFIG" ]
}

@test "stops when archinstall fails" {
    fake archinstall <<< 'exit 1'
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(chroot_calls)" ]
}

@test "stops when archinstall left no installed system" {
    rm "$TARGET/etc/passwd"
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Exit archinstall"* ]]
    [ -z "$(chroot_calls)" ]
    [ ! -e "$TARGET/etc/sudoers.d/99-bootstrap" ]
}

@test "stops when the installed system has no UID 1000 user" {
    printf '%s\n' 'root:x:0:0::/root:/bin/bash' 'other:x:1001:1001::/home/other:/bin/bash' > "$TARGET/etc/passwd"
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(chroot_calls)" ]
}

@test "clones repo over https without credentials" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(chroot_calls | grep ' git clone ')" = \
        "arch-chroot $TARGET runuser -u harry -- env GIT_TERMINAL_PROMPT=0 git clone https://github.com/HRusby/arch-setup.git /home/harry/arch-setup" ]
}

@test "existing clone reused" {
    mkdir -p "$TARGET/home/harry/arch-setup/.git"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(chroot_calls | grep ' git clone ')" ]
    [ "$(chroot_calls | grep ' pull ')" = \
        "arch-chroot $TARGET runuser -u harry -- env GIT_TERMINAL_PROMPT=0 git -C /home/harry/arch-setup pull --ff-only" ]
    [ -n "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "existing clone kept when git pull fails" {
    mkdir -p "$TARGET/home/harry/arch-setup/.git"
    fake arch-chroot <<< '[[ "$*" == *" pull "* ]] && exit 1; exit 0'
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"git pull failed"* ]]
    [ -n "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "refuses to clone into a non-empty directory that is not a clone" {
    mkdir -p "$TARGET/home/harry/arch-setup"
    touch "$TARGET/home/harry/arch-setup/stray"
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(chroot_calls | grep 'git ')" ]
    [ -z "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "resume detected: existing install skips archinstall" {
    touch "$FAKE_DIR/mounted"
    run "$INSTALL" <<< "y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Existing install found on $TARGET"* ]]
    [ -z "$(calls archinstall)" ]
    [ -n "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "resume detected: no answer still skips archinstall" {
    touch "$FAKE_DIR/mounted"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(calls archinstall)" ]
    [ -n "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "resume declined: runs archinstall" {
    touch "$FAKE_DIR/mounted"
    run "$INSTALL" <<< "n"
    [ "$status" -eq 0 ]
    [ -n "$(calls archinstall)" ]
}

@test "mounted target without a UID 1000 user is not offered as a resume" {
    touch "$FAKE_DIR/mounted"
    printf '%s\n' 'root:x:0:0::/root:/bin/bash' > "$TARGET/etc/passwd"
    run "$INSTALL" < /dev/null
    [ -n "$(calls archinstall)" ]
}

@test "--resume never runs archinstall" {
    touch "$FAKE_DIR/mounted"
    run "$INSTALL" --resume < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(calls archinstall)" ]
    [ -n "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "--resume with no install: clear error, no archinstall" {
    run "$INSTALL" --resume < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"no existing install"* ]]
    [ -z "$(calls archinstall)" ]
    [ -z "$(chroot_calls)" ]
}

@test "rejects unknown options before doing anything" {
    run "$INSTALL" --bogus < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(calls ping)" ]
    [ -z "$(calls archinstall)" ]
}

@test "bootstrap failure points at install-arch --resume" {
    export BOOTSTRAP_RC=1
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"install-arch --resume"* ]]
}

@test ".zlogin failure message names --resume" {
    grep -q 'install-arch --resume' "$REPO_ROOT/iso/profile/airootfs/root/.zlogin"
}

@test "runs bootstrap as the user with the base and desktop lists" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(chroot_calls | grep bootstrap.sh)" = \
        "arch-chroot $TARGET runuser -u harry -- env PROC_CMDLINE=/var/tmp/install-arch.cmdline /home/harry/arch-setup/bootstrap.sh --lists base,desktop" ]
    clone_line=$(grep -n 'git clone' "$CALLS" | cut -d: -f1)
    bootstrap_line=$(grep -n 'bootstrap.sh' "$CALLS" | cut -d: -f1)
    [ "$clone_line" -lt "$bootstrap_line" ]
}

@test "sudoers drop-in grants the user NOPASSWD only while bootstrap runs" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls sudoers)" = "sudoers 440 harry ALL=(ALL:ALL) NOPASSWD: ALL" ]
    [ ! -e "$TARGET/etc/sudoers.d/99-bootstrap" ]
}

@test "sudoers drop-in removed even when bootstrap fails" {
    export BOOTSTRAP_RC=1
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -n "$(calls sudoers)" ]
    [ ! -e "$TARGET/etc/sudoers.d/99-bootstrap" ]
    [[ "$output" == *"bootstrap failed"* ]]
    [[ "$output" == *"(or: arch-chroot $TARGET runuser -u harry -- env PROC_CMDLINE=/var/tmp/install-arch.cmdline /home/harry/arch-setup/bootstrap.sh --lists base,desktop"* ]]
    [ -f "$TARGET/var/tmp/install-arch.cmdline" ]
    [ -z "$(calls reboot)" ]
}

@test "sudoers drop-in is checked with visudo before it is installed" {
    fake visudo <<< 'exit 1'
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [[ "$(calls visudo)" == "visudo -cf "* ]]
    [ ! -e "$TARGET/etc/sudoers.d/99-bootstrap" ]
    [ -z "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "hands bootstrap the installed system's kernel cmdline, not the live ISO's" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(calls cmdline)" = "cmdline $CMDLINE" ]
    [ ! -e "$TARGET/var/tmp/install-arch.cmdline" ]
}

@test "stops before bootstrap when archinstall wrote no Limine cmdline" {
    rm "$TARGET/boot/EFI/arch-limine/limine.conf"
    run "$INSTALL" < /dev/null
    [ "$status" -ne 0 ]
    [ -z "$(chroot_calls | grep bootstrap.sh)" ]
}

@test "no cmdline handoff when the installed system already pins one" {
    rm "$TARGET/boot/EFI/arch-limine/limine.conf"
    mkdir -p "$TARGET/etc/kernel"
    echo "$CMDLINE" > "$TARGET/etc/kernel/cmdline"
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ "$(chroot_calls | grep bootstrap.sh)" = \
        "arch-chroot $TARGET runuser -u harry -- /home/harry/arch-setup/bootstrap.sh --lists base,desktop" ]
}

@test "reboots when the user says yes" {
    run "$INSTALL" <<< "y"
    [ "$status" -eq 0 ]
    [ "$(calls reboot)" = "reboot " ]
}

@test "does not reboot without an answer" {
    run "$INSTALL" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$(calls reboot)" ]
}
