# Neovim config

Your standalone Neovim setup, using lazy.nvim as the plugin manager—not LazyVim.

## Launch

```sh
nvim
```

This is now the main config at `~/.config/nvim`. The `nvown` Zsh alias also runs
plain `nvim`; open a new terminal or run `source ~/.zshrc` to update the alias.
No `NVIM_APPNAME` override is needed. Plugins, cache, undo, and language servers
use Neovim's standard `nvim` directories.

Bare `nvim` opens a full-window file explorer instead of an empty `[No Name]`
file tab. Choose a file with `Enter`, `l`, or `L` to replace the explorer with
that file. `nvim filename` still opens the file normally; stdin and restored
sessions are left alone. After opening a file, `Space e` opens the usual sidebar.
Closing the last file returns to the full-window explorer instead of creating
an empty file tab. Unsaved changes are still protected. Empty-line `~` markers
are hidden in both the editor and explorer.

## Files

- `init.lua`: entry point and leader keys.
- `lua/config/options.lua`: editor options and fallback colorscheme.
- `lua/config/pdf.lua`: open PDFs in the default web browser.
- `lua/config/wallpaper.lua`: wallpaper backgrounds and live reload.
- `lua/config/syntax.lua`: fixed VS Code–inspired syntax and plugin/UI highlights.
- `colors/dotfiles.lua`: local colorscheme entry point (no theme plugin).
- `lua/config/keymaps.lua`: your keybindings. The leader key is Space.
- `lua/config/tab_navigation.lua`: focusable overlay for the file tab bar.
- `lua/config/lazy.lua`: standalone lazy.nvim plugin manager.
- `lua/plugins/explorer.lua`: explorer keybindings and nvim-tree sidebar settings.
- `lua/config/explorer.lua`: connected tree branches and full-window explorer on startup/last-file close.
- `lua/plugins/bufferline.lua`: top bar for open files.
- `lua/plugins/statusline.lua`: compact Lualine bottom bar and explorer status.
- `lua/plugins/telescope.lua`: fuzzy finder and search keybindings.
- `lua/plugins/diffview.lua`: Git-review entry point and Diffview rendering configuration.
- `lua/config/git_review/`: repository queries, review-tree state, sidebar, Diffview adapter, and session lifecycle.
- `lua/plugins/lsp.lua`: language server management and completion plugins.
- `lua/config/lsp.lua`: enabled servers, diagnostics, and LSP keybindings.
- `lua/config/treesitter.lua`: language parsers, highlighting, indentation, and folds.
- `lua/plugins/treesitter.lua`: Treesitter installation and updates.
- `lua/plugins/gitsigns.lua`: Git gutter signs and hunk keybindings.
- `lua/plugins/pairs.lua`: automatic bracket/quote pairing and HTML/JSX tag handling.

Start editing with `nvim ~/dotfiles/.config/nvim/init.lua`.
Restart this Neovim instance after changing the config.

## Wallpaper colors

The local `dotfiles` colorscheme provides fixed, VS Code Dark+–inspired syntax
foreground colors, including Treesitter and LSP semantic highlights. No theme
plugin is required; edit `lua/config/syntax.lua` to customize colors. Wallpaper
colors affect only backgrounds: the editor, tree, tabs, popups, selection, and
related UI surfaces. The top file bar and bottom status bar share the explorer's
background, including mode labels. The active file tab uses the editor background
to distinguish it from inactive tabs. Background shades derive from `base00` in the newest valid
palette from:

