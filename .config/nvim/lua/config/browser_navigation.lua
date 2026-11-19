local M = {}
local api = vim.api
local mode = require("config.navigation_mode")

local function explorer_rows(matches)
  local root = require("nvim-tree.api").tree.get_nodes()
  local rows, index = {}, 0
  local function visit(directory)
    for _, node in ipairs(directory.nodes or {}) do
      if not node.hidden then
        index = index + 1
        if node.nodes then
          if node.open then visit(node) end
        elseif matches(node.absolute_path, node.git_status and node.git_status.file) then
          rows[#rows + 1] = index
        end
      end
    end
  end
  if root then visit(root) end
  -- nvim-tree can prepend a root label and a live-filter banner.
  local offset = api.nvim_buf_line_count(0) - index
  for i, row in ipairs(rows) do rows[i] = row + offset end
  return rows
end

local function diagnostic_match(severity)
  local paths = {}
  for _, diagnostic in ipairs(vim.diagnostic.get(nil, { severity = severity })) do
    local path = api.nvim_buf_get_name(diagnostic.bufnr)
    if path ~= "" and vim.bo[diagnostic.bufnr].buftype == "" then paths[path] = true end
  end
  return function(path) return paths[path] == true end
end

function M.start(kind)
  local filetype = vim.bo.filetype
  if filetype ~= "NvimTree" and filetype ~= "GitReview" then return false end
  local name = ({ git = "Changed files", diagnostic = "Files with diagnostics", error = "Files with errors" })[kind]
  local function matches()
    local predicate = kind == "git" and function(_, status) return status and status ~= "!!" and status ~= " " end
      or diagnostic_match(kind == "error" and vim.diagnostic.severity.ERROR or nil)
    if filetype == "NvimTree" then return explorer_rows(predicate) end
    return require("config.git_review").matching_rows(predicate)
  end
  local function move(row) api.nvim_win_set_cursor(0, { row, 0 }) end
  local rows = matches()
  if #rows == 0 then
    vim.notify("No visible " .. name:lower() .. " in this browser.", vim.log.levels.INFO)
    return true
  end
  local initial = api.nvim_win_get_cursor(0)[1]
  local nearest = rows[1]
  for _, row in ipairs(rows) do
    if math.abs(row - initial) <= math.abs(nearest - initial) then nearest = row end
  end
  move(nearest)
  mode.enter({ name = name, step = function(count)
    local current = api.nvim_win_get_cursor(0)[1]
    local candidates = matches()
    if #candidates == 0 then
      mode.leave()
      vim.notify("No visible " .. name:lower() .. " in this browser.", vim.log.levels.INFO)
      return
    end
    local before, through = 0, 0
    for _, row in ipairs(candidates) do
      if row < current then before = before + 1 end
      if row <= current then through = through + 1 end
    end
    local index = (count > 0 and through or before + 1) + count
    move(candidates[(index - 1) % #candidates + 1])
  end })
  return true
end

return M
