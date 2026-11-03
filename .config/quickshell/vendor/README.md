# Pinned comparison sources

These are **selected, unmodified upstream source files**, not complete installed
shells. They document ports under `../modules/`. Upstream QML entry points are
never imported/executed; do not follow installation instructions in archived
READMEs. The one runtime data asset read here is MM's emoji catalog.

| Source | Revision | License |
| --- | --- | --- |
| [EnzoNotNice/quickshell-bar](https://github.com/EnzoNotNice/quickshell-bar) | `68d721985be796d2d9a344f73a8b3ae5495a738d` | [MIT](enzo/upstream/LICENSE) |
| [MM-2103/quickshell-bar](https://github.com/MM-2103/quickshell-bar) | `d31a94da14648439da05457d57b1648da9b3b18e` | [MIT](mm2103/upstream/LICENSE) |
| [Dux Shell](https://github.com/duxlabs-dev/dux-shell) | `6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0` | [MIT](dux/upstream/LICENSE) |

`sources.json` records **every** imported file and its SHA-256; offline tests check
both hashes and completeness. Preserve notices in derivative files. No fonts,
generated binaries, installers, GPL source or unclear-license documentation was
imported. `mm2103/upstream/launcher/emoji.json` is the upstream copy of GitHub's
MIT gemoji catalog; GitHub's copyright and complete license are retained in
[`mm2103/upstream/NOTICE`](mm2103/upstream/NOTICE). That NOTICE also mentions an
upstream Quickshell-reference document which we **do not** bundle.

## Runtime ports

- Enzo shell/workspaces/title/media → `modules/comparison/`: floating frame,
  animated workspace pills, title and native MPRIS adaptations.
- MM Bar/Workspaces/Theme → `modules/comparison/`: flat frame, chips, masked
  auto-hide and native palette option.
- MM Launcher/LauncherService → `modules/launcher/ListPicker.qml` and
  `services/LauncherData.qml`: multi-mode query routing, compact list, bounded
  numeric calculator and emoji catalog. Our original app filtering/usage policy
  remains; upstream's frecency formula is not substituted.
- Dux LauncherTile → `modules/launcher/GridPicker.qml`: icon tile/pin presentation
  with our pin persistence and shared app controller. Not the full Dux launcher.
- MM WallpaperPickerPopup → `modules/wallpaper/GalleryPicker.qml`: lazy gallery,
  without upstream's renderer, output/fill controls or apply-on-selection.
- Dux WallpaperCarousel → `modules/wallpaper/CarouselPicker.qml`: overlapping,
  index-driven slides using bounded local images and explicit Apply.
- MM NotificationCard/NotificationCenterPopup → `modules/notifications/CompactCard.qml`
  and compact `AlternativeCenter.qml`: shared record methods and plain text.
- Dux notification card/history-list presentation → stacked/time-filtered
  `AlternativeCenter.qml`. No alternate server, persistence or rich-text backend.
- MM TilesView/SlidersBlock → `modules/controls/`: supported actions and native
  volume/brightness; no unsupported radio/power toggles or settings bootstraps.
- MM Osd → `modules/osd/Osd.qml`: horizontal pill; vertical rendering is a local
  alternative observing the same services without extra polling.

No wholesale shared-widget SDK, theme writer, wallpaper daemon, search daemon or
notification backend is pulled into these ports. All source components have
been adapted; unmodified snapshot files are for provenance/review, not runtime.

To update: inspect a fixed upstream commit in a temporary clone, copy only the
selected source/data/license files, update commit and hashes together, review
ports, and run offline + baseline/bar/feature integration tests. Never fetch a
branch at startup. See [FEATURE-COMPARISON.md](../docs/FEATURE-COMPARISON.md).
