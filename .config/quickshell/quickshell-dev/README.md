# Quickshell development shell

This is a development-only Quickshell configuration. It is kept separate from
the default Quickshell configuration and is not started by Hyprland yet.

The initial shell renders a small bottom panel on every detected monitor. It
intentionally does not start a notification server, launcher, or any other
component that would conflict with the existing Waybar, SwayNC, or Rofi setup.

## Run directly from the repository

From the dotfiles repository:

```bash
qs -p .config/quickshell/quickshell-dev/shell.qml
```

Use `quickshell` instead of `qs` if that is the executable provided by your
package. Quickshell live-reloads QML files while it is running; press `Ctrl+C`
to stop it.

## Run as a named configuration

After this directory is available below `~/.config/quickshell/`, run:

```bash
qs -c quickshell-dev
```

The existing Waybar, SwayNC, and Rofi configuration is intentionally
unchanged. Do not add this shell to Hyprland autostart until it is ready to
replace the corresponding components.
