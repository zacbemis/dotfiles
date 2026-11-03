# Minimal shell design

The bar profiles and feature renderers retain their distinct layouts, but share
these presentation rules:

- No popup X/close or search-clear buttons. Escape and outside-click dismissal
  remain; the existing launcher modes, selection and keyboard actions remain.
- No permanent keyboard directions, implementation notes, successful-save text,
  repeated result counts or per-card explanation paragraphs. Keep meaningful
  filenames, paths, message bodies, media data, errors and preview-mode indicators.
  Option descriptions live in tooltips and accessibility names.
- Avoid repeated headings, shortcuts and nested outlines. The shared tabs name
  Apps/Run/Files/Wallpapers/Settings; unselected app tiles do not need boxes. Quick settings renders core
  controls rather than repeating app/wallpaper shortcuts and media play buttons.
- Settings applies/saves immediately. Classic already resets defaults, so there
  is no second reset button. The bar is visible outside the popup; only other
  components need a Preview button.
- Wallpaper selection remains preview-only. Each renderer has **one** small
  **Set wallpaper** action, also reachable by Enter/double-click. Removing it must
  not turn ordinary browsing into wallpaper application.
- Notification dismissal is meaningful, not window chrome: show a small trash
  action on hover or keyboard focus, keep Delete, and disable hidden hit targets.
  Preserve app grouping, timestamps, body expansion, client actions and DND.
- Desktop bars have no dedicated wallpaper icon; the gear opens Quick settings
  beside Notifications in the imported layouts. Notification centers do not repeat
  that shortcut. Existing per-profile icon sizes and spacing are retained; the
  original pill layout keeps the Quick settings gear last.
  Wallpapers remain available in the shared panel and Super+W; the clock is display-only.
- Keep SF text sizes readable; reduce padding, repeated rows and empty space
  rather than shrinking all typography. Wallpaper-derived contrast roles stay.

## Default maximum sizes (logical pixels)

| Surface | Width × height |
| --- | --- |
| All five tabbed pages, every renderer | Shared 720 × 420 |
| Quick settings | 340/360 wide, content-sized |
| Horizontal / vertical OSD | 280 × 48 / 56 × 180 |

Tabbed pages no longer resize for short/empty search results or when switching
renderers. See [NAVIGATION.md](NAVIGATION.md) for Alt+H/L and shared-frame details.
Notification panels remain separate, narrower surfaces with shorter empty states. All sizes are bounded by the current output;
wallpaper/selector comparison sizing hooks remain available for narrow tests.

The comparison-only 740 × 310 dashboard is now a small wrapping toolbar. Its gear
opens the shared selector instead of duplicating all of its feature settings.
Daily startup, saved choices, notification ownership, wallpaper generators and
all underlying action/IPC routes are unchanged.

## Exterior spacing and hover alignment

`LayoutMetrics` reads Hyprland's live `general:gaps_out`, `general:gaps_in` and
per-output reserved areas without changing compositor settings. Edge panels,
notification popups, tray menus and OSDs use the outer gap beyond reserved bars.
With this configuration that is **8 logical pixels** (top panels start at y=40
with a 32px bar). Centered navigation stays 720 × 420, shrinking only to fit
those safe edges. Internal padding and each bar profile's original spacing stay
unchanged.

Tooltips center their bubble on the target hit area and center each text line.
Their vertical separation uses the combined inner window insets (4 + 4 = 8px).
Native popup constraints still keep them on-screen. Target movement/resizing
updates the anchor; long output names no longer left-align the percentage line.

Metrics refresh on configuration/monitor/layer changes, bar profile/auto-hide/pin changes,
and panel opening, with a coalesced read and a 60-second recovery refresh. Keep
the last valid values on read/parse failure; initial fallback is outer 8/inner 4.
Fresh reserved-area snapshots avoid stale Hyprland monitor caches after switching
bar profiles. There are no preference writes or compositor mutations.

## Direct panel switching

Fullscreen dismissal surfaces capture the entire desktop **including the bar**,
with small input cutouts only for actual panel-opening buttons. Clicking those
buttons switches directly; the bar's background, gaps and non-panel widgets still
dismiss the open window. Both bar implementations register their button items,
including the separate Apps control and eligible tray entries. The display-only
clock is not a cutout, so clicking it dismisses an open panel like other outside areas. Cross-window
mapping follows output position, scale, parent layout changes and auto-hide.
Because Wayland does not give Qt layer-shell global positions, the coalesced
metrics read also caches compositor layer frames **for this shell PID only**;
cutouts use the actual bar frame relative to the output origin, not guessed
reserved margins. This also handles stacked comparison bars and retained native
namespaces when switching bar profiles.
Desktop outside-click and Escape dismissal remain unchanged; closed/fading
surfaces release input. Navigation and tray menus use the same precise mask.

The Quick settings gear returns directly from Sound/Network/Bluetooth/VPN to the
overview in the existing native controls window. Only clicking it while already
on the overview closes it. Sound and notification icons retain same-panel toggle
behaviour, while different icons route directly without an intermediate close.
`tests/test_quickshell_panel_switching.py` checks routing, bar-background capture,
button-only cutouts, ancestor movement/visibility and immediate input release
with offline connectivity fixtures.

## Verification

`tests/test_quickshell_minimal.py` guards chrome, size caps, explicit wallpaper
activation and hidden dismissal hit targets. The existing full runtime suites
cover fonts/contrast, exclusive input, narrow layouts, search and activation,
notification actions/history, carousel events and normal/reduced motion. Feature
integration checks the fixed common frame even with short search results; the
navigation suite checks identical frame position and size across all tabs.
`tests/test_quickshell_layout.py` checks actual popup positions at 1×/2× scale,
multiline centering, target movement, CSS gap parsing and invalid-data retention.
`tests/verify_quickshell_layout.py` checks live gap/reserved-edge alignment across
all bars, control/notification renderers, tray menus and both OSDs in preview only.
