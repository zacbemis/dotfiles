local M = {}

local badges = { A = "+", ["?"] = "?", M = "~", R = ">", C = ">", T = "~", U = "!", D = "-", X = "!", B = "!" }

local function badge(comp, status)
  if badges[status] then
    comp:add_text(" " .. badges[status], require("diffview.hl").get_git_hl(status))
  end
end

local function render_file(comp, prefix)
  local file = comp.context
  local hl = require("diffview.hl")
  comp:clear()
  comp:add_text(prefix, "NvimTreeIndentMarker")
  local icon, icon_hl = hl.get_file_icon(file.basename, file.extension)
  comp:add_text(icon, icon_hl)
  comp:add_text(file.basename, file.active and "DiffviewFilePanelSelected"
    or hl.get_git_hl(file.status) or "DiffviewFilePanelFileName")
  badge(comp, file.status)
  if file.stats then
    if file.stats.additions then
      comp:add_text(" +" .. file.stats.additions, "DiffviewFilePanelInsertions")
      comp:add_text(" -" .. (file.stats.deletions or 0), "DiffviewFilePanelDeletions")
    elseif file.stats.conflicts then
      if file.stats.conflicts > 0 then
        comp:add_text(" !" .. file.stats.conflicts, "DiffviewFilePanelConflicts")
      else
        comp:add_text(" " .. require("diffview.config").get_config().signs.done, "DiffviewFilePanelInsertions")
      end
    end
  elseif file.kind == "conflicting" then
    comp:add_text(" !", "DiffviewFilePanelConflicts")
  end
  comp:ln()
end

local function render_tree(parent, ancestors)
  local conf = require("diffview.config").get_config()
  for idx, comp in ipairs(parent.components) do
    local last = idx == #parent.components
    local prefix = " " .. ancestors .. (last and "└─ " or "├─ ")
    if comp.name == "file" then
      render_file(comp, prefix)
    elseif comp.name == "directory" then
      local ctx = comp.context
      local dir, items = comp.components[1], comp.components[2]
      dir:clear()
      dir:add_text(prefix, "NvimTreeIndentMarker")
      if conf.use_icons then
        dir:add_text((ctx.collapsed and conf.icons.folder_closed or conf.icons.folder_open) .. " ", "DiffviewFolderSign")
      end
      dir:add_text(ctx.name, ctx.collapsed and "NvimTreeFolderName" or "NvimTreeOpenedFolderName")
      local statuses = conf.file_panel.tree_options.folder_statuses
      if statuses == "always" or (statuses == "only_folded" and ctx.collapsed) then
        badge(dir, ctx.status)
      end
      dir:ln()
      if not ctx.collapsed then
        render_tree(items, ancestors .. (last and "  " or "│ "))
      end
    end
  end
end

-- Treat replacement hunks as removed text on the left and added text on the
-- right, instead of painting both sides with the same generic DiffChange blue.
function M.diff_colors(_, winid, ctx)
  if not ctx.layout_name:match("^diff2_") then return end
  local removed = ctx.symbol == "a"
  local line = removed and "DiffviewDiffAddAsDelete" or "DiffviewDiffAdd"
  local word = removed and "DiffviewDiffTextDelete" or "DiffviewDiffTextAdd"
  local mappings = {}
  for _, entry in ipairs(vim.split(vim.wo[winid].winhighlight, ",", { trimempty = true })) do
    local source, target = entry:match("^([^:]+):(.+)$")
    if source then mappings[source] = target end
  end
  mappings.DiffChange = line
  mappings.DiffText = word
  local entries = {}
  for source, target in pairs(mappings) do
    entries[#entries + 1] = source .. ":" .. target
  end
  table.sort(entries)
  vim.wo[winid].winhighlight = table.concat(entries, ",")
end

function M.setup()
  if M.configured then return end
  M.configured = true
  -- Keep Diffview's component tree, section headings and navigation intact.
  -- Replace only the visible tree rows, just as our main explorer replaces padding.
  local module = "diffview.scene.views.diff.render"
  local original = require(module)
  package.loaded[module] = function(panel)
    original(panel)
    if not panel.render_data or panel.listing_style ~= "tree" then return end
    local path = panel.components.path.comp
    path:clear()
    path:add_line("  " .. vim.fs.basename(panel.adapter.ctx.toplevel), "NvimTreeRootFolder")
    for _, section in ipairs({ "conflicting", "working", "staged" }) do
      render_tree(panel.components[section].files.comp, "")
    end
  end
end

-- Unlike Enter (toggle), l only expands a folder, matching nvim-tree.
function M.open_entry()
  local view = require("diffview.lib").get_current_view()
  if not view or not view.panel then return end
  local item = view.panel:get_item_at_cursor()
  if not item then return end
  if type(item.collapsed) == "boolean" then
    view.panel:set_item_fold(item, true)
  else
    require("diffview.actions").select_entry()
  end
end

return M
