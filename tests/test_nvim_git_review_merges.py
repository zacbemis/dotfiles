"""Flat merge history with source-branch/author metadata only in the header."""
import shutil
import unittest

import test_nvim_git_review as review_tests

HELPERS = r'''
local repository = require('config.git_review.repository')
local root = vim.fn.getcwd()
local function git(...)
  local result = vim.system({'git', ...}, {text=true}):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function commit(path, text, subject, author)
  vim.fn.writefile({text}, path)
  git('add', path)
  git('commit', '-m', subject, '--author', author .. ' <author@example.invalid>')
  return git('rev-parse', 'HEAD')
end
git('add', '-A')
git('commit', '-m', 'fixture checkpoint')
local base = git('rev-parse', 'HEAD')
local function find(rows, id)
  for _, row in ipairs(rows) do if row.id == id then return row end end
end
'''

SETUP = HELPERS + r'''
git('switch', '-q', '-c', 'feature/search')
local alice = commit('first.txt', 'feature first content', 'feature: first change', 'Alice Example')
local bob = commit('feature.txt', 'feature second content', 'feature: second change', 'Bob Example')
git('switch', '-q', 'main')
local before_merge = commit('main.txt', 'main before merge', 'main: before merge', 'Main Author')
git('merge', '--no-ff', 'feature/search', '-m', "Merge branch 'feature/search' into main")
local merge = git('rev-parse', 'HEAD')
git('branch', '-D', 'feature/search')
git('update-ref', 'refs/remotes/origin/renamed', bob)
local main_one = commit('main.txt', 'main one', 'main: first local change', 'Main Author')
local main_two = commit('main.txt', 'main two', 'main: second local change', 'Main Author')
vim.fn.writefile({'working content'}, 'first.txt')
vim.fn.writefile({'staged content'}, 'staged.txt')
git('add', 'staged.txt')
local before_status = git('status', '--porcelain=v1')
local before_index = git('diff', '--cached')
local function unchanged()
  assert(git('symbolic-ref', 'HEAD') == 'refs/heads/main')
  assert(git('rev-parse', 'HEAD') == main_two)
  assert(git('status', '--porcelain=v1') == before_status)
  assert(git('diff', '--cached') == before_index)
  assert(vim.fn.readfile('first.txt')[1] == 'working content')
end
'''

REPOSITORY = SETUP + r'''
local commits = repository.commits(root, 'HEAD', 100)
local hashes, positions = {}, {}
for index, c in ipairs(commits) do hashes[c.hash], positions[c.hash] = c, index end
assert(hashes[main_one] and hashes[main_two] and hashes[merge] and hashes[alice] and hashes[bob])
assert(hashes[merge].parents[1] == before_merge and hashes[merge].parents[2] == bob)
assert(hashes[merge].author == 'Test')
assert(hashes[bob].author == 'Bob Example' and hashes[alice].author == 'Alice Example')
for _, c in ipairs(commits) do
  for _, parent in ipairs(c.parents) do
    if positions[parent] then assert(positions[c.hash] < positions[parent], 'children must precede every parent') end
  end
end
vim.fn.writefile({'Alice Canonical <canonical@example.invalid> Alice Example <author@example.invalid>'}, '.mailmap')
assert(repository.commits(root, alice, 1)[1].author == 'Alice Canonical')
vim.fn.delete('.mailmap')
unchanged()
print('PASS: flat topological history, all incoming commits, parent edges, author and mailmap')
'''

