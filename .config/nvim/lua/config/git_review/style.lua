-- Review-only presentation derived from the editor's current theme.
-- Keep links for window surfaces; text spans use foregrounds only so they
-- never paint editor-background rectangles over the explorer surface.
local M = {}
local api = vim.api
local group

local function source(names)
  for _, name in ipairs(names) do
    local hl = api.nvim_get_hl(0, { name = name, link = false, create = false })
    if next(hl) then return name, hl end
  end
  return "Normal", api.nvim_get_hl(0, { name = "Normal", link = false })
end

function M.apply()
  local function link(name, candidates)
    api.nvim_set_hl(0, name, { link = source(candidates) })
  end
  local function text(name, candidates, bold)
    local _, hl = source(candidates)
    api.nvim_set_hl(0, name, { fg = hl.fg, bold = bold or false })
  end
  link("GitReviewNormal", { "NvimTreeNormal", "Normal" })
  link("GitReviewNormalNC", { "NvimTreeNormalNC", "NvimTreeNormal", "NormalNC" })
  link("GitReviewCursorLine", { "NvimTreeCursorLine", "CursorLine" })
  link("GitReviewEndOfBuffer", { "NvimTreeEndOfBuffer", "NvimTreeNormal", "EndOfBuffer" })
  link("GitReviewWinSeparator", { "NvimTreeWinSeparator", "WinSeparator" })
  text("GitReviewText", { "NvimTreeNormal", "Normal" })
  text("GitReviewRoot", { "NvimTreeRootFolder", "Directory" }, true)
  text("GitReviewFolder", { "NvimTreeFolderName", "Directory" })
  text("GitReviewFolderIcon", { "NvimTreeFolderIcon", "Directory" })
  text("GitReviewOpenFolder", { "NvimTreeOpenedFolderName", "Directory" })
  text("GitReviewIndent", { "NvimTreeIndentMarker", "NonText" })
  text("GitReviewMuted", { "NvimTreeEmptyFolderName", "Comment" })
  text("GitReviewAdded", { "GitSignsAdd", "DiagnosticOk" })
  text("GitReviewChanged", { "GitSignsChange", "DiagnosticWarn" })
  text("GitReviewDeleted", { "GitSignsDelete", "DiagnosticError" })
  text("GitReviewConflict", { "DiagnosticWarn", "WarningMsg" })

  local _, selected = source({ "BufferLineBufferSelected", "TabLineSel", "Normal" })
  local _, normal = source({ "Normal" })
  local _, muted = source({ "NvimTreeEmptyFolderName", "Comment" })
  local background = selected.bg or normal.bg
  api.nvim_set_hl(0, "GitReviewTab", { fg = selected.fg or normal.fg, bg = background })
  api.nvim_set_hl(0, "GitReviewTabBranch", { fg = selected.fg or normal.fg, bg = background, bold = true })
  api.nvim_set_hl(0, "GitReviewTabMeta", { fg = muted.fg, bg = background })
  link("GitReviewTabFill", { "BufferLineFill", "TabLineFill" })
end

function M.setup()
  if not group then
    group = api.nvim_create_augroup("GitReviewStyle", { clear = true })
    api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = function()
        M.apply()
        -- Bufferline and wallpaper integrations can update their groups later
        -- in the same event; pick up their final surfaces as well.
        vim.schedule(M.apply)
      end,
    })
  end
  M.apply()
end

return M
