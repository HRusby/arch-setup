-- Key bindings. Every bind has a description: `keybinds` (SUPER + K) lists them.
-- String actions run via `uwsm-app --`; see lib/bind.lua.

local bind = require("hypr.lib.bind")
local dsp = hl.dsp

-- run(...) — a bind action that dispatches each dispatcher in turn.
local function run(...)
  local dispatchers = { ... }
  return function()
    for _, d in ipairs(dispatchers) do
      hl.dispatch(d)
    end
  end
end

local function has_tag(window, wanted)
  for _, tag in ipairs(window.tags or {}) do
    -- Dynamic tags carry a trailing "*".
    if tag:gsub("%*$", "") == wanted then
      return true
    end
  end
  return false
end

local function address(window)
  return "address:" .. window.address
end

---------------------------------------------------------------------------
-- Apps
---------------------------------------------------------------------------
bind("SUPER + RETURN", "Terminal", "foot")
bind("SUPER + SHIFT + RETURN", "Browser", "firefox")
bind("SUPER + SHIFT + B", "Browser", "firefox")
bind("SUPER + SHIFT + ALT + B", "Browser (private)", "firefox --private-window")
bind("SUPER + SHIFT + F", "File manager", "nautilus --new-window")
bind("SUPER + SHIFT + N", "Editor", "foot -e nvim")
bind("SUPER + SHIFT + O", "Obsidian", "obsidian")
bind("SUPER + SHIFT + T", "Activity", "foot -e btop")
bind("SUPER + CTRL + A", "Audio", "foot -e wiremix")
bind("SUPER + CTRL + B", "Bluetooth", "foot -e bluetui")
bind("SUPER + CTRL + N", "Network", "nm-menu")

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
bind("SUPER + SPACE", "System menu", "menu")
bind("SUPER + SHIFT + code:201", "System menu", "menu")
bind("SUPER + ALT + SPACE", "Apps", "menu apps")
bind("SUPER + ESCAPE", "Power menu", "menu power")
bind("XF86PowerOff", "Power menu", "menu power", { locked = true })
bind("SUPER + CTRL + C", "Capture menu", "menu capture")
bind("SUPER + CTRL + O", "Toggle menu", "menu toggles")
bind("SUPER + CTRL + T", "Theme menu", "menu theme")
bind("SUPER + SHIFT + CTRL + SPACE", "Theme menu", "menu theme")
bind("SUPER + K", "Keybindings", "keybinds")
bind("SUPER + CTRL + V", "Clipboard manager", "clipmenu")

---------------------------------------------------------------------------
-- Session, notifications, reminders
---------------------------------------------------------------------------
bind("SUPER + CTRL + L", "Lock system", "loginctl lock-session")
bind("SUPER + CTRL + I", "Toggle locking on idle", "toggle idle")
bind("SUPER + SHIFT + SPACE", "Toggle top bar", "pkill -SIGUSR1 waybar")

-- xkbcommon names the comma keysym "comma"; the upper-case "COMMA" does not match.
bind("SUPER + comma", "Dismiss notification", "makoctl dismiss")
bind("SUPER + SHIFT + comma", "Dismiss all notifications", "makoctl dismiss --all")
bind("SUPER + SHIFT + ALT + comma", "Restore last notification", "makoctl restore")
bind("SUPER + CTRL + ALT + comma", "Toggle silencing notifications", "toggle dnd")

