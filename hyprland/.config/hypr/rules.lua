-- Window and layer rules. See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- window(match, effects) — match is a class pattern or a table of match fields.
local function window(match, effects)
  effects.match = type(match) == "string" and { class = match } or match
  hl.window_rule(effects)
end

-- Opt a window in to the standard active/inactive transparency.
local function transparent(match)
  window(match, { opacity = "0.985 0.96", tag = "+transparent-window" })
end

window(".*", { suppress_event = "maximize" })

-- Fix some dragging issues with XWayland.
window({
  class = "^$",
  title = "^$",
  xwayland = true,
  float = true,
  fullscreen = false,
  pin = false,
}, { no_focus = true })

-- Terminals: tagged so binds (universal copy/paste) and rules can single them out.
window("(foot|org\\.codeberg\\.dnkl\\.foot)", { tag = "+terminal" })
-- foot only applies its scrollback multiplier to wheel clicks, not touchpad scrolling.
window("foot", { scroll_touchpad = 2.0 })

-- Floating windows: centred at a standard size.
window({ tag = "floating-window" }, { float = true })
window({ tag = "floating-window" }, { center = true })
window({ tag = "floating-window" }, { size = { 875, 600 } })

window("(org\\.gnome\\.NautilusPreviewer|org\\.gnome\\.Evince|About|imv|mpv)", { tag = "+floating-window" })

-- The portal only shows dialogs (file pickers, screen shares, permission prompts).
window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
window({
  class = "(org\\.gnome\\.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- Popped-out windows (SUPER + O) get rounded corners.
window({ tag = "pop" }, { rounding = 8 })

-- Prevent idle while a window tagged noidle is open.
window({ tag = "noidle" }, { idle_inhibit = "always" })

-- Picture-in-picture overlays.
window({ title = "(Picture.?in.?[Pp]icture)" }, { tag = "+pip" })
window({ tag = "pip" }, {
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  move = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})

-- Transparency: terminals, the file manager, and anything SUPER + BACKSPACE tags.
transparent({ tag = "terminal" })
transparent("(org\\.gnome\\.Nautilus)")
transparent({ tag = "transparent" })

-- slurp's region picker (screenshots, recording, OCR): no fade in or out.
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true, animation = "none" })
