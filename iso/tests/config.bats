load ../../tests/helpers

# The saved archinstall config (archinstall 4.5 schema), checked with jq.

setup() {
    CONFIG="$REPO_ROOT/iso/profile/airootfs/root/archinstall/user_configuration.json"
    GUIDE="$REPO_ROOT/iso/INSTALL.md"
}

# value <jq filter> — one value from the config, raw.
value() {
    jq -r "$1" "$CONFIG"
}

@test "is valid JSON" {
    jq -e . "$CONFIG" > /dev/null
}

@test "has no disk device" {
    [ "$(jq '[paths | select(.[-1] == "device")] | length' "$CONFIG")" -eq 0 ]
    [ "$(value 'has("disk_config")')" = false ]
    run grep -c '/dev/' "$CONFIG"
    [ "$output" = 0 ]
}

@test "has no credentials" {
    hits=$(jq -r '[paths | .[-1] | strings
        | select(test("pass|users|auth|creds|enc_password|encryption"; "i"))] | join(",")' "$CONFIG")
    [ -z "$hits" ] || { echo "credential keys: $hits"; false; }
}

@test "bootloader is Limine" {
    [ "$(value .bootloader_config.bootloader)" = Limine ]
    [ "$(value .bootloader_config.uki)" = false ]
}

@test "btrfs subvolumes match spec" {
    # archinstall can't hold a btrfs layout without a device, so the layout is
    # picked in the menu (its default btrfs subvolumes) as INSTALL.md says.
    for line in '`@` → `/`' '`@home` → `/home`' '`@log` → `/var/log`' '`@pkg` → `/var/cache/pacman/pkg`'; do
        grep -qF "$line" "$GUIDE" || { echo "INSTALL.md lacks: $line"; false; }
    done
    grep -q 'btrfs' "$GUIDE"
    grep -q 'LUKS' "$GUIDE"
}

@test "locale, keyboard and timezone" {
    [ "$(value .locale_config.sys_lang)" = en_US.UTF-8 ]
    [ "$(value .locale_config.sys_enc)" = UTF-8 ]
    [ "$(value .locale_config.kb_layout)" = uk ]
    [ "$(value .timezone)" = Europe/London ]
}

@test "kernel, network, audio, profile and swap" {
    [ "$(value '.kernels | join(",")')" = linux ]
    [ "$(value .network_config.type)" = nm ]
    [ "$(value .app_config.audio_config.audio)" = pipewire ]
    [ "$(value .profile_config.profile.main)" = Minimal ]
    [ "$(value .swap.enabled)" = true ]
}

@test "installs git for the bootstrap clone" {
    [ "$(value '.packages | index("git") != null')" = true ]
}
