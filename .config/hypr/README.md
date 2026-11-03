# Hyprland configuration

The Lua entrypoint and every module were reviewed against installed Hyprland
0.56.2. `Hyprland --verify-config` and the live compositor's `configerrors` must
both remain clean. Hyprlock and Hypridle still use their own `.conf` files.

## Floating dialogs and browser subwindows

`hyprmodules/windowrules.lua` keeps normal browser windows tiled, while floating
and centering:

- Modal dialogs reported to Hyprland (the 0.56.2 modal matcher is XWayland-only).
- Known file-dialog initial titles and GTK/Hyprland/KDE portal windows.
- Chromium-family popups initially titled `about:blank`, scoped to browser app IDs.
- Browser picture-in-picture and detached developer tools.

Wayland windows with a transient parent or fixed-size constraints already float
through Hyprland's built-in policy. No nonexistent `has_parent`/`window_role` rule
fields or catch-all browser floating rules are used. The XWayland empty-class
no-focus workaround is retained for drag surfaces.

A real Helium `window.open()` test reproduced the problem: its child advertised
neither a parent nor an xdg tag, and mapped as `about:blank - Helium` before changing
title. Matching the **initial** title fixes that case without making a normal tab
float when its page title changes. A deliberately opened standalone `about:blank`
window also matches this narrowly scoped fallback.

A popup that maps directly with an ordinary nonblank webpage title and no parent
hint can be indistinguishable from a normal browser window. Do not float every
browser window to hide this: inspect that specific popup's `initialClass` and
`initialTitle` with `hyprctl clients -j` and add a narrowly scoped rule if needed.
These floating/centering effects are applied at map time, so reopen existing
dialogs after changing them.
`Super+F` remains the manual floating toggle.

## Idle, lock and screen power

The idle daemon uses `scripts/display-power.sh`, which calls the typed Lua DPMS
dispatcher. The old `hyprctl dispatch dpms on/off` form fails with the Lua provider.
Only `on` and `off` are accepted by the helper. Lock commands check for an existing
Hyprlock instance; the lockscreen font family no longer includes an accidental
numeric suffix.

Existing timing preferences are unchanged: dim at 150 seconds, lock at 300,
display off at 330, suspend at 1800, and **power off at 3600 seconds**. The last two
are deliberate existing commands, not new behavior. The brightness save/restore
and Quickshell OSD-origin tracking are preserved. Restart Hypridle after editing
its config; a compositor reload alone does not restart the idle daemon.

## Other reviewed settings

- The internal display supports the configured 2880×1800 at 60 Hz; auto scale is
  currently 2. A different/external monitor may need its own monitor rule.
- Lua dispatchers, workspace/mouse bindings, wallpaper/color hooks and Quickshell
  layer rules validate. Autostart remains a startup event, not a reload event.
- Existing opacity, focus behavior, keyboard mapping, touchpad preferences,
  wallpaper generation, suspend/shutdown policy and night-light times are retained.
- Media-key bindings require **playerctl**. It is declared in `install.sh`, but was
  missing on the audited machine. Install it separately:

  ```bash
  sudo pacman -S --needed playerctl
  ```

## Verification

```bash
python3 -m unittest discover -s tests -v
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua
hyprctl configerrors
# Live test: temporary browser profile and local HTML; briefly opens two windows.
python3 tests/verify_hyprland_windows.py
```

Offline tests evaluate the real Lua rules against dialog, utility and ordinary
browser fixtures. The live test requires an unlocked session and installed Helium;
it verifies that a normal window tiles while its blank-initial popup floats after
a title change. It stops only the test browser and attempts to restore focus.
No login, private profile, external website, screenshot or device operation is used.
Idle tests mock DPMS, brightness and application commands, or parse against a
nonexistent Wayland display; they never turn off or lock the live desktop.

References: [window-rule documentation](https://wiki.hypr.land/configuring/core/rules/window-rules/)
and [0.56.2 built-in transient classification](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/XWaylandManager.cpp).
