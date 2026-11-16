-- Flat, topologically ordered history with merge-derived header metadata.
-- Git stores parent edges, not original branch ownership. Prefer the historical
-- merge message; exact surviving refs are a fallback, never a containment guess.
local M = {}

local function source_names(subject)
  local branch = subject:match("^Merge branch '([^']+)'")
    or subject:match("^Merge remote%-tracking branch '([^']+)'")
    or subject:match("^Merge pull request #%d+ from [^/]+/(%S+)")
    or subject:match("^Merged in (%S+) %(pull request #%d+")
  if branch then return { branch } end
  if subject:match("^Merge branches ") or subject:match("^Merge remote%-tracking branches ") then
    local names = {}
    for name in (subject:match("^(.-) into ") or subject):gmatch("'([^']+)'") do names[#names + 1] = name end
    return names
  end
  return {}
end

function M.sources(commit, branches)
  local names, sources = source_names(commit.subject), {}
  for index = 2, #commit.parents do
    local tip, matching = commit.parents[index], nil
    for _, branch in ipairs(branches) do
      if branch.hash == tip and (not matching or (matching.remote and not branch.remote)) then matching = branch end
    end
    sources[#sources + 1] = { tip = tip,
      name = names[index - 1] or (matching and matching.name) or ("Merged branch " .. tip:sub(1, 7)) }
  end
  return sources
end

-- Topological order guarantees all children have contributed context before a
-- parent is visited. Prefer first-parent routes closest to the browsed branch:
-- shared pre-merge ancestors must not inherit a feature branch's identity.
function M.annotate(commits, branches, branch_name)
  local contexts, result = {}, {}
  local function offer(hash, name, depth)
    if not contexts[hash] or depth < contexts[hash].depth then contexts[hash] = { name = name, depth = depth } end
  end
  for _, commit in ipairs(commits) do
    local context = contexts[commit.hash] or { name = branch_name, depth = 0 }
    local sources = M.sources(commit, branches)
    local names = {}
    for _, source in ipairs(sources) do names[#names + 1] = source.name end
    result[#result + 1] = vim.tbl_extend("force", commit, {
      branch_name = #names > 0 and table.concat(names, " + ") or context.name,
    })
    if commit.parents[1] then offer(commit.parents[1], context.name, context.depth) end
    for _, source in ipairs(sources) do offer(source.tip, source.name, context.depth + 1) end
  end
  return result
end

function M.new(root, repository)
  local pages = {}
  local history = {}

  function history:commits(tip, limit)
    if not tip then return {} end
    local key = vim.json.encode({ tip, limit })
    if not pages[key] then pages[key] = repository.commits(root, tip, limit) end
    return pages[key]
  end

  return history
end

return M
