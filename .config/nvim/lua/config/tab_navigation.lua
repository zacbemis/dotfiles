-- The native tabline is not focusable. Overlay it with a real one-row
-- window while navigating, keeping file changes in the originating split.
local M = { active = false }
local api = vim.api
local group = api.nvim_create_augroup("PersonalTabNavigation", { clear = true })
local ns = api.nvim_create_namespace("PersonalTabNavigation")
local bar_win, bar_buf, target_win
local updating = false

function M.leave(restore_focus)
  M.active = false
  api.nvim_clear_autocmds({ group = group })
  if bar_win and api.nvim_win_is_valid(bar_win) then
    api.nvim_win_close(bar_win, true)
  end
  if restore_focus ~= false and target_win and api.nvim_win_is_valid(target_win) then
    api.nvim_set_current_win(target_win)
  end
  bar_win, bar_buf, target_win = nil, nil, nil
end

local function in_target(fn)
  if not target_win or not api.nvim_win_is_valid(target_win) then
    M.leave(false)
    return
  end
  updating = true
  local ok, result = pcall(api.nvim_win_call, target_win, fn)
  updating = false
  if not ok then
    M.leave()
    vim.notify(result, vim.log.levels.ERROR)
    return
  end
  return result
end

local function render()
  local rendered = in_target(function()
    return api.nvim_eval_statusline(_G.nvim_bufferline(), {
      use_tabline = true, maxwidth = vim.o.columns, highlights = true,
    })
  end)
  if not rendered or not M.active or not api.nvim_buf_is_valid(bar_buf) then
    return
  end
  vim.bo[bar_buf].modifiable = true
  api.nvim_buf_set_lines(bar_buf, 0, -1, false, { rendered.str })
  vim.bo[bar_buf].modifiable = false
  api.nvim_buf_clear_namespace(bar_buf, ns, 0, -1)
  local cursor_col = 0
  for i, hl in ipairs(rendered.highlights) do
    local finish = rendered.highlights[i + 1] and rendered.highlights[i + 1].start or #rendered.str
    if finish > hl.start then
      api.nvim_buf_set_extmark(bar_buf, ns, 0, hl.start, {
        end_col = finish, hl_group = hl.group,
      })
    end
    if hl.group == "BufferLineBufferSelected" then
      cursor_col = hl.start
    end
  end
  api.nvim_win_set_config(bar_win, { width = vim.o.columns })
  api.nvim_win_set_cursor(bar_win, { 1, math.min(cursor_col, math.max(0, #rendered.str - 1)) })
end

local function cycle(direction)
  in_target(function()
    _G.nvim_bufferline() -- Refresh buffer order using the target split's context.
    if direction < 0 then
      vim.cmd.BufferLineCyclePrev()
    else
      vim.cmd.BufferLineCycleNext()
    end
  end)
  if M.active then
    render()
  end
end

function M.enter()
  if M.active then
    return
  end
  target_win = api.nvim_get_current_win()
  -- Prefer an editing window, but allow the full-window startup tree when
  -- there are no editors yet (and possibly no file tabs at all).
  if vim.bo.buftype ~= "" then
    local tree_win = vim.bo.filetype == "NvimTree" and target_win or nil
    target_win = tree_win
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_config(win).relative == "" and vim.bo[api.nvim_win_get_buf(win)].buftype == "" then
        target_win = win
        break
      end
    end
  end
  if not target_win then
    return
  end
  bar_buf = api.nvim_create_buf(false, true)
  vim.bo[bar_buf].bufhidden = "wipe"
  vim.bo[bar_buf].filetype = "personal-tab-bar"
  bar_win = api.nvim_open_win(bar_buf, true, {
    relative = "editor", row = 0, col = 0, width = vim.o.columns, height = 1,
    focusable = true, style = "minimal", border = "none", zindex = 1000,
  })
  vim.wo[bar_win].wrap = false
  vim.wo[bar_win].scrolloff = 0
  vim.wo[bar_win].winhighlight = "Normal:TabLineFill"
  M.active = true
  local function map(key, fn, desc)
    vim.keymap.set("n", key, fn, { buffer = bar_buf, silent = true, nowait = true, desc = desc })
  end
  map("h", function() cycle(-1) end, "Previous file tab")
  map("l", function() cycle(1) end, "Next file tab")
  for _, key in ipairs({ "<Esc>", "<CR>", "<C-j>" }) do
    map(key, function() M.leave() end, "Return to originating split")
  end
  map("<C-k>", function() end, "Already in file tab bar")
  map("<leader>q", function()
    in_target(function()
      -- An empty tab bar has no file to close; never delete the explorer.
      if vim.bo.buftype == "" then vim.cmd.bdelete() end
    end)
    if M.active then render() end
  end, "Close selected file tab")
  api.nvim_create_autocmd({ "VimResized", "ColorScheme" }, { group = group, callback = render })
  api.nvim_create_autocmd("WinLeave", {
    group = group, buffer = bar_buf,
    callback = function()
      if not updating then
        vim.schedule(function()
          if M.active and api.nvim_get_current_win() ~= bar_win then M.leave(false) end
        end)
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local win = tonumber(event.match)
      if not updating and (win == target_win or win == bar_win) then
        vim.schedule(function() if M.active then M.leave(false) end end)
      end
    end,
  })
  render()
end

return M
