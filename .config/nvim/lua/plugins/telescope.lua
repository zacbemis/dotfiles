local function picker(name)
  return function()
    -- Open results in the editing split, not the focusable tab-bar overlay.
    local tabs = require("config.tab_navigation")
    if tabs.active then
      tabs.leave()
    end
    if vim.bo.filetype == "NvimTree" then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
    require("telescope.builtin")[name]()
  end
end

return {
  {
    "nvim-telescope/telescope.nvim",
    version = "*",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>ff", picker("find_files"), desc = "Find files" },
      { "<leader>fg", picker("live_grep"), desc = "Search project text" },
      { "<leader>fb", picker("buffers"), desc = "Find open files" },
      { "<leader>fh", picker("help_tags"), desc = "Search help" },
    },
    opts = function()
      return {
        defaults = require("telescope.themes").get_dropdown({
          previewer = false, -- Compact dropdown, capped at 80 columns / 15 rows.
          file_ignore_patterns = { "^%.git/" },
          mappings = {
            i = {
              ["<C-j>"] = "move_selection_next",
              ["<C-k>"] = "move_selection_previous",
              ["<Esc>"] = "close",
            },
          },
        }),
        pickers = {
          find_files = { hidden = true, previewer = false },
          live_grep = {
            previewer = false,
            additional_args = function()
              return { "--hidden", "--glob", "!.git" }
            end,
          },
          buffers = { sort_mru = true, ignore_current_buffer = false, previewer = false },
          help_tags = { previewer = false },
        },
      }
    end,
  },
}
