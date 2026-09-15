# Quickshell migration development shell

This config is a side-by-side replacement for the current Waybar, SwayNC, and
Rofi setup. Hyprland autostart and keybindings remain unchanged, so the old
stack is still the fallback.

## Components

- `Bar.qml` — top bar with workspaces, clock, tray, brightness, volume, and battery
- `Launcher.qml` — Rofi-like application launcher
- `WallpaperPicker.qml` — wallpaper list with previews, using the existing wallpaper setter
- `Notifications.qml` — SwayNC-like popups and control center
- `SystemState.qml` — PipeWire, UPower, brightness, and update polling
- `Theme.qml` — read-only adapter for the generated Waybar palette with fallbacks

## Run

From the repository:

```bash
qs -p .config/quickshell/quickshell-dev/shell.qml
```

Quickshell live-reloads QML files. Use `Ctrl+C` to stop it. The launcher and
wallpaper picker can be opened from another terminal while the shell is
running:

```bash
qs ipc --pid <quickshell-pid> call launcher toggle
qs ipc --pid <quickshell-pid> call wallpaper toggle
```

Notifications are disabled by default so SwayNC can continue running. To test
Quickshell notifications, temporarily mask the SwayNC user service first:

```bash
systemctl --user mask --runtime --now swaync.service
QUICKSHELL_ENABLE_NOTIFICATIONS=1 qs -p .config/quickshell/quickshell-dev/shell.qml
notify-send "Quickshell test" "Notification body"
```

Only one process can own `org.freedesktop.Notifications`. Restore SwayNC after
testing with:

```bash
systemctl --user unmask --runtime swaync.service
systemctl --user start swaync.service
```

Do not add this shell to Hyprland autostart or change the existing keybindings
until the replacement is ready.
