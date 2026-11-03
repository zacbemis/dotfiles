# Network and Bluetooth controls

Open the bar gear → **Network / Bluetooth**, or left- or right-click the corresponding
tray icon. Both clicks open the same native panel. Network has **Wi-Fi · VPN**
sub-tabs, separate from the shared launcher tabs. Both compact/tile quick settings
use the same controls window; Back returns to the overview without mapping another
popup. Escape/outside-click closes the detail directly: its page and geometry
remain until the fade finishes, rather than briefly showing the overview. Only
Back returns to the parent page (Quick settings, or the source page for Audio).
Sensitive inputs and pending pairing/discovery
are cleared/cancelled immediately; detail content unloads once hidden. No bar
spacing was changed.

## Wi-Fi

- NetworkManager's cached networks, connected/saved first. Signal is shown by the
  icon (exact percentage in its tooltip). **Reload** is an icon at the bottom right;
  opening or selecting a row never requests a radio scan or connection change.
- Per-adapter selection when more than one Wi-Fi device exists.
- Wi-Fi radio on/off, connect/disconnect, and confirmed forgetting of the selected
  saved profile. The radio is a toggle pill at the right of **Wi-Fi · VPN** when
  Wi-Fi is selected; it is hidden on VPN, where it must not imply a global VPN
  switch. These actions target Wi-Fi only, not global networking/VPN state.
- New WPA/WPA2/WPA3-personal networks use a protected in-panel password field.
  Open and OWE networks do not request a password. Existing compatible saved
  profiles activate through NetworkManager and its existing secret agents.
- Device-state progress distinguishes connecting, authentication and address
  configuration. Authentication failures offer corrected-password retry; DHCP/IP
  failures do not misleadingly demand a new password. The row options also expose
  **Change password** and a direct **Configure** action for saved networks.
- **Retry** updates only the selected personal profile's PSK, preserving its UUID,
  other settings and secret-storage flags. A profile version check rejects
  concurrent edits. It then requests activation; profiles are never deleted as
  password-recovery strategy. Enterprise credentials remain in the standard editor.
- There is no favourites/saved-networks toolbar button. Out-of-range profiles and
  autoconnect/IP/DNS are managed through the **Network settings…** footer link.
  Saved networks in range still have Configure, Change password and confirmed
  Forget under the selected row's Options.
- Wi-Fi submission releases the panel so existing credential/polkit agents are
  not trapped underneath it. Reopening shows current progress or retained errors.
- **Network settings…** opens the retained `nm-connection-editor` after releasing the panel's
  keyboard focus. Use it for enterprise/EAP, WEP, hidden SSIDs, changing a saved
  password, IP/DNS and other advanced profile settings. Failed connections never
  silently delete or rewrite profiles; a corrected password is saved only on Retry.

### Internet and captive portals

The Wi-Fi page uses NetworkManager's **cached system-wide** connectivity. A connected
network only gets an extra banner when sign-in is required or access is limited,
absent or unknown; normal internet availability adds no redundant status line.
This may reflect Ethernet/VPN routes. Opening never requests an HTTP probe.
**Check connection** explicitly refreshes unknown/limited connectivity.
**Open login page** releases the panel and opens NetworkManager's configured check
URI in the browser, allowing a captive portal to redirect it. Only HTTP(S) URLs
without credentials/control characters are accepted. Check, browser launch and
editing are disabled in read-only previews; fixture checks never access a network.

## VPN

- The **VPN** sub-tab lists saved NetworkManager VPN and WireGuard profiles, with
  connected/connecting state and explicit connect/disconnect (or connecting cancel).
  Only the selected tunnel is activated/deactivated; the base Wi-Fi/Ethernet
  connection is never a disconnect target.
- Select a profile to reveal Connect/Disconnect and Configure; the unselected list
  stays quiet. **Add VPN** and **Add WireGuard** are footer actions. These and each
  profile's **Configure** open the standard
  `nm-connection-editor` creation/edit form. Configuration and provider-specific
  credentials stay with NetworkManager and its plugins, not a second shell settings
  database. VPN providers require their NetworkManager plugin; WireGuard is built in.
- Connecting releases the panel so existing NetworkManager authentication agents
  can show their normal credential dialogs. Reopen Network → VPN to inspect state
  or cancel a pending activation. Closing does not cancel an already-submitted VPN
  connection. Asynchronous errors remain available when reopening the panel.
- Separately managed tunnels such as Tailscale are not misrepresented as
  NetworkManager VPN profiles. Opening the tab never connects or disconnects anything.

## Bluetooth

- A matching power toggle pill sits to the right of the Bluetooth heading.
  Adapter selection; connected/paired devices first, with battery when BlueZ
  provides it. The bottom-right reload icon starts discovery for up to 60 seconds;
  it becomes a stop icon while this helper owns discovery. Leaving the detail view
  stops only this helper's own session.
- Pair/connect/disconnect, explicit trust/untrust, and confirmed device removal.
- Device options include **Rename**. A blocked device offers **Unblock** rather than
  silently trying to connect; unblocking does not pair or connect it. Names are
  UTF-8, size-limited and reject control characters.
