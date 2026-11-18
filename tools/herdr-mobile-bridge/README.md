# Herdr Mobile Bridge

A Rust plugin for Herdr TUI on Linux. Each detected TUI agent appears as a
separate terminal in the default `herdr-core` session used by the official
Herdr phone app. Launch agents in the TUI as usual. The plugin uses Herdr's
existing socket and your phone's existing SSH connection.

## Set up

Install Herdr TUI 0.9.3 and put `hc` beside the Herdr binary or on the server's
`PATH`. Core 0.1.21 is the tested version. From this directory, build and link
the plugin:

```sh
cargo build --locked --release
herdr --session default plugin link "$PWD"
herdr --session default plugin action invoke sync --plugin herdr-mobile-bridge
```

The final command imports agents already running when the plugin is linked.
Afterward, agent events sync new panes automatically and Herdr's startup hook
runs an initial sync when the TUI server starts. For a named TUI session,
substitute its name for `default` in both Herdr commands. The phone should
connect to the machine's default Core session as the same Unix user.

Open the official phone app and select the SSH host. The Inbox uses the
agent's reported status. A terminal name such as `codex-tui-…` identifies a
bridged pane. Core carries the live terminal and status, while the original
TUI owns the agent and its workspace. The bridge reflows the source text for
the phone and seeds Core scrollback from up to 1,000 rows available in Herdr.
The phone view displays text without the original terminal colors.

Swipe to scroll. The bridge forwards wheel gestures inside the terminal to
the source, including fullscreen agents that manage their own history.
Page Up and Page Down can also be sent from the terminal key bar, subject to
the source application's key bindings. For a longer reply, open Compose
inside the agent's terminal and press Send.

A phone viewer does not take input or resize control. Phone keystrokes request
control briefly and can resize the source pane while typing. If a separate
direct terminal controller already owns the pane, the bridge drops the
conflicting input. Send it again after that controller releases the pane.

## Disable and troubleshoot

```sh
herdr --session default plugin disable herdr-mobile-bridge
herdr --session default plugin log list --plugin herdr-mobile-bridge
```

Disabling the plugin removes the Core entries without stopping the source
agents. To re-enable it, run `plugin enable herdr-mobile-bridge` and the sync
action again. The sync action also republishes missing entries after a manual
Core shutdown. Use `plugin unlink herdr-mobile-bridge` to unregister it.

## Verify

```sh
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
cargo build --release --locked
timeout 90s python3 -u tests/smoke.py
```

The smoke test runs separate Herdr and Core servers under scratch XDG paths
and substitutes local probe processes for agents. It exercises startup and
discovery hooks, the Core list API, OSC 7501 status, preexisting scrollback,
phone-width reflow, split Compose input, alternate-screen wheel input,
controller contention, pane reuse, and cleanup in default and named TUI sessions.

Protocol references [Herdr TUI socket API](https://herdr.dev/tui/docs/socket-api/),
[terminal streams](https://herdr.dev/tui/docs/persistence-remote/),
[Core API](https://github.com/herdrdev/herdr-core/blob/master/schema/README.md),
and [Herdr mobile](https://herdr.dev/mobile/).
