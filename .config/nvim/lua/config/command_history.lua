-- An ordinary split, unlike the native command-line window which traps focus.
local M = {}
local api = vim.api

function M.open()
  for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.b[api.nvim_win_get_buf(window)].command_history then
      api.nvim_set_current_win(window)
      return
    end
  end

  local source = api.nvim_get_current_win()
  local buffer = api.nvim_create_buf(false, true)
  vim.b[buffer].command_history = true
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "vim"
  api.nvim_buf_set_name(buffer, "command-history://" .. buffer)

  local lines = {}
  local last = vim.fn.histnr("cmd")
  for index = math.max(1, last - vim.o.history + 1), last do
    local command = vim.fn.histget("cmd", index)
    if command ~= "" then lines[#lines + 1] = command end
  end
  lines[#lines + 1] = ""
  api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  local window = api.nvim_open_win(buffer, true, {
    split = "below", win = -1, height = vim.o.cmdwinheight,
  })
  for option, value in pairs({ diff = false, scrollbind = false, cursorbind = false,
    foldenable = false, winfixheight = true, wrap = false }) do
    vim.wo[window][option] = value
  end
  api.nvim_win_set_cursor(window, { #lines, 0 })

  local function close()
    if #api.nvim_tabpage_list_wins(0) == 1 then
      vim.cmd.bdelete({ bang = true })
    else
      api.nvim_win_close(0, true)
    end
    if api.nvim_win_is_valid(source) then api.nvim_set_current_win(source) end
  end
  local function execute()
    local command = api.nvim_get_current_line()
    vim.cmd.stopinsert()
    close()
    if command:match("%S") then
      -- Use the real command line for native history, errors and Ex semantics.
      api.nvim_feedkeys(":" .. command .. "\r", "nt", true)
    end
  end
  vim.keymap.set("n", "<leader>q", close, { buffer = buffer, desc = "Close command history" })
  vim.keymap.set({ "n", "i" }, "<CR>", execute, { buffer = buffer, desc = "Run command from history" })
end

return M
