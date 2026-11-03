# Typography roles

SF Pro Display is the only text face used by Quickshell: **Bold for headings
and bars; Regular for all other UI and supporting copy**. Ubuntu Sans and Ubuntu
Mono are not Quickshell display fonts. Terminal/editor fonts remain independent.

| `textRole` | Face | Default weight | Intended use |
| --- | --- | --- | --- |
| `label` | SF Pro Display | Regular | Buttons, input, primary control/app labels, empty-state labels |
| `bar` | SF Pro Display | Bold | Every clock, workspace, title and status label in all three bars |
| `menu` | SF Pro Display | Regular | Tray/menu actions |
| `title` | SF Pro Display | Bold | Panel/section/group/notification headings |
| `display` | SF Pro Display | Regular | App names, selected wallpaper/media titles, prominent values |
| `body` | SF Pro Display | Regular | Descriptions, bodies, subtitles, timestamps, counts, placeholders, hints |
| `tooltip` | SF Pro Display | Regular | Hover explanations |
| `icon` | Symbols Nerd Font | Regular | Pictograms, never ordinary labels |

The original bar retains its explicitly separate JetBrains Nerd glyph face.
The emoji illustration uses system emoji fallback, not a Latin text role.
All workspace labels, including inactive ones, inherit the bold bar role.
Display values, app names, control labels and supporting copy remain regular.

## Authoring rules

`Theme.fontFamily`, `Theme.uiFont`, and default `ThemeText` / `ThemeButton` mean
**regular SF labels**. Supporting text opts into `body` or `tooltip` for semantic
classification and sizing, but uses the same SF family at regular weight.

Every runtime `ThemeText` declares a `textRole`. New bars must use `bar` regardless
of profile or source/wallpaper color selection. Do not let upstream platform font
choices, a system sans-serif alias, or the body face determine bar typography.
Use `Theme.fontForRole()` instead of duplicating role-to-face switches.

Override `font.pixelSize` or `font.weight` without replacing the family. Shared
text, buttons and icons bind font fields independently: assigning a whole default
font and then overriding just its size can reset a custom font property to system
Sans Serif. The icon-size regression is tested on the actual rendered glyph.
Keep Nerd glyphs separate from ordinary text wherever possible.

## Actual-item diagnostics

```bash
qs ipc --pid <pid> call shell theme
qs ipc --pid <pid> call bar geometry
qs ipc --pid <pid> call launcher status
qs ipc --pid <pid> call wallpaper status
qs ipc --pid <pid> call controls status
qs ipc --pid <pid> call notifications status
```

The theme report includes requested and resolved role probes. In addition, each
bar's `fonts` and the feature-status `fonts` arrays inspect actual visible rendered
items via `Theme.auditText()`: text sample, role, requested family, Qt-resolved
family/style/size/weight. A successful theme probe alone does not establish what
a clock, button content item, or delegate actually renders.

Desktop regressions check all visible bar text in **current**, **Enzo** and
**MM-2103**, before/after profile switches and in source/wallpaper color modes.
Feature checks apply the same role policy across every launcher, wallpaper and
notification view and both control layouts. Headless tests cover role switching,
size/weight overrides, default controls, rendered child labels/icons and explicit
weight overrides. Source guards reject unclassified runtime `ThemeText` uses
and any reintroduction of Ubuntu text faces into runtime Quickshell code.

## Waybar is separate

The always-running existing Waybar is not a Quickshell profile. Its stylesheet is
`.config/waybar/style.css`: primary labels/buttons explicitly request SF Pro
Display Bold, with Nerd icon fallback; tooltip copy requests Ubuntu Sans Regular.
Existing processes can retain their old stylesheet/font selection until reloaded.
A Waybar config/CSS reload does not install, autostart or switch to Quickshell.
Upstream files under `vendor/` are reference snapshots, not active configuration.