TREE = SETUP + r'''
local model = require('config.git_review.tree').new(root, repository)
local rows = model:rows()
local top = {}
for _, row in ipairs(rows) do if row.depth == 1 then top[#top+1] = row end end
assert(top[1].kind == 'unstaged' and top[2].kind == 'staged')
assert(top[3].id == commit_id(main_two) and top[4].id == commit_id(main_one))
assert(find(rows, commit_id(merge)).kind == 'commit')
assert(find(rows, commit_id(merge)).label:find("Merge branch 'feature/search'", 1, true))
assert(find(rows, commit_id(alice)) and find(rows, commit_id(bob)), 'incoming commits must be ordinary sibling rows')
for index=3,#top do assert(top[index].kind == 'commit', 'no merge/source folder nodes may remain') end
assert(model:context(commit_id(alice)).branch_name == 'feature/search')
assert(model:context(commit_id(alice)).author == 'Alice Example')
assert(model:context(commit_id(bob)).author == 'Bob Example')
assert(model:context(commit_id(merge)).branch_name == 'feature/search')
assert(model:context(commit_id(merge)).author == 'Test')
assert(model:context(commit_id(before_merge)).branch_name == 'main')
assert(model:context(commit_id(base)).branch_name == 'main', 'shared ancestors must retain mainline context')
model:drill(commit_id(alice))
assert(#model:rows() == 2 and model:rows()[2].kind == 'file')
local selection = model:selection(commit_id(alice) .. ':file:first.txt')
assert(selection.branch_name == 'feature/search' and selection.author == 'Alice Example')
assert(not model:can_stage(selection.id) and not pcall(model.stage, model, selection.id))
model:drill(commit_id(merge))
local aggregate = model:selection(commit_id(merge) .. ':file:first.txt')
assert(aggregate.hash == merge and aggregate.parent == before_merge)
for _, row in ipairs(model:rows()) do
  assert(not row.label:find('Alice Example',1,true) and not row.label:find('Bob Example',1,true))
  assert(row.label ~= 'Merged changes')
end
git('update-ref', '-d', 'refs/remotes/origin/renamed')
assert(model:refresh() and model:rows()[1].id == commit_id(merge))
assert(model:context(commit_id(alice)).branch_name == 'feature/search')
unchanged()
print('PASS: flat commit/file tree, retained source and author metadata, deleted refs, no extra folders')
'''

NESTED = HELPERS + r'''
git('switch', '-q', '-c', 'feature/outer')
local outer_commit = commit('outer.txt', 'outer', 'outer change', 'Outer Author')
git('switch', '-q', '-c', 'feature/inner')
local inner_commit = commit('inner.txt', 'inner', 'inner change', 'Inner Author')
git('switch', '-q', 'feature/outer')
git('merge', '--no-ff', 'feature/inner', '-m', "Merge branch 'feature/inner' into feature/outer")
local inner_merge = git('rev-parse', 'HEAD')
git('switch', '-q', 'main')
git('merge', '--no-ff', 'feature/outer', '-m', "Merge branch 'feature/outer' into main")
local outer_merge = git('rev-parse', 'HEAD')
git('branch', '-D', 'feature/inner', 'feature/outer')
local model = require('config.git_review.tree').new(root, repository)
local rows = model:rows()
for _, hash in ipairs({outer_merge, inner_merge, outer_commit, inner_commit}) do
  assert(find(rows,commit_id(hash)).depth == 1, 'nested merges must also be flat')
end
assert(model:context(commit_id(outer_commit)).branch_name == 'feature/outer')
assert(model:context(commit_id(inner_commit)).branch_name == 'feature/inner')
assert(model:context(commit_id(inner_commit)).author == 'Inner Author')
assert(model:context(commit_id(inner_merge)).branch_name == 'feature/inner')
assert(model:context(commit_id(base)).branch_name == 'main')
print('PASS: nested merges stay flat while retaining source and author attribution')
'''

REPEATED = HELPERS + r'''
git('switch', '-q', '-c', 'feature/repeat')
local first = commit('repeat.txt', 'first', 'first incoming', 'First Author')
git('switch', '-q', 'main')
git('merge', '--no-ff', 'feature/repeat', '-m', "Merge branch 'feature/repeat'")
local first_merge = git('rev-parse', 'HEAD')
git('switch', '-q', 'feature/repeat')
local second = commit('repeat.txt', 'second', 'second incoming', 'Second Author')
git('switch', '-q', 'main')
git('merge', '--no-ff', 'feature/repeat', '-m', "Merge branch 'feature/repeat'")
local second_merge = git('rev-parse', 'HEAD')
local model = require('config.git_review.tree').new(root, repository)
local seen = {}
for _, row in ipairs(model:rows()) do assert(not seen[row.id]); seen[row.id] = true end
for _, hash in ipairs({first, second, first_merge, second_merge}) do
  assert(seen[commit_id(hash)] and model:context(commit_id(hash)).branch_name == 'feature/repeat')
end
print('PASS: repeated merges do not duplicate commits or create folders')
'''

