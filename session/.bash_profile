#
# ~/.bash_profile
#

# shellcheck shell=bash disable=SC1090
[[ -f ~/.bashrc ]] && . ~/.bashrc

# On tty1 (uwsm's default), replace the login shell with the Hyprland session.
if command -v uwsm > /dev/null && uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
