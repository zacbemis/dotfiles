local M = {}
local api = vim.api
local displayed, ready = {}, {}

function M.closed(tab)
  displayed[tab], ready[tab] = nil, nil
end

function M.open(selection)
  local args = { "-C" .. selection.root }
  if selection.kind == "staged" then args[#args + 1] = "--cached" end
  if selection.kind == "commit" then
    args[#args + 1] = selection.parent and selection.parent .. ".." .. selection.hash or selection.hash .. "^!"
  end
  if selection.path then
    args[#args + 1] = "--selected-file=" .. selection.root .. "/" .. selection.path
    args[#args + 1] = "--"
    args[#args + 1] = ":(literal)" .. selection.path
  end
  local previous = api.nvim_get_current_tabpage()
  require("diffview").open(args)
  local tab = api.nvim_get_current_tabpage()
  if tab == previous then error("Diffview could not open the requested comparison.", 0) end
  if selection.path and not vim.wait(10000, function() return ready[tab] == true end, 10) then
    M.close(tab)
    error("The comparison did not finish loading; refresh the Git review and try again.", 0)
  end
  for _, window in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if vim.bo[api.nvim_win_get_buf(window)].filetype == "DiffviewFiles" then
      vim.cmd.DiffviewToggleFiles()
      break
    end
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

function M.focus_file(tab)
  local target, column = nil, -1
  for _, window in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local position = api.nvim_win_get_position(window)
    local filetype = vim.bo[api.nvim_win_get_buf(window)].filetype
    if api.nvim_win_get_config(window).relative == "" and filetype ~= "GitReview"
      and filetype ~= "DiffviewFiles" and position[2] > column then
      target, column = window, position[2]
    end
  end
  if target then api.nvim_set_current_win(target) end
end

function M.decorate(_, window, context)
  local tab = api.nvim_win_get_tabpage(window)
  displayed[tab] = displayed[tab] or {}
  displayed[tab][window] = api.nvim_win_get_buf(window)
  vim.schedule(function()
    if not api.nvim_tabpage_is_valid(tab) or not displayed[tab] then return end
    local count = 0
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if vim.wo[win].diff then
        if displayed[tab][win] ~= api.nvim_win_get_buf(win) then return end
        count = count + 1
      end
    end
    ready[tab] = count >= 2
  end)
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
