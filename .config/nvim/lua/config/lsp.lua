local M = {}

-- nvim-lspconfig names; Mason translates these to package names.
M.servers = {
  "lua_ls", "clangd", "neocmake", "ts_ls", "jdtls",
  "html", "cssls", "rust_analyzer", "pyright",
}

function M.setup()
  -- Use Neovim's modern LSP API, not the deprecated lspconfig.setup API.
  vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

  vim.lsp.config("lua_ls", {
    on_init = function(client)
      local root = client.config.root_dir
      -- Respect a project's own Lua settings when provided.
      if root and (vim.uv.fs_stat(root .. "/.luarc.json") or vim.uv.fs_stat(root .. "/.luarc.jsonc")) then
        return
      end
      client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua or {}, {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
      })
    end,
  })

  -- Give each Java project its own workspace, even when folder names match.
  vim.lsp.config("jdtls", {
    cmd = function(dispatchers, config)
      local root = config.root_dir or vim.fn.getcwd()
      local workspace = vim.fn.stdpath("state") .. "/jdtls/" .. vim.fn.sha256(root):sub(1, 16)
      vim.fn.mkdir(workspace, "p")
      local cmd = { "jdtls", "-data", workspace }
      for arg in (vim.env.JDTLS_JVM_ARGS or ""):gmatch("%S+") do
        cmd[#cmd + 1] = "--jvm-arg=" .. arg
      end
      return vim.lsp.rpc.start(cmd, dispatchers, {
        cwd = config.cmd_cwd or root,
        env = config.cmd_env,
        detached = config.detached,
      })
    end,
  })

  vim.diagnostic.config({
    virtual_text = { spacing = 2, source = "if_many" },
    severity_sort = true,
    float = { border = "rounded", source = true },
  })

  local group = vim.api.nvim_create_augroup("PersonalLsp", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    desc = "Format on save when a language server supports it",
    callback = function(event)
      if vim.g.autoformat == false or vim.b[event.buf].autoformat == false then
        return
      end
      if vim.bo[event.buf].buftype ~= "" or not vim.bo[event.buf].modifiable then
        return
      end
      local clients = vim.lsp.get_clients({
        bufnr = event.buf,
        method = "textDocument/formatting",
      })
      if clients[1] then
        vim.lsp.buf.format({ bufnr = event.buf, id = clients[1].id, async = false, timeout_ms = 2000 })
      end
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(event)
      local function map(key, action, desc, modes)
        vim.keymap.set(modes or "n", key, action, { buffer = event.buf, desc = desc })
      end
      map("gd", vim.lsp.buf.definition, "Go to definition")
      map("gD", vim.lsp.buf.declaration, "Go to declaration")
      map("gr", vim.lsp.buf.references, "Find references")
      map("gi", vim.lsp.buf.implementation, "Go to implementation")
      map("K", vim.lsp.buf.hover, "Hover documentation")
      map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
      map("<leader>ca", vim.lsp.buf.code_action, "Code action", { "n", "x" })
      map("<leader>cs", vim.lsp.buf.signature_help, "Signature help")
      map("<leader>cf", function() vim.lsp.buf.format({ async = true }) end, "Format with LSP", { "n", "x" })
    end,
  })

  vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Show line diagnostics" })
  vim.keymap.set("n", "[d", function()
    vim.diagnostic.jump({ count = -vim.v.count1, float = true })
  end, { desc = "Previous diagnostic" })
  vim.keymap.set("n", "]d", function()
    vim.diagnostic.jump({ count = vim.v.count1, float = true })
  end, { desc = "Next diagnostic" })

  require("mason-lspconfig").setup({
    ensure_installed = M.servers,
    automatic_enable = M.servers,
  })
end

return M
