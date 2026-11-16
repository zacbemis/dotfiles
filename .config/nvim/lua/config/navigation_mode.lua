-- Buffer-local transient mappings, shared by diagnostic and Git navigation.
-- Like Hydra-style submodes, leaving restores the exact previous mappings.
local M = {}
local api = vim.api
local group = api.nvim_create_augroup("PersonalNavigationMode", { clear = true })
local active
local keys = { "n", "N", "<Esc>" }

local function redraw()
  api.nvim_exec_autocmds("User", { pattern = "PersonalNavigationModeChanged", modeline = false })
  vim.cmd.redrawstatus()
end

function M.label()
  return active and (active.name .. " [n/N · Esc]") or ""
end

function M.leave()
  local current = active
  if not current then return end
  active = nil
  api.nvim_clear_autocmds({ group = group })
  if api.nvim_buf_is_valid(current.buf) then
    api.nvim_buf_call(current.buf, function()
      for _, key in ipairs(keys) do
        vim.keymap.del("n", key, { buffer = current.buf })
        local saved = current.saved[key]
        if saved then vim.fn.mapset("n", false, saved) end
      end
    end)
  end
  if current.cleanup then current.cleanup() end
  redraw()
end

function M.enter(spec)
  M.leave()
  local current = { buf = api.nvim_get_current_buf(), name = spec.name, saved = {}, cleanup = spec.cleanup }
  active = current
  for _, key in ipairs(keys) do
    local previous = vim.fn.maparg(key, "n", false, true)
    -- Global mappings are left untouched: deleting our overlay reveals them.
    if previous.buffer == 1 then current.saved[key] = previous end
  end
  local function map(key, action, desc)
    vim.keymap.set("n", key, action, { buffer = current.buf, silent = true, nowait = true, desc = desc })
  end
  local function step(direction)
    local ok, err = pcall(spec.step, direction * vim.v.count1)
    if not ok then
      M.leave()
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
  end
  map("n", function() step(1) end, "Next " .. spec.name)
  map("N", function() step(-1) end, "Previous " .. spec.name)
  map("<Esc>", M.leave, "Exit navigation mode")
  api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertEnter", "BufWipeout" }, {
    group = group, buffer = current.buf, callback = M.leave,
  })
  redraw()
end

return M
