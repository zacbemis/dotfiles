-- The tabline is global: own it only while the review tab is active.
local M = {}
local api = vim.api

function M.new(group)
  require("config.git_review.style").setup()
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
    -- End the selected surface before the fill, like an active editor file tab.
    vim.o.tabline = "%#GitReviewTab# " .. title .. " %#GitReviewTabFill#%="
    vim.o.showtabline = 2
  end

  function header:update(review_tab, selection)
    tab = review_tab
    local function segment(highlight, text)
      -- Git metadata is data, never tabline expressions or click targets.
      return "%#" .. highlight .. "#" .. text:gsub("%c", " "):gsub("%%", "%%%%")
    end
    local branch = selection.kind == "branch" and selection.name or selection.branch_name or "(unknown branch)"
    title = segment("GitReviewTabBranch", branch)
    if selection.worktree_label then
      title = title .. segment("GitReviewTabMeta", " · worktree: " .. selection.worktree_label)
    end
    if selection.kind ~= "branch" then
      local message
      if selection.kind == "commit" then
        local author = selection.author and selection.author ~= "" and selection.author or "Unknown author"
        title = title .. segment("GitReviewTabMeta", " · " .. author)
        message = selection.subject ~= "" and selection.subject or "(no commit message)"
      else
        message = selection.kind == "staged" and "Staged changes" or "Unstaged changes"
      end
      -- Truncate the message before sacrificing the branch/author prefix.
      title = title .. segment("GitReviewTabMeta", " · ") .. "%<" .. segment("GitReviewTab", message)
    end
    self:show()
  end

  api.nvim_create_autocmd("TabEnter", { group = group, callback = function() header:show() end })
  api.nvim_create_autocmd("TabLeave", { group = group, callback = function() header:hide() end })
  return header
end

return M
