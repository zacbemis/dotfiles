# Desktop tests

The active desktop UI is Quickshell. No test requires Waybar, Rofi or SwayNC.
References to those names in removal guards only assert that retired configs,
commands and theme outputs cannot return. Network/Bluetooth applets, Hyprlock,
Hypridle and wallpaper/color tools are still supported components.

## Unit and headless tests

```bash
python3 -m unittest discover -s tests -v
```

- `test_quickshell_session.py`: daily startup, restart, notification ownership,
  PID/config safety, panel IPC routing, inert command/file indexes and safe markup.
  Session commands are mocked; the real desktop is never stopped.
- `test_quickshell_only.py`: current installer dependencies, Hyprland startup and
  keys, D-Bus activation, supported color outputs and retired-component guards.
  Color hooks run against a temporary HOME and stubbed desktop commands.
- Other `test_quickshell*.py`: real headless QML services, preferences, all supported
  Quickshell renderers, notifications-disabled behavior, connectivity fixtures,
  typography, contrast, input and layout. Optional tools are skipped when absent.
- `test_hyprland.py`: Lua-only compositor loading, used/unique animation curves,
  input/environment cleanup, generated palette recovery and safe lockscreen parsing.
- `test_hyprland_windows.py`: executes the actual Lua window rules against modal,
  file/portal, browser-popup and normal-window fixtures, without a compositor.
- `test_stow.py`: deploys the entire tracked checkout into a temporary HOME, checks
  idempotent Stow/unstow/restow and private-sibling preservation, and excludes
  bytecode, local agent state, tests and maintenance files. Also guards removed artifacts.
- `test_tool_settings.py`: tracked tool config parsing, private-state ignore rules,
  filtered preference capture/restore, credential guards, relative Stow-compatible
  links and safe handling of existing folded directory links.
- Other `test_*.py`: idle brightness, fonts, terminal colors and editor configuration.

## Desktop smoke tests

Run on an unlocked Hyprland session:

```bash
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_features.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_settings.py
# Separate browser popup regression, with a temporary profile and local HTML:
python3 tests/verify_hyprland_windows.py
```

The Quickshell checks launch separate instances, target their own PIDs and use temporary
state, fixture applications and stub wallpaper setters. Notifications use preview
mode or a private D-Bus session, not a replacement for the daily server. Imported
bar/layout alternatives are Quickshell renderers, not legacy desktop programs.
The tests still exercise their UI, fonts, routing and shared services.

The Quickshell smoke tests reject runtime warnings as well as functional failures. On the
current Qt/Wayland stack, rapid panel switches can emit text-input focus warnings
and fail that strict check even when all functional assertions pass. Do not remove
the warning check or treat such a run as a complete pass. Screenshot options capture
your open desktop; inspect those images manually.
