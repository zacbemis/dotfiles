local M = {}
local pending
local tab = vim.api.nvim_replace_termcodes("<Tab>", true, false, true)

-- Only an immediately repeated Tab may replace an accepted completion.
vim.on_key(function(_, typed)
  -- Neovim can report several consumed mapping keys together. The final key
  -- is the current input; earlier navigation may precede the accepting Tab.
  if typed ~= "" and typed:sub(-#tab) ~= tab then pending = nil end
end, vim.api.nvim_create_namespace("completion_repeat_tab"))

local function unchanged(state)
  return state.buf == vim.api.nvim_get_current_buf()
    and state.win == vim.api.nvim_get_current_win()
    and state.tick == vim.api.nvim_buf_get_changedtick(state.buf)
    and vim.deep_equal(state.after_cursor, vim.api.nvim_win_get_cursor(0))
end

local function replace_with_tab(cmp, state)
  pending = nil
  cmp.hide()
  -- Keymap callbacks run under textlock; edit after they return.
  vim.schedule(function()
    if not unchanged(state) then return end
    if vim.snippet.active() then vim.snippet.stop() end
    local was_selecting = vim.fn.mode():match("^[sS\19]") ~= nil
    if was_selecting then
      -- Native snippets select their first placeholder. Leave Select mode so
      -- the fallback Tab inserts whitespace instead of replacing a selection.
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
    end

    -- Restore only changed lines, including any auto-imports or snippet text.
    local current = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local first, old_end, new_end = 0, #state.lines, #current
    while first < math.min(old_end, new_end) and state.lines[first + 1] == current[first + 1] do
      first = first + 1
    end
    while old_end > first and new_end > first and state.lines[old_end] == current[new_end] do
      old_end, new_end = old_end - 1, new_end - 1
    end
    if old_end ~= first or new_end ~= first then
      local replacement = {}
      for i = first + 1, old_end do replacement[#replacement + 1] = state.lines[i] end
      vim.api.nvim_buf_set_lines(state.buf, first, new_end, false, replacement)
    end
    vim.api.nvim_win_set_cursor(state.win, state.cursor)
    -- Non-remapped Tab uses Neovim's normal expandtab/softtabstop behavior.
    local insert = ""
    if was_selecting then
      insert = state.cursor[2] >= #state.lines[state.cursor[1]] and "a" or "i"
    end
    vim.api.nvim_feedkeys(insert .. tab, "in", false)
  end)
end

function M.tab(cmp)
  if pending then
    local state = pending
    if not state.tick then
      -- Handle a second Tab while an LSP item is still being resolved.
      state.replace = true
      return true
    elseif unchanged(state) then
      replace_with_tab(cmp, state)
      return true
    end
    pending = nil
  end

  if not cmp.is_visible() then return end
  local state = {
    buf = vim.api.nvim_get_current_buf(),
    win = vim.api.nvim_get_current_win(),
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(0),
  }
  pending = state
  local accepted = cmp.select_and_accept({
    callback = function()
      if pending ~= state or state.buf ~= vim.api.nvim_get_current_buf() then return end
      state.tick = vim.api.nvim_buf_get_changedtick(state.buf)
      state.after_cursor = vim.api.nvim_win_get_cursor(0)
      if state.replace then replace_with_tab(cmp, state) end
    end,
  })
  if not accepted then pending = nil end
  return accepted
end

return M
