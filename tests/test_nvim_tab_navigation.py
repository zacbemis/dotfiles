"""Offline regression tests for the focusable Neovim file tab bar."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

LUA = r'''
vim.opt.runtimepath:prepend(vim.env.NVIM_CONFIG)
vim.g.mapleader = ' '
require('config.keymaps')
local api = vim.api
local nav = require('config.tab_navigation')
-- Keep the test independent of installed plugins and network access.
_G.nvim_bufferline = function() return ' File tabs ' end
package.preload['bufferline'] = function()
  return { get_elements = function() return { elements = {} } end }
end
local cycles = 0
for _, name in ipairs({ 'BufferLineCyclePrev', 'BufferLineCycleNext' }) do
  api.nvim_create_user_command(name, function() cycles = cycles + 1 end, {})
end
local function press(key)
  local keys = api.nvim_replace_termcodes(key, true, false, true)
  api.nvim_feedkeys(keys, 'xt', false)
end
local tree_win = api.nvim_get_current_win()
local tree_buf = api.nvim_get_current_buf()
vim.bo[tree_buf].buftype = 'nofile'
vim.bo[tree_buf].filetype = 'NvimTree'
vim.bo[tree_buf].buflisted = false

-- Startup has only the full-window explorer, with no editing split.
press('<C-k>')
assert(nav.active, 'startup explorer must be able to focus the tab bar')
assert(vim.bo.filetype == 'personal-tab-bar')
assert(#api.nvim_tabpage_list_wins(0) == 2, 'must not create an empty editing split')
press('<C-k>')
assert(nav.active)
press(' q')
assert(nav.active and api.nvim_buf_is_valid(tree_buf), 'closing an empty bar must keep the tree')
assert(api.nvim_win_get_buf(tree_win) == tree_buf)
press('<C-j>')
assert(not nav.active and api.nvim_get_current_win() == tree_win)
assert(#api.nvim_tabpage_list_wins(0) == 1)
for _, key in ipairs({ '<Esc>', '<CR>' }) do
  press('<C-k>')
  assert(nav.active)
  press(key)
  assert(not nav.active and api.nvim_get_current_win() == tree_win)
end

-- A sidebar still routes tab selection into the existing editing split.
vim.cmd.vsplit()
local editor_win = api.nvim_get_current_win()
local file_buf = api.nvim_create_buf(true, false)
api.nvim_win_set_buf(editor_win, file_buf)
api.nvim_set_current_win(tree_win)
press('<C-k>')
assert(nav.active)
press('l')
assert(cycles == 1)
press('<CR>')
assert(api.nvim_get_current_win() == editor_win)
assert(api.nvim_win_get_buf(tree_win) == tree_buf)

-- Normal editing windows keep their existing navigation behavior.
press('<C-k>')
assert(nav.active)
press('<Esc>')
assert(api.nvim_get_current_win() == editor_win)
vim.cmd('qa!')
'''


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is not installed')
class TabNavigation(unittest.TestCase):
    def test_startup_tree_and_sidebar(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'check.lua'
            script.write_text(LUA)
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(script)],
                env=dict(os.environ, NVIM_CONFIG=str(ROOT / '.config/nvim')),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
