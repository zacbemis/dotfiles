# Shell component selector

Open Settings from the shared **Apps · Run · Files · Wallpapers · Settings** row,
with **Super + ,**, the gear inside Quick settings, or the daily-session helper.
The desktop bar's gear opens Quick settings, not this component selector.
**Alt+H / Alt+L** navigates the same five tabs on every page; they share a stable
720×420 frame. Notifications are not an added tab. See [NAVIGATION.md](NAVIGATION.md).

```bash
~/.config/quickshell/desktop.sh settings
```

Each section has compact, keyboard-focusable choice cards with schematic previews
and a radio-style selected marker; descriptions are tooltips. Click a card to apply
it immediately. Bar changes leave the panel open. Other component choices do not
follow the bar automatically. **Preview** opens the real renderer; return through
the shared Settings tab. See [DESIGN.md](DESIGN.md) for shared minimal presentation rules.
Wallpaper browsing never applies an image. OSD preview uses a synthetic value and
does not adjust hardware. Tab/Shift+Tab traverse controls, Space activates a card,
Left/Right choose adjacent cards, Ctrl+Tab/Ctrl+Shift+Tab change sections, and Escape
or an outside click closes the panel. Narrow panels use a section-cycle button.

## Choices

| Section | Choices |
| --- | --- |
| Top bar | Wallpaper pills (`current`), Enzo floating (`enzo`), MM-2103 flat (`mm2103`) |
| App launcher | Classic list (`current`), MM search (`mm2103`), App grid (`grid`) |
| Wallpapers | List + preview (`current`), Thumbnail gallery (`gallery`), Cover carousel (`carousel`) |
| Notifications | Classic center (`current`), Compact cards (`compact`), Application stacks (`stacked`) |
| Quick settings | Compact rows (`compact`), MM-style tiles (`tiles`) |
| Volume / brightness | Off (`off`), Horizontal OSD (`horizontal`), Vertical OSD (`vertical`) |
| Bar indicators | Sound, brightness and battery independently: Icon + %, Icon only, % only, Hidden |

Wallpaper colors remain the default for daily bars. The bar section also provides
an explicit upstream-palette alternative for the imported bars and MM-2103's
optional auto-hide/pinning. SF Pro Display stays shared: headings/bars Bold and
other text Regular, with separate icon fonts.

The **Bar indicators** section changes presentation only, across every profile.
Choices persist separately from the bar/OSD and are not reset by presets. Icons
show actual battery fill/charging, brightness level, and volume/mute/Bluetooth state;
exact values remain in tooltips. Existing visibility is preserved until you choose
another mode. See [INDICATORS.md](INDICATORS.md) for implementation and research.

### Optional presets

These intentionally change **all six components**, restore wallpaper colors and
turn auto-hide/pinning off. Individual cards can then customize any one component.

| Preset | Bar | Launcher | Wallpapers | Notifications | Controls | OSD |
| --- | --- | --- | --- | --- | --- | --- |
| Classic | Current | Classic list | List | Classic | Compact | Off |
| MM-style | MM-2103 | MM search | Carousel | Compact | Tiles | Horizontal |
| Grid + gallery | Enzo | Grid | Gallery | Stacked | Tiles | Vertical |

**Classic** also restores defaults; there is no duplicate reset button. Presets do not launch apps, apply wallpapers,
change hardware, reset notification history/DND, or replace any shared service.
These are local combinations of existing renderer adaptations, not complete
upstream desktop installations. See [FEATURE-COMPARISON.md](FEATURE-COMPARISON.md).

## Saving and isolation

Daily selections survive restart in Quickshell's shell-scoped state file,
`Quickshell.statePath("shell-preferences.json")`. `settings status` reports its exact
path. This is separate from app pins, launcher usage, update cache and notification
history. Saving layout preferences does **not** add on-disk notification history.

