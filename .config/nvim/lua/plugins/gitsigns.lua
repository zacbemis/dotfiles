return {
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      current_line_blame = false, -- Available on demand instead of always showing.
      on_attach = function(buf)
        local gs = require("gitsigns")
        local function map(mode, key, action, desc)
          vim.keymap.set(mode, key, action, { buffer = buf, silent = true, desc = desc })
        end

        map({ "n", "x" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage / unstage Git hunk")
        map({ "n", "x" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Git hunk")
        map("n", "<leader>ghS", gs.stage_buffer, "Stage file")
        map("n", "<leader>ghU", gs.reset_buffer_index, "Unstage file")
        map("n", "<leader>ghp", gs.preview_hunk, "Preview Git hunk")
        map("n", "<leader>ghb", function()
          gs.blame_line({ full = true })
        end, "Blame line")
        map("n", "<leader>ghB", gs.toggle_current_line_blame, "Toggle inline Git blame")
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "Select Git hunk")
      end,
    },
  },
}
