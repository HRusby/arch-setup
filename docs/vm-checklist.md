# VM end-to-end checklist

Walk this after `iso/test-vm.sh` boots the ISO. Fill in the Result column (pass, fail with a note, or N/A). Anything that fails is fixed in its owning task with a test, the ISO rebuilt and the check repeated.

Tools: `iso/test-vm.sh [--iso PATH] [--recreate]` boots the newest `iso/out/*.iso` with two disks (`vm/disk1.qcow2` target, `vm/disk2.img` stand-in Windows disk). `iso/test-vm.sh --check-disk2` verifies disk 2 was never written. Disk 2 needs `sfdisk`, `mkfs.fat` and `mtools`, and disk 1 needs `qemu-img`.

## 1. Install flow

| Check | How | Result |
|---|---|---|
| Build the ISO | `iso/build.sh` (needs `archiso`, sudo). Prints the ISO path in `iso/out/`. | |
| Repo reachable by the installer | Ask Harry first. Push to `HRusby/arch-setup` on GitHub, or point `install-arch` at a local HTTP clone for the test. | |
| Boot the ISO in the VM | `iso/test-vm.sh` (first run builds `vm/disk1.qcow2` and `vm/disk2.img`). OVMF boots the live ISO and tty1 starts `install-arch`. | |
| Wired network skips Wi-Fi | QEMU user networking is wired. `install-arch` goes straight on, no `iwctl`. | |
| archinstall 4.5 loads the config | The menu opens pre-filled from `/root/archinstall/user_configuration.json`, with no error. | |
| Menu shows the pre-filled choices | UK keyboard, `en_US.UTF-8`, Europe/London, kernel `linux`, bootloader Limine, NetworkManager, PipeWire, Minimal profile, zram swap, `git` in packages. | |
| Disk choice | Disk configuration per `iso/INSTALL.md`: best-effort layout on **disk1 only** (the 40G disk, not the 1G Windows disk), btrfs with default subvolumes, zstd, LUKS on the btrfs root. LVM off, btrfs snapshots unset. | |
| Hostname, user, root password | One superuser account (UID 1000). Review the install summary: it lists only disk1. | |
| `/mnt` still mounted after exiting archinstall | Choose **Exit archinstall**, not Reboot. In another tty, `mountpoint /mnt` succeeds. | |
| sudo present in the target | `arch-chroot /mnt which sudo`. The temporary `99-bootstrap` sudoers drop-in is used during bootstrap and gone afterwards: `ls /mnt/etc/sudoers.d/`. | |
| Bootstrap runs inside the chroot | `install-arch` clones to `~/arch-setup` and runs `bootstrap.sh --lists base,desktop` as the user. Watch for failures in `limine-update`/`efibootmgr`, `systemctl enable` and anything needing a running systemd or user session. | |
| Bootstrap failure path (if it fails) | `install-arch --resume` skips archinstall, reuses the clone (`git pull --ff-only`) and runs bootstrap again. Not needed if the first run succeeds. | |
| Reboot | `install-arch` offers a reboot. The VM reboots into the installed system (remove the ISO or let UEFI pick disk1). | |

## 2. Disk layout and boot loader

| Check | How | Result |
|---|---|---|
| btrfs subvolumes | `btrfs subvolume list /` shows exactly `@`, `@home`, `@log`, `@pkg`. `findmnt` shows them at `/`, `/home`, `/var/log`, `/var/cache/pacman/pkg`. | |
| Which limine.conf is read | `find /boot -iname 'limine.conf*'` lists only the ESP's `limine.conf` (others renamed `.disabled`). In the Limine menu press `e` on an entry and check it shows the tool's entries. | |
| EFI binary and NVRAM entry | `efibootmgr -v` boots `\EFI\limine\limine_x64.efi`, or the fallback `EFI/BOOT/BOOTX64.EFI` boots. No `limine.conf` sits next to whichever binary boots. | |
| No duplicate or stock entries | The Limine menu has `/+Arch Linux` first with its kernels, the Snapshots entry and Windows. No `Arch Linux (linux)` stock entries, no `boot():/vmlinuz-linux` entries. | |
| Default entry boots | Without input: Plymouth, the LUKS prompt, auto-login, Hyprland. `cat /proc/cmdline` contains `splash` and matches `/etc/kernel/cmdline`. | |
| Plymouth is in the built initramfs | `lsinitcpio /boot/*/linux/initramfs-linux.img \| grep -i plymouth` (path from `/boot/<machine-id>/linux/`). | |
| Simulated `linux` upgrade still boots | `sudo pacman -S linux`. Hook output has no "skipping"; `/boot/<machine-id>/linux/` has fresh vmlinuz and initramfs; no new `boot():/vmlinuz-linux` entries. Reboot: `uname -r` equals the installed package version, and `sudo modprobe` of an unloaded module works. | |
| Windows entry from disk 2 | The Limine menu has a Windows entry for the ESP on disk2 (dummy `bootmgfw.efi`). It is listed; chainloading the dummy file is expected to fail. `sudo limine-windows-entry` finds exactly one ESP (disk2), not disk1's. | |
| Snapshots in Limine | After `sysupdate` (or `sudo snapper -c root create`), the Snapshots submenu lists the snapshot. It boots read-only with an overlay. | |

