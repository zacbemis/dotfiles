# Dotfile shell comparisons

## Run

```bash
bash .config/quickshell/compare.sh list
bash .config/quickshell/compare.sh             # starts Current, with a switcher
bash .config/quickshell/compare.sh enzo
bash .config/quickshell/compare.sh mm2103
```

Run **one comparison instance**. Use the bottom-right toolbar to switch Current /
Enzo / MM-2103 live; do not launch three concurrent bars. Ctrl+C stops only that
instance. Existing Waybar/SwayNC/Rofi/autostart/keybindings remain unchanged.
While Waybar is running, layer-shell places the preview below its reserved bar
space: seeing two bars is intentional, not a cutover.

These are **adapted upstream bar/layout profiles**, not full installations of the
upstream desktop shells. Selected real source is vendored, pinned and licensed;
we ported layouts/workspace widgets and replaced their integrations with shared
services. Bar changes do not alter feature choices. The toolbar's gear opens the shared selector for independent
app/wallpaper/notification/control/OSD choices; see
[FEATURE-COMPARISON.md](FEATURE-COMPARISON.md). Application launching, wallpaper
application and notification lifetimes still have single shared controllers.

### What you can compare

| | Current | EnzoNotNice | MM-2103 |
| --- | --- | --- | --- |
| Frame | Separate wallpaper-colored pills | Floating rounded translucent strip | Flat edge-to-edge strip + bottom hairline |
| Workspace treatment | Number + application icons | Animated pills + application icons | Numbered chips + application icons |
| Center | Clock | Native MPRIS title / play-pause | Absolute centered date/clock |
| Active window title | Not in bar | Elided beside workspaces | Elided beside workspaces |
| Colors | Our wallpaper palette | Native Catppuccin-inspired, or Wal colors | Native grayscale/white, or Wal colors |
| Auto-hide | Not added | Not added | Optional hover reveal, pinning, 2 px hidden input strip |
| Shared feature UI | Existing QML pickers, menus and notification center | Same | Same |

The selector's bar section has **Upstream / Wallpaper** colors, changing only the
imported bar palette, not generated wallpaper files or your desktop theme. **Auto-hide** and
**Pin** apply only to MM-2103. Reduced-motion mode disables the added transitions:

```bash
QUICKSHELL_REDUCED_MOTION=1 bash .config/quickshell/compare.sh enzo
```

### Feature wiring

| Needed feature | Wiring in imported layouts |
| --- | --- |
| Applications | Launcher glyph / comparison Apps button → `UiState` → existing `Launcher` |
| Workspaces and app icons | Per-monitor native Hyprland workspace objects; `.activate()` works with current Lua Hyprland |
| Network / Bluetooth | Existing real DBus tray items, with our themed menus/submenus and middle activation |
| Volume / mute | `SystemState` → tracked native PipeWire sink; click mute, scroll 2% |
| Brightness | `BrightnessService`; scroll 5%, panel hidden when unavailable |
| Battery | Native UPower, hidden when unavailable |
| Media | Native MPRIS metadata and play/pause, no new playerctl polling |
| Wallpaper | Image glyph / Wallpapers button → existing picker → exact-path existing Pywal setter |
| Notifications / DND | Bell / Alerts button → existing service and center; right-click bell toggles DND |
| Updates / media transport | Existing notification center controls; no eager network check |
| Wallpaper palette | Existing read-only palette watcher; optional bar color toggle |

**Comparison notifications are always previews**, even if your environment sets
`QUICKSHELL_NOTIFICATIONS=server`. The backend independently enforces this, not
just the wrapper. Sample inserts a synthetic notification into this instance.
No live notification owner is replaced. The sample/history survives profile
changes and is discarded when the process stops. Actual application launches,
audio/brightness adjustments, update checks and wallpaper applies happen only
when you explicitly activate those controls; preview mode does not sandbox your
own requested actions.

No upstream installer, power action, session lock, wallpaper daemon, font
installer, external weather/AI service, or system-theme writer is activated.
Optional upstream CPU/RAM/network pollers were not imported. Native Wi-Fi/BT
controls now use the event-driven bridge described in [CONNECTIVITY.md](CONNECTIVITY.md);
right-click still retains the existing applet menus. We do not claim complete upstream feature parity.

## Feature-level alternatives

[FEATURE-COMPARISON.md](FEATURE-COMPARISON.md) documents the live independent
feature choices and their supported behavior. [FEATURE-ALTERNATIVES.md](FEATURE-ALTERNATIVES.md)
records the broader source research, including alternatives not yet ported.

## Research and selection

Inspected source files/READMEs rather than relying only on screenshots:

