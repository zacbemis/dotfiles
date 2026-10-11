local M = {}

local function empty_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_get_name(buf) == ""
    and not vim.bo[buf].modified
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype == ""
    and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "" })
end

local function open_in_place(buf)
  require("nvim-tree.api").tree.open({ current_window = true })
  -- Remove only the unused placeholder, never unsaved text.
  if vim.api.nvim_get_current_buf() ~= buf and empty_buffer(buf) then
    vim.api.nvim_buf_delete(buf, { force = false })
  end
end

function M.toggle()
  local api = require("nvim-tree.api")
  local wins = vim.api.nvim_tabpage_list_wins(0)
  if api.tree.is_visible() then
    -- Closing a lone tree would make Neovim invent an empty editor buffer.
    -- Only hide the tree when there is another real window to return to.
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_get_config(win).relative == ""
        and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "NvimTree" then
        api.tree.toggle()
        return
      end
    end
    api.tree.focus()
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  if #wins == 1 and empty_buffer(buf) then
    -- Recover an empty window left by a direct :NvimTreeClose, too.
    open_in_place(buf)
  else
    api.tree.toggle()
  end
end

local function after_last_file()
  if vim.v.exiting ~= vim.NIL or vim.fn.getcmdwintype() ~= "" then return end
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local target, buf
  for _, win in ipairs(wins) do
    local candidate = vim.api.nvim_win_get_buf(win)
    if empty_buffer(candidate) and vim.bo[candidate].buflisted then
      target, buf = win, candidate
      break
    end
  end
  if not target then return end

  -- Keep other open files and deliberately created buffers, including unsaved
  -- unnamed files. A normal :enew does not trigger this close-file handler.
  for _, other in ipairs(vim.api.nvim_list_bufs()) do
    if other ~= buf and vim.bo[other].buflisted and vim.bo[other].buftype == "" then return end
  end
  -- Don't disturb a placeholder shared with another tab's layout.
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= vim.api.nvim_get_current_tabpage() then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_get_buf(win) == buf then return end
      end
    end
  end

  local api = require("nvim-tree.api")
  -- A sidebar must be closed before replacing the editor window with the tree.
  if api.tree.is_visible() then api.tree.close() end
  if not vim.api.nvim_win_is_valid(target) then return end
  vim.api.nvim_set_current_win(target)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= target and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_close(win, false)
    end
  end
  open_in_place(buf)
end

-- nvim-tree's stock padding omits branches for root children and uses spaces
-- after non-final siblings. Override only padding so every node gets a ├─/└─
-- branch; normal rendering, icons, highlights, and node navigation stay intact.
function M.setup_branches()
  local padding = require("nvim-tree.renderer.components.padding")
  if padding.dotfiles_branches then return end
  padding.dotfiles_branches = true
  local original = padding.get_indent_markers
  padding.get_indent_markers = function(depth, idx, count, node, markers, early_stop)
    local renderer = require("nvim-tree.config").g.renderer
    if not renderer.indent_markers.enable then
      return original(depth, idx, count, node, markers, early_stop)
    end
    local level = depth + 1 -- Connect direct children to the visible root too.
    local width = math.max(renderer.indent_width, 2)
    local icons = renderer.indent_markers.icons
    markers[level] = idx ~= count
    local parts = { " " } -- One-cell inset from the window edge.
    for i = 1, level - (early_stop or 0) do
      if i == level then
        parts[#parts + 1] = (idx == count and icons.corner or icons.item)
          .. icons.bottom .. string.rep(" ", width - 2) .. " " -- Small branch/icon gap.
      else
        parts[#parts + 1] = (markers[i] and icons.edge or icons.none) .. string.rep(" ", width - 1)
      end
    end
    return { str = table.concat(parts), hl = { "NvimTreeIndentMarker" } }
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("StartupExplorer", { clear = true })
  local reading_stdin = false
  vim.api.nvim_create_autocmd("StdinReadPre", {
    group = group,
    callback = function() reading_stdin = true end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.schedule(function()
        -- Leave explicit files, stdin, sessions, and startup layouts alone.
        if reading_stdin or vim.fn.argc() ~= 0 or #vim.api.nvim_list_wins() ~= 1 then return end
        local buf = vim.api.nvim_get_current_buf()
        if empty_buffer(buf) then open_in_place(buf) end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    desc = "Return to the full-window explorer after closing the last file",
    callback = function(event)
      if vim.bo[event.buf].buflisted and vim.bo[event.buf].buftype == "" and not empty_buffer(event.buf) then
        -- :bdelete must finish selecting/creating its replacement buffer first.
        vim.schedule(after_last_file)
      end
    end,
  })
end

return M
