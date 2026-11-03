# Quickshell desktop shell

The daily replacement for the configured Waybar, SwayNC and Rofi workflows.
Hyprland startup and Super+D/W/R use the checked session helper. The old stack
is retained as an inactive rollback option; wallpaper/color generators and
non-UI desktop bindings stay in place. See [docs/CAPABILITY-AUDIT.md](docs/CAPABILITY-AUDIT.md).

Tested with Arch Quickshell **0.3.1**, Qt Quick Controls and Python 3.
See [docs/RESEARCH.md](docs/RESEARCH.md) for the architecture review, upstream
source references (Caelestia/DankMaterialShell), decisions and remaining limits.
Cutover constraints are in [docs/MIGRATION.md](docs/MIGRATION.md).

## Daily session and rollback

```bash
~/.config/quickshell/desktop.sh start       # idempotent daily server
~/.config/quickshell/desktop.sh status
~/.config/quickshell/desktop.sh activate    # checked handoff / return from legacy
~/.config/quickshell/desktop.sh legacy      # rollback to retained old stack
```

See [docs/MIGRATION.md](docs/MIGRATION.md) for ownership checks, logs and backups.

## Panel navigation

Super+D opens **Apps · Run · Files · Wallpapers · Settings**. Use **Alt+H / Alt+L**
to move left/right (with wrap), or click a tab. The row stays visible on every page;
all pages and renderer alternatives share a centered 720×420 frame. Notifications
and quick controls remain separate, not additional tabs. See
[docs/NAVIGATION.md](docs/NAVIGATION.md).

## Network and Bluetooth

The bar gear's Network/Bluetooth buttons and either click on their tray icons open
the same native connection pages. Network has **Wi-Fi · VPN** sub-tabs, including
saved VPN/WireGuard connections and explicit Add/Configure actions through the
standard NetworkManager editor. Radio controls, private password/pairing prompts
and explicit reload replace the old tray-only delegation. Compact radio pills and
selectable rows keep the panels quiet; connection actions appear only on selection,
with less-common actions under Options. The bottom-right icon reloads the list.
There is no favourites button; footer settings links handle saved/out-of-range
profiles and detailed edits. Wi-Fi retains password retry and captive-portal status.
Bluetooth retains rename/unblock; its footer speaker icon (also in Quick settings'
header) opens output/microphone routing and available headphone/headset modes. Opening does not change a connection,
audio route or radio, or start a scan/probe. See [docs/CONNECTIVITY.md](docs/CONNECTIVITY.md)
for supported actions, privacy and read-only/fixture verification.

## Customize components

The desktop bar's **gear** opens Quick settings. For component customization, use
the panel's **Settings** tab, **Super+,**, the gear inside Quick settings, or run:

```bash
~/.config/quickshell/desktop.sh settings
```

The categorized selector switches bars, launchers, wallpaper pickers, notification
views, controls and OSD independently, with labeled choice cards and live previews.
Daily choices save automatically and survive restart. Optional Classic / MM-style /
Grid + gallery presets change all six components; wallpaper colors and SF typography
remain shared defaults. Comparison/isolated preview choices never touch daily
preferences. **Settings → Bar indicators** independently chooses Icon + %, Icon
only, % only or Hidden for sound, brightness and battery. Level-aware vector icons
and exact tooltips make permanent percentages optional; OSD remains independent.
See [docs/INDICATORS.md](docs/INDICATORS.md) for icon behavior/research and
[docs/SETTINGS.md](docs/SETTINGS.md) for saving and IPC.

## Isolated development / comparison

From the repository (does not replace the daily shell):

```bash
bash .config/quickshell/run.sh --preview
```

`--preview` enables notification UI without claiming the notification D-Bus
name; SwayNC still receives all live notifications. Omit it to disable the
notification UI entirely. Add `--no-bar` to test just the pickers/notifications
without a second bar. Stop with Ctrl+C. QML live-reloads.

