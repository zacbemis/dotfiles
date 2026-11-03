# Optional bar indicators

Open **Settings → Bar indicators** (Super+, or the shared Settings tab). Sound,
brightness and battery each have four independent modes:

| Mode | Result |
| --- | --- |
| Icon + % (`both`) | Descriptive icon and percentage/readout |
| Icon only (`icon`) | Descriptive icon; exact value remains in its tooltip |
| % only (`percent`) | Readout with no empty icon gap; muted sound says Muted |
| Hidden (`hidden`) | Entire module removed, including its hit region/spacing |

Existing preferences default to Icon + %; merely loading the update does not
rewrite choices. Changes apply to **all three bar profiles**, persist atomically,
and survive restart. Bar/renderer presets do not reset these choices. Comparison
sessions do not read or write daily preferences. OSD settings and quick-settings
controls remain independent: hiding a bar indicator does not disable popup feedback
or alter hardware. Exact tooltip values remain available when an icon is shown.

## Descriptive icons

`components/StatusIcon.qml` is an original small vector renderer, using the existing
SystemState/PipeWire/UPower/brightness data rather than another hardware poller.

- **Battery:** proportional fill, a bolt while charging (including at empty), a
  full-charge check, and a plugged-in mark when connected but not charging.
  Existing low-battery warning labels remain; the icon itself keeps the shared
  wallpaper accent, even while low/charging. Full charge comes from
  UPower's actual state, not an arbitrary 99% threshold.
- **Brightness:** a level-filled sun with increasing rays. It represents the
  actual brightness, not time of day; the previous moon/day glyph was misleading.
- **Sound:** silent speaker at zero, increasing waves for low/medium/high, a cross
  for mute, a Bluetooth badge when appropriate, and a boost mark above 100%.

Sound, battery/charging and the settings gear have calibrated painted sizes
(18/15/15px respectively). These are based on the actual Papirus Wi-Fi/Bluetooth
artwork at 2× scale, including visible width and painted area rather than height
alone. A horizontal battery must be shorter than a square Wi-Fi icon to avoid
looking oversized. The battery's rendered footprint is about 16.5×10px, including
its terminal, versus Wi-Fi's 15×14px; even full-charge ink area stays comparable.
`tests/measure_quickshell_icons.py` audits vectors, badges, brightness, settings,
notifications/DND, clock, applications, media and the original Arch glyph. `inkSize` changes rendering only: original 14/15px layout
slots, bar spacing, text and hit targets stay unchanged across all profiles.
Brightness, notification glyphs and tray/application logos retain their sizes.
Vertical centering preserves fractional logical pixels instead of snapping odd
paint/slot heights to whole pixels. This fixes the battery canvas and tray artwork
landing on different center lines at 2× scale. The same centering is used in both
bar implementations without changing horizontal positions or spacing. Pixel audits
cover both 14px and 15px slots, including charging/full/mute/Bluetooth states.

Ordinary shell-drawn bar status icons share a **near-white wallpaper tint**
(85% white mixed into the wallpaper primary), including sound, brightness, battery,
clock/control glyphs and media icons. Sound has no separate tertiary/amber color.
Mute, low battery and hover retain that shared ink; shapes/badges/tooltips convey
state, while optional warning labels can retain semantic colors. Tray/application
logos are not recolored. The shared role is contrast-checked against bar/hover
surfaces and follows palette changes, with readable adaptation on light palettes
and upstream previews.

**Notifications are the intentional exception:** any unseen records use the previous,
darker wallpaper-primary accent. Once all records have been seen, the icon returns
to the same near-white tint as the other icons, even if history remains. Opening
any notification-center layout marks those records seen. Popup expiry and DND do
not falsely mark unseen records read; notifications arriving while the center is
open are already seen. All three bar profiles use the same rule.
Transparent badge halos
keep battery state marks distinguishable across fill levels and backplates.
They are drawn at the profile's existing icon height; meaningful battery/Bluetooth
width is intrinsic. No bar padding, tray spacing or other profile module sizes
are normalized. Text remains SF Pro Display; vector icons need no replacement font.
Accessible names include state and exact values.

Icon-only presentation is approximate by design: waves/rays and a small battery
fill are not an exact numerical meter. Tooltips and an enabled OSD retain precision.

## IPC

```bash
pid=$(~/.config/quickshell/desktop.sh status | jq -r '.session.shell.pid')
qs ipc --pid "$pid" call settings category indicators
qs ipc --pid "$pid" call settings set volumeIndicator icon
qs ipc --pid "$pid" call settings set brightnessIndicator hidden
qs ipc --pid "$pid" call settings set batteryIndicator both
qs ipc --pid "$pid" call settings apply '{"volumeIndicator":"icon","brightnessIndicator":"icon"}'
```

The three keys accept only `both`, `icon`, `percent`, `hidden`. Invalid multi-key
updates are rejected atomically. Normal live choices are not changed by tests.

## Research

Design/interaction references only, not imported implementation code or assets:

- [macOS Menu Bar settings](https://support.apple.com/guide/mac-help/change-menu-bar-settings-mchlad96d366/mac):
  optional menu-bar modules and independently optional battery percentage.
- [Windows battery and charging](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/battery-and-charging):
  battery icons convey power source/charging state; detailed values remain available
  without requiring a permanent percentage beside the icon.
- [Noctalia battery widget](https://docs.noctalia.dev/noctalia/bar/widgets/battery/):
  graphical fill, independent label visibility and distinct charging/plugged state.
- [Noctalia volume widget](https://docs.noctalia.dev/noctalia/bar/widgets/volume/):
  separate glyph/readout visibility, dynamic levels and explicit mute presentation.

No additional shell, widget package or proprietary icon assets are installed.

## Verification

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell_indicators.py
```

The indicator harness uses the compose input context because it tests only display
choices, avoiding Qt Wayland text-input-v3 focus warnings in locked test sessions.
For the other non-IME runtime suites, `QT_IM_MODULE=compose python3 tests/<suite>.py`
can be used in the same situation. This is test-only; the daily shell's input method
is not changed.

Coverage includes persistent independent modes, invalid/partial preference fallback,
all three real bars, mixed modes, preset and OSD independence, comparison isolation,
near-white icon color and live wallpaper-palette replacement, notification seen/unseen
transitions across all bar/center combinations (including expiry and DND),
actual 14px vector image differences (levels/mute/charge/full/plug/Bluetooth/boost),
and resolved SF text. Tests change presentation only, never volume, brightness,
battery/power configuration or production notification ownership.
