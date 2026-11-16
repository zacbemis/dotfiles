# herdr-control

Small synchronous Rust client for the gaps in Herdr 0.8's keybinding API.
No daemon, async runtime, scripting runtime, or build-on-keypress wrapper.

## Install

Requires Linux/macOS, Rust/Cargo 1.89+, and a running Herdr with the
`session.snapshot`, `tab.create`, `tab.move`, `tab.focus`, and `workspace.move`
socket methods (verified against Herdr 0.8.0).

From the dotfiles repository root:

```sh
cargo install --path tools/herdr-control --locked --root "$HOME/.local" --force
```

This builds a release binary at `~/.local/bin/herdr-control`. Repeat after source
changes. The tool-settings linker deploys preferences, not compiled binaries;
install this tool before enabling its keybindings on another machine.

The managed `.config/herdr/config.toml` invokes that absolute location:

| Shortcut | Command | Behavior |
| --- | --- | --- |
| Alt+Shift+H | `tab-left` | Move the active tab one position left |
| Alt+Shift+L | `tab-right` | Move the active tab one position right |
| Alt+Shift+J | `workspace-down` | Move the active workspace one position down |
| Alt+Shift+K | `workspace-up` | Move the active workspace one position up |
| Alt+N | `new-tab` | Create and focus a tab immediately after the active tab |

Reordering stops at the edges, preserves focus, and never moves a tab to a
different workspace. `new-tab` uses Herdr's configured shell and CWD policy. It
creates in the background, moves if necessary, then focuses the new tab to avoid
briefly showing it at the end of the bar.

**Adjacent creation applies to Alt+N only.** Menu/CLI-created tabs retain Herdr's
native placement. Making this universal requires native Herdr support.

## Design

- `src/client.rs`: bounded, timed, newline-delimited JSON exchanges over
  `HERDR_SOCKET_PATH`; validates response IDs, errors, and typed results.
- `src/actions.rs`: typed snapshots and ordering policy. Herdr's `insert_index`
  describes a gap *before* removing the source, so moving forward skips two gaps.
- `src/main.rs`: command parsing and useful nonzero errors on stderr.

The helper uses `HERDR_ACTIVE_TAB_ID` / `HERDR_ACTIVE_WORKSPACE_ID` from custom
command context, otherwise the live focused IDs. It does not use the inherited
shell's `HERDR_TAB_ID` / `HERDR_WORKSPACE_ID`, or guess another session's socket.
A per-socket advisory file lock serializes helper invocations across the whole
snapshot/create/move/focus operation. It does not serialize mouse actions or
other API clients, so this is not a server-side transaction. API failures stop
subsequent requests; a failure after creation may leave an unfocused new tab.
The empty `<socket>.herdr-control.lock` file is local runtime state, not a source
file, and should not be deleted while commands are running.

Architecture informed by the separate Rust socket client in
[pdjsh/herdr-plugins](https://github.com/pdjsh/herdr-plugins). This tool deliberately
has no interactive picker or plugin framework.

## Test

```sh
cargo test --manifest-path tools/herdr-control/Cargo.toml --locked
cargo clippy --manifest-path tools/herdr-control/Cargo.toml --locked --all-targets -- -D warnings
```

Unit tests verify insertion indices by applying Herdr's removal/insertion
semantics. Integration tests execute the actual binary against isolated fake Unix
sockets, checking every request, keypress context, boundaries, creation/focus
ordering, malformed responses, API failures, and argument errors. They never
modify a live Herdr session.