`Preferences.qml` validates a versioned, whitelisted partial JSON document against
`StyleCatalog.js`; omitted/invalid values use defaults, and malformed or unsupported
versions do not execute anything. Each selection finishes an atomic replacement
of a small file before returning, so an immediate restart cannot lose it. Presets
and multi-key updates batch their changes into one write. Save failures appear in the
panel without undoing the current live choice. Files are read on startup/reload,
not watched for external edits.

- `QUICKSHELL_COMPARE=1` disables **both reading and writing** saved choices,
  even with `QUICKSHELL_PERSIST_SETTINGS=1` or inherited notification server mode.
- Ordinary isolated preview/off-mode runners do not read/write daily choices.
- The checked daily helper enables persistence. An explicit
  `QUICKSHELL_PERSIST_SETTINGS=1` can enable it for isolated tests with a separate
  `QUICKSHELL_PREFERENCES=/absolute/test/path.json`; `0` disables it.
- A valid explicit `QUICKSHELL_PROFILE` takes precedence over the saved startup bar.
- Existing `profile`/`features` IPC changes also save in daily mode. Switching bars
  does not change feature settings; reselecting the active bar does not unpin it.

The selector itself never instantiates or replaces a notification backend. The
existing double comparison preview guard and PID-scoped daily IPC stay unchanged.
In legacy mode, `desktop.sh settings` explains that Quickshell must be activated;
it does not silently switch desktops.

## Stable IPC

Use the daily PID from `desktop.sh status`, not a random comparison process:

```bash
pid=$(~/.config/quickshell/desktop.sh status | jq -r '.session.shell.pid')
qs ipc --pid "$pid" call settings open
qs ipc --pid "$pid" call settings category notifications
qs ipc --pid "$pid" call settings set notifications stacked
qs ipc --pid "$pid" call settings set wallpaperColors true
qs ipc --pid "$pid" call settings preset mm2103
qs ipc --pid "$pid" call settings apply '{"launcher":"grid","wallpaper":"gallery"}'
qs ipc --pid "$pid" call settings status
qs ipc --pid "$pid" call settings close
```

`apply` rejects the entire update if any key/value is invalid. Allowed keys are the
six renderer sections, boolean `wallpaperColors`, `autoHide`, `pinned`, and
`volumeIndicator`, `brightnessIndicator`, `batteryIndicator` with values
`both`, `icon`, `percent`, `hidden`. There are no
shell-command, server-mode, font or hardware mutation fields. `preview` opens the
current section's real view or previews the OSD. `size 340 620` is a comparison-only
geometry test hook; `size 0 0` restores adaptive sizing.

## Online design references

Interaction inspiration, **not copied code or new runtime dependencies**:

- [Noctalia's Quickshell-era settings](https://docs.noctalia.dev/noctalia-shell-legacy/configuration/configure-noctalia/):
  categorized GUI settings, entry points in the bar/control center, immediate
  application and automatic saving. This is explicitly its legacy documentation,
  not a claim about its newer non-Quickshell implementation.
- [Caelestia configuration](https://github.com/caelestia-dots/shell#configuring):
  partial JSON configuration with defaults for omitted fields. We retain a tiny
  local schema rather than adopting its settings daemon, config or GPL code.
- [DMS/Dux repository](https://github.com/AvengeMedia/DankMaterialShell): settings
  accessible through both UI and IPC. The fetched upstream README currently brands
  itself Dux; existing pinned MIT renderer provenance remains in `vendor/`.

## Verification

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell_settings.py
python3 tests/verify_quickshell_indicators.py
QUICKSHELL_REDUCED_MOTION=1 python3 tests/verify_quickshell_settings.py
```

Headless tests cover save/restart, immediate graceful shutdown, invalid/partial
schemas, preview isolation and visible save errors. Preview integration covers all
cards, actual resolved SF text, independent choices, presets, rejected atomic
updates, narrow sizing, real-view/OSD previews, shared history/DND and unchanged
production D-Bus ownership. It stops only its own process. Optional `--screenshots`
captures your open desktop/apps and is not written into this repository.
