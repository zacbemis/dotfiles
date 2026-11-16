-- Keep leader actions discoverable even before a language server attaches.
local M = {}

local function action(name, method, callback)
  return function()
    local supported = type(method) == "function" and method() or method
    if #vim.lsp.get_clients({ bufnr = 0, method = supported }) == 0 then
      vim.notify("No language server supports " .. name .. " in this buffer. Check :checkhealth vim.lsp.", vim.log.levels.WARN)
      return
    end
    callback()
  end
end

function M.setup()
  local map = vim.keymap.set
  map("n", "<leader>cr", action("rename", "textDocument/rename", function()
    vim.lsp.buf.rename()
  end), { desc = "Rename symbol" })
  map({ "n", "x" }, "<leader>ca", action("code actions", "textDocument/codeAction", function()
    vim.lsp.buf.code_action()
  end), { desc = "Code actions" })
  map({ "n", "x" }, "<leader>cf", action("formatting", function()
    return vim.fn.mode():match("[vV\22]") and "textDocument/rangeFormatting" or "textDocument/formatting"
  end, function()
    vim.lsp.buf.format({ async = true })
  end), { desc = "Format code" })
end

return M
