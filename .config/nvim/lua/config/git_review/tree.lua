local History = require("config.git_review.history")
local M = {}
local PAGE_SIZE = 100

function M.new(root, repository)
  local nodes, old_nodes, expanded = {}, {}, {}
  local file_cache, limits, initialized = {}, {}, {}
  local history = History.new(root, repository)
  local root_id, current_id, snapshot, branch_refs
  local statuses = {}
  local model = {}
  local load

  local function add(node)
    nodes[node.id] = node
    node.children = node.children or {}
    return node
  end

  local function restore(node)
    if expanded[node.id] or node.id == root_id or (old_nodes[node.id] and old_nodes[node.id].loaded) then load(node) end
  end

  local function add_files(section, files)
    for _, file in ipairs(files) do
      local node = add({ id = section.id .. ":file:" .. file.path, kind = "file", label = vim.fs.basename(file.path),
        path = file.path, status = file.status, section = section.id, parent = section.id, branch_id = section.branch_id })
      section.children[#section.children + 1] = node.id
    end
    table.sort(section.children, function(a, b)
      local left, right = nodes[a], nodes[b]
      if left.label == right.label then return left.path < right.path end
      return left.label < right.label
    end)
  end

  local function load_commit(node)
    if not file_cache[node.hash] then
      local files, parent = repository.commit_files(root, node.hash)
      file_cache[node.hash] = { files = files, parent = parent }
    end
    node.parent_hash = file_cache[node.hash].parent
    add_files(node, file_cache[node.hash].files)
  end

  local function append_history(branch)
    local limit = limits[branch.id] or PAGE_SIZE
    local commits = History.annotate(history:commits(branch.hash, limit + 1), branch_refs, branch.name)
    for index, commit in ipairs(commits) do
      if index > limit then break end
      local node = add({ id = branch.id .. ":commit:" .. commit.hash, kind = "commit",
        parent = branch.id, branch_id = branch.id, hash = commit.hash, subject = commit.subject,
        author = commit.author, branch_name = commit.branch_name, label = commit.short .. " " .. commit.subject })
      branch.children[#branch.children + 1] = node.id
      restore(node)
    end
    if #commits > limit then
      branch.children[#branch.children + 1] = add({ id = branch.id .. ":more", kind = "more",
        parent = branch.id, branch_id = branch.id, label = "Older commits..." }).id
    end
  end

  local function load_branch(branch)
    if branch.worktree then
      local status = statuses[branch.worktree] or repository.status(branch.worktree)
      statuses[branch.worktree] = status
      local first_visit = initialized[branch.id] ~= branch.worktree
      for _, kind in ipairs({ "unstaged", "staged" }) do
        local id = branch.id .. ":" .. kind
        local section = add({ id = id, kind = kind, parent = branch.id, branch_id = branch.id,
          label = (kind == "unstaged" and "Unstaged files" or "Staged files") .. " (" .. #status[kind] .. ")" })
        branch.children[#branch.children + 1] = id
        if first_visit then expanded[id] = true end
        add_files(section, status[kind])
      end
      initialized[branch.id] = branch.worktree
    end
    append_history(branch)
  end

  load = function(node)
    if node.loaded then return end
    if node.kind == "branch" then load_branch(node)
    elseif node.kind == "commit" then load_commit(node)
    else return end
    node.loaded = true
  end

  function model:refresh(force)
    local branches = repository.branches(root)
    local next_statuses = { [root] = repository.status(root) }
    for _, branch in ipairs(branches) do
      local path = branch.worktree
      if path and statuses[path] and not next_statuses[path] then next_statuses[path] = repository.status(path) end
    end
    local next_snapshot = vim.json.encode(branches)
    if not force and next_snapshot == snapshot and vim.deep_equal(next_statuses, statuses) then return false end
    local previous_current = current_id
    old_nodes, nodes, statuses, current_id, branch_refs = nodes, {}, next_statuses, nil, branches
    local overview = add({ id = "branches", kind = "root", label = "Branches: " .. vim.fs.basename(root) })
    for _, branch in ipairs(branches) do
      local id = branch.worktree_row and ("worktree:" .. vim.json.encode(branch.worktree)) or ("branch:" .. branch.ref)
      local path = branch.worktree
      local worktree_label
      if path and not branch.current then
        worktree_label = vim.fs.relpath(root, path)
          or (vim.fs.dirname(path) == vim.fs.dirname(root) and ("../" .. vim.fs.basename(path)))
          or vim.fn.fnamemodify(path, ":~")
      end
      local badge = branch.current and " (current)" or branch.remote and " (remote)"
        or worktree_label and (" (worktree: " .. worktree_label .. ")") or ""
      add({ id = id, kind = "branch", parent = overview.id, branch_id = id,
        ref = branch.ref, name = branch.name, hash = branch.hash, worktree = path, worktree_label = worktree_label,
        remote = branch.remote, current = branch.current,
        label = branch.name .. badge })
      overview.children[#overview.children + 1] = id
      if branch.current then current_id = id end
    end
    assert(current_id, "The repository did not report a checked-out branch or detached HEAD.")
    if not root_id or root_id == previous_current then root_id = current_id end
    for _, id in ipairs(overview.children) do
      if id == current_id then load(nodes[id]) else restore(nodes[id]) end
    end
    while not nodes[root_id] do root_id = old_nodes[root_id] and old_nodes[root_id].parent or current_id end
    snapshot = next_snapshot
    return true
  end

  function model:rows()
    local rows = {}
    local function visit(id, depth)
      local node = nodes[id]
      if not node then return end
      rows[#rows + 1] = { id = id, label = node.label, kind = node.kind, depth = depth,
        expanded = id == root_id or expanded[id] == true, status = node.status }
      if id == root_id or expanded[id] then
        load(node)
        for _, child in ipairs(node.children) do visit(child, depth + 1) end
      end
    end
    visit(root_id, 0)
    return rows
  end

  function model:expand(id)
    local node = nodes[id]
    if not node then return root_id end
    if node.kind == "more" then
      local owner = nodes[node.parent]
      local previous = #owner.children - 1
      limits[owner.id] = (limits[owner.id] or PAGE_SIZE) + PAGE_SIZE
      self:refresh(true)
      return nodes[owner.id] and (nodes[owner.id].children[previous + 1] or owner.id) or root_id
    end
    load(node)
    if expanded[id] or id == root_id then return node.children[1] or id end
    expanded[id] = true
    return id
  end

  function model:collapse(id)
    if id == root_id then return self:up() end
    local node = nodes[id]
    if not node then return root_id end
    if expanded[id] then expanded[id] = false; return id end
    local parent = node.parent
    if parent and parent ~= root_id then expanded[parent] = false; return parent end
    return id
  end

  function model:drill(id)
    local node = nodes[id]
    if not node or node.kind == "file" then return id end
    if node.kind == "more" then return self:expand(id) end
    load(node)
    root_id = id
    return id
  end

  function model:up()
    local parent = nodes[root_id].parent
    if not parent then return root_id end
    local previous = root_id
    root_id, expanded[previous] = parent, false
    return previous
  end

  function model:toggle(id)
    if expanded[id] then expanded[id] = false; return id end
    return self:expand(id)
  end

  function model:context(id)
    local node = nodes[id]
    local section = node and nodes[node.section or node.id]
    if not section or section.kind == "root" or section.kind == "more" then return end
    local branch = nodes[section.branch_id]
    local working = section.kind == "unstaged" or section.kind == "staged"
    return { root = working and branch.worktree or root, kind = section.kind, hash = section.hash, name = section.name,
      parent = section.parent_hash, subject = section.subject, author = section.author, id = section.id,
      branch_id = branch.id, branch_ref = branch.ref, branch_name = section.branch_name or section.name or branch.name,
      worktree_label = branch.worktree_label }
  end

  function model:selection(id)
    local node = nodes[id]
    if not node or node.kind ~= "file" then return end
    local selection = self:context(id)
    selection.path, selection.id = node.path, node.id
    return selection
  end

  function model:initial_selection(id)
    local node = nodes[id] or nodes[current_id]
    local branch = nodes[node.branch_id] or nodes[current_id]
    local function first(node)
      if node.kind == "more" then return end
      load(node)
      if node.kind == "file" then return self:selection(node.id) end
      for _, id in ipairs(node.children) do
        local selection = first(nodes[id])
        if selection then return selection end
      end
    end
    return first(node) or (branch.worktree and self:context(branch.id .. ":unstaged"))
      or (branch.id ~= current_id and self:initial_selection(current_id))
  end

  function model:switch_target(id)
    local expected = nodes[id]
    if not expected or expected.kind ~= "branch" then
      error("Select a branch or worktree row to switch.", 0)
    end
    if expected.remote then error("Remote-tracking branches are read-only; switch to a local branch.", 0) end
    self:refresh()
    local node = nodes[id]
    if not node or node.worktree ~= expected.worktree or node.ref ~= expected.ref then
      error("The branch or worktree changed; refresh Git review before switching.", 0)
    end
    return { current = node.current, worktree = node.worktree, name = node.name }
  end

  function model:can_stage(id)
    local node = nodes[id]
    local section = node and nodes[node.section or node.id]
    return section and nodes[section.branch_id].worktree ~= nil
      and (section.kind == "unstaged" or section.kind == "staged") or false
  end

  function model:stage(id)
    if not self:can_stage(id) then error("Committed history is read-only; select an unstaged or staged file.", 0) end
    local expected = nodes[nodes[id].branch_id]
    self:refresh()
    local branch, node = nodes[expected.id], nodes[id]
    if not branch or branch.worktree ~= expected.worktree or branch.ref ~= expected.ref
      or (branch.ref == "HEAD" and branch.hash ~= expected.hash) then
      error("The checked-out branch changed or the worktree moved; refresh Git review before staging.", 0)
    end
    if not node then error("The selected file is no longer in this section; refresh Git review.", 0) end
    local section = nodes[node.section or node.id]
    if section.kind == "unstaged" then repository.stage(branch.worktree, node.path)
    else repository.unstage(branch.worktree, node.path) end
    local destination = branch.id .. (section.kind == "unstaged" and ":staged" or ":unstaged")
    self:refresh()
    local file_id = destination .. ":file:" .. (node.path or "")
    return nodes[file_id] and file_id or destination
  end

  model:refresh()
  return model
end

return M
