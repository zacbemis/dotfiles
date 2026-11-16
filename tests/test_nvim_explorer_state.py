"""Real nvim-tree cursor restoration, including independent Neovim launches."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGINS = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim/lazy'
DEPENDENCIES = ('nvim-tree.lua', 'nvim-web-devicons')

PRELUDE = r'''
local api = vim.api
vim.opt.runtimepath:prepend(vim.env.NVIM_CONFIG)
for path in vim.env.NVIM_PLUGINS:gmatch('[^:]+') do vim.opt.runtimepath:append(path) end
vim.g.mapleader = ' '
vim.g.loaded_netrw, vim.g.loaded_netrwPlugin = 1, 1
vim.opt.hidden = true
vim.opt.scrolloff = 0
require('config.keymaps')
local spec = require('plugins.explorer')[1]
spec.init()
spec.config(nil, vim.tbl_deep_extend('force', spec.opts, {
  filesystem_watchers = {enable=false}, git = {enable=false}, diagnostics = {enable=false},
  filters = {dotfiles=vim.env.NVIM_HIDE_DOTFILES == '1'},
}))
local tree = require('nvim-tree.api').tree
local explorer = require('config.explorer')
local state = require('config.explorer_state')
local cwd = vim.fn.getcwd()
local target = cwd .. '/alpha/nested/target.txt'
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(30)
  api.nvim_exec_autocmds('CursorMoved', {}) -- -l does not run the interactive idle loop.
end
local function startup()
  api.nvim_exec_autocmds('VimEnter', {})
  assert(vim.wait(1000, function() return tree.is_visible() end))
  assert(vim.bo.filetype == 'NvimTree' and #api.nvim_tabpage_list_wins(0) == 1)
end
local function selected(expected)
  local node = tree.get_node_under_cursor()
  assert(node and node.absolute_path == expected,
    'Expected browser selection ' .. expected .. ', got ' .. tostring(node and node.absolute_path))
end
'''

REOPEN = r'''
startup()
for _, key in ipairs({'l', '<CR>', 'L'}) do
  tree.find_file({buf=target, focus=true})
  selected(target)
  press(key)
  assert(vim.bo.filetype ~= 'NvimTree')
  api.nvim_win_set_cursor(0, {35, 0}) -- Must not be mistaken for a tree row.
  press(' q')
  assert(vim.wait(1000, function() return tree.is_visible() and vim.bo.filetype == 'NvimTree' end))
  selected(target)
  assert(#api.nvim_tabpage_list_wins(0) == 1)
end
print('PASS: every full-window file-open mapping returns to the selected path')
'''

SIDEBAR = r'''
startup()
tree.find_file({buf=target, focus=true})
press('l')
press(' e')
selected(target)
local folder = cwd .. '/zeta'
tree.find_file({buf=folder, focus=true})
press(' e')
api.nvim_win_set_cursor(0, {20, 0})
press(' e')
selected(folder)
-- Close the last editor while the sidebar is visible but not focused.
press('<C-l>')
press(' q')
assert(vim.wait(1000, function() return tree.is_visible() and #api.nvim_tabpage_list_wins(0) == 1 end))
selected(folder)
print('PASS: sidebar hide/show and sidebar-to-fullscreen transitions preserve browser selection')
'''

SAVE_FROM_EDITOR = r'''
startup()
tree.find_file({buf=target, focus=true})
press('l')
api.nvim_win_set_cursor(0, {35, 0})
press(':q<CR>')
error('Quit must exit and save the browser location while the tree is hidden')
'''

RESTORE_STARTUP = r'''
startup()
selected(target)
assert(tree.get_nodes().absolute_path == cwd)
assert(#vim.fn.getbufinfo({buflisted=1}) == 0, 'restoring the browser must not reopen editor files')
print('PASS: saved browser location restored without reopening buffers')
'''

SAVE_CUSTOM_ROOT = r'''
startup()
require('nvim-tree.api').tree.change_root(cwd .. '/alpha')
tree.find_file({buf=target, focus=true})
press('l')
press(':q<CR>')
error('Quit must save the browsed root as well as the selected path')
'''

RESTORE_CUSTOM_ROOT = r'''
startup()
assert(tree.get_nodes().absolute_path == cwd .. '/alpha')
selected(target)
assert(vim.fn.getcwd() == cwd, 'restoring the browser must not change the working directory')
print('PASS: custom browser root restored independently of cwd')
'''

PROJECT_ROOT = r'''
startup()
selected(cwd)
assert(tree.get_nodes().absolute_path == cwd)
'''

EXPLICIT_FILE = r'''
vim.cmd('argadd ' .. vim.fn.fnameescape(target))
vim.cmd.edit(target)
local buffer = api.nvim_get_current_buf()
api.nvim_exec_autocmds('VimEnter', {})
vim.wait(50)
assert(api.nvim_get_current_buf() == buffer and not tree.is_visible(), 'explicit file launches must remain editors')
'''

STDIN = r'''
api.nvim_exec_autocmds('StdinReadPre', {})
api.nvim_exec_autocmds('VimEnter', {})
vim.wait(50)
assert(not tree.is_visible(), 'stdin startup must not be replaced by saved browser state')
'''

SESSION = r'''
vim.v.this_session = cwd .. '/Session.vim'
api.nvim_exec_autocmds('VimEnter', {})
vim.wait(50)
assert(not tree.is_visible(), 'restored sessions must not be replaced by saved browser state')
'''

TABS = r'''
startup()
tree.find_file({buf=target, focus=true})
press('l')
press(' e')
local first_tab = api.nvim_get_current_tabpage()
local first_selection = cwd .. '/zeta'
tree.find_file({buf=first_selection, focus=true})
press(' e')
vim.cmd.tabnew()
explorer.toggle()
tree.find_file({buf=cwd .. '/alpha', focus=true})
explorer.toggle() -- Lone tree is intentionally kept open.
api.nvim_set_current_tabpage(first_tab)
press(' e')
selected(first_selection)
print('PASS: selections in separate tabs do not overwrite each other')
'''


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required')
@unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES), 'nvim-tree fixtures are not installed')
class ExplorerState(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.state = self.base / 'state'
        self.workspace = self.make_workspace('project')

    def make_workspace(self, name):
        root = self.base / name
        (root / 'alpha/nested').mkdir(parents=True)
        (root / 'alpha/nested/target.txt').write_text(''.join(f'line {i}\n' for i in range(60)))
        (root / 'zeta').mkdir()
        (root / 'zeta/other.txt').write_text('other\n')
        (root / '.private').mkdir()
        (root / '.private/secret.txt').write_text('private\n')
        for index in range(45):
            (root / f'file_{index:02}.txt').write_text('file\n')
        return root

    def state_file(self, workspace=None):
        key = str((workspace or self.workspace).resolve()).encode()
        return self.state / 'nvim/explorer' / (hashlib.sha256(key).hexdigest() + '.json')

    def run_lua(self, lua, *, workspace=None, hide_dotfiles=False):
        script = self.base / 'check.lua'
        script.write_text(PRELUDE + lua + "\nvim.cmd('qa!')\n")
        result = subprocess.run(
            ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
            cwd=workspace or self.workspace,
            env=dict(os.environ, NVIM_CONFIG=str(ROOT / '.config/nvim'),
                     NVIM_PLUGINS=':'.join(str(PLUGINS / name) for name in DEPENDENCIES),
                     XDG_STATE_HOME=str(self.state), NVIM_HIDE_DOTFILES='1' if hide_dotfiles else '0'),
            capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Could not restore file-browser position', result.stdout + result.stderr)
        self.assertNotIn('Could not save file-browser position', result.stdout + result.stderr)

    def test_fullscreen_open_and_close(self):
        self.run_lua(REOPEN)

    def test_sidebar_and_fullscreen_transitions(self):
        self.run_lua(SIDEBAR)

    def test_location_survives_quitting_from_a_file(self):
        self.run_lua(SAVE_FROM_EDITOR)
        saved = json.loads(self.state_file().read_text())
        self.assertEqual(saved['path'], str(self.workspace / 'alpha/nested/target.txt'))
        self.assertEqual(self.state_file().stat().st_mode & 0o777, 0o600)
        # A different tree row count must not affect restoration.
        (self.workspace / 'alpha/aaa.txt').write_text('new earlier file\n')
        self.run_lua(RESTORE_STARTUP)

    def test_custom_root_is_restored(self):
        self.run_lua(SAVE_CUSTOM_ROOT)
        self.run_lua(RESTORE_CUSTOM_ROOT)

    def test_projects_remain_independent(self):
        self.run_lua(SAVE_FROM_EDITOR)
        other = self.make_workspace('other-project')
        self.run_lua(PROJECT_ROOT, workspace=other)
        self.run_lua(RESTORE_STARTUP)
        self.assertNotEqual(self.state_file(), self.state_file(other))
        self.assertTrue(self.state_file(other).exists())

    def test_deleted_file_falls_back_to_parent(self):
        self.run_lua(SAVE_FROM_EDITOR)
        (self.workspace / 'alpha/nested/target.txt').unlink()
        self.run_lua("startup(); selected(cwd .. '/alpha/nested')")

    def test_deleted_root_falls_back_to_working_directory(self):
        self.run_lua(SAVE_CUSTOM_ROOT)
        shutil.rmtree(self.workspace / 'alpha')
        self.run_lua(PROJECT_ROOT)

    def test_root_deleted_while_editing_recovers_in_same_session(self):
        self.run_lua(r'''
startup()
tree.change_root(cwd .. '/alpha')
tree.find_file({buf=target, focus=true})
press('l')
vim.fn.delete(cwd .. '/alpha', 'rf')
press(' q')
assert(vim.wait(1000, function() return vim.bo.filetype == 'NvimTree' end))
assert(tree.get_nodes().absolute_path == cwd)
selected(cwd)
''')

    def test_filtered_selection_falls_back_to_visible_parent(self):
        self.run_lua("startup(); tree.find_file({buf=cwd .. '/.private/secret.txt', focus=true})")
        self.run_lua(PROJECT_ROOT, hide_dotfiles=True)

    def test_invalid_state_is_ignored(self):
        path = self.state_file()
        path.parent.mkdir(parents=True)
        for content in ('{broken json', '{}', json.dumps({
            'version': 1, 'root': str(self.workspace), 'path': '/outside/the/root', 'offset': 0,
        })):
            with self.subTest(content=content):
                path.write_text(content)
                self.run_lua(PROJECT_ROOT)

    def test_explicit_files_stdin_and_sessions_are_untouched(self):
        self.run_lua(SAVE_FROM_EDITOR)
        expected = self.state_file().read_text()
        for lua in (EXPLICIT_FILE, STDIN, SESSION):
            with self.subTest(lua=lua):
                self.run_lua(lua)
                self.assertEqual(self.state_file().read_text(), expected)

    def test_tab_locations_are_independent(self):
        self.run_lua(TABS)

    def test_viewport_is_preserved(self):
        self.run_lua(r'''
startup()
local path = cwd .. '/file_30.txt'
tree.find_file({buf=path, focus=true})
vim.cmd('normal! zz')
local offset = api.nvim_win_get_cursor(0)[1] - vim.fn.winsaveview().topline
press('l')
press(' q')
assert(vim.wait(1000, function() return vim.bo.filetype == 'NvimTree' end))
selected(path)
assert(api.nvim_win_get_cursor(0)[1] - vim.fn.winsaveview().topline == offset,
  'restoring a path should preserve its position in the viewport')
''')

    def test_failed_write_keeps_previous_state_intact(self):
        self.run_lua(r'''
startup()
tree.find_file({buf=target, focus=true})
assert(state.save())
local path = vim.fn.stdpath('state') .. '/explorer/' .. vim.fn.sha256(cwd) .. '.json'
local before = vim.fn.readfile(path)
tree.find_file({buf=cwd .. '/zeta', focus=true})
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function() return nil, 'simulated rename failure' end
local ok = state.save()
vim.uv.fs_rename = rename
assert(not ok and vim.deep_equal(vim.fn.readfile(path), before), 'failed writes must leave the old state intact')
assert(#vim.fn.glob(path .. '*.tmp', false, true) == 0, 'failed writes must clean up temporary files')
assert(state.save(), 'in-memory location must remain available for retry')
''')

    def test_direct_tree_close_then_toggle_restores_location(self):
        self.run_lua(r'''
startup()
tree.find_file({buf=target, focus=true})
press('l')
press(' e')
tree.find_file({buf=cwd .. '/zeta', focus=true})
tree.close()
press(' e')
selected(cwd .. '/zeta')
''')


if __name__ == '__main__':
    unittest.main()
