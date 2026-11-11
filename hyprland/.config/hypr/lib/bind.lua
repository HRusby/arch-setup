-- bind(keys, description, action, opts)
--   description  required: the keybinds menu lists it.
--   action       a string runs as an app via `uwsm-app -- <action>`; anything
--                else (hl.dsp.* dispatcher, Lua function) is passed through.
--   opts         extra hl.bind options (locked, repeating, mouse, release, ...).

return function(keys, description, action, opts)
  if type(description) ~= "string" or not description:match("%S") then
    error("bind " .. tostring(keys) .. ": description required", 2)
  end

  local options = { description = description }
  for k, v in pairs(opts or {}) do
    options[k] = v
  end

  if type(action) == "string" then
    action = hl.dsp.exec_cmd("uwsm-app -- " .. action)
  end

  hl.bind(keys, action, options)
end
