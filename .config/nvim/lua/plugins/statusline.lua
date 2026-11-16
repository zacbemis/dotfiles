return {
  {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    config = function(_, opts)
      local line = require("lualine")
      line.setup(opts)
      vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("PersonalStatusline", { clear = true }),
        pattern = "PersonalNavigationModeChanged",
        callback = function() line.refresh({ place = { "statusline" }, force = true }) end,
      })
    end,
    opts = {
      options = {
        theme = function()
          local theme = require("lualine.themes.auto")
          local tree = vim.api.nvim_get_hl(0, { name = "NvimTreeNormal", link = false })
          local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
          for _, sections in pairs(theme) do
            for section, hl in pairs(sections) do
              hl.bg = string.format("#%06x", tree.bg)
              -- The mode label normally has dark text on a bright background.
              if section == "a" then
                hl.fg = string.format("#%06x", normal.fg)
              end
            end
          end
          return theme
        end,
        globalstatus = true,
        icons_enabled = false, -- Avoid unsupported font glyphs in the bottom bar.
        component_separators = "",
        section_separators = "",
      },
      sections = {
        lualine_a = { { function()
          local navigation = package.loaded["config.navigation_mode"]
          local label = navigation and navigation.label() or ""
          return label ~= "" and label or require("lualine.utils.mode").get_mode()
        end, padding = 1 } },
        lualine_b = { { "branch", padding = { left = 0, right = 1 } } },
        lualine_c = {
          {
            "filename",
            path = 1,
            shorting_target = 40,
            symbols = { modified = "[+]", readonly = "[RO]", unnamed = "[New file]" },
            padding = { left = 0, right = 1 },
          },
        },
        lualine_x = {
          {
            "diff",
            source = function()
              local status = vim.b.gitsigns_status_dict
              if status then
                return { added = status.added, modified = status.changed, removed = status.removed }
              end
            end,
            symbols = { added = "+", modified = "~", removed = "-" },
            padding = { left = 1, right = 0 },
          },
          {
            "diagnostics",
            sources = { "nvim_diagnostic" },
            sections = { "error", "warn" },
            symbols = { error = "E", warn = "W" },
            padding = { left = 1, right = 0 },
          },
        },
        lualine_y = { { "%S", padding = { left = 1, right = 0 } } },
        lualine_z = { { "location", padding = 1 } },
      },
      extensions = {
        {
          filetypes = { "NvimTree" },
          sections = {
            lualine_a = { { function() return "FILES" end, padding = 1 } },
            lualine_c = {
              {
                function()
                  local root = require("nvim-tree.api").tree.get_nodes()
                  local path = root and root.absolute_path or vim.fn.getcwd()
                  return vim.fn.fnamemodify(path, ":~")
                end,
                padding = { left = 0, right = 1 },
              },
            },
          },
        },
        "quickfix",
      },
    },
  },
}
