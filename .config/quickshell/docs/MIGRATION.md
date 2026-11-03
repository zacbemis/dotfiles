# Daily Quickshell migration

The active capabilities of the live Waybar/SwayNC/Rofi desktop were audited and
ported before changing ownership. See [CAPABILITY-AUDIT.md](CAPABILITY-AUDIT.md)
for the exact mapping, dormant settings, deliberate differences and test coverage.
The config root is `.config/quickshell/`; it is now the daily desktop shell.

## Startup and controls

Both Hyprland config variants call `~/.config/quickshell/desktop.sh start`.
Super+D opens/toggles the app launcher, Super+W the wallpaper picker and Super+R
restarts the selected daily stack. Super+comma opens Settings. The
[shared panel row](NAVIGATION.md) supports Alt+H/L across Apps/Run/Files/Wallpapers/
Settings without resizing; notifications remain separate. Other desktop/hardware
bindings are unchanged.
The session helper serializes commands and supervises one daily Quickshell process;
IPC always targets its recorded PID, not whichever comparison instance happens
to exist. It retries crashes with a bounded backoff and checks PID start times.

```bash
~/.config/quickshell/desktop.sh status
~/.config/quickshell/desktop.sh start       # idempotent, no duplicate bars
~/.config/quickshell/desktop.sh activate    # checked handoff / return from rollback
~/.config/quickshell/desktop.sh restart
~/.config/quickshell/desktop.sh launcher
~/.config/quickshell/desktop.sh run
~/.config/quickshell/desktop.sh files
~/.config/quickshell/desktop.sh wallpaper
~/.config/quickshell/desktop.sh notifications
~/.config/quickshell/desktop.sh controls
~/.config/quickshell/desktop.sh settings
```

`activate` validates dependencies and refuses to evict an unrelated notification
server. It gracefully stops same-session SwayNC, starts Quickshell, verifies its
IPC **and ownership of org.freedesktop.Notifications**, and only then removes the
old Waybar. Failure restores the legacy stack instead of leaving no desktop UI.
Existing SwayNC in-memory history cannot be transferred across server ownership.

## Rollback

```bash
~/.config/quickshell/desktop.sh legacy
```

This stops only the recorded daily Quickshell instance, restarts the retained
Waybar/SwayNC configs and persists legacy mode. The **same** Hyprland keybindings
then dispatch to Rofi/the legacy reload path. Login startup and palette hooks
honor the saved mode. Return with `desktop.sh activate`.

State/logs: `~/.local/state/quickshell-desktop/`; PID/locks are in
`$XDG_RUNTIME_DIR/quickshell-desktop/`. Desktop mode in the state directory is
separate from the [component selector](SETTINGS.md)'s shell-scoped layout preferences.
Daily bar/feature choices now survive restart; comparison choices remain transient
and never read/write daily preferences. Configuration backups are under
`~/.local/state/dotfiles-quickshell-migration/`.

Legacy packages are not uninstalled during migration. New installs use Quickshell
by default; `INSTALL_LEGACY_UI=1 ./install.sh` also installs Waybar/Rofi/SwayNC for
rollback. The old config files and generated rollback palettes remain available.

## Notifications, updates and themes

The daily helper enables server mode and performs the old read-only login update
check. Opening a panel does not run upgrades; terminal upgrades remain explicit.
Restart/recovery suppresses repeated login checks. Update polling is demand-driven
while the center/controls are open. Counts/errors never rewrite old SwayNC JSON.

Normal `run.sh` remains an isolated development runner (notifications off unless
requested); `run.sh --preview` / `compare.sh` always preserve live desktop ownership.
The comparison's double preview guard remains in both wrapper and service.
Notification-server regressions run on a private D-Bus session.

Pywal/Matugen still set the wallpaper and generate all desktop app colors. They
now publish `~/.config/quickshell/colors.css` for Quickshell to watch read-only.
Legacy generated palettes remain for rollback, but hooks never auto-start retired
daemons. Terminal/Neovim/GTK/Hyprlock color reloads and the exact-path wallpaper
setter remain unchanged. Local D-Bus activation routes notification startup to
the daily helper and masks automatic SwayNC control-center activation; explicit
legacy mode starts SwayNC normally.

## Verification and limits

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_features.py
python3 tests/verify_quickshell_settings.py
```

Tests stop only their own instances; they do not stop the recorded daily shell.
New regressions cover safe ownership handoff/rollback/refusal, inert Run/file
indexes, terminal desktop entries, exact-path file opening, basic safe notification
markup, muted Spotify, actual fonts, and image/touchpad carousel events.
Multi-monitor hotplug and every hardware/device permutation still require manual
validation. History is in-memory, not an unimplemented persistence promise.
