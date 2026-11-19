local M = {}
local api = vim.api
local repository = require("config.git_review.repository")
local renderer = require("config.git_review.diffview")
local tree = require("config.git_review.tree")
local session

local function notify(message)
  vim.notify(tostring(message), vim.log.levels.ERROR)
end

local function comparison(selection)
  return table.concat({ selection.root, selection.kind, selection.hash or "", selection.path or "",
    selection.branch_name or "", selection.author or "", selection.id or "" }, "\0")
end

local function dispose(current)
  if current.timer then current.timer:stop(); current.timer:close() end
  api.nvim_clear_autocmds({ group = current.group })
  current.header:hide()
  current.sidebar:dispose()
  if session == current then session = nil end
end

local function update_header(current)
  if session ~= current or current.phase ~= "ready" or api.nvim_get_current_tabpage() ~= current.tab then return end
  local context = current.sidebar:focused() and current.sidebar:context() or nil
  current.header:update(current.tab, context or current.selection)
end

local function show_comparison(current, selection, refresh)
  if current.selection.root == selection.root then
    renderer.select(current.tab, selection, refresh)
    return
  end
  -- Diffview owns a Git adapter and index watcher per view. Open the new
  -- worktree before retiring the old one so a failed open leaves it usable.
  local previous, visible = current.tab, current.sidebar:visible()
  current.tab = renderer.open(selection)
  renderer.close(previous)
  api.nvim_set_current_tabpage(current.tab)
  if visible then current.sidebar:attach() end
end

local function update_comparison(current, resolve, refresh)
  current.phase = "switching"
  current.sidebar:remember()
  local ok, selection, cursor = pcall(resolve)
  if ok then
    local updated, err = pcall(show_comparison, current, selection, refresh)
    if not updated then ok, selection = false, err end
  end
  current.phase = "ready"
  if not ok then notify(selection); return false end
  current.selection = selection
  if cursor then current.sidebar:render(cursor) end
  update_header(current)
  return true
end

function M.select(selection, focus_file, refresh)
  local current = session
  if not current or current.phase ~= "ready" then return end
  local allowed, reason = renderer.can_leave(current.tab)
  if not allowed then notify(reason); return end
  if (refresh or comparison(selection) ~= comparison(current.selection))
    and not update_comparison(current, function() return selection end, refresh) then return end
  if focus_file ~= false then renderer.focus_file(current.tab) else current.sidebar:focus() end
  update_header(current)
end

function M.refresh(force)
  local current = session
  if not current or current.phase ~= "ready" or api.nvim_get_current_tabpage() ~= current.tab then return end
  local changed = current.model:refresh()
  if changed or force then
    local window = api.nvim_get_current_win()
    local in_sidebar = vim.bo.filetype == "GitReview"
    current.sidebar:render()
    local selection = current.model:selection(current.selection.id)
      or current.model:initial_selection(current.selection.branch_id)
    M.select(selection, not in_sidebar, true)
    if api.nvim_win_is_valid(window) then api.nvim_set_current_win(window) end
    update_header(current)
  end
end

function M.stage(id)
  local current = session
  if not current or current.phase ~= "ready" then return end
  if not current.model:can_stage(id) then
    notify("Committed history is read-only; select an unstaged or staged file.")
    return
  end
  local allowed, reason = renderer.can_leave(current.tab)
  if not allowed then notify(reason); return end
  update_comparison(current, function()
    local destination = current.model:stage(id)
    return current.model:selection(destination) or current.model:initial_selection(destination), destination
  end, true)
end

local function reload_after_checkout(current)
  local model = tree.new(current.root, repository)
  if update_comparison(current, function() return model:initial_selection() end, true) then
    current.model = model
    current.sidebar:set_model(model)
  end
end

function M.switch(id)
  local current = session
  if not M.is_active() then return end
  local target = current.model:switch_target(id)
  if target.current then return end
  if target.worktree then
    require("config.workspace_window").open(target.worktree)
    return
  end
  local allowed, reason = renderer.can_leave(current.tab)
  if not allowed then notify(reason); return end
  for _, buffer in ipairs(api.nvim_list_bufs()) do
    local path = api.nvim_buf_get_name(buffer)
    if vim.bo[buffer].buftype == "" and vim.bo[buffer].modified and path ~= ""
      and vim.fs.relpath(current.root, path) then
      notify("Save or close modified files in this worktree before switching branches.")
      return
    end
  end
  current.phase = "checking_out"
  local started, err = pcall(repository.switch, current.root, target.name, function(ok, message)
    if session == current then current.phase = "ready" end
    if ok then
      local checked, failure = pcall(vim.cmd.checktime)
      if not checked then notify(failure) end
    end
    if session ~= current then return end
    if not ok then notify(message ~= "" and message or "Could not switch branches."); return end
    local window = api.nvim_get_current_win()
    local updated, failure = pcall(reload_after_checkout, current)
    if api.nvim_win_is_valid(window) then api.nvim_set_current_win(window) end
    if not updated then notify(failure) end
  end)
  if not started then current.phase = "ready"; notify(err) end
