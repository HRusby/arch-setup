# Bare Arch setup (leaving Omarchy): design

Date: 2026-11-08
Status: approved 2026-11-08

## Intent

Harry is moving from Omarchy to a plain Arch Linux + Hyprland setup that he owns
end to end. He likes what Omarchy *does* (one theme across everything, a tidy bar,
notifications, dmenu-style app and system pickers, keybind display, screenshot and
recording integration, a good Hyprland setup) but not how it is *delivered*:

- updates rewrite config and keybindings he had already set up correctly;
- it installs packages he doesn't want;
- he can't update one component on its own, because Omarchy's mirrors have moved on.

The replacement should give the same day-to-day behaviour from standard Arch packages,
with all configuration living in a new repo, `~/Work/arch-setup` (the old `~/Work/dotfiles` repo is left as it is), installable from a small ISO onto a
fresh machine or after a bricked install.

## Goals

1. **Rebuildable.** Boot a custom ISO, answer a few prompts, and end up at a working
   Hyprland desktop: network up, user account created, bar, menus, theme, keybinds.
   It does not install every app, only the base and desktop modules.
2. **Modular, with few moving parts.** Prefer one tool that covers several features
   over one tool per feature. Each feature is one folder in this repo (its config and
   its package list). Adding or dropping a feature is adding or removing one folder.
3. **One palette, one place.** Colours are defined once. No hand-written config file
   contains a colour value.
4. **Stable under updates.** Only official Arch repos plus a few AUR packages. Nothing
   rewrites Harry's config on update.

## Non-goals

- Reproducing every Omarchy feature. Dropped on purpose: font switcher, battery and
  power-profile widgets, web apps as desktop apps, emoji picker, AI-agent widget,
  dictation, world clocks, speedtest/Tailscale panels.
- Installing all of Harry's applications from the ISO. App modules are opt-in later.
- Supporting machines other than "an x86_64 PC with UEFI". No multi-machine templating.
- An offline installer.

## Anti-goals (would count as failure even if it works)

- Recreating Omarchy: a large opinionated layer that owns config and forces packages.
- Colour values copied into more than one place.
- An ISO that needs rebuilding for ordinary config changes.
- Config that changes itself on update.

## Constraints

- **Current hardware** (reference machine): AMD Radeon RX 6600 (Navi 23, `amdgpu`, no
  Nvidia handling needed), MediaTek MT7922 Wi-Fi, UEFI. Displays: 5120x1440@120
  ultrawide on DP-1 and a 4K TV on HDMI-A-1 (scale 2, to the right). Take the current
  values from `~/.config/hypr/monitors.lua`, including its note about HDMI being the
  only screen.
- **Other disks must never be touched.** This machine has NTFS partitions on `sda` and
  `sdc` (Windows and a shared drive mounted at `/mnt/SharedHDD`). The installer must
  make the user pick the target disk explicitly and must not auto-select or wipe others.
- **Current system layout to keep:** LUKS-encrypted root, btrfs with subvolumes for `/`,
  `/home`, `/var/log`, `/var/cache/pacman/pkg`, vfat `/boot`, zram swap.
- **Locale:** `en_US.UTF-8`, console keymap `uk`, XKB layout `gb`.
- **Hyprland** is 0.56.x with the **Lua** config format (Harry's choice: he wants the
  programmatic config over static `.conf`).
- Stage only touched files when committing; the repo may hold unrelated work in progress.
- Harry prefers test-driven development; scripts in this repo are tested with `bats`
  (pattern from `~/Work/dotfiles/trim/tests/`).

## Decisions

All of these are Harry's choices unless marked *(Claude's call)*.

### Foundation

