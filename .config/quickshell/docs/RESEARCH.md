# Quickshell architecture review

## Local baseline

Reviewed the development shell, shared controls, bar, pickers, notification
backend/records, palette/motion handling, wrapper and verification script.
The existing CLI verification passed before changes on Quickshell 0.3.1.

Keep these existing strengths:

- `Variants` creates one bar per screen; PipeWire/UPower already use native
  reactive services rather than command polling.
- `UiState` owns exclusive routes and monitor pinning. Shared overlay/picker
  components own keyboard handling, input release and animations.
- Notification state and expiration belong to records, not popup delegates.
- Palette/fonts and reusable controls are centralized. Desktop integration is
  explicitly opt-in, with private-bus notification tests and stub setters.

Main findings: brightness launched a shell and two commands every second;
`Theme` launched two hyprctl commands every five seconds; update pipelines
converted failed commands into successful zero counts; refreshed notification
records could bypass the actual popup cap; wallpaper delegates/images remained
bound after dismissal.

## Upstream implementations inspected

These are implementation references, not dependencies or code copied wholesale.
Links track upstream branches and may evolve.

### Caelestia

- [shell.qml](https://github.com/caelestia-dots/shell/blob/main/shell.qml): small
  composition root, separate services/modules/daemons, explicit startup access
  for services that must not remain lazy.
- [services/Brightness.qml](https://github.com/caelestia-dots/shell/blob/main/services/Brightness.qml):
  a dedicated brightness singleton, per-screen monitor variants, discovery
  separate from adjustment, queued/throttled DDC changes. Its sysfs path invokes
  brightnessctl on initialization/adjustment rather than every second.
- [services/Hypr.qml](https://github.com/caelestia-dots/shell/blob/main/services/Hypr.qml):
  `Connections` to `Hyprland.rawEvent`; `configreloaded` drives a service signal.

Applied: focused brightness/motion services, serialized/coalesced brightness
adjustments, and event-driven compositor refresh. Unlike Caelestia's cached
backlight value, retain direct reads so external brightness keys remain visible.
Do not adopt its DDC/Apple display support without suitable hardware tests.

### DankMaterialShell

- [Services/SystemUpdateService.qml](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/SystemUpdateService.qml):
  separate checking/upgrading/error state, last-check metadata, backend
  subscriptions, and consumer references controlling daemon polling. UI consumers
  acquire/release demand rather than the service knowing their route names.

Applied: independent `UpdateService`, explicit error/known/checking state,
structured backend results, and UI-owned polling demand. A single boolean is
sufficient for this shell's one update consumer; reference counting and a daemon
would add unnecessary machinery. Existing no-eager-network-check behavior stays.

### Official Quickshell APIs

- [Variants](https://quickshell.org/docs/v0.3.0/types/Quickshell/Variants/):
  appropriate for screen-bound instances; keep the existing bar architecture.
- [LazyLoader](https://quickshell.org/docs/v0.3.0/types/Quickshell/LazyLoader/):
  deferred/async component loading; forcing active/item access can block.
- [FileView](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/FileView/):
  small-file background loading; blocking reads can stall the UI.

Applied: asynchronous small sysfs reads and demand-bound wallpaper delegates.
Keep picker controllers/windows and IPC alive; only release image delegates and
preview sources after exit animations. Wrapping whole controllers in route-bound
loaders would remove their IPC targets and could truncate exits. Never unload the
notification backend just because its center is hidden.

## Component selector research

The daily categorized selector takes interaction ideas from Noctalia's
Quickshell-era settings (GUI categories, immediate application and auto-save),
Caelestia's partial JSON configuration/defaults, and DMS/Dux's UI + IPC settings.
[SETTINGS.md](SETTINGS.md#online-design-references) records primary links and the
implementation boundaries. No upstream settings code/daemon was imported; the
local validated store and independent renderer selectors remain our own.

## Implementation decisions

The composition root now lives at `.config/quickshell/shell.qml`. Focused
singletons and their data objects live in `services/`, the palette in `theme/`,
shared controls in `components/`, and feature UI in `modules/`. Imports use
Quickshell's root-relative `qs.*` namespace. Runtime helpers live in `scripts/`;
tests are kept under the repository's `tests/`, outside deployed configuration.

- `services/BrightnessService.qml`: one brightnessctl discovery; native file refreshes at
  1 Hz because sysfs does not reliably emit file-watcher notifications. Rediscover
  every 30 seconds only while unavailable. Bind controls to the discovered
  backlight, not keyboard LEDs. Queue wheel steps and reload after setters exit.
- `services/MotionService.qml`: refresh at startup/config reload, coalesce bursts, and
  retain a 60-second fallback for runtime changes that emit no reload event.
- `services/UpdateService.qml` / `scripts/check-updates.py`: 60-second timeout per installed
  backend, checkupdates exit 2 treated as no updates, failures exposed separately,
  and last successful count retained. Missing tools are skipped; no tools is an
  error. The existing explicit terminal upgrade action remains unchanged.
- Notifications: refreshing a record promotes it and enforces the eligible
  popup cap, including timeout-only replacements. This fixes a local correctness
  issue; it is not claimed as an upstream algorithm.
- Wallpaper data/selection remain available through IPC after dismissal, but
  thumbnail delegates and the preview source are released.

## Validation and limits

`tests/test_quickshell.py` runs headless service fixtures: no periodic brightness
command spawning, external file updates, rapid adjustments, missing/empty file
recovery, successful/failed/recovered update checks, absent backends and timeouts.
`tests/verify_quickshell.py` additionally checks real rendering/runtime integration, private-bus
notification replacement limits/timeouts, and hidden wallpaper image release.

No measured CPU/RAM improvement is claimed; the reduction in scheduled subprocess
launches follows from the implementation and is regression-tested for brightness.
No wallpaper, packages, live notification ownership, desktop styling, autostart or
keybindings are changed. Multi-monitor hotplug, DDC and persistent notification
history remain future work, rather than expanding this migration's scope.
