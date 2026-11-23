"""Render the separate scrollbar/Git overview using the installed plugin."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim/lazy/nvim-scrollview'

LUA = r'''
local api = vim.api
vim.opt.rtp:prepend(vim.env.SCROLL_CONFIG)
vim.opt.rtp:append(vim.env.SCROLL_PLUGIN)
vim.cmd('runtime plugin/scrollview.vim')
vim.o.lines = 40
vim.o.columns = 100
vim.o.wrap = false
vim.o.termguicolors = true
vim.cmd.colorscheme('dotfiles')
local hunks = {
  {type='add', added={start=1, count=3}},
  {type='change', added={start=100, count=4}, removed={count=4}},
  {type='delete', added={start=190, count=0}},
}
-- Supply deterministic hunks through the same API used by the integration.
package.loaded.gitsigns = {get_hunks=function() return hunks end, refresh=function() end}
local spec = require('plugins.scrollview')[1]
spec.config(nil, spec.opts)
assert(vim.wait(1000, function() return vim.fn.exists(':ScrollViewRefresh') == 2 end))
local lines = {}
for i=1,200 do lines[i] = 'line ' .. i end
api.nvim_buf_set_lines(0, 0, -1, false, lines)
local function refresh()
  api.nvim_exec_autocmds('User', {pattern='GitSignsUpdate'})
  vim.cmd('ScrollViewRefresh')
  vim.wait(100)
end
local function windows()
  local bar, signs
  signs = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
    if ft == 'scrollview' then bar = win end
    if ft == 'scrollview_sign' then signs[#signs+1] = win end
  end
  return bar, signs
end
refresh()
local bar, signs = windows()
assert(bar, 'scrollbar missing')
assert(#signs >= 3, 'Git overview should include add, change and delete')
local first_row = api.nvim_win_get_config(bar).row
for _, win in ipairs(signs) do
  local config = api.nvim_win_get_config(win)
  assert(config.col == api.nvim_win_get_config(bar).col - 1,
    'Git overview must stay one column left, even outside the thumb')
  assert(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, 1, false)[1] == '▐ ')
end
vim.cmd('normal! Gzb')
refresh()
bar = windows()
assert(api.nvim_win_get_config(bar).row > first_row, 'thumb should follow scrolling')
-- Theme resets retain the scrollbar color link.
vim.cmd.colorscheme('dotfiles')
assert(api.nvim_get_hl(0, {name='ScrollView'}).link == 'Comment')
-- Explorer/review sidebars must not get editor scrollbars.
for _, ft in ipairs({'NvimTree', 'GitReview'}) do
  vim.bo.filetype = ft
  refresh()
  local excluded_bar, excluded_signs = windows()
  assert(not excluded_bar and #excluded_signs == 0, 'sidebar must be excluded')
end
vim.bo.filetype = ''
hunks = {}
refresh()
local _, cleared = windows()
assert(#cleared == 0, 'stale Git signs must disappear when changes are reverted')
vim.cmd('qa!')
'''


@unittest.skipUnless(shutil.which('nvim') and PLUGIN.exists(), 'Neovim/scrollview not installed')
class Scrollview(unittest.TestCase):
    def test_separate_tracks(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'check.lua'
            script.write_text(LUA)
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '-l', str(script)],
                env=dict(os.environ, SCROLL_CONFIG=str(ROOT / '.config/nvim'),
                         SCROLL_PLUGIN=str(PLUGIN)),
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