end

function M.matching_rows(matches)
  return M.is_active() and session.sidebar:matching_rows(matches) or {}
end

function M.focus_sidebar()
  if session and session.phase == "ready" then
    api.nvim_set_current_tabpage(session.tab)
    session.sidebar:focus()
    update_header(session)
  end
end

function M.is_active()
  return session ~= nil and session.phase == "ready" and api.nvim_get_current_tabpage() == session.tab
end

function M.fold(open)
  if not M.is_active() then return false end
  renderer.fold(session.tab, open)
  return true
end

function M.toggle_sidebar()
  local current = session
  if not M.is_active() then return false end
  if current.sidebar:visible() then
    local focused = vim.bo.filetype == "GitReview"
    current.sidebar:hide()
    if focused then renderer.focus_file(current.tab) end
  else
    current.sidebar:focus()
  end
  update_header(current)
  return true
end

function M.close()
  local current = session
  if not current or current.phase == "closing" then return true end
  if current.phase == "checking_out" then
    local reason = "Wait for the branch switch to finish."
    notify(reason)
    return false, reason
  end
  local allowed, reason = renderer.can_leave(current.tab)
  if not allowed then notify(reason); return false, reason end
  current.phase = "closing"
  renderer.close(current.tab)
  dispose(current)
  if api.nvim_win_is_valid(current.origin_window) then api.nvim_set_current_win(current.origin_window)
  elseif api.nvim_tabpage_is_valid(current.origin_tab) then api.nvim_set_current_tabpage(current.origin_tab) end
  return true
end

function M.on_view_closed(tab)
  renderer.closed(tab)
  if session and session.tab == tab and (session.phase == "ready" or session.phase == "checking_out") then
    dispose(session)
  end
end

local function directory()
  if vim.bo.filetype == "NvimTree" then
    local node = require("nvim-tree.api").tree.get_node_under_cursor()
    if node then return node.type == "directory" and node.absolute_path or vim.fs.dirname(node.absolute_path) end
  end
  local name = api.nvim_buf_get_name(0)
  return vim.bo.buftype == "" and name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
end

function M.open()
  if session then M.focus_sidebar(); return end
  local ok, root = pcall(repository.root, directory())
  if not ok then notify(root); return end
  local model_ok, model = pcall(tree.new, root, repository)
  if not model_ok then notify(model); return end
  local current = { phase = "opening", model = model, root = root,
    origin_tab = api.nvim_get_current_tabpage(), origin_window = api.nvim_get_current_win(),
    group = api.nvim_create_augroup("GitReviewSession", { clear = true }) }
  current.header = require("config.git_review.header").new(current.group)
  current.sidebar = require("config.git_review.sidebar").new(model, {
    select = M.select, stage = M.stage, switch = M.switch, refresh = M.refresh, close = M.close,
    toggle_sidebar = M.toggle_sidebar,
    context_changed = function() update_header(current) end,
  })
  current.selection = model:initial_selection()
  session = current
  local opened, tab = pcall(renderer.open, current.selection)
  if not opened then dispose(current); notify(tab); return end
  current.tab = tab
  current.header:update(tab, current.selection)
  current.sidebar:attach()
  current.phase = "ready"
  update_header(current)
  api.nvim_create_autocmd({ "WinEnter", "TabEnter", "CursorMoved" }, {
    group = current.group,
    callback = function(event)
      if event.event ~= "CursorMoved" or current.sidebar:focused() then update_header(current) end
    end,
  })
  api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
    group = current.group,
    callback = function() vim.schedule(function() if session == current then M.refresh() end end) end,
  })
  current.timer = assert(vim.uv.new_timer())
  current.timer:start(1500, 1500, vim.schedule_wrap(function()
    if session ~= current then return end
    local refreshed, err = pcall(M.refresh)
    if not refreshed then current.timer:stop(); notify(err) end
  end))
end

return M
