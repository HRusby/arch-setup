load ../../tests/helpers

# iso/test-vm.sh with every external tool faked. A copy of iso/ lives in the
# sandbox so vm/ and iso/out are the sandbox's, never the repo's. Fakes log to
# $CALLS; fake truncate makes a small file so the disk hash is cheap to check.

setup() {
    sandbox
    mkdir -p "$FAKE_DIR/sys"
    for c in bash env cat grep sed awk rm find mkdir cp chmod dirname touch sort head ls sha256sum cut tr basename cmp; do
        ln -s "$(command -v "$c")" "$FAKE_DIR/sys/$c"
    done
    export PATH="$FAKE_DIR/bin:$FAKE_DIR/sys"

    mkdir -p "$REPO/iso"
    cp "$REPO_ROOT/iso/test-vm.sh" "$REPO/iso/test-vm.sh"
    TESTVM="$REPO/iso/test-vm.sh"
    VM="$REPO/vm"

    export OVMF_CODE="$FAKE_DIR/OVMF_CODE.4m.fd" OVMF_VARS="$FAKE_DIR/OVMF_VARS.4m.fd"
    echo code > "$OVMF_CODE"
    echo vars > "$OVMF_VARS"

    mkdir -p "$REPO/iso/out"
    touch -d '2026-01-01' "$REPO/iso/out/archlinux-old.iso"
    touch -d '2026-06-01' "$REPO/iso/out/archlinux-new.iso"

    fake qemu-system-x86_64 < /dev/null
    fake qemu-img <<'EOF2'
[[ $1 == create ]] && echo qcow > "${@: -2:1}"
EOF2
    fake truncate <<'EOF2'
echo "dummy-disk2" > "${@: -1}"
EOF2
    fake sfdisk < /dev/null
    fake mkfs.fat < /dev/null
    fake mmd < /dev/null
    fake mcopy < /dev/null
}

@test "boots the newest ISO in iso/out by default" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    [[ $(calls qemu-system-x86_64) == *"-cdrom $REPO/iso/out/archlinux-new.iso"* ]]
}

@test "--iso overrides the default ISO" {
    touch "$FAKE_DIR/mine.iso"
    run "$TESTVM" --iso "$FAKE_DIR/mine.iso"
    [ "$status" -eq 0 ]
    [[ $(calls qemu-system-x86_64) == *"-cdrom $FAKE_DIR/mine.iso"* ]]
}

