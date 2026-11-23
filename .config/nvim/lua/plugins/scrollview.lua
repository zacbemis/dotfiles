return {
  {
    "dstein64/nvim-scrollview",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = {
      base = "right",
      column = 1,
      width = 1,
      symbol = "▐",
      overflow = "left",
      visibility = "always",
      excluded_filetypes = { "NvimTree", "GitReview", "lazy", "mason" },
      signs_on_startup = {}, -- Keep the overview dedicated to Git changes.
      signs_max_per_row = 1,
      -- Git symbols include a trailing cell under the scrollbar, keeping their
      -- visible bar in the next column left even outside the scrollbar thumb.
      signs_scrollbar_overlap = "under",
    },
    config = function(_, opts)
      require("scrollview").setup(opts)
      require("scrollview.contrib.gitsigns").setup({
        add_symbol = "▐ ",
        change_symbol = "▐ ",
        delete_symbol = "▐ ",
        add_highlight = "GitSignsAdd",
        change_highlight = "GitSignsChange",
        delete_highlight = "GitSignsDelete",
        hide_full_add = false,
      })
    end,
  },
}
