return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false, -- The current Treesitter API does not support lazy loading.
    build = ":TSUpdate",
    dependencies = { "mason-org/mason.nvim" }, -- Supplies the tree-sitter CLI when installed through Mason.
    config = function()
      require("config.treesitter").setup()
    end,
  },
}
