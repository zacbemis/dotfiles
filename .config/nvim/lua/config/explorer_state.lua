-- Browser locations are filesystem paths, never renderer-dependent row numbers.
-- Per-workspace files avoid different Neovim instances overwriting other projects.
local M = {}
local api, uv = vim.api, vim.uv
local locations, cached, dirty = {}, {}, {}
local restoring = false

local function normalize(path)
  return uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function workspace()
  return normalize(vim.fn.getcwd())
end

local function within(path, root)
  local prefix = root:sub(-1) == "/" and root or root .. "/"
  return path == root or path:sub(1, #prefix) == prefix
end

local function valid(entry)
  return type(entry) == "table" and entry.version == 1
    and type(entry.root) == "string" and entry.root:sub(1, 1) == "/"
    and type(entry.path) == "string" and entry.path:sub(1, 1) == "/"
    and vim.fs.normalize(entry.root) == entry.root and vim.fs.normalize(entry.path) == entry.path
    and within(entry.path, entry.root)
    and type(entry.offset) == "number" and entry.offset >= 0 and entry.offset < 100000
    and entry.offset == math.floor(entry.offset)
end

local function filename(key)
  return vim.fn.stdpath("state") .. "/explorer/" .. vim.fn.sha256(key) .. ".json"
end

local function read(key)
  if cached[key] == nil then
    local ok, lines = pcall(vim.fn.readfile, filename(key))
    local decoded, entry = false, nil
    if ok then decoded, entry = pcall(vim.json.decode, table.concat(lines, "\n")) end
    cached[key] = decoded and valid(entry) and entry or false
  end
  return cached[key] or nil
end

local function tree_api()
  return package.loaded["nvim-tree.api"] -- Never load a browser just to capture/quit.
end

function M.location(root)
  root = root and normalize(root)
  local tab = api.nvim_get_current_tabpage()
  local entry = root and locations[tab] and locations[tab][root] or nil
  entry = entry or dirty[workspace()] or read(workspace())
  if not entry or (root and entry.root ~= root) or vim.fn.isdirectory(entry.root) ~= 1 then return end
  return vim.deepcopy(entry)
end

function M.remember()
  if restoring then return end
  local tree = tree_api()
  local win = tree and tree.tree.winid()
  if not win or not api.nvim_win_is_valid(win) or vim.bo[api.nvim_win_get_buf(win)].filetype ~= "NvimTree" then return end
  api.nvim_win_call(win, function()
    local node = tree.tree.get_node_under_cursor()
    local root = node
    -- Follow the public parent handles instead of cloning the entire tree on
    -- every cursor movement via get_nodes().
    while root and root.parent do root = root.parent end
    if not root or not node or not within(node.absolute_path, root.absolute_path) then return end
    local entry = { version = 1, root = root.absolute_path, path = node.absolute_path,
      offset = math.max(0, api.nvim_win_get_cursor(win)[1] - vim.fn.winsaveview().topline) }
    local tab = api.nvim_get_current_tabpage()
    locations[tab] = locations[tab] or {}
    locations[tab][entry.root] = entry
    dirty[workspace()] = entry
  end)
end

function M.restore(entry)
  if not entry then return end
  local tree = tree_api()
  local win = tree and tree.tree.winid()
  local root = tree and tree.tree.get_nodes()
  if not win or not root or root.absolute_path ~= entry.root
    or vim.bo[api.nvim_win_get_buf(win)].filetype ~= "NvimTree" then return end
  restoring = true
  local ok, err = pcall(api.nvim_win_call, win, function()
    local path = entry.path
    -- Missing or filtered entries fall back to the nearest visible parent.
    while within(path, entry.root) do
      if path == entry.root then
        api.nvim_win_set_cursor(win, { 1, 0 })
        break
      end
      if uv.fs_stat(path) then
        tree.tree.find_file({ buf = path, focus = false, update_root = false })
        local node = tree.tree.get_node_under_cursor()
        if node and (node.absolute_path == path or node.link_to == uv.fs_realpath(path)) then break end
      end
      path = vim.fs.dirname(path)
    end
    local view = vim.fn.winsaveview()
    local offset = math.min(entry.offset, math.max(0, api.nvim_win_get_height(win) - 1))
    view.topline = math.max(1, api.nvim_win_get_cursor(win)[1] - offset)
    vim.fn.winrestview(view)
  end)
  restoring = false
  if not ok then vim.notify("Could not restore file-browser position: " .. tostring(err), vim.log.levels.WARN) end
end

local function write(key, entry)
  local encoded, data = pcall(vim.json.encode, entry)
  if not encoded then return false, data end
  data = data .. "\n"
  local path = filename(key)
  local ok, err = pcall(vim.fn.mkdir, vim.fs.dirname(path), "p", 448)
  if not ok then return false, err end
  local temp = path .. "." .. vim.fn.getpid() .. ".tmp"
  local fd
  fd, err = uv.fs_open(temp, "w", 384)
  if not fd then return false, err end
  local count
  count, err = uv.fs_write(fd, data, 0)
  local closed = uv.fs_close(fd)
  if count == #data and closed then
    local renamed
    renamed, err = uv.fs_rename(temp, path)
    if renamed then return true end
  end
  uv.fs_unlink(temp)
  return false, err or "incomplete state write"
end

function M.save()
  M.remember()
  for key, entry in pairs(dirty) do
    local ok, err = write(key, entry)
    if not ok then return false, err end
    cached[key], dirty[key] = entry, nil
  end
  return true
end

function M.setup()
  local group = api.nvim_create_augroup("ExplorerLocation", { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "WinLeave", "BufWinLeave" }, {
    group = group,
    callback = function(event)
      if vim.bo[event.buf].filetype == "NvimTree" then M.remember() end
    end,
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(locations) do
        if not api.nvim_tabpage_is_valid(tab) then locations[tab] = nil end
      end
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local ok, err = M.save()
      if not ok then vim.notify("Could not save file-browser position: " .. tostring(err), vim.log.levels.WARN) end
    end,
  })
end

return M
