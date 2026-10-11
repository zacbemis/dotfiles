return {
  {
    "akinsho/bufferline.nvim",
    version = "*",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      highlights = function(defaults)
        -- The active tab joins the editor surface; other tabs match the explorer.
        for name, hl in pairs(defaults.highlights) do
          local surface = name:match("_selected$") and "Normal" or "NvimTreeNormal"
          hl.bg = { highlight = surface, attribute = "bg" }
          hl.default = false -- Reapply after wallpaper overrides on ColorScheme.
        end
        return defaults.highlights
      end,
      options = {
        mode = "buffers", -- One tab-like entry per open file, not per window layout.
        always_show_bufferline = true,
        separator_style = "thin",
        show_close_icon = false,
        -- Don't silently discard unsaved changes when closing a file.
        close_command = "bdelete %d",
        right_mouse_command = "bdelete %d",
      },
    },
  },
}