@test "no ISO built: clear error, no disks, no qemu" {
    rm "$REPO"/iso/out/*.iso
    run "$TESTVM"
    [ "$status" -ne 0 ]
    [[ $output == *"no ISO"*"iso/build.sh"* ]]
    [ -z "$(calls qemu-system-x86_64)" ]
    [ ! -e "$VM/disk1.qcow2" ]
}

@test "--iso with a missing file: clear error" {
    run "$TESTVM" --iso "$FAKE_DIR/nope.iso"
    [ "$status" -ne 0 ]
    [[ $output == *"$FAKE_DIR/nope.iso"* ]]
    [ -z "$(calls qemu-system-x86_64)" ]
}

@test "unknown option is rejected before anything runs" {
    run "$TESTVM" --bogus
    [ "$status" -ne 0 ]
    [[ $output == *"--bogus"* ]]
    [ ! -s "$CALLS" ]
}

@test "qemu gets readonly OVMF code pflash and a writable vars copy" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    local c; c=$(calls qemu-system-x86_64)
    [[ $c == *"-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE"* ]]
    [[ $c == *"-drive if=pflash,format=raw,file=$VM/OVMF_VARS.4m.fd"* ]]
    [[ $c != *"file=$OVMF_VARS"* ]]
    cmp "$OVMF_VARS" "$VM/OVMF_VARS.4m.fd"
}

@test "qemu gets both disks, virtio GPU with gtk gl, user networking" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    local c; c=$(calls qemu-system-x86_64)
    [[ $c == *"file=$VM/disk1.qcow2,format=qcow2"* ]]
    [[ $c == *"file=$VM/disk2.img,format=raw"* ]]
    [[ $c == *"-device virtio-vga-gl"* ]]
    [[ $c == *"-display gtk,gl=on"* ]]
    [[ $c == *"-nic user"* ]]
    [[ $c == *"-enable-kvm"* ]]
}

@test "missing OVMF firmware: clear error, no qemu" {
    export OVMF_CODE="$FAKE_DIR/absent.fd"
    run "$TESTVM"
    [ "$status" -ne 0 ]
    [[ $output == *"$FAKE_DIR/absent.fd"* ]]
    [ -z "$(calls qemu-system-x86_64)" ]
}

@test "creates disk1 as a 40G qcow2" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    [[ $(calls qemu-img) == "qemu-img create -f qcow2 $VM/disk1.qcow2 40G" ]]
    [ -e "$VM/disk1.qcow2" ]
}

@test "creates disk2 as 1G with a GPT ESP, vfat, and the dummy Windows loader" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    [[ $(calls truncate) == "truncate -s 1G $VM/disk2.img" ]]
    [[ $(calls sfdisk) == "sfdisk $VM/disk2.img" ]]
    [[ $(calls mkfs.fat) == *"-F 32"*"$VM/disk2.img"* ]]
    [[ $(calls mmd) == *"-i $VM/disk2.img@@1048576"*"::/EFI/Microsoft/Boot"* ]]
    [[ $(calls mcopy) == *"-i $VM/disk2.img@@1048576"*"::/EFI/Microsoft/Boot/bootmgfw.efi"* ]]
}

@test "the partition table is GPT with an EFI System Partition" {
    # the real sfdisk script text goes to stdin; capture it
    fake sfdisk <<'EOF2'
cat > "$FAKE_DIR/sfdisk.stdin"
EOF2
    run "$TESTVM"
    [ "$status" -eq 0 ]
    grep -q '^label: gpt' "$FAKE_DIR/sfdisk.stdin"
    grep -q 'type=U' "$FAKE_DIR/sfdisk.stdin"
    grep -q 'start=2048' "$FAKE_DIR/sfdisk.stdin"
}

@test "records disk2's sha256 after building it" {
    run "$TESTVM"
    [ "$status" -eq 0 ]
    expected=$(sha256sum "$VM/disk2.img" | cut -d' ' -f1)
    [ "$(cut -d' ' -f1 "$VM/disk2.sha256")" = "$expected" ]
}

@test "disk2 is hashed after the dummy loader is copied in" {
    fake mcopy <<'EOF2'
echo loader >> "$REPO/vm/disk2.img"
EOF2
    run "$TESTVM"
    [ "$status" -eq 0 ]
    expected=$(sha256sum "$VM/disk2.img" | cut -d' ' -f1)
    [ "$(cut -d' ' -f1 "$VM/disk2.sha256")" = "$expected" ]
}

@test "existing disks are reused, not recreated" {
    "$TESTVM"
    : > "$CALLS"
    echo marker >> "$VM/disk1.qcow2"
    hash_before=$(cat "$VM/disk2.sha256")
    run "$TESTVM"
    [ "$status" -eq 0 ]
    [ -z "$(calls qemu-img)" ]
    [ -z "$(calls truncate)" ]
    grep -q marker "$VM/disk1.qcow2"
    [ "$(cat "$VM/disk2.sha256")" = "$hash_before" ]
    [ -n "$(calls qemu-system-x86_64)" ]
}

@test "--recreate wipes vm/ and builds fresh disks" {
    "$TESTVM"
    echo marker >> "$VM/disk1.qcow2"
    echo stale > "$VM/leftover"
    : > "$CALLS"
    run "$TESTVM" --recreate
    [ "$status" -eq 0 ]
    [ ! -e "$VM/leftover" ]
    ! grep -q marker "$VM/disk1.qcow2"
    [ -n "$(calls qemu-img)" ]
    [ -n "$(calls truncate)" ]
}

@test "disk2 without a recorded hash is refused" {
    mkdir -p "$VM"
    echo x > "$VM/disk2.img"
    run "$TESTVM"
    [ "$status" -ne 0 ]
    [[ $output == *"disk2.sha256"*"--recreate"* ]]
    [ -z "$(calls qemu-system-x86_64)" ]
}

@test "missing tool for creating disks: names the tool" {
    rm "$FAKE_DIR/bin/qemu-img"
    run "$TESTVM"
    [ "$status" -ne 0 ]
    [[ $output == *"qemu-img"* ]]
    [ -z "$(calls qemu-system-x86_64)" ]
}

@test "--check-disk2 passes when disk2 is unchanged" {
    "$TESTVM"
    : > "$CALLS"
    run "$TESTVM" --check-disk2
    [ "$status" -eq 0 ]
    [[ $output == *"unchanged"* ]]
    [ ! -s "$CALLS" ]
}

@test "--check-disk2 fails clearly when disk2 changed" {
    "$TESTVM"
    echo tampered >> "$VM/disk2.img"
    run "$TESTVM" --check-disk2
    [ "$status" -ne 0 ]
    [[ $output == *"CHANGED"* ]]
    [[ $output == *"disk2"* ]]
}

@test "--check-disk2 without a recorded hash: clear error" {
    run "$TESTVM" --check-disk2
    [ "$status" -ne 0 ]
    [[ $output == *"disk2.sha256"* ]]
}

@test "--check-disk2 with the image gone: clear error" {
    "$TESTVM"
    rm "$VM/disk2.img"
    run "$TESTVM" --check-disk2
    [ "$status" -ne 0 ]
    [[ $output == *"disk2.img"* ]]
}
