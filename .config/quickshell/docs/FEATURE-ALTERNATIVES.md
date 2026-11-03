# Feature-level Quickshell alternatives

## Scope

This research identifies genuinely different implementations beyond bar layouts.
Selected **MIT renderer ports are now wired in**, independently of the bar: MM
search/gallery/compact notifications/quick settings, Dux-style grid/carousel/
stacked presentation, and passive OSD layouts. See
[FEATURE-COMPARISON.md](FEATURE-COMPARISON.md) for exact supported behavior and tests.
The source shells below are not installed wholesale; GPL/unlicensed modules and
unported upstream providers remain research references. Research-only findings
are not runtime compatibility claims. No upstream installer/daemon/theme writer
was run.

## Shortlist

| Project | App selector | Wallpaper selector | Notifications / other features | Integration fit |
| --- | --- | --- | --- | --- |
| [MM-2103/quickshell-bar](https://github.com/MM-2103/quickshell-bar) | Compact search list; app frecency; calculator, web and emoji query modes | Four-column folder browser, output selector and fit-mode controls | Compact anchored history popover; reusable cards; 3-column control-center tiles; bottom OSD; clipboard history | **Best first port.** MIT, QML services; adapt theme/router/backend interfaces. |
| [scottbass3/shell](https://github.com/scottbass3/shell) | Windows 11-style pinned and recommended app grids; paged pins; drag reordering; context menu | Favorites/local/Wallhaven tabs, rotation selections, thumbnail grids | Conversation-like stacks grouped by app + title; content-only center/toast UI; vertical speaker/microphone sliders and device page | **Biggest visual/interaction change.** GPL-3.0; custom theme/state/window shell. |
| [Caelestia](https://github.com/caelestia-dots/shell) | Command-oriented launcher with separate app/action result types and field-specific search | Horizontal centered carousel in the launcher; separate categorized gallery | Swipe-away/expandable Material cards, timeout ring, grouped sidebar and stored history; media/performance dashboard | **Polished, higher-effort port.** GPL-3.0; custom C++ QML modules and current git Quickshell. |
| [Dux Shell, formerly DankMaterialShell](https://github.com/duxlabs-dev/dux-shell) | Spotlight and app drawer; row/grid views; pinned items and multi-source search | Dashboard carousel and paged thumbnail grid with per-monitor targeting | Grouped session/history tabs, keyboard navigation and swipe interactions; detailed quick settings and device pages | **Richest MIT reference, substantial dependencies.** Shared QML library, many services and Go backend integration. |
| [doannc2212/quickshell-config](https://github.com/doannc2212/quickshell-config) | Small Rofi-like centered search list | Searchable four-column grid with separate large preview | Dunst-like urgency strips, actions and expiration progress bar; vertical volume/brightness OSD | **Simple reference, not ready to vendor.** No license file found in the inspected revision. |

The AvengeMedia/DankMaterialShell URL currently redirects to
`duxlabs-dev/dux-shell`; the inspected README calls it Dux Shell. The source still
uses DMS/Dank identifiers in several places. Links here use the current repo.

## 1. Application selectors

### A. MM: compact multi-mode search

Source:
- [launcher/Launcher.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/launcher/Launcher.qml)
- [launcher/LauncherService.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/launcher/LauncherService.qml)

What differs: one search box routes normal queries to apps, `=` to arithmetic,
`?` to web search, and `;` to emoji. App/emoji ranking uses a count-and-recency
score. Keyed result rows are released while hidden. This is more of a command
palette than our app-only list, even though the visual layout is also a list.

Adaptation: keep our app visibility filters and launch/usage behavior; replace
`PopupController` with `UiState`, adapt `Theme`, and make clipboard/web actions
explicit. Emoji needs its separately attributed MIT gemoji data. Review the
calculator implementation before importing it; it uses a numeric allowlist and
`Function`, not a general expression language.

### B. Scottbass: pinned/recommended grid

Source:
- [panels/Launcher.qml](https://github.com/scottbass3/shell/blob/86f907703e7079989f8f039ae9b909f6fd0a92e8/panels/Launcher.qml)
- [widgets/launcher/AppGrid.qml](https://github.com/scottbass3/shell/blob/86f907703e7079989f8f039ae9b909f6fd0a92e8/widgets/launcher/AppGrid.qml)

What differs: six-column tiles, pinned app pages, recommended apps, drag-to-reorder
pins, right-click context menus and 2-D keyboard navigation. Search replaces the
home sections with results. The panel is **content only**, making its separation
from its host window useful for our architecture.

Adaptation: put the content in our existing overlay/focus host; provide pin and
usage models over `DesktopEntries`. Do not copy its custom MainWindow/blob border
or unrelated settings stack merely to obtain a grid. Direct code reuse must
retain GPL terms; it cannot silently become MIT code.

### C. Caelestia / Dux: expanded search front ends

- [Caelestia modules/launcher/](https://github.com/caelestia-dots/shell/tree/0b0beb520a36f6972999c2afc97b311a27ba87f0/modules/launcher):
  content/list/item separation, app frequency database, action commands and
  field-specific app searches. Current app search uses `Caelestia.Models.AppDb`
  and a shared searcher; copying the QML alone is insufficient.
- [Dux quickshell/Modals/DLauncherV2/](https://github.com/duxlabs-dev/dux-shell/tree/6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0/quickshell/Modals/DLauncherV2):
  separate controller, scoring/helpers, row/tile components and spotlight host.
  Search can combine apps, files, clipboard/plugins and more. Its controller
  references `AppSearchService`, `SettingsData`, `SessionData` and `DSearchService`.
  Useful as a richer second-stage port, not a one-file drop-in.

## 2. Wallpaper selectors

### A. MM: folder/thumbnail browser

Source:
- [wallpaper/WallpaperPickerPopup.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/wallpaper/WallpaperPickerPopup.qml)
- [wallpaper/WallpaperService.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/wallpaper/WallpaperService.qml)

Four-column lazy grid, folder-up/subfolder navigation, monitor target pills and
Fill/Fit/Stretch/Center/Tile choices. This is a clear alternative to our current
list-plus-preview picker.

**Important:** upstream applies on thumbnail click and paints wallpapers with
its own background-layer `WallpaperLayer`. We should port the browser UI only,
keep our JSON-safe scanner and explicit Apply behavior, and invoke the existing
Pywal setter. That setter currently accepts a selected path, not upstream's
per-output/fill-mode contract: those controls must not be shown as functional
until their backend is implemented.

### B. Caelestia: horizontal carousel

Source:
- [modules/launcher/WallpaperList.qml](https://github.com/caelestia-dots/shell/blob/0b0beb520a36f6972999c2afc97b311a27ba87f0/modules/launcher/WallpaperList.qml)
- [modules/nexus/pages/wallandstyle/WallpaperSelect.qml](https://github.com/caelestia-dots/shell/blob/0b0beb520a36f6972999c2afc97b311a27ba87f0/modules/nexus/pages/wallandstyle/WallpaperSelect.qml)

Launcher variant uses a `PathView`, centered selection, wheel stepping and an odd
number of visible thumbnails. The settings gallery groups local wallpapers into
categories. **Upstream selection previews the actual wallpaper**; its preview
and dynamic-color side effects must be removed/replaced with an in-card preview
for a safe comparison with our current pipeline.

### C. Scottbass / Dux: favorites and richer browsing

- [Scottbass panels/Settings.qml](https://github.com/scottbass3/shell/blob/86f907703e7079989f8f039ae9b909f6fd0a92e8/panels/Settings.qml)
  contains the wallpaper settings section; `services/WallpaperService.qml` and
  `services/WallhavenService.qml` provide favorites, local images, Wallhaven
  browsing/downloading and rotation. Its live preview applies hyprpaper and
  re-themes; commit writes hyprpaper configuration. Do not import those writers.
- [Dux quickshell/Modules/DDash/WallpaperTab.qml](https://github.com/duxlabs-dev/dux-shell/blob/6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0/quickshell/Modules/DDash/WallpaperTab.qml)
  offers a carousel plus paged grid, folder browsing and target-monitor state.
  `WallpaperCarousel.qml` is separately factored, but the surrounding tab relies
  heavily on Dux session/settings services.

## 3. Notifications

### A. MM: small anchored history popover

Source:
- [notifications/NotificationCenterPopup.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/notifications/NotificationCenterPopup.qml)
- [notifications/NotificationCard.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/notifications/NotificationCard.qml)

A compact bar-anchored history list with a count, Clear and DND controls, rather
than our larger combined media/update/notification center. Card rendering is
separate from service state. Low-to-medium porting effort: bind it to our record
objects and keep our overlay host instead of reintroducing platform popup/input
limitations. Its history is session tracking, not evidence of disk persistence.

### B. Caelestia: gesture-driven Material cards

Source:
- [modules/notifications/Notification.qml](https://github.com/caelestia-dots/shell/blob/0b0beb520a36f6972999c2afc97b311a27ba87f0/modules/notifications/Notification.qml)
- [modules/sidebar/](https://github.com/caelestia-dots/shell/tree/0b0beb520a36f6972999c2afc97b311a27ba87f0/modules/sidebar)
- [services/Notifs.qml](https://github.com/caelestia-dots/shell/blob/0b0beb520a36f6972999c2afc97b311a27ba87f0/services/Notifs.qml)

Horizontal swipe hides a popup, vertical dragging expands/collapses, hovering
pauses expiration, and an icon ring indicates remaining time. The sidebar has
group components. The service serializes/restores notification data through
`notifs.json`; restored history must not be confused with a still-live client's
action handles. More sophisticated than changing notification colors/radii.

### C. Scottbass / Dux: stacks and navigable history

- [Scottbass panels/NotificationCenter.qml](https://github.com/scottbass3/shell/blob/86f907703e7079989f8f039ae9b909f6fd0a92e8/panels/NotificationCenter.qml):
  content-only toast/center renderer. Service groups by **application + summary**,
  so distinct conversation titles can become separate stacks, with per-stack and
  per-message dismissal. Different grouping semantics from our application-only
  history; it needs a model adapter, not only a new delegate.
- [Dux quickshell/Modules/Notifications/Center/](https://github.com/duxlabs-dev/dux-shell/tree/6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0/quickshell/Modules/Notifications/Center):
  separate session/history tabs, keyboard controller/hints, grouped cards, swipe
  rows and time-filtered history. Its service has optional JSON-backed history.
  MIT, but substantially tied to Dux common widgets/settings/service contracts.

**Do not start another NotificationServer to compare any of these UIs.** Bind
alternative views to our current preview records; keep expiration, replacement,
DND and actions in the existing service. Rich-text/link rendering and persistence
need a separate behavior/security review rather than accidental adoption.

## 4. Other useful feature implementations

- **Tile-based quick settings:**
  [MM controlcenter/TilesView.qml](https://github.com/MM-2103/quickshell-bar/blob/d31a94da14648439da05457d57b1648da9b3b18e/controlcenter/TilesView.qml)
  plus `SlidersBlock.qml`: a stable 3-column tile grid with volume/brightness,
  network/Bluetooth detail navigation, power profile, caffeine, DND and wallpaper
  actions. Best first alternative to putting everything in the notification
  center. Route existing actions first; do not expose unsupported toggles.
- **Audio-device selector:**
  [Scottbass panels/AudioPanel.qml](https://github.com/scottbass3/shell/blob/86f907703e7079989f8f039ae9b909f6fd0a92e8/panels/AudioPanel.qml)
  has two vertical speaker/microphone sliders and a separate devices page. We
  currently track the default sink only; source/device models are new work.
- **OSD:** MM `osd/Osd.qml` is a bottom horizontal pill;
  [doann osd/OSD.qml](https://github.com/doannc2212/quickshell-config/blob/481a6f479f0255f62ee9f73b9ead16cc2545426c/osd/OSD.qml)
  is a right-edge vertical volume/brightness pill. Bind either design to our
  existing reactive values; do not add a second brightness poller or assume a
  sysfs file watcher reliably reports all external changes.
- **Clipboard selector:** MM `clipboard/ClipboardPopup.qml` /
  `ClipboardService.qml` provides searchable text/image history and cached
  thumbnails over `cliphist` + `wl-copy`. Requires an explicitly enabled clipboard
  capture process (`wl-paste --watch cliphist store`); do not enable background
  capture merely by opening the shell comparison.
- **Media/performance dashboard:** Caelestia `modules/dashboard/` separates media,
  calendar/weather and performance pages. Useful if we want a dashboard instead
  of a small transport card, but services/fonts/custom modules add porting cost.

## Comparison direction and remaining work

The live implementation covers MIT-first subsets of the following designs, not
all upstream behavior. Scottbass pins/recommendations/drag reordering, Caelestia's
carousel/live preview, full Dux providers and disk-backed notification history
are still unported. The implementation guide distinguishes those from the live
choices.


1. **Launcher:** Current app list vs MM multi-mode list vs pinned-app grid.
2. **Wallpaper:** Current list/preview vs MM thumbnail browser vs carousel.
3. **Notifications:** Current grouped center vs MM compact popover vs a
   swipe/stack-oriented view.
4. **Controls:** Current compact controls vs a tile-based quick-settings panel;
   optionally compare horizontal vs vertical OSD separately.

Select each feature independently of the bar. For example, an Enzo bar with a
thumbnail wallpaper gallery and MM notification popover should be possible
without switching the launcher too. Keep `UiState` as the single overlay router,
register each IPC endpoint only once, and expose data/actions through existing
services. The launcher and wallpaper modules currently mix controller/data/view
code, so those need separating before multiple front ends can safely share
usage history, exact-path wallpaper application and stable IPC.

MIT-first implementation order: MM launcher/gallery/notification popover and
quick settings; Dux's factored tile/carousel/card components where their dependency
surface is manageable. Scottbass/Caelestia are strong GPL alternatives to adopt
with license notices/obligations kept intact, or interaction-design references
for an independent implementation. Doann is research-only until licensing is
clarified. No automatic rewriting of this repository's MIT license is proposed.

## Inspected revisions

- MM-2103: `d31a94da14648439da05457d57b1648da9b3b18e` — MIT.
- Scottbass: `86f907703e7079989f8f039ae9b909f6fd0a92e8` — GPL-3.0 license file.
- Caelestia: `0b0beb520a36f6972999c2afc97b311a27ba87f0` — GPL-3.0 license file;
  README requires git Quickshell, a built C++ QML plugin and additional packages.
- Dux: `6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0` — MIT shell source; shared
  libraries/assets retain their own licenses and need review if imported.
- Doann: `481a6f479f0255f62ee9f73b9ead16cc2545426c` — no license file found.

Research clones live outside the dotfiles tree under
`/tmp/quickshell-config-research.GIW5Gk/`; these are temporary inspection sources,
not deployed configurations. Selected pinned MIT source snapshots for the runtime
ports are retained under `vendor/` with licenses and SHA-256 records.