OCTOPUS = HELPERS + r'''
git('switch', '-q', '-c', 'side/one')
local one = commit('one.txt', 'one', 'one change', 'One Author')
git('switch', '-q', '-c', 'side/two', base)
local two = commit('two.txt', 'two', 'two change', 'Two Author')
git('switch', '-q', 'main')
git('merge', '--no-ff', 'side/one', 'side/two', '-m', 'Integrate parallel work')
local merge = git('rev-parse', 'HEAD')
local model = require('config.git_review.tree').new(root, repository)
assert(model:context(commit_id(merge)).branch_name == 'side/one + side/two')
assert(model:context(commit_id(one)).branch_name == 'side/one')
assert(model:context(commit_id(two)).branch_name == 'side/two')
assert(model:context(commit_id(base)).branch_name == 'main')
git('branch','-D','side/one','side/two')
assert(model:refresh())
assert(model:context(commit_id(one)).branch_name == 'Merged branch ' .. one:sub(1,7))
assert(model:context(commit_id(two)).branch_name == 'Merged branch ' .. two:sub(1,7))
print('PASS: octopus source metadata and honest unknown-source fallbacks, without folders')
'''

PAGINATION = r'''
local calls = 0
local repo = {
  status = function() return {unstaged={}, staged={}} end,
  branches = function() return {{ref='refs/heads/main', name='main', hash='merge', current=true}} end,
  commits = function(_, tip, maximum)
    calls = calls + 1
    assert(tip == 'merge')
    local commits = {{hash='merge', short='merge', subject="Merge branch 'feature/paged'", author='Merger', parents={'base','source1'}}}
    for index=1, math.min(maximum-1,225) do
      commits[#commits+1] = {hash='source'..index, short=tostring(index), subject='source change', author='Author', parents={'source'..(index+1)}}
    end
    return commits
  end,
  commit_files = function() return {} end,
}
local model = require('config.git_review.tree').new(vim.fn.getcwd(),repo)
assert(calls == 1)
assert(model:context(commit_id('source99')).branch_name == 'feature/paged')
assert(model:expand(node_id('more')) == commit_id('source100'))
assert(calls == 2 and model:context(commit_id('source150')).branch_name == 'feature/paged')
assert(model:expand(node_id('more')) == commit_id('source200'))
assert(calls == 3 and model:context(commit_id('source225')).branch_name == 'feature/paged')
print('PASS: flat pagination preserves source metadata across page boundaries')
'''

NAMING = r'''
local history = require('config.git_review.history')
local function names(subject,parents,branches)
  return history.sources({subject=subject,parents=parents or {'target','source'}},branches or {})
end
assert(names("Merge branch 'deleted/feature' into main")[1].name=='deleted/feature')
assert(names("Merge remote-tracking branch 'origin/topic'")[1].name=='origin/topic')
assert(names('Merge pull request #42 from owner/team/feature')[1].name=='team/feature')
assert(names('Merged in feature/search (pull request #4)')[1].name=='feature/search')
local many=names("Merge branches 'side/a', 'side/b' and 'side/c' into main",{'target','a','b','c'})
assert(#many==3 and many[1].name=='side/a' and many[2].name=='side/b' and many[3].name=='side/c')
local fallback=names('custom integration',nil,{
  {hash='source',name='origin/topic',remote=true},{hash='source',name='topic',remote=false},
})
assert(fallback[1].name=='topic')
assert(names('custom integration')[1].name=='Merged branch source')
print('PASS: historical source naming retained solely for header metadata')
'''

LINEAR = HELPERS + r'''
git('switch','-q','-c','feature/linear')
local incoming=commit('linear.txt','linear',"Merge branch 'not-a-real-merge'",'Linear Author')
git('switch','-q','main')
git('merge','--ff-only','feature/linear')
local model=require('config.git_review.tree').new(root,repository)
assert(find(model:rows(),commit_id(incoming)).kind=='commit')
local context=model:context(commit_id(incoming))
assert(context.branch_name=='main' and context.author=='Linear Author')
print('PASS: linear history does not invent branch origins from merge-like subjects')
'''

CONFLICT = HELPERS + r'''
git('switch','-q','-c','feature/conflict')
local feature=commit('first.txt','feature version','feature edit','Feature Author')
git('switch','-q','main')
local target=commit('first.txt','main version','main edit','Main Author')
local result=vim.system({'git','merge','--no-ff','feature/conflict'},{text=true}):wait()
assert(result.code==1,'fixture must produce a real merge conflict')
vim.fn.writefile({'resolved merge version'},'first.txt')
git('add','first.txt')
git('commit','--no-edit','--author','Merge Author <merge@example.invalid>')
local merge=git('rev-parse','HEAD')
'''

