"""Interactive quit-all versus local Space-q buffer/review closing."""
import shutil
import unittest

import test_nvim_git_review as review_tests

PRELUDE = r'''
local api = vim.api
vim.g.mapleader = ' '
vim.opt.hidden = true
require('config.keymaps')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
end
'''

CLEAN = PRELUDE + r'''
vim.cmd.edit('first.txt')
vim.cmd.vsplit('staged.txt')
vim.cmd.tabnew()
assert(#api.nvim_list_tabpages() == 2)
press(':QUIT_COMMAND<CR>')
error('Interactive quit must exit the entire process, not just close one window/tab')
'''

DIRTY = PRELUDE + r'''
vim.cmd.edit('first.txt')
local first = api.nvim_get_current_buf()
api.nvim_buf_set_lines(first, 0, -1, false, {'unsaved first buffer'})
vim.cmd.edit('staged.txt')
local second = api.nvim_get_current_buf()
api.nvim_buf_set_lines(second, 0, -1, false, {'unsaved second buffer'})
vim.cmd.tabnew()
local tab, window, buffer = api.nvim_get_current_tabpage(), api.nvim_get_current_win(), api.nvim_get_current_buf()
press(':q<CR>')
assert(vim.bo[first].modified and vim.bo[second].modified, ':q must refuse hidden unsaved buffers')
-- Native :qall may focus the unsaved buffer so the user can save it.
assert(api.nvim_tabpage_is_valid(tab) and api.nvim_win_is_valid(window))
assert(api.nvim_buf_is_valid(buffer) and #api.nvim_list_tabpages() == 2)
assert(api.nvim_buf_get_lines(first, 0, 1, false)[1] == 'unsaved first buffer')
assert(api.nvim_buf_get_lines(second, 0, 1, false)[1] == 'unsaved second buffer')
vim.bo[first].modified, vim.bo[second].modified = false, false
press(':q<CR>')
error('Quit must exit once every modified buffer is safe')
'''

FORCED = PRELUDE + r'''
vim.cmd.edit('first.txt')
api.nvim_buf_set_lines(0, 0, -1, false, {'explicitly discarded edit'})
vim.cmd.tabnew()
press(':q!<CR>')
error('Only an explicit :q! should force quit-all')
'''

LOCAL_CLOSE = PRELUDE + r'''
vim.cmd.edit('first.txt')
local first = api.nvim_get_current_buf()
vim.cmd.edit('staged.txt')
local second = api.nvim_get_current_buf()
press(' q')
assert(not vim.bo[second].buflisted, 'Space q must close only the selected buffer')
assert(api.nvim_buf_is_valid(first) and vim.bo[first].buflisted)
vim.cmd.buffer(first)
api.nvim_buf_set_lines(first, 0, -1, false, {'protected edit'})
press(' q')
assert(api.nvim_buf_is_valid(first) and vim.bo[first].modified, 'Space q must not discard unsaved changes')
assert(api.nvim_buf_get_lines(first, 0, 1, false)[1] == 'protected edit')
print('PASS: Space q closes one buffer and preserves unsaved text')
'''

ABBREVIATION_SCOPE = PRELUDE + r'''
local left
api.nvim_create_autocmd('CmdlineLeave', {callback=function() left = vim.fn.getcmdline() end})
for _, command in ipairs({'echo q ', 'echo quit ', 'edit q ', 'edit quit ', 'lua print("q") '}) do
  press(':' .. command .. '<Esc>')
  assert(left == command, 'quit abbreviations must not rewrite arguments: ' .. tostring(left))
end
press('/q <Esc>')
assert(left == 'q ', 'search text must not be rewritten')
press(':silent q <Esc>')
assert(left == 'silent qall ', 'quit command modifiers must be preserved')
print('PASS: only actual quit commands are expanded')
'''

REVIEW = PRELUDE + r'''
vim.cmd('runtime plugin/diffview.lua')
local spec = require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
vim.keymap.set('n', spec.keys[1][1], spec.keys[1][2])
vim.cmd.edit('first.txt')
local editor_tab = api.nvim_get_current_tabpage()
press(' gd')
local review = require('config.git_review')
assert(review.is_active() and #api.nvim_list_tabpages() == 2)
'''

REVIEW_QUIT = REVIEW + r'''
press(':q<CR>')
error(':q in Git review must quit Neovim, not restore the editor')
'''

REVIEW_LOCAL_CLOSE = REVIEW + r'''
press(' q')
assert(not review.is_active() and api.nvim_get_current_tabpage() == editor_tab)
assert(#api.nvim_list_tabpages() == 1, 'Space q must close only the review tab')
print('PASS: Space q closes Git review without quitting Neovim')
'''

REVIEW_UNSAVED = REVIEW + r'''
local tab = api.nvim_get_current_tabpage()
local windows = api.nvim_tabpage_list_wins(tab)
local root = require('config.git_review.repository').root(vim.fn.getcwd())
review.select({root=root, kind='staged', path='staged.txt', branch_name='main', id=node_id('staged:file:staged.txt')})
local buffer = api.nvim_get_current_buf()
assert(api.nvim_buf_get_name(buffer):match('^diffview://'))
api.nvim_buf_set_lines(buffer, 0, -1, false, {'pending index edit'})
press(':q<CR>')
assert(review.is_active() and vim.bo[buffer].modified, 'native quit-all must protect nonlisted index buffers')
assert(vim.deep_equal(api.nvim_tabpage_list_wins(tab), windows), 'a rejected quit must not tear down review')
press(' q')
assert(review.is_active() and vim.bo[buffer].modified, 'Space q must protect index edits too')
vim.bo[buffer].modified = false
press(' q')
assert(#api.nvim_list_tabpages() == 1 and api.nvim_get_current_tabpage() == editor_tab)
print('PASS: quit-all and local close both protect edited index buffers')
'''

EMPTY_REVIEW = PRELUDE + r'''
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
vim.fn.delete('first.txt')
local review = require('config.git_review')
review.open()
require('config.git_review.diffview').focus_file(api.nvim_get_current_tabpage())
press(' q')
assert(#api.nvim_list_tabpages() == 1 and not review.is_active(), 'Space q must close an empty review from its null pane')
print('PASS: global Space q also handles empty reviews')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class QuitPolicy(unittest.TestCase):
    def run_lua(self, lua, *, plugins=False, unborn=False):
        review_tests.GitReview.run_lua(self, lua, plugins=plugins, unborn=unborn)

    def test_quit_commands_exit_all_windows_and_tabs(self):
        for command in ('q', 'qu', 'qui', 'quit', 'silent q', ' q'):
            with self.subTest(command=command):
                self.run_lua(CLEAN.replace('QUIT_COMMAND', command))

    def test_quit_protects_all_modified_buffers(self):
        self.run_lua(DIRTY)

    def test_force_quit_is_explicit(self):
        self.run_lua(FORCED)

    def test_space_q_closes_only_the_current_buffer(self):
        self.run_lua(LOCAL_CLOSE)

    def test_abbreviation_scope(self):
        self.run_lua(ABBREVIATION_SCOPE)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_quit_exits_from_git_review(self):
        self.run_lua(REVIEW_QUIT, plugins=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_space_q_closes_only_the_review(self):
        self.run_lua(REVIEW_LOCAL_CLOSE, plugins=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_quit_and_close_preserve_unsaved_index_buffers(self):
        self.run_lua(REVIEW_UNSAVED, plugins=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_space_q_from_an_empty_review(self):
        self.run_lua(EMPTY_REVIEW, plugins=True, unborn=True)


if __name__ == '__main__':
    unittest.main()
