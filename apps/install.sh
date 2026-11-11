#!/usr/bin/env bash
# Default applications. xdg-mime writes ~/.config/mimeapps.list, which is
# runtime state (Firefox and file managers write it too), so it is never stowed.
set -euo pipefail

xdg-mime default firefox.desktop x-scheme-handler/http x-scheme-handler/https text/html
xdg-mime default nvim.desktop text/plain
