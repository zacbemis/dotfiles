"""Real explorer/bufferline navigation must not move files into the review tab."""
import shutil
import unittest

import test_nvim_git_review as review_tests

LUA = r'''
local api = vim.api
local plugin = vim.env.NVIM_PLUGINS:match('^[^:]+')
vim.opt.runtimepath:append(vim.fs.dirname(plugin) .. '/nvim-tree.lua')
vim.g.mapleader = ' '
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.hidden = true
vim.opt.termguicolors = true
vim.opt.switchbuf = 'useopen,usetab'
require('config.keymaps')
require('bufferline').setup({options=require('plugins.bufferline')[1].opts.options})
local explorer = require('plugins.explorer')[1]
require('nvim-tree').setup(vim.tbl_deep_extend('force', explorer.opts, {
  filesystem_watchers = {enable=false}, git = {enable=false},
}))
vim.cmd('runtime plugin/diffview.lua')
local spec = require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
vim.keymap.set('n', spec.keys[1][1], spec.keys[1][2])
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
  vim.wait(100)
end
local tree = require('nvim-tree.api').tree
local placeholder = api.nvim_get_current_buf()
if SIDEBAR then
  vim.cmd.edit('staged.txt')
  tree.open()
else
  tree.open({current_window=true})
  api.nvim_buf_delete(placeholder, {force=false})
end
local editor_tab = api.nvim_get_current_tabpage()
assert(vim.bo.filetype == 'NvimTree')
press(' gd')
local review = require('config.git_review')
local review_tab = api.nvim_get_current_tabpage()
review.select({root=vim.fn.getcwd(), kind='unstaged', path='first.txt', branch_name='main', id=node_id('unstaged:file:first.txt')})
local review_windows = api.nvim_tabpage_list_wins(review_tab)
local reviewed_buffer = api.nvim_get_current_buf()
assert(api.nvim_buf_get_name(reviewed_buffer) == vim.fn.getcwd() .. '/first.txt')
press(' h')
assert(api.nvim_get_current_tabpage() == editor_tab and vim.bo.filetype == 'NvimTree')
_G.nvim_bufferline()
local elements = require('bufferline').get_elements().elements
local found = false
for _, element in ipairs(elements) do
  local name = api.nvim_buf_get_name(element.id)
  assert(not name:match('^diffview://'), 'revision buffers must never be file tabs')
  if element.id == reviewed_buffer then found = true end
end
assert(found, 'a reviewed working file should remain available for normal editing')
press('<C-k>')
assert(api.nvim_tabpage_is_valid(editor_tab), 'opening a file from the startup tree must not delete the editor tab')
assert(api.nvim_get_current_tabpage() == editor_tab, 'file-tab navigation must stay in the editor tab')
local nav = require('config.tab_navigation')
assert(nav.active)
-- Navigate to the reviewed file in Bufferline order, not to its review window.
for _ = 1, #elements do
  local selected = false
  for _, win in ipairs(api.nvim_tabpage_list_wins(editor_tab)) do
    if api.nvim_win_get_buf(win) == reviewed_buffer then selected = true end
  end
  if selected then break end
  press('l')
end
press('<CR>')
assert(not nav.active and api.nvim_get_current_tabpage() == editor_tab)
assert(api.nvim_get_current_buf() == reviewed_buffer)
assert(vim.bo.modifiable and vim.bo.buftype == '' and not vim.wo.diff, 'selected file must be a normal editable buffer')
api.nvim_buf_set_lines(reviewed_buffer, 0, -1, false, {'unsaved editor change'})
press(' l')
assert(review.is_active() and api.nvim_get_current_tabpage() == review_tab)
assert(vim.deep_equal(api.nvim_tabpage_list_wins(review_tab), review_windows), 'normal editing must preserve review layout')
press(' h')
assert(api.nvim_get_current_tabpage() == editor_tab, 'Space h must still return from review to the editor')
assert(api.nvim_get_current_buf() == reviewed_buffer and vim.bo.modified)
assert(api.nvim_buf_get_lines(reviewed_buffer, 0, -1, false)[1] == 'unsaved editor change')
-- Switching tabs directly from the focusable file bar must clean up its overlay.
press('<C-k>')
assert(nav.active)
press(' l')
assert(review.is_active() and not nav.active)
press(' h')
assert(api.nvim_get_current_tabpage() == editor_tab)
assert(api.nvim_get_current_buf() == reviewed_buffer and vim.bo.modified)
assert(#api.nvim_list_tabpages() == 2)
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
@unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in (*review_tests.DEPENDENCIES, 'nvim-tree.lua')), 'Plugins are not installed')
class ReviewEditorNavigation(unittest.TestCase):
    def test_startup_explorer_to_review_to_editing(self):
        review_tests.GitReview.run_lua(self, LUA.replace('SIDEBAR', 'false'), plugins=True)

    def test_sidebar_to_review_to_editing(self):
        review_tests.GitReview.run_lua(self, LUA.replace('SIDEBAR', 'true'), plugins=True)

    def test_space_k_from_startup_explorer(self):
        lua = LUA.replace('SIDEBAR', 'false').replace("press('<C-k>')", "press(' k')")
        review_tests.GitReview.run_lua(self, lua, plugins=True)

    def test_space_k_from_sidebar(self):
        lua = LUA.replace('SIDEBAR', 'true').replace("press('<C-k>')", "press(' k')")
        review_tests.GitReview.run_lua(self, lua, plugins=True)


if __name__ == '__main__':
    unittest.main()
