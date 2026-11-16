-- The tabline is global: own it only while the review tab is active.
local M = {}
local api = vim.api

function M.new(group)
  local tab, title, saved
  local header = {}

  function header:hide()
    if not saved then return end
    vim.o.tabline, vim.o.showtabline = saved.tabline, saved.showtabline
    saved = nil
  end

  function header:show()
    if api.nvim_get_current_tabpage() ~= tab then return end
    saved = saved or { tabline = vim.o.tabline, showtabline = vim.o.showtabline }
    vim.o.tabline = "%#TabLineSel# " .. title .. " %=%#TabLineFill#"
    vim.o.showtabline = 2
  end

  function header:update(review_tab, selection)
    tab = review_tab
    local prefix, message
    if selection.kind == "branch" then
      prefix = selection.name
    else
      prefix = selection.branch_name or "(unknown branch)"
      if selection.kind == "commit" then
        local author = selection.author and selection.author ~= "" and selection.author or "Unknown author"
        prefix = prefix .. " · " .. author
        message = selection.subject ~= "" and selection.subject or "(no commit message)"
      else
        message = selection.kind == "staged" and "Staged changes" or "Unstaged changes"
      end
    end
    -- All Git metadata is data, never tabline expressions or click targets.
    -- Truncate the message before sacrificing the branch/author prefix.
    title = prefix:gsub("%c", " "):gsub("%%", "%%%%")
    if message then title = title .. " · %<" .. message:gsub("%c", " "):gsub("%%", "%%%%") end
    self:show()
  end

  api.nvim_create_autocmd("TabEnter", { group = group, callback = function() header:show() end })
  api.nvim_create_autocmd("TabLeave", { group = group, callback = function() header:hide() end })
  return header
end

return M
