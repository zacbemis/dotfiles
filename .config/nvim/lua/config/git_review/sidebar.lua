local M = {}
local api = vim.api

function M.new(model, actions)
  require("config.git_review.style").setup()
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

  function sidebar:focused()
    return self:visible() and api.nvim_get_current_win() == window
  end

  function sidebar:context()
    return model:context(self:current())
  end

  function sidebar:render(selected)
    selected = selected or self:current() or remembered
    rows = model:rows()
    local lines, highlights = require("config.git_review.sidebar_render").rows(rows)
    local cursor = 1
    for index, row in ipairs(rows) do
      if row.id == selected then cursor = index end
    end
    vim.bo[buffer].modifiable = true
    api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    for _, span in ipairs(highlights) do
      api.nvim_buf_set_extmark(buffer, namespace, span.row, span.start, {
        end_col = span.finish, hl_group = span.group,
      })
    end
    remembered = rows[cursor] and rows[cursor].id
    if window and api.nvim_win_is_valid(window) then api.nvim_win_set_cursor(window, { cursor, 0 }) end
    actions.context_changed()
  end

  function sidebar:set_model(next_model)
    model = next_model
    self:render(model:rows()[1].id)
  end

  function sidebar:remember()
    remembered = self:current() or remembered
  end

  function sidebar:attach()
    local selected = self:current() or remembered
    window = api.nvim_open_win(buffer, true, { split = "left", win = -1, width = 32 })
    for option, value in pairs({ number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
      statuscolumn = "", wrap = false, cursorline = true, cursorlineopt = "line", winfixwidth = true,
      list = false, spell = false, colorcolumn = "", fillchars = "eob: ",
      winhighlight = "Normal:GitReviewNormal,NormalNC:GitReviewNormalNC,CursorLine:GitReviewCursorLine,EndOfBuffer:GitReviewEndOfBuffer,WinSeparator:GitReviewWinSeparator" }) do
      vim.wo[window][option] = value
    end
    self:render(selected)
  end

  function sidebar:focus()
    if not self:visible() then self:attach() end
    api.nvim_set_current_win(window)
  end

  function sidebar:hide()
    if not self:visible() then return end
    self:remember()
    api.nvim_win_close(window, true)
    window = nil
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
  map("L", function() navigate("drill") end, "Make branch, section or commit the root / open file")
  map("h", function() navigate("collapse") end, "Collapse / go to parent")
  map("H", function() sidebar:render(model:up()) end, "Return to parent root")
  map("<CR>", function() navigate("toggle") end, "Toggle folder / open file")
  map("<2-LeftMouse>", function() navigate("toggle") end, "Toggle folder / open file")
  map("s", function() actions.stage(sidebar:current()) end, "Stage / unstage selection")
  if actions.switch then
    map("gS", function() actions.switch(sidebar:current()) end, "Switch local branch / open worktree in a new window")
  end
  map("R", function() actions.refresh(true) end, "Refresh Git review")
  map("<leader>q", actions.close, "Close Git review")
  map("<leader>e", actions.toggle_sidebar, "Toggle review browser")
  map("g?", function()
    vim.notify("Git branches and worktrees\nl expand/open  L make root  h collapse/parent  H parent root / branch list\ns stage/unstage  gS switch branch / open worktree window  R refresh  Space e toggle sidebar\nH/L collapse/open context in diff panes  Space q close review  :q close window")
  end, "Show review controls")
  return sidebar
end

return M
