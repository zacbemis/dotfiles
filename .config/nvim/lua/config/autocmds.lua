-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local auto_reload = vim.api.nvim_create_augroup("opencode_auto_reload", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained", "TermClose", "TermLeave" }, {
  group = auto_reload,
  callback = function(event)
    if vim.bo[event.buf].buftype == "" and vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})