WORKFLOW = CONFLICT + r'''
local api=vim.api
vim.g.mapleader=' '
vim.opt.hidden=true
require('config.keymaps')
vim.cmd('runtime plugin/diffview.lua')
local spec=require('plugins.diffview')[1]
require('diffview').setup(spec.opts)
vim.keymap.set('n',spec.keys[1][1],spec.keys[1][2])
local function press(key)
  api.nvim_feedkeys(api.nvim_replace_termcodes(key,true,false,true),'xt',false)
  vim.wait(50)
  api.nvim_exec_autocmds('CursorMoved',{})
end
vim.cmd.edit('first.txt')
press(' gd')
local review=require('config.git_review')
local tab,windows=api.nvim_get_current_tabpage(),api.nvim_tabpage_list_wins(0)
local sidebar
for _,window in ipairs(windows) do
  if vim.bo[api.nvim_win_get_buf(window)].filetype=='GitReview' then sidebar=window end
end
local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(sidebar),0,-1,false) end
local function choose(label)
  api.nvim_set_current_win(sidebar)
  for row,line in ipairs(lines()) do
    if line:find(label,1,true) then press(row..'G'); return end
  end
  error('Missing entry: '..label)
end
local function title(expected)
  local text=vim.trim(api.nvim_eval_statusline(vim.o.tabline,{use_tabline=true,maxwidth=200}).str)
  assert(text==expected,'Expected '..expected..', got '..text)
  assert(api.nvim_get_current_tabpage()==tab and vim.deep_equal(api.nvim_tabpage_list_wins(tab),windows))
end
local subject=repository.commits(root,merge,1)[1].subject
choose(subject)
title('feature/conflict · Merge Author · '..subject)
press('L')
choose('first.txt')
press('l')
assert(api.nvim_buf_get_lines(0,0,1,false)[1]=='resolved merge version')
review.focus_sidebar()
press('H')
choose('feature edit')
title('feature/conflict · Feature Author · feature edit')
press('<C-l>')
title('feature/conflict · Merge Author · '..subject)
press('<C-h>')
title('feature/conflict · Feature Author · feature edit')
press('L')
choose('first.txt')
press('l')
assert(api.nvim_buf_get_lines(0,0,1,false)[1]=='feature version')
title('feature/conflict · Feature Author · feature edit')
git('update-ref','refs/remotes/origin/copy',feature)
review.refresh()
review.focus_sidebar()
press('H') -- main's flat commit list
press('H') -- branch list
choose('origin/copy')
press('L')
choose('feature edit')
press('L')
choose('first.txt')
press('l')
title('origin/copy · Feature Author · feature edit')
review.focus_sidebar()
press('H')
press('H')
choose('main (current)')
press('L')
choose('main edit')
title('main · Main Author · main edit')
press('<C-l>')
title('origin/copy · Feature Author · feature edit')
assert(git('symbolic-ref','HEAD')=='refs/heads/main')
assert(git('status','--porcelain=v1')=='')
assert(vim.fn.readfile('first.txt')[1]=='resolved merge version')
press(' q')
assert(#api.nvim_list_tabpages()==1)
print('PASS: flat merge review, retained branch/authors, focus context, stable panes, read-only content')
'''


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git are required')
class MergeReview(unittest.TestCase):
    def run_lua(self, lua, *, plugins=False):
        review_tests.GitReview.run_lua(self, lua, plugins=plugins)

    def test_flat_history_queries_and_authors(self):
        self.run_lua(REPOSITORY)

    def test_flat_tree_and_source_metadata(self):
        self.run_lua(TREE)

    def test_nested_merge_metadata_without_folders(self):
        self.run_lua(NESTED)

    def test_repeated_merges(self):
        self.run_lua(REPEATED)

    def test_octopus_and_unknown_sources(self):
        self.run_lua(OCTOPUS)

    def test_flat_pagination_preserves_source_metadata(self):
        self.run_lua(PAGINATION)

    def test_source_naming(self):
        self.run_lua(NAMING)

    def test_linear_history_does_not_guess_sources(self):
        self.run_lua(LINEAR)

    @unittest.skipUnless(all((review_tests.PLUGINS / name).is_dir() for name in review_tests.DEPENDENCIES), 'Plugins are not installed')
    def test_flat_conflict_review_workflow(self):
        self.run_lua(WORKFLOW, plugins=True)


if __name__ == '__main__':
    unittest.main()