- BlueZ numeric comparison, PIN/passkey entry and displayed keyboard codes are
  handled in-panel. Closing/back cancels a pending pairing request.
- The helper registers an agent only for its own initiated pairing and does **not**
  request default-agent ownership or displace blueman's agent. Agent calls must
  come from BlueZ and match the currently requested device.
- The footer speaker icon opens audio routing/headset modes; Back returns to Bluetooth.
  **Bluetooth settings…** opens `blueman-manager`. Full codec tweaking, tethering, file transfers
  and discoverability/server features remain outside this small UI.

## Sound, devices and applications

Click the bar's sound icon (again to close), the **Sound** button in Quick
settings, or Bluetooth's footer speaker icon. The same native **Sound** dropdown
contains sound/microphone volume and separate mute buttons. Expand the current
device name to select an output or microphone via native PipeWire metadata;
Easy Effects Sink and monitor sources are not offered as ordinary device choices.
**Applications** reveals individual playback-stream volume and mute controls;
only apps with an audio stream appear, with an explicit empty state otherwise.
Changes target the exact live node ID/serial; stale rows cannot change another
application after ID reuse. Volume changes do not implicitly unmute. Microphone
recording streams are not mistaken for playback apps.
Bluetooth cards expose their available **High quality** / **Headset + microphone**
modes, preserving the current codec when already in a mode. Changing a profile may
recreate devices, so models follow PipeWire/BlueZ changes rather than keeping stale
node references. No route/profile is selected automatically by opening the page.

`AudioService.qml` uses the native Quickshell PipeWire API for node discovery and
routing. The installed API lacks card profiles, so `scripts/audio-profiles.py`
uses bounded `pactl` JSON reads and a fixed-argv, no-shell profile command. Selection
revalidates the exact Bluetooth card index **and name** plus profile availability;
it cannot switch a wired card or a recycled index belonging to another card.
Reads are demand/event-driven, not periodic shell polling. `libpulse` supplies pactl.
Comparison guards block native volume/mute/route writes and the helper's profile writes.
Offline fixtures handle selections and mixer changes entirely in memory and never
start that helper. Stable stream keys retain slider pointer grabs during volume
echoes. Stream tracking survives the outgoing fade, then releases hidden resources.
`tests/test_quickshell_sound.py` exercises devices, both mutes, independent app
levels/mutes, stale/invalid targets, read-only guards and delegate identity offscreen.

## Button and toggle affordances

Windows/macOS-inspired **progressive disclosure** keeps these panels quiet:

- Compact **40×24** radio pills (previously 54×32), in the same aligned positions.
- Select a network/device row to reveal its primary action; Options reveals the
  less-common configuration, rename, trust and forget actions. Selection itself
  never connects/disconnects. Connected rows have a checkmark.
- No favourites button or permanent top action toolbar. Settings and the reload
  icon live in the bottom footer; reload has a tooltip, not a “Scan” label.
- Audio choices are quiet selectable rows with checkmarks, not repeated boxed
  buttons. VPN actions similarly appear only for the selected profile.
- Explicit connection/confirmation actions retain visible filled button bounds;
  footer links and secondary actions are quieter. Panels size to content with a
  capped, scrollable list and retain their page/geometry through fade-out.

This is scoped to controls, not bars or unrelated panels. Pills and rows support
keyboard/mouse input and accessibility. Pills request changes without optimistically
changing their value: the backend remains authoritative after a rejected request.
Disabled/read-only controls cannot mutate state; reduced motion removes animation.

## State, privacy and permissions

`services/ConnectivityService.qml` owns the UI state and one demand-started child
process, `scripts/connectivity.py`. It uses **libnm** and **BlueZ D-Bus**, not shell
pipelines or parsed/localized CLI text. Native notifications update cached state;
there is no periodic command polling. Missing adapters/services, hardware blocks,
permission failures, busy requests and timeouts produce bounded visible errors.

Actions use a whitelisted JSON-lines protocol over the child's private stdin.
Passphrases/PINs never appear in argv, temporary files, shell commands, public IPC
status or the rendered-text diagnostic audit. Protected input is cleared on submit,
cancel or page destruction. NetworkManager itself owns any newly saved Wi-Fi
credentials; Quickshell does not keep another password database. Standard system
NetworkManager/BlueZ/polkit policy still controls authorization.

The existing services and applets remain installed. No service enable/disable,
connection switch, scan, pairing or radio power change is performed on shell startup.
An already-submitted Wi-Fi connection request may complete after closing the panel.

## Preview and tests

Normal comparison sessions have two read-only guards: QML refuses mutation and
the Python helper independently enforces `QUICKSHELL_COMPARE=1`. It may read cached
system state, but cannot scan, probe, toggle, connect, pair, rename, unblock, trust,
forget or change audio routes/profiles. Editor/browser launches are also disabled.

`QUICKSHELL_CONNECTIVITY_FIXTURE=/absolute/test.json` selects a wholly offline
backend which never constructs libnm/BlueZ clients. The test-only activation IPC is
accepted only with an explicit fixture **and** comparison mode. Fixture mutations
stay in memory; the fixture file is never changed. No password-taking mutation IPC
is exported to normal users.

