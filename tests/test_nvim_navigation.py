"""Transient code navigation, mapping restoration, and guarded LSP actions."""
import shutil
import unittest

import test_nvim_git_review as review_tests

PRELUDE = r'''
local api = vim.api
vim.g.mapleader = ' '
require('config.keymaps')
local mode = require('config.navigation_mode')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
end
local function line() return api.nvim_win_get_cursor(0)[1] end
'''

OPTIONS = PRELUDE + r'''
require('config.options')
assert(not vim.o.timeout, 'leader/multi-key mappings must wait indefinitely')
assert(vim.o.ttimeout and vim.o.ttimeoutlen == 50, 'terminal key detection must remain bounded')
assert(vim.o.expandtab and vim.o.tabstop == 4 and vim.o.shiftwidth == 4 and vim.o.softtabstop == 4,
  'default indentation must use four spaces')
press('i<Tab>x<Esc>')
assert(api.nvim_get_current_line() == '    x', 'Tab must insert four spaces')
'''

DIAGNOSTICS = PRELUDE + r'''
api.nvim_buf_set_lines(0, 0, -1, false, {'start', 'warning', 'error', 'info', 'error', 'end'})
local severity = vim.diagnostic.severity
vim.diagnostic.set(api.nvim_create_namespace('navigation-test'), 0, {
  {lnum=1, col=0, severity=severity.WARN, message='warning'},
  {lnum=2, col=0, severity=severity.ERROR, message='first error'},
  {lnum=3, col=0, severity=severity.INFO, message='info'},
  {lnum=4, col=0, severity=severity.ERROR, message='second error'},
})
local searched = 0
local original_n = function() searched = searched + 1 end
vim.keymap.set('n', 'n', original_n, {buffer=0, desc='Original search', silent=true})
press(' cd')
assert(mode.label():find('Diagnostics', 1, true))
assert(line() == 2, 'entering diagnostics must select the next item when the line has none')
assert(vim.wait(1000, function() return #api.nvim_list_wins() == 2 end),
  'entering diagnostics must open a nonfocused line popup')
assert(api.nvim_win_get_config(api.nvim_get_current_win()).relative == '')
press('n')
assert(line() == 3)
press('N')
assert(line() == 2)
press('2n')
assert(line() == 4, 'navigation must honor counts')
press(' ce')
assert(mode.label():find('Errors', 1, true))
assert(line() == 5, 'error mode must skip info')
press('N')
assert(line() == 3, 'error mode must skip warnings')
press('N')
assert(line() == 5, 'error navigation must wrap')
press('<Esc>')
assert(mode.label() == '')
assert(#api.nvim_list_wins() == 1, 'Escape must close the diagnostic popup')
local restored = vim.fn.maparg('n', 'n', false, true)
assert(restored.callback == original_n and restored.desc == 'Original search' and restored.silent == 1)
assert(vim.fn.maparg('<Esc>', 'n', false, true).buffer == 0, 'global Escape mapping must remain intact')
press('n')
assert(searched == 1, 'Escape must restore normal search mappings')
-- Entering on a diagnostic preserves the cursor and shows that line.
press(' cd')
assert(line() == 5)
press('<Esc>')
'''

POPUP_LIFECYCLE = PRELUDE + r'''
local buffer = api.nvim_get_current_buf()
api.nvim_buf_set_lines(buffer, 0, -1, false, {'first', 'warning', 'second'})
local severity = vim.diagnostic.severity
vim.diagnostic.set(api.nvim_create_namespace('popup-test'), buffer, {
  {lnum=0, col=0, severity=severity.ERROR, message='First full error\nFirst details'},
  {lnum=1, col=0, severity=severity.WARN, message='Full warning\nWarning details'},
  {lnum=2, col=0, severity=severity.ERROR, message='Second full error\nSecond details'},
})
local function popup(expected)
  vim.wait(30)
  local found = false
  for _, window in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(window).relative ~= '' then
      local lines = api.nvim_buf_get_lines(api.nvim_win_get_buf(window), 0, -1, false)
      if table.concat(lines, '\n'):find(expected, 1, true) then found = true end
    end
  end
  assert(found, 'the popup must automatically show ' .. expected)
end
local function move(key, expected)
  -- Run the mapped jump, then dispatch the cursor event as the real editor
  -- does after the Lua mapping returns. Merely checking cursor positions
  -- misses the preview's delayed CursorMoved close handler.
  vim.fn.maparg(key, 'n', false, true).callback()
  api.nvim_exec_autocmds('CursorMoved', {buffer=buffer})
  popup(expected)
end
press(' cd')
popup('First details')
move('n', 'Warning details')
move('n', 'Second details')
move('N', 'Warning details')
press(' ce')
popup('Second details')
move('N', 'First details')
move('N', 'Second details')
move('n', 'First details')
-- Queued popups must not reopen after leaving or changing navigation modes.
vim.fn.maparg('n', 'n', false, true).callback()
press('<Esc>')
vim.wait(30)
assert(#api.nvim_list_wins() == 1 and mode.label() == '')
press(' ce')
vim.fn.maparg('n', 'n', false, true).callback()
press(' cd')
popup('First details')
assert(#api.nvim_list_wins() == 2, 'old navigation requests must not create extra popups')
-- Rapid navigation must display only the final destination's details.
vim.fn.maparg('n', 'n', false, true).callback()
vim.fn.maparg('n', 'n', false, true).callback()
api.nvim_exec_autocmds('CursorMoved', {buffer=buffer})
popup('Second details')
assert(#api.nvim_list_wins() == 2)
press('<Esc>')
-- A queued popup must also be safe if its originating window is closed.
vim.cmd.vsplit()
press(' ce')
vim.fn.maparg('n', 'n', false, true).callback()
api.nvim_win_close(api.nvim_get_current_win(), true)
vim.wait(30)
assert(#api.nvim_list_wins() == 1 and mode.label() == '')
'''

