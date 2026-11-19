local M = {}

local function duration(seconds)
  if seconds < 60 then return ("%.1fs"):format(seconds) end
  if seconds < 3600 then return ("%dm"):format(math.floor(seconds / 60)) end
  return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

---@param task Task
---@return string text, string highlight
function M.describe(task)
  local state, elapsed = task:state(), duration(task:elapsed())
  if state.kind == "running" then
    return "● running since " .. os.date("%H:%M", task:started_at()), "DiagnosticInfo"
  end
  if state.kind == "stopping" then return "● stopping", "Comment" end
  if state.kind == "killed" then return "■ stopped after " .. elapsed, "Comment" end
  if state.code == 0 then return "✓ " .. elapsed, "DiagnosticOk" end
  return ("✗ exit %d · %s"):format(state.code, elapsed), "DiagnosticError"
end

return M