## 3. Session and login

| Check | How | Result |
|---|---|---|
| Auto-login to Hyprland | No login prompt after the LUKS passphrase: tty1 auto-login starts Hyprland through uwsm. | |
| Waybar appears | The bar is on screen with no error notification. | |
| Caps Lock still toggles | Press Caps Lock in a terminal: typed letters switch case, and the swayosd Caps Lock indicator shows. | |
| Theme applied on first login | `theme-set gruvbox-dark` has been run (a first bootstrap may not have applied it). Run it once and check the colours change everywhere. | |
| `theme-set gruvbox-dark` re-run is clean | Run it twice. No errors, no duplicate entries, apps follow the theme. | |

## 4. Waybar

| Check | How | Result |
|---|---|---|
| Clock | Shows the time; click toggles the alternate format. | |
| Network module | Click opens `nm-menu`. | |
| Audio module | Click opens `wiremix` in foot. | |
| Bluetooth module | Click opens `bluetui` in foot. | |
| CPU module | Click opens `btop` in foot. | |
| Weather module | `waybar-weather` shows a temperature (VM has network) or a clean fallback. | |
| Indicators | `waybar-indicators` shows recording, night light, DND and idle state; each flips when toggled. Signal numbers match (signal 8 mapping). | |
| Capture status on/off | The recording indicator appears during a recording and disappears after it stops. | |
| swayosd and waybar `@import` paths | Waybar and swayosd load their generated theme CSS: `journalctl --user -b \| grep -i -e import -e css` shows no error; the bar and OSD are themed, not default. | |
| Toggle top bar | SUPER+SHIFT+SPACE hides and shows the bar. | |

## 5. Menus (fuzzel)

| Check | How | Result |
|---|---|---|
| System menu | SUPER+SPACE opens the menu. | |
| Apps | SUPER+ALT+SPACE lists applications; launching one works. | |
| Power submenu | SUPER+ESCAPE shows lock, suspend, reboot, shutdown (do not pick the destructive ones unless intended). | |
| Capture, toggle and theme menus | SUPER+CTRL+C, SUPER+CTRL+O, SUPER+CTRL+T each open and act. | |
| Clipboard manager | Copy two texts, SUPER+CTRL+V lists both; picking one pastes it. | |
| Keybindings list | SUPER+K lists the binds with their descriptions. | |
| `fuzzel --prompt-only` returns typed text | `fuzzel --dmenu --prompt-only 'x '` (or the reminder prompt): type text, Enter, the text is printed on stdout. | |
| `~` expansion in fuzzel and mako includes | fuzzel is themed from `~/.config/theme/generated/...` and mako picks up its included theme file (colours match the theme); no "cannot open include" in `journalctl --user -b`. | |
| `nmcli --ask` with piped stdin | In `nm-menu`, connect to a secured network (or `echo secret \| nmcli --ask device wifi connect X`): the passphrase prompt is answered from stdin, no hang. The VM has no Wi-Fi radio; use a hotspot passthrough or note N/A. | |
| NetworkManager from the fuzzel module | `systemctl is-enabled NetworkManager` is enabled; `nmcli general status` works. | |

## 6. Notifications and feedback