LIFECYCLE = PRELUDE + r'''
local global_n = function() end
vim.keymap.set('n', 'n', global_n)
local function enter()
  mode.enter({name='Test', step=function() end})
  assert(mode.label() ~= '')
end
local function restored()
  assert(mode.label() == '')
  local mapping = vim.fn.maparg('n', 'n', false, true)
  assert(mapping.buffer == 0 and mapping.callback == global_n)
end
enter()
press('i<Esc>')
restored()
enter()
vim.cmd.vsplit()
restored()
enter()
vim.cmd.tabnew()
restored()
enter()
vim.cmd.enew()
restored()
enter()
local buffer = api.nvim_get_current_buf()
vim.cmd.enew()
api.nvim_buf_delete(buffer, {force=true})
restored()
-- A provider failure must restore keys rather than leaving a broken mode.
local message
vim.notify = function(value) message = value end
mode.enter({name='Broken', step=function() error('fixture failure') end})
press('n')
restored()
assert(message:find('fixture failure', 1, true))
'''

EMPTY = PRELUDE + r'''
local message
vim.notify = function(value) message = value end
press(' cd')
assert(mode.label() == '' and message:find('No diagnostics', 1, true))
press(' ce')
assert(mode.label() == '' and message:find('No errors', 1, true))
package.loaded.gitsigns = {get_hunks=function() return {} end}
press(' cg')
assert(mode.label() == '' and message:find('No Git hunks', 1, true))
'''

LSP_ACTIONS = PRELUDE + r'''
local called, options, message, method
vim.notify = function(value) message = value end
vim.lsp.buf.code_action = function() called = 'actions' end
vim.lsp.buf.rename = function() called = 'rename' end
vim.lsp.buf.format = function(opts) called, options = 'format', opts end
vim.lsp.get_clients = function(opts) method = opts.method; return {} end
for _, key in ipairs({' ca', ' cr', ' cf'}) do
  press(key)
  assert(called == nil and message:find('No language server supports', 1, true))
end
vim.lsp.get_clients = function(opts) method = opts.method; return {{}} end
for key, expected in pairs({[' ca']='actions', [' cr']='rename', [' cf']='format'}) do
  called = nil
  press(key)
  assert(called == expected, key .. ' must invoke ' .. expected .. ' without an LspAttach remap')
end
assert(options.async == true, 'formatting must remain asynchronous')
press(' cr')
assert(method == 'textDocument/rename')
for _, key in ipairs({' ca', ' cf'}) do
  local mapping = vim.fn.maparg(key, 'x', false, true)
  assert(type(mapping.callback) == 'function', key .. ' must support visual selections')
end
press('v cf')
assert(method == 'textDocument/rangeFormatting', 'visual formatting must check range-formatting capability')
'''

HUNKS = PRELUDE + r'''
local direction, options
package.loaded.gitsigns = {
  get_hunks=function() return {{}} end,
  nav_hunk=function(value, opts) direction, options = value, opts end,
}
press(' cg')
assert(mode.label():find('Git hunks', 1, true))
press('n')
assert(direction == 'next' and options.count == 1 and options.wrap)
press('3N')
assert(direction == 'prev' and options.count == 3)
press('<Esc>')
assert(mode.label() == '')
-- Diffview revision panes must use native diff navigation, not Gitsigns.
local normal = vim.cmd.normal
local called
vim.cmd.normal = function(args) called = args end
vim.wo.diff = true
press(' cg')
press('n')
assert(called[1] == '1]c' and called.bang)
press('2N')
assert(called[1] == '2[c' and called.bang)
press('<Esc>')
vim.cmd.normal = normal
assert(mode.label() == '')
'''


