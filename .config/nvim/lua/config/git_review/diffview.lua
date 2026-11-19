local M = {}
local api = vim.api
-- Keep version-pinned Diffview view APIs confined to this adapter. Native
-- set_file/use_entry reuse the layout, just like Diffview's own file browser.
local contexts = {}

local function revision(selection)
  if selection.kind == "commit" then
    return selection.parent and selection.parent .. ".." .. selection.hash or selection.hash .. "^!"
  end
  -- A normal Diffview contains BOTH working and staged file entries.
  return "working"
end

local function await(future)
  if not vim.wait(10000, function() return future:is_done() end, 10) then
    error("The comparison did not finish loading; refresh the Git review and try again.", 0)
  end
  return future:await()
end

local function find_file(files, selection)
  local kind = selection.kind == "staged" and "staged" or "working"
  for _, file in files:iter() do
    if file.path == selection.path and (file.kind == kind or file.kind == "conflicting") then return file end
  end
end

local function destroy_files(files, retained_buffers)
  for _, entry in files:iter() do
    for _, file in ipairs(entry.layout:files()) do
      -- Replacement entries can share the exact same native buffer. Destroying
      -- the old File would detach the replacement's buffer-local keymaps too.
      if not retained_buffers or not retained_buffers[file.bufnr] then file:destroy() end
    end
    entry.layout:destroy()
  end
end

local function invalidate_index_buffers(view)
  for _, entry in view.files:iter() do
    for _, file in ipairs(entry.layout:files()) do
      if file.rev.stage ~= nil and file:is_valid() and not vim.bo[file.bufnr].modified then
        if file.rev.stage > 0 or file.blob_hash ~= view.adapter:file_blob_hash(file.path) then
          file:dispose_buffer()
        end
      end
    end
  end
end

local function reload(context, selection)
  local view = context.view
  local key = revision(selection)
  local left, right = view.adapter:parse_revs(key ~= "working" and key or nil, {})
  if not left or not right then error("Could not resolve the requested Git revisions.", 0) end
  -- Fetch before changing the live view, so a failed query leaves it intact.
  local err, files = await(require("diffview.vcs.utils").diff_file_list(
    view.adapter, left, right, {}, view.options, {
      default_layout = view.class.get_default_layout(),
      merge_layout = view.class.get_default_merge_layout(),
    }
  ))
  if err then error(table.concat(err, "\n"), 0) end
  local target = find_file(files, selection)
  if selection.path and not target then
    destroy_files(files)
    error("The selected file is no longer in this comparison; refresh Git review.", 0)
  end
  invalidate_index_buffers(view)
  local previous = view.files
  view.left, view.right, view.rev_arg = left, right, key ~= "working" and key or nil
  view.files, view.panel.files = files, files
  view.panel.rev_pretty_name = view.adapter:rev_to_pretty_string(left, right)
  view.merge_ctx = next(files.conflicting) and view.adapter:get_merge_context() or nil
  if view.merge_ctx then
    for _, entry in ipairs(files.conflicting) do entry:update_merge_context(view.merge_ctx) end
  end
  view.panel:set_cur_file(nil)
  view.panel:update_components()
  view.panel:render()
  view.panel:redraw()
  if target then await(view:set_file(target, false, true)) else view:file_safeguard() end
  context.revision = key
  -- Release retired buffers, but leave shared live buffers and their mappings
  -- attached to the replacement entries.
  local retained = {}
  for _, file in ipairs(view.cur_layout:files()) do
    if file.bufnr then retained[file.bufnr] = true end
  end
  destroy_files(previous, retained)
end

function M.select(tab, selection, refresh)
  local context = assert(contexts[tab], "Git review view is no longer available.")
  local view = context.view
  api.nvim_set_current_tabpage(tab)
  local target = find_file(view.files, selection)
  if refresh or context.revision ~= revision(selection) or (selection.path and not target) then
    reload(context, selection)
  elseif target and view.cur_entry ~= target then
    await(view:set_file(target, false, true))
  end
end

function M.closed(tab)
  contexts[tab] = nil
end

function M.open(selection)
  local args = { "-C" .. selection.root }
  local key = revision(selection)
  if key ~= "working" then args[#args + 1] = key end
  if selection.path then args[#args + 1] = "--selected-file=" .. selection.root .. "/" .. selection.path end
  local previous = api.nvim_get_current_tabpage()
  require("diffview").open(args)
  local tab = api.nvim_get_current_tabpage()
  if tab == previous then error("Diffview could not open the requested comparison.", 0) end
  local view = assert(require("diffview.lib").tabpage_to_view(tab))
  contexts[tab] = { view = view, revision = key }
  local ok, err = pcall(function()
    if not vim.wait(10000, function() return view.initialized end, 10) then
      error("The comparison did not finish loading; refresh Git review and try again.", 0)
    end
    if view.panel:is_open() then view.panel:close() end
    M.select(tab, selection)
  end)
  if not ok then
    M.close(tab)
    if api.nvim_tabpage_is_valid(previous) then api.nvim_set_current_tabpage(previous) end
    error(err, 0)
  end
  return tab
end

function M.can_leave(tab)
  if not tab or not api.nvim_tabpage_is_valid(tab) then return true end
  for _, window in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local buffer = api.nvim_win_get_buf(window)
    if vim.bo[buffer].modified and api.nvim_buf_get_name(buffer):match("^diffview://") then
      return false, "Save the edited index buffer before leaving this comparison."
    end
  end
  return true
end

function M.close(tab)
  if tab and api.nvim_tabpage_is_valid(tab) then
    api.nvim_set_current_tabpage(tab)
    require("diffview").close()
  end
  M.closed(tab)
end

local function file_window(tab)
  local target, column = nil, -1
  for _, window in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local position = api.nvim_win_get_position(window)
    local filetype = vim.bo[api.nvim_win_get_buf(window)].filetype
    if api.nvim_win_get_config(window).relative == "" and filetype ~= "GitReview"
      and filetype ~= "DiffviewFiles" and position[2] > column then
      target, column = window, position[2]
    end
  end
  return target
end

function M.focus_file(tab)
  local target = file_window(tab)
  if target then api.nvim_set_current_win(target) end
end

function M.fold(tab, open)
  local target = vim.wo.diff and api.nvim_get_current_win() or file_window(tab)
  if not target then return end
  api.nvim_win_call(target, function()
    if not vim.wo.diff or vim.fn.foldlevel(".") == 0 then return end
    local closed = vim.fn.foldclosed(".") ~= -1
    if (open and not closed) or (not open and closed) then return end
    -- Use Diffview's zo/zc mappings: manual folds need both panes updated.
    vim.cmd.normal({ (open and "zo" or "zc"), bang = false })
  end)
end

function M.decorate(_, window, context)
  if not context.layout_name:match("^diff2_") then return end
  local removed = context.symbol == "a"
  local mappings = {}
  for _, entry in ipairs(vim.split(vim.wo[window].winhighlight, ",", { trimempty = true })) do
    local source, target = entry:match("^([^:]+):(.+)$")
    if source then mappings[source] = target end
  end
  mappings.DiffChange = removed and "DiffviewDiffAddAsDelete" or "DiffviewDiffAdd"
  mappings.DiffText = removed and "DiffviewDiffTextDelete" or "DiffviewDiffTextAdd"
  local entries = {}
  for source, target in pairs(mappings) do entries[#entries + 1] = source .. ":" .. target end
  table.sort(entries)
  vim.wo[window].winhighlight = table.concat(entries, ",")
end

return M
