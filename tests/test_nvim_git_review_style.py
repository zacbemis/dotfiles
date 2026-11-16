"""Git review presentation shares editor surfaces without changing its model."""
import shutil
import unittest

import test_nvim_git_review as review_tests

RENDER = r'''
local rows = {
  {id='branch', kind='branch', depth=0, expanded=true, label='main (current)'},
  {id='unstaged', kind='unstaged', depth=1, expanded=true, label='Unstaged files (3)'},
  {id='modified', kind='file', depth=2, label='main.lua', status='M'},
  {id='new', kind='file', depth=2, label='späce\t%!.lua', status='A'},
  {id='deleted', kind='file', depth=2, label='gone.lua', status='D'},
  {id='staged', kind='staged', depth=1, expanded=true, label='Staged files (0)'},
  {id='commit', kind='commit', depth=1, expanded=false, label='abc1234 Commit subject'},
  {id='more', kind='more', depth=1, label='Older commits...'},
}
local lines, highlights = require('config.git_review.sidebar_render').rows(rows)
assert(#lines == #rows, 'styling must preserve one navigable line per model row')
assert(lines[1] == '  main (current)')
assert(lines[2] == ' ├─  Unstaged files (3)')
assert(lines[3] == ' │ ├─ · main.lua  ~')
assert(lines[4] == ' │ ├─ · späce %!.lua  +', 'labels must remain literal and controls sanitized')
assert(lines[5] == ' │ └─ · gone.lua  -')
assert(lines[6] == ' ├─  Staged files (0)')
assert(lines[7] == ' ├─ ▸ abc1234 Commit subject')
assert(lines[8] == ' └─ … Older commits...')
local function highlighted(text, group)
  for _, span in ipairs(highlights) do
    if span.group == group and lines[span.row + 1]:sub(span.start + 1, span.finish) == text then return true end
  end
end
assert(highlighted(' (current)', 'GitReviewMuted'))
assert(highlighted(' (3)', 'GitReviewMuted'))
assert(highlighted('abc1234 ', 'GitReviewMuted'))
assert(highlighted('Commit subject', 'GitReviewText'))
assert(highlighted('  ~', 'GitReviewChanged'))
assert(highlighted('  +', 'GitReviewAdded'))
assert(highlighted('  -', 'GitReviewDeleted'))
-- Closing a section must not leave orphan continuation guides.
local compact = require('config.git_review.sidebar_render').rows({rows[1], rows[6], rows[7]})
assert(compact[2] == ' ├─  Staged files (0)' and compact[3] == ' └─ ▸ abc1234 Commit subject')
'''

THEME = r'''
local api = vim.api
local function highlight(name) return api.nvim_get_hl(0, {name=name, link=false}) end
api.nvim_set_hl(0, 'Normal', {fg='#eeeeee', bg='#101010'})
api.nvim_set_hl(0, 'NvimTreeNormal', {fg='#dddddd', bg='#202020'})
api.nvim_set_hl(0, 'NvimTreeEmptyFolderName', {fg='#888888'})
api.nvim_set_hl(0, 'NvimTreeRootFolder', {fg='#5588ff', bold=true})
api.nvim_set_hl(0, 'GitSignsAdd', {fg='#88ff88'})
api.nvim_set_hl(0, 'GitSignsChange', {fg='#ffff88'})
api.nvim_set_hl(0, 'GitSignsDelete', {fg='#ff8888'})
api.nvim_set_hl(0, 'BufferLineBufferSelected', {fg='#eeeeee', bg='#101010'})
api.nvim_set_hl(0, 'BufferLineFill', {bg='#202020'})
local style = require('config.git_review.style')
style.setup()
style.setup()
assert(#api.nvim_get_autocmds({group='GitReviewStyle'}) == 1, 'style setup must be idempotent')
assert(highlight('GitReviewNormal').bg == highlight('NvimTreeNormal').bg)
assert(highlight('GitReviewText').fg == highlight('NvimTreeNormal').fg)
assert(highlight('GitReviewText').bg == nil, 'text must not paint editor backgrounds over the sidebar')
assert(highlight('GitReviewAdded').fg == highlight('GitSignsAdd').fg)
assert(highlight('GitReviewChanged').fg == highlight('GitSignsChange').fg)
assert(highlight('GitReviewDeleted').fg == highlight('GitSignsDelete').fg)
assert(highlight('GitReviewTab').bg == highlight('BufferLineBufferSelected').bg)
assert(highlight('GitReviewTabFill').bg == highlight('BufferLineFill').bg)
local original = vim.deepcopy(highlight('Normal'))
local group = api.nvim_create_augroup('StyleHeaderTest', {clear=true})
local header = require('config.git_review.header').new(group)
vim.o.tabline = 'original editor tabs'
header:update(api.nvim_get_current_tabpage(), {kind='commit', branch_name='main', author='Author', subject='Subject'})
local rendered = api.nvim_eval_statusline(vim.o.tabline, {use_tabline=true, highlights=true, maxwidth=100})
assert(vim.trim(rendered.str) == 'main · Author · Subject')
assert(rendered.highlights[#rendered.highlights].group == 'GitReviewTabFill')
assert(rendered.highlights[#rendered.highlights].start < 80, 'selected tab background must end before the empty bar')
local groups = {}
for _, span in ipairs(rendered.highlights) do groups[span.group] = true end
assert(groups.GitReviewTabBranch and groups.GitReviewTabMeta and groups.GitReviewTab)
-- Derived groups must follow themes changed while review remains open.
api.nvim_set_hl(0, 'BufferLineBufferSelected', {fg='#ffffff', bg='#334455'})
api.nvim_set_hl(0, 'NvimTreeEmptyFolderName', {fg='#aabbcc'})
api.nvim_exec_autocmds('ColorScheme', {pattern='test'})
vim.wait(20)
assert(highlight('GitReviewTab').bg == 0x334455)
assert(highlight('GitReviewTabMeta').fg == 0xaabbcc)
assert(vim.deep_equal(highlight('Normal'), original), 'review styling must not alter editor colors')
header:hide()
assert(vim.o.tabline == 'original editor tabs')
-- The repository's own theme is also supported, without Bufferline loaded.
vim.cmd.colorscheme('dotfiles')
vim.wait(20)
assert(highlight('GitReviewNormal').bg == highlight('NvimTreeNormal').bg)
assert(highlight('GitReviewTab').bg == highlight('TabLineSel').bg)
'''

