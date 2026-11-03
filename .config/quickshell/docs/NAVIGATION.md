# Shared panel navigation

Super+D opens the tabbed panel:

**Apps · Run · Files · Wallpapers · Settings**

- **Alt+H / Alt+L** selects the previous/next tab, wrapping at either end.
- The same row remains available on every tab, including every launcher and
  wallpaper renderer. Clicks use the same navigation controller as the shortcuts.
- Shortcuts work with search fields, lists or buttons focused, without inserting
  H/L into the query. They are inactive when the tabbed panel is closed.
- The launcher also retains Ctrl+Tab / Ctrl+Shift+Tab and Shift+Left/Right tab
  switching. Settings' Ctrl+Tab still changes its internal component category.
- Apps/Run/Files change the launcher mode; selecting Wallpapers or Settings changes
  the panel page. Nothing launches or applies simply by switching tabs.
- Notifications and quick controls remain separate surfaces, **not new tabs**.
  The OSD and tray menus remain their existing passive/transient surfaces.

## Stable frame

All five tabs use the same centered **720×420 logical-pixel** frame from
`services/UiState.qml`, bounded by the opening monitor. One persistent native
`components/NavigationWindow.qml` owns the backdrop, blur surface, common frame and
`PanelTabs.qml` row. Tabbed `OverlayWindow` instances supply visually reparented
page content only; their own native windows never map. There is no overlapping
scrim/blur or exit/entrance fade at a tab boundary, so the background stays steady.
Only opening/closing the whole panel animates. `renderVisible` controls page models
and images so hidden pages still release resources. Search-result counts do not
resize the launcher. Switching tabs does not rerun
the opening scale animation, and the opening monitor remains pinned. On narrow
outputs, the row scrolls to reveal the selected tab.

Wallpaper/Settings comparison-only sizing hooks can still override a test
instance's frame; normal daily navigation always uses the shared defaults.
Wallpaper selection remains preview-only until Set wallpaper, Enter or double-click.
Saved component choices, fonts, palette generation and notification ownership are
unchanged. Super+comma still toggles Settings directly, now with the same tab row.

## Diagnostics / verification

PID-targeted IPC (the daily PID comes from `desktop.sh status`):

```bash
qs ipc --pid "$pid" call navigation select settings
qs ipc --pid "$pid" call navigation next
qs ipc --pid "$pid" call navigation previous
qs ipc --pid "$pid" call navigation status
qs ipc --pid "$pid" call shell motion
```

Only the five tab keys above are accepted; next/previous do nothing when closed.
`navigation status` exposes current tab/order, and `shell motion` includes each
surface's navigation flag and actual frame geometry, plus the shared host's
visibility, opacity and backdrop opacity.

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell_navigation.py
QUICKSHELL_REDUCED_MOTION=1 python3 tests/verify_quickshell_navigation.py
```

The Qt test sends real Alt+H/L events with text/button focus. Preview integration
checks controller routing, five visible tabs in all renderers, both wrap directions,
fixed geometry across tabs/query modes, exclusive input, monitor pinning and unchanged
live notification ownership. It also verifies one unchanged native layer address and
constant backdrop opacity throughout tab transitions, with no per-page blur layers. It stops only its own shell process.
