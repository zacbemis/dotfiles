-- Owns every background task. Changes are announced as `User TaskChanged`
-- autocommands with `data.id`, so views never poll or touch task internals.
local Task = require("config.tasks.task")

local M = {}
local api = vim.api

---@type table<string, Task> latest task per command line; history deduplicates commands too
local latest = {}
local next_id = 1

local function announce(task)
  api.nvim_exec_autocmds("User", { pattern = "TaskChanged", modeline = false, data = { id = task:id() } })
end

---@param command_line string
---@param shell_command string
---@return Task
function M.start(command_line, shell_command)
  local previous = latest[command_line]
  if previous then
    previous:stop()
    if api.nvim_buf_is_valid(previous:output_buffer()) then
      api.nvim_buf_delete(previous:output_buffer(), { force = true })
    end
  end
  local task = Task.start(next_id, command_line, shell_command, announce)
  next_id = next_id + 1
  latest[command_line] = task
  announce(task)
  return task
end

---@param command_line string
---@return Task?
function M.latest(command_line)
  return latest[command_line]
end

---@param id integer
---@return Task? nil once a newer run of the same command replaced it
function M.get(id)
  for _, task in pairs(latest) do
    if task:id() == id then return task end
  end
end

return M
