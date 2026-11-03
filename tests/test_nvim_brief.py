"""Offline Brief filetype/highlighting smoke test (requires Neovim)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

LUA = r'''
vim.opt.runtimepath:prepend(vim.env.BRIEF_CONFIG)
vim.cmd('filetype plugin on')
vim.cmd('syntax enable')
vim.cmd.edit(vim.env.BRIEF_SAMPLE)
assert(vim.bo.filetype == 'brief', vim.bo.filetype)
assert(vim.bo.syntax == 'brief', vim.bo.syntax)
assert(vim.b.current_syntax == 'brief')
assert(vim.bo.commentstring == '// %s')

local function check(line, text, expected)
  local col = assert(vim.fn.getline(line):find(text, 1, true))
  local actual = vim.fn.synIDattr(vim.fn.synID(line, col, 1), 'name')
  assert(actual == expected, ('line %d %s: expected %s, got %s'):format(line, text, expected, actual))
end
local function checks()
  check(1, 'type', 'briefKeyword')
  check(1, 'Outcome', 'briefType')
  check(1, 'Sym', 'briefType')
  check(1, ':ok', 'briefSymbol')
  check(1, ':badAmount', 'briefSymbol')
  check(1, 'lng', 'briefType')
  check(2, 'deposit', 'briefFunction')
  check(2, 'account', 'briefIdentifier')
  check(2, '&', 'briefOperator')
  check(2, 'Self', 'briefType')
  check(3, 'let', 'briefKeyword')
  check(3, '"', 'briefString')
  check(3, 'if', 'briefString')
  check(3, [[\n]], 'briefEscape')
  check(4, "'", 'briefCharacter')
  check(4, [[\t]], 'briefEscape')
  check(5, 'for', 'briefRepeat')
  check(5, 'in', 'briefRepeat')
  check(5, '0', 'briefNumber')
  check(5, '..', 'briefOperator')
  check(5, '10', 'briefNumber')
  check(5, 'print', 'briefFunction')
  check(6, 'if', 'briefConditional')
  check(6, 'true', 'briefBoolean')
  check(6, 'and', 'briefOperator')
  check(6, '1.25', 'briefFloat')
  check(6, 'ret', 'briefStatement')
  check(6, ':ok', 'briefSymbol')
  check(7, '//', 'briefComment')
  check(7, 'TODO', 'briefTodo')
  check(7, 'false', 'briefComment')
  check(9, 'let', 'briefComment')
  check(10, 'let', 'briefKeyword')
  check(10, 'int', 'briefType') -- Compact type annotation is not a symbol.
  check(10, '42', 'briefNumber')
end
checks()
-- The local colorscheme resets syntax; Brief rules and links must survive it.
require('config.syntax').apply()
checks()
assert(vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID('briefSymbol')), 'name') == 'Constant')
vim.cmd.edit(vim.env.BRIEF_NEW)
assert(vim.bo.filetype == 'brief')
assert(vim.b.current_syntax == 'brief')
vim.cmd('qa!')
'''

SAMPLE = r'''type Outcome = Sym<:ok, :badAmount(lng)>
deposit(account: &Self, amount: lng): Outcome {
  let text = "if // :ok \"quoted\"\n"
  let tab = '\t'
  for i in 0..10 { print(i) }
  if true and amount > 1.25 { ret :ok }
  // TODO false
  /* block
     let hidden = "not code" */
  let count:int = 42
}
'''


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is not installed')
class BriefSyntax(unittest.TestCase):
    def test_filetype_syntax_and_colorscheme_reload(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / 'sample.brf').write_text(SAMPLE)
            (tmp / 'check.lua').write_text(LUA)
            env = dict(os.environ, BRIEF_CONFIG=str(ROOT / '.config/nvim'),
                       BRIEF_SAMPLE=str(tmp / 'sample.brf'),
                       BRIEF_NEW=str(tmp / 'new.brf'))
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(tmp / 'check.lua')],
                env=env, capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
