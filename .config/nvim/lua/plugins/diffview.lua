local function command(name)
  return function()
    local tabs = require("config.tab_navigation")
    if tabs.active then
      tabs.leave()
    end
    vim.cmd(name)
  end
end

return {
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory",
      "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh",
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>gd", command("DiffviewOpen"), desc = "Open side-by-side Git diff" },
      { "<leader>gq", command("DiffviewClose"), desc = "Close Git diff view" },
    },
    config = function(_, opts)
      require("diffview").setup(opts)
      require("config.diffview").setup()
    end,
    opts = {
      enhanced_diff_hl = true, -- Tint real removed lines, not empty alignment rows.
      hooks = {
        diff_buf_win_enter = function(...) require("config.diffview").diff_colors(...) end,
      },
      show_help_hints = false,
      icons = { folder_closed = "", folder_open = "" },
      view = {
        default = { layout = "diff2_horizontal" }, -- Left/right panes.
        file_history = { layout = "diff2_horizontal" },
      },
      file_panel = {
        listing_style = "tree",
        tree_options = { flatten_dirs = false, folder_statuses = "only_folded" },
        win_config = { width = 26 },
      },
      keymaps = {
        view = { ["<leader>e"] = "<Cmd>DiffviewToggleFiles<CR>" },
        file_panel = {
          ["<leader>e"] = "<Cmd>DiffviewToggleFiles<CR>",
          ["l"] = function() require("config.diffview").open_entry() end,
        },
        file_history_panel = { ["<leader>e"] = "<Cmd>DiffviewToggleFiles<CR>" },
      },
    },
  },
}
