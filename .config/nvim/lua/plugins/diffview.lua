return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewRefresh" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      {
        "<leader>gd",
        function()
          local tabs = require("config.tab_navigation")
          if tabs.active then tabs.leave() end
          require("config.git_review").open()
        end,
        desc = "Browse changes and commit history",
      },
    },
    opts = {
      enhanced_diff_hl = true,
      show_help_hints = false,
      hooks = {
        view_closed = function(view) require("config.git_review").on_view_closed(view.tabpage) end,
        diff_buf_win_enter = function(...) require("config.git_review.diffview").decorate(...) end,
      },
      view = {
        default = { layout = "diff2_horizontal" },
        file_history = { layout = "diff2_horizontal" },
      },
      keymaps = {
        view = {
          ["<leader>e"] = function() require("config.git_review").focus_sidebar() end,
          ["<leader>q"] = function() require("config.git_review").close() end,
        },
        file_panel = {
          ["<leader>e"] = function() require("config.git_review").focus_sidebar() end,
          ["<leader>q"] = function() require("config.git_review").close() end,
        },
      },
    },
  },
}
