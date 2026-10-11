local M = {}

function M.open(path)
  if vim.fn.executable("xdg-settings") ~= 1 or vim.fn.executable("gtk-launch") ~= 1 then
    vim.notify("Opening PDFs requires xdg-settings and gtk-launch", vim.log.levels.ERROR)
    return false
  end
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("PDF not found: " .. path, vim.log.levels.ERROR)
    return false
  end

  -- xdg-open would use the PDF viewer, not necessarily the default browser.
  local result = vim.system({ "xdg-settings", "get", "default-web-browser" }, { text = true }):wait(2000)
  local browser = vim.trim(result.stdout or "")
  if result.code ~= 0 or browser == "" then
    vim.notify("Could not determine the default web browser", vim.log.levels.ERROR)
    return false
  end

  vim.system({ "gtk-launch", browser, vim.uri_from_fname(path) }, { text = true }, function(proc)
    if proc.code ~= 0 then
      vim.schedule(function()
        vim.notify("Could not open PDF: " .. vim.trim(proc.stderr or ""), vim.log.levels.ERROR)
      end)
    end
  end)
  return true
end

function M.setup()
  local group = vim.api.nvim_create_augroup("PdfInBrowser", { clear = true })
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "*.[pP][dD][fF]",
    desc = "Open PDFs in the default browser instead of reading binary data",
    callback = function(event)
      local buf = event.buf
      local previous = vim.fn.bufnr("#")
      local path = vim.api.nvim_buf_get_name(buf)
      if not M.open(path) then
        return
      end

      -- Wait until the file-opening command finishes before removing its buffer.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if previous > 0 and previous ~= buf and vim.api.nvim_buf_is_valid(previous)
          and vim.bo[previous].buflisted then
          for _, win in ipairs(vim.fn.win_findbuf(buf)) do
            vim.api.nvim_win_set_buf(win, previous)
          end
        end
        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end,
  })
end

return M
