# Quickshell migration development shell

A side-by-side replacement for Waybar, SwayNC and the Rofi app/wallpaper
pickers. **Existing autostart, keybindings, services and color pipelines are
unchanged.** No automatic cutover yet.

Tested with Arch Quickshell **0.3.1**, Qt Quick Controls and Python 3.

## Run

From the repository:

```bash
bash .config/quickshell/quickshell-dev/run.sh --preview
```

`--preview` enables notification UI without claiming the notification D-Bus
name; SwayNC still receives all live notifications. Omit it to disable the
notification UI entirely. Add `--no-bar` to test just the pickers/notifications
without a second bar. Stop with Ctrl+C. QML live-reloads.

`run.sh` repairs a stale inherited Hyprland signature only when exactly one
live compositor exists. It does not change your session environment. It also
registers one named, runtime-only `no_anim` rule for the three development picker/
center namespaces. QML animates their cards; Hyprland must not animate the whole
screen-sized input surface a second time. No existing UI namespace or Hyprland
configuration file is changed. Use this wrapper rather than launching `qs` directly.

## Controls

- Clock: left click for applications, right click for wallpapers.
- Arch button: notification center; right click toggles DND. Unread notifications
  add a count badge; opening the center marks history as read. With notification
  UI disabled, both clicks continue to control SwayNC instead.
- Workspace buttons show app icons and activate their workspace.
- Volume: click to mute; scroll for 2% steps. Brightness scrolls in 5% steps.
- Tray: left/right click opens the exported menu when available (including
  nm-applet); middle click uses secondary activation. Items without a menu keep
  their activation action. Menus are themed, with submenus, scrolling, arrows,
  Enter, Escape and outside-click dismissal; no GTK/Qt default menu styling.
- Pickers: type to search, clear-search button, arrows/PageUp/PageDown to select,
  Enter to activate, Escape or an outside click to close. Keyboard navigation
  also works after focusing a picker control. Opening a picker closes tray menus;
  only one exclusive overlay remains, pinned to the monitor where it was opened.
- Wallpapers: click to select/preview, **double-click, Enter, or Apply wallpaper**
  to apply. Hover no longer changes selection. Narrow cards switch to a single
  list; larger compact cards stack the preview. Loading thumbnails have a
  placeholder, and the current wallpaper stays selected after scanning.
- Notification center: clear history, DND, media transport, manual update check
  and updater launch, plus shortcuts to both pickers. No eager network update
  check on startup; refresh polls every five minutes while the center is open.
  History groups by application, with timestamps, collapse/expand, show-older and
  per-application dismissal. Long bodies have Read full message / Show less.
  Default groups show three cards to keep history
  manageable. Both the center and popups sit below reserved bar space; oversized
  popup stacks scroll rather than overflowing the screen.

IPC, using the PID from `qs list --all`:

```bash
qs ipc --pid <pid> call launcher toggle
qs ipc --pid <pid> call wallpaper open
qs ipc --pid <pid> call notifications open
qs ipc --pid <pid> call notifications preview "Test title" "Test body"
qs ipc --pid <pid> call shell close
qs ipc --pid <pid> call shell status
qs ipc --pid <pid> call shell theme
qs ipc --pid <pid> call shell motion
qs ipc --pid <pid> call bar geometry
qs ipc --pid <pid> call tray items
qs ipc --pid <pid> call tray open nm-applet
qs ipc --pid <pid> call tray close
qs ipc --pid <pid> call notifications preview_app Mail "New message" "Preview only"
qs ipc --pid <pid> call notifications group_toggle Mail
qs ipc --pid <pid> call notifications group_expand Mail
qs ipc --pid <pid> call notifications group_dismiss Mail
qs ipc --pid <pid> call wallpaper status
qs ipc --pid <pid> call wallpaper size 340 420 # dev-only narrow-card test
qs ipc --pid <pid> call wallpaper size 820 500 # restore defaults
```

`open` is intentional: Quickshell reserves `show` for IPC introspection.
`notifications preview` is accepted only in preview mode. `search`, `results`
and `activate` are also available on both pickers.

## Components

- `UiState.qml`, `OverlayWindow.qml`, `PickerWindow.qml`: shared routing,
  monitor selection, outside-click/Escape dismissal, search and keyboard UI.
