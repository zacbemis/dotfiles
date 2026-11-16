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
- Git review includes staged/unstaged files, local/fetched remote branches and flat merge history without checkout.
- Fixed VS Code–inspired syntax colors with live Pywal/Matugen backgrounds.
- PDFs open in the default browser.

## Main keys

| Key | Action |
| --- | --- |
| `Space w` / `Space q` | Save / close file or review tab; protect unsaved changes |
| `Space e` | Toggle explorer or review sidebar |
| `Space k` | Focus file-tab navigation; `h` / `l` switch files |
| `Ctrl-h/j/k/l` | Move between windows |
| `Space ff` / `Space fg` | Find files / search text |
| `Space gd` | Open Git review |
| `gd` / `gr` / `K` | Definition / references / hover |
| `Space rn` / `Space ca` / `Space cf` | Rename / code action / format |
| `Tab` / `Enter` | Accept completion / advance snippet or insert newline |
| `g?` | Explorer/review help |

Interactive `:q` / `:quit` quits **all** windows and tabs, protecting unsaved buffers.
`:q!` discards unsaved changes across the application.

## Requirements

Neovim 0.12+, Git, a C compiler, curl, tar, ripgrep, a Nerd Font and tree-sitter CLI 0.26.1+.
First launch downloads plugins, parsers and language servers; use `:Lazy` and `:Mason` to manage them.
If tree-sitter CLI is missing, run `:MasonInstall tree-sitter-cli` and restart.
Language runtimes and project dependencies are installed separately; Java requires JDK 21+.
