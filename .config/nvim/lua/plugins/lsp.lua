return {
  {
    "saghen/blink.cmp",
    version = "1.*", -- Stable completion API, not the in-development v2.
    lazy = false,
    opts = {
      keymap = {
        preset = "default", -- Keep Ctrl-y and the existing navigation aliases.
        ["<C-j>"] = { "select_next", "fallback" },
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<CR>"] = { "snippet_forward", "fallback" },
        ["<Tab>"] = {
          function(cmp) return require("config.completion").tab(cmp) end,
          "fallback",
        },
      }, -- Enter advances snippet arguments; otherwise it stays a newline.
      sources = { default = { "lsp", "path", "buffer" } },
      completion = {
        list = { selection = { preselect = true, auto_insert = false } },
        documentation = { auto_show = false },
      },
      fuzzy = { implementation = "lua" }, -- No native binary/build required.
    },
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      {
        "mason-org/mason.nvim",
        opts = {
          install_root_dir = vim.fn.stdpath("data") .. "/mason",
          ui = { border = "rounded" },
        },
      },
      "mason-org/mason-lspconfig.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      require("config.lsp").setup()
    end,
  },
}
