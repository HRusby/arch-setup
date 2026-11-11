# arch-setup

Arch Linux dotfiles. Each feature is a GNU Stow module: a top-level folder whose
contents mirror `$HOME`, plus optional metadata that is never linked.

## A module

```
<module>/
  .config/...        # stowed into $HOME
  .local/bin/...     # stowed into $HOME
  packages.txt       # repo packages, one per line (# comments, blanks ok)
  packages.aur.txt   # AUR packages (installed with paru)
  install.sh         # optional, executable; runs before the module is stowed
  post-install.sh    # optional, executable; runs after every module is stowed
```

`packages.txt`, `packages.aur.txt`, `install.sh`, `post-install.sh`, `tests/`
and `system/` are ignored by stow.

## Adding one

1. Create the folder with its config tree and package lists.
2. Add its name to `modules.base` or `modules.desktop` (one per line, in install order).
3. Add bats tests under `tests/`.

## Running

```
./bootstrap.sh                       # lists base,desktop
./bootstrap.sh --modules nvim,foot   # just these modules
./bootstrap.sh --lists base          # just a list
./bootstrap.sh --adopt               # take over existing files at stow targets
./bootstrap.sh --dry-run             # print the plan, run nothing
```

Packages are installed in one `pacman` call and one `paru` call, then each
`install.sh` runs, then modules are stowed, then each `post-install.sh` runs
(in module order). Conflicts with real files abort before anything is linked.

## Tests

```
bats tests/
```

Tests run in a sandboxed `$HOME` with fake `sudo`/`paru`; real-stow tests are
skipped when `stow` is not installed. `tests/lint.bats` rejects colour literals
outside `theme/.config/theme/palettes/` and runs shellcheck on scripts.