`run.sh` repairs a stale inherited Hyprland signature only when exactly one
live compositor exists. It does not change your session environment. It also
registers one named, runtime-only `no_anim` rule for the picker, center, controls
and settings namespaces. QML animates their cards; Hyprland must not animate the whole
screen-sized input surface a second time. No existing UI namespace or Hyprland
configuration file is changed. Use this wrapper rather than launching `qs` directly.

## Compare imported dotfile layouts

```bash
bash .config/quickshell/compare.sh list
bash .config/quickshell/compare.sh enzo
```

The small bottom-right toolbar switches **Current**, **Enzo**, and **MM-2103**
bars. Its gear opens the same independent component selector as daily mode;
notification/OSD buttons provide synthetic samples. No comparison choice is
persisted. See [docs/DESIGN.md](docs/DESIGN.md) for the compact presentation rules.

These are MIT renderer ports over shared services and the existing wallpaper
pipeline, not complete upstream installations. Comparison always uses preview
notifications and never installs/autostarts another shell. See
[docs/FEATURE-COMPARISON.md](docs/FEATURE-COMPARISON.md) for controls and exact
supported behavior, [docs/COMPARISON.md](docs/COMPARISON.md) for bars, and
[docs/FEATURE-ALTERNATIVES.md](docs/FEATURE-ALTERNATIVES.md) for broader research.

## Controls

- Clock: display-only; hover for the full weekday/date/year. No click actions.
- Arch button: notification center; right click toggles DND. Unread notifications
  add a count badge; opening the center marks history as read. With notification
  UI disabled, both clicks continue to control SwayNC instead.
- Workspace buttons show app icons and activate their workspace.
- Volume: click to open/close Sound, with output/microphone volume and mute,
  device dropdowns and an Applications mixer. Scroll still adjusts in 2% steps.
  Brightness scrolls in 5% steps.
  Automatic idle dim/restore updates the bar quietly; only non-idle brightness
  changes show the brightness OSD. Manual volume feedback is unaffected.
- Tray: Wi-Fi/Bluetooth left- and right-click open the same native connection page.
  Network includes Wi-Fi and VPN controls. Other items open their exported menu when available;
  middle click uses secondary activation. Items without a menu keep
  their activation action. Menus are themed, with submenus, scrolling, arrows,
  Enter, Escape and outside-click dismissal; no GTK/Qt default menu styling.
- Launcher: Apps / Run / Files / Wallpapers tabs; `>` enters a command, absolute
  or `~/` paths browse files. PATH/run history and directory indexes never execute
  on typing. Enter opens a file, enters a folder or explicitly runs a command.
  Terminal desktop entries use Kitty; existing Rofi usage is read-only.
- Pickers: type to search, Ctrl+A/Backspace to clear, arrows/PageUp/PageDown to select,
  Enter to activate, Escape or an outside click to close. Keyboard navigation
  also works after focusing a picker control. Opening a picker closes tray menus;
  only one exclusive overlay remains, pinned to the monitor where it was opened.
- Wallpapers: click to select/preview, **double-click, Enter, or Set wallpaper**
  to apply. Hover no longer changes selection. Narrow cards switch to a single
  list; larger compact cards stack the preview. Loading thumbnails have a
  placeholder, and the current wallpaper stays selected after scanning.
- Notification center: clear history, DND, selectable-player media transport, manual update check
  and updater launch, plus shortcuts to both pickers. Daily startup performs the
  old read-only login check; isolated tests/comparison do not. Refresh polls every
  five minutes while the center/controls are open. No upgrades run automatically.
  History groups by application, with timestamps, collapse/expand, show-older and
  per-application dismissal. Long bodies have More / Less; dismiss controls appear on hover or keyboard focus.
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
qs ipc --pid <pid> call connectivity open vpn
qs ipc --pid <pid> call tray menu nm-applet # explicit legacy menu diagnostics
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

## Layout

