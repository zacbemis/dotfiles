# Wallpaper-derived contrast

The palette still comes from the existing read-only Waybar/Pywal/Matugen output.
No generated colors, wallpaper, GTK/terminal settings or other desktop components
are changed. The original and comparison feature views share the corrected roles;
comparison bars retain their explicit source-colors / wallpaper-colors switch.
SF titles and the currently applied supporting font are unchanged.

## Why the raw palette needed help

The current green Pywal palette gives `surface_container`,
`surface_container_high`, `outline_variant` and several containers the same
middle-bright green-gray. Its extracted `on_surface_variant` is too close to
those surfaces. A color named `primary` is also not automatically readable text
on a color named `inverse_primary`.

Measured role pairs for the current wallpaper:

| Pair | Raw roles before | Corrected roles |
| --- | ---: | ---: |
| Main text / card surface | 3.05:1 | 8.44:1 |
| Supporting text / card surface | 1.81:1 | 5.49:1 |
| Main text / highest ordinary surface | 3.05:1 | 7.05:1 |
| Supporting text / highest ordinary surface | 1.81:1 | 4.59:1 |

These are solid foreground/background role ratios, not a claim that every old
widget used the uncorrected pair. Some buttons already selected a better
foreground; the old fallback still failed when both candidates were unsuitable.
The resulting green accents remain green, not a replacement blue/gray theme.

## Policy

`theme/Theme.qml` defines semantic roles. `theme/ColorMath.js` implements sRGB
relative luminance, alpha composition, contrast and minimal tonal adjustment.

- Preserve extracted accent seeds. Leave a usable foreground alone; otherwise
  move its tone toward black or white only as far as necessary. This retains
  the seed's hue rather than substituting an unrelated preset color.
- Derive panel/card/raised surfaces from the background and generated surface
  hints. Keep their tones close to the base and in the same foreground polarity.
  Dark and light palettes both work; identical/flat palettes still gain hierarchy.
- Main text targets **7:1 across ordinary surfaces**. Where the preserved base
  makes 7:1 impossible, use **4.5:1**. Subtitles, timestamps, descriptions and
  accent-colored text target **4.5:1** without additional opacity multipliers.
- Use `primaryInk`, `secondaryInk`, `tertiaryInk` and `inversePrimaryInk` for text
  on ordinary surfaces. The corresponding raw accents are fill seeds, not text
  roles. Selected fills use `pickerSelectedText` / `activeText`, not body text.
- Ordinary shell-drawn bar status icons use one near-white `barIconColor`, seeded
  from wallpaper primary mixed 85% toward white, checked at **4.5:1** across
  normal/hover surfaces. The exception is unseen notifications: `barUnreadIconColor`
  preserves the previous darker primary accent, also checked at **4.5:1**; all-seen
  history returns to the shared near-white ink. Imported previews adapt these same
  seeds for readability rather than giving audio a separate tertiary color. Other
  state uses shape/badges; warning labels may keep semantic error roles. Client
  logos stay untouched.
- Selection/active boundaries, focus rings, outlines and slider fill-versus-track
  pairs target **3:1**. Slider fills retain a track-colored rim and thumbs have
  an outline, so a fill similar to the base cannot erase the control boundary.
  Disabled labels target **3:1** as a usability choice,
  even though inactive controls are exempt from the WCAG contrast requirement.
- Use an opaque control backplate and calculate text from its actual animated
  color. Independently animating foreground and background can pass through an
  unreadable pair even when both endpoints are good.
- Floating panels are 98% opaque. Test text against both black and white behind
  a translucent panel; if that small amount of bleed makes the target infeasible
  near middle gray, make the panel opaque. Foreground alpha is composited too.
- Round adjusted RGB colors to renderable 8-bit values before testing them, with
  a small contrast margin where available, rather than passing only in float math.

The ratio targets follow [WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
and [non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).
This is a theme-role/interaction check, not a complete accessibility conformance
claim. Bitmap icons, app-provided images and wallpaper thumbnails are not recolored;
intentional overlay entry/exit fades are not static reading states.

## Diagnostics and regression coverage

```bash
qs ipc --pid <pid> call shell theme
python3 -m unittest discover -s tests -p test_quickshell_contrast.py -v
python3 tests/verify_quickshell.py
```

`shell theme` keeps the extracted `primary`/`secondary`/`tertiary` fields and adds
rendered `roles` plus a `contrast` array of named pairs, actual colors, measured
ratios and minimum targets. Translucent-background ratios are worst-case over
black/white underlays. Screenshot verification also writes `theme-contrast.json`.

The math tests exercise all 256 grayscale bases and 200 deterministic colored
wallpapers, flat/identical seeds, alpha composition and selected backgrounds.
Headless actual-Qt tests apply the current palette, deliberately colliding dark,
light, middle-gray and saturated palettes, aliases and translucent foregrounds.
They check roles, normal/pressed/disabled buttons and intermediate interaction
colors. The desktop verifier repeats the role checks during live palette writes,
atomic replacement, symlink replacement and missing/partial-file recovery.

Temporary visual review captures are in `/tmp/quickshell-contrast-review/`;
they include the desktop/open apps and are not deployed or committed.
