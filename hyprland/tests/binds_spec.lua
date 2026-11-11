-- Spec for the Hyprland Lua config, run against the recording stub.
-- Usage: lua tests/binds_spec.lua [case name]   (exit 1 on any failure)

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local stub = dofile(here .. "/stub_hl.lua")

local NO_COLORS = { XDG_CONFIG_HOME = "/nonexistent", HOME = "/nonexistent" }
local FIXTURE_COLORS = { XDG_CONFIG_HOME = here .. "/fixture" }

local cases, order = {}, {}
local function case(name, fn)
  cases[name] = fn
  table.insert(order, name)
end

local function check(cond, msg)
  if not cond then
    error(msg, 2)
  end
end

-- "SHIFT + super + b" and "SUPER + SHIFT + B" are the same chord.
local function chord(keys)
  local parts = {}
  for part in keys:gmatch("[^+]+") do
    table.insert(parts, (part:gsub("^%s+", ""):gsub("%s+$", ""):upper()))
  end
  local key = table.remove(parts)
  table.sort(parts)
  table.insert(parts, key)
  return table.concat(parts, " + ")
end

local function binds_by_chord(rec)
  local by = {}
  for _, b in ipairs(rec.bind) do
    by[chord(b.keys)] = b
  end
  return by
end

local function exec_of(dispatcher)
  if type(dispatcher) == "table" and dispatcher.dsp == "exec_cmd" then
    return dispatcher.args[1]
  end
end

-- Keys -> command (run via uwsm-app), and options that must be set.
local REQUIRED = {
  { "SUPER + SPACE", "menu" },
  { "SUPER + ALT + SPACE", "menu apps" },
  { "SUPER + ESCAPE", "menu power" },
  { "XF86PowerOff", "menu power", { locked = true } },
  { "SUPER + K", "keybinds" },
  { "SUPER + CTRL + V", "clipmenu" },
  { "SUPER + CTRL + N", "nm-menu" },
  { "SUPER + CTRL + A", "foot -e wiremix" },
  { "SUPER + CTRL + B", "foot -e bluetui" },
  { "SUPER + SHIFT + T", "foot -e btop" },
  { "PRINT", "capture screenshot region" },
  { "SUPER + CTRL + ALT + C", "capture screenshot region" },
  { "ALT + PRINT", "capture record toggle" },
  { "SUPER + PRINT", "capture colour" },
  { "SUPER + CTRL + PRINT", "capture ocr" },
  { "SUPER + CTRL + R", "menu reminder" },
  { "SUPER + CTRL + T", "menu theme" },
  { "SUPER + CTRL + L", "loginctl lock-session" },
  { "SUPER + CTRL + I", "toggle idle" },
  { "SUPER + CTRL + ALT + comma", "toggle dnd" },
  { "SUPER + comma", "makoctl dismiss" },
  { "SUPER + SHIFT + comma", "makoctl dismiss --all" },
  { "SUPER + RETURN", "foot" },
  { "SUPER + SHIFT + B", "firefox" },
  { "SUPER + SHIFT + RETURN", "firefox" },
  { "SUPER + SHIFT + ALT + B", "firefox --private-window" },
  { "SUPER + SHIFT + N", "foot -e nvim" },
  { "SUPER + SHIFT + O", "obsidian" },
  { "XF86AudioRaiseVolume", "swayosd-client --output-volume raise", { locked = true, repeating = true } },
  { "XF86AudioLowerVolume", "swayosd-client --output-volume lower", { locked = true, repeating = true } },
  { "XF86AudioMute", "swayosd-client --output-volume mute-toggle", { locked = true } },
  { "XF86AudioMicMute", "swayosd-client --input-volume mute-toggle", { locked = true } },
  { "XF86MonBrightnessUp", "swayosd-client --brightness raise", { locked = true, repeating = true } },
  { "XF86MonBrightnessDown", "swayosd-client --brightness lower", { locked = true, repeating = true } },
  { "Caps_Lock", "swayosd-client --caps-lock", { locked = true, release = true } },
  { "XF86AudioNext", "playerctl next", { locked = true } },
  { "XF86AudioPlay", "playerctl play-pause", { locked = true } },
  { "XF86AudioPause", "playerctl play-pause", { locked = true } },
  { "XF86AudioPrev", "playerctl previous", { locked = true } },
}