| Area | Decision |
|---|---|
| Installer / ISO | Thin custom ISO built with `mkarchiso`, carrying an `archinstall` config plus a bootstrap script that clones this repo and runs its setup. Packages and config are fetched at install time, so the ISO rarely needs rebuilding. Wi-Fi setup is **skipped if Ethernet is already connected**. |
| Repo hosting | New repo `~/Work/arch-setup`, pushed to a **public GitHub repo** `HRusby/arch-setup` (push confirmed with Harry first); the installer clones `main` over HTTPS with no login. No secrets in the repo, ever. |
| Reinstall behaviour | The installer **wipes the chosen target disk** (new LUKS container). It does not try to keep `/home`; personal files are restored from backup or the other drives. |
| Migrating this machine | Done by reinstalling from the ISO once it works, after Harry has backed up. No in-place conversion of the Omarchy install. *(Claude's call, follows from the wipe decision.)* |
| Windows | The Limine menu gets a **Windows entry** that chainloads Windows Boot Manager from `sda`'s own ESP. `sda` is only read, never written; nothing relies on the copy currently on `sdb1`. |
| Dotfiles | **GNU Stow.** Each module is one top-level folder mirroring `$HOME`, plus its own `packages.txt`. |
| Package lists | Plain-text lists, one package per line, per module. |
| Terminal | `foot` |
| AUR helper | `paru` |

### Look & feel

| Area | Decision |
|---|---|
| Theme engine | Own small script: `palette.toml` + per-format templates → generated files. |
| Palette | **Gruvbox Dark** (the only theme required at launch). |
| Wallpaper | `hyprpaper` |

### Bar (Waybar)

| Module | Decision |
|---|---|
| Bar | Waybar |
| Clock | Built-in clock module, alternate format on click |
| Wi-Fi / Ethernet | NetworkManager, with a launcher-menu script (networkmanager_dmenu style) on click |
| Sound | Waybar module; click opens `wiremix` in foot |
| Bluetooth | Waybar module; click opens `bluetui` in foot |
| System monitor | Built-in cpu + memory modules; click opens `btop` in foot |
| Extras | Custom modules (small scripts, refreshed by signal): weather, recording indicator, night-light indicator |

### Menus & launching (all on fuzzel)

| Area | Decision |
|---|---|
| App picker | `fuzzel` |
| System picker | One menu script driving `fuzzel --dmenu`, with nested menus |
| Power menu | Entries in the system picker |
| Clipboard history | `cliphist` shown through fuzzel |
| Keybind display | Binds carry descriptions; a script lists `hyprctl binds -j` through fuzzel |
| Wi-Fi menu | Same fuzzel dmenu mode (see Bar) |

### Feedback

| Area | Decision |
|---|---|
| Notifications | `mako` (do-not-disturb via a mako mode) |
| On-screen display | `swayosd` (volume, brightness, caps lock) |
| Reminders | Tiny script: `systemd-run --user --on-active=…` + `notify-send` |

### Hyprland

| Area | Decision |
|---|---|
| Config format | Lua, split into modules (binds, look, rules, input, monitors, autostart) |
| Session | `uwsm` |
| Lock / idle / night light | `hyprlock`, `hypridle`, `hyprsunset` |
| Portal | `xdg-desktop-portal-hyprland` + `xdg-desktop-portal-gtk` |

### Capture

| Area | Decision |
|---|---|
| Screenshots | `grimblast` + `satty` |
| Recording | `gpu-screen-recorder` |
| OCR | `grim` + `slurp` + `tesseract` script |
| Colour picker | `hyprpicker` |

### System

| Area | Decision |
|---|---|
| Login | Auto-login on TTY1 straight into `uwsm` after the LUKS unlock; no display manager |
| Boot | Limine + snapper + `limine-snapper-sync`, Plymouth splash |
| Update wrapper | Own script: snapshot → `reflector` → `pacman -Syu` → `paru -Sua` → remove orphans (with prompt) → `pacdiff` |

## How it fits together

### Repo layout (Stow modules)

Each top-level module folder is a Stow package. *(Claude's call)* Module metadata
(`packages.txt`, optional `install.sh`) sits in the module folder and is excluded from
stowing with an ignore rule, so a module is truly one folder.

```
dotfiles/
  modules.base       # module names installed by the ISO (base)
  modules.desktop    # module names installed by the ISO (desktop)
  bootstrap.sh       # entry point: install packages for listed modules, stow them, enable services
  base/              # pacman/paru, update wrapper, snapper, reflector, zram, locale
  hypr/              # .config/hypr/*.lua, hypridle, hyprlock, hyprsunset, hyprpaper
  theme/             # .config/theme/{palettes/,templates/}, .local/bin/theme-set
  waybar/
  fuzzel/            # fuzzel.ini + menu, keybind, clipboard, wifi scripts in .local/bin
  mako/
  swayosd/
  capture/           # screenshot, record, ocr scripts
  foot/
  session/           # uwsm env, TTY autologin drop-in, Plymouth
  iso/               # archiso profile (not stowed)
  ...
```

Exact module boundaries are left to the builder, with the rule: one feature = one
folder, and a folder's `packages.txt` lists only what that folder's config needs.

### Theme pipeline

- Source: `~/.config/theme/palettes/gruvbox-dark.toml` (named colours: `bg`, `bg1`…,
  `fg`, `accent`, `red`, `green`, `yellow`, `blue`, `purple`, `aqua`, `orange`, `grey`).
  `~/.config/theme/current` points at the active palette.
- `theme-set <name>` renders one file per *format* into
  `~/.config/theme/generated/` (outside the repo, so switching never dirties git):

  | Generated file | Included by |
  |---|---|
  | `colors.css` | Waybar, swayosd (`@import`) |
  | `colors.lua` | Hyprland Lua config and Neovim (`require`/`dofile`) |
  | `colors.conf` | hyprlock (`source =`) |
  | `colors.ini` | fuzzel, foot (`include=`) |
  | whole files | btop theme, satty config, mako config if it can't include |

- After rendering, it reloads the running tools (Hyprland reload, Waybar signal,
  `makoctl reload`, foot picks up on new windows) and sets the matching wallpaper.
- Hand-written configs only reference the generated files, never colour values.

### Installer flow

1. Boot ISO → bootstrap script runs automatically on TTY1.
2. If no wired connection is up, offer Wi-Fi setup (`iwctl` on the live ISO).
3. `archinstall` with the repo's saved config: user prompts for **target disk**
   (explicit choice, other disks untouched), username, password, LUKS passphrase,
   hostname. Layout: LUKS + btrfs subvolumes as in Constraints, Limine, NetworkManager.
4. In the new system: clone this repo, run `bootstrap.sh` with the base and desktop
   module lists (installs `paru`, packages, stows modules, enables services, sets
   Gruvbox Dark, sets up TTY autologin).
5. Reboot → LUKS prompt (Plymouth) → Hyprland.

The ISO profile lives in `iso/` and is built locally with `mkarchiso`. A CI build is a
possible later addition, not part of this work.

### System picker contents (initial)

Apps · Theme (switch palette) · Capture (screenshot region/window/screen, record
start/stop, OCR, colour pick) · Toggles (night light, do-not-disturb, idle inhibit) ·
Clipboard · Keybinds · Reminder · Network · Update · Power (lock, suspend, logout,
reboot, shutdown).

### The old dotfiles repo

`~/Work/dotfiles` is not modified. The Proton Mail / Thunderbird setup is copied from it
into an opt-in `mail` module here (not installed by the ISO). Nothing else carries over:
the monitor-layout scripts, solo-window daemon, `trim/`, `setup.sh` and
`install-packages.sh` stay behind with the old repo, which Harry retires after cutover.
The monitor values move into the new hyprland module's `monitors.lua`.

### Browser and editor

- **Browser: Firefox.** In the desktop module and set as the default browser in
  `mimeapps.list`. Chromium is not installed or maintained.
- **Editor: Neovim only.** In the base module and set as `$EDITOR`/`$VISUAL`. VS Code is
  not installed and gets no theme template.
- Neovim follows the palette by reading the generated `colors.lua`. Firefox is not
  themed from the palette; it follows the system dark preference
  (`gsettings set org.gnome.desktop.interface color-scheme prefer-dark`).

## Left to the builder

- Exact module split and file names inside each module.
- Porting Omarchy's binds and window rules. **Rule** *(Claude's call)*: port every
  Omarchy default bind and window rule whose target exists in the new setup (tiling,
  workspaces, media, capture, lock, menus, the apps kept in `app-bindings.lua`); drop
  binds that launch dropped or Omarchy-only things (web apps, `omarchy-launch-*`
  helpers, Omawrite, etc.). Write each with a description for the keybind display.
  Harry reviews the resulting bind list before it's final.
- Waybar layout and styling, matching the current bar's arrangement
  (left: menu + workspaces; centre: clock with indicators; right: tray, Bluetooth,
  network, audio, monitor, power) minus dropped widgets.
- Whether `mako` and `swayosd` can include the generated palette or need a whole
  generated file (verify before building; fall back to generating the whole file).
- The Gruvbox Dark palette values (use the canonical Gruvbox Dark hex values).
- Tests: `bats` tests for every script (theme-set rendering, menu script, update
  wrapper dry-run, bootstrap module resolution), following `trim/tests/`.
