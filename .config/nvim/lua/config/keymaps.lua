local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlighting" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>bdelete<CR>", { desc = "Close file tab" })
map("n", "<leader>e", function()
  require("config.explorer").toggle()
end, { desc = "Toggle sidebar / keep full-window explorer" })

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

map("n", "<S-h>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Previous file tab" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<CR>", { desc = "Next file tab" })

map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Keep the selection when changing indentation.
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })
