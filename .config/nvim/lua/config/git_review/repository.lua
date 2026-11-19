local M = {}

local function command(root, args)
  -- Polling must not rewrite .git/index: Diffview watches it and would reload the diff.
  return vim.list_extend({ "git", "--no-optional-locks", "--literal-pathspecs", "-C", root }, args)
end

local function run(root, args, allow_failure)
  local result = vim.system(command(root, args), { text = false }):wait(10000)
  if result.code ~= 0 and not allow_failure then
    error(vim.trim(result.stderr or "Git command failed"), 0)
  end
  return result.stdout or "", result.code
end

local function fields(text)
  local values = vim.split(text, "\0", { plain = true })
  if values[#values] == "" then table.remove(values) end
  return values
end

function M.root(path)
  return (run(path, { "rev-parse", "--show-toplevel" }):gsub("\n$", ""))
end

function M.status(root)
  local records = fields(run(root, { "status", "--porcelain=v1", "-z", "--untracked-files=all" }))
  local unstaged, staged, index = {}, {}, 1
  while records[index] do
    local record = records[index]
    local x, y, path = record:sub(1, 1), record:sub(2, 2), record:sub(4)
    local original
    if x:match("[RC]") or y:match("[RC]") then
      index = index + 1
      original = records[index]
    end
    if x ~= " " and x ~= "?" then
      staged[#staged + 1] = { path = path, original = original, status = x }
    end
    if y ~= " " or x == "?" then
      unstaged[#unstaged + 1] = { path = path, original = original, status = y == " " and x or y }
    end
    index = index + 1
  end
  return { unstaged = unstaged, staged = staged }
end

local function worktrees(root)
  local result, entry, common_dir = {}, nil, nil
  for _, field in ipairs(fields(run(root, { "worktree", "list", "--porcelain", "-z" }))) do
    local key, value = field:match("^(%S+) ?(.*)$")
    if key == "worktree" then
      entry = { path = value }
    elseif key and entry then
      entry[key] = value
    elseif entry then
      if entry.path ~= root and not entry.bare and not entry.prunable and vim.fn.isdirectory(entry.path) == 1 then
        -- A stale registration can point at a replaced directory, even another Git repo.
        common_dir = common_dir or run(root, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
        local location, code = run(entry.path,
          { "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir" }, true)
        if code == 0 and location == entry.path .. "\n" .. common_dir then result[#result + 1] = entry end
      end
      entry = nil
    end
  end
  return result
end

function M.branches(root)
  local current, code = run(root, { "symbolic-ref", "--quiet", "HEAD" }, true)
  current = code == 0 and vim.trim(current) or nil
  local branches, by_ref = {}, {}
  local output = run(root, { "for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)%00",
    "refs/heads/", "refs/remotes/" })
  for line in output:gmatch("[^\n]+") do
    local values = fields(line)
    if values[3] == "" then -- Exclude aliases such as origin/HEAD.
      local ref = values[1]
      local branch = { ref = ref, hash = values[2], current = ref == current,
        remote = ref:sub(1, 13) == "refs/remotes/",
        name = ref:gsub("^refs/heads/", ""):gsub("^refs/remotes/", "") }
      branches[#branches + 1] = branch
      by_ref[ref] = branch
    end
  end
  local active = by_ref[current]
  if not active then
    local hash, head_code = run(root, { "rev-parse", "--verify", "HEAD" }, true)
    hash = head_code == 0 and vim.trim(hash) or nil
    active = { ref = current or "HEAD", hash = hash, current = true, remote = false,
      name = current and current:gsub("^refs/heads/", "") or ("Detached HEAD (" .. (hash or "unknown"):sub(1, 7) .. ")") }
    branches[#branches + 1] = active
  end
  active.worktree = root
  for _, entry in ipairs(worktrees(root)) do
    local branch = by_ref[entry.branch]
    if branch and not branch.worktree then
      branch.worktree = entry.path
    else
      -- Detached worktrees (or extra checkouts made with --force) need separate rows.
      local hash = entry.HEAD and not entry.HEAD:match("^0+$") and entry.HEAD or nil
      branches[#branches + 1] = { ref = entry.branch or "HEAD", hash = hash, worktree = entry.path,
        worktree_row = true, current = false, remote = false,
        name = branch and branch.name or (entry.branch and entry.branch:gsub("^refs/heads/", ""))
          or (vim.fs.basename(entry.path) .. " (detached HEAD)") }
    end
  end
  table.sort(branches, function(a, b)
    if a.current ~= b.current then return a.current end
    if a.remote ~= b.remote then return not a.remote end
    if a.name ~= b.name then return a.name < b.name end
    if a.worktree_row ~= b.worktree_row then return not a.worktree_row end
    return (a.worktree or "") < (b.worktree or "")
  end)
  return branches
end

function M.commits(root, ref, limit)
  local _, code = run(root, { "rev-parse", "--verify", "--end-of-options", ref .. "^{commit}" }, true)
  if code ~= 0 then return {} end
  local args = { "log", "--topo-order", "-z", "--format=%H%x00%h%x00%s%x00%aN%x00%P", "--max-count=" .. limit, ref, "--" }
  local values, commits = fields(run(root, args)), {}
  for index = 1, #values, 5 do
    commits[#commits + 1] = { hash = values[index], short = values[index + 1], subject = values[index + 2],
      author = values[index + 3], parents = vim.split(values[index + 4], " ", { trimempty = true }) }
  end
  return commits
end

function M.commit_files(root, hash)
  local ancestry = vim.split(vim.trim(run(root, { "rev-list", "--parents", "-n", "1", hash })), " ")
  local parent = ancestry[2]
  local args = parent and { "diff", "--name-status", "-z", "-M", parent, hash, "--" }
    or { "diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "-z", "-M", hash, "--" }
  local values, files, index = fields(run(root, args)), {}, 1
  while values[index] do
    local status, path = values[index], values[index + 1]
    local original
    if status:match("^[RC]") then
      original, path = path, values[index + 2]
      index = index + 1
    end
    files[#files + 1] = { path = path, original = original, status = status:sub(1, 1) }
    index = index + 2
  end
  return files, parent
end

function M.switch(root, branch, done)
  vim.system(command(root, { "switch", "--no-guess", "--", branch }), { text = true },
    vim.schedule_wrap(function(result)
      done(result.code == 0, vim.trim(result.stderr or ""))
    end))
end

function M.stage(root, path)
  run(root, { "add", "-A", "--", path or "." })
end

function M.unstage(root, path)
  local _, code = run(root, { "rev-parse", "--verify", "HEAD" }, true)
  if code == 0 then
    run(root, { "restore", "--staged", "--", path or "." })
  else
    run(root, { "rm", "-r", "--cached", "--ignore-unmatch", "--", path or "." })
  end
end

return M
