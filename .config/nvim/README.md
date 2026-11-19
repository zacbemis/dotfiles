# Neovim

Standalone configuration using lazy.nvim, not LazyVim. Launch with `nvim`.

## Features

- Full-window file explorer on startup and after closing the last file; sidebar while editing.
- Explorer selection and viewport remembered per working directory across restarts.
- Open-file tabs with keyboard navigation, splits and a shared status bar.
- Telescope file, text, buffer and help search.
- LSP navigation, diagnostics, rename, code actions and format-on-save.
- Mason-managed servers for Lua, C/C++/CUDA, CMake, JavaScript/TypeScript, Java, HTML, CSS, Rust and Python.
- Completion, snippets, automatic bracket pairs and HTML/JSX tag handling.
- Treesitter highlighting/folds and local Brief (`.brf`) syntax support.
- Git gutter signs, hunk staging/blame and branch/commit review with side-by-side diffs.
- Git review includes staged/unstaged files across worktrees, local/fetched remote branches and flat merge history without checkout.
- Review sidebar matches the file explorer's connected tree, icons and Git badges; its top bar shares editor-tab surfaces and follows theme changes.
- Fixed VS Code–inspired syntax colors with live Pywal/Matugen backgrounds.
- PDFs open in the default browser.

## Main keys

Space-prefixed and other multi-key mappings wait indefinitely; press `Esc` to cancel.

| Key | Action |
| --- | --- |
| `::` | Open editable command-history split; `Enter` runs the current line, `Space q` closes |
| `Space w` / `Space q` | Save / close file or review tab; protect unsaved changes |
| `Space e` | Toggle explorer or review sidebar |
| `Space k` | Focus file-tab navigation; `h` / `l` switch files |
| `Space h` / `Space l` | Previous / next Neovim tab (including Git review) |
| `[b` / `]b` | Previous / next buffer |
| `Shift-h` / `Shift-l` | Previous / next file tab; collapse / expand context in Git diffs |
| `Ctrl-h/j/k/l` | Move between windows |
| `Space ff` / `Space fg` | Find files / search text |
| `Space gd` | Open Git review |
| `gd` / `gr` / `K` | Definition / references / hover |
| `Space cd` | Diagnostic navigation mode (errors, warnings and info) |
| `Space ce` | Error-only navigation mode |
| `Space cg` | Git-hunk navigation mode (also in Git review) |
| `Space ca` | Code actions |
| `Space cr` | Rename symbol |
| `Space cf` | Format code |
| `Tab` / `Enter` | Accept completion / advance snippet or insert newline |
| `g?` | Explorer/review help |

Command history is a regular scratch split: `Ctrl-j/k` moves into/out of it, and
`Ctrl-c` does not close it. Edit a previous command or type a new one on the blank last line.

In navigation modes, `n` / `N` move next / previous (counts supported); `Esc` exits.
The status bar shows the active mode. Normal search mappings are restored on exit,
and switching buffers/windows/tabs or entering insert mode also exits.
`Space cd` shows the current line's diagnostics, or selects the next diagnostic if the line has none.
Empty diagnostic/hunk lists and unavailable LSP actions report why nothing can happen.
Rename, code actions and formatting need a language server supporting that action;
use `:checkhealth vim.lsp` to check attachment and server health.

`:q` / `:quit` uses normal Neovim behavior: close the current window, exiting if it is the last.
`Space q` closes the current file buffer (across splits) or the Git review tab, protecting unsaved changes.
Use `:qa` to quit all windows and tabs, or `:qa!` to discard all unsaved changes.

In Git review, press `H` from the current branch root to see all branches. A branch
checked out in another worktree has a `worktree:` label; detached worktrees get
separate rows. Expand a worktree row to see its staged and unstaged files alongside
its history. `s` stages or unstages in that worktree's index. `Shift-L` on a
branch or worktree row makes it the browser root without checking anything out.

Press `gS` on a branch or worktree row. A local branch with no existing checkout
is checked out in the current worktree; unsaved editor changes and Git's normal
checkout protections still apply. A branch checked out elsewhere opens that
worktree immediately in a separate Kitty window running Neovim (or a new editor tab
if Kitty or a graphical display is unavailable). The original review stays open.
Remote-tracking rows remain browse-only.

## Requirements

Neovim 0.12+, Git, a C compiler, curl, tar, ripgrep, a Nerd Font and tree-sitter CLI 0.26.1+.
First launch downloads plugins, parsers and language servers; use `:Lazy` and `:Mason` to manage them.
If tree-sitter CLI is missing, run `:MasonInstall tree-sitter-cli` and restart.
Language runtimes and project dependencies are installed separately; Java requires JDK 21+.
