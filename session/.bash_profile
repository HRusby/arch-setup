#
# ~/.bash_profile
#

# shellcheck shell=bash disable=SC1090
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Repo scripts (menu, toggle, ...) live in ~/.local/bin; binds, Waybar and the
# menu call them by name. uwsm hands this PATH to the session.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

# On tty1 (uwsm's default), replace the login shell with the Hyprland session.
if command -v uwsm > /dev/null && uwsm check may-start; then
    exec uwsm start hyprland.desktop
fi
