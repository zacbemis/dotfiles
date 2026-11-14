local M = {}
local api = vim.api
local repository = require("config.git_review.repository")
local renderer = require("config.git_review.diffview")
local session

local function notify(message)
  vim.notify(tostring(message), vim.log.levels.ERROR)
end

local function comparison(selection)
  return table.concat({ selection.kind, selection.hash or "", selection.path or "" }, "\0")
end

local function dispose(current)
  if current.timer then current.timer:stop(); current.timer:close() end
  api.nvim_clear_autocmds({ group = current.group })
  current.sidebar:dispose()
  if session == current then session = nil end
end

local function replace_comparison(current, resolve)
  current.phase = "switching"
  current.sidebar:remember()
  renderer.close(current.tab)
  local resolved, selection, cursor = pcall(resolve)
  if not resolved then dispose(current); notify(selection); return false end
  local opened, tab = pcall(renderer.open, selection)
  if not opened then dispose(current); notify(tab); return false end
  current.tab, current.selection = tab, selection
  current.sidebar:attach()
  if cursor then current.sidebar:render(cursor) end
  current.phase = "ready"
  return true
end

function M.select(selection, focus_file)
  local current = session
  if not current or current.phase ~= "ready" then return end
  local allowed, reason = renderer.can_leave(current.tab)
  if not allowed then notify(reason); return end
  if comparison(selection) ~= comparison(current.selection)
    and not replace_comparison(current, function() return selection end) then return end
  if focus_file ~= false then renderer.focus_file(current.tab) else current.sidebar:focus() end
end

function M.refresh(force)
  local current = session
  if not current or current.phase ~= "ready" or api.nvim_get_current_tabpage() ~= current.tab then return end
  local changed = current.model:refresh()
  if changed then
    local window = api.nvim_get_current_win()
    local in_sidebar = vim.bo.filetype == "GitReview"
    current.sidebar:render()
    local selection = current.model:selection(current.selection.id) or current.model:initial_selection()
    M.select(selection, not in_sidebar)
    if api.nvim_win_is_valid(window) then api.nvim_set_current_win(window) end
  end
  if force and session == current then vim.cmd.DiffviewRefresh() end
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
  replace_comparison(current, function()
    local destination = current.model:stage(id)
    return current.model:selection(destination) or current.model:initial_selection(), destination
  end)
end

function M.focus_sidebar()
  if session and session.phase == "ready" then
    api.nvim_set_current_tabpage(session.tab)
    session.sidebar:focus()
  end
end

function M.close()
  local current = session
  if not current or current.phase == "closing" then return true end
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
  if session and session.tab == tab and session.phase == "ready" then dispose(session) end
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
  local model_ok, model = pcall(require("config.git_review.tree").new, root, repository)
  if not model_ok then notify(model); return end
  local current = { phase = "opening", model = model,
    origin_tab = api.nvim_get_current_tabpage(), origin_window = api.nvim_get_current_win(),
    group = api.nvim_create_augroup("GitReviewSession", { clear = true }) }
  current.sidebar = require("config.git_review.sidebar").new(model, {
    select = M.select, stage = M.stage, refresh = M.refresh, close = M.close,
  })
  current.selection = model:initial_selection()
  session = current
  local opened, tab = pcall(renderer.open, current.selection)
  if not opened then dispose(current); notify(tab); return end
  current.tab = tab
  current.sidebar:attach()
  current.phase = "ready"
  api.nvim_create_autocmd("QuitPre", {
    group = current.group,
    callback = function()
      if session == current and api.nvim_get_current_tabpage() == current.tab then
        local closed, reason = M.close()
        if not closed then error(reason, 0) end
      end
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
