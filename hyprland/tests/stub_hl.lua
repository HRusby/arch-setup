-- A fake global `hl` that records every config call, so the Hyprland Lua
-- config can be loaded and inspected outside Hyprland.
--
--   local stub = dofile("tests/stub_hl.lua")
--   local rec = stub.load_config({ XDG_CONFIG_HOME = "/nonexistent" })
--   rec.bind[1] --> { keys = "SUPER + W", dispatcher = {...}, opts = {...} }
--
-- Dispatchers record themselves: hl.dsp.window.close() returns
-- { dsp = "window.close", args = {} }, hl.dsp.exec_cmd("foot") returns
-- { dsp = "exec_cmd", args = { "foot" } }. Any other hl.* name errors, so the
-- config only uses the API surface listed here.

local M = {}

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
M.module_dir = here .. "/../.config/hypr"
M.entry = M.module_dir .. "/hyprland.lua"

-- dispatcher proxy: indexing extends the path, calling records it.
local function dsp_proxy(path)
  return setmetatable({}, {
    __index = function(_, name)
      return dsp_proxy(path == "" and name or path .. "." .. name)
    end,
    __call = function(_, ...)
      return { dsp = path, args = { ... } }
    end,
  })
end

local RECORDED = {
  "bind", "config", "monitor", "env", "exec_cmd", "window_rule", "layer_rule",
  "workspace_rule", "curve", "animation", "dispatch", "timer",
}

-- install() — fresh global `hl`; returns the recorder its calls land in.
function M.install()
  local rec = { on = {} }
  local api = {}

  for _, name in ipairs(RECORDED) do
    rec[name] = {}
    api[name] = function(...)
      table.insert(rec[name], { ... })
    end
  end

  api.bind = function(keys, dispatcher, opts)
    table.insert(rec.bind, { keys = keys, dispatcher = dispatcher, opts = opts or {} })
  end

  api.on = function(event, fn)
    rec.on[event] = rec.on[event] or {}
    table.insert(rec.on[event], fn)
  end

  -- Runtime queries only run inside bind callbacks, never at load.
  for _, name in ipairs({ "get_active_window", "get_windows", "get_config" }) do
    api[name] = function() return nil end
  end

  api.dsp = dsp_proxy("")

  _G.hl = setmetatable(api, {
    __index = function(_, name)
      error("stub hl has no '" .. tostring(name) .. "'", 2)
    end,
  })

  return rec
end

-- fire(rec, event) — run the handlers the config registered for an event.
function M.fire(rec, event, ...)
  for _, fn in ipairs(rec.on[event] or {}) do
    fn(...)
  end
end

-- with_env(env, fn) — run fn with os.getenv answering from env first.
function M.with_env(env, fn)
  local real = os.getenv
  os.getenv = function(name)
    if env[name] ~= nil then
      return env[name] ~= false and env[name] or nil
    end
    return real(name)
  end
  local ok, err = pcall(fn)
  os.getenv = real
  if not ok then
    error(err, 0)
  end
end

-- load_config(env) — install hl, load the entry file under env, return the recorder.
function M.load_config(env)
  local rec = M.install()
  M.with_env(env or {}, function()
    dofile(M.entry)
  end)
  return rec
end

-- require_module(name) — install hl and load one module (e.g. "hypr.lib.bind").
function M.require_module(name)
  local rec = M.install()
  local config_dir = M.module_dir .. "/.."
  package.path = config_dir .. "/?.lua;" .. package.path
  package.loaded[name] = nil
  return require(name), rec
end

return M
