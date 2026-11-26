return {
  {
    "dstein64/nvim-scrollview",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = {
      base = "right",
      column = 1,
      width = 1,
      symbol = "▌", -- Touch the Git bar in the right half of the preceding cell.
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
      -- Themes commonly give ScrollView a selection background. With a
      -- half-cell thumb that paints an unwanted extra strip beside the bar.
      local function highlights()
        local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
        local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
        vim.api.nvim_set_hl(0, "ScrollView", { fg = comment.fg or normal.fg })
        vim.api.nvim_set_hl(0, "ScrollViewHover", { fg = normal.fg })
      end
      highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("PersonalScrollview", { clear = true }),
        callback = highlights,
      })
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
