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
  local source = vim.fn.getline(line)
  local col
  if text:match('^[%w_]+$') then
    col = source:find('%f[%w_]' .. text .. '%f[^%w_]')
  else
    col = source:find(text, 1, true)
  end
  assert(col, ('line %d: missing %s'):format(line, text))
  -- Check the whole token, including #!, not just its first character.
  for offset = 0, #text - 1 do
    local actual = vim.fn.synIDattr(vim.fn.synID(line, col + offset, 1), 'name')
    assert(actual == expected, ('line %d %s (+%d): expected %s, got %s')
      :format(line, text, offset, expected, actual))
  end
end
local function checks()
  check(1, 'type', 'briefKeyword')
  check(1, 'Outcome', 'briefTypeName')
  check(1, '#ok', 'briefSymbol')
  check(1, '#!badAmount', 'briefSymbol')
  check(1, 'lng', 'briefType')
  check(2, 'fn', 'briefKeyword')
  check(2, 'deposit', 'briefFunction')
  check(2, 'account', 'briefIdentifier')
  check(2, 'Account', 'briefType')
  check(2, '->', 'briefOperator')
  check(3, 'let', 'briefKeyword')
  check(3, '"if // #ok', 'briefString')
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
  check(6, '1.25', 'briefFloat')
  check(6, 'then', 'briefConditional')
  check(6, 'ret', 'briefStatement')
  check(6, '#ok', 'briefSymbol')
  check(7, '//', 'briefComment')
  check(7, 'TODO', 'briefTodo')
  check(7, 'false', 'briefComment')
  check(9, 'let', 'briefComment')
  check(10, 'let', 'briefKeyword')
  check(10, ':', 'briefDelimiter')
  check(10, 'int', 'briefType')
  check(10, '42', 'briefNumber')
  check(12, 'mod', 'briefInclude')
  check(12, 'BalanceCollection', 'briefTypeName')
  check(13, 't', 'briefTypeName')
  check(13, 'as', 'briefKeyword')
  check(13, 'Vec', 'briefType')
  check(14, 'fn', 'briefKeyword')
  check(14, 'new', 'briefFunction')
  check(14, 't', 'briefType')
  check(14, ':=', 'briefOperator')
  check(15, 'bln', 'briefType')
  check(15, 'false', 'briefBoolean')
  check(16, 'dbl', 'briefType')
  check(17, '|>', 'briefOperator')
  check(17, '#!sameAccount', 'briefSymbol')
  check(17, '#if', 'briefSymbol')
  check(17, '#true', 'briefSymbol')
  check(18, 'var', 'briefKeyword')
  check(18, 'yield', 'briefStatement')
  check(19, 'else', 'briefConditional')
  check(19, '?', 'briefOperator')
  check(20, 'Arr', 'briefType')
  check(20, ':=', 'briefOperator')
  check(21, 't', 'briefType')
  -- A direct jump deep into the design notes must not treat them as code.
  check(95, 'fn', 'briefComment')
  check(96, 'mod', 'briefComment')
  check(98, 'fn', 'briefKeyword')
end
-- Query the distant comment first, as when opening a file at a saved cursor.
check(95, 'fn', 'briefComment')
checks()
-- The local colorscheme resets syntax; Brief rules and links must survive it.
require('config.syntax').apply()
checks()
for group, target in pairs({briefSymbol='Constant', briefTypeName='Type', briefFunction='Function'}) do
  assert(vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(group)), 'name') == target)
end
vim.cmd.edit(vim.env.BRIEF_NEW)
assert(vim.bo.filetype == 'brief')
assert(vim.b.current_syntax == 'brief')
vim.cmd('qa!')
'''

SAMPLE = r'''type Outcome: #ok | #!badAmount(lng)
fn deposit(account: Account.t, amount: lng): Outcome -> {
  let text = "if // #ok \"quoted\"\n"
  let tab = '\t'
  for i in 0..10 { print(i) }
  if true and amount > 1.25 then ret #ok
  // TODO false
  /* block
     let hidden = "not code" */
  let count:int = 42
}
mod BalanceCollection(B: Balance): [
  type t: [accounts as balanceVec: Vec(B.t)]
  fn new() -> t := [accounts = Vec(B.t).new()]
  let frozen:bln = false
  let rate: dbl = 1.25
  status |> { #!sameAccount -> #if; #true -> #ok }
  for var account in accounts { yield account }
  if frozen then deposit()? else []
  let numbers = Arr(int) := [1, 2, 3]
  let collection: BalanceCollection.t = value
]
/*
'''
SAMPLE += '\n' * 71 + 'fn hidden() -> #!badAmount(1)\nmod Hidden: []\n*/\nfn visible(): [] -> []\n'


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is not installed')
class BriefSyntax(unittest.TestCase):
    def test_filetype_syntax_and_colorscheme_reload(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / 'sample.brf').write_text(SAMPLE)
            (tmp / 'check.lua').write_text(LUA)
            config = os.environ.get('BRIEF_TEST_CONFIG', str(ROOT / '.config/nvim'))
            env = dict(os.environ, BRIEF_CONFIG=config,
                       BRIEF_SAMPLE=str(tmp / 'sample.brf'),
                       BRIEF_NEW=str(tmp / 'new.brf'))
            result = subprocess.run(
                ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(tmp / 'check.lua')],
                env=env, capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