- `Bar.qml`, `BarPill.qml`, `BarLabel.qml`, `BarTooltip.qml`, `TrayMenu.qml`: multi-monitor bar
  with workspaces, clock, themed DBus tray menus, brightness, volume and battery.
  Tray overlays avoid layer-shell/xdg-popup input and resize limitations; each
  menu depth retains its opener so submenu handles stay alive.
- `Launcher.qml`: desktop entries, multi-term search and usage sorting. Reads
  Rofi's frequency cache but writes only its own Quickshell state file.
- `WallpaperPicker.qml`, `wallpaper-scan.py`: large preview, thumbnails and
  current-wallpaper indicator. JSON discovery handles duplicate basenames,
  Unicode, spaces and newlines. Images decode asynchronously at bounded sizes;
  no dependency on or modifications to Rofi's thumbnail cache.
- `NotificationService.qml`, `NotificationBackend.qml`, `NotificationRecord.qml`:
  optional notification server, bounded history/popups, client replacement and
  closure, sticky/transient notifications and record-owned expiration timers.
- `Notifications.qml`, `NotificationCard.qml`, `NotificationGroup.qml`,
  `NotificationGroupData.qml`: grouped history, unread state, timestamps, popups,
  actions and control center. Stable group QObjects keep new records live in
  existing delegates instead of leaving stale groups after a repeated app sends.
- `SystemState.qml`: service adapters.
- `Theme.qml`, `ThemeButton.qml`, `ThemeText.qml`, `ThemeScrollBar.qml`: shared
  wallpaper palette, typography, interaction roles and themed controls.

Wallpaper application still invokes `~/.config/hypr/scripts/set-wallpaper.sh`
with the exact selected path. `WALL_DIR` and `SETTER` can override the defaults.
The existing script starts awww/Pywal asynchronously; the picker reports setter
invocation failures, not the eventual result of its background children.

## Fonts and wallpaper colors

The current wallpaper setter uses **Pywal, not Wallust**. `wal-post.sh` links
`~/.config/waybar/colors/colors.css` to `~/.cache/wal/colors-waybar-custom.css`.
The optional Matugen path writes the same Waybar palette. Quickshell only reads
that output; it never modifies generated files or runs a second color generator.

`Theme.qml` is the single customization point:

- Bar text: **SF Pro Display**, bold, 15px (old Waybar font). Nerd glyphs use
  **JetBrainsMono Nerd Font Propo** separately so fallback metrics cannot distort
  or shift the text. Workspace text/icons are vertically centered in their row.
- Pickers, notifications, menus, controls: **Mononoki Nerd Font Propo**, bold
  (old Rofi/SwayNC/GTK font), rather than Qt's default font.
- Bar hover: `primary_container`; picker/menu selection: `primary` / `on_primary`.
- Notification history: `notificationSurface` / `notificationText`, defaulting
  to a subtle wallpaper-derived panel surface rather than full-accent fills.
- Control backgrounds: `inverse_primary`; control hover:
  `tertiary` at 70% opacity; pressed: `secondary`. Foregrounds select a readable
  palette color when Pywal produces light backgrounds.

Edit the font properties or semantic interaction aliases in `Theme.qml` to
customize all widgets together. For example, making `barHoverBackground` refer
to `secondary` instead of `primaryContainer` still follows every wallpaper.
Text uses native hinted rendering rather than distance-field glyphs.
`ThemeText.qml` binds font fields separately: overriding only a label's size
must not remove its inherited family/weight and fall back to the system font.
`Qt.font()` requires `family`, not `families`; the latter silently selected
FreeSans instead. `shell theme` reports `resolvedFonts` from Qt's actual
`Text.fontInfo`, and verification checks the resolved family/style/size, not
just the requested names. Tested on Qt 6.11.2 (font diagnostics require Qt 6.9+).
CSS `@color` aliases are resolved. File watching plus a two-second recovery poll
handles atomic writes/recreated symlinks; missing files or incomplete core
palettes retain the last valid colors. `QUICKSHELL_PALETTE=/path/to/colors.css`
can override the read-only source for testing or a separate palette.

## UI dimensions and motion

Sizes are logical pixels (monitor scale is applied once): tray/workspace images
**15px**, launcher icons **24px**, control glyphs **16px**, popup application icons
**50px**. `GlyphIcon.qml` centers visible ink, not the font's ascender/line box;
inline bar labels retain actual glyph advances and the SF Pro space width. Tray
slots have **8px** gaps and pills include GTK's **15px padding + 1px border**.
Workspace buttons are **18px** high; active/hover content has **40px minimum width
plus 12px padding**, with matching button margins. Network/Bluetooth tray order
is stable across asynchronous DBus discovery and reloads.

