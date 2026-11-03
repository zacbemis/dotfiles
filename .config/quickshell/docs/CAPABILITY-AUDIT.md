# Existing desktop capability audit

Audited the repository **and live** settings before switching desktop ownership.
The live SwayNC config differed only in its update-button label (the update script
had replaced its symlink with a regular file). Its actual settings were backed up.
This audits the pre-migration desktop, not every optional upstream feature.
The old configuration is now archived on `snapshot/pre-quickshell-cleanup-2026-11-03`;
Quickshell is the only configured desktop UI.

## Active capabilities

| Existing source | Capability | Quickshell replacement / verification |
| --- | --- | --- |
| `waybar/config.jsonc` | Top bar, margin, centered 12-hour clock/date tooltip | Current bar; geometry, fonts and per-monitor layout checks |
| Waybar workspaces/taskbar | Activate workspaces, show window icons, active/urgent states | Native Hyprland workspace/toplevel models; profile lifecycle checks |
| Waybar tray | 15px icons, 8px gaps, network/Bluetooth menus | Native tray + GTK icon lookup; Wi-Fi/Bluetooth either click opens the same [native detail pages](CONNECTIVITY.md), including VPN/WireGuard configuration; explicit menu IPC retains themed DBus menus/submenus/keyboard navigation |
| Waybar brightness | Brightness display and time-dependent sun/moon | Existing backlight service + shared clock; no periodic command spawning |
| Waybar PulseAudio | Volume, 2% wheel steps, mute, headphones/Bluetooth indicators, ignore Easy Effects Sink | Native PipeWire state/actions, filtered output/input selection, available Bluetooth headphone/headset modes, same indicators |
| Waybar battery | Laptop battery, 40%/20% warning/critical states, capacity icons | Native UPower state and the same thresholds |
| Waybar notification module | Arch icon, unread/DND state, left-click center, right-click DND | Shared notification service, center and bar actions |
| `swaync/config.json` | Popup/center, actions/default action, images, grouping, clear, DND, keyboard access | Native notification backend; private-bus timeout/action/group/image tests; Tab/Enter/Delete/Escape support |
| SwayNC timeouts/filter | Normal 4s, low 2s, critical 6s; low-urgency Spotify muted | Preserved; explicit client timeouts/sticky notifications respected; private-bus regression |
| SwayNC body rendering | Basic emphasis and clickable links | Sanitized b/i/u + HTTP(S)/mailto links; no remote/local image HTML loading; correct advertised capabilities |
| SwayNC MPRIS | Track/player information and previous/play-pause/next | Notification center and quick settings; player cycling when multiple players exist; no album art (old image-size was 0) |
| SwayNC update button + startup script | Pacman/AUR/Flatpak count, explicit terminal upgrade, refresh afterwards | Read-only login check in daily mode; same explicit `yay -Syu; flatpak update` action; no legacy-config mutation |
| `rofi/config.rasi`, theme, launcher | Apps, icons, generic names/keywords/categories, normalized search, usage order | Shared desktop-entry controller; own usage/pins persisted (the transitional Rofi cache reader is removed) |
| Rofi terminal apps | Honor desktop `Terminal=true` and working directory | Explicit Kitty wrapper (Quickshell 0.3.1's native execute ignores Terminal); fixture terminal test |
| Rofi Run mode | PATH commands, command entry, run history | Run tab / `>` prefix in every launcher; bounded read-only PATH index; executes only on activation; own last-25 history |
| Rofi filebrowser | Directory navigation, folders-first/name sorting, opening files | Files tab / absolute or `~/` query; parent row; exact-path `xdg-open`, Unicode/newline/metacharacter fixture test |
| Rofi modes/navigation | App/Run/Files/Wallpaper switching, keyboard selection/cycling | Mode buttons, Ctrl+Tab / Ctrl+Shift+Tab / Shift+Left/Right; wrapping launcher selection |
| Rofi wallpaper scripts | Image discovery, thumbnails, select/apply | Shared JSON-safe scanner + list/gallery/carousel; exact-path existing setter; selection never applies; wheel/touchpad regression |
| Hyprland autostart/bindings | Start UI; Super+D apps, Super+W wallpapers, Super+R reload | `desktop.sh start/launcher/wallpaper/restart` in the Lua autostart/keybinding modules |
| Multimedia, lock, screenshots, desktop apps | wpctl, mic mute, brightnessctl, playerctl, Hyprlock/idle, screenshots, Thunar/browser, wallpaper daemon | Commands intentionally unchanged; observed by native shell services, not reimplemented as competing daemons |
| Pywal/Matugen | Wallpaper-derived desktop colors and app reloads | Same generators/setter; canonical `quickshell/colors.css`; watched read-only without UI reload hooks |

## Not active in the old configuration

- `volume` / `show-per-app` had widget settings but was **not in SwayNC's widgets
  list**. No per-app mixer was part of the active center. A later explicit request
  added native per-playback-stream volume/mute controls to Quickshell's Sound panel.
- SSH settings were present, but SSH was **not in Rofi's enabled modi**.
- SwayNC's `example-script` was the stock successful `echo` placeholder, not a
  user automation workflow. It is not run for every incoming notification.
- Clipboard capture, online wallpaper services, wallpaper rotation/output modes,
  inline replies and on-disk notification-history storage were not configured.

## Deliberate differences / safety

- Existing SwayNC in-memory notifications/actions cannot be transferred to another
  D-Bus server. Handoff starts fresh history; new notifications go to Quickshell.
  Quickshell history is in-memory/bounded (100 records, five visible popups).
- Only safe body markup/links are enabled; arbitrary Pango/HTML attributes, inline
  image HTML and unsafe URL schemes are not executed or fetched.
- Files/command indexes are bounded and read-only. Command/file activation is
  explicit. The tests use a harmless command, stub opener, stub terminal and stub
  wallpaper setter—not real applications, updates or hardware changes.
- Physical multi-monitor hotplug and every hardware/device variation remain
  manual checks; only the current single-monitor laptop is available here.
- Preview/comparison remains preview-only and never owns the live notification
  name, even while the daily Quickshell server is running.

## Completed phase-out

Waybar/SwayNC/Rofi configs, installer options, layer rules, theme outputs and
in-session fallback commands have been removed. The local notification activation
entry starts Quickshell. Existing installed packages and caches are not deleted;
the complete previous repo is on `snapshot/pre-quickshell-cleanup-2026-11-03`.

Pre-cutover live/repository backup, if still present:
`~/.local/state/dotfiles-quickshell-migration/20261023-145811/` (with manifest).
See [MIGRATION.md](MIGRATION.md) for session ownership, logs and deliberate Git-based
recovery. The wallpaper/color pipeline, terminal setup and non-UI desktop
keybindings remain in place.
