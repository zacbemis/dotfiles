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

function M.commits(root, limit)
  local _, code = run(root, { "rev-parse", "--verify", "HEAD" }, true)
  if code ~= 0 then return {} end
  local values = fields(run(root, { "log", "-z", "--format=%H%x00%h%x00%s", "--max-count=" .. limit }))
  local commits = {}
  for index = 1, #values, 3 do
    commits[#commits + 1] = { hash = values[index], short = values[index + 1], subject = values[index + 2] }
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
