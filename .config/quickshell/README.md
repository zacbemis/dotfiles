# Quickshell

Desktop shell for Hyprland, with shared Pywal/Matugen colors and SF Pro typography.

## Features

- Multi-monitor bar with workspaces, app icons, clock, tray and configurable status indicators.
- Apps, commands, files and wallpaper pickers with search and keyboard navigation.
- Wallpaper previews with explicit apply; integrates with the existing wallpaper scripts.
- Notification popups, grouped history, unread counts, actions and Do Not Disturb.
- Media controls, update checks and explicit updater launch; no automatic upgrades.
- Native Wi-Fi, VPN and Bluetooth pages with private password/pairing prompts.
- Output/microphone routing, application mixer and Bluetooth audio profiles.
- Volume/brightness controls, OSD and an idle-only Caffeine inhibitor.
- Persistent component choices for bars, launchers, wallpapers, notifications, controls and OSD.
- Isolated previews and imported layout comparisons without changing daily preferences.
- Checked single-instance startup that refuses to replace another notification server.

## Use

- `Super+D`: launcher; `Alt+H/L` switches panel tabs.
- `Super+W`: wallpapers.
- `Super+,`: component settings.
- `Super+R`: restart shell.
- Bar gear: quick settings; Arch button: notifications, right-click for DND.

```bash
~/.config/quickshell/desktop.sh start
~/.config/quickshell/desktop.sh status
~/.config/quickshell/desktop.sh restart
```

Notification history and DND reset on process restart; inline replies are not supported.

## Development

From the repository root:

```bash
bash .config/quickshell/run.sh --preview
bash .config/quickshell/compare.sh enzo
```

Previews do not claim the notification D-Bus name. Tested with Quickshell 0.3.1, Qt Quick Controls and Python 3.
See [session recovery](docs/MIGRATION.md), [connectivity](docs/CONNECTIVITY.md),
[settings](docs/SETTINGS.md), [theme](docs/CONTRAST.md) and [tests](../../tests/README.md).
