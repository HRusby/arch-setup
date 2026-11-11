load ../../tests/helpers

# Disks in every test:
#   nvme0n1  root disk: p1 = this system's ESP (mounted at /boot), p2 = LUKS -> /dev/mapper/root
#   sda      internal: sda1 = ESP (Windows when the test says so), sda2 = ntfs
#   sdb      internal: sdb1 = ESP
#   sdc      USB disk (only TRAN=usb, on the disk, marks it): sdc1 = ESP
#   sdd      internal: sdd1 = vfat with the basic data partition type, not an ESP
# Fake mount "mounts" a partition by copying $FAKE_DIR/esp/<name>/ into the
# mount point; fake umount empties it again. Nothing real is mounted.

ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
DATA_TYPE=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
RO_MOUNT="mount -o ro,nosuid,nodev,noexec -t vfat"

setup() {
    sandbox
    ENTRY="$REPO_ROOT/session/.local/bin/limine-windows-entry"
    mkdir -p "$FAKE_DIR/sys" "$FAKE_DIR/esp" "$FAKE_DIR/tmp" "$FAKE_DIR/boot"
    for c in bash env cat grep sed awk mktemp rm rmdir find mkdir cp mv cmp dirname basename chmod; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"
    export TMPDIR="$FAKE_DIR/tmp"
    export LIMINE_CONF="$FAKE_DIR/boot/limine.conf"
    export LIMINE_DEFAULTS="$FAKE_DIR/no-defaults"
    export LIMINE_MUTEX="$FAKE_DIR/no-mutex"
    export LIMINE_WINDOWS_ENTRY_NO_ROOT_CHECK=1

    printf 'timeout: 3\n\n/Arch Linux\n    protocol: linux\n    path: boot():/vmlinuz-linux\n' > "$LIMINE_CONF"

    cat > "$FAKE_DIR/lsblk-deps" <<'EOF'
/dev/mapper/root crypt
/dev/nvme0n1p2 part
/dev/nvme0n1 disk
EOF
    # Like real lsblk, TRAN is only set on whole disks.
    cat > "$FAKE_DIR/lsblk-pairs" <<EOF
NAME="/dev/nvme0n1" TYPE="disk" FSTYPE="" PARTUUID="" PARTTYPE="" PKNAME="" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN="nvme"
NAME="/dev/nvme0n1p1" TYPE="part" FSTYPE="vfat" PARTUUID="11111111-1111-1111-1111-111111111111" PARTTYPE="$ESP_TYPE" PKNAME="/dev/nvme0n1" MOUNTPOINT="$FAKE_DIR/esp/nvme0n1p1" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/nvme0n1p2" TYPE="part" FSTYPE="crypto_LUKS" PARTUUID="22222222-2222-2222-2222-222222222222" PARTTYPE="4f68bce3-e8cd-4db1-96e7-fbcaf984b709" PKNAME="/dev/nvme0n1" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/mapper/root" TYPE="crypt" FSTYPE="btrfs" PARTUUID="" PARTTYPE="" PKNAME="/dev/nvme0n1p2" MOUNTPOINT="/" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/sda" TYPE="disk" FSTYPE="" PARTUUID="" PARTTYPE="" PKNAME="" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN="sata"
NAME="/dev/sda1" TYPE="part" FSTYPE="vfat" PARTUUID="49c516e8-a6d5-4232-9da6-b5506efcb2dc" PARTTYPE="$ESP_TYPE" PKNAME="/dev/sda" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/sda2" TYPE="part" FSTYPE="ntfs" PARTUUID="33333333-3333-3333-3333-333333333333" PARTTYPE="$DATA_TYPE" PKNAME="/dev/sda" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/sdb" TYPE="disk" FSTYPE="" PARTUUID="" PARTTYPE="" PKNAME="" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN="sata"
NAME="/dev/sdb1" TYPE="part" FSTYPE="vfat" PARTUUID="44444444-4444-4444-4444-444444444444" PARTTYPE="$ESP_TYPE" PKNAME="/dev/sdb" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/sdc" TYPE="disk" FSTYPE="" PARTUUID="" PARTTYPE="" PKNAME="" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN="usb"
NAME="/dev/sdc1" TYPE="part" FSTYPE="vfat" PARTUUID="55555555-5555-5555-5555-555555555555" PARTTYPE="$ESP_TYPE" PKNAME="/dev/sdc" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
NAME="/dev/sdd" TYPE="disk" FSTYPE="" PARTUUID="" PARTTYPE="" PKNAME="" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN="sata"
NAME="/dev/sdd1" TYPE="part" FSTYPE="vfat" PARTUUID="66666666-6666-6666-6666-666666666666" PARTTYPE="$DATA_TYPE" PKNAME="/dev/sdd" MOUNTPOINT="" RM="0" HOTPLUG="0" TRAN=""
EOF
    mkdir -p "$FAKE_DIR/esp/nvme0n1p1/EFI/BOOT" "$FAKE_DIR/esp/sdb1/EFI/BOOT"

    fake findmnt <<< 'echo "${FINDMNT_SOURCE-/dev/mapper/root}"'
    fake lsblk <<'EOF'
for a in "$@"; do [[ $a == -*s* && $a != --* ]] && { cat "$FAKE_DIR/lsblk-deps"; exit 0; }; done
cat "$FAKE_DIR/lsblk-pairs"
EOF
    fake mount <<'EOF'
dev="${*: -2:1}" dir="${*: -1}"
[[ " ${MOUNT_FAIL:-} " == *" $dev "* ]] && exit 32
src="$FAKE_DIR/esp/${dev##*/}"
[[ -d $src ]] && cp -r "$src/." "$dir/"
exit 0
EOF
    fake umount <<< 'find "${*: -1}" -mindepth 1 -delete'
}

