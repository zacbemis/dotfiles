"""Background :! commands and their status in the :: history split."""
import shutil
import unittest

import test_nvim_git_review as review_tests

PRELUDE = r'''
local api = vim.api
vim.g.mapleader = ' '
require('config.keymaps')
local tasks = require('config.tasks')
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), 'xt', false)
end
local function wait_for(command_line, kind)
  assert(vim.wait(5000, function()
    local task = tasks.latest(command_line)
    return task and task:state().kind == kind
  end, 10), command_line .. ' never reached ' .. kind)
  return tasks.latest(command_line)
end
local function annotation(buffer, text)
  local namespace = api.nvim_get_namespaces()['config.command_history']
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {details=true})) do
    local line = api.nvim_buf_get_lines(buffer, mark[2], mark[2] + 1, false)[1]
    if line == text then return mark[4].virt_text[1][1] end
  end
end
local notices = {}
vim.notify = function(message, level) notices[#notices + 1] = {message=message, level=level} end
'''

BACKGROUND = PRELUDE + r'''
local started = vim.uv.hrtime()
press(':!sleep 30<CR>')
local server = wait_for('!sleep 30', 'running')
assert((vim.uv.hrtime() - started) / 1e9 < 5, ':! must not block the editor')
assert(vim.fn.histget('cmd', -1) == '!sleep 30', 'background commands must stay in command history')
assert(not vim.bo[server:output_buffer()].buflisted, 'output must not appear as a file tab')

press(":!printf 'built\\n'; exit 3<CR>")
local build = wait_for("!printf 'built\\n'; exit 3", 'exited')
assert(build:state().code == 3)
assert(vim.wait(1000, function() return #notices == 1 end), 'finished commands must notify')
assert(notices[1].level == vim.log.levels.ERROR and notices[1].message:find('exit 3', 1, true))

press('::')
local history = api.nvim_get_current_buf()
assert(annotation(history, '!sleep 30'):find('running since', 1, true))
assert(annotation(history, "!printf 'built\\n'; exit 3"):find('exit 3', 1, true))
assert(not annotation(history, 'nonexistent'))
vim.fn.search([[^!printf]])
press('go')
assert(api.nvim_get_current_buf() == build:output_buffer(), 'go must open the command output')
assert(vim.tbl_contains(api.nvim_buf_get_lines(0, 0, -1, false), 'built'))
assert(api.nvim_get_current_line() ~= '', 'output must open at its last line, not terminal padding')
press(' q')
assert(api.nvim_buf_is_valid(build:output_buffer()), 'Space q must keep the output buffer')

vim.fn.confirm = function() return 1 end
press(':!sleep 30<CR>')
assert(vim.wait(5000, function() return tasks.latest('!sleep 30') ~= server end))
assert(not api.nvim_buf_is_valid(server:output_buffer()), 'restarting must discard the old run')
wait_for('!sleep 30', 'running')
'''

NATIVE_AND_EXPANSION = PRELUDE + r'''
vim.cmd.edit('first.txt')
api.nvim_buf_set_lines(0, 0, -1, false, {'b', 'a'})
press(':%!sort<CR>')
assert(vim.deep_equal(api.nvim_buf_get_lines(0, 0, -1, false), {'a', 'b'}), 'ranged filters stay native')
vim.bo.modified = false

press(':!echo \\% %:r<CR>')
local task = wait_for('!echo \\% %:r', 'exited')
assert(vim.tbl_contains(api.nvim_buf_get_lines(task:output_buffer(), 0, -1, false), '% first'),
  '% must expand to the current file like native :!, and \\% must stay literal')

press(':!! again<CR>')
task = wait_for('!echo \\% %:r again', 'exited')
assert(vim.tbl_contains(api.nvim_buf_get_lines(task:output_buffer(), 0, -1, false), '% first again'),
  ':!! must repeat the previous command')

vim.cmd.enew()
press(':!echo %<CR>')
assert(vim.wait(1000, function() return vim.v.errmsg:find('E499', 1, true) end), 'unnamed % must error')
assert(not tasks.latest('!echo %'), 'failed expansion must not start a task')

vim.fn.histadd('cmd', '!printf history')
press('::')
press('k<CR>')
task = wait_for('!printf history', 'exited')
assert(vim.tbl_contains(api.nvim_buf_get_lines(task:output_buffer(), 0, -1, false), 'history'),
  'history Enter must run :! in the background too')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class ShellTasks(unittest.TestCase):
    def run_lua(self, lua):
        review_tests.GitReview.run_lua(self, lua)

    def test_background_commands_and_history_status(self):
        self.run_lua(BACKGROUND)

    def test_native_filters_expansion_and_history_execution(self):
        self.run_lua(NATIVE_AND_EXPANSION)


if __name__ == '__main__':
    unittest.main()
