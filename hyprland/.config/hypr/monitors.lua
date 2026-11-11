-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List monitors and their modes with: hyprctl monitors all

-- Anything not named below.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Desk ultrawide on the left, TV to its right at 2x.
hl.monitor({ output = "DP-1", mode = "5120x1440@120", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "5120x0", scale = 2 })

-- Known issue (Hyprland 0.56.2): if the TV drops HDMI (e.g. auto power-off)
-- while it is the only screen, every later modeset wedges until Hyprland
-- restarts. The old setup kept a spare headless output ("KEEPALIVE", created
-- with `hyprctl output create headless KEEPALIVE`) so there was never zero
-- outputs. That only matters with the desk monitor off; with both on, as here,
-- it isn't needed.
