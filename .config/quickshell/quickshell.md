# Quickshell migration notes

- Development config lives in `.config/quickshell/quickshell-dev/`; it is intentionally not started by Hyprland yet.
- Run from this repository with `qs -p .config/quickshell/quickshell-dev/shell.qml` after installing `quickshell` (`sudo pacman -Syu quickshell`). Quickshell live-reloads QML.
- Existing `.config/waybar/`, `.config/swaync/`, `.config/rofi/`, Hyprland autostart, and keybindings are the fallback and must remain unchanged until cutover.
- Reproduce the current UI in QML: Waybar bar/modules, SwayNC popups/control center, and Rofi app/wallpaper pickers. Existing shell helpers may be reused where practical.
- SwayNC and a Quickshell notification server cannot run together; defer enabling the latter until notification UI testing.
- Current wallpaper startup/keybindings use Pywal (`wal`); Matugen exists as a separate, mostly manual path. Do not change either color pipeline during initial UI work.
- Keep Quickshell-specific state inside this development config; `Theme.qml` only reads the generated Waybar palette and never overwrites it.
- Test with screenshots/logs and manual interaction. Quickshell is available locally; verify with `qs --version`.
