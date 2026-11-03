-- Override Neovim's built-in .brf -> TeX association for Brief source files.
vim.filetype.add({
  extension = { brf = "brief" },
})
