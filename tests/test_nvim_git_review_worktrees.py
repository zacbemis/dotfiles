"""Review linked worktrees without changing checkout, index, or editor cwd."""
import shutil
import unittest

import test_nvim_git_review as review_tests

SETUP = r'''
local repository = require('config.git_review.repository')
local root = vim.fn.getcwd()
local workspace = root .. '/worktree fixtures'
local linked = workspace .. '/linked tree'
local linked_id = 'branch:refs/heads/linked'
local function git(path, ...)
  local result = vim.system({'git', '-C', path, ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
vim.fn.writefile({'/worktree fixtures/'}, root .. '/.git/info/exclude', 'a')
vim.fn.mkdir(workspace)
git(root, 'worktree', 'add', '-qb', 'linked', linked)
git(root, 'branch', 'history-only')
vim.fn.writefile({'linked worktree line'}, linked .. '/first.txt')
vim.fn.writefile({'linked staged line'}, linked .. '/staged.txt')
git(linked, 'add', 'staged.txt')
local main_status = git(root, 'status', '--porcelain')
local main_index = git(root, 'write-tree')
local function unchanged()
  assert(vim.fn.getcwd() == root)
  assert(git(root, 'symbolic-ref', 'HEAD') == 'refs/heads/main')
  assert(git(root, 'status', '--porcelain') == main_status)
  assert(git(root, 'write-tree') == main_index)
end
'''

MODEL = SETUP + r'''
local detached = workspace .. '/detached\ncheckout'
local missing = workspace .. '/unavailable'
local replaced = workspace .. '/replaced'
git(root, 'worktree', 'add', '-q', '--detach', detached)
git(root, 'worktree', 'add', '-qb', 'unavailable', missing)
git(root, 'worktree', 'lock', missing)
assert(vim.fn.delete(missing, 'rf') == 0)
git(root, 'worktree', 'add', '-qb', 'replaced', replaced)
assert(vim.fn.rename(replaced, replaced .. '-backup') == 0)
git(root, 'init', '-q', replaced)
vim.fn.writefile({'detached worktree line'}, detached .. '/first.txt')
local detached_id = 'worktree:' .. vim.json.encode(detached)
local queried = {}
local counted = vim.tbl_extend('force', repository, {
  status = function(path)
    queried[path] = (queried[path] or 0) + 1
    return repository.status(path)
  end,
})
local model = require('config.git_review.tree').new(root, counted)
assert(model:rows()[1].id == branch_id)
model:up()
for _, row in ipairs(model:rows()) do
  if row.id == 'branch:refs/heads/unavailable' then assert(row.label == 'unavailable') end
  if row.id == 'branch:refs/heads/replaced' then assert(row.label == 'replaced') end
end
assert(not queried[linked] and not queried[detached], 'status should be lazy for unopened worktrees')
model:drill('branch:refs/heads/history-only')
for _, row in ipairs(model:rows()) do assert(not model:can_stage(row.id)) end
model:up()
model:drill(linked_id)
local function file(branch, section, path) return branch .. ':' .. section .. ':file:' .. path end
local linked_file = file(linked_id, 'unstaged', 'first.txt')
assert(model:selection(linked_file).root == linked)
local staged_file = file(linked_id, 'staged', 'first.txt')
assert(model:stage(linked_file) == staged_file)
assert(git(linked, 'show', ':first.txt') == 'linked worktree line')
assert(model:stage(staged_file) == linked_file)
assert(git(linked, 'diff', '--cached', '--', 'first.txt') == '')
assert(queried[linked] and not queried[detached])
model:up()
model:drill(detached_id)
assert(model:rows()[1].label:find('detached HEAD', 1, true))
assert(model:selection(file(detached_id, 'unstaged', 'first.txt')).root == detached)
local from_linked = require('config.git_review.tree').new(linked, repository)
assert(from_linked:rows()[1].id == linked_id and from_linked:initial_selection().root == linked)
from_linked:up()
from_linked:drill(branch_id)
assert(from_linked:selection(node_id('unstaged:file:first.txt')).root == root)
-- A path switch must not stage a stale node against the same branch at its new location.
local moved = workspace .. '/moved tree'
git(root, 'worktree', 'move', linked, moved)
local ok, err = pcall(model.stage, model, linked_file)
assert(not ok and err:find('worktree moved', 1, true), tostring(err))
assert(git(moved, 'diff', '--cached', '--', 'first.txt') == '')
assert(model:selection(linked_file).root == moved)
git(root, 'worktree', 'remove', '--force', moved)
assert(model:refresh())
model:drill(linked_id)
assert(not model:can_stage(linked_file) and not model:selection(linked_file))
unchanged()
'''

