# Installing from the ISO

Build the image with `iso/build.sh` (needs `archiso`), write `iso/out/*.iso` to
a USB stick and boot it. On tty1 `install-arch` starts by itself:

1. **Network.** With Ethernet it goes straight on. Otherwise it opens `iwctl`:
   `station wlan0 connect <SSID>`, then `exit`. It reopens `iwctl` until
   `archlinux.org` answers.
2. **archinstall** opens its menu pre-filled from
   `/root/archinstall/user_configuration.json`: UK keyboard, `en_US.UTF-8`,
   Europe/London, `linux`, Limine, NetworkManager, PipeWire, Minimal profile,
   zram swap, plus `git`. The file names no disk and no credentials, so set
   these yourself.
3. When archinstall finishes, choose **Exit archinstall** (not Reboot).
   `install-arch` then clones this repo into `~/arch-setup` in the new system
   and runs `bootstrap.sh --lists base,desktop` as your user, then offers to
   reboot.

## Disk configuration (do this carefully)

archinstall's config can't describe a btrfs layout without naming a disk, so
you choose the layout in the menu. Only the disk you pick is wiped; leave the
Windows and data disks alone.

- **Disk configuration → Partitioning → Use a best-effort default partition layout**
  - select **only** the target disk (check model and size)
  - filesystem: **btrfs**
  - "Use BTRFS subvolumes with a default structure?" **Yes**. This gives
    exactly the subvolumes the repo expects:
    - `@` → `/`
    - `@home` → `/home`
    - `@log` → `/var/log`
    - `@pkg` → `/var/cache/pacman/pkg`
  - compression: **Use compression** (zstd) is fine
- **Disk configuration → LVM**: leave off.
- **Disk configuration → Btrfs snapshots**: leave unset. The `session` module
  sets up snapper itself (and copes with an existing `/.snapshots`).
- **Disk configuration → Disk encryption**
  - Encryption type: **LUKS**
  - Encryption password: your LUKS passphrase
  - Partitions: select the btrfs root partition

## Also set in the menu

- **Hostname**
- **Authentication → User account**: one user, marked as superuser (sudo).
  It gets UID 1000, which is the user `install-arch` bootstraps as.
- **Authentication → Root password** (optional)

Then **Install**. Review the summary: it must list only the disk you picked.

## If bootstrap fails

The temporary passwordless sudo rule is removed either way. Fix the problem,
then run `install-arch --resume` before rebooting: it never runs archinstall,
reuses the `~/arch-setup` clone (`git pull --ff-only`) and runs bootstrap
again. A plain `install-arch` also notices the install mounted at `/mnt` and
offers to resume instead of repartitioning.
