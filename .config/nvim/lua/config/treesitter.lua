local M = {}

M.parsers = {
  "bash",
  "c",
  "cpp",
  "cmake",
  "css",
  "html",
  "java",
  "javascript",
  "jsdoc",
  "json",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "python",
  "rust",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "vimdoc",
  "xml",
  "yaml",
  "diff",
  "git_config",
  "git_rebase",
  "gitcommit",
  "gitignore",
  "gitattributes",
}

local function attach(buf)
  -- Leave plugin windows and unsupported filetypes on their existing settings.
  if vim.bo[buf].buftype ~= "" then
    return
  end
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang or not pcall(vim.treesitter.start, buf, lang) then
    return
  end

  if vim.treesitter.query.get(lang, "indents") then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
  -- Folding is window-local. Never override Diffview's diff folds.
  if vim.treesitter.query.get(lang, "folds") then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      local expr = "v:lua.vim.treesitter.foldexpr()"
      if not vim.wo[win].diff and (vim.wo[win].foldmethod ~= "expr" or vim.wo[win].foldexpr ~= expr) then
        vim.wo[win].foldmethod = "expr"
        vim.wo[win].foldexpr = expr
        vim.wo[win].foldlevel = 99 -- Start expanded, but preserve folds on later visits.
      end
    end
  end
end

function M.setup()
  local ts = require("nvim-treesitter")
  ts.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })

  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("PersonalTreesitter", { clear = true }),
    callback = function(event)
      attach(event.buf)
    end,
  })

  if vim.fn.executable("tree-sitter") == 0 then
    vim.schedule(function()
      vim.notify(
        "Treesitter: run :MasonInstall tree-sitter-cli, then restart Neovim to install parsers.",
        vim.log.levels.WARN
      )
    end)
    return
  end

  -- Install missing parsers asynchronously; also activate them in files already open.
  ts.install(M.parsers):await(vim.schedule_wrap(function(err, success)
    if err or not success then
      vim.notify(
        "Treesitter: some parsers failed to install; check :TSLog. " .. tostring(err or ""),
        vim.log.levels.ERROR
      )
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        attach(buf)
      end
    end
  end))
end

return M