| Config | Architecture / implementation | Decision |
| --- | --- | --- |
| [EnzoNotNice/quickshell-bar](https://github.com/EnzoNotNice/quickshell-bar) | Small per-widget QML config; floating frame; animated workspace pills; center media; inline Catppuccin colors. Several widgets poll CLI commands and use unqualified shell-command bindings. | Imported selected MIT source and ported layout/widgets. Replace polling, unscoped IPC and fixed 1–5 workspace assumptions. |
| [MM-2103/quickshell-bar](https://github.com/MM-2103/quickshell-bar) | Per-screen bars, compositor facade, service-oriented widgets; keyed workspace chips; grayscale theme; mapped-but-masked/sliding auto-hide panel. Full entry point also starts wallpaper, lock, idle, polkit and night-light services. | Imported selected MIT source. Keep the layout/workspace/auto-hide design, not its system-changing service bootstrap. |
| [dedenholm/hyprminimal-quickshell-bar](https://github.com/dedenholm/hyprminimal-quickshell-bar) | Auto-hide with separate reveal strip; configurable commands/fonts; widgets inherit `main` state; pause/resume polling while hidden; some optional remote toggle plumbing. | Researched, not bundled. GPL-3.0 source plus machine-specific toggle paths; MM gives a differently structured auto-hide option without adding GPL-derived code to this MIT tree. |
| [bjarneo/quickshell, desktop](https://github.com/bjarneo/quickshell/tree/main/desktop) | Shared root state, separate bar faces, rich omni-menu and Quick tiles; Omarchy palette/command integration; four bar edges. | Researched, not bundled. Strong Omarchy integration and no license file in the inspected tree; not a drop-in for our Pywal/Hyprland setup. |
| [ekremx25/quickshell](https://github.com/ekremx25/quickshell) | Large MIT desktop shell; component/module/service split; configurable bar/dock, settings, theme, lock and monitor management. | Reviewed README/tree/license, not integrated. Its full system settings/theme/lock stack is much broader than a safe side-by-side bar comparison. |

Pinned imported revisions and per-file hashes are in
[`vendor/sources.json`](../vendor/sources.json); source and licenses are retained
under `vendor/<profile>/upstream/`. No network fetch is needed at runtime. Runtime
ports live in `modules/comparison/`; shared selection/action state lives in
`services/ShellProfile.qml`. Baseline implementation remains in `modules/bar/`.
Bar/tray IPC is registered once at the composition root and delegated to the
current adapter, avoiding duplicate registration during hot switching.

## IPC

Use the PID from `qs list --all`, so commands cannot hit another running shell:

```bash
qs ipc --pid <pid> call profile status
qs ipc --pid <pid> call profile set enzo
qs ipc --pid <pid> call profile set mm2103
qs ipc --pid <pid> call profile next
qs ipc --pid <pid> call profile colors
qs ipc --pid <pid> call profile autohide
qs ipc --pid <pid> call profile activate launcher
qs ipc --pid <pid> call profile activate wallpaper
qs ipc --pid <pid> call profile activate notifications
qs ipc --pid <pid> call profile activate sample
qs ipc --pid <pid> call bar geometry
qs ipc --pid <pid> call bar reveal       # imported profiles
qs ipc --pid <pid> call bar hide
qs ipc --pid <pid> call bar toggle       # MM pin/unpin
```

For a normal development run without the comparison panel:
`bash .config/quickshell/run.sh --profile enzo --preview`.
No comparison profile choice is persisted; the comparison default stays Current.
Daily choices now save through the [component selector](SETTINGS.md).

## Validation / optional gallery

```bash
python3 -m unittest discover -s tests -p test_quickshell.py -v
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_profiles.py
QUICKSHELL_REDUCED_MOTION=1 python3 tests/verify_quickshell_profiles.py
# Explicitly opt in: screenshots include your current desktop/open apps.
python3 tests/verify_quickshell_profiles.py --screenshots /tmp/quickshell-comparison
xdg-open /tmp/quickshell-comparison/index.html
```

The comparison verifier owns/stops only its child, cycles layouts repeatedly,
exercises the same click-path feature dispatcher, fake-wallpaper discovery,
preview/history retention, palette controls, real tray menu opening (no network
changes), and auto-hide mask/reservation/pinning. It never applies a wallpaper,
launches an app, runs an updater, or changes audio/brightness. Runtime warnings
fail the test. Offline checks validate source hashes, CLI validation and the
backend's preview-only guard even with an unavailable D-Bus address.

Bar-only captures were visually inspected on the current 1440-logical-pixel
HiDPI output; temporary images live under `/tmp/quickshell-layout-review.OSbAnm/`.
They are local evidence, not tracked assets. Physical multi-monitor/hotplug and
very narrow screens still need testing; no performance benchmark is claimed.