WORKFLOW = SETUP + r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
local review = require('config.git_review')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
end
local function choose(label)
  review.focus_sidebar()
  assert(vim.bo.filetype == 'GitReview')
  for row, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(label, 1, true) then api.nvim_win_set_cursor(0, {row, 0}); return end
  end
  error('missing entry: ' .. label)
end
local function assert_diff(path, text)
  assert(vim.wo.diff and api.nvim_buf_get_lines(0, 0, 1, false)[1] == text)
  assert(api.nvim_buf_get_name(0) == path)
  assert(#api.nvim_list_tabpages() == 2, 'switching roots must not leak review tabs')
  assert(review.is_active())
end
vim.cmd.edit('first.txt')
review.open()
choose('main (current)')
press('H')
choose('linked (worktree:')
press('L')
choose('first.txt')
press('l')
assert_diff(linked .. '/first.txt', 'linked worktree line')
assert(vim.o.tabline:find('worktree:', 1, true) and vim.o.tabline:find('linked tree', 1, true))
assert(vim.o.tabline:find('Unstaged changes', 1, true))
choose('first.txt')
press('s')
assert(git(linked, 'show', ':first.txt') == 'linked worktree line')
assert(vim.bo.filetype == 'GitReview')
press('s')
assert(git(linked, 'diff', '--cached', '--', 'first.txt') == '')
-- Updating another worktree must refresh the existing sidebar without losing focus.
vim.fn.writefile({'created externally'}, linked .. '/external.txt')
review.refresh()
choose('external.txt')
press('l')
assert_diff(linked .. '/external.txt', 'created externally')
choose('staged.txt')
press('l')
local index_buffer, linked_tab = api.nvim_get_current_buf(), api.nvim_get_current_tabpage()
assert(api.nvim_buf_get_name(index_buffer):match('^diffview://'))
assert(api.nvim_buf_get_lines(index_buffer, 0, 1, false)[1] == 'linked staged line')
api.nvim_buf_set_lines(index_buffer, 0, -1, false, {'pending index edit'})
review.focus_sidebar()
press('H')
choose('main (current)')
press('L')
choose('first.txt')
press('l')
assert(api.nvim_get_current_tabpage() == linked_tab and vim.bo[index_buffer].modified,
  'switching worktrees must protect unsaved index edits')
vim.bo[index_buffer].modified = false
press('l')
assert_diff(root .. '/first.txt', 'working change')
unchanged()
press(' q')
assert(#api.nvim_list_tabpages() == 1 and api.nvim_buf_get_name(0) == root .. '/first.txt')
'''


SWITCH = SETUP + r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
vim.opt.autoread = true
local plugin = vim.env.NVIM_PLUGINS:match('^[^:]+')
vim.opt.runtimepath:append(vim.fs.dirname(plugin) .. '/nvim-tree.lua')
local explorer = require('plugins.explorer')[1]
explorer.config(nil, explorer.opts)
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
local review = require('config.git_review')
local function press(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end
local function choose(label)
  review.focus_sidebar()
  for row, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(label, 1, true) then api.nvim_win_set_cursor(0, {row, 0}); return end
  end
  error('missing entry: ' .. label)
end
local notice = ''
vim.notify = function(message) notice = message end
local function wait_for_notice(text)
  assert(vim.wait(5000, function() return notice:find(text, 1, true) ~= nil end), notice)
  notice = ''
end
-- Make a branch whose checkout conflicts with the original worktree's local changes.
local donot_switch = workspace .. '/branch preparation'
git(root, 'worktree', 'add', '-qb', 'other-local', donot_switch)
vim.fn.writefile({'other branch committed'}, donot_switch .. '/first.txt')
git(donot_switch, 'commit', '-qam', 'other branch content')
git(root, 'worktree', 'remove', donot_switch)
git(root, 'update-ref', 'refs/remotes/origin/remote-only', 'HEAD')
vim.cmd.edit('first.txt')
local origin_tab = api.nvim_get_current_tabpage()
review.open()
local review_tab = api.nvim_get_current_tabpage()
press('H')
choose('linked (worktree:')
press('L')
assert(git(root, 'symbolic-ref', 'HEAD') == 'refs/heads/main')
assert(vim.o.tabline:find('worktree:', 1, true), 'L must only browse')
local function unnamed()
  local result = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == '' and api.nvim_buf_get_name(buf) == '' then
      result[#result + 1] = buf
    end
  end
  return result
end
assert(#unnamed() == 0, 'opening review must not leak a listed unnamed buffer')
local review_windows, review_cwd = api.nvim_tabpage_list_wins(review_tab), vim.fn.getcwd()
vim.env.WAYLAND_DISPLAY, vim.env.DISPLAY = nil, nil
press('gS')
local worktree_tab = api.nvim_get_current_tabpage()
assert(worktree_tab ~= review_tab and worktree_tab ~= origin_tab and #api.nvim_list_tabpages() == 3)
assert(vim.fn.getcwd() == linked and vim.fn.getcwd(-1, -1) == root)
assert(vim.bo.filetype == 'NvimTree' and require('nvim-tree.api').tree.get_nodes().absolute_path == linked)
assert(#unnamed() == 0, 'the new editor tab must not leave a [No Name] buffer behind')
review.focus_sidebar()
assert(api.nvim_get_current_tabpage() == review_tab and vim.deep_equal(review_windows, api.nvim_tabpage_list_wins(review_tab)))
assert(vim.fn.getcwd() == review_cwd and api.nvim_get_current_line():find('linked (worktree:', 1, true))
-- A desktop launch uses a new Kitty process without creating an editor tab.
local launcher = workspace .. '/bin'
vim.fn.mkdir(launcher)
local launch_record = workspace .. '/kitty launch'
vim.env.PATH = launcher .. ':' .. vim.env.PATH
vim.env.WORKTREE_LAUNCH_TEST = launch_record
vim.fn.writefile({'#!/bin/sh', 'printf "%s\\n" "$@" > "$WORKTREE_LAUNCH_TEST"'}, launcher .. '/kitty')
assert(vim.uv.fs_chmod(launcher .. '/kitty', 493))
vim.env.DISPLAY = ':test'
press('gS')
assert(vim.wait(2000, function() return vim.fn.getfsize(launch_record) > 0 end), notice)
assert(vim.deep_equal(vim.fn.readfile(launch_record), {'--directory', linked, vim.v.progpath}))
assert(api.nvim_get_current_tabpage() == review_tab and review.is_active() and #api.nvim_list_tabpages() == 3)
press('H')
choose('origin/remote-only')
press('gS')
wait_for_notice('Remote-tracking branches are read-only')
choose('other-local')
press('gS')
wait_for_notice('would be overwritten')
assert(git(root, 'symbolic-ref', 'HEAD') == 'refs/heads/main')
assert(vim.fn.readfile(root .. '/first.txt')[1] == 'working change')
-- Save a clean checkout on disk, but keep a real Neovim buffer unsaved.
git(root, 'restore', 'first.txt')
local main_buffer = vim.fn.bufnr(root .. '/first.txt')
api.nvim_buf_set_lines(main_buffer, 0, -1, false, {'unsaved edit'})
choose('other-local')
press('gS')
wait_for_notice('Save or close modified files')
assert(git(root, 'symbolic-ref', 'HEAD') == 'refs/heads/main')
vim.bo[main_buffer].modified = false
press('gS')
assert(vim.wait(5000, function()
  return review.is_active() and api.nvim_get_current_line():find('other-local (current)', 1, true)
end), 'review did not update after checkout: ' .. notice)
assert(git(root, 'symbolic-ref', 'HEAD') == 'refs/heads/other-local')
assert(git(root, 'write-tree') ~= main_index, 'the branch change should update the index')
assert(git(root, 'show', ':staged.txt') == 'index change', 'checkout must preserve nonconflicting staged changes')
assert(git(linked, 'symbolic-ref', 'HEAD') == 'refs/heads/linked')
assert(git(linked, 'show', ':staged.txt') == 'linked staged line')
press(' q')
assert(not review.is_active() and api.nvim_get_current_tabpage() == origin_tab)
assert(api.nvim_tabpage_is_valid(worktree_tab) and #api.nvim_list_tabpages() == 2)
assert(#unnamed() == 0 and vim.fn.getcwd() == root)
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class WorktreeReview(unittest.TestCase):
    def test_discovery_and_index_isolation(self):
        review_tests.GitReview.run_lua(self, MODEL)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES),
                         'Plugins are not installed')
    def test_switch_between_worktree_diffs(self):
        review_tests.GitReview.run_lua(self, WORKFLOW, plugins=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir()
                             for name in (*review_tests.DEPENDENCIES, 'nvim-tree.lua')), 'Plugins are not installed')
    def test_open_separate_worktree_and_checkout_local_branch(self):
        review_tests.GitReview.run_lua(self, SWITCH, plugins=True)


if __name__ == '__main__':
    unittest.main()
