"""Branch queries, branch-scoped trees, and read-only cross-branch review."""
import shutil
import unittest

import test_nvim_git_review as review_tests

SETUP = r'''
local repository = require('config.git_review.repository')
local root = vim.fn.getcwd()
local function git(...)
  local result = vim.system({'git', ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
git('add', '-A')
git('commit', '-m', 'main: checkpoint')
local main_hash = git('rev-parse', 'HEAD')
local shared_hash = git('rev-parse', 'HEAD~1')
git('switch', '-q', '-c', 'feature/tree', shared_hash)
vim.fn.writefile({'feature branch content'}, 'first.txt')
git('commit', '-am', 'feature: branch change')
local feature_hash = git('rev-parse', 'HEAD')
git('switch', '-q', 'main')
vim.fn.writefile({'main worktree content'}, 'first.txt')
vim.fn.writefile({'main staged content'}, 'staged.txt')
git('add', 'staged.txt')
git('update-ref', 'refs/remotes/origin/topic', feature_hash)
git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/topic')
local feature_id = 'branch:refs/heads/feature/tree'
local remote_id = 'branch:refs/remotes/origin/topic'
local before_status = git('status', '--porcelain=v1')
local function unchanged()
  assert(git('symbolic-ref', 'HEAD') == 'refs/heads/main', 'browsing must never check out another branch')
  assert(git('rev-parse', 'HEAD') == main_hash)
  assert(git('status', '--porcelain=v1') == before_status)
  assert(vim.fn.readfile('first.txt')[1] == 'main worktree content')
  assert(git('show', ':staged.txt') == 'main staged content')
end
'''

REPOSITORY = SETUP + r'''
local branches = repository.branches(root)
assert(#branches == 3, 'symbolic remote HEAD must not become a branch folder')
assert(branches[1].ref == 'refs/heads/main' and branches[1].current)
assert(branches[2].name == 'feature/tree' and not branches[2].current and not branches[2].remote)
assert(branches[3].ref == 'refs/remotes/origin/topic' and branches[3].remote)
assert(repository.commits(root, branches[1].ref, 1)[1].subject == 'main: checkpoint')
assert(repository.commits(root, branches[2].ref, 1)[1].subject == 'feature: branch change')
assert(repository.commits(root, branches[3].ref, 1)[1].hash == feature_hash)
assert(#repository.commits(root, 'refs/heads/missing', 100) == 0)
unchanged()
print('PASS: current/local/remote refs, symbolic aliases, and branch-specific logs')
'''

TREE = SETUP + r'''
local file_queries = {}
local counted = vim.tbl_extend('force', repository, {
  commit_files = function(directory, hash)
    file_queries[hash] = (file_queries[hash] or 0) + 1
    return repository.commit_files(directory, hash)
  end,
})
local model = require('config.git_review.tree').new(root, counted)
assert(model:rows()[1].id == branch_id and model:rows()[1].label == 'main (current)')
assert(model:initial_selection().kind == 'unstaged')
assert(model:up() == branch_id)
local rows = model:rows()
assert(#rows == 4 and rows[1].id == 'branches')
assert(rows[2].id == branch_id and rows[3].id == feature_id and rows[4].id == remote_id)
model:drill(feature_id)
rows = model:rows()
assert(rows[1].label == 'feature/tree')
for _, row in ipairs(rows) do
  assert(row.kind ~= 'unstaged' and row.kind ~= 'staged', 'working changes belong only to the checked-out branch')
end
local feature_commit = feature_id .. ':commit:' .. feature_hash
model:drill(feature_commit)
local selection = model:selection(feature_commit .. ':file:first.txt')
assert(selection.hash == feature_hash and selection.parent == shared_hash)
assert(selection.branch_ref == 'refs/heads/feature/tree')
assert(not model:can_stage(selection.id) and not pcall(model.stage, model, selection.id))
model:up()
local feature_shared = feature_id .. ':commit:' .. shared_hash
model:expand(feature_shared)
model:expand(commit_id(shared_hash))
local left = model:selection(feature_shared .. ':file:first.txt')
local right = model:selection(commit_id(shared_hash) .. ':file:first.txt')
assert(left.id ~= right.id and left.hash == right.hash, 'shared commits need distinct branch-scoped node IDs')
assert(file_queries[shared_hash] == 1, 'immutable commit file data should be shared across branches')
model:drill(remote_id)
model:expand(remote_id .. ':commit:' .. feature_hash)
local remote = model:selection(remote_id .. ':commit:' .. feature_hash .. ':file:first.txt')
assert(remote.hash == selection.hash and remote.id ~= selection.id)
assert(not model:can_stage(remote.id))
assert(file_queries[feature_hash] == 1)
-- Ref changes must rebuild only affected history and preserve a valid root.
git('branch', 'new-branch')
assert(model:refresh())
assert(model:rows()[1].id == remote_id)
git('branch', '-D', 'feature/tree')
assert(model:refresh())
model:up()
for _, row in ipairs(model:rows()) do assert(row.id ~= feature_id) end
unchanged()
print('PASS: branch folders, working-state ownership, shared commits, remote browsing, and ref refresh')
'''

