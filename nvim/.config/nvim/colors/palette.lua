-- Colourscheme driven by the theme engine's generated palette.
-- colors.lua returns hex strings without '#'; they are prefixed here.
local path = vim.fn.expand("~/.config/theme/generated/colors.lua")
local ok, raw = pcall(dofile, path)
if not ok or type(raw) ~= "table" then
  vim.notify("palette: cannot load " .. path, vim.log.levels.ERROR)
  return
end

local c = {}
for name, hex in pairs(raw) do
  c[name] = "#" .. hex
end

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.termguicolors = true
vim.o.background = "dark"
vim.g.colors_name = "palette"

local function hl(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

local groups = {
  -- Editor UI
  Normal = { fg = c.fg, bg = c.bg },
  NormalFloat = { fg = c.fg, bg = c.bg1 },
  FloatBorder = { fg = c.grey, bg = c.bg1 },
  Cursor = { fg = c.bg, bg = c.fg },
  CursorLine = { bg = c.bg1 },
  CursorLineNr = { fg = c.accent, bold = true },
  LineNr = { fg = c.bg3 },
  SignColumn = { fg = c.grey, bg = c.bg },
  ColorColumn = { bg = c.bg1 },
  Visual = { bg = c.bg2 },
  Search = { fg = c.bg, bg = c.yellow },
  IncSearch = { fg = c.bg, bg = c.orange },
  MatchParen = { fg = c.accent, bold = true },
  NonText = { fg = c.bg3 },
  Whitespace = { fg = c.bg2 },
  VertSplit = { fg = c.bg2 },
  WinSeparator = { fg = c.bg2 },
  StatusLine = { fg = c.fg, bg = c.bg2 },
  StatusLineNC = { fg = c.fg_dim, bg = c.bg1 },
  Pmenu = { fg = c.fg, bg = c.bg1 },
  PmenuSel = { fg = c.bg, bg = c.accent },
  Folded = { fg = c.grey, bg = c.bg1 },
  Directory = { fg = c.blue },
  Title = { fg = c.accent, bold = true },
  ErrorMsg = { fg = c.red, bold = true },
  WarningMsg = { fg = c.yellow },
  -- Syntax
  Comment = { fg = c.grey, italic = true },
  Constant = { fg = c.purple },
  String = { fg = c.green },
  Number = { fg = c.purple },
  Boolean = { fg = c.purple },
  Identifier = { fg = c.blue },
  Function = { fg = c.aqua },
  Statement = { fg = c.red },
  Keyword = { fg = c.red },
  Operator = { fg = c.orange },
  PreProc = { fg = c.aqua },
  Type = { fg = c.yellow },
  Special = { fg = c.orange },
  Delimiter = { fg = c.fg_dim },
  Todo = { fg = c.bg, bg = c.yellow, bold = true },
  -- Diagnostics
  DiagnosticError = { fg = c.red },
  DiagnosticWarn = { fg = c.yellow },
  DiagnosticInfo = { fg = c.blue },
  DiagnosticHint = { fg = c.aqua },
  DiagnosticUnderlineError = { undercurl = true, sp = c.red },
  DiagnosticUnderlineWarn = { undercurl = true, sp = c.yellow },
  -- Diff
  DiffAdd = { bg = c.bg1, fg = c.green },
  DiffChange = { bg = c.bg1, fg = c.yellow },
  DiffDelete = { bg = c.bg1, fg = c.red },
  DiffText = { bg = c.bg2, fg = c.yellow, bold = true },
  Added = { fg = c.green },
  Changed = { fg = c.yellow },
  Removed = { fg = c.red },
}

for group, spec in pairs(groups) do
  hl(group, spec)
end
