local M = {}
local api = vim.api
local mode = require("config.navigation_mode")
local browser = require("config.browser_navigation")

function M.diagnostics(errors_only)
  mode.leave()
  if browser.start(errors_only and "error" or "diagnostic") then return end
  local severity = errors_only and vim.diagnostic.severity.ERROR or nil
  local name = errors_only and "Errors" or "Diagnostics"
  if #vim.diagnostic.get(0, { severity = severity }) == 0 then
    vim.notify("No " .. name:lower() .. " in this buffer.", vim.log.levels.INFO)
    return
  end
  local float
  local active, request = true, 0
  local buffer, window = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local function close_float()
    if float and api.nvim_win_is_valid(float) then api.nvim_win_close(float, true) end
    float = nil
  end
  local function show()
    close_float()
    float = select(2, vim.diagnostic.open_float({ scope = "line", severity = severity, focusable = false }))
  end
  local function step(count)
    close_float()
    vim.diagnostic.jump({ count = count, severity = severity, float = false, wrap = true })
    request = request + 1
    local current_request, position = request, api.nvim_win_get_cursor(window)
    -- Like Neovim's on_jump callback, open only after the jump's CursorMoved
    -- event. Opening immediately lets that event close the brand-new popup.
    vim.schedule(function()
      if active and request == current_request and api.nvim_get_current_win() == window
        and api.nvim_get_current_buf() == buffer
        and vim.deep_equal(api.nvim_win_get_cursor(window), position) then
        show()
      end
    end)
  end
  mode.enter({ name = name, step = step, cleanup = function()
    active = false -- Cancel queued popups when exiting or switching modes.
    close_float()
  end })
  -- Preserve Space-cd's line popup when already on a diagnostic; otherwise
  -- select the next item so entering the mode always gives useful feedback.
  local line = api.nvim_win_get_cursor(0)[1] - 1
  if #vim.diagnostic.get(0, { lnum = line, severity = severity }) > 0 then show() else step(1) end
end

function M.git()
  mode.leave()
  if browser.start("git") then return end
  local step
  if vim.wo.diff then
    -- Diffview revision buffers need native diff navigation, not Gitsigns.
    step = function(count)
      vim.cmd.normal({ math.abs(count) .. (count > 0 and "]c" or "[c"), bang = true })
    end
  else
    local ok, gs = pcall(require, "gitsigns")
    local hunks = ok and gs.get_hunks(0)
    if not hunks or #hunks == 0 then
      vim.notify("No Git hunks in this buffer (or Git signs are not ready yet).", vim.log.levels.INFO)
      return
    end
    step = function(count)
      gs.nav_hunk(count > 0 and "next" or "prev", { count = math.abs(count), wrap = true })
    end
  end
  mode.enter({ name = "Git hunks", step = step })
end

return M