```text
.config/quickshell/
├── shell.qml                 # composition root and shell IPC
├── run.sh                    # safe development-session wrapper
├── compare.sh                # preview-only live layout comparison
├── components/               # shared controls, overlays and ThemeTooltip
├── theme/                    # Theme.qml roles + ColorMath.js contrast/tone math
├── services/                 # shared state and system integrations
├── modules/
│   ├── bar/                  # per-monitor bar, workspace and tray UI
│   ├── comparison/           # adapted Enzo / MM bars and independent feature choices
│   ├── settings/             # categorized, persistent daily component selector
│   ├── controls/             # compact/tile quick settings
│   ├── osd/                  # passive horizontal/vertical OSD
│   ├── launcher/             # application picker
│   ├── wallpaper/            # wallpaper picker and preview
│   └── notifications/        # center, groups and popup cards
├── scripts/                  # Python update, wallpaper and GTK icon helpers
├── vendor/                   # pinned, unmodified upstream sources + licenses
└── docs/                     # migration notes, research and comparison guide

tests/                        # repository-level tests, not deployed config
├── test_quickshell.py        # offline/headless service regressions
├── test_quickshell_contrast.py # wallpaper tones + actual Qt state/contrast checks
├── test_quickshell_scroll.py # real Qt mouse/touchpad events over clickable slides
├── verify_quickshell.py      # desktop/private-bus integration checks
├── verify_quickshell_profiles.py # imported-bar lifecycle checks
└── verify_quickshell_features.py # feature renderers, shared data/actions and OSD
```

Use root-relative `qs.services`, `qs.theme` and `qs.components` imports;
feature-local QML types resolve within their module. Shared components must not
import feature modules. Helper paths use `Quickshell.shellPath("scripts/…")`,
independent of the caller's directory. The old `quickshell-dev/` directory is
removed; restart any preview launched from that path using the command above.
Development layer namespaces remain unchanged to avoid interfering with the
existing desktop stack.

## Components

- `services/UiState.qml`, `components/OverlayWindow.qml`, `components/PickerWindow.qml`:
  shared routing, monitor selection, outside-click/Escape dismissal, search and
  keyboard UI.
- `modules/bar/`: multi-monitor workspaces, clock, themed DBus tray menus,
  brightness, volume and battery. Tray overlays avoid layer-shell/xdg-popup input
  and resize limitations; each menu depth retains its opener so submenu handles
  stay alive. `components/ThemeTooltip.qml` is shared by bar and general controls.
- `modules/launcher/`: desktop entries, multi-term search and usage sorting.
  Reads Rofi's frequency cache but writes only its own Quickshell state file.
- `modules/wallpaper/`, `scripts/wallpaper-scan.py`: bounded asynchronous previews
  and thumbnails, current-wallpaper indication, and exact JSON discovery of
  duplicate basenames, Unicode, spaces and newlines. No Rofi cache modifications;
  hidden pickers release thumbnail delegates and the preview source after exit.
- `services/Notification{Service,Backend,Record,GroupData}.qml`: optional server,
  bounded history/popups, client replacement/closure, sticky/transient records,
  expiration timers and stable group QObjects.
- `modules/notifications/`: grouped history, unread state, timestamps, popups,
  actions and control center. Stable service-owned groups keep delegates live
  when another notification arrives from an existing application.
- `services/SystemState.qml`: native PipeWire/UPower adapters and bar-facing state.
- `services/BrightnessService.qml`: asynchronous one-second sysfs reads without
  command spawning, discovery every 30 seconds while unavailable, and serialized/
  coalesced adjustments. Controls panel backlights, never keyboard LEDs.
- `services/MotionService.qml`: config-reload refreshes with a one-minute fallback.
- `services/UpdateService.qml`, `scripts/check-updates.py`: structured,
  timeout-bounded checks with explicit errors and the last successful count.
  Empty `yay -Qua` exit 1 is a successful zero count only without diagnostics;
  reload visibly shows Checking… then Up to date/count or Check failed.
  The notification center owns periodic polling demand.
