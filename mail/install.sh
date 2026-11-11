#!/usr/bin/env bash
# Thunderbird handles mailto links and mail messages. xdg-mime writes
# ~/.config/mimeapps.list, which is runtime state, so the defaults
# are set here; the file itself is never stowed.
set -euo pipefail

xdg-mime default org.mozilla.Thunderbird.desktop \
    x-scheme-handler/mailto message/rfc822 x-scheme-handler/mid
