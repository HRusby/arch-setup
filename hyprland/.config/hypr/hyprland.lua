-- Hyprland entry point. Loads the sibling modules in ~/.config/hypr.
-- See https://wiki.hypr.land/Configuring/Start/

-- This file's directory, so `require("hypr.x")` finds ~/.config/hypr/x.lua.
local function config_home()
  local xdg = os.getenv("XDG_CONFIG_HOME")
  return (xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")
end

local hypr_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or (config_home() .. "/hypr")
local search = hypr_dir .. "/../?.lua;"
if not package.path:find(search, 1, true) then
  package.path = search .. package.path
end

-- Hyprland keeps one Lua state across reloads: drop our cached modules so a
-- reload picks up edits.
for name in pairs(package.loaded) do
  if name:sub(1, 5) == "hypr." then
    package.loaded[name] = nil
  end
end

require("hypr.env")
require("hypr.monitors")
require("hypr.input")
require("hypr.look")
require("hypr.rules")
require("hypr.binds")
require("hypr.autostart")