bind("SUPER + CTRL + R", "Set reminder", "menu reminder")
bind("SUPER + CTRL + ALT + R", "Show reminders", 'notify-send Reminders "$(remind list)"')
bind("SUPER + SHIFT + CTRL + R", "Clear reminders", "remind clear")

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------
bind("PRINT", "Screenshot", "capture screenshot region")
bind("SUPER + CTRL + ALT + C", "Screenshot", "capture screenshot region")
bind("ALT + PRINT", "Screen recording", "capture record toggle")
bind("SUPER + PRINT", "Color picker", "capture colour")
bind("SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "capture ocr")

---------------------------------------------------------------------------
-- Volume, brightness, media
---------------------------------------------------------------------------
local held = { locked = true, repeating = true }
local locked = { locked = true }

bind("XF86AudioRaiseVolume", "Volume up", "swayosd-client --output-volume raise", held)
bind("XF86AudioLowerVolume", "Volume down", "swayosd-client --output-volume lower", held)
bind("XF86AudioMute", "Mute", "swayosd-client --output-volume mute-toggle", locked)
bind("XF86AudioMicMute", "Mute microphone", "swayosd-client --input-volume mute-toggle", locked)
bind("ALT + XF86AudioRaiseVolume", "Volume up precise", "swayosd-client --output-volume +1", held)
bind("ALT + XF86AudioLowerVolume", "Volume down precise", "swayosd-client --output-volume -1", held)

bind("XF86MonBrightnessUp", "Brightness up", "swayosd-client --brightness raise", held)
bind("XF86MonBrightnessDown", "Brightness down", "swayosd-client --brightness lower", held)
bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", "swayosd-client --brightness 100", held)
bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", "swayosd-client --brightness 1", held)
bind("ALT + XF86MonBrightnessUp", "Brightness up precise", "swayosd-client --brightness +1", held)
bind("ALT + XF86MonBrightnessDown", "Brightness down precise", "swayosd-client --brightness -1", held)

-- On release, once the lock state has flipped. Transparent and non-consuming
-- so Caps Lock itself still reaches the keyboard; ignore_mods so it fires
-- whether Caps Lock was on or off.
bind("Caps_Lock", "Caps Lock indicator", "swayosd-client --caps-lock",
  { locked = true, release = true, transparent = true, non_consuming = true, ignore_mods = true })

bind("XF86AudioNext", "Next track", "playerctl next", locked)
bind("ALT + XF86AudioPlay", "Next track", "playerctl next", locked)
bind("XF86AudioPause", "Pause", "playerctl play-pause", locked)
bind("XF86AudioPlay", "Play", "playerctl play-pause", locked)
bind("XF86AudioPrev", "Previous track", "playerctl previous", locked)
bind("ALT + SHIFT + XF86AudioPlay", "Previous track", "playerctl previous", locked)
bind("XF86Eject", "Eject media", "eject", locked)

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
bind("SUPER + W", "Close window", dsp.window.close())
bind("SUPER + Q", "Close window", dsp.window.close())
bind("CTRL + ALT + DELETE", "Close all windows", function()
  for _, w in ipairs(hl.get_windows() or {}) do
    hl.dispatch(dsp.window.close({ window = address(w) }))
  end
  hl.dispatch(dsp.focus({ workspace = "1" }))
end)

bind("SUPER + J", "Toggle window split", dsp.layout("togglesplit"))
bind("SUPER + P", "Pseudo window", dsp.window.pseudo())
bind("SUPER + T", "Toggle window floating/tiling", dsp.window.float({ action = "toggle" }))
bind("SUPER + F", "Full screen", dsp.window.fullscreen({ mode = "fullscreen" }))
bind("SUPER + ALT + F", "Full width", dsp.window.fullscreen({ mode = "maximized" }))

-- Float, size, centre and pin the window above the others; again to put it back.
bind("SUPER + O", "Pop window out (float & pin)", function()
  local w = hl.get_active_window()
  if not w then
    return
  end
  local target = address(w)
  if w.pinned then
    hl.dispatch(dsp.window.pin({ window = target }))
    hl.dispatch(dsp.window.float({ window = target, action = "toggle" }))
    hl.dispatch(dsp.window.tag({ window = target, tag = "-pop" }))
  else
    hl.dispatch(dsp.window.float({ window = target, action = "toggle" }))
    hl.dispatch(dsp.window.resize({ window = target, x = 1300, y = 900 }))
    hl.dispatch(dsp.window.center({ window = target }))
    hl.dispatch(dsp.window.pin({ window = target }))
    hl.dispatch(dsp.window.alter_zorder({ window = target, mode = "top" }))
    hl.dispatch(dsp.window.tag({ window = target, tag = "+pop" }))
  end
end)

-- Tag the window so the transparency rule (rules.lua) applies, or flip it back to opaque.
bind("SUPER + BACKSPACE", "Toggle transparency on a window", function()
  local w = hl.get_active_window()
  if not w then
    return
  end
  local target = address(w)
  if has_tag(w, "transparent-window") then
    hl.dispatch(dsp.window.set_prop({ window = target, prop = "opaque", value = "toggle" }))
  else
    hl.dispatch(dsp.window.tag({ window = target, tag = "+transparent" }))
    hl.dispatch(dsp.window.set_prop({ window = target, prop = "opaque", value = "false" }))
  end
end)

bind("SUPER + LEFT", "Focus on left window", dsp.focus({ direction = "l" }))
bind("SUPER + RIGHT", "Focus on right window", dsp.focus({ direction = "r" }))
bind("SUPER + UP", "Focus on above window", dsp.focus({ direction = "u" }))
bind("SUPER + DOWN", "Focus on below window", dsp.focus({ direction = "d" }))

bind("SUPER + SHIFT + LEFT", "Swap window to the left", dsp.window.swap({ direction = "l" }))
bind("SUPER + SHIFT + RIGHT", "Swap window to the right", dsp.window.swap({ direction = "r" }))
bind("SUPER + SHIFT + UP", "Swap window up", dsp.window.swap({ direction = "u" }))
bind("SUPER + SHIFT + DOWN", "Swap window down", dsp.window.swap({ direction = "d" }))

-- Cycling raises the window it lands on; going backwards lowers the one it
-- leaves instead, since raising would ping-pong between two windows.
bind("ALT + TAB", "Focus on next window",
  run(dsp.window.cycle_next(), dsp.window.bring_to_top()))
bind("ALT + SHIFT + TAB", "Focus on previous window",
  run(dsp.window.alter_zorder({ mode = "bottom" }), dsp.window.cycle_next({ next = false })))

-- code:20 / code:21 are the - and = keys.
local resize_steps = { { "", 100, "" }, { "ALT + ", 25, " a little" }, { "CTRL + ", 300, " a lot" } }
for _, step in ipairs(resize_steps) do
  local mod, n, how = step[1], step[2], step[3]
  bind("SUPER + " .. mod .. "code:20", "Expand window left" .. how, dsp.window.resize({ x = -n, y = 0, relative = true }))
  bind("SUPER + " .. mod .. "code:21", "Shrink window left" .. how, dsp.window.resize({ x = n, y = 0, relative = true }))
  bind("SUPER + SHIFT + " .. mod .. "code:20", "Shrink window up" .. how, dsp.window.resize({ x = 0, y = -n, relative = true }))
  bind("SUPER + SHIFT + " .. mod .. "code:21", "Expand window down" .. how, dsp.window.resize({ x = 0, y = n, relative = true }))
end

bind("SUPER + mouse:272", "Move window", dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", "Resize window", dsp.window.resize(), { mouse = true })

---------------------------------------------------------------------------
-- Workspaces and monitors
---------------------------------------------------------------------------
-- code:10 .. code:19 are the number keys 1 .. 0.
for n = 1, 10 do
  local key = "code:" .. (n + 9)
  local ws = tostring(n)
  bind("SUPER + " .. key, "Switch to workspace " .. n, dsp.focus({ workspace = ws }))
  bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. n, dsp.window.move({ workspace = ws }))
  bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. n,
    dsp.window.move({ workspace = ws, follow = false }))
end

bind("SUPER + S", "Toggle scratchpad", dsp.workspace.toggle_special("scratchpad"))
bind("SUPER + ALT + S", "Move window to scratchpad", dsp.window.move({ workspace = "special:scratchpad", follow = false }))

bind("SUPER + TAB", "Next workspace", dsp.focus({ workspace = "m+1" }))
bind("SUPER + SHIFT + TAB", "Previous workspace", dsp.focus({ workspace = "m-1" }))
bind("SUPER + CTRL + TAB", "Former workspace", dsp.focus({ workspace = "previous_per_monitor" }))
bind("SUPER + mouse_down", "Scroll active workspace forward", dsp.focus({ workspace = "m+1" }))
bind("SUPER + mouse_up", "Scroll active workspace backward", dsp.focus({ workspace = "m-1" }))

bind("CTRL + ALT + TAB", "Focus on next monitor", dsp.focus({ monitor = "+1" }))
bind("CTRL + ALT + SHIFT + TAB", "Focus on previous monitor", dsp.focus({ monitor = "-1" }))

local directions = { { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "up" }, { "DOWN", "d", "down" } }
for _, d in ipairs(directions) do
  local key, dir, name = d[1], d[2], d[3]
  bind("SUPER + SHIFT + ALT + " .. key, "Move workspace to " .. name .. " monitor", dsp.workspace.move({ monitor = dir }))
  bind("SUPER + SHIFT + CTRL + " .. key, "Move window to " .. name .. " monitor", dsp.window.move({ monitor = dir }))
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
bind("SUPER + G", "Toggle window grouping", dsp.group.toggle())
bind("SUPER + ALT + G", "Move active window out of group", dsp.window.move({ out_of_group = true }))

bind("SUPER + ALT + LEFT", "Move window to group on left", dsp.window.move({ into_group = "l" }))
bind("SUPER + ALT + RIGHT", "Move window to group on right", dsp.window.move({ into_group = "r" }))
bind("SUPER + ALT + UP", "Move window to group on top", dsp.window.move({ into_group = "u" }))
bind("SUPER + ALT + DOWN", "Move window to group on bottom", dsp.window.move({ into_group = "d" }))

bind("SUPER + ALT + TAB", "Next window in group", dsp.group.next())
bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", dsp.group.prev())
bind("SUPER + CTRL + LEFT", "Move grouped window focus left", dsp.group.prev())
bind("SUPER + CTRL + RIGHT", "Move grouped window focus right", dsp.group.next())
bind("SUPER + ALT + mouse_down", "Next window in group", dsp.group.next())
bind("SUPER + ALT + mouse_up", "Previous window in group", dsp.group.prev())

for n = 1, 5 do
  bind("SUPER + ALT + code:" .. (n + 9), "Switch to group window " .. n, dsp.group.active({ index = n }))
end

---------------------------------------------------------------------------
-- Clipboard: SUPER + A/C/V/X act like Ctrl (Ctrl+Shift in terminals)
---------------------------------------------------------------------------
-- Send to the focused surface with explicit mods. The down/up split works
-- around send_shortcut sometimes leaving synthetic key state stuck/repeating
-- (https://github.com/hyprwm/Hyprland/discussions/14099).
local function send_shortcut(mods, key)
  hl.dispatch(dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function shortcut(mods, key, terminal_mods)
  return function()
    local w = hl.get_active_window()
    if terminal_mods and w and has_tag(w, "terminal") then
      send_shortcut(terminal_mods, key)
    else
      send_shortcut(mods, key)
    end
  end
end

bind("SUPER + A", "Select all", shortcut("CTRL", "A"))
bind("SUPER + C", "Universal copy", shortcut("CTRL", "C", "CTRL SHIFT"))
bind("SUPER + V", "Universal paste", shortcut("CTRL", "V", "CTRL SHIFT"))
bind("SUPER + X", "Universal cut", shortcut("CTRL", "X"))

---------------------------------------------------------------------------
-- Zoom
---------------------------------------------------------------------------
bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)
bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)
