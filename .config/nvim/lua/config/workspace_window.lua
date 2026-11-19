local M = {}

function M.open(path)
  local kitty = vim.fn.exepath("kitty")
  if kitty == "" or not (vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY) then
    require("config.explorer").open_workspace_tab(path)
    return
  end

  local job = vim.fn.jobstart({ kitty, "--directory", path, vim.v.progpath }, {
    detach = true,
    on_exit = function(_, code)
      if code ~= 0 then vim.notify("Worktree window exited with status " .. code .. ".", vim.log.levels.ERROR) end
    end,
  })
  if job <= 0 then error("Could not open a Kitty window for " .. path, 0) end
end

return M