Read-only diagnostics:

```bash
qs ipc --pid "$pid" call connectivity open wifi
qs ipc --pid "$pid" call connectivity open bluetooth
qs ipc --pid "$pid" call connectivity open vpn
qs ipc --pid "$pid" call connectivity open audio
qs ipc --pid "$pid" call connectivity audio_status
qs ipc --pid "$pid" call connectivity back
qs ipc --pid "$pid" call connectivity status
python3 ~/.config/quickshell/scripts/connectivity.py --snapshot
```

The snapshot includes local SSIDs/device names; do not publish it unredacted.
`tray open nm-applet` / `tray open blueman` open the same native panels as either
physical click. Explicit `tray menu nm-applet` / `tray menu blueman` retain exported
legacy menus for diagnostics. `connectivity click nm-applet left|right` exercises
the shared native click route without changing a connection.

```bash
python3 -m unittest discover -s tests -v
python3 tests/verify_quickshell_connectivity.py
QUICKSHELL_REDUCED_MOTION=1 python3 tests/verify_quickshell_connectivity.py
```

Fixtures cover password validation and redaction, exact targets, read-only refusal,
agent tokens/PIN/passkey/confirmation/cancel, blocked devices, trust/forget, adapter
errors, JSON transport, both UI layouts, back navigation, matching left/right
routing, VPN/WireGuard controls, tunnel-only activation/deactivation and stable
native surface. Exit-frame checks cover retained detail content/geometry, immediate
logical cleanup, hidden loader release and rapid gear/tray reopening in both layouts.
Pill checks cover aligned placement, fixture on/off, hidden VPN switches, real Qt
mouse/Space delivery, accessibility state, rejected requests and disabled input.
Row checks cover selection without mutations, progressive actions, removed saved
controls, footer reload geometry and wholly offline reload/start/stop actions.
Both pill states and action buttons are contrast-checked across synthetic palettes.
Additional checks cover corrected-password serialization and preserved secret flags,
profile version guards, out-of-range profiles, safe portal URLs/no probe on open,
rename/unblock, output/input selection, available headset modes, card identity and
read-only routing/profile guards. Real PipeWire discovery was also checked read-only,
with unchanged defaults, card profiles and notification ownership.
Real-adapter validation so far is **read-only cached discovery**, not a claimed
physical connection/pairing certification. Enterprise credentials, hardware-specific
pairing, polkit prompts, real VPN activation/provider forms, Bluetooth audio mode
changes and reconnect-after-suspend behavior still need manual testing.

## Design research / primary sources

Interaction references, not imported daemons/settings code:

- [Windows Wi-Fi quick settings](https://support.microsoft.com/en-us/windows/experience/connectivity-networking/connect-to-a-wi-fi-network-in-windows):
  select a network, then Connect; Microsoft explicitly places manual refresh in the
  lower right. Used for footer reload and selection-before-action interaction.
- [macOS Wi-Fi status menu](https://support.apple.com/guide/mac-help/use-the-wi-fi-status-menu-mchlfad426fa/mac):
  simple network lists and a compact radio control, with detailed configuration
  outside the transient list. Used for restrained rows and settings delegation.
  These are interaction ideas only; no proprietary assets or code copied.

- [DMS/Dux NetworkDetail](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/ControlCenter/Details/NetworkDetail.qml)
  and [BluetoothDetail](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/ControlCenter/Details/BluetoothDetail.qml):
  detail pages, adapters, explicit scans, connected devices, password/pairing flows.
  Inspected retained MIT reference commit `6f36e49c68a9ed7c86ab8d7cc9c5b3bd14270fd0`
  and current upstream pages. We do not install DMS/Dux's backend.
- [Caelestia Nmcli](https://github.com/caelestia-dots/shell/blob/main/services/Nmcli.qml)
  and [BluetoothPage](https://github.com/caelestia-dots/shell/blob/main/modules/nexus/pages/BluetoothPage.qml):
  separate connection state, connected/saved-first lists and restrained controls.
  Inspected reference commit `0b0beb520a36f6972999c2afc97b311a27ba87f0`.
  No GPL implementation code copied. Our bridge also avoids credentials in nmcli argv.
- [Noctalia legacy system controls](https://docs.noctalia.dev/noctalia-shell-legacy/getting-started/keybinds/system-controls/):
  dedicated network/Bluetooth detail entry points, not just opaque tray delegation.
- [libnm RemoteConnection](https://networkmanager.dev/docs/libnm/latest/NMRemoteConnection.html)
  and [Settings.Connection.Update2](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.Settings.Connection.html):
  explicit credential updates, secret-storage flags and concurrent profile versions.
- [libnm Client API](https://networkmanager.dev/docs/libnm/latest/NMClient.html),
  [BlueZ Agent API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst)
  and [Device API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst):
  authoritative transport/agent behavior. Quickshell's installed Bluetooth API has
  no complete pairing agent, so a direct BlueZ agent is provided by the helper.
