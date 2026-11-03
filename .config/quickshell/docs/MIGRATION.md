# Quickshell desktop session

Quickshell is the sole configured desktop UI. The previous Waybar/SwayNC/Rofi
setup is preserved on `snapshot/pre-quickshell-cleanup-2026-11-03`, not as an
in-session fallback. See [CAPABILITY-AUDIT.md](CAPABILITY-AUDIT.md) for the
historical workflow mapping and deliberate differences.

## Startup and controls

Hyprland's Lua autostart module calls `~/.config/quickshell/desktop.sh start`.
Super+D opens Apps/Run/Files, Super+W opens wallpapers, Super+R restarts
Quickshell, and Super+comma opens Settings. The [shared panel row](NAVIGATION.md)
supports Alt+H/L across Apps/Run/Files/Wallpapers/Settings. Notifications and quick
controls remain separate. Other desktop/hardware bindings are unchanged.

The session helper serializes commands and supervises one daily Quickshell process.
IPC targets its recorded PID, not a comparison instance. Crash recovery is bounded,
and signals check process ownership and PID start times.

```bash
~/.config/quickshell/desktop.sh status
~/.config/quickshell/desktop.sh start       # idempotent, no duplicate bars
~/.config/quickshell/desktop.sh restart
~/.config/quickshell/desktop.sh stop
~/.config/quickshell/desktop.sh launcher
~/.config/quickshell/desktop.sh run
~/.config/quickshell/desktop.sh files
~/.config/quickshell/desktop.sh wallpaper
~/.config/quickshell/desktop.sh notifications
~/.config/quickshell/desktop.sh controls
~/.config/quickshell/desktop.sh settings
```

`activate` remains an alias for checked startup. Startup verifies dependencies,
IPC health and ownership of `org.freedesktop.Notifications`. It never stops or
replaces another notification server; stop that server explicitly first.
A failed startup reports the desktop log rather than launching an alternative UI.
The old saved desktop-mode file is ignored, so it cannot redirect startup or keys.

State/logs: `~/.local/state/quickshell-desktop/`; PID/locks:
`$XDG_RUNTIME_DIR/quickshell-desktop/`. Daily [component preferences](SETTINGS.md)
survive restart; comparison preferences remain transient. Notification history and
DND are in-memory and reset on process restart.

## Removed components and recovery

The legacy configs, install option, layer rules, launcher cache reader, notification
client fallback and generated theme outputs have been removed. Existing packages
and personal caches are not uninstalled or deleted. Hyprlock, Hypridle, awww,
Pywal/Matugen and network/Bluetooth tray applets still support the desktop.

To inspect the old configuration without changing the running desktop:

```bash
git show snapshot/pre-quickshell-cleanup-2026-11-03:.config/waybar/config.jsonc
```

Restoring the old desktop is a deliberate Git/configuration deployment, not a
`desktop.sh legacy` command. Stop Quickshell before starting a different notification
server. Configuration backups from the original migration, if present, remain in
`~/.local/state/dotfiles-quickshell-migration/`.

## Notifications, updates and themes

Daily startup enables notification server mode and a read-only login update check.
Opening panels never runs upgrades; terminal upgrades remain explicit. Restart and
crash recovery suppress repeated login checks. Update polling is demand-driven
while the center/controls are open.

`run.sh` is an isolated development runner with notifications off by default.
`run.sh --preview` / `compare.sh` use synthetic notifications without claiming the
live D-Bus name. Notification-server tests use a private D-Bus session.

Pywal links `~/.config/quickshell/colors.css` to
`~/.cache/wal/colors-quickshell-custom.css`; Matugen writes the same canonical
Quickshell palette. Quickshell watches it read-only, without restart hooks.
Terminal/Neovim/GTK/Hyprlock colors and exact-path wallpaper application remain
unchanged. Local D-Bus notification activation starts the daily session helper.

## Verification and limits

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_features.py
python3 tests/verify_quickshell_settings.py
```

Tests stop only their own instances, never the recorded daily shell. Regressions
cover notification-owner refusal, idempotent startup, stale-mode immunity, inert
Run/file indexes, terminal desktop entries, exact-path opening and safe markup.
Multi-monitor hotplug and every physical device permutation still need manual
validation. On-disk notification history and inline replies are not implemented.