`TrayIcon.qml`/`theme-icon.py` use GTK's logical-size icon lookup before HiDPI
rendering. Qt's larger Papirus variants have extra transparent padding and made
icons visibly too small despite a nominal 15px canvas. Python PyGObject/GTK 3
is needed for exact GTK asset selection; without it the native source remains
available. Third-party pixmap icons are not cropped or artificially enlarged.

- Workspace width/background/text transitions: **300ms CSS ease-in-out**.
- SwayNC-style controls and DND thumb: **200ms CSS ease**. Rofi selections remain
  immediate; no extra hover scale, bounce, or spring is introduced.
- Picker cards: **85% → 100% pop-in** with the inherited Hyprland layer duration/
  curve. Fade and center motion use the inherited layer-fade settings. These
  are read periodically, not hardcoded to a different easing profile. Current
  desktop: 800ms pop-in, 180ms fade.
- Dismissal releases keyboard/pointer input immediately while the card fades;
  rapid reversal uses the current animated value. Moving/scaling a card under
  a stationary cursor cannot change the launcher selection.
- `QUICKSHELL_REDUCED_MOTION=1` disables all these QML transitions. Disabling
  compositor animations is also respected.

`shell motion` reports resolved timings and live surface progress; `bar geometry`
reports actual hit-target/image sizes, asset paths, button widths and animation
state. The accuracy pass was visually reviewed on the unlocked desktop, with
real pointer workspace-hover frames and picker-entry contact sheets in
`/tmp/quickshell-accuracy-review/` (temporary local evidence, not repository files).

## CLI verification

```bash
python3 .config/quickshell/quickshell-dev/verify.py
python3 .config/quickshell/quickshell-dev/verify.py --screenshots /tmp/quickshell-verification
```

The tests launch/stop only their own Quickshell instances. They exercise search,
empty states, overlay routing, a harmless fixture app and its usage history,
a stub wallpaper setter, preview expiration, and the real notification server
on a **private `dbus-run-session` bus**. Notification tests cover requested
millisecond timeouts, replacement, sticky notifications, DND, transients, the
five-popup limit, client close and clear-all. Font and isolated palette tests
cover writes, atomic replacement, recreated symlinks and missing/partial recovery.
Grouping checks exercise live repeated-app updates, unread/read state, the
actual derived header font, collapse/expand, full-message expansion and application
dismissal. Wallpaper
checks exercise compact layout and ensure selecting a preview does not run the
setter. When nm-applet is present, its real menu/submenus are inspected without invoking
network-changing actions. Geometry checks cover icon canvases, GTK variants,
tray spacing and workspace dimensions. Motion checks sample intermediate states,
monotonic progress, exit completion, immediate input release and rapid route
reversal; repeat with `QUICKSHELL_REDUCED_MOTION=1` to check zero-duration behavior.
Runtime warnings fail the tests.
Requires `notify-send`, `gdbus`, `dbus-run-session`; screenshot mode also needs
`grim` and captures your open desktop/apps. Use screenshot mode on an **unlocked
desktop** and visually inspect the results: lock-screen captures do not validate
the widget appearance. No live wallpaper is applied, no
packages are updated, and SwayNC/Waybar are never stopped.

Menu selection screenshots normally use keyboard-navigation IPC (`tray next`).
For actual pointer-hover capture, optionally set `QUICKSHELL_POINTER_CLI` to a
no-argument executable emitting a small real Wayland pointer movement, **without
clicking**. Compositor cursor warps alone do not emit pointer motion. The test
restores the original cursor position afterward.

For live notifications later, explicitly use `QUICKSHELL_NOTIFICATIONS=server`
only after stopping/masking SwayNC. The legacy
`QUICKSHELL_ENABLE_NOTIFICATIONS=1` still works. Do not run two real servers
on the same session bus.

## Remaining before cutover

- Persistent notification history and inline replies are not migrated; bodies
  intentionally render plain text (unsupported markup is not advertised).
- DND/history reset on process restart; tracked notifications survive QML reload.
- Multi-monitor/hotplug and physical small-screen behavior still need testing;
  compact wallpaper-card layout is now covered without changing output settings.
- Existing Hyprland bindings/autostart stay on the old stack until explicit cutover.
