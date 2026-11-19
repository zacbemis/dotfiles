local opt = vim.opt

-- Appearance
opt.number = true
opt.relativenumber = true
opt.numberwidth = 2 -- Grow automatically when more digits are needed.
opt.cursorline = true
opt.signcolumn = "yes"
local gutter_pad = "%{&nu || &rnu ? ' ' : ''}"
opt.statuscolumn = gutter_pad .. "%C%=%l" .. gutter_pad .. "%s"
-- One-cell left inset and number/sign gap; the sign column provides the code gap.
-- No extra gutter padding in unnumbered windows such as the file explorer.
opt.fillchars:append({ eob = " ", diff = " " }) -- Hide tildes and dashed diff alignment rows.
opt.termguicolors = true
opt.showtabline = 2
opt.laststatus = 3 -- One shared bottom status bar across split windows.
opt.cmdheight = 0 -- Native : and / input temporarily covers that bottom row.
-- Without ui2, statusline redraws erase messages within ~100ms when cmdheight is 0.
require("vim._core.ui2").enable({ msg = { targets = "msg" } })
opt.showmode = false -- Lualine already displays the mode.
opt.showcmdloc = "statusline" -- Pending normal-mode commands appear in the bar.
opt.scrolloff = 8
opt.wrap = true
opt.linebreak = true -- Wrap at word boundaries without changing the file.
opt.breakindent = true
opt.diffopt:append("followwrap") -- Keep wrapping enabled in side-by-side diffs.

-- Indentation (filetype-specific settings may override these)
opt.expandtab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true

-- Editing and windows
opt.undofile = true
opt.splitbelow = true
opt.splitright = true
opt.mouse = "a"
opt.updatetime = 250
opt.timeout = false -- Wait indefinitely for leader/multi-key mappings.
opt.ttimeout = true -- Still recognize terminal key sequences promptly.
opt.ttimeoutlen = 50

-- Store persistent undo in Neovim's standard state directory.
local undo_dir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(undo_dir, "p")
opt.undodir = undo_dir

-- For system clipboard integration, install a provider (e.g. wl-clipboard)
-- and uncomment this:
-- opt.clipboard = "unnamedplus"
