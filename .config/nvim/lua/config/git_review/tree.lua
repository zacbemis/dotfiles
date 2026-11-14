local M = {}

function M.new(root, repository)
  local nodes, expanded, cache = {}, { unstaged = true, staged = true }, {}
  local root_id, limit, snapshot = "review", 100, nil
  local model = {}

  local function add(node)
    nodes[node.id] = node
    node.children = node.children or {}
    return node
  end

  local function add_files(section, files)
    for _, file in ipairs(files) do
      local parent, prefix = section, ""
      local parts = vim.split(file.path, "/", { plain = true })
      for index = 1, #parts - 1 do
        prefix = prefix == "" and parts[index] or prefix .. "/" .. parts[index]
        local id = section.id .. ":directory:" .. prefix
        if not nodes[id] then
          local directory = add({ id = id, kind = "directory", label = parts[index],
            path = prefix, section = section.id, parent = parent.id })
          parent.children[#parent.children + 1] = directory.id
        end
        parent = nodes[id]
      end
      local node = add({ id = section.id .. ":file:" .. file.path, kind = "file", label = parts[#parts],
        path = file.path, status = file.status, section = section.id, parent = parent.id })
      parent.children[#parent.children + 1] = node.id
    end
    local function sort(node)
      table.sort(node.children, function(a, b)
        local left, right = nodes[a], nodes[b]
        if left.kind ~= right.kind then return left.kind == "directory" end
        return left.label < right.label
      end)
      for _, id in ipairs(node.children) do
        if nodes[id].kind == "directory" then sort(nodes[id]) end
      end
    end
    sort(section)
  end

  local function load(node)
    if node.kind ~= "commit" or node.loaded then return end
    if not cache[node.hash] then
      local files, parent = repository.commit_files(root, node.hash)
      cache[node.hash] = { files = files, parent = parent }
    end
    node.parent_hash, node.loaded = cache[node.hash].parent, true
    add_files(node, cache[node.hash].files)
  end

  function model:refresh()
    local status = repository.status(root)
    local commits = repository.commits(root, limit + 1)
    local next_snapshot = vim.json.encode({ status, commits })
    if next_snapshot == snapshot then return false end
    local old_nodes = nodes
    nodes = {}
    local overview = add({ id = "review", kind = "root", label = "Git review: " .. vim.fs.basename(root) })
    for _, kind in ipairs({ "unstaged", "staged" }) do
      local section = add({ id = kind, kind = kind, parent = "review",
        label = (kind == "unstaged" and "Unstaged files" or "Staged files") .. " (" .. #status[kind] .. ")" })
      overview.children[#overview.children + 1] = section.id
      add_files(section, status[kind])
    end
    for index, commit in ipairs(commits) do
      if index > limit then break end
      local node = add({ id = commit.hash, kind = "commit", parent = "review", hash = commit.hash,
        label = commit.short .. " " .. commit.subject })
      overview.children[#overview.children + 1] = node.id
      if cache[node.hash] then load(node) end
    end
    if #commits > limit then
      overview.children[#overview.children + 1] = add({ id = "more", kind = "more", parent = "review",
        label = "Older commits..." }).id
    end
    while not nodes[root_id] do
      root_id = old_nodes[root_id] and old_nodes[root_id].parent or "review"
    end
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
      local previous = limit
      limit = limit + 100
      self:refresh()
      return nodes.review.children[previous + 3] or "review"
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
    if expanded[id] then
      expanded[id] = nil
      return id
    end
    local parent = node.parent
    if parent and parent ~= root_id then expanded[parent] = nil; return parent end
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
    root_id, expanded[previous] = parent, nil
    return previous
  end

  function model:toggle(id)
    if expanded[id] then expanded[id] = nil; return id end
    return self:expand(id)
  end

  function model:selection(id)
    local node = nodes[id]
    if not node or node.kind ~= "file" then return end
    local section = nodes[node.section]
    return { root = root, kind = section.kind, hash = section.hash,
      parent = section.parent_hash, path = node.path, id = node.id }
  end

  function model:initial_selection()
    local function first(node)
      load(node)
      if node.kind == "file" then return self:selection(node.id) end
      for _, id in ipairs(node.children) do
        local selection = first(nodes[id])
        if selection then return selection end
      end
    end
    for _, id in ipairs(nodes.review.children) do
      if nodes[id].kind ~= "more" then
        local selection = first(nodes[id])
        if selection then return selection end
      end
    end
    return { root = root, kind = "unstaged" }
  end

  function model:can_stage(id)
    local node = nodes[id]
    local section = node and nodes[node.section or node.id]
    return section and (section.kind == "unstaged" or section.kind == "staged") or false
  end

  function model:stage(id)
    local node = nodes[id]
    if not node then return end
    local section = nodes[node.section or node.id]
    if section.kind ~= "unstaged" and section.kind ~= "staged" then
      error("Committed history is read-only; select an unstaged or staged file.", 0)
    end
    if section.kind == "unstaged" then repository.stage(root, node.path)
    else repository.unstage(root, node.path) end
    local destination = section.kind == "unstaged" and "staged" or "unstaged"
    self:refresh()
    local file_id = destination .. ":file:" .. (node.path or "")
    return nodes[file_id] and file_id or destination
  end

  model:refresh()
  return model
end

return M
