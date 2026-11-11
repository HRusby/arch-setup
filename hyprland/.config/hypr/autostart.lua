-- Session services, started once when Hyprland starts (not on reload).
-- mako is D-Bus activated, so it isn't listed.

local services = {
  "waybar",
  "swayosd-server",
  "hyprpaper",
  "hypridle",
  "hyprsunset",
  "systemctl --user start hyprpolkitagent",
  "wl-paste --type text --watch cliphist store",
  "wl-paste --type image --watch cliphist store",
}

hl.on("hyprland.start", function()
  for _, command in ipairs(services) do
    hl.exec_cmd("uwsm-app -- " .. command)
  end
  -- theme-set runs gsettings during bootstrap, in a chroot where it only
  -- reaches the memory backend; set the colour scheme again for real.
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
end)