STATUSLINE = PRELUDE + r'''
local plugin = vim.env.NVIM_PLUGINS:match('^[^:]+')
vim.opt.runtimepath:append(vim.fs.dirname(plugin) .. '/lualine.nvim')
vim.opt.termguicolors = true
api.nvim_set_hl(0, 'Normal', {fg='#ffffff', bg='#101010'})
api.nvim_set_hl(0, 'NvimTreeNormal', {bg='#202020'})
local spec = require('plugins.statusline')[1]
spec.config(nil, spec.opts)
mode.enter({name='Diagnostics', step=function() end})
local rendered = api.nvim_eval_statusline(vim.o.statusline, {}).str
assert(rendered:find('Diagnostics', 1, true), 'status bar must immediately show navigation mode')
mode.leave()
rendered = api.nvim_eval_statusline(vim.o.statusline, {}).str
assert(not rendered:find('Diagnostics', 1, true), 'status bar must clear navigation mode on exit')
'''

REAL_GIT = PRELUDE + r'''
local plugin = vim.env.NVIM_PLUGINS:match('^[^:]+')
vim.opt.runtimepath:append(vim.fs.dirname(plugin) .. '/gitsigns.nvim')
local gs = require('gitsigns')
gs.setup(require('plugins.gitsigns')[1].opts)
local text = {}
for i = 1, 50 do text[i] = 'line ' .. i end
vim.fn.writefile(text, 'navigation.txt')
local function git(...)
  local result = vim.system({'git', ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
end
git('add', 'navigation.txt')
git('commit', '-qm', 'navigation fixture', '--', 'navigation.txt')
text[5], text[35] = 'changed first', 'changed second'
vim.fn.writefile(text, 'navigation.txt')
vim.cmd.edit('navigation.txt')
assert(vim.wait(5000, function() local hunks = gs.get_hunks(0); return hunks and #hunks == 2 end))
press(' cg')
press('n')
assert(vim.wait(1000, function() return line() == 5 end))
press('n')
assert(vim.wait(1000, function() return line() == 35 end))
press('N')
assert(vim.wait(1000, function() return line() == 5 end))
press('<Esc>')
assert(mode.label() == '')
assert(vim.fn.maparg('n', 'n', false, true).buffer ~= 1)
'''

REVIEW_GIT = PRELUDE + r'''
vim.cmd('runtime plugin/diffview.lua')
require('diffview').setup(require('plugins.diffview')[1].opts)
vim.cmd.edit('first.txt')
local editor_tab = api.nvim_get_current_tabpage()
local review = require('config.git_review')
review.open()
local review_tab = api.nvim_get_current_tabpage()
review.select({root=vim.fn.getcwd(), kind='staged', path='staged.txt', branch_name='main', id=node_id('staged:file:staged.txt')})
review.focus_sidebar()
assert(vim.bo.filetype == 'GitReview')
press(' cg')
assert(vim.wo.diff, 'entering Git navigation from the review sidebar must focus a diff pane')
assert(mode.label():find('Git hunks', 1, true))
press('nN')
press(' h')
assert(api.nvim_get_current_tabpage() == editor_tab and mode.label() == '')
press(' l')
assert(api.nvim_get_current_tabpage() == review_tab and review.is_active())
assert(mode.label() == '', 'returning to review must not re-enter the old navigation mode')
press(' cg')
press('<Esc>')
assert(review.is_active() and mode.label() == '', 'Escape must leave the mode, not close review')
press(' q')
assert(api.nvim_get_current_tabpage() == editor_tab)
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class Navigation(unittest.TestCase):
    def run_lua(self, lua):
        review_tests.GitReview.run_lua(self, lua)

    def test_mapping_timeout_is_disabled(self):
        self.run_lua(OPTIONS)

    def test_diagnostic_and_error_modes(self):
        self.run_lua(DIAGNOSTICS)

    def test_diagnostic_popups_follow_each_jump(self):
        self.run_lua(POPUP_LIFECYCLE)

    def test_navigation_lifecycle_and_mapping_restoration(self):
        self.run_lua(LIFECYCLE)

    def test_empty_navigation_gives_feedback(self):
        self.run_lua(EMPTY)

    def test_lsp_action_keys_and_missing_server_feedback(self):
        self.run_lua(LSP_ACTIONS)

    def test_git_hunk_mode(self):
        self.run_lua(HUNKS)

    @unittest.skipUnless((review_tests.PLUGINS / 'lualine.nvim').is_dir(), 'Lualine is not installed')
    def test_status_bar_shows_navigation_mode(self):
        review_tests.GitReview.run_lua(self, STATUSLINE, plugins=True)

    @unittest.skipUnless((review_tests.PLUGINS / 'gitsigns.nvim').is_dir(), 'Gitsigns is not installed')
    def test_real_git_hunk_navigation(self):
        review_tests.GitReview.run_lua(self, REAL_GIT, plugins=True)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_git_review_navigation_and_tab_switching(self):
        review_tests.GitReview.run_lua(self, REVIEW_GIT, plugins=True)


if __name__ == '__main__':
    unittest.main()
