local map = vim.keymap.set
require("config.quit").setup()

map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlighting" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save file" })
map("n", "<leader>q", function()
  local review = require("config.git_review")
  if review.is_active() then review.close() else vim.cmd.bdelete() end
end, { desc = "Close file buffer / Git review tab" })
map("n", "<leader>e", function()
  if require("config.git_review").toggle_sidebar() then return end
  require("config.explorer").toggle()
end, { desc = "Toggle sidebar / keep full-window explorer" })
map("n", "<leader>k", function()
  require("config.tab_navigation").enter()
end, { desc = "Focus file tab bar" })

-- Move between split windows; at the top, Ctrl-k focuses the file tab bar.
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", function()
  if vim.fn.winnr("k") ~= vim.fn.winnr() then
    vim.cmd.wincmd("k")
  else
    require("config.tab_navigation").enter()
  end
end, { desc = "Go to upper window / file tab bar" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })
map("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>sh", "<cmd>split<CR>", { desc = "Horizontal split" })

map("n", "<leader>h", function()
  require("config.git_review").fold(false)
end, { desc = "Collapse Git diff context" })
map("n", "<leader>l", function()
  require("config.git_review").fold(true)
end, { desc = "Expand Git diff context" })
map("n", "<S-h>", function()
  if require("config.git_review").fold(false) then return end
  vim.cmd.BufferLineCyclePrev()
end, { desc = "Previous file tab / collapse Git diff context" })
map("n", "<S-l>", function()
  if require("config.git_review").fold(true) then return end
  vim.cmd.BufferLineCycleNext()
end, { desc = "Next file tab / expand Git diff context" })

map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Keep the selection when changing indentation.
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })
