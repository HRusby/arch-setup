load ../../tests/helpers

# Disks in every test:
#   nvme0n1  root disk: p1 = this system's ESP (mounted at /boot), p2 = LUKS -> /dev/mapper/root
#   sda      other disk: sda1 = vfat (Windows ESP when the fixture says so), sda2 = ntfs
#   sdb      other disk: sdb1 = vfat data stick
# Fake mount "mounts" a partition by copying $FAKE_DIR/esp/<name>/ into the
# mount point; fake umount empties it again. Nothing real is mounted.

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
    cat > "$FAKE_DIR/lsblk-pairs" <<EOF
NAME="/dev/nvme0n1" TYPE="disk" FSTYPE="" PARTUUID="" PKNAME="" MOUNTPOINT=""
NAME="/dev/nvme0n1p1" TYPE="part" FSTYPE="vfat" PARTUUID="11111111-1111-1111-1111-111111111111" PKNAME="/dev/nvme0n1" MOUNTPOINT="$FAKE_DIR/esp/nvme0n1p1"
NAME="/dev/nvme0n1p2" TYPE="part" FSTYPE="crypto_LUKS" PARTUUID="22222222-2222-2222-2222-222222222222" PKNAME="/dev/nvme0n1" MOUNTPOINT=""
NAME="/dev/mapper/root" TYPE="crypt" FSTYPE="btrfs" PARTUUID="" PKNAME="/dev/nvme0n1p2" MOUNTPOINT="/"
NAME="/dev/sda" TYPE="disk" FSTYPE="" PARTUUID="" PKNAME="" MOUNTPOINT=""
NAME="/dev/sda1" TYPE="part" FSTYPE="vfat" PARTUUID="49c516e8-a6d5-4232-9da6-b5506efcb2dc" PKNAME="/dev/sda" MOUNTPOINT=""
NAME="/dev/sda2" TYPE="part" FSTYPE="ntfs" PARTUUID="33333333-3333-3333-3333-333333333333" PKNAME="/dev/sda" MOUNTPOINT=""
NAME="/dev/sdb" TYPE="disk" FSTYPE="" PARTUUID="" PKNAME="" MOUNTPOINT=""
NAME="/dev/sdb1" TYPE="part" FSTYPE="vfat" PARTUUID="44444444-4444-4444-4444-444444444444" PKNAME="/dev/sdb" MOUNTPOINT=""
EOF
    mkdir -p "$FAKE_DIR/esp/nvme0n1p1/EFI/BOOT" "$FAKE_DIR/esp/sdb1/photos"

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
        [[ $line == "mount -o ro -t vfat "* ]] || { echo "not read-only: $line"; return 1; }
        [[ $line != *nvme0n1* ]] || { echo "root disk mounted: $line"; return 1; }
    done < <(calls mount)
    # Only vfat partitions: never the ntfs one.
    [ "$(calls mount | sed 's/ [^ ]*$//')" = "mount -o ro -t vfat /dev/sda1
mount -o ro -t vfat /dev/sdb1" ]
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
    # Found on the first candidate, so the second is never mounted.
    [ -z "$(calls mount | grep sdb1)" ]
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
    sed -i "s|PARTUUID=\"49c516e8-a6d5-4232-9da6-b5506efcb2dc\" PKNAME=\"/dev/sda\" MOUNTPOINT=\"\"|PARTUUID=\"49c516e8-a6d5-4232-9da6-b5506efcb2dc\" PKNAME=\"/dev/sda\" MOUNTPOINT=\"$FAKE_DIR/esp/sda1\"|" "$FAKE_DIR/lsblk-pairs"
    run "$ENTRY"
    [ "$status" -eq 0 ]
    [ -z "$(calls mount)" ]
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