- `services/CaffeineService.qml`, `scripts/caffeine.py`: Quick settings' Caffeine
  button owns one logind **idle-only** inhibitor, respected by hypridle. It pauses
  automatic dim/lock/DPMS/suspend/shutdown timers without stopping hypridle or
  blocking explicit lock/suspend/lid/shutdown actions. Default off, not persisted;
  disabling/exiting releases its own descriptor. Comparison toggles simulate only.
- `theme/Theme.qml`, `components/Theme*.qml`: shared wallpaper palette,
  typography, interaction roles and themed controls.

Wallpaper application still invokes `~/.config/hypr/scripts/set-wallpaper.sh`
with the exact selected path. `WALL_DIR` and `SETTER` can override the defaults.
The existing script starts awww/Pywal asynchronously; the picker reports setter
invocation failures, not the eventual result of its background children.

## Fonts and wallpaper colors

The current wallpaper setter uses **Pywal, not Wallust**. `wal-post.sh` links
`~/.config/quickshell/colors.css` to `~/.cache/wal/colors-waybar-custom.css`.
The optional Matugen path writes the same canonical Quickshell palette. Quickshell only reads
that output; it never modifies generated files or runs a second color generator.

`theme/Theme.qml` is the single customization point:

- Titles: **SF Pro Display Bold** for picker/panel headings, notification
  summaries and application-group headings.
- Primary display text: **SF Pro Display Regular** for app names, wallpaper captions,
  media titles, prominent values and comparison-bar text. The original bar keeps
  its 15px SF metrics with bold status/workspace/clock text; glyphs remain separate Nerd Font text.
- Primary interface labels: **SF Pro Display Regular** for buttons, quick-setting
  tiles, navigation, menus, search input, slider/control labels and app labels.
  Using SF does not imply using bold; normal controls remain regular-weight.
- Supporting text: `Theme.bodyFontFamily`, now also **SF Pro Display Regular**,
  for descriptions, bodies, subtitles, timestamps, placeholders, tooltips and hints.
- `ThemeText` and `ThemeButton` default to the primary SF `label` role. Every
  runtime `ThemeText` declares its role explicitly, including `body` for supporting
  copy. Both use `Theme.fontForRole()`; `Theme.fontFamily` / `uiFont` mean SF,
  not the supporting font. Other roles are `title`, `display`, `bar`, `menu`,
  `tooltip` and `icon`. Ubuntu text faces and the unused monospace role are removed
  from Quickshell; terminal fonts are unchanged. See [docs/TYPOGRAPHY.md](docs/TYPOGRAPHY.md).
  Size overrides retain the selected face; use `font.weight`
  for explicit weight overrides without losing the family.
  Icons use a separate Symbols Nerd Font face (the original bar retains its
  JetBrains Nerd glyphs), never the proportional UI font. Imported comparisons use these
  same roles instead of upstream `sans-serif`/`monospace` defaults.
- Wallpaper accents remain the extracted `primary`, `secondary` and `tertiary`.
  Text uses their contrast-corrected `*Ink` roles instead of treating a fill color
  as universally readable text. See [docs/CONTRAST.md](docs/CONTRAST.md).
- Panel/card/raised surfaces form a restrained tonal ladder from the wallpaper
  background and generated surface colors, not full-strength outline colors.
- Primary text targets **7:1**, falling back to **4.5:1** on middle-tone palettes;
  supporting text targets **4.5:1** on all ordinary surfaces. Disabled content
  remains quieter but readable at **3:1**, without extra opacity reductions.
- Picker/menu selection and active toggles use corrected wallpaper accent fills
  with matching foregrounds; hover/press states use accent-tinted surfaces.
  Foregrounds follow the actual animated background. Controls have opaque
  backplates; panels use 98% opacity, or become opaque near contrast-sensitive
  middle gray. This avoids unpredictable wallpaper/window bleed-through.
- Notification history uses `notificationSurface` / `notificationText`. Focus
  rings, outlines and slider fill/track pairs have explicit contrast roles.

