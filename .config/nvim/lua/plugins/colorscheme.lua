return {
  {
    "nvim-mini/mini.base16",
    version = false,
    lazy = false,
    priority = 1000,
    config = function()
      local palette_path = vim.fn.stdpath("config") .. "/lua/colors/wal-colors.lua"

      local ok, palette = pcall(dofile, palette_path)
      if not ok then
        vim.cmd.colorscheme("habamax")
        return
      end

      require("mini.base16").setup({
        palette = palette,
        use_cterm = true,
      })

      -- Optional tweaks (same idea as your nvim_set_hl example)
      vim.api.nvim_set_hl(0, "Visual", {
        bg = palette.base0D, -- or whatever you prefer
        fg = palette.base00,
      })
    end,
  },
}
