local M = {}

local function run(root, args, allow_failure)
  local command = { "git", "--literal-pathspecs", "-C", root }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = false }):wait(10000)
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
  return vim.trim(run(path, { "rev-parse", "--show-toplevel" }))
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

function M.branches(root)
  local current, code = run(root, { "symbolic-ref", "--quiet", "HEAD" }, true)
  current = code == 0 and vim.trim(current) or nil
  local branches, found = {}, false
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
      found = found or branch.current
    end
  end
  if not found then
    local hash, head_code = run(root, { "rev-parse", "--verify", "HEAD" }, true)
    hash = head_code == 0 and vim.trim(hash) or nil
    branches[#branches + 1] = { ref = current or "HEAD", hash = hash, current = true, remote = false,
      name = current and current:gsub("^refs/heads/", "") or ("Detached HEAD (" .. (hash or "unknown"):sub(1, 7) .. ")") }
  end
  table.sort(branches, function(a, b)
    if a.current ~= b.current then return a.current end
    if a.remote ~= b.remote then return not a.remote end
    return a.name < b.name
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
