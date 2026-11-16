-- Display-only tree rendering. Row IDs/order belong to the model; this
-- module adds the same connected branches and inline badges as the explorer.
local M = {}
local status_symbols = { A = "+", ["?"] = "?", C = "+", M = "~", R = ">", T = "~", D = "-", U = "!", X = "!" }
local status_groups = {
  A = "GitReviewAdded", ["?"] = "GitReviewAdded", C = "GitReviewAdded", R = "GitReviewAdded",
  M = "GitReviewChanged", T = "GitReviewChanged",
  D = "GitReviewDeleted", U = "GitReviewConflict", X = "GitReviewConflict",
}

function M.rows(rows)
  local lines, highlights, siblings, next_at_depth = {}, {}, {}, {}
  -- Find following siblings without confusing children of different parents.
  for index = #rows, 1, -1 do
    local depth = rows[index].depth
    for level in pairs(next_at_depth) do
      if level > depth then next_at_depth[level] = nil end
    end
    siblings[index] = next_at_depth[depth] == true
    next_at_depth[depth] = true
  end
  local has_icons, icons = pcall(require, "nvim-web-devicons")
  local continuing = {}
  for index, row in ipairs(rows) do
    local line = ""
    local function add(text, highlight)
      local start = #line
      line = line .. text
      if #text > 0 then
        highlights[#highlights + 1] = { row = index - 1, start = start, finish = #line, group = highlight }
      end
    end
    local indent = " " -- Match the editor explorer's one-cell left inset.
    for level = 1, row.depth - 1 do
      indent = indent .. (continuing[level] and "│ " or "  ")
    end
    if row.depth > 0 then indent = indent .. (siblings[index] and "├─ " or "└─ ") end
    continuing[row.depth] = siblings[index]
    add(indent, "GitReviewIndent")

    local label = row.label:gsub("%c", " ")
    local status = row.status and status_groups[row.status] or "GitReviewText"
    if row.kind == "file" then
      local icon, highlight
      if has_icons then icon, highlight = icons.get_icon(label, label:match("%.([^.]*)$"), { default = true }) end
      add((icon or "·") .. " ", highlight or "GitReviewMuted")
      add(label, status)
      if row.status and row.status ~= " " then add("  " .. (status_symbols[row.status] or row.status), status) end
    elseif row.kind == "commit" then
      add(row.expanded and "▾ " or "▸ ", "GitReviewMuted")
      local hash, subject = label:match("^(%S+) (.*)$")
      if hash then
        add(hash .. " ", "GitReviewMuted")
        add(subject, "GitReviewText")
      else
        add(label, "GitReviewText")
      end
    elseif row.kind == "more" then
      add("… " .. label, "GitReviewMuted")
    else
      local highlight = row.depth == 0 and "GitReviewRoot" or row.expanded and "GitReviewOpenFolder" or "GitReviewFolder"
      add(row.kind == "branch" and " " or row.expanded and " " or " ",
        row.depth == 0 and "GitReviewRoot" or "GitReviewFolderIcon")
      local name, metadata
      if row.kind == "branch" then name, metadata = label:match("^(.-)( %([^()]+%))$")
      elseif row.kind == "staged" or row.kind == "unstaged" then name, metadata = label:match("^(.-)( %(%d+%))$") end
      add(name or label, highlight)
      if metadata then add(metadata, "GitReviewMuted") end
    end
    lines[index] = line
  end
  return lines, highlights
end

return M