PAGINATION = r'''
local queries, file_queries = {}, 0
local branches = {
  {ref='refs/heads/main', name='main', hash='main-tip', current=true, worktree=vim.fn.getcwd()},
  {ref='refs/heads/other', name='other', hash='other-tip', current=false},
}
local repository = {
  status = function() return {unstaged={}, staged={}} end,
  branches = function() return branches end,
  commits = function(_, ref, maximum)
    queries[ref] = (queries[ref] or 0) + 1
    local result = {}
    for index=1, math.min(maximum, 225) do
      result[index] = {hash=index == 1 and 'shared' or ref .. '-' .. index, short=tostring(index), subject='history', author='Test', parents={}}
    end
    return result
  end,
  commit_files = function()
    file_queries = file_queries + 1
    return {{path='shared.txt', status='M'}}, 'parent'
  end,
}
local model = require('config.git_review.tree').new(vim.fn.getcwd(), repository)
local other = 'branch:refs/heads/other'
assert(queries['main-tip'] == 1 and not queries['other-tip'], 'other branch history must load lazily')
model:up()
model:expand(other)
assert(queries['other-tip'] == 1)
assert(not model:refresh() and queries['main-tip'] == 1 and queries['other-tip'] == 1)
model:drill(branch_id)
assert(model:expand(node_id('more')) == commit_id('main-tip-101'))
assert(queries['main-tip'] == 2 and queries['other-tip'] == 1)
model:drill(other)
local before = model:rows()
assert(before[#before].id == other .. ':more')
assert(model:expand(other .. ':more') == other .. ':commit:other-tip-101')
assert(queries['other-tip'] == 2)
model:expand(commit_id('shared'))
model:expand(other .. ':commit:shared')
assert(file_queries == 1)
branches[2].hash = 'new-other-tip'
assert(model:refresh() and queries['new-other-tip'] == 1 and queries['main-tip'] == 2)
branches[2] = nil
assert(model:refresh() and model:rows()[1].id == 'branches', 'deleted branch roots must fall back safely')
print('PASS: lazy branch histories, independent pagination, tip invalidation, and deleted roots')
'''

CHECKOUT = r'''
local repository = require('config.git_review.repository')
local root = vim.fn.getcwd()
local model = require('config.git_review.tree').new(root, repository)
local function git(...)
  local result = vim.system({'git', ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
git('switch', '-q', '-c', 'other')
local index = git('diff', '--cached')
local ok, err = pcall(model.stage, model, node_id('unstaged:file:first.txt'))
assert(not ok and tostring(err):find('checked%-out branch changed'))
assert(git('diff', '--cached') == index, 'stale branch nodes must never stage the new branch worktree')
assert(model:rows()[1].id == 'branch:refs/heads/other')
local rows = model:rows()
for _, row in ipairs(rows) do
  if row.kind == 'unstaged' or row.kind == 'staged' then assert(row.id:find('branch:refs/heads/other:', 1, true) == 1) end
end
git('switch', '-q', '--detach', 'HEAD')
assert(model:refresh())
assert(model:rows()[1].id == 'branch:HEAD')
assert(model:rows()[1].label:find('Detached HEAD', 1, true))
assert(repository.branches(root)[1].ref == 'HEAD')
print('PASS: external checkout, stale-staging guard, and detached HEAD')
'''

