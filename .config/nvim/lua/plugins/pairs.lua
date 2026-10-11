return {
  {
    "nvim-mini/mini.pairs",
    version = "*",
    event = "InsertEnter",
    opts = {
      modes = { insert = true, command = false, terminal = false },
    },
  },
  {
    "windwp/nvim-ts-autotag",
    lazy = false,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      opts = {
        enable_close = true,
        enable_rename = true,
        enable_close_on_slash = false,
      },
    },
  },
}
