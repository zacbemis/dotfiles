# Hyprland

Lua configuration in `hyprland.lua` and `hyprmodules/`; Hyprlock and Hypridle use `.conf` files.

## Features

- Monitor, workspace, keyboard, mouse and touchpad configuration.
- Tiled browser windows with floating dialogs, portals, picture-in-picture and detached devtools.
- Quickshell startup, launcher bindings and layer rules.
- Wallpaper application with Pywal/Matugen colors and app reloads.
- Hyprlock, idle brightness save/restore and screen-power controls.
- Media/brightness keys and scheduled night light.

**Idle policy:** dim at 150s, lock at 300s, screen off at 330s, suspend at 1800s,
and **shut down at 3600s**. Edit `hypridle.conf` to change this; restart Hypridle afterward.

Edit `hyprmodules/monitors.lua` for your display (default: 2880×1800 at 60 Hz).
`Super+F` toggles floating manually.

## Validate

```bash
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua
hyprctl configerrors
```

Reviewed against Hyprland 0.56.2. See [tests](../../tests/README.md) for offline and live checks.
