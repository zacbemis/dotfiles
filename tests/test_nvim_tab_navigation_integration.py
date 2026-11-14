"""Offline tab-navigation checks against locally installed real plugins."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
PLUGINS = DATA / "nvim/lazy"
DEPENDENCIES = ("bufferline.nvim", "nvim-tree.lua", "nvim-web-devicons")

LUA = r'''
local api = vim.api
vim.opt.runtimepath:prepend(vim.env.NVIM_CONFIG)
for name in vim.env.NVIM_PLUGINS:gmatch('[^:]+') do
  vim.opt.runtimepath:append(name)
end
vim.g.mapleader = ' '
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.hidden = true
vim.opt.showtabline = 2
vim.opt.termguicolors = true
require('config.keymaps')
require('bufferline').setup({ options = { mode = 'buffers', always_show_bufferline = true } })
require('nvim-tree').setup({
  filesystem_watchers = { enable = false },
  git = { enable = false },
  on_attach = function(buf)
    require('nvim-tree.api').map.on_attach.default(buf)
    vim.keymap.del('n', '<C-k>', { buffer = buf })
  end,
})
local tree = require('nvim-tree.api').tree
local nav = require('config.tab_navigation')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
end
local function refresh()
  _G.nvim_bufferline()
end
local function editor_window()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == ''
      and vim.bo[api.nvim_win_get_buf(win)].buftype == '' then
      return win
    end
  end
end
local function fullscreen()
  tree.open({ current_window = true, path = vim.env.NVIM_FIXTURE })
  refresh()
  assert(vim.bo.filetype == 'NvimTree')
  assert(#api.nvim_tabpage_list_wins(0) == 1)
end

local placeholder = api.nvim_get_current_buf()
fullscreen()
api.nvim_buf_delete(placeholder, { force = false })
refresh()
press('<C-k>')
assert(nav.active, 'empty explorer must still focus the tab bar')
press('hl')
press(' q')
press('<CR>')
assert(not nav.active and vim.bo.filetype == 'NvimTree')
assert(#api.nvim_tabpage_list_wins(0) == 1)

tree.close_in_this_tab()
vim.cmd.edit(vim.env.NVIM_FIXTURE .. '/first.txt')
local first = api.nvim_get_current_buf()
vim.cmd.edit(vim.env.NVIM_FIXTURE .. '/second.txt')
local second = api.nvim_get_current_buf()
refresh()
assert(#require('bufferline').get_elements().elements == 2)

fullscreen()
press('<C-k>')
assert(nav.active)
local editor = editor_window()
assert(editor, 'full-screen explorer must restore an editor when file tabs exist')
press('<CR>')
assert(api.nvim_get_current_win() == editor)
assert(api.nvim_get_current_buf() == second, 'Enter must open the last file without cycling')
assert(not tree.is_visible())
assert(#api.nvim_tabpage_list_wins(0) == 1)

fullscreen()
press('<C-k>')
editor = editor_window()
press('h')
assert(api.nvim_win_get_buf(editor) == first, 'previous tab must work from the full-screen tree')
press('l')
assert(api.nvim_win_get_buf(editor) == second, 'next tab must work from the full-screen tree')
press('l')
assert(api.nvim_win_get_buf(editor) == first, 'next tab must wrap in bufferline order')
press('<C-j>')
assert(not nav.active and api.nvim_get_current_win() == editor)

api.nvim_buf_set_lines(first, 0, -1, false, { 'unsaved changes' })
fullscreen()
press('<C-k>')
press('l')
press('<Esc>')
assert(api.nvim_get_current_buf() == second)
assert(vim.bo[first].modified, 'tab navigation must preserve unsaved buffers')
assert(api.nvim_buf_get_lines(first, 0, -1, false)[1] == 'unsaved changes')

tree.open()
local tree_win, tree_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
press('<C-k>')
assert(nav.active)
press('h')
press('<CR>')
assert(api.nvim_get_current_buf() == first)
assert(api.nvim_get_current_win() ~= tree_win)
assert(api.nvim_win_is_valid(tree_win) and api.nvim_win_get_buf(tree_win) == tree_buf,
  'sidebar navigation must preserve the explorer')
print('PASS: empty tree, Enter, cycling, wrapping, unsaved buffers, and sidebar')
vim.cmd('qa!')
'''


@unittest.skipUnless(shutil.which("nvim"), "Neovim is not installed")
@unittest.skipUnless(all((PLUGINS / name).is_dir() for name in DEPENDENCIES),
                     "Real plugin fixtures are not installed")
class RealTabNavigation(unittest.TestCase):
    def test_fullscreen_tree_and_sidebar(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp)
            (fixture / "first.txt").write_text("first\n")
            (fixture / "second.txt").write_text("second\n")
            script = fixture / "check.lua"
            script.write_text(LUA)
            result = subprocess.run(
                ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
                env=dict(os.environ, NVIM_CONFIG=str(ROOT / ".config/nvim"),
                         NVIM_FIXTURE=tmp,
                         NVIM_PLUGINS=":".join(str(PLUGINS / name) for name in DEPENDENCIES)),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
