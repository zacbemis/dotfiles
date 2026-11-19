-- `:!cmd` front-end: runs the command as a background task instead of Neovim's
-- blocking shell call. Ranged filters such as `:'<,'>!sort` stay native.
local tasks = require("config.tasks")
local status = require("config.tasks.status")

local M = {}
local api = vim.api

---@type string? the previous shell command, for `:!!`
local last_command

---@return string? command_line, string? command
local function parse(line)
  local command_line = line:gsub("^[%s:]+", ""):gsub("%s+$", "")
  local command = command_line:match("^!(.*%S)")
  if not command then return end
  if command:sub(1, 1) == "!" then
    if not last_command then return end
    command = last_command .. command:sub(2)
    command_line = "!" .. command
  end
  return command_line, command
end

-- Native :! expands only file-name tokens and keeps other backslashes for the
-- shell; expandcmd() would strip them (printf 'a\n' -> printf 'an').
---@return string? expanded, string? error
local function expand(command)
  local parts, index = {}, 1
  while index <= #command do
    local escaped = command:match("^\\[%%#]", index)
    local token = command:match("^[%%#]%d*", index) or command:match("^<c%a+>", index)
    if escaped then
      parts[#parts + 1] = escaped:sub(2)
      index = index + 2
    elseif token then
      local finish = index + #token
      while command:match("^:[phtre~.]", finish) do finish = finish + 2 end
      token = command:sub(index, finish - 1)
      local value = vim.fn.expand(token)
      if value == "" then return nil, "E499: Empty file name for '%' or '#': " .. token end
      parts[#parts + 1] = value
      index = finish
    else
      parts[#parts + 1] = command:sub(index, index)
      index = index + 1
    end
  end
  return table.concat(parts)
end

---@param line string an Ex command line
---@return boolean
function M.accepts(line)
  return parse(line) ~= nil
end

---@param line string an Ex command line
---@return boolean handled false when the line is not a plain `:!cmd`
function M.run(line)
  local command_line, command = parse(line)
  if not command_line then return false end
  vim.fn.histadd("cmd", command_line)
  last_command = command
  local expanded, problem = expand(command)
  if not expanded then
    api.nvim_echo({ { problem } }, true, { err = true })
    return true
  end

  local previous = tasks.latest(command_line)
  if previous and previous:is_running()
    and vim.fn.confirm(command_line .. " is still running.", "&Restart\n&Cancel", 2) ~= 1 then
    return true
  end
  tasks.start(command_line, expanded)
  api.nvim_echo({ { command_line, "Normal" }, { "  running in background", "Comment" } }, false, {})
  return true
end

api.nvim_create_autocmd("User", {
  group = api.nvim_create_augroup("config.tasks.shell_command", {}),
  pattern = "TaskChanged",
  callback = function(event)
    local task = tasks.get(event.data.id)
    if not task or task:state().kind ~= "exited" then return end
    local text = status.describe(task)
    local failed = task:state().code ~= 0
    vim.notify(task:command_line() .. "  " .. text, failed and vim.log.levels.ERROR or vim.log.levels.INFO)
  end,
})

return M
