local api = vim.api

---@alias TaskState
---| { kind: "running" }
---| { kind: "stopping" }
---| { kind: "exited", code: integer }
---| { kind: "killed" }

---@class Task
---@field private _id integer
---@field private _command_line string
---@field private _cwd string
---@field private _buffer integer
---@field private _job integer
---@field private _state TaskState
---@field private _started integer
---@field private _started_at integer
---@field private _finished integer?
local Task = {}
Task.__index = Task

---@param id integer
---@param command_line string Ex command as typed, used to match command history.
---@param shell_command string
---@param on_change fun(task: Task)
---@return Task
function Task.start(id, command_line, shell_command, on_change)
  local self = setmetatable({
    _id = id,
    _command_line = command_line,
    _cwd = vim.fn.getcwd(),
    _buffer = api.nvim_create_buf(false, true),
    _state = { kind = "running" },
    _started = vim.uv.hrtime(),
    _started_at = os.time(),
  }, Task)
  vim.bo[self._buffer].bufhidden = "hide"

  -- jobstart(term=true) turns the current buffer into the terminal, so start it
  -- inside the hidden buffer; the output stays alive without occupying a window.
  api.nvim_buf_call(self._buffer, function()
    self._job = vim.fn.jobstart(shell_command, {
      term = true,
      cwd = self._cwd,
      on_exit = function(_, code)
        self._finished = vim.uv.hrtime()
        self._state = self._state.kind == "stopping" and { kind = "killed" }
          or { kind = "exited", code = code }
        on_change(self)
      end,
    })
  end)
  vim.bo[self._buffer].buflisted = false
  if self._job <= 0 then
    self._finished = self._started
    self._state = { kind = "exited", code = 127 }
  end
  return self
end

function Task:id() return self._id end
function Task:command_line() return self._command_line end
function Task:cwd() return self._cwd end
function Task:output_buffer() return self._buffer end
function Task:state() return vim.deepcopy(self._state) end
function Task:started_at() return self._started_at end

function Task:is_running()
  return self._state.kind == "running" or self._state.kind == "stopping"
end

---@return number seconds
function Task:elapsed()
  return ((self._finished or vim.uv.hrtime()) - self._started) / 1e9
end

function Task:stop()
  if self._state.kind ~= "running" then return end
  self._state = { kind = "stopping" }
  vim.fn.jobstop(self._job)
end

return Task