- `~/.config/nvim/lua/colors/wal-colors.lua` (linked by `wal-post.sh` to Pywal's cache)
- `~/.config/nvim/lua/colors/matugen-colors.lua` (written by Matugen)

Use your existing wallpaper picker, `set-wallpaper.sh`, or
`set-wallpaper-matugen.sh`; no extra reload hook is needed. Running Neovim
instances check for new colors every second and on focus. `:WallpaperReload`
forces a refresh. `:echo g:wallpaper_palette_file` shows the active source.

Missing palettes use the local scheme's default backgrounds. Incomplete/invalid writes keep
the last good backgrounds. Syntax, normal text, comments, diagnostics, and Git
sign foreground colors stay consistent when the wallpaper changes. This dark
scheme works best with dark Pywal/Matugen palettes. Generated palettes remain
Git-ignored.

## Starter keys

- `Space w`: save
- `Space q`: close the current file tab/buffer (refuses unsaved changes)
- `Space e`: toggle the nvim-tree file explorer
- `Space sv` / `Space sh`: vertical / horizontal split
- `Ctrl-h/j/k/l`: move between windows, including out of the explorer; `Ctrl-k` focuses the file tab bar when there is no window above
- `[b` / `]b`: previous / next buffer
- `Esc`: clear search highlighting in normal mode

## PDFs

Opening a `.pdf` (including from the explorer, Telescope, or `:edit`) launches
it in your default web browser and removes the PDF buffer from Neovim. Your
previous editing buffer is restored when available. This follows the browser
configured in `xdg-settings`, not the system's PDF-viewer association, and
requires `xdg-settings` and `gtk-launch`.

## File explorer

Bare `nvim` starts with the explorer filling the window; opening a file replaces
it with the editor. `Space e` opens/closes the usual sidebar while editing.
When the explorer is the only window, `Space e` keeps it open rather than
revealing an empty `[No Name]` buffer. Repeated presses are safe; no separate
home-page plugin is needed. The sidebar is 26 columns wide, with two-column
indentation, a one-cell left inset, and a one-cell branch/icon gap. There is no
extra sign-column gutter; badges appear after filenames.
The root folder appears at the top. Connected `├─` / `└─` branches lead to
every child folder and file, with vertical lines continuing through nested
folders; dropdown chevrons are hidden. Blue folders, colored file icons,
trailing Git/diagnostic badges, and unsaved-change dots remain. This keeps
nvim-tree, your existing palette, and all explorer behavior.
Git badges use font-independent symbols: `~` unstaged, `+` staged, `!` conflict,
`>` renamed, `?` untracked, `-` deleted, and `.` ignored.
Opening files from the tree or switching files through the top bar leaves the explorer's root,
expanded folders, and selection unchanged. Change the root explicitly with
`H` / `L`; browsing the tree doesn't change `:pwd`. Inside it:

- `l`: expand the selected folder or open a file; on the root row, go down into the folder last visited below it (or its first visible child folder)
- `h`: close the folder, or move to and close its parent; on the root row, go up one directory level
- `Enter`: toggle a folder open/closed, or open a file
- `Shift-l` (`L`): enter the selected folder as the new root, or open a file
- `Shift-h` (`H`): go up to the parent root, collapsing and selecting the folder you just left
- `Ctrl-l`: move from the tree back into the editing window
- `a`: create a file/folder (end the name with `/` for a folder)
- `r`: rename
- `d`: delete (with confirmation)
- `g.`: toggle hidden files
- `gi`: show file info (moved from `Ctrl-k`, which now navigates upward)
- `g?`: show all explorer keybindings

File icons use nvim-web-devicons and require a Nerd Font in your terminal.

Plugins are managed by lazy.nvim (not LazyVim). The first launch needs Git and
internet access to install them. Use `:Lazy` to manage plugins; versions are
recorded in `lazy-lock.json`. Plugins and Mason-installed language servers use
`vim.fn.stdpath("data")` (normally `~/.local/share/nvim`).

## Open file tabs

bufferline.nvim displays open file buffers as tabs across the top. Click a tab
to switch files, or use `Shift-h` / `Shift-l` (previous / next in bar order).
`[b` / `]b` also switch buffers. Click its close icon (or right-click the tab)
to close the buffer; unsaved changes are not discarded. These are file buffers,
not Neovim tabpages (which represent separate window layouts).

`Ctrl-k` moves to the window above, or focuses a one-row overlay on the tab
bar when there is no window above. This is a real focusable window: `h` / `l`
switch files in the editing split you came from, leaving other splits alone.
`Enter`, `Esc`, or `Ctrl-j` close the overlay and return to that split.
`Ctrl-k` while in the overlay stays there. From the full-window explorer,
`Ctrl-k` restores the last editing file when file tabs exist, so `h` / `l` can
switch files and `Enter` returns to the selected file. With no open files, it keeps the explorer; `Space q` does nothing.
`Space q` closes the selected file. Moving to another window dismisses the
overlay too. The underlying native tab bar stays unchanged.

## Bottom status bar and command input

Lualine provides one shared bottom bar across splits, showing mode, Git branch,
relative filename, unsaved status, Git change counts, errors/warnings, and cursor
position. It uses the existing colors, minimal padding, and plain-text symbols.
In the explorer it shows `FILES` and the current root path.

There is no permanently reserved command row (`cmdheight=0`). Native `:` command
input and `/` / `?` searches temporarily cover the bottom row, then the status
bar returns. Pending normal-mode commands also appear in the bar. No Noice or
popup command interface is installed. Messages can temporarily use the same
area; `:messages` shows message history. `cmdheight=0` is still experimental in
Neovim; if it causes display issues, `:set cmdheight=1` restores a separate row.

## Fuzzy finder

Telescope uses a compact dropdown (up to 80 columns / 15 rows) without a preview
pane. It searches from Neovim's current working directory (`:pwd`).

- `Space ff`: fuzzy-find files, including hidden files (respects ignore rules)
- `Space fg`: search project text with ripgrep
- `Space fb`: fuzzy-find open file buffers
- `Space fh`: search Neovim/plugin help

Type to filter, use `Ctrl-j` / `Ctrl-k` or arrow keys to select, `Enter` to open,
and `Esc` to close. `Ctrl-v` / `Ctrl-x` open the result in a vertical / horizontal
split. Searches skip `.git` internals. ripgrep and fd are already installed on
this machine; text search requires ripgrep on other machines.

## Git review

`Space gd` opens one review browser, with this sidebar order:

1. **Unstaged files** (including untracked files)
2. **Staged files**
3. **Most recent commit**, followed by older commits on the current branch

Sections and commits behave like folders. Their files are grouped into directories.
The browser uses ordinary text markers instead of requiring Nerd Font icons.

- `j` / `k`: navigate the sidebar.
- `l`: expand a section, commit, or directory; open a file in the diff area.
- `L`: make the selected section, commit, or directory the browser root; open a file.
- `h`: collapse an expanded folder, or move to and collapse its parent.
- `H`: go up from the current browser root, selecting and collapsing the root just left.
- `Enter`: toggle a folder or open a file.
- `Space e`: focus the review sidebar from either diff pane.
- `s`: stage an unstaged file/directory/section, or unstage a staged one.
- `R`: refresh. The browser also refreshes after writes, on focus, and while active.
- `Older commits...`: load the next page of history with `l` or `Enter`.
- `Space q` or `:q`: exit the entire review and restore the previous editing layout.
- `g?`: show sidebar controls. `[c` / `]c` retain normal diff-hunk navigation.

Unstaged comparisons show index versus working file; staged comparisons show HEAD
versus index; commit comparisons show parent versus commit (the first parent for
merges). Selecting files replaces the current comparison instead of stacking views.
Staging and external Git commits move files down through the sidebar's sections.
History is read-only: browsing never checks out a commit or modifies the working tree.
There is no separate `Space gl` or `Space gq` entry point.

Diffview remains responsible for diff buffers, hunk editing, and its Git integration;
the review sidebar and lifecycle use only public APIs. Normal editor buffers and
unsaved text are preserved. Save pending edits to an index diff buffer before
switching comparisons or closing the review. Existing theme colors are retained.

## Git signs and hunks

Gitsigns marks added, changed, and deleted lines to the right of the line
numbers, directly before the code. The number column has a two-column minimum
and grows automatically for larger line numbers. A one-cell left inset and
number/sign gap provide minimal padding; the sign column also separates the
markers from the code. Relative numbering is retained; the explorer has neither
a number column nor a sign-column gutter.
It works alongside the Git-review browser opened with `Space gd`.
In Git-tracked buffers:

- `[h` / `]h`: previous / next hunk (uses diff navigation in diff windows)
- `Space ghs`: stage / unstage the hunk; also works on a visual selection
- `Space ghr`: reset the hunk or selected lines (discards those working changes)
- `Space ghS`: stage the whole file
- `Space ghU`: unstage the whole file
- `Space ghp`: preview the hunk
- `Space ghb`: show blame for the current line
- `Space ghB`: toggle inline blame
- `ih`: Git hunk text object, e.g. `vih` selects the hunk

Staged hunks have gutter signs too. `Space ghs` prefers staging unstaged changes;
when only staged changes exist at the cursor it unstages them. If staged and
unstaged hunks overlap, `Space ghU` can unstage the whole file instead.

## Treesitter, pairs, and tags

Treesitter installs parsers for the configured programming languages, plus shell,
JSON, YAML, TOML, Markdown, Vim help, XML, diffs, and Git files. It enables
syntax highlighting and query-supported indentation/folding. Folds start open;
use `zc` / `zo` to close/open one, or `zM` / `zR` for all folds. Diffview keeps
its own diff folds. Indentation support is experimental upstream.

This setup uses the current `main` API and requires Neovim 0.12+, a C compiler,
`curl`, `tar`, and tree-sitter CLI 0.26.1+. If the CLI is missing, run
`:MasonInstall tree-sitter-cli` and restart; Mason keeps it isolated in this
config's data directory. Parsers then install automatically (internet required).
Use `:TSUpdate` after updates, or `:TSInstall <language>` for another parser.

mini.pairs automatically closes `()`, `[]`, `{}`, quotes, and backticks in insert
mode. Typing the closing character skips an existing match; Backspace inside an
empty pair removes both characters. Enter advances to the next placeholder
inside an active snippet; otherwise it inserts a newline (not completion
acceptance) and can expand an empty bracket pair onto multiple lines.

nvim-ts-autotag automatically closes HTML/XML/JSX/TSX tags and keeps matching
opening/closing tag names synchronized when renaming. The corresponding parser
must be installed first.

## Brief (`.brf`)

Brief files are detected as `brief` and use local regex-based highlighting for
keywords, types, function names, `:symbol` tags, numbers, strings, characters,
and comments. Capitalized names are treated as nominal types. This uses the
existing syntax palette; no plugin, parser, or language server is required.
Native commenting (`gc`) uses `//`. Rules live in `syntax/brief.vim`, with
file detection in `ftdetect/brief.lua` and comment settings in `ftplugin/brief.vim`.

## Language support and completion

Servers install automatically through Mason in `~/.local/share/nvim/mason`
(with standard XDG defaults). `:Mason` manages them; `:checkhealth vim.lsp` shows
active clients and configuration. Internet access is needed for installation.

| Language | Server |
| --- | --- |
| Lua | lua-language-server (`lua_ls`) |
| C / C++ | clangd |
| CMake | neocmakelsp (`neocmake`) |
| JavaScript / TypeScript, JSX / TSX | typescript-language-server (`ts_ls`) |
| Java | Eclipse JDT LS (`jdtls`) |
| HTML | vscode-html-language-server (`html`) |
| CSS / SCSS / Less | vscode-css-language-server (`cssls`) |
| Rust | rust-analyzer (`rust_analyzer`) |
| Python | Pyright (`pyright`) |

Open a source file in its project to attach the appropriate server. Project
markers such as `package.json`, `Cargo.toml`, `pom.xml`, and `.git` determine the
workspace. Java uses separate, isolated workspace directories per project.

LSP keys (available in attached buffers):

- `gd` / `gD`: definition / declaration
- `gr` / `gi`: references / implementation
- `K`: hover documentation
- `Space rn`: rename symbol
- `Space ca`: code action
- `Space cs`: signature help
- `Space cf`: format using the language server, if it supports formatting
- `Space cd`: show line diagnostics
- `[d` / `]d`: previous / next diagnostic

Completion uses stable blink.cmp with its Lua matcher. In insert mode,
`Ctrl-space` opens completion, `Ctrl-j` / `Ctrl-k` select the next / previous
item (`Ctrl-n` / `Ctrl-p` and arrows also work), and `Tab` accepts. Press `Tab`
again immediately to undo that completion and insert a normal tab using the
current indentation settings. Typing or moving first keeps the completion;
without a completion menu, `Tab` works normally. `Ctrl-y` also accepts, and
`Ctrl-e` hides the menu. In a function completion with snippet placeholders,
`Enter` jumps to the next argument (and finally out of the call). Otherwise,
`Enter` remains a normal newline. This requires the language server to provide
argument placeholders; signature-help text alone is not a snippet. `Shift-Tab`
jumps to the previous placeholder. `Ctrl-k` no longer opens signature help;
use `Space cs` in normal mode instead.
No autoformat-on-save or extra formatter is enabled.

Project/tooling notes:

- Java requires JDK 21+; the existing JDK 21 works. Maven/Gradle wrappers in your
  project are used as needed; this does not install build tools or a debugger.
- Rust needs Cargo and rustc (already installed). Standard-library source is not
  installed here; for full standard-library navigation on this Arch machine,
  install `rust-src` with `sudo pacman -S rust-src`. With rustup-managed Rust,
  use `rustup component add rust-src` instead.
- C/C++ projects get accurate flags and include paths from `compile_commands.json`.
  For CMake, generate it with `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -S . -B build`.
- Python projects should have their dependencies installed in their virtualenv
  (a project-local `.venv` is usually detected automatically).
- JavaScript/TypeScript project dependencies still belong in the project's
  `node_modules`; the editor-installed server does not install those for you.

## Link on another machine

If not already linked by your dotfiles installation:

```sh
ln -s "$HOME/dotfiles/.config/nvim" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
```

Do not replace an existing destination without checking it first.
