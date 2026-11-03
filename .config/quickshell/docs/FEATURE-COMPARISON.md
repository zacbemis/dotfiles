# Live feature comparisons

For daily use, open the panel's Settings tab or `desktop.sh settings` for the categorized
[component selector](SETTINGS.md), presets and automatic saving. This page describes
the isolated research/comparison workflow, whose choices are intentionally transient.

```bash
bash .config/quickshell/compare.sh
```

The small bottom-right toolbar switches bars; its gear opens the independent
component selector. Choose a card and use Preview to open its renderer. Escape
or outside-click closes overlays. Toolbar notification/OSD buttons show synthetic
samples without claiming live ownership or adjusting hardware. Ctrl+C stops only
this instance. Comparison view choices are not persisted.

## Available choices

| Feature | Values | What changes |
| --- | --- | --- |
| App selector | `current`, `mm2103`, `grid` | Original app list; MM multi-mode search list; Dux-style icon grid with persistent pins and 2D navigation |
| Wallpaper | `current`, `gallery`, `carousel` | Original list/large preview; MM thumbnail gallery; Dux centered overlapping carousel |
| Notifications | `current`, `compact`, `stacked` | Original combined grouped center; MM compact history list/cards; Dux-style application stacks with All / Last hour / Today filters |
| Quick settings | `compact`, `tiles` | Vertical compact actions; MM-style stable 3-column tile layout; both have volume/brightness sliders |
| OSD | `off`, `horizontal`, `vertical` | None by default; bottom horizontal MM-style pill; local right-edge vertical variant |

These are **ported feature renderers**, not complete upstream shells. Their exact
upstream sources/licenses are retained and hashed in `vendor/`. MM-2103 and Dux
are MIT-licensed. No Scottbass/Caelestia GPL code or unlicensed doann source was
copied. The grid is not Scottbass's complete Windows-style Start menu, and the
carousel is not Caelestia's live wallpaper/theme preview.

### Apps

MM and grid modes support:
- normal text: existing multi-term app search, existing Rofi + local usage scores;
- `= (12 + 3) * 2`: bounded numeric arithmetic; Enter copies the result;
- `? snow & ice`: explicit DuckDuckGo search; Enter opens your browser;
- `; grinning`: emoji search; Enter copies the chosen character.

Copy actions require `wl-copy` (`wl-clipboard`). The emoji catalog is the pinned
MM copy of GitHub's MIT gemoji data; attribution/license is in its retained NOTICE.
All launcher views now share those modes plus Apps / Run / Files / Wallpapers
buttons. `>` is explicit command mode; absolute and `~/` queries are file browsing.
Run history is local, directories remain open on Enter, files use exact-path
`xdg-open`, and terminal desktop entries launch in Kitty.
No web search, clipboard write or application execution occurs just by typing.

Grid: arrow keys navigate in 2D, PageUp/PageDown skip rows, Home/End jump to ends.
Right-click an app to pin/unpin it. Pins appear first on an empty query and live
in Quickshell's `launcher-pins.json`; app usage still uses `launcher-usage.json`.
This is pin-first sorting, not a separate recommended-app model or drag reordering.

### Wallpapers

Every view shares `services/WallpaperData.qml` and the JSON-safe scanner. Click
selects/previews only; **Set wallpaper**, Enter or a double-click explicitly invokes the
existing exact-path setter. Carousel wheel/left-right controls move selection;
mouse wheels and horizontal/vertical touchpad gestures work over both images and
empty viewport space. High-resolution deltas accumulate (120 angle units / 48
logical pixels per image), with bounded selection and no double inversion of
natural scrolling. The viewport handler does not steal image clicks/double-clicks,
including a one-image library. No browsing gesture applies the desktop wallpaper
or regenerates colors.

No upstream wallpaper renderer, swww/hyprpaper writer or theme generator runs.
Per-output targets, fill modes, live desktop preview, online downloads and rotation
are intentionally absent because our current setter has only a path contract.
Images decode at bounded sizes; closed pickers release image delegates/sources.

### Notifications

All views use the **same** `NotificationService` and `NotificationRecord` objects.
Changing a bar or renderer does not create a server or clear history/DND. The
comparison remains preview-only even with an inherited `server` setting.

Compact changes both the popup cards and the center, anchoring a smaller plain
list on the right. Stacked adds collapsible application groups and time filters;
its grouping remains our application's grouping, not Scottbass's app+title
conversation model. Clear, per-group/message dismissal, default actions, action
buttons and full-body expansion use the existing record methods. Text remains
plain for summaries/app names; bodies support sanitized b/i/u and safe links,
not arbitrary resource-loading HTML. On-disk history and inline replies were not added.

### Quick settings / OSD

