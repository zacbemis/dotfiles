-- Your own Neovim config: no LazyVim.
-- nvim-tree replaces Neovim's built-in file explorer.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
-- Set leaders before loading any keymaps or plugins.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.options")
require("config.pdf").setup()
require("config.wallpaper").setup()
require("config.keymaps")
require("config.lazy")