case("every bind has a non-empty description", function()
  local rec = stub.load_config(NO_COLORS)
  check(#rec.bind > 0, "no binds recorded")
  for _, b in ipairs(rec.bind) do
    local d = b.opts.description
    check(type(d) == "string" and d:match("%S"), "no description: " .. b.keys)
  end
end)

case("no key combination is bound twice", function()
  local rec = stub.load_config(NO_COLORS)
  local seen = {}
  for _, b in ipairs(rec.bind) do
    local c = chord(b.keys)
    check(not seen[c], "bound twice: " .. b.keys .. " (" .. tostring(seen[c]) .. ")")
    seen[c] = b.opts.description
  end
end)

case("bind() errors without a description", function()
  local bind = stub.require_module("hypr.lib.bind")
  for _, desc in ipairs({ false, "", "  " }) do
    local ok, err = pcall(bind, "SUPER + Z", desc or nil, "foot")
    check(not ok, "accepted description " .. tostring(desc))
    check(tostring(err):find("SUPER %+ Z"), "error does not name the keys: " .. tostring(err))
  end
end)

case("bind() runs strings via uwsm-app and passes dispatchers through", function()
  local bind, rec = stub.require_module("hypr.lib.bind")
  local close = hl.dsp.window.close()
  bind("SUPER + A", "Terminal", "foot", { locked = true })
  bind("SUPER + B", "Close", close)
  check(exec_of(rec.bind[1].dispatcher) == "uwsm-app -- foot", "string not wrapped")
  check(rec.bind[1].opts.locked == true, "opts dropped")
  check(rec.bind[1].opts.description == "Terminal", "description not passed")
  check(rec.bind[2].dispatcher == close, "dispatcher not passed through")
end)

case("required binds exist", function()
  local by = binds_by_chord(stub.load_config(NO_COLORS))
  for _, row in ipairs(REQUIRED) do
    local keys, cmd, opts = row[1], row[2], row[3] or {}
    local b = by[chord(keys)]
    check(b, "missing bind: " .. keys)
    local got = exec_of(b.dispatcher)
    check(got == "uwsm-app -- " .. cmd, keys .. ": expected '" .. cmd .. "', got '" .. tostring(got) .. "'")
    for k, v in pairs(opts) do
      check(b.opts[k] == v, keys .. ": option " .. k .. " should be " .. tostring(v))
    end
  end
end)

case("no bind references omarchy", function()
  local rec = stub.load_config(NO_COLORS)
  stub.fire(rec, "hyprland.start")
  local cmds = {}
  for _, b in ipairs(rec.bind) do
    cmds[#cmds + 1] = exec_of(b.dispatcher) -- nil for non-exec dispatchers
  end
  for _, call in ipairs(rec.exec_cmd) do
    table.insert(cmds, call[1])
  end
  for _, cmd in ipairs(cmds) do
    check(not tostring(cmd):lower():find("omarchy"), "references omarchy: " .. tostring(cmd))
  end
end)

local function general(rec)
  local g = {}
  for _, call in ipairs(rec.config) do
    for k, v in pairs(call[1].general or {}) do
      g[k] = v
    end
  end
  return g
end

case("config loads without generated colors.lua", function()
  local rec = stub.load_config(NO_COLORS)
  local g = general(rec)
  check(g.gaps_in == 5 and g.gaps_out == 10, "look not applied")
  check(g.col == nil, "border colours set without a palette")
end)

case("border colours come from colors.lua", function()
  local rec = stub.load_config(FIXTURE_COLORS)
  local col = general(rec).col or {}
  check(col.active_border == "rgb(00000f)", "active border: " .. tostring(col.active_border))
  check(col.inactive_border == "rgb(000004)", "inactive border: " .. tostring(col.inactive_border))
  local bg
  for _, call in ipairs(rec.config) do
    bg = (call[1].misc or {}).background_color or bg
  end
  check(bg == "rgb(000001)", "background: " .. tostring(bg))
end)

case("monitors match spec", function()
  local rec = stub.load_config(NO_COLORS)
  local by = {}
  for _, call in ipairs(rec.monitor) do
    by[call[1].output] = call[1]
  end
  local want = {
    ["DP-1"] = { mode = "5120x1440@120", position = "0x0", scale = 1 },
    ["HDMI-A-1"] = { mode = "3840x2160@60", position = "5120x0", scale = 2 },
    [""] = { mode = "preferred", position = "auto" },
  }
  for output, fields in pairs(want) do
    check(by[output], "no monitor rule for '" .. output .. "'")
    for k, v in pairs(fields) do
      check(by[output][k] == v, output .. " " .. k .. ": " .. tostring(by[output][k]))
    end
  end
end)

case("input uses the gb layout", function()
  local rec = stub.load_config(NO_COLORS)
  local layout
  for _, call in ipairs(rec.config) do
    layout = (call[1].input or {}).kb_layout or layout
  end
  check(layout == "gb", "kb_layout: " .. tostring(layout))
end)

case("autostart launches the session via uwsm-app", function()
  local rec = stub.load_config(NO_COLORS)
  check(#rec.exec_cmd == 0, "commands ran before hyprland.start")
  stub.fire(rec, "hyprland.start")
  local ran = {}
  for _, call in ipairs(rec.exec_cmd) do
    ran[call[1]] = true
  end
  for _, cmd in ipairs({
    "waybar", "swayosd-server", "hyprpaper", "hypridle", "hyprsunset",
    "systemctl --user start hyprpolkitagent",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
  }) do
    check(ran["uwsm-app -- " .. cmd], "not started: " .. cmd)
  end
end)

case("autostart re-applies the dark colour scheme in the session", function()
  local rec = stub.load_config(NO_COLORS)
  stub.fire(rec, "hyprland.start")
  local ran = {}
  for _, call in ipairs(rec.exec_cmd) do
    ran[call[1]] = true
  end
  -- gsettings from bootstrap (in the chroot) hits the memory backend and is lost.
  check(ran["gsettings set org.gnome.desktop.interface color-scheme prefer-dark"], "colour scheme not set")
end)

-- Run one named case, or all of them.
local selected = arg[1] and { arg[1] } or order
local failures = 0
for _, name in ipairs(selected) do
  local fn = cases[name]
  if not fn then
    print("not ok - unknown case: " .. name)
    failures = failures + 1
  else
    local ok, err = pcall(fn)
    if ok then
      print("ok - " .. name)
    else
      print("not ok - " .. name .. ": " .. tostring(err))
      failures = failures + 1
    end
  end
end
os.exit(failures == 0 and 0 or 1)
