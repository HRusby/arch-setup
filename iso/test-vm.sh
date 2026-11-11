#!/usr/bin/env bash
# Boot the installer ISO in QEMU for the end-to-end check (docs/vm-checklist.md).
# Usage: iso/test-vm.sh [--iso PATH] [--recreate]
#        iso/test-vm.sh --check-disk2
#
# vm/disk1.qcow2   40G install target, empty.
# vm/disk2.img     1G stand-in for the Windows disk: GPT, one vfat ESP holding a
#                  dummy EFI/Microsoft/Boot/bootmgfw.efi. Built without root
#                  (sfdisk + mkfs.fat + mtools on the image file); its sha256 is
#                  recorded in vm/disk2.sha256. The installer must never write to
#                  it: --check-disk2 re-hashes it and fails if it changed.
# Existing disks are reused; --recreate wipes vm/ first. The default ISO is the
# newest iso/out/*.iso. OVMF_CODE / OVMF_VARS override the firmware paths.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
vm=$(dirname "$here")/vm
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
disk1=$vm/disk1.qcow2
disk2=$vm/disk2.img
hashfile=$vm/disk2.sha256
vars_copy=$vm/OVMF_VARS.4m.fd
esp_offset=1048576  # first partition starts at sector 2048

die() {
    echo "test-vm: $*" >&2
    exit 1
}

need() {
    local c
    for c in "$@"; do
        command -v "$c" > /dev/null || die "$c not found; install the package that provides it (qemu-img: qemu-img, sfdisk: util-linux, mkfs.fat: dosfstools, mmd/mcopy: mtools)"
    done
}

hash_of() { sha256sum "$1" | cut -d' ' -f1; }

check_disk2() {
    [[ -f $hashfile ]] || die "no recorded hash ($hashfile); run iso/test-vm.sh first"
    [[ -f $disk2 ]] || die "$disk2 is missing"
    local want got
    want=$(cut -d' ' -f1 "$hashfile")
    got=$(hash_of "$disk2")
    if [[ $want != "$got" ]]; then
        echo "test-vm: disk2 CHANGED: the installer wrote to the Windows disk" >&2
        echo "  recorded $want" >&2
        echo "  now      $got" >&2
        exit 1
    fi
    echo "disk2 unchanged ($got)"
}

make_disk2() {
    need truncate sfdisk mkfs.fat mmd mcopy
    local loader=$vm/bootmgfw.efi.tmp mkfs_out
    echo "dummy Windows boot manager" > "$loader"

    truncate -s 1G "$disk2"
    # GPT, one EFI System Partition (type U) from sector 2048, leaving room for the backup table.
    sfdisk "$disk2" > /dev/null <<'PART'
label: gpt
start=2048, size=2093056, type=U
PART
    # --offset is in sectors, the size argument in KiB (1022 MiB partition). mkfs.fat
    # warns about a "block count mismatch" (the file runs past the partition); the
    # output is shown only on failure.
    mkfs_out=$(mkfs.fat -F 32 -n WINESP --offset 2048 "$disk2" 1046528 2>&1) || die "mkfs.fat failed: $mkfs_out"
    mmd -i "$disk2@@$esp_offset" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot
    mcopy -i "$disk2@@$esp_offset" "$loader" ::/EFI/Microsoft/Boot/bootmgfw.efi
    rm -f "$loader"
    hash_of "$disk2" > "$hashfile"
}

iso=
recreate=0
check=0
while (( $# )); do
    case $1 in
        --iso) [[ $# -ge 2 ]] || die "--iso needs a path"; iso=$2; shift 2 ;;
        --recreate) recreate=1; shift ;;
        --check-disk2) check=1; shift ;;
        *) die "unknown option: $1 (usage: test-vm.sh [--iso PATH] [--recreate] | --check-disk2)" ;;
    esac
done

if (( check )); then
    check_disk2
    exit 0
fi

if [[ -z $iso ]]; then
    shopt -s nullglob
    isos=("$here"/out/*.iso)
    shopt -u nullglob
    (( ${#isos[@]} )) || die "no ISO in $here/out; build one with iso/build.sh or pass --iso PATH"
    iso=${isos[0]}
    for f in "${isos[@]}"; do [[ $f -nt $iso ]] && iso=$f; done
fi
[[ -f $iso ]] || die "ISO not found: $iso"
[[ -f $ovmf_code ]] || die "OVMF firmware not found: $ovmf_code (install edk2-ovmf)"
[[ -f $ovmf_vars ]] || die "OVMF vars template not found: $ovmf_vars (install edk2-ovmf)"
need qemu-system-x86_64

(( recreate )) && rm -rf "$vm"
mkdir -p "$vm"

if [[ ! -e $disk1 ]]; then
    need qemu-img
    qemu-img create -f qcow2 "$disk1" 40G > /dev/null
fi
if [[ -e $disk2 ]]; then
    [[ -f $hashfile ]] || die "$disk2 exists but $hashfile does not; use --recreate"
else
    make_disk2
fi
[[ -e $vars_copy ]] || cp "$ovmf_vars" "$vars_copy"

exec qemu-system-x86_64 \
    -enable-kvm -machine q35 -cpu host -smp 4 -m 4G \
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
    -drive "if=pflash,format=raw,file=$vars_copy" \
    -device virtio-vga-gl -display gtk,gl=on \
    -nic user,model=virtio-net-pci \
    -drive "if=virtio,file=$disk1,format=qcow2" \
    -drive "if=virtio,file=$disk2,format=raw" \
    -cdrom "$iso"
