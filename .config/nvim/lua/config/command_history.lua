-- An ordinary split, unlike the native command-line window which traps focus.
local tasks = require("config.tasks")
local task_status = require("config.tasks.status")
local shell_command = require("config.tasks.shell_command")

local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace("config.command_history")

local function task_on_line(buffer, row)
  local line = api.nvim_buf_get_lines(buffer, row - 1, row, false)[1] or ""
  return tasks.latest(vim.trim(line))
end

local function annotate(buffer)
  if not api.nvim_buf_is_valid(buffer) then return end
  api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  for row, line in ipairs(api.nvim_buf_get_lines(buffer, 0, -1, false)) do
    local task = line:find("^%s*!") and tasks.latest(vim.trim(line))
    if task then
      local text, highlight = task_status.describe(task)
      api.nvim_buf_set_extmark(buffer, namespace, row - 1, 0, {
        virt_text = { { "  " .. text, highlight } }, virt_text_pos = "eol",
      })
    end
  end
end

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
  annotate(buffer)
  local group = api.nvim_create_augroup("config.command_history." .. buffer, {})
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group, buffer = buffer, callback = function() annotate(buffer) end,
  })
  api.nvim_create_autocmd("User", {
    group = group, pattern = "TaskChanged", callback = function() annotate(buffer) end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group, buffer = buffer, callback = function() api.nvim_del_augroup_by_id(group) end,
  })

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
    if shell_command.run(command) then return end
    if command:match("%S") then
      -- Use the real command line for native history, errors and Ex semantics.
      api.nvim_feedkeys(":" .. command .. "\r", "nt", true)
    end
  end
  local function open_output()
    local task = task_on_line(buffer, api.nvim_win_get_cursor(0)[1])
    if not task then
      api.nvim_echo({ { "No background task for this command", "WarningMsg" } }, false, {})
      return
    end
    local output = task:output_buffer()
    close()
    local output_window = api.nvim_open_win(output, true, {
      split = "below", win = -1, height = vim.o.cmdwinheight,
    })
    -- Terminal buffers pad below the output with blank rows; land on the last output line.
    local last = api.nvim_buf_line_count(output)
    while last > 1 and api.nvim_buf_get_lines(output, last - 1, last, false)[1] == "" do last = last - 1 end
    api.nvim_win_set_cursor(output_window, { last, 0 })
    -- The global Space q deletes the buffer, which would discard the task's output.
    vim.keymap.set("n", "<leader>q", function() api.nvim_win_close(0, false) end,
      { buffer = output, desc = "Close command output" })
  end
  vim.keymap.set("n", "go", open_output, { buffer = buffer, desc = "Open command output" })
  vim.keymap.set("n", "<leader>q", close, { buffer = buffer, desc = "Close command history" })
  vim.keymap.set({ "n", "i" }, "<CR>", execute, { buffer = buffer, desc = "Run command from history" })
end

return M
