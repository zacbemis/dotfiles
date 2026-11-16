-- Interactive :q/:quit mean quit-all; keep Neovim's native unsaved-buffer checks.
-- An expression abbreviation leaves plugin/programmatic :quit commands alone.
local M = {}

function M.expand(command)
  if vim.fn.getcmdtype() ~= ":" or vim.fn.getcmdpos() ~= #vim.fn.getcmdline() + 1 then return command end
  local ok, parsed = pcall(vim.api.nvim_parse_cmd, vim.fn.getcmdline(), {})
  if ok and parsed.cmd == "quit" then return "qall" end
  return command
end

function M.setup()
  for _, command in ipairs({ "q", "qu", "qui", "quit" }) do
    vim.cmd(("cnoreabbrev <expr> %s v:lua.require'config.quit'.expand('%s')"):format(command, command))
  end
end

return M
