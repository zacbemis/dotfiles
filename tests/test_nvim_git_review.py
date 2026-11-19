"""Git-review model and real Diffview workflows, entirely in temporary repositories."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim/lazy"
DEPENDENCIES = ("diffview.nvim", "plenary.nvim", "nvim-web-devicons", "bufferline.nvim")

MODEL = r'''
local repository = require('config.git_review.repository')
local root = repository.root(vim.fn.getcwd())
local status = repository.status(root)
assert(#status.staged == 1 and status.staged[1].path == 'staged.txt')
local found = {}
for _, file in ipairs(status.unstaged) do found[file.path] = true end
assert(found['first.txt'] and found['nested/new file.txt'] and found['tab\tname.txt'])
local commits = repository.commits(root, 'HEAD', 20)
assert(#commits == 2 and commits[1].subject == 'test: update fixture')
assert(commits[1].author == 'Test' and commits[1].parents[1] == commits[2].hash and #commits[2].parents == 0)
local files, parent = repository.commit_files(root, commits[1].hash)
assert(parent == commits[2].hash and #files == 1 and files[1].path == 'first.txt')
local original, no_parent = repository.commit_files(root, commits[2].hash)
assert(not no_parent and #original == 2)
local model = require('config.git_review.tree').new(root, repository)
local top = {}
for _, row in ipairs(model:rows()) do if row.depth == 1 then top[#top + 1] = row end end
assert(model:rows()[1].id == branch_id and model:rows()[1].label == 'main (current)')
assert(top[1].id == node_id('unstaged') and top[2].id == node_id('staged'))
assert(top[3].id == commit_id(commits[1].hash) and top[4].id == commit_id(commits[2].hash))
assert(model:context(commit_id(commits[1].hash)).subject == 'test: update fixture', 'collapsed commits must expose browser context')
assert(model:context(node_id('staged:file:staged.txt')).kind == 'staged')
assert(model:context(node_id('unstaged')).kind == 'unstaged')
assert(not model:context('branches') and not model:context('missing'))
model:drill(commit_id(commits[1].hash))
assert(model:rows()[1].id == commit_id(commits[1].hash))
assert(model:selection(commit_id(commits[1].hash) .. ':file:first.txt').parent == commits[2].hash)
model:up()
assert(model:rows()[1].id == branch_id)
local staged = model:stage(node_id('unstaged:file:first.txt'))
assert(staged == node_id('staged:file:first.txt'))
assert(model:selection(staged).kind == 'staged')
local unstaged = model:stage(staged)
assert(unstaged == node_id('unstaged:file:first.txt'))
assert(not model:can_stage(commit_id(commits[1].hash)))
assert(not pcall(model.stage, model, commit_id(commits[1].hash)), 'commits must be read-only')
local many = { status = function() return {unstaged={}, staged={}} end,
  branches = function(path) return {{ref='refs/heads/main', name='main', hash='tip', current=true, worktree=path}} end,
  commits = function(_, _, maximum)
    local result = {}
    for index = 1, math.min(maximum, 110) do
      result[index] = {hash='commit' .. index, short=tostring(index), subject='history', author='Test', parents={}}
    end
    return result
  end,
  commit_files = function() return {} end,
}
local paged = require('config.git_review.tree').new(root, many)
assert(paged:rows()[#paged:rows()].id == node_id('more'))
paged:expand(node_id('more'))
assert(paged:rows()[#paged:rows()].id == commit_id('commit110'), 'older commit pages must be reachable')
local committed = vim.system({'git','-C',root,'commit','--allow-empty','--allow-empty-message','-m',''}, {text=true}):wait()
assert(committed.code == 0, committed.stderr)
assert(repository.commits(root, 'HEAD', 1)[1].subject == '', 'empty commit subjects must not corrupt log fields')
print('PASS: status, commit order, root commits, filenames, tree roots, staging, pagination')
'''

FLAT_FILES = r'''
local root = vim.fn.getcwd()
local status = {
  unstaged = {
    {path='z/deep/shared.lua', status='M'},
    {path='nested/alpha.lua', status='A'},
    {path='a/shared.lua', status='D'},
  },
  staged = {{path='staged/deep/file.lua', status='M'}},
}
local function move(from, to, path)
  for index, file in ipairs(status[from]) do
    if file.path == path then
      table.insert(status[to], table.remove(status[from], index))
      return
    end
  end
  error('Unexpected Git path: ' .. tostring(path))
end
local repository = {
  status = function() return vim.deepcopy(status) end,
  branches = function(path) return {{ref='refs/heads/main', name='main', hash='commit', current=true, worktree=path}} end,
  commits = function() return {{hash='commit', short='abc123', subject='nested files', author='Test', parents={}}} end,
  commit_files = function() return {
    {path='z/deep/shared.lua', status='M'},
    {path='nested/alpha.lua', status='A'},
    {path='a/shared.lua', status='D'},
  }, 'parent' end,
  stage = function(directory, path) assert(directory == root); move('unstaged', 'staged', path) end,
  unstage = function(directory, path) assert(directory == root); move('staged', 'unstaged', path) end,
}
local model = require('config.git_review.tree').new(root, repository)
local function check_files(section, paths)
  model:drill(section)
  local rows = model:rows()
  assert(#rows == #paths + 1, 'only files should appear beneath a section or commit')
  for index, path in ipairs(paths) do
    local row = rows[index + 1]
    assert(row.kind == 'file' and row.depth == 1, 'nested files must be direct children')
    assert(row.label == vim.fs.basename(path) and not row.label:find('/', 1, true))
    assert(model:selection(row.id).path == path, 'retain full paths for Git operations')
  end
  model:up()
end
local paths = {'nested/alpha.lua', 'a/shared.lua', 'z/deep/shared.lua'}
check_files(node_id('unstaged'), paths)
check_files(node_id('staged'), {'staged/deep/file.lua'})
check_files(commit_id('commit'), paths)
local selection = model:selection(commit_id('commit') .. ':file:z/deep/shared.lua')
assert(selection.hash == 'commit' and selection.parent == 'parent')
assert(model:stage(node_id('unstaged:file:z/deep/shared.lua')) == node_id('staged:file:z/deep/shared.lua'))
check_files(node_id('staged'), {'staged/deep/file.lua', 'z/deep/shared.lua'})
assert(model:stage(node_id('staged:file:z/deep/shared.lua')) == node_id('unstaged:file:z/deep/shared.lua'))
check_files(node_id('unstaged'), paths)
check_files(commit_id('commit'), paths)
model:expand(node_id('unstaged'))
local selected
local sidebar = require('config.git_review.sidebar').new(model, {
  select = function(file) selected = file end,
  stage = function() end, refresh = function() end, close = function() end,
  toggle_sidebar = function() end, context_changed = function() end,
})
sidebar:attach()
for _, path in ipairs({'a/shared.lua', 'z/deep/shared.lua'}) do
  sidebar:render(node_id('unstaged:file:' .. path))
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    assert(not line:find('/', 1, true), 'sidebar must not display directory paths')
  end
  vim.api.nvim_feedkeys('l', 'xt', false)
  assert(selected.path == path, 'duplicate basenames must open their own full paths')
end
sidebar:dispose()
print('PASS: flat filenames, stable duplicate order, original paths, staging, sidebar selection')
'''

WORKFLOW = r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
local spec = require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
assert(#spec.keys == 1 and spec.keys[1][1] == '<leader>gd', 'Git review must have one entry point')
vim.keymap.set('n', spec.keys[1][1], spec.keys[1][2])
vim.cmd.edit('first.txt')
local original_buffer = api.nvim_get_current_buf()
api.nvim_buf_set_lines(original_buffer, 0, -1, false, {'unsaved editor content'})
vim.cmd.vsplit()
local original_tab, original_window = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
local original_windows = api.nvim_tabpage_list_wins(original_tab)
local review = require('config.git_review')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(100)
end
local function sidebar(optional)
  for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(window)].filetype == 'GitReview' then return window end
  end
  if not optional then error('Review sidebar is missing') end
end
local function lines()
  return api.nvim_buf_get_lines(api.nvim_win_get_buf(sidebar()), 0, -1, false)
end
local function choose(label)
  api.nvim_set_current_win(sidebar())
  for row, line in ipairs(lines()) do
    if line:find(label, 1, true) then api.nvim_win_set_cursor(sidebar(), {row, 0}); return row end
  end
  error('Missing sidebar entry: ' .. label .. '\n' .. table.concat(lines(), '\n'))
end
local function contains(text)
  for _, line in ipairs(lines()) do if line:find(text, 1, true) then return true end end
  return false
end
local function preview(text)
  assert(vim.wait(5000, function()
    for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
      if vim.wo[window].diff then
        local content = api.nvim_buf_get_lines(api.nvim_win_get_buf(window), 0, -1, false)
        if content[1] == text then return true end
      end
    end
    return false
  end, 10), 'Expected diff content: ' .. text)
  assert(#api.nvim_list_tabpages() == 2, 'switching comparisons must not stack tabs')
  for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
    assert(vim.bo[api.nvim_win_get_buf(window)].filetype ~= 'DiffviewFiles', 'stock panel must stay hidden')
  end
end
local function restored()
  assert(api.nvim_get_current_tabpage() == original_tab)
  assert(api.nvim_get_current_win() == original_window)
  assert(#api.nvim_tabpage_list_wins(original_tab) == #original_windows)
  for _, window in ipairs(original_windows) do assert(api.nvim_win_is_valid(window)) end
  assert(vim.bo[original_buffer].modified)
  assert(api.nvim_buf_get_lines(original_buffer, 0, -1, false)[1] == 'unsaved editor content')
end
assert(review.toggle_sidebar() == false, 'outside review the normal explorer must handle Space e')
press(' gd')
local review_tab = api.nvim_get_current_tabpage()
assert(review_tab ~= original_tab)
api.nvim_set_current_tabpage(original_tab)
assert(review.toggle_sidebar() == false, 'a review in another tab must not intercept the explorer toggle')
assert(api.nvim_get_current_tabpage() == original_tab)
api.nvim_set_current_tabpage(review_tab)
assert(contains('Unstaged files') and contains('Staged files'))
assert(choose('Unstaged files') < choose('Staged files'))
assert(choose('Staged files') < choose('test: update fixture'))
assert(choose('test: update fixture') < choose('test: add fixture'))
choose('test: update fixture')
press('L')
assert(lines()[1]:find('test: update fixture', 1, true), 'L must make a commit the parent')
local selected_row = choose('first.txt')
local sidebar_buffer = api.nvim_win_get_buf(sidebar())
local sidebar_lines = lines()
press(' e')
assert(not sidebar(true), 'Space e in the sidebar must hide it')
assert(vim.bo.filetype ~= 'GitReview', 'hiding the focused sidebar must focus a diff pane')
press(' e')
assert(vim.bo.filetype == 'GitReview', 'reopening must focus the sidebar')
assert(api.nvim_win_get_buf(sidebar()) == sidebar_buffer, 'toggle must reuse the sidebar buffer')
assert(api.nvim_win_get_cursor(sidebar())[1] == selected_row, 'toggle must preserve selection')
assert(vim.deep_equal(lines(), sidebar_lines), 'toggle must preserve the current root and expansions')
choose('first.txt')
press('l')
preview('committed change')
for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
  if vim.wo[window].diff then
    api.nvim_set_current_win(window)
    press(' e')
    assert(not sidebar(true), 'Space e from either diff pane must hide the sidebar')
    assert(api.nvim_get_current_win() == window, 'hiding from a diff pane must preserve focus')
    press(' e')
    assert(vim.bo.filetype == 'GitReview', 'Space e from either pane must reopen and focus the sidebar')
  end
end
press('H')
assert(lines()[1]:find('main (current)', 1, true), 'H must return to the current branch')
choose('test: update fixture')
press('l')
press('h')
assert(lines()[api.nvim_win_get_cursor(sidebar())[1]]:find('▸', 1, true), 'h must collapse a commit')
choose('test: add fixture')
press('L')
choose('first.txt')
press('l')
preview('original')
review.focus_sidebar()
press('H')
choose('staged.txt')
press('l')
preview('index change')
local index_buffer = api.nvim_get_current_buf()
assert(api.nvim_buf_get_name(index_buffer):match('^diffview://'), api.nvim_buf_get_name(index_buffer))
local index_lines = api.nvim_buf_get_lines(index_buffer, 0, -1, false)
api.nvim_buf_set_lines(index_buffer, 0, -1, false, {'pending index edit'})
press(' e')
assert(not sidebar(true) and vim.bo[index_buffer].modified, 'hiding must preserve unsaved index edits')
press(' e')
require('config.git_review.diffview').focus_file(api.nvim_get_current_tabpage())
local protected_tab = api.nvim_get_current_tabpage()
assert(not review.close(), 'unsaved index edits must block closing the review with Space q')
assert(api.nvim_tabpage_is_valid(protected_tab))
api.nvim_buf_set_lines(index_buffer, 0, -1, false, index_lines)
vim.bo[index_buffer].modified = false
local root = require('config.git_review.repository').root(vim.fn.getcwd())
press(' e')
assert(not sidebar(true))
for _ = 1, 3 do
  review.select({root=root, kind='unstaged', path='first.txt', id=node_id('unstaged:file:first.txt'), branch_name='main'})
  review.select({root=root, kind='staged', path='staged.txt', id=node_id('staged:file:staged.txt'), branch_name='main'})
  assert(not sidebar(true), 'switching comparisons must keep the sidebar hidden')
end
preview('index change')
press(' e')
assert(vim.bo.filetype == 'GitReview')
choose('first.txt')
press('s')
assert(contains('Staged files (2)'), 'staging must move the file into the staged section')
press('s')
assert(contains('Staged files (1)'), 'unstaging must move the file back')
assert(contains('new file.txt') and not contains('nested'), 'nested files must appear without folders')
choose('new file.txt')
press('l')
preview('new')
review.focus_sidebar()
choose('Unstaged files')
press('L')
assert(lines()[1]:find('Unstaged files', 1, true))
press('H')
assert(lines()[1]:find('main (current)', 1, true))
press(' q')
restored()
press(' gd')
choose('first.txt')
press('l')
preview('unsaved editor content')
review.focus_sidebar()
press(' q')
restored()
press(' gd')
choose('first.txt')
press('l')
local diff_window = api.nvim_get_current_win()
press(' e')
assert(not sidebar(true))
local added = vim.system({'git','add','--','first.txt'}, {text=true}):wait()
assert(added.code == 0, added.stderr)
review.refresh()
assert(not sidebar(true), 'automatic refresh must not reopen the hidden sidebar')
assert(vim.bo.filetype ~= 'GitReview', 'automatic refresh must not steal focus into the sidebar')
press(' e')
assert(contains('Staged files (2)'), 'external staging must refresh the hidden tree')
require('config.git_review.diffview').focus_file(api.nvim_get_current_tabpage())
local committed = vim.system({'git','commit','-m','test: commit staged changes'}, {text=true}):wait()
assert(committed.code == 0, committed.stderr)
review.refresh()
assert(contains('Staged files (0)'))
assert(contains('test: commit staged changes'), 'new commits must appear after the two working sections')
vim.wait(100)
press(' q')
restored()
print('PASS: unified review, commit roots, staging, external commits, unsaved buffers, all exits')
'''

STABLE_LAYOUT = r'''
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
assert(sidebar)
api.nvim_win_set_width(sidebar, 40)
local sidebar_buffer = api.nvim_win_get_buf(sidebar)
local events = {}
local group = api.nvim_create_augroup('TestStableReviewLayout', {clear=true})
api.nvim_create_autocmd({'TabNew', 'TabClosed', 'TabEnter', 'WinNew', 'WinClosed'}, {
  group=group, callback=function(event)
    -- nvim_buf_call may close an invisible autocmd window while detecting a
    -- new filetype. Only closing an actual review window resets the layout.
    if event.event ~= 'WinClosed' or vim.tbl_contains(windows, tonumber(event.match)) then
      events[#events+1] = event.event
    end
  end,
})
local function stable()
  assert(api.nvim_get_current_tabpage() == tab, 'file selection must reuse the review tab')
  assert(vim.deep_equal(api.nvim_tabpage_list_wins(tab), windows), 'file selection must reuse every window')
  assert(api.nvim_win_get_buf(sidebar) == sidebar_buffer)
  assert(api.nvim_win_get_width(sidebar) == 40, 'file selection must preserve sidebar width')
  assert(#events == 0, 'file selection must not rebuild or leave the layout: ' .. table.concat(events, ', '))
end
local function choose(label)
  api.nvim_set_current_win(sidebar)
  for row, line in ipairs(api.nvim_buf_get_lines(sidebar_buffer, 0, -1, false)) do
    if line:find(label, 1, true) then api.nvim_win_set_cursor(sidebar, {row,0}); return end
  end
  error('Missing sidebar entry: ' .. label)
end
local function preview(text)
  assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == text, 'Expected current file content: ' .. text)
  stable()
end
choose('first.txt')
press('l')
preview('working change')
choose('new file.txt')
press('l')
preview('new')
choose('staged.txt')
press('l')
preview('index change')
-- New index data must not reuse stale content from the previous stage buffer.
vim.fn.writefile({'updated index content'}, 'staged.txt')
assert(vim.system({'git','add','--','staged.txt'}):wait().code == 0)
review.refresh(true)
preview('updated index content')
review.refresh(true)
local index_buffer = api.nvim_get_current_buf()
api.nvim_buf_set_lines(index_buffer, 0, -1, false, {'updated index content'})
vim.cmd.write()
assert(not vim.bo[index_buffer].modified, 'shared stage buffers must retain their native index-write handler')
stable()
choose('test: update fixture')
press('L')
choose('first.txt')
press('l')
preview('committed change')
review.focus_sidebar()
press('H')
choose('test: add fixture')
press('L')
choose('first.txt')
press('l')
preview('original')
review.focus_sidebar()
choose('staged.txt')
press('l')
preview('base')
review.focus_sidebar()
press('H')
choose('Unstaged files')
press('L')
choose('first.txt')
press('s')
stable()
-- A failed selection must leave the current review alive and usable.
local original_notify, notifications = vim.notify, {}
vim.notify = function(message) notifications[#notifications+1] = tostring(message) end
local root = require('config.git_review.repository').root(vim.fn.getcwd())
review.select({root=root, kind='unstaged', path='does-not-exist.txt'})
vim.notify = original_notify
assert(#notifications == 1 and notifications[1]:find('no longer', 1, true))
assert(review.is_active())
stable()
api.nvim_clear_autocmds({group=group})
press(' q')
assert(#api.nvim_list_tabpages() == 1)
print('PASS: stable tab/windows/sidebar across files, stages, commits, refreshes, and failed selections')
'''

CONTEXT_HEADER = r'''
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
  -- -l scripts do not return to Neovim's interactive idle loop, which normally
  -- delivers CursorMoved after input. Dispatch that event explicitly here.
  api.nvim_exec_autocmds('CursorMoved', {})
end
vim.cmd.edit('first.txt')
local editor_tab, original_tabline = api.nvim_get_current_tabpage(), vim.o.tabline
press(' gd')
local review = require('config.git_review')
local tab = api.nvim_get_current_tabpage()
local view = require('diffview.lib').tabpage_to_view(tab)
local windows = api.nvim_tabpage_list_wins(tab)
local sidebar
for _, window in ipairs(windows) do
  if vim.bo[api.nvim_win_get_buf(window)].filetype == 'GitReview' then sidebar = window end
end
local function title(expected)
  if expected ~= 'main' then
    local working = expected == 'Staged changes' or expected == 'Unstaged changes'
    expected = 'main · ' .. (working and '' or 'Test · ') .. expected
  end
  local text = vim.trim(api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=200}).str)
  assert(text == expected, 'Expected header ' .. expected .. ', got ' .. text)
  assert(vim.deep_equal(api.nvim_tabpage_list_wins(tab), windows), 'header changes must not rebuild the layout')
end
local function choose(label)
  api.nvim_set_current_win(sidebar)
  for row, line in ipairs(api.nvim_buf_get_lines(api.nvim_win_get_buf(sidebar), 0, -1, false)) do
    if line:find(label, 1, true) then press(row .. 'G'); return end
  end
  error('Missing browser entry: ' .. label)
end
title('main')
local initial_entry = view.cur_entry
choose('test: add fixture')
title('test: add fixture')
assert(view.cur_entry == initial_entry, 'browsing a collapsed commit must not change the diff')
press('<C-l>')
title('Unstaged changes')
press('<C-h>')
title('test: add fixture')
-- A drilled commit root and its files share the same browser title.
press('L')
title('test: add fixture')
choose('first.txt')
title('test: add fixture')
press('l')
title('test: add fixture')
local original_entry = view.cur_entry
review.focus_sidebar()
press('H')
choose('test: update fixture')
title('test: update fixture')
press('<C-l>')
title('test: add fixture')
assert(view.cur_entry == original_entry, 'changing focus must not load the browsed commit')
press('<C-h>')
title('test: update fixture')
press('l') -- Expand, without opening a different diff.
title('test: update fixture')
press('j')
title('test: update fixture')
press('l') -- Open that commit's file.
title('test: update fixture')
assert(view.cur_entry ~= original_entry)
review.focus_sidebar()
choose('Staged files')
title('Staged changes')
press('<C-l>')
title('test: update fixture')
press('<C-h>')
title('Staged changes')
press('j')
title('Staged changes')
press('l')
title('Staged changes')
review.focus_sidebar()
choose('Unstaged files')
title('Unstaged changes')
press('L')
title('Unstaged changes') -- Same cursor position, different browser root.
press('<C-l>')
title('Staged changes')
press('<C-h>')
press('H')
choose('test: add fixture')
title('test: add fixture')
review.refresh(true)
title('test: add fixture')
assert(view.cur_entry.kind == 'staged', 'refresh must keep browser context separate from the diff')
-- Hiding/showing the sidebar and leaving/re-entering the tab follow focus.
press(' e')
local text = vim.trim(api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=200}).str)
assert(text == 'main · Staged changes')
press(' e')
sidebar = api.nvim_get_current_win()
windows = api.nvim_tabpage_list_wins(tab)
title('test: add fixture')
api.nvim_set_current_tabpage(editor_tab)
assert(vim.o.tabline == original_tabline)
api.nvim_set_current_tabpage(tab)
title('test: add fixture')
press('<C-l>')
title('Staged changes')
press(' q')
assert(vim.o.tabline == original_tabline)
vim.o.tabline = 'after review'
press('j')
assert(vim.o.tabline == 'after review', 'header callbacks must be removed when the review closes')
print('PASS: browser commit context, Ctrl-l/Ctrl-h, roots, working sections, refresh, visibility, and cleanup')
'''

HEADER = r'''
local api = vim.api
vim.o.tabline, vim.o.showtabline = 'original file tabs', 0
local group = api.nvim_create_augroup('TestReviewHeader', {clear=true})
local header = require('config.git_review.header').new(group)
local function title()
  return vim.trim(api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=200}).str)
end
local tab = api.nvim_get_current_tabpage()
header:update(tab, {kind='commit', branch_name='feature/100%', author='A %!uthor', subject='100% %!literal\tmessage'})
assert(title() == 'feature/100% · A %!uthor · 100% %!literal message')
assert(vim.o.showtabline == 2)
header:update(tab, {kind='branch', name='feature/100%'})
assert(title() == 'feature/100%')
header:update(tab, {kind='commit', branch_name='feature', author='Alice', subject=string.rep('long message ', 20)})
local narrow = api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=45}).str
assert(narrow:find('feature · Alice · ', 1, true), 'long subjects must not hide branch and author')
header:update(tab, {kind='commit', branch_name='main', author='', subject='missing author'})
assert(title() == 'main · Unknown author · missing author')
header:update(tab, {kind='staged', branch_name='main'})
assert(title() == 'main · Staged changes', 'uncommitted edits must not invent an author')
header:update(tab, {kind='commit', branch_name='main', author='Test', subject=''})
assert(title() == 'main · Test · (no commit message)')
vim.cmd.tabnew()
assert(vim.o.tabline == 'original file tabs' and vim.o.showtabline == 0)
api.nvim_set_current_tabpage(tab)
assert(title() == 'main · Test · (no commit message)' and vim.o.showtabline == 2)
api.nvim_clear_autocmds({group=group})
header:hide()
header:hide()
assert(vim.o.tabline == 'original file tabs' and vim.o.showtabline == 0)
print('PASS: safe header data, empty subjects, tabline visibility restoration')
'''

REVIEW_UI = r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
vim.opt.termguicolors = true
require('bufferline').setup({options={always_show_bufferline=true}})
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
local spec = require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
vim.keymap.set('n', spec.keys[1][1], spec.keys[1][2])
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(100)
end
local function git(...)
  local result = vim.system({'git', ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local text = {}
for index = 1, 120 do text[index] = 'context line ' .. index end
vim.fn.writefile(text, 'context.txt')
git('add', 'context.txt')
git('commit', '-m', 'review: add context', '--', 'context.txt')
text[60] = 'changed context line'
vim.fn.writefile(text, 'context.txt')
git('add', 'context.txt')
local message = 'review: 100% %!literal context'
git('commit', '-m', message, '--', 'context.txt')
local hash = git('rev-parse', 'HEAD')
local root = git('rev-parse', '--show-toplevel')
vim.cmd.edit('first.txt')
local editor_tab = api.nvim_get_current_tabpage()
local original_tabline, original_showtabline = vim.o.tabline, vim.o.showtabline
local review = require('config.git_review')
local function title()
  return vim.trim(api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, maxwidth=200}).str)
end
local function assert_title(expected)
  if expected ~= 'main' then
    local working = expected == 'Staged changes' or expected == 'Unstaged changes'
    expected = 'main · ' .. (working and '' or 'Test · ') .. expected
  end
  assert(title() == expected, 'Expected title ' .. expected .. ', got ' .. title())
  assert(not vim.o.tabline:find('nvim_bufferline', 1, true), 'review must not show file tabs')
end
press(' gd')
assert_title('main')
review.select({root=root, kind='staged', path='staged.txt', id=node_id('staged:file:staged.txt'), branch_name='main'})
assert_title('Staged changes')
local model = require('config.git_review.tree').new(root, require('config.git_review.repository'))
model:expand(commit_id(hash))
local selection = model:selection(commit_id(hash) .. ':file:context.txt')
assert(selection.subject == message, 'commit selections must carry their message')
review.select(selection)
assert_title(message)
local review_tab = api.nvim_get_current_tabpage()
local diff_windows = {}
for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
  if vim.wo[window].diff then diff_windows[#diff_windows + 1] = window end
end
assert(#diff_windows == 2)
local function assert_fold(closed)
  for _, window in ipairs(diff_windows) do
    api.nvim_win_call(window, function()
      assert((vim.fn.foldclosed(1) ~= -1) == closed, 'fold state must match in both panes')
    end)
  end
end
for _, window in ipairs(diff_windows) do
  api.nvim_set_current_win(window)
  api.nvim_win_set_cursor(window, {1, 0})
  local buffer = api.nvim_get_current_buf()
  assert_fold(true)
  press('L')
  assert_fold(false)
  press('H')
  assert_fold(true)
  vim.v.errmsg = ''
  press('H')
  api.nvim_win_set_cursor(window, {60, 0})
  press('H')
  press('L')
  assert(vim.v.errmsg == '', 'already-closed folds and unfolded change lines must be safe no-ops')
  for _, key in ipairs({' k', '<C-k>'}) do
    press(key)
    assert(not require('config.tab_navigation').active, 'commit header must not open tab navigation')
    assert(api.nvim_get_current_win() == window)
  end
  assert(api.nvim_get_current_buf() == buffer, 'fold keys must never switch file tabs')
end
-- Exercise Diffview's synchronized manual-fold compatibility as well.
press('gg') -- Drive cursorbind before replacing the diff folds with manual folds.
for _, window in ipairs(diff_windows) do
  api.nvim_set_current_win(window)
  vim.wo.foldmethod = 'manual'
  vim.cmd('normal! zE')
  vim.cmd('1,20fold')
  api.nvim_win_set_cursor(window, {1, 0})
end
assert_fold(true)
press('L')
assert_fold(false)
press('H')
assert_fold(true)
review.focus_sidebar()
local sidebar_window = api.nvim_get_current_win()
review.fold(true)
assert_fold(false)
assert(api.nvim_get_current_win() == sidebar_window, 'folding from the sidebar must preserve focus')
review.fold(false)
assert_fold(true)
press(' e')
assert_title(message)
press(' e')
assert_title('main')
api.nvim_set_current_tabpage(editor_tab)
assert(vim.o.tabline == original_tabline, 'leaving review must restore file tabs')
api.nvim_set_current_tabpage(review_tab)
assert_title('main')
press(' q')
assert(vim.o.tabline == original_tabline and vim.o.showtabline == original_showtabline)
-- Normal editing still cycles buffers and can focus the real file tab bar.
local cycles = 0
api.nvim_create_user_command('BufferLineCycleNext', function() cycles = cycles + 1 end, {force=true})
press('L')
assert(cycles == 1, 'normal editor tab navigation must be unchanged')
press(' k')
assert(require('config.tab_navigation').active)
press('<Esc>')
press(' gd')
vim.cmd.DiffviewClose()
assert(vim.o.tabline == original_tabline, ':DiffviewClose must restore the file tab bar')
print('PASS: commit header, literal subjects, tab lifecycle, synchronized folds, scoped navigation')
'''

UNBORN = r'''
local repository = require('config.git_review.repository')
local root = repository.root(vim.fn.getcwd())
assert(#repository.commits(root, 'HEAD', 10) == 0)
local model = require('config.git_review.tree').new(root, repository)
assert(model:stage(node_id('unstaged:file:first.txt')) == node_id('staged:file:first.txt'))
assert(model:stage(node_id('staged:file:first.txt')) == node_id('unstaged:file:first.txt'))
vim.g.mapleader = ' '
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
require('config.git_review').open()
local found = false
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'GitReview' then found = true end
end
assert(found, 'repositories without commits must still open')
vim.wait(100)
require('config.git_review').close()
vim.fn.delete('first.txt')
require('config.keymaps')
require('config.git_review').open()
assert(#vim.api.nvim_list_tabpages() == 2, 'an empty repository must still have a review browser')
local function press(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(100)
end
press(' e')
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local ft = vim.bo[vim.api.nvim_win_get_buf(window)].filetype
  assert(ft ~= 'GitReview' and ft ~= 'NvimTree', 'empty review toggle must hide review, not open the file explorer')
end
press(' e')
assert(vim.bo.filetype == 'GitReview', 'Space e must reopen the sidebar even without a diff buffer')
require('config.git_review').close()
assert(#vim.api.nvim_list_tabpages() == 1)
print('PASS: unborn and empty repositories, staging, and review')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class GitReview(unittest.TestCase):
    def run_lua(self, lua, unborn=False, plugins=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')

            def git(*args):
                return subprocess.run(['git', *args], cwd=tmp, env=env, check=True,
                                      capture_output=True, text=True).stdout

            git('init', '-q', '--initial-branch=main')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            (root / 'first.txt').write_text('original\n')
            if not unborn:
                (root / 'staged.txt').write_text('base\n')
                git('add', '.')
                git('commit', '-qm', 'test: add fixture')
                (root / 'first.txt').write_text('committed change\n')
                git('add', 'first.txt')
                git('commit', '-qm', 'test: update fixture')
                (root / 'first.txt').write_text('working change\n')
                (root / 'staged.txt').write_text('index change\n')
                git('add', 'staged.txt')
                (root / 'nested').mkdir()
                (root / 'nested/new file.txt').write_text('new\n')
                (root / 'tab\tname.txt').write_text('tab\n')
            prelude = '''vim.opt.runtimepath:prepend(vim.env.NVIM_CONFIG)
local branch_id = 'branch:refs/heads/main'
local function node_id(suffix) return branch_id .. ':' .. suffix end
local function commit_id(hash) return node_id('commit:' .. hash) end
'''
            if plugins:
                prelude += '''for name in vim.env.NVIM_PLUGINS:gmatch('[^:]+') do
  vim.opt.runtimepath:append(name)
end
'''
            # Keep the test script outside the repository's untracked file list.
            with tempfile.TemporaryDirectory() as scripts:
                script = Path(scripts) / 'check.lua'
                script.write_text(prelude + lua + "\nvim.cmd('qa!')\n")
                result = subprocess.run(
                    ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                    cwd=tmp,
                    env=dict(env, NVIM_CONFIG=str(ROOT / '.config/nvim'),
                             NVIM_PLUGINS=':'.join(str(PLUGINS / name) for name in DEPENDENCIES)),
                    capture_output=True, text=True, timeout=45,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('vim.schedule callback', result.stdout + result.stderr)
                self.assertNotIn('The coroutine failed', result.stdout + result.stderr)

    def test_repository_and_tree(self):
        self.run_lua(MODEL)

    def test_flat_filenames_preserve_git_paths(self):
        self.run_lua(FLAT_FILES)

    def test_header_restoration_and_literal_subjects(self):
        self.run_lua(HEADER)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_review_workflow(self):
        self.run_lua(WORKFLOW, plugins=True)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_unborn_repository(self):
        self.run_lua(UNBORN, unborn=True, plugins=True)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_commit_header_and_diff_folds(self):
        self.run_lua(REVIEW_UI, plugins=True)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_file_selection_preserves_review_layout(self):
        self.run_lua(STABLE_LAYOUT, plugins=True)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_header_follows_browser_and_diff_focus(self):
        self.run_lua(CONTEXT_HEADER, plugins=True)


if __name__ == '__main__':
    unittest.main()
