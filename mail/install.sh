#!/usr/bin/env bash
# Thunderbird handles mailto links and mail messages. xdg-mime writes
# ~/.config/mimeapps.list, which the apps module also stows, so the defaults
# are set here rather than shipped as a second copy of that file.
set -euo pipefail

xdg-mime default org.mozilla.Thunderbird.desktop \
    x-scheme-handler/mailto message/rfc822 x-scheme-handler/mid
