# Pinned comparison sources

Selected, unmodified MIT source snapshots used to develop the local renderer ports.
These are not complete shells; archived README installation instructions do not apply.

| Source | Revision | License |
| --- | --- | --- |
| [EnzoNotNice/quickshell-bar](https://github.com/EnzoNotNice/quickshell-bar) | `68d721985be796d2d9a344f73a8b3ae5495a738d` | [MIT](enzo/upstream/LICENSE) |
| [MM-2103/quickshell-bar](https://github.com/MM-2103/quickshell-bar) | `d31a94da14648439da05457d57b1648da9b3b18e` | [MIT](mm2103/upstream/LICENSE) |
| [Dux Shell](https://github.com/duxlabs-dev/dux-shell) | `6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0` | [MIT](dux/upstream/LICENSE) |

## Adapted features

- **Enzo:** floating bar, workspaces, window title and media presentation.
- **MM:** flat bar, list launcher, calculator/emoji search, wallpaper gallery, notifications, controls and OSD.
- **Dux:** grid launcher, wallpaper carousel and stacked notification history.

Ports share the local services, theme and wallpaper pipeline; upstream QML is never executed.
The only runtime asset here is MM's emoji catalog, with its [gemoji notice](mm2103/upstream/NOTICE).

`sources.json` records file hashes checked by offline tests. Keep snapshots and notices intact.
To update, review a fixed upstream commit, update selected files/revision/hashes together and test the ports.
See [feature comparison](../docs/FEATURE-COMPARISON.md).