SIDEBAR = r'''
local api = vim.api
local rows = {
  {id='root', kind='branch', depth=0, label='main (current)', expanded=true},
  {id='file', kind='file', depth=1, label='first.txt', status='M'},
}
local changed = 0
local sidebar = require('config.git_review.sidebar').new({
  rows=function() return rows end, context=function(_, id) return {id=id} end,
}, {context_changed=function() changed=changed+1 end})
sidebar:attach()
local window, buffer = api.nvim_get_current_win(), api.nvim_get_current_buf()
assert(vim.wo.winhighlight:find('Normal:GitReviewNormal', 1, true))
assert(vim.wo.winhighlight:find('WinSeparator:GitReviewWinSeparator', 1, true))
assert(vim.wo.cursorline and not vim.wo.number and not vim.wo.wrap and not vim.wo.spell)
assert(not vim.bo.modifiable and not vim.bo.buflisted)
sidebar:render('file')
assert(sidebar:current() == 'file' and sidebar:context().id == 'file')
local lines = api.nvim_buf_get_lines(buffer, 0, -1, false)
local marks = api.nvim_buf_get_extmarks(buffer, api.nvim_create_namespace('GitReviewSidebar'), 0, -1, {details=true})
assert(#marks > #rows, 'sidebar must highlight semantic text spans rather than entire lines')
for _, mark in ipairs(marks) do
  assert(mark[3] < mark[4].end_col and mark[4].end_col <= #lines[mark[2] + 1], 'UTF-8 span boundaries must use byte columns')
end
sidebar:hide()
sidebar:focus()
assert(sidebar:current() == 'file', 'styling must preserve selection when toggling the sidebar')
assert(changed >= 3)
sidebar:dispose()
assert(not api.nvim_buf_is_valid(buffer))
'''


TOKYONIGHT = r'''
local api = vim.api
local plugin = vim.env.NVIM_PLUGINS:match('^[^:]+')
vim.opt.runtimepath:append(vim.fs.dirname(plugin) .. '/tokyonight.nvim')
vim.opt.termguicolors = true
vim.opt.hidden = true
require('tokyonight').setup({style='moon'})
vim.cmd.colorscheme('tokyonight-moon')
require('bufferline').setup(require('plugins.bufferline')[1].opts)
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
vim.cmd.edit('first.txt')
local original_tabline = vim.o.tabline
local review = require('config.git_review')
review.open()
local function highlight(name) return api.nvim_get_hl(0, {name=name, link=false}) end
assert(review.is_active())
assert(highlight('GitReviewTab').bg == highlight('BufferLineBufferSelected').bg)
assert(highlight('GitReviewNormal').bg == highlight('NvimTreeNormal').bg)
assert(highlight('GitReviewText').bg == nil)
local styled = false
for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
  if vim.bo[api.nvim_win_get_buf(window)].filetype == 'GitReview' then
    styled = vim.wo[window].winhighlight:find('Normal:GitReviewNormal', 1, true) ~= nil
  end
end
assert(styled)
vim.cmd.colorscheme('dotfiles')
vim.wait(50)
assert(highlight('GitReviewTab').bg == highlight('BufferLineBufferSelected').bg)
assert(highlight('GitReviewNormal').bg == highlight('NvimTreeNormal').bg)
review.close()
vim.wait(100)
assert(vim.o.tabline == original_tabline, 'themed review must restore the editor bar')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class ReviewStyle(unittest.TestCase):
    def test_connected_tree_and_semantic_text_spans(self):
        review_tests.GitReview.run_lua(self, RENDER)

    def test_theme_surfaces_and_tab_header(self):
        review_tests.GitReview.run_lua(self, THEME)

    def test_sidebar_styling_preserves_selection_and_lifecycle(self):
        review_tests.GitReview.run_lua(self, SIDEBAR)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in (*review_tests.DEPENDENCIES, 'tokyonight.nvim')), 'Plugins are not installed')
    def test_real_tokyonight_and_bufferline_theme_integration(self):
        review_tests.GitReview.run_lua(self, TOKYONIGHT, plugins=True)


if __name__ == '__main__':
    unittest.main()