Both control layouts show notifications, caffeine, media transport, native
[Wi-Fi/Bluetooth detail pages](CONNECTIVITY.md) and updates. DND is a
40×24 switch in every notification panel header, not a Quick settings tile;
its name remains available through the tooltip and accessibility label.
The Sound dropdown owns output/microphone mute, device selection and app levels. Redundant app/wallpaper shortcuts and
duplicate media tiles are omitted; their existing action/IPC routes stay supported.
Unavailable hardware/menu actions are disabled. Brightness is hidden without a
panel backlight; slider writes are serialized/coalesced by `BrightnessService`.
Wi-Fi/Bluetooth tiles open native detail pages; radio, scan, connection and pairing
actions require explicit activation and are read-only in comparison. Update
upgrades are explicit; opening a view does not eagerly contact package servers.
The daily session retains the old read-only login check (not enabled in comparison).
Media controls expose previous/play-pause/next and cycling between available players.

OSD watches the existing services; it adds no brightness poller and never takes
keyboard/pointer input. A startup grace suppresses initial-value flashes and a
1.5-second timer dismisses it. The Preview OSD button / IPC only changes its
presentation data, not system volume/brightness.

Idle dimming/restoring is not a manual brightness event. Hypridle runs
`~/.config/hypr/scripts/idle-brightness.py dim|restore`, preserving save/set-10/restore
while atomically tagging the device and resulting raw value in
`$XDG_RUNTIME_DIR/quickshell-desktop/brightness-automation.json`. BrightnessService
still updates bar values, but does not request OSD for those automatic samples.
Markers expire, apply only to the matching device/value, and are consumed after
observation, so immediate manual changes (including returning to the restore value)
still show feedback. Missing/bad/stale metadata fails open; volume OSD is unchanged.
The helper never starts Quickshell or changes desktop selection/idle timeouts.

`python3 tests/verify_quickshell_idle.py` exercises dim/wake, immediate manual
adjustments, pending/coalesced changes and both OSD layouts against a fake backlight
and fake brightnessctl; it does not dim or restore real hardware.

## IPC

Use the PID from `qs list --all`:

```bash
qs ipc --pid <pid> call features status
qs ipc --pid <pid> call features set launcher mm2103
qs ipc --pid <pid> call features set launcher grid
qs ipc --pid <pid> call features set wallpaper gallery
qs ipc --pid <pid> call features set wallpaper carousel
qs ipc --pid <pid> call features set notifications compact
qs ipc --pid <pid> call features set notifications stacked
qs ipc --pid <pid> call features set controls tiles
qs ipc --pid <pid> call features set osd horizontal
qs ipc --pid <pid> call features cycle wallpaper
qs ipc --pid <pid> call profile activate controls
qs ipc --pid <pid> call osd preview volume 65
```

Existing `launcher`, `wallpaper`, `notifications`, `tray` and `shell` IPC remains
stable. Their controllers live outside renderer loaders. `launcher status` reports
mode/view/pins/columns; `wallpaper status` reports view/selection/image lifetime;
`notifications status` includes alternative view/filter/group information.

## Implementation and verification

- `services/FeatureSettings.qml`: validated independent choices; persistent in daily
  mode through `Preferences.qml`, transient in comparison. `StyleCatalog.js` owns
  the shared choice schema and `modules/settings/` the categorized selector.
- `services/LauncherData.qml`, `services/WallpaperData.qml`: shared data/actions.
- `modules/launcher/`, `modules/wallpaper/`: stable IPC hosts + swappable views.
- `modules/notifications/AlternativeCenter.qml`, `CompactCard.qml`: renderer-only
  alternatives; original service lifecycle retained.
- `modules/controls/`, `modules/osd/`: supported controls and passive OSD.
- `components/PickerWindow.qml`: shared service synchronization and grid keys.

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_features.py
QUICKSHELL_REDUCED_MOTION=1 python3 tests/verify_quickshell_features.py
# Opt-in screenshots include your open desktop/apps:
python3 tests/verify_quickshell_features.py --screenshots /tmp/quickshell-features
xdg-open /tmp/quickshell-features/index.html
```

The feature verifier launches only a harmless fixture app and a stub wallpaper
setter. It checks every view, usage/pin sharing, numeric input rejection, web/emoji
query routing (no activation), grid navigation, exact paths, no apply on preview,
image release, retained preview history, grouping/filter/dismissal, routed control
actions, synthetic OSD expiry and runtime warnings. No real clipboard, package,
hardware, wallpaper or network settings are changed. The main private-bus test
also renders real action QObjects in both alternative notification views.

The current HiDPI output was visually reviewed. Temporary gallery/captures are
at `/tmp/quickshell-feature-review/index.html`; they are not tracked assets.
Physical multi-monitor/hotplug and narrow-screen behavior remain unverified.

See [FEATURE-ALTERNATIVES.md](FEATURE-ALTERNATIVES.md) for the broader research and
still-unported options. Full upstream services/daemons, clipboard capture, audio
source/device selection, per-monitor wallpaper features and complete Dux launcher
providers remain outside this comparison's scope.
