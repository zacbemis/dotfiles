"""Git-review model and real Diffview workflows, entirely in temporary repositories."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim/lazy"
DEPENDENCIES = ("diffview.nvim", "plenary.nvim", "nvim-web-devicons")

MODEL = r'''
local repository = require('config.git_review.repository')
local root = repository.root(vim.fn.getcwd())
local status = repository.status(root)
assert(#status.staged == 1 and status.staged[1].path == 'staged.txt')
local found = {}
for _, file in ipairs(status.unstaged) do found[file.path] = true end
assert(found['first.txt'] and found['nested/new file.txt'] and found['tab\tname.txt'])
local commits = repository.commits(root, 20)
assert(#commits == 2 and commits[1].subject == 'test: update fixture')
local files, parent = repository.commit_files(root, commits[1].hash)
assert(parent == commits[2].hash and #files == 1 and files[1].path == 'first.txt')
local original, no_parent = repository.commit_files(root, commits[2].hash)
assert(not no_parent and #original == 2)
local model = require('config.git_review.tree').new(root, repository)
local top = {}
for _, row in ipairs(model:rows()) do if row.depth == 1 then top[#top + 1] = row end end
assert(top[1].id == 'unstaged' and top[2].id == 'staged')
assert(top[3].id == commits[1].hash and top[4].id == commits[2].hash)
model:drill(commits[1].hash)
assert(model:rows()[1].id == commits[1].hash)
assert(model:selection(commits[1].hash .. ':file:first.txt').parent == commits[2].hash)
model:up()
assert(model:rows()[1].id == 'review')
local staged = model:stage('unstaged:file:first.txt')
assert(staged == 'staged:file:first.txt')
assert(model:selection(staged).kind == 'staged')
local unstaged = model:stage(staged)
assert(unstaged == 'unstaged:file:first.txt')
assert(not model:can_stage(commits[1].hash))
assert(not pcall(model.stage, model, commits[1].hash), 'commits must be read-only')
local many = { status = function() return {unstaged={}, staged={}} end,
  commits = function(_, maximum)
    local result = {}
    for index = 1, math.min(maximum, 110) do
      result[index] = {hash='commit' .. index, short=tostring(index), subject='history'}
    end
    return result
  end,
  commit_files = function() return {} end,
}
local paged = require('config.git_review.tree').new(root, many)
assert(paged:rows()[#paged:rows()].id == 'more')
paged:expand('more')
assert(paged:rows()[#paged:rows()].id == 'commit110', 'older commit pages must be reachable')
local committed = vim.system({'git','-C',root,'commit','--allow-empty','--allow-empty-message','-m',''}, {text=true}):wait()
assert(committed.code == 0, committed.stderr)
assert(repository.commits(root, 1)[1].subject == '', 'empty commit subjects must not corrupt log fields')
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
  status = function() return status end,
  commits = function() return {{hash='commit', short='abc123', subject='nested files'}} end,
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
check_files('unstaged', paths)
check_files('staged', {'staged/deep/file.lua'})
check_files('commit', paths)
local selection = model:selection('commit:file:z/deep/shared.lua')
assert(selection.hash == 'commit' and selection.parent == 'parent')
assert(model:stage('unstaged:file:z/deep/shared.lua') == 'staged:file:z/deep/shared.lua')
check_files('staged', {'staged/deep/file.lua', 'z/deep/shared.lua'})
assert(model:stage('staged:file:z/deep/shared.lua') == 'unstaged:file:z/deep/shared.lua')
check_files('unstaged', paths)
check_files('commit', paths)
model:expand('unstaged')
local selected
local sidebar = require('config.git_review.sidebar').new(model, {
  select = function(file) selected = file end,
  stage = function() end, refresh = function() end, close = function() end,
})
sidebar:attach()
for _, path in ipairs({'a/shared.lua', 'z/deep/shared.lua'}) do
  sidebar:render('unstaged:file:' .. path)
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
local function sidebar()
  for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(window)].filetype == 'GitReview' then return window end
  end
  error('Review sidebar is missing')
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
press(' gd')
assert(api.nvim_get_current_tabpage() ~= original_tab)
assert(contains('Unstaged files') and contains('Staged files'))
assert(choose('Unstaged files') < choose('Staged files'))
assert(choose('Staged files') < choose('test: update fixture'))
assert(choose('test: update fixture') < choose('test: add fixture'))
choose('test: update fixture')
press('L')
assert(lines()[1]:find('test: update fixture', 1, true), 'L must make a commit the parent')
choose('first.txt')
press('l')
preview('committed change')
press(' e')
press('H')
assert(lines()[1]:find('Git review', 1, true), 'H must return to the full review')
choose('test: update fixture')
press('l')
press('h')
assert(lines()[api.nvim_win_get_cursor(sidebar())[1]]:find('[+]', 1, true), 'h must collapse a commit')
choose('test: add fixture')
press('L')
choose('first.txt')
press('l')
preview('original')
press(' e')
press('H')
choose('staged.txt')
press('l')
preview('index change')
local index_buffer = api.nvim_get_current_buf()
assert(api.nvim_buf_get_name(index_buffer):match('^diffview://'), api.nvim_buf_get_name(index_buffer))
local index_lines = api.nvim_buf_get_lines(index_buffer, 0, -1, false)
api.nvim_buf_set_lines(index_buffer, 0, -1, false, {'pending index edit'})
local protected_tab = api.nvim_get_current_tabpage()
assert(not pcall(vim.cmd.quit), 'unsaved index edits must block :q')
assert(api.nvim_tabpage_is_valid(protected_tab))
api.nvim_buf_set_lines(index_buffer, 0, -1, false, index_lines)
vim.bo[index_buffer].modified = false
local root = require('config.git_review.repository').root(vim.fn.getcwd())
for _ = 1, 3 do
  review.select({root=root, kind='unstaged', path='first.txt', id='unstaged:file:first.txt'})
  review.select({root=root, kind='staged', path='staged.txt', id='staged:file:staged.txt'})
end
preview('index change')
press(' e')
choose('first.txt')
press('s')
assert(contains('Staged files (2)'), 'staging must move the file into the staged section')
press('s')
assert(contains('Staged files (1)'), 'unstaging must move the file back')
assert(contains('new file.txt') and not contains('nested'), 'nested files must appear without folders')
choose('new file.txt')
press('l')
preview('new')
press(' e')
choose('Unstaged files')
press('L')
assert(lines()[1]:find('Unstaged files', 1, true))
press('H')
assert(lines()[1]:find('Git review', 1, true))
press(' q')
restored()
press(' gd')
choose('first.txt')
press('l')
preview('unsaved editor content')
press(' e')
vim.cmd.quit()
restored()
press(' gd')
choose('first.txt')
press('l')
local diff_window = api.nvim_get_current_win()
local added = vim.system({'git','add','--','first.txt'}, {text=true}):wait()
assert(added.code == 0, added.stderr)
review.refresh()
assert(contains('Staged files (2)'), 'external staging must refresh the mixed tree')
assert(vim.bo.filetype ~= 'GitReview', 'automatic refresh must not steal focus into the sidebar')
local committed = vim.system({'git','commit','-m','test: commit staged changes'}, {text=true}):wait()
assert(committed.code == 0, committed.stderr)
review.refresh()
assert(contains('Staged files (0)'))
assert(contains('test: commit staged changes'), 'new commits must appear after the two working sections')
vim.wait(100)
vim.cmd.quit()
restored()
print('PASS: unified review, commit roots, staging, external commits, unsaved buffers, all exits')
'''

UNBORN = r'''
local repository = require('config.git_review.repository')
local root = repository.root(vim.fn.getcwd())
assert(#repository.commits(root, 10) == 0)
local model = require('config.git_review.tree').new(root, repository)
assert(model:stage('unstaged:file:first.txt') == 'staged:file:first.txt')
assert(model:stage('staged:file:first.txt') == 'unstaged:file:first.txt')
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
require('config.git_review').open()
assert(#vim.api.nvim_list_tabpages() == 2, 'an empty repository must still have a review browser')
vim.wait(100)
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

            git('init', '-q')
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
            prelude = 'vim.opt.runtimepath:prepend(vim.env.NVIM_CONFIG)\n'
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

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_review_workflow(self):
        self.run_lua(WORKFLOW, plugins=True)

    @unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'Plugins are not installed')
    def test_unborn_repository(self):
        self.run_lua(UNBORN, unborn=True, plugins=True)


if __name__ == '__main__':
    unittest.main()
