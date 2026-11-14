local M = {}
local api = vim.api

function M.new(model, actions)
  local buffer = api.nvim_create_buf(false, true)
  local window, rows, remembered
  local namespace = api.nvim_create_namespace("GitReviewSidebar")
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "GitReview"
  api.nvim_buf_set_name(buffer, "Git review")
  local sidebar = {}

  function sidebar:current()
    if window and api.nvim_win_is_valid(window) and rows then
      local row = rows[api.nvim_win_get_cursor(window)[1]]
      return row and row.id
    end
  end

  function sidebar:render(selected)
    selected = selected or self:current() or remembered
    rows = model:rows()
    local lines, cursor = {}, 1
    for index, row in ipairs(rows) do
      local marker = row.kind == "file" and (row.status or " ")
        or row.kind == "more" and ">" or (row.expanded and "[-]" or "[+]")
      lines[index] = string.rep("  ", row.depth) .. marker .. " " .. row.label:gsub("[\r\n\t]", " ")
      if row.id == selected then cursor = index end
    end
    vim.bo[buffer].modifiable = true
    api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    for index, row in ipairs(rows) do
      local highlight = row.kind == "file" and "Normal" or row.kind == "more" and "Comment" or "Directory"
      api.nvim_buf_set_extmark(buffer, namespace, index - 1, 0, { end_col = #lines[index], hl_group = highlight })
    end
    if window and api.nvim_win_is_valid(window) then api.nvim_win_set_cursor(window, { cursor, 0 }) end
  end

  function sidebar:remember()
    remembered = self:current()
  end

  function sidebar:attach()
    local selected = self:current() or remembered
    window = api.nvim_open_win(buffer, true, { split = "left", win = -1, width = 32 })
    for option, value in pairs({ number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
      statuscolumn = "", wrap = false, cursorline = true, winfixwidth = true,
      winhighlight = "Normal:NvimTreeNormal,NormalNC:NvimTreeNormalNC,CursorLine:NvimTreeCursorLine,EndOfBuffer:NvimTreeEndOfBuffer" }) do
      vim.wo[window][option] = value
    end
    self:render(selected)
  end

  function sidebar:focus()
    if not self:visible() then self:attach() end
    api.nvim_set_current_win(window)
  end

  function sidebar:visible()
    return window and api.nvim_win_is_valid(window)
  end

  function sidebar:dispose()
    if api.nvim_buf_is_valid(buffer) then api.nvim_buf_delete(buffer, { force = true }) end
  end

  local function navigate(method)
    local id = sidebar:current()
    local selection = model:selection(id)
    if selection and (method == "expand" or method == "drill" or method == "toggle") then
      actions.select(selection)
    else
      sidebar:render(model[method](model, id))
    end
  end

  local function map(key, callback, description)
    vim.keymap.set("n", key, function()
      local ok, err = pcall(callback)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
    end, { buffer = buffer, silent = true, nowait = true, desc = description })
  end
  map("l", function() navigate("expand") end, "Expand / open file")
  map("L", function() navigate("drill") end, "Make section or directory the root / open file")
  map("h", function() navigate("collapse") end, "Collapse / go to parent")
  map("H", function() sidebar:render(model:up()) end, "Return to parent root")
  map("<CR>", function() navigate("toggle") end, "Toggle folder / open file")
  map("<2-LeftMouse>", function() navigate("toggle") end, "Toggle folder / open file")
  map("s", function() actions.stage(sidebar:current()) end, "Stage / unstage selection")
  map("R", function() actions.refresh(true) end, "Refresh Git review")
  map("<leader>q", actions.close, "Close Git review")
  map("<leader>e", function() sidebar:focus() end, "Focus review browser")
  map("g?", function()
    vim.notify("Git review\nl expand/open  L make root  h collapse/parent  H parent root\ns stage/unstage  R refresh  Space q / :q close review")
  end, "Show review controls")
  return sidebar
end

return M
