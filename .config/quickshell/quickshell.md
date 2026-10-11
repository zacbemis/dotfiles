# Quickshell migration notes

- Development config lives in `.config/quickshell/quickshell-dev/`; it is intentionally not started by Hyprland yet.
- Run from this repository with `bash .config/quickshell/quickshell-dev/run.sh --preview`. Tested with Quickshell 0.3.1; QML live-reloads. See `quickshell-dev/README.md` for controls and CLI verification.
- Existing `.config/waybar/`, `.config/swaync/`, `.config/rofi/`, Hyprland autostart, and keybindings are the fallback and must remain unchanged until cutover.
- Reproduce the current UI in QML: Waybar bar/modules, SwayNC popups/control center, and Rofi app/wallpaper pickers. Existing shell helpers may be reused where practical.
- SwayNC and a Quickshell notification server cannot own the same session bus name. Preview mode renders the native UI without a server; `verify.py` tests the real backend on a private D-Bus bus without stopping SwayNC.
- Current wallpaper startup/keybindings use Pywal (`wal`), not Wallust; Matugen exists as a separate, mostly manual path. Do not change either color pipeline during initial UI work.
- Keep Quickshell-specific state inside this development config; `Theme.qml` only reads the generated Waybar palette and never overwrites it. Fonts and hover/selection roles are centralized there; color changes recover from atomic writes and recreated symlinks.
- Tray left/right click prioritizes exported DBus menus, including nm-applet. `TrayMenu.qml` renders themed menus/submenus in an input-capable overlay instead of an unreliable native layer-shell popup.
- Shared overlays coordinate keyboard focus/monitor selection across both pickers, tray menus and the notification center. Wallpapers have a large preview, exact-path discovery, explicit apply controls and a compact layout; moving across results does not change the selection.
- Notification history now groups by application with collapse/show-older/group dismissal, timestamps and unread/read state. Center/popups respect reserved bar space; calmer card colors and font-field bindings avoid overpowering fills and fallback-font regressions. History remains in-memory.
- Run `python3 .config/quickshell/quickshell-dev/verify.py --screenshots /tmp/quickshell-verification` for fixture-safe application/wallpaper tests, notification lifecycle tests, runtime logs and `grim` screenshots. Physical multi-monitor/hotplug and manual keyboard testing are still needed before cutover.
