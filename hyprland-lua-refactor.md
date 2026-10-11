# Hyprland Lua refactor

## Baseline

- At research time Hyprland `0.56.2` used `configProvider: hyprlang`; the live session now uses the verified Lua entrypoint below.
- Legacy entrypoint: `~/.config/hypr/hyprland.conf` -> `dotfiles/.config/hypr/hyprland.conf`.
- The legacy entrypoint sources generated `colors/colors.conf` plus seven modules: monitors, autostart, environment variables, look-and-feel, input, keybindings, and window rules.
- `hyprctl configerrors` was empty before and after the migration.
- `hypridle.conf`, `hyprlock.conf`, the Pywal/Matugen scripts, and unrelated Quickshell work are out of scope.

## Target architecture

Use native Hyprland Lua (`~/.config/hypr/hyprland.lua`) with `require()`d Lua modules. Keep every existing `.conf` file unchanged as the rollback configuration. The misspelled `enviromentvars` module name may be retained to avoid an unrelated rename.

Suggested layout:

```text
.config/hypr/hyprland.lua
.config/hypr/hyprmodules/{monitors,autostart,enviromentvars,lookandfeel,input,keybindings,windowrules}.lua
.config/hypr/colors/colors.lua
```

Lua modules have separate lexical scopes: `$primary` converted to a local in one module is not visible in another. The color module therefore returns a table. The implementation uses a small Lua bridge that reads the existing generated `colors.conf`; this preserves both current Pywal and Matugen pipelines. A future optimization could generate a Lua table directly, but must retain the `.conf` output for `hyprlock` and legacy rollback.

The Lua entrypoint should require modules in the old source order. Hyprland’s Lua loader supports `require("module.name")` relative to the config directory.

## Required translations/review

- `source = ...` becomes `require(...)`; `.conf` files cannot be sourced by Lua.
- `exec-once` becomes `hl.on("hyprland.start", function() ... hl.exec_cmd(...) end)`.
- `env` becomes `hl.env(name, value)`; environment values should be strings.
- `monitor` becomes `hl.monitor({ output = "", mode = "2880x1800@60", position = "auto", scale = "auto" })`.
- `bind` dispatchers become typed `hl.dsp.*` calls. Preserve `bindel` as `{ locked = true, repeating = true }`, `bindl` as `{ locked = true }`, and add `{ mouse = true }` to both mouse drag/resize binds.
- Use typed direction values (`left/right/up/down`; the installed version also accepts legacy short values).
- `general.col.active_border = $primary $secondary 45deg` must become `{ colors = { palette.primary, palette.secondary }, angle = 45 }`.
- Convert animation curves with `hl.curve(name, { type = "bezier", points = {{x1,y1},{x2,y2}} })` and animations with `hl.animation({ leaf=..., enabled=..., speed=..., bezier=..., style=... })`. Preserve the later duplicate `easeInOutCirc` definition because it is the effective legacy value.
- Window-rule match fields become `match = { class = ..., title = ..., xwayland = true, float = true, fullscreen = false, pin = false }`; effects remain fields in the rule table.
- Layer rules require separate `hl.layer_rule({ match = { namespace = ... }, effect = ... })` calls. Preserve order and translate `blur`, `ignore_alpha`, `dim_around`, and `animation` directly. Do not let a converter turn `match:namespace ^(waybar)$, blur 1` into `match = { namespace = "blur 1" }`.

## Converter/validator findings

`hyprlang2lua` is useful as a scaffold. On the assembled current config it reported `240 translated`, `41 passthrough`, `10 flagged`, and `96.0%` coverage. Its output passed `luac -p` only after syntax generation, but raw output still had the active-border representation wrong and all ten layer rules required manual correction. Another converter tested (`hyprconf2lua`) emitted invalid Lua for `class.*` on this config. No converter is authoritative.

Validation gates, in order:

```sh
luac -p <each Lua file>
hyprvalidate check <candidate entrypoint> --stub /usr/share/hypr/stubs/hl.meta.lua
Hyprland --verify-config --config <candidate>/hyprland.lua
```

`luac` checks syntax only; `hyprvalidate` is static/schema validation; `Hyprland --verify-config` is the authoritative load/API check but cannot prove interactive behavior. After cutover, also run `hyprctl configerrors` and manually test bindings, monitor mode, rules, layer effects, autostart, wallpaper reloads, and color changes.

## Implementation status

- Added and deployed `hyprland.lua`, seven Lua modules, and `hyprmodules/colors.lua`.
- `hyprmodules/colors.lua` reads the existing generated `colors.conf`, retaining compatibility with Pywal, Matugen, and hyprlock.
- Unlike legacy `source`, Lua's `io.open()` does not register `colors.conf` for automatic reloads. Pywal's `wal-post.sh` explicitly runs `hyprctl reload` after linking the generated palette; Matugen's Hyprland template does the same in its `post_hook` after writing it. A manual reload was verified to replace stale border colors with the current palette.
- The running compositor was reloaded successfully. `Hyprland --verify-config` passed; `luac -p` passed; 58 bindings and the active-border gradient were observed through `hyprctl`.
- `hyprland.start` is a startup event, so it does not rerun on `hyprctl reload`; Waybar must already be running or be started manually after a reload.
- The initial migration left legacy `.conf` files unchanged. The follow-up fixes below also update legacy autostart so rollback uses the same color restoration logic. The repository still contains unrelated dirty-tree changes; do not mix them into this migration.

## Follow-up fixes

- The color bridge supplies fallback border colors when the generated palette is absent, incomplete, or malformed. A fresh installation or deleted cache no longer prevents Lua configuration loading.
- Pywal16's post-hook and Matugen's `reload-hyprland.sh` record the last generator in `${XDG_STATE_HOME:-$HOME/.local/state}/hypr/color-generator` before reloading Hyprland.
- Both autostart variants call `restore-colors.sh`. Matugen's existing output is preserved rather than overwritten with Pywal's cache; missing output is regenerated from `current_wallpaper`. Pywal restores its cache or regenerates it if deleted. Installations without a generator marker retain the previous Pywal default.
- Regression tests: `python3 tests/test_hyprland.py -v`. Tests use isolated homes and mock application reloads.

## Rollback

When both files exist, Hyprland selects `hyprland.lua` by default; it does not merge or automatically fall back to `hyprland.conf`. Keep the old entrypoint/modules and generated `colors.conf` intact. Relaunch with an explicit fallback when needed:

```sh
Hyprland --config ~/.config/hypr/hyprland.conf
```

## References

- Local authoritative API: `/usr/share/hypr/hyprland.lua`, `/usr/share/hypr/stubs/hl.meta.lua`.
- [Hyprland Lua configuration](https://wiki.hypr.land/Configuring/Start/)
- [Official example](https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua)
- [Autostart](https://wiki.hypr.land/configuring/core/autostart/)
- [Dispatchers](https://wiki.hypr.land/configuring/core/dispatchers/)
- [Window/layer rules](https://wiki.hypr.land/configuring/core/rules/layer-rules/)
- [hyprlang2lua](https://github.com/EIonTusk/hyprlang2lua)