# windows_on <partition> — give that partition a Windows Boot Manager.
windows_on() {
    mkdir -p "$FAKE_DIR/esp/$1/EFI/Microsoft/Boot"
    echo efi > "$FAKE_DIR/esp/$1/EFI/Microsoft/Boot/bootmgfw.efi"
}

entry_count() {
    grep -c '^/Windows$' "$LIMINE_CONF" || true
}

@test "mounts other-disk ESPs read-only only" {
    windows_on sdb1
    run "$ENTRY"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ -n "$(calls mount)" ]
    while read -r line; do
        [[ $line == "$RO_MOUNT "* ]] || { echo "not read-only: $line"; return 1; }
        [[ $line != *nvme0n1* ]] || { echo "root disk mounted: $line"; return 1; }
    done < <(calls mount)
    # Only internal ESPs: never the ntfs, USB or non-ESP vfat partitions.
    [ "$(calls mount | sed 's/ [^ ]*$//')" = "$RO_MOUNT /dev/sda1
$RO_MOUNT /dev/sdb1" ]
}

@test "unmounts every partition it mounted and removes the mount point" {
    windows_on sdb1
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ "$(calls mount | grep -c .)" = 2 ]
    [ "$(calls umount | grep -c .)" = 2 ]
    [ -z "$(find "$TMPDIR" -mindepth 1)" ]
}

@test "writes one entry with the found PARTUUID" {
    windows_on sda1
    run "$ENTRY"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(entry_count)" = 1 ]
    grep -qx 'protocol: efi' "$LIMINE_CONF"
    grep -qx 'path: guid(49c516e8-a6d5-4232-9da6-b5506efcb2dc):/EFI/Microsoft/Boot/bootmgfw.efi' "$LIMINE_CONF"
    # The existing config is kept as it was, ahead of the new entry.
    [ "$(sed -n '1,5p' "$LIMINE_CONF")" = "$(printf 'timeout: 3\n\n/Arch Linux\n    protocol: linux\n    path: boot():/vmlinuz-linux')" ]
}

@test "re-run does not duplicate" {
    windows_on sda1
    run "$ENTRY"
    [ "$status" -eq 0 ]
    cp "$LIMINE_CONF" "$FAKE_DIR/after-first"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ "$(entry_count)" = 1 ]
    cmp "$FAKE_DIR/after-first" "$LIMINE_CONF"
}

@test "re-run replaces a stale entry and keeps the entries after it" {
    windows_on sda1
    printf 'timeout: 3\n\n/Windows\nprotocol: efi\npath: guid(00000000-0000-0000-0000-000000000000):/EFI/Microsoft/Boot/bootmgfw.efi\n\n/Other\nprotocol: efi\npath: boot():/EFI/other.efi\n' > "$LIMINE_CONF"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ "$(entry_count)" = 1 ]
    [ -z "$(grep 00000000-0000 "$LIMINE_CONF" || true)" ]
    grep -qx 'path: guid(49c516e8-a6d5-4232-9da6-b5506efcb2dc):/EFI/Microsoft/Boot/bootmgfw.efi' "$LIMINE_CONF"
    grep -qx '/Other' "$LIMINE_CONF"
    grep -qx 'path: boot():/EFI/other.efi' "$LIMINE_CONF"
}

@test "no Windows found changes nothing" {
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    cmp "$FAKE_DIR/before" "$LIMINE_CONF"
    [ -z "$(find "$FAKE_DIR/boot" -mindepth 1 ! -name limine.conf)" ]
}

@test "ignores a Windows loader on the root disk" {
    windows_on nvme0n1p1
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    cmp "$FAKE_DIR/before" "$LIMINE_CONF"
}

@test "reads an already-mounted ESP in place instead of mounting it again" {
    windows_on sda1
    sed -i "s|^\(NAME=\"/dev/sda1\" .*\) MOUNTPOINT=\"\"|\1 MOUNTPOINT=\"$FAKE_DIR/esp/sda1\"|" "$FAKE_DIR/lsblk-pairs"
    grep -q "^NAME=\"/dev/sda1\" .* MOUNTPOINT=\"$FAKE_DIR/esp/sda1\"" "$FAKE_DIR/lsblk-pairs"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount | grep sda1 || true)" ]
    [ "$(entry_count)" = 1 ]
}