UNBORN = r'''
local repository = require('config.git_review.repository')
local root = vim.fn.getcwd()
local branches = repository.branches(root)
assert(#branches == 1 and branches[1].current and branches[1].name == 'main' and not branches[1].hash)
local model = require('config.git_review.tree').new(root, repository)
assert(model:rows()[1].id == branch_id)
assert(model:initial_selection().path == 'first.txt')
model:up()
assert(#model:rows() == 2 and model:rows()[1].id == 'branches')
model:drill(branch_id)
assert(model:stage(node_id('unstaged:file:first.txt')) == node_id('staged:file:first.txt'))
print('PASS: unborn branch folder, initial selection, and staging')
'''

WORKFLOW = SETUP + r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
local spec = require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
vim.keymap.set('n', spec.keys[1][1], spec.keys[1][2])
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(50)
  api.nvim_exec_autocmds('CursorMoved', {})
end
vim.cmd.edit('first.txt')
press(' gd')
local review = require('config.git_review')
local tab = api.nvim_get_current_tabpage()
local windows = api.nvim_tabpage_list_wins(tab)
local sidebar
for _, window in ipairs(windows) do
  if vim.bo[api.nvim_win_get_buf(window)].filetype == 'GitReview' then sidebar = window end
end
local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(sidebar), 0, -1, false) end
local function choose(label)
  api.nvim_set_current_win(sidebar)
  for row, line in ipairs(lines()) do
    if line:find(label, 1, true) then press(row .. 'G'); return end
  end
  error('Missing branch browser entry: ' .. label)
end
local function title(expected, branch)
  if expected == 'feature: branch change' then expected = (branch or 'feature/tree') .. ' · Test · ' .. expected
  elseif expected == 'Unstaged changes' then expected = 'main · ' .. expected end
  local text = vim.trim(api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=200}).str)
  assert(text == expected, 'Expected ' .. expected .. ', got ' .. text)
  assert(api.nvim_get_current_tabpage() == tab and vim.deep_equal(api.nvim_tabpage_list_wins(tab), windows))
end
title('main')
assert(lines()[1]:find('main (current)', 1, true))
press('H')
assert(lines()[1]:find('Branches:', 1, true))
choose('feature/tree')
title('feature/tree')
press('L')
for _, line in ipairs(lines()) do assert(not line:find('Staged files', 1, true) and not line:find('Unstaged files', 1, true)) end
choose('feature: branch change')
press('L')
choose('first.txt')
press('l')
title('feature: branch change')
assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'feature branch content')
unchanged()
review.focus_sidebar()
press('H')
title('feature: branch change') -- Cursor is the commit just left.
press('H')
choose('main (current)')
press('L')
choose('first.txt')
press('l')
title('Unstaged changes')
assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'main worktree content')
review.focus_sidebar()
press('H')
choose('origin/topic')
title('origin/topic')
press('<C-l>')
title('Unstaged changes')
press('<C-h>')
title('origin/topic')
press('L')
choose('feature: branch change')
press('L')
choose('first.txt')
press('l')
title('feature: branch change', 'origin/topic')
review.refresh(true)
title('feature: branch change', 'origin/topic')
unchanged()
press(' q')
assert(#api.nvim_list_tabpages() == 1)
print('PASS: local/remote branch folders, branch headers, live diffs, stable windows, no checkout')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class BranchReview(unittest.TestCase):
    def run_lua(self, lua, *, plugins=False, unborn=False):
        review_tests.GitReview.run_lua(self, lua, plugins=plugins, unborn=unborn)

    def test_branch_queries(self):
        self.run_lua(REPOSITORY)

    def test_branch_scoped_tree(self):
        self.run_lua(TREE)

    def test_lazy_histories_and_independent_pagination(self):
        self.run_lua(PAGINATION)

    def test_external_checkout_and_detached_head(self):
        self.run_lua(CHECKOUT)

    def test_unborn_branch(self):
        self.run_lua(UNBORN, unborn=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_branch_browser_workflow(self):
        self.run_lua(WORKFLOW, plugins=True)


if __name__ == '__main__':
    unittest.main()