Edit the font properties or semantic interaction aliases in `theme/Theme.qml` to
customize all widgets together. For example, making `barHoverBackground` refer
to `secondary` instead of `primaryContainer` still follows every wallpaper.
Text uses native hinted rendering rather than distance-field glyphs.
`ThemeText.qml` / `ThemeButton.qml` bind font fields separately: overriding only
size or weight must not drop the role's family and fall back to the system font.
`tests/test_quickshell_typography.py` verifies real Qt face selection, smaller
SF titles, large display text, supporting text and live role changes headlessly.
`Qt.font()` requires `family`, not `families`; the latter silently selected
FreeSans instead. `shell theme` reports `resolvedFonts` from Qt's actual
`Text.fontInfo`. In addition, `bar geometry` and feature `status` include `fonts`
from the actual rendered item tree. Tests inspect every visible clock, workspace,
status, control, heading and supporting label, not just separate font probes. Tested on Qt 6.11.2 (font diagnostics require Qt 6.9+).
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

`modules/bar/TrayIcon.qml`/`scripts/theme-icon.py` use GTK's logical-size icon lookup before HiDPI
rendering. Qt's larger Papirus variants have extra transparent padding and made
icons visibly too small despite a nominal 15px canvas. Python PyGObject/GTK 3
is needed for exact GTK asset selection; without it the native source remains
available. Third-party pixmap icons are not cropped or artificially enlarged.

- Workspace width/background transitions: **300ms CSS ease-in-out**. Text follows
  each animated background frame directly to avoid low-contrast interpolation.
- SwayNC-style controls and DND thumb: **200ms CSS ease**. Rofi selections remain
  immediate; no extra hover scale, bounce, or spring is introduced.
- Picker cards: **85% → 100% pop-in** with the inherited Hyprland layer duration/
  curve. Fade and center motion use the inherited layer-fade settings. These
  refresh on config reload, with a one-minute recovery poll, not a different
  hardcoded easing profile. Current
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
# Offline helper/headless service tests; no compositor required:
python3 -m unittest discover -s tests -p 'test_quickshell*.py' -v
# Desktop integration (requires a running Hyprland session):
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_features.py
python3 tests/verify_quickshell.py --screenshots /tmp/quickshell-verification
```

The tests launch/stop only their own Quickshell instances. They exercise search,
empty states, overlay routing, a harmless fixture app and its usage history,
a stub wallpaper setter, preview expiration, and the real notification server
on a **private `dbus-run-session` bus**. Notification tests cover requested
millisecond timeouts, replacement, sticky notifications, DND, transients, the
five-popup limit, client close and clear-all. Font and isolated palette tests
cover writes, atomic replacement, recreated symlinks and missing/partial recovery.
Contrast tests cover every grayscale background and 200 deterministic colored
wallpapers, plus actual Qt palette roles, button states and intermediate color
frames. `shell theme` includes a `contrast` audit; screenshot mode saves it as
`theme-contrast.json`. The math test uses Node.js; actual-Qt tests use headless `qs`.
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

For live notifications use `desktop.sh activate`; it checks ownership, performs
an orderly SwayNC handoff and rolls back on failure. For isolated development,
`QUICKSHELL_NOTIFICATIONS=server` must only be used on a private bus or after
releasing the live name. The legacy
`QUICKSHELL_ENABLE_NOTIFICATIONS=1` still works. Do not run two real servers
on the same session bus.

## Remaining limits

- On-disk notification history and inline replies are not implemented (neither
  was configured in the old desktop). Body b/i/u and safe links are supported;
  arbitrary rich HTML/resource loading is intentionally not.
- DND/history reset on process restart; tracked notifications survive QML reload.
- Multi-monitor/hotplug and physical small-screen behavior still need testing;
  compact wallpaper-card layout is now covered without changing output settings.
- Legacy configs/packages remain available for explicit rollback; they are not
  autostarted or revived by color hooks in Quickshell mode.