@test "skips a partition that fails to mount and carries on" {
    windows_on sdb1
    MOUNT_FAIL=/dev/sda1 run "$ENTRY"
    [ "$status" -eq 0 ]
    [ "$(calls umount | grep -c .)" = 1 ]
    grep -qx 'path: guid(44444444-4444-4444-4444-444444444444):/EFI/Microsoft/Boot/bootmgfw.efi' "$LIMINE_CONF"
}

@test "refuses to scan when the root disk cannot be found" {
    windows_on sda1
    FINDMNT_SOURCE='' run "$ENTRY"
    [ "$status" -ne 0 ]
    [ -z "$(calls mount)" ]
}

@test "finds limine.conf through ESP_PATH in /etc/default/limine" {
    windows_on sda1
    mkdir -p "$FAKE_DIR/efi"
    cp "$LIMINE_CONF" "$FAKE_DIR/efi/limine.conf"
    echo "ESP_PATH=\"$FAKE_DIR/efi\"" > "$FAKE_DIR/defaults"
    LIMINE_CONF='' LIMINE_DEFAULTS="$FAKE_DIR/defaults" run "$ENTRY"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qx '/Windows' "$FAKE_DIR/efi/limine.conf"
}

@test "re-enrolls the config hash only when the config changed" {
    windows_on sda1
    fake limine-enroll-config < /dev/null
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ "$(calls limine-enroll-config)" = "limine-enroll-config " ]
    run "$ENTRY"
    [ "$(calls limine-enroll-config | grep -c .)" = 1 ]
}

@test "skips an ESP on a USB disk" {
    windows_on sdc1
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount | grep sdc || true)" ]
    cmp "$FAKE_DIR/before" "$LIMINE_CONF"
}

@test "skips an ESP on a removable disk" {
    windows_on sdb1
    sed -i 's|^\(NAME="/dev/sdb" .*\) RM="0"|\1 RM="1"|' "$FAKE_DIR/lsblk-pairs"
    grep -q '^NAME="/dev/sdb" .* RM="1"' "$FAKE_DIR/lsblk-pairs"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount | grep sdb || true)" ]
    [ "$(entry_count)" = 0 ]
}

@test "skips an ESP on a hotplug disk" {
    windows_on sdb1
    sed -i 's|^\(NAME="/dev/sdb" .*\) HOTPLUG="0"|\1 HOTPLUG="1"|' "$FAKE_DIR/lsblk-pairs"
    grep -q '^NAME="/dev/sdb" .* HOTPLUG="1"' "$FAKE_DIR/lsblk-pairs"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount | grep sdb || true)" ]
    [ "$(entry_count)" = 0 ]
}

@test "skips a vfat partition that is not an EFI system partition" {
    windows_on sdd1
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount | grep sdd || true)" ]
    cmp "$FAKE_DIR/before" "$LIMINE_CONF"
}

@test "two Windows candidates: writes nothing and lists them" {
    windows_on sda1
    windows_on sdb1
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    run "$ENTRY"
    [ "$status" -ne 0 ]
    cmp "$FAKE_DIR/before" "$LIMINE_CONF"
    [[ $output == *"/dev/sda1  PARTUUID=49c516e8-a6d5-4232-9da6-b5506efcb2dc"* ]]
    [[ $output == *"/dev/sdb1  PARTUUID=44444444-4444-4444-4444-444444444444"* ]]
    [[ $output == *"--partuuid"* ]]
    [ "$(calls mount | grep -c .)" = "$(calls umount | grep -c .)" ]
}

@test "--partuuid picks one of several candidates" {
    windows_on sda1
    windows_on sdb1
    run "$ENTRY" --partuuid 44444444-4444-4444-4444-444444444444
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(entry_count)" = 1 ]
    grep -qx 'path: guid(44444444-4444-4444-4444-444444444444):/EFI/Microsoft/Boot/bootmgfw.efi' "$LIMINE_CONF"
}

@test "--partuuid must name a Windows candidate" {
    windows_on sda1
    windows_on sdc1
    cp "$LIMINE_CONF" "$FAKE_DIR/before"
    for uuid in 44444444-4444-4444-4444-444444444444 55555555-5555-5555-5555-555555555555 11111111-1111-1111-1111-111111111111; do
        run "$ENTRY" --partuuid "$uuid"
        [ "$status" -ne 0 ] || { echo "accepted $uuid"; false; }
        cmp "$FAKE_DIR/before" "$LIMINE_CONF"
    done
}

@test "rejects unknown arguments" {
    run "$ENTRY" --bogus
    [ "$status" -ne 0 ]
    [ -z "$(calls mount)" ]
}

@test "a failing limine-enroll-config is reported, not fatal" {
    windows_on sda1
    fake limine-enroll-config <<< 'exit 1'
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [[ $output == *"limine-enroll-config failed"* ]]
    [ "$(entry_count)" = 1 ]
}