| Check | How | Result |
|---|---|---|
| Notification shows | `notify-send hello world` shows a themed mako popup. | |
| Dismiss | SUPER+comma dismisses one, SUPER+SHIFT+comma all. | |
| Restore | SUPER+SHIFT+ALT+comma restores the last (`makoctl restore`). | |
| Do not disturb | SUPER+CTRL+ALT+comma: `notify-send` is silent and `toggle dnd status` says on; toggle again restores popups. The indicator follows. | |
| OSD on volume keys | Volume up/down/mute (`swayosd-client --output-volume raise`) shows the swayosd popup, themed; the volume actually changes (`wpctl get-volume @DEFAULT_AUDIO_SINK@`). | |
| Brightness OSD | Brightness keys show an OSD, or fail cleanly (a VM has no backlight). | |
| Reminder fires | `remind 1 test reminder`: a notification appears after about a minute. `remind list` shows it before, `remind clear` removes pending ones. | |
| Reminder menu | SUPER+CTRL+R prompts for minutes and message, then schedules. | |

## 7. Lock, idle and night light

| Check | How | Result |
|---|---|---|
| Lock | SUPER+CTRL+L shows hyprlock, themed; the user password unlocks it. | |
| Idle | Wait for the hypridle timeouts (dim, lock, screen off); input wakes the screen. `toggle idle` (SUPER+CTRL+I) disables locking on idle. | |
| Night light toggle | `toggle nightlight` tints the screen and `toggle nightlight status` says on; again turns it off. | |
| Night light with idle dim | Gamma dimming by hypridle does not break or stick the night-light toggle. | |

## 8. Screenshots, recording, OCR, colour

| Check | How | Result |
|---|---|---|
| Screenshot region to satty | PRINT, drag a region: satty opens with it, themed. Save writes under `~/Pictures/Screenshots`. | |
| grimblast stdout and `satty --filename -` | The region reaches satty through the pipe (satty shows the image, not a blank canvas). | |
| Recording start/stop | ALT+PRINT starts `gpu-screen-recorder` (the VM may lack a usable GPU encoder: note the error text); the indicator shows; ALT+PRINT stops and a file lands in `~/Videos/Recordings`. | |
| OCR | SUPER+CTRL+PRINT, select text on screen: it is on the clipboard (`wl-paste`). | |
| Colour pick | SUPER+PRINT, click a pixel: the colour value is on the clipboard / notified. | |

## 9. Window management

| Check | How | Result |
|---|---|---|
| Monitor-direction dispatchers | The move-workspace-to-monitor (SUPER+SHIFT+ALT+direction key) and move-window-to-monitor (SUPER+SHIFT+CTRL+direction key) binds run without a Hyprland error with one monitor; `hyprctl` shows no config errors. Direction args (`l`, `r`, `u`, `d`) accepted by `dsp.workspace.move` / `dsp.window.move`. | |
| Basic binds | SUPER+RETURN opens foot, SUPER+SHIFT+B firefox, SUPER+Q closes, workspaces SUPER+1..9 switch. | |
| Universal copy and paste | SUPER+C / SUPER+V work in foot (with Shift) and in firefox. | |

## 10. Software and updates

| Check | How | Result |
|---|---|---|
| `sysupdate` makes a snapshot | `sysupdate`: a snapper snapshot is created first (`snapper -c root list`), mirrors refresh, repo and AUR packages update, orphans are pruned. | |
| reflector config works | `sudo reflector @/etc/xdg/reflector/reflector.conf` (the line `sysupdate` uses) succeeds and rewrites the mirrorlist. | |
| Firefox is the default browser | `xdg-settings get default-web-browser` is `firefox.desktop`; SUPER+SHIFT+B opens it. | |
| `:colorscheme palette` in nvim | Open `nvim`, run `:colorscheme palette`: no error and colours match the theme. | |
| Real-stow bats tests | Once `stow` is installed (`sudo pacman -S stow bats`): in `~/arch-setup`, `bats tests/` passes, with no skipped stow tests. | |

## 11. Windows disk safety

| Check | How | Result |
|---|---|---|
| Disk 2 untouched | Shut the VM down, then run `iso/test-vm.sh --check-disk2`. Expected: `disk2 unchanged`. Anything else fails the whole run. | |
