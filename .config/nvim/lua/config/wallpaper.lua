local M = {}

local function read_palette(path)
  local file = io.open(path, "r")
  if not file then
    return
  end
  local content = file:read("*a")
  file:close()
  local chunk = loadstring(content, "@" .. path)
  if not chunk then
    return -- A generator may still be writing the file.
  end
  setfenv(chunk, {}) -- Generated palettes only need a table of literal colors.
  local ok, palette = pcall(chunk)
  if not ok or type(palette) ~= "table" then
    return
  end
  for i = 0, 15 do
    local color = palette[string.format("base%02X", i)]
    if type(color) ~= "string" or not color:match("^#%x%x%x%x%x%x$") then
      return
    end
  end
  return palette
end

local function mix(color, other, amount)
  local out = "#"
  for i = 2, 6, 2 do
    local a = tonumber(color:sub(i, i + 1), 16)
    local b = tonumber(other:sub(i, i + 1), 16)
    out = out .. string.format("%02x", math.floor(a * (1 - amount) + b * amount + 0.5))
  end
  return out
end

local function apply_backgrounds(palette)
  -- Start from our fixed local syntax colors; only backgrounds follow wallpaper.
  vim.cmd.colorscheme("dotfiles")
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local text = string.format("#%06x", normal.fg)
  local bg = palette.base00
  local shades = {
    base = bg,
    mantle = mix(bg, "#000000", 0.08),
    crust = mix(bg, "#000000", 0.16),
    surface0 = mix(bg, text, 0.08),
    surface2 = mix(bg, text, 0.22),
  }
  local replacements = {}
  for _, role in ipairs({
    { "TabLine", "mantle" },
    { "TabLineFill", "crust" },
    { "StatusLine", "mantle" },
    { "StatusLineNC", "crust" },
    { "NormalFloat", "mantle" },
    { "CursorLine", "surface0" },
    { "Visual", "surface2" },
    { "PmenuSel", "surface2" },
    { "Normal", "base" },
  }) do
    local original = vim.api.nvim_get_hl(0, { name = role[1], link = false }).bg
    if original then
      replacements[original] = tonumber(shades[role[2]]:sub(2), 16)
    end
  end
  -- Replace only background fields, preserving foregrounds, styles and links.
  -- This also covers tree, bufferline, and completion integration highlights.
  for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
    -- Semantic diff colors are fixed, even if a color matches a UI surface.
    if not hl.link and not name:match("^Diff") and replacements[hl.bg] then
      hl.bg = replacements[hl.bg]
      vim.api.nvim_set_hl(0, name, hl)
    end
  end

  -- Some UI backgrounds are blended by the theme, rather than exact palette colors.
  local ui = {
    Normal = "base",
    NormalNC = "base",
    SignColumn = "base",
    EndOfBuffer = "base",
    LineNr = "base",
    CursorLineNr = "base",
    FoldColumn = "base",
    WinSeparator = "base",
    NormalFloat = "mantle",
    FloatBorder = "mantle",
    Pmenu = "mantle",
    CursorLine = "surface0",
    Folded = "surface0",
    ColorColumn = "surface0",
    PmenuSel = "surface2",
    PmenuSbar = "surface0",
    PmenuThumb = "surface2",
    StatusLine = "mantle",
    StatusLineNC = "crust",
    TabLineFill = "crust",
    Visual = "surface2",
  }
  for name, shade in pairs(ui) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    hl.bg = tonumber(shades[shade]:sub(2), 16)
    vim.api.nvim_set_hl(0, name, hl)
  end
  -- Bars and the focusable tab overlay match the tree, except the active tab.
  local tree = vim.api.nvim_get_hl(0, { name = "NvimTreeNormal", link = false })
  for _, name in ipairs({ "StatusLine", "StatusLineNC", "TabLine", "TabLineSel", "TabLineFill" }) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    hl.bg = name == "TabLineSel"
      and vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or tree.bg
    vim.api.nvim_set_hl(0, name, hl)
  end
  -- Refresh the file tab bar and its focusable overlay after background overrides.
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "dotfiles" })
end

function M.reload(force)
  local candidates = {}
  for _, path in ipairs(M.paths or {}) do
    -- fs_stat follows Pywal's symlink, so cache rewrites are detected too.
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "file" then
      candidates[#candidates + 1] = { path = path, mtime = stat.mtime }
    end
  end
  table.sort(candidates, function(a, b)
    if a.mtime.sec == b.mtime.sec then
      if a.mtime.nsec == b.mtime.nsec then
        return a.path < b.path
      end
      return a.mtime.nsec > b.mtime.nsec
    end
    return a.mtime.sec > b.mtime.sec
  end)

  for _, candidate in ipairs(candidates) do
    local palette = read_palette(candidate.path)
    if palette then
      M.source = candidate.path
      vim.g.wallpaper_palette_file = M.source
      if force or not M.palette or palette.base00 ~= M.palette.base00 then
        apply_backgrounds(palette)
      end
      M.palette = palette
      return true
    elseif M.palette and candidate.path == M.source then
      return false -- Keep the last good colors during partial/invalid writes.
    end
  end
  return false -- Missing palettes keep the startup fallback or last good theme.
end

function M.stop()
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

function M.setup(opts)
  opts = opts or {}
  M.stop()
  vim.cmd.colorscheme("dotfiles") -- Fixed syntax even when no wallpaper palette exists.
  M.paths = opts.paths
    or {
      vim.fn.stdpath("config") .. "/lua/colors/wal-colors.lua",
      vim.fn.stdpath("config") .. "/lua/colors/matugen-colors.lua",
    }
  M.reload(true)

  local group = vim.api.nvim_create_augroup("WallpaperColors", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      M.reload()
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
  vim.api.nvim_create_user_command("WallpaperReload", function()
    if not M.reload(true) then
      vim.notify("No valid wallpaper palette found; keeping the current colors.", vim.log.levels.WARN)
    end
  end, { desc = "Reload the newest Pywal / Matugen palette" })

  -- Polling also handles replaced files and symlink targets, unlike a file watcher.
  M.timer = assert(vim.uv.new_timer())
  local interval = opts.interval or 1000
  M.timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      if M.timer and vim.v.exiting == vim.NIL then
        M.reload()
      end
    end)
  )
end

return M
