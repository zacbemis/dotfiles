#!/usr/bin/env python3
"""Private JSON-lines libnm/BlueZ bridge. No shell, credential argv or credential files.

Reads cached state on startup; scanning and mutations require explicit commands.
Comparison sessions are read-only unless using an entirely offline JSON fixture.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import re
import sys
import uuid
from urllib.parse import urlsplit

import gi
from gi.repository import Gio, GLib

AGENT_XML = '''<node><interface name="org.bluez.Agent1">
<method name="Release"/><method name="Cancel"/>
<method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
<method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
<method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
<method name="RequestAuthorization"><arg type="o" direction="in"/></method>
<method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>'''


def validate(command):
    if not isinstance(command, dict):
        raise ValueError("Invalid request")
    action = command.get("action")
    fields = {
        "refresh": (), "panel.close": (), "cancel": (),
        "wifi.adapter": ("target",), "wifi.power": ("enabled",), "wifi.scan": (),
        "wifi.connect": ("target",), "wifi.disconnect": ("target",), "wifi.forget": ("target",),
        "wifi.retry": ("target", "password"), "wifi.profile.forget": ("target",), "network.check": (),
        "bluetooth.adapter": ("target",), "bluetooth.power": ("enabled",), "bluetooth.scan": ("enabled",),
        "bluetooth.connect": ("target",), "bluetooth.disconnect": ("target",), "bluetooth.pair": ("target",),
        "bluetooth.forget": ("target",), "bluetooth.trust": ("target", "enabled"),
        "bluetooth.rename": ("target", "alias"), "bluetooth.unblock": ("target",),
        "vpn.connect": ("target",), "vpn.disconnect": ("target",),
        "agent.reply": ("token", "accepted"),
    }
    if not isinstance(action, str) or action not in fields or any(key not in command for key in fields[action]):
        raise ValueError("Unsupported request")
    if set(command) - {"action", *fields[action], *(('password',) if action in {"wifi.connect", "wifi.retry"} else ()),
                       *(('value',) if action == "agent.reply" else ())}:
        raise ValueError("Unexpected request field")
    for key in ("enabled", "accepted"):
        if key in command and type(command[key]) is not bool:
            raise ValueError("Expected a boolean")
    for key in ("target", "token", "password", "value", "alias"):
        if key in command and (not isinstance(command[key], str) or len(command[key]) > (128 if key in {"password", "value"} else 512)):
            raise ValueError("Invalid request value")
    if action == "bluetooth.rename" and (not command["alias"].strip()
            or len(command["alias"].encode("utf-8")) > 248
            or any(ord(char) < 32 or ord(char) == 127 for char in command["alias"])):
        raise ValueError("Enter a device name of 1–248 bytes without control characters.")
    return action


def portal_uri(value):
    if not isinstance(value, str):
        return ""
    try:
        parts = urlsplit(value or "")
        return value if parts.scheme in {"http", "https"} and parts.hostname and not parts.username and not parts.password and not any(ord(c) <= 32 or ord(c) == 127 for c in value) else ""
    except ValueError:
        return ""


def valid_psk(value, sae=False):
    # WPA2 accepts 8–63 UTF-8 bytes or a 64-digit hex PSK; SAE accepts a passphrase.
    if "\x00" in value:
        return False
    try:
        length = len(value.encode("utf-8"))
    except UnicodeError:
        return False
    return (1 <= length <= 63) if sae else (8 <= length <= 63 or bool(re.fullmatch(r"[0-9a-fA-F]{64}", value)))


def public_error(error):
    # Never echo backend arguments, SSIDs, passphrases or agent replies in errors.
    if isinstance(error, UnicodeError):
        return "Invalid text encoding."
    if isinstance(error, ValueError):
        return str(error)
    if isinstance(error, GLib.Error):
        remote = Gio.DBusError.get_remote_error(error) or ""
        if "NotAuthorized" in remote or "AccessDenied" in remote:
            return "Permission denied. Check your session's authorization agent."
        if "Authentication" in remote:
            return "Authentication failed. Check the password or pairing code."
        if "NotReady" in remote:
            return "The adapter is not ready."
        if "InProgress" in remote:
            return "An operation is already in progress."
    return "The operation failed. Check the device and try again."


class Bridge:
    def __init__(self, read_only=False, fixture=None):
        self.fixture = copy.deepcopy(fixture) if fixture is not None else None
        self.read_only = read_only
        self.error = ""
        self.busy = ""
        self.generation = 0
        self.panel_closed = False
        self.target = ""
        self.prompt = None
        self.invocation = None
        self.cancel = None
        self.timeout = 0
        self.emit_timer = 0
        self.discovery_timer = 0
        self.owned_discovery = set()
        self.watches = {}
        self.nm = None
        self.bluez = None
        self.bus = None
        self.agent_registration = 0
        self.agent_registered = False
        self.wifi_adapter = ""
        self.wifi_attempt = None
        self.wifi_failure = None
        self.vpn_pending = ""
        self.bt_adapter = ""
        self.agent_path = "/org/dotfiles/Quickshell/Agent"
        self.loop = GLib.MainLoop()
        if self.fixture is None:
            self.init_real()

    def init_real(self):
        try:
            gi.require_version("NM", "1.0")
            from gi.repository import NM
            self.NM = NM
            self.nm = NM.Client.new(None)
        except (ImportError, ValueError, GLib.Error):
            self.nm = None
        try:
            self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            self.bluez = Gio.DBusObjectManagerClient.new_sync(self.bus, Gio.DBusObjectManagerClientFlags.DO_NOT_AUTO_START,
                                                            "org.bluez", "/", None, None, None)
            for signal in ("object-added", "object-removed", "interface-added", "interface-removed", "interface-proxy-properties-changed", "notify::name-owner"):
                self.bluez.connect(signal, lambda *_: self.schedule())
        except GLib.Error:
            self.bluez = None

    def schedule(self, *_):
        if not self.emit_timer:
            self.emit_timer = GLib.timeout_add(120, self.emit)

    @staticmethod
    def props(obj, interface):
        proxy = obj.get_interface(interface) if obj else None
        if not proxy:
            return {}
        return {key: proxy.get_cached_property(key).unpack() for key in proxy.get_cached_property_names() or []}

    def wifi(self):
        if not self.nm or not self.nm.get_nm_running():
            if self.nm:
                self.watch_nm([])
            return {"available": False, "enabled": False, "hardware": False, "adapters": [], "networks": [], "profiles": [], "phase": "unavailable", "failure": None, "selected": ""}
        NM = self.NM
        devices = [device for device in self.nm.get_devices() if device.get_device_type() == NM.DeviceType.WIFI]
        device = next((d for d in devices if d.get_path() == self.wifi_adapter), None)
        device = device or next((d for d in devices if d.get_active_access_point()), None) or (devices[0] if devices else None)
        self.wifi_adapter = device.get_path() if device else ""
        flags = getattr(NM, "80211ApSecurityFlags")
        rows = {}
        if device:
            active_ap = device.get_active_access_point()
            active_connection = device.get_active_connection()
            if device.get_state() == NM.DeviceState.ACTIVATED and active_ap and self.wifi_attempt and self.wifi_attempt["target"] == active_ap.get_path():
                self.wifi_attempt = self.wifi_failure = None
            for ap in device.get_access_points():
                ssid = bytes(ap.get_ssid().get_data()) if ap.get_ssid() else b""
                if not ssid:  # Hidden SSIDs are configured explicitly in the advanced editor.
                    continue
                bits = int(ap.get_rsn_flags()) | int(ap.get_wpa_flags())
                eap = int(flags.KEY_MGMT_802_1X) | int(getattr(flags, "KEY_MGMT_EAP_SUITE_B_192", 0))
                owe = int(getattr(flags, "KEY_MGMT_OWE", 0)) | int(getattr(flags, "KEY_MGMT_OWE_TM", 0))
                security = "enterprise" if bits & eap else "sae" if bits & int(flags.KEY_MGMT_SAE) else "wpa" if bits & int(flags.KEY_MGMT_PSK) else "owe" if bits & owe else "wep" if int(ap.get_flags()) & 1 else "open"
                profiles = [c for c in device.get_available_connections() if ap.connection_valid(c)]
                profile = next((c for c in profiles if active_connection and c.get_uuid() == active_connection.get_uuid()), None) or (profiles[0] if profiles else None)
                active = bool(active_ap and ap.get_path() == active_ap.get_path())
                attempting = bool(self.wifi_attempt and self.wifi_attempt["adapter"] == device.get_path())
                pending = attempting and self.wifi_attempt["target"] == ap.get_path()
                connecting = NM.DeviceState.PREPARE <= device.get_state() < NM.DeviceState.ACTIVATED
                connected = active and device.get_state() == NM.DeviceState.ACTIVATED
                key = (ssid, security)
                row = {"id": ap.get_path(), "name": ssid.decode("utf-8", "replace"), "strength": int(ap.get_strength()),
                       "security": security, "saved": bool(profile), "profile": profile.get_uuid() if profile else "",
                       "passwordKind": profile.get_setting_wireless_security().get_key_mgmt() if profile and profile.get_setting_wireless_security() else security,
                       "connected": connected, "connecting": connecting and (pending if attempting else active),
                       "failed": bool(self.wifi_failure and self.wifi_failure["target"] == ap.get_path()),
                       "retryPassword": bool(self.wifi_failure and self.wifi_failure["target"] == ap.get_path() and self.wifi_failure.get("auth")),
                       "advanced": security in {"enterprise", "wep"}}
                old = rows.get(key)
                if old is None or (row["connected"], row["strength"]) > (old["connected"], old["strength"]):
                    rows[key] = row
        profiles = []
        for profile in self.nm.get_connections():
            if profile.get_connection_type() != "802-11-wireless":
                continue
            ssid = profile.get_setting_wireless().get_ssid()
            matches = [r for r in rows.values() if r["profile"] == profile.get_uuid()]
            profiles.append({"id": profile.get_uuid(), "profile": profile.get_uuid(), "name": profile.get_id(),
                             "ssid": bytes(ssid.get_data()).decode("utf-8", "replace") if ssid else "",
                             "available": bool(device and any(ap.connection_valid(profile) for ap in device.get_access_points())), "connected": any(r["connected"] for r in matches),
                             "autoconnect": profile.get_setting_connection().get_autoconnect()})
        phase = "unavailable"
        if device:
            ds = device.get_state()
            phase = "connected" if ds == NM.DeviceState.ACTIVATED else "authentication" if ds == NM.DeviceState.NEED_AUTH else "address" if ds == NM.DeviceState.IP_CONFIG else "connecting" if NM.DeviceState.PREPARE <= ds < NM.DeviceState.ACTIVATED else "disconnected"
        self.watch_nm(devices)
        return {"available": bool(devices), "enabled": self.nm.wireless_get_enabled(),
                "hardware": self.nm.wireless_hardware_get_enabled(), "selected": self.wifi_adapter,
                "adapters": [{"id": d.get_path(), "name": d.get_iface()} for d in devices],
                "profiles": sorted(profiles, key=lambda p: p["name"].casefold()), "phase": phase,
                "failure": self.wifi_failure,
                "networks": sorted(rows.values(), key=lambda r: (not r["connected"], not r["saved"], -r["strength"], r["name"]))}

    def watch_nm(self, devices):
        active = self.nm.get_active_connections()
        objects = [self.nm, *devices, *self.nm.get_connections(), *active,
                   *(ap for d in devices for ap in d.get_access_points())]
        for obj in list(self.watches):
            if obj not in objects:
                for handler in self.watches.pop(obj):
                    obj.disconnect(handler)
        for obj in objects:
            if obj not in self.watches:
                handlers = [obj.connect("notify", self.schedule)]
                if obj is self.nm:
                    for signal in ("device-added", "device-removed", "connection-added", "connection-removed", "active-connection-added", "active-connection-removed"):
                        handlers.append(obj.connect(signal, self.schedule))
                if obj in active:
                    handlers.append(obj.connect("state-changed", self.vpn_state_changed))
                if obj in devices:
                    handlers += [obj.connect("access-point-added", self.schedule), obj.connect("access-point-removed", self.schedule),
                                 obj.connect("state-changed", self.wifi_state_changed)]
                self.watches[obj] = handlers

    def wifi_state_changed(self, device, state, old, reason):
        if self.wifi_attempt and self.wifi_attempt["adapter"] == device.get_path():
            if state == self.NM.DeviceState.FAILED:
                nick = self.NM.DeviceStateReason(reason).value_nick
                auth = nick in {"no-secrets", "supplicant-config-failed", "supplicant-failed", "supplicant-timeout"}
                self.wifi_failure = {"target": self.wifi_attempt["target"], "reason": nick, "auth": auth}
                self.error = "Wi-Fi authentication failed. Retry the password or configure the network." if auth else "Wi-Fi connection failed (" + nick + "). Retry or configure the network."
                self.wifi_attempt = None
            elif state == self.NM.DeviceState.ACTIVATED:
                self.wifi_attempt = self.wifi_failure = None
        self.schedule()

    def internet(self):
        if not self.nm or not self.nm.get_nm_running():
            return {"state": "unknown", "uri": "", "checking": False}
        states = {self.NM.ConnectivityState.FULL: "full", self.NM.ConnectivityState.PORTAL: "portal",
                  self.NM.ConnectivityState.LIMITED: "limited", self.NM.ConnectivityState.NONE: "none"}
        return {"state": states.get(self.nm.get_connectivity(), "unknown"),
                "uri": portal_uri(self.nm.connectivity_check_get_uri()), "checking": self.busy == "network.check"}

    def wifi_profile(self, target):
        if not self.nm or not self.nm.get_nm_running():
            raise ValueError("NetworkManager is unavailable.")
        profile = next((p for p in self.nm.get_connections() if p.get_uuid() == target and p.get_connection_type() == "802-11-wireless"), None)
        if not profile:
            raise ValueError("That saved Wi-Fi profile is no longer available.")
        return profile

    def vpn(self):
        if not self.nm or not self.nm.get_nm_running():
            return {"available": False, "profiles": []}
        NM = self.NM
        active = {a.get_uuid(): a for a in self.nm.get_active_connections()}
        profiles = []
        for profile in self.nm.get_connections():
            kind = profile.get_connection_type()
            if kind not in {"vpn", "wireguard"}:
                continue
            connection = active.get(profile.get_uuid())
            state = connection.get_state() if connection else NM.ActiveConnectionState.DEACTIVATED
            if profile.get_uuid() == self.vpn_pending and state == NM.ActiveConnectionState.ACTIVATED:
                self.vpn_pending = ""
            profiles.append({"id": profile.get_uuid(), "name": profile.get_id(), "type": kind,
                             "connected": state == NM.ActiveConnectionState.ACTIVATED,
                             "connecting": state == NM.ActiveConnectionState.ACTIVATING,
                             "active": bool(connection) and state != NM.ActiveConnectionState.DEACTIVATED})
        return {"available": True, "profiles": sorted(profiles, key=lambda p: (not p["active"], p["name"].casefold()))}

    def vpn_state_changed(self, connection, state, reason):
        if connection.get_uuid() == self.vpn_pending:
            if state == self.NM.ActiveConnectionState.ACTIVATED:
                self.vpn_pending = ""
            elif state == self.NM.ActiveConnectionState.DEACTIVATED:
                self.vpn_pending = ""
                self.error = "VPN connection failed (" + self.NM.ActiveConnectionStateReason(reason).value_nick + ")."
        self.schedule()

    def vpn_action(self, c):
        profiles = self.vpn()
        row = next((p for p in profiles["profiles"] if p["id"] == c["target"]), None)
        if not row:
            raise ValueError("That VPN profile is no longer available.")
        if c["action"] == "vpn.connect":
            if row["active"]:
                raise ValueError("That VPN is already active.")
            profile = next(p for p in self.nm.get_connections() if p.get_uuid() == row["id"])
            self.begin(c["action"], row["id"])
            self.vpn_pending = row["id"]
            self.nm.activate_connection_async(profile, None, None, self.cancel, self.nm_done("activate_connection_finish"))
        else:
            connection = next((a for a in self.nm.get_active_connections() if a.get_uuid() == row["id"]), None)
            if not connection:
                raise ValueError("That VPN is not connected.")
            self.vpn_pending = ""
            self.begin(c["action"], row["id"])
            self.nm.deactivate_connection_async(connection, self.cancel, self.nm_done("deactivate_connection_finish"))

    def bluetooth(self):
        objects = self.bluez.get_objects() if self.bluez else []
        adapters = []
        devices = []
        for obj in objects:
            p = self.props(obj, "org.bluez.Adapter1")
            if p:
                adapters.append({"id": obj.get_object_path(), "name": p.get("Alias", p.get("Name", "Bluetooth")),
                                 "enabled": p.get("Powered", False), "discovering": p.get("Discovering", False)})
        adapters.sort(key=lambda a: a["id"])
        selected = next((a for a in adapters if a["id"] == self.bt_adapter), None) or (adapters[0] if adapters else None)
        self.bt_adapter = selected["id"] if selected else ""
        for obj in objects:
            p = self.props(obj, "org.bluez.Device1")
            if p and p.get("Adapter") == self.bt_adapter:
                battery = self.props(obj, "org.bluez.Battery1")
                devices.append({"id": obj.get_object_path(), "name": p.get("Alias", p.get("Name", p.get("Address", "Device"))),
                                "address": p.get("Address", ""), "icon": p.get("Icon", "bluetooth"),
                                "paired": p.get("Paired", False), "connected": p.get("Connected", False),
                                "trusted": p.get("Trusted", False), "blocked": p.get("Blocked", False),
                                "battery": battery.get("Percentage", -1)})
        return {"available": bool(adapters), "adapters": adapters, "selected": self.bt_adapter,
                "enabled": selected["enabled"] if selected else False,
                "discovering": selected["discovering"] if selected else False,
                "ownDiscovery": self.bt_adapter in self.owned_discovery,
                "devices": sorted(devices, key=lambda d: (not d["connected"], not d["paired"], d["name"].casefold()))}

    def snapshot(self):
        state = copy.deepcopy(self.fixture) if self.fixture is not None else {"wifi": self.wifi(), "bluetooth": self.bluetooth(), "vpn": self.vpn(), "internet": self.internet()}
        return {**state, "readOnly": self.read_only, "fixture": self.fixture is not None,
                "busy": self.busy, "target": self.target, "error": self.error, "prompt": self.prompt}

    def emit(self):
        self.emit_timer = 0
        try:
            print(json.dumps({"type": "state", **self.snapshot()}, ensure_ascii=False), flush=True)
        except BrokenPipeError:
            self.cleanup()
            self.loop.quit()
        return False

    def finish(self, error=None):
        if self.timeout:
            GLib.source_remove(self.timeout)
            self.timeout = 0
        self.error = public_error(error) if error else ""
        if error and self.busy == "vpn.connect":
            self.vpn_pending = ""
        if error and self.busy in {"wifi.connect", "wifi.retry"}:
            self.wifi_failure = {"target": self.target, "reason": "request-failed", "auth": False}
            self.wifi_attempt = None
        self.busy = self.target = ""
        self.generation += 1
        self.cancel = None
        self.reject_prompt()
        self.emit()

    def begin(self, action, target=""):
        if self.busy:
            raise ValueError("Wait for the current operation to finish.")
        self.generation += 1
        self.busy, self.target, self.error = action, target, ""
        if action in {"wifi.connect", "wifi.retry"}:
            self.wifi_failure = None
            self.wifi_attempt = {"adapter": self.wifi_adapter, "target": target}
        self.cancel = Gio.Cancellable()
        self.timeout = GLib.timeout_add_seconds(90 if action == "bluetooth.pair" else 30, self.timed_out)
        self.emit()

    def timed_out(self):
        self.timeout = 0
        self.cancel_operation()
        self.finish(ValueError("The operation timed out."))
        return False

    def nm_done(self, finish_name):
        generation = self.generation
        def callback(client, result, *_):
            if self.generation != generation:
                return
            try:
                active = getattr(client, finish_name)(result)
                if self.busy == "vpn.connect" and active and active.get_state() == self.NM.ActiveConnectionState.DEACTIVATED:
                    raise ValueError("VPN connection failed.")
                self.finish()
            except (ValueError, GLib.Error) as error:
                self.finish(error)
        return callback

    def bt_call(self, path, interface, method, params=None, callback=None, cancellable=None, service="org.bluez"):
        generation = self.generation
        def done(bus, result, *_):
            if callback and self.generation != generation:
                return
            try:
                value = bus.call_finish(result)
                if callback:
                    callback(None, value)
            except GLib.Error as error:
                if callback:
                    callback(error, None)
        self.bus.call(service, path, interface, method, params, None, Gio.DBusCallFlags.NONE,
                      90000 if method == "Pair" else 15000, cancellable, done)

    def bt_property(self, path, interface, name, value, callback):
        self.bt_call(path, "org.freedesktop.DBus.Properties", "Set", GLib.Variant("(ssv)", (interface, name, GLib.Variant("b" if type(value) is bool else "s", value))), callback)

    def request(self, command):
        was_busy = bool(self.busy)
        try:
            action = validate(command)
            if action == "refresh":
                pass  # Keep asynchronous VPN failures visible when the panel reopens.
            elif action in {"panel.close", "cancel"}:
                self.panel_closed = True
                self.stop_discovery()
                if self.busy == "bluetooth.pair" or self.prompt:
                    self.cancel_operation()
                    self.finish()
            elif self.read_only:
                raise ValueError("Preview mode is read-only.")
            elif action == "agent.reply":
                self.agent_reply(command)
            elif self.busy:
                raise ValueError("Wait for the current operation to finish.")
            else:
                self.panel_closed = False
                if self.fixture is not None:
                    self.mock(command)
                elif action == "network.check":
                    if not self.nm:
                        raise ValueError("NetworkManager is unavailable.")
                    self.begin(action)
                    self.nm.check_connectivity_async(self.cancel, self.nm_done("check_connectivity_finish"))
                elif action.startswith("wifi."):
                    self.wifi_action(command)
                elif action.startswith("vpn."):
                    self.vpn_action(command)
                else:
                    self.bluetooth_action(command)
        except (ValueError, GLib.Error) as error:
            if not was_busy and self.busy:
                self.finish(error)
            else:
                self.error = public_error(error)
        self.emit()

    def wifi_action(self, c):
        if c["action"] == "wifi.profile.forget":
            profile = self.wifi_profile(c["target"])
            self.begin(c["action"], c["target"])
            profile.delete_async(self.cancel, self.nm_done("delete_finish"))
            return
        state = self.wifi()
        if not state["available"]:
            raise ValueError("No Wi-Fi adapter is available.")
        action = c["action"]
        if action == "wifi.adapter":
            if c["target"] not in [a["id"] for a in state["adapters"]]:
                raise ValueError("The adapter is no longer available.")
            self.wifi_adapter = c["target"]
            return
        if action == "wifi.power":
            if c["enabled"] and not state["hardware"]:
                raise ValueError("Wi-Fi is blocked by the hardware switch.")
            self.begin(action)
            self.bt_call("/org/freedesktop/NetworkManager", "org.freedesktop.DBus.Properties", "Set",
                         GLib.Variant("(ssv)", ("org.freedesktop.NetworkManager", "WirelessEnabled", GLib.Variant("b", c["enabled"]))),
                         lambda error, _: self.finish(error), service="org.freedesktop.NetworkManager")
            return
        device = next(d for d in self.nm.get_devices() if d.get_path() == self.wifi_adapter)
        if action == "wifi.scan":
            self.begin(action)
            device.request_scan_async(self.cancel, self.nm_done("request_scan_finish"))
            return
        row = next((r for r in state["networks"] if r["id"] == c["target"]), None)
        if not row:
            raise ValueError("The network is no longer available. Reload the list and try again.")
        ap = next(a for a in device.get_access_points() if a.get_path() == row["id"])
        if action == "wifi.disconnect":
            active = device.get_active_connection()
            if not row["connected"] or not active:
                raise ValueError("That network is not connected.")
            self.begin(action, row["id"])
            self.nm.deactivate_connection_async(active, self.cancel, self.nm_done("deactivate_connection_finish"))
        elif action == "wifi.forget":
            profile = next((p for p in self.nm.get_connections() if p.get_uuid() == row["profile"]), None)
            if not profile:
                raise ValueError("No saved profile exists for that network.")
            self.begin(action, row["id"])
            profile.delete_async(self.cancel, self.nm_done("delete_finish"))
        elif action in {"wifi.connect", "wifi.retry"}:
            if action == "wifi.retry":
                profile = self.wifi_profile(row["profile"])
                connection = self.NM.SimpleConnection.new_clone(profile)
                security = connection.get_setting_wireless_security()
                if not security or security.props.key_mgmt not in {"wpa-psk", "sae"}:
                    raise ValueError("Configure this network in the connection editor.")
                if not valid_psk(c["password"], security.props.key_mgmt == "sae"):
                    raise ValueError("Enter a valid Wi-Fi password.")
                security.props.psk = c["password"]
                connection.verify()
                self.begin(action, row["id"])
                generation = self.generation
                def updated(client, result, *_):
                    if self.generation != generation:
                        return
                    try:
                        client.update2_finish(result)
                        self.nm.activate_connection_async(profile, device, ap.get_path(), self.cancel, self.nm_done("activate_connection_finish"))
                    except GLib.Error as error:
                        self.finish(error)
                # Preserve the existing secret storage flags and every other setting.
                profile.update2(connection.to_dbus(self.NM.ConnectionSerializationFlags.ALL), self.NM.SettingsUpdate2Flags.TO_DISK,
                                GLib.Variant("a{sv}", {"version-id": GLib.Variant("t", profile.get_version_id())}), self.cancel, updated)
                return
            if row["saved"]:
                if c.get("password"):
                    raise ValueError("Edit the saved password in Advanced settings.")
                profile = next(p for p in self.nm.get_connections() if p.get_uuid() == row["profile"])
                self.begin(action, row["id"])
                self.nm.activate_connection_async(profile, device, ap.get_path(), self.cancel, self.nm_done("activate_connection_finish"))
                return
            if row["advanced"]:
                raise ValueError("Configure this network in Advanced settings.")
            NM = self.NM
            connection = NM.SimpleConnection.new()
            identity = NM.SettingConnection.new()
            identity.props.id = row["name"]
            identity.props.uuid = str(uuid.uuid4())
            identity.props.type = "802-11-wireless"
            identity.props.autoconnect = True
            connection.add_setting(identity)
            wifi = NM.SettingWireless.new()
            wifi.props.ssid = ap.get_ssid()
            wifi.props.mode = "infrastructure"
            connection.add_setting(wifi)
            if row["security"] in {"wpa", "sae", "owe"}:
                security = NM.SettingWirelessSecurity.new()
                security.props.key_mgmt = {"wpa": "wpa-psk", "sae": "sae", "owe": "owe"}[row["security"]]
                if row["security"] != "owe":
                    if not valid_psk(c.get("password", ""), row["security"] == "sae"):
                        raise ValueError("Enter a valid Wi-Fi password.")
                    security.props.psk = c["password"]
                connection.add_setting(security)
            for cls in (NM.SettingIP4Config, NM.SettingIP6Config):
                setting = cls.new()
                setting.props.method = "auto"
                connection.add_setting(setting)
            connection.verify()
            self.begin(action, row["id"])
            self.nm.add_and_activate_connection_async(connection, device, ap.get_path(), self.cancel, self.nm_done("add_and_activate_connection_finish"))

    def bluetooth_action(self, c):
        state = self.bluetooth()
        if not state["available"]:
            raise ValueError("No Bluetooth adapter is available.")
        action = c["action"]
        if action == "bluetooth.adapter":
            if c["target"] not in [a["id"] for a in state["adapters"]]:
                raise ValueError("The adapter is no longer available.")
            self.stop_discovery()
            self.bt_adapter = c["target"]
            return
        if action == "bluetooth.power":
            self.begin(action)
            self.bt_property(self.bt_adapter, "org.bluez.Adapter1", "Powered", c["enabled"], lambda error, _: self.finish(error))
            return
        if action == "bluetooth.scan":
            if not c["enabled"]:
                self.stop_discovery()
                return
            if not state["enabled"]:
                raise ValueError("Enable Bluetooth before reloading devices.")
            self.begin(action)
            adapter = self.bt_adapter
            def started(error, _):
                if not error:
                    self.owned_discovery.add(adapter)
                    if self.panel_closed:
                        self.stop_discovery()
                    else:
                        self.discovery_timer = GLib.timeout_add_seconds(60, self.stop_discovery)
                self.finish(error)
            self.bt_call(adapter, "org.bluez.Adapter1", "StartDiscovery", callback=started)
            return
        device = next((d for d in state["devices"] if d["id"] == c["target"]), None)
        if not device:
            raise ValueError("The device is no longer available.")
        path = device["id"]
        if action == "bluetooth.forget":
            self.begin(action, path)
            self.bt_call(self.bt_adapter, "org.bluez.Adapter1", "RemoveDevice", GLib.Variant("(o)", (path,)), lambda error, _: self.finish(error))
        elif action == "bluetooth.rename":
            self.begin(action, path)
            self.bt_property(path, "org.bluez.Device1", "Alias", c["alias"].strip(), lambda error, _: self.finish(error))
        elif action == "bluetooth.unblock":
            self.begin(action, path)
            self.bt_property(path, "org.bluez.Device1", "Blocked", False, lambda error, _: self.finish(error))
        elif action == "bluetooth.trust":
            self.begin(action, path)
            self.bt_property(path, "org.bluez.Device1", "Trusted", c["enabled"], lambda error, _: self.finish(error))
        else:
            if device["blocked"]:
                raise ValueError("This device is blocked. Unblock it in the Bluetooth manager.")
            if action == "bluetooth.pair":
                self.register_agent()
            self.begin(action, path)
            def finished(error, _):
                if error or action != "bluetooth.pair":
                    self.finish(error)
                else:
                    self.reject_prompt()
                    self.bt_call(path, "org.bluez.Device1", "Connect", callback=lambda e, _: self.finish(e), cancellable=self.cancel)
            self.bt_call(path, "org.bluez.Device1", {"bluetooth.pair": "Pair", "bluetooth.connect": "Connect", "bluetooth.disconnect": "Disconnect"}[action],
                         callback=finished, cancellable=self.cancel)

    def register_agent(self):
        if self.agent_registered:
            return
        info = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
        self.agent_registration = self.bus.register_object(self.agent_path, info, self.agent_call, None, None)
        # Own initiated pairings only: do not replace blueman's default agent.
        try:
            self.bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent",
                               GLib.Variant("(os)", (self.agent_path, "KeyboardDisplay")), None, Gio.DBusCallFlags.NONE, 3000, None)
            self.agent_registered = True
        except GLib.Error:
            self.bus.unregister_object(self.agent_registration)
            self.agent_registration = 0
            raise

    def agent_call(self, bus, sender, path, interface, method, params, invocation):
        if not self.bluez or sender != self.bluez.get_name_owner():
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Unexpected agent caller")
            return
        args = params.unpack()
        if method in {"Cancel", "Release"}:
            self.reject_prompt()
            if method == "Release":
                self.agent_registered = False
            invocation.return_value(None)
        elif not self.busy or not args or args[0] != self.target:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "No matching user-initiated operation")
        else:
            self.reject_prompt()
            kind = {"RequestPinCode": "pin", "RequestPasskey": "passkey", "DisplayPinCode": "display",
                    "DisplayPasskey": "display", "RequestConfirmation": "confirm",
                    "RequestAuthorization": "authorize", "AuthorizeService": "authorize"}[method]
            device = next((d for d in self.bluetooth()["devices"] if d["id"] == args[0]), {})
            code = f"{args[1]:06d}" if method in {"DisplayPasskey", "RequestConfirmation"} else args[1] if method == "DisplayPinCode" else ""
            self.prompt = {"kind": kind, "token": uuid.uuid4().hex, "name": device.get("name", "Bluetooth device"), "code": code}
            if kind == "display":
                invocation.return_value(None)
            else:
                self.invocation = invocation
        self.emit()

    def agent_reply(self, c):
        if not self.prompt or self.prompt["token"] != c["token"]:
            raise ValueError("That pairing request has expired.")
        if not c["accepted"]:
            self.cancel_operation()
            self.finish()
            return
        kind = self.prompt["kind"]
        value = c.get("value", "")
        if kind == "pin" and not 1 <= len(value.encode("utf-8")) <= 16:
            raise ValueError("Enter a PIN of 1–16 bytes.")
        if kind == "passkey" and not re.fullmatch(r"\d{1,6}", value):
            raise ValueError("Enter a numeric passkey of up to six digits.")
        if self.fixture is not None:
            device = next(d for d in self.fixture["bluetooth"]["devices"] if d["id"] == self.target)
            device["paired"] = device["connected"] = True
        if self.invocation:
            self.invocation.return_value(GLib.Variant("(s)", (value,)) if kind == "pin" else GLib.Variant("(u)", (int(value),)) if kind == "passkey" else None)
            self.invocation = None
        self.prompt = None
        if self.fixture is not None:
            self.finish()

    def reject_prompt(self):
        if self.invocation:
            self.invocation.return_dbus_error("org.bluez.Error.Canceled", "Request canceled")
            self.invocation = None
        self.prompt = None

    def cancel_operation(self):
        self.reject_prompt()
        if self.cancel:
            self.cancel.cancel()
        if self.fixture is None and self.busy == "bluetooth.pair" and self.target:
            self.bt_call(self.target, "org.bluez.Device1", "CancelPairing")

    def stop_discovery(self):
        if self.discovery_timer:
            GLib.source_remove(self.discovery_timer)
            self.discovery_timer = 0
        if self.fixture is not None:
            self.fixture["bluetooth"]["discovering"] = False
            self.fixture["bluetooth"]["ownDiscovery"] = False
        elif self.bus:
            for adapter in self.owned_discovery:
                self.bt_call(adapter, "org.bluez.Adapter1", "StopDiscovery")
        self.owned_discovery.clear()
        return False

    def mock(self, c):
        action = c["action"]
        if action == "network.check":
            return  # Cached fixture status only; never a real HTTP probe.
        if action == "wifi.profile.forget":
            profiles = self.fixture["wifi"].get("profiles", [])
            profile = next((p for p in profiles if p["id"] == c["target"]), None)
            if not profile:
                raise ValueError("That saved Wi-Fi profile is no longer available.")
            profiles.remove(profile)
            for row in self.fixture["wifi"]["networks"]:
                if row["profile"] == c["target"]:
                    row["saved"], row["profile"] = False, ""
            return
        kind, operation = action.split(".")
        data = self.fixture[kind]
        if kind == "vpn":
            row = next((p for p in data["profiles"] if p["id"] == c["target"]), None)
            if not data["available"] or not row:
                raise ValueError("That VPN profile is no longer available.")
            if operation == "disconnect" and not row["active"]:
                raise ValueError("That VPN is not connected.")
            row["connected"] = row["active"] = operation == "connect"
            row["connecting"] = False
            return
        if not data["available"]:
            raise ValueError("No adapter is available.")
        if operation == "adapter":
            if c["target"] not in [a["id"] for a in data["adapters"]]:
                raise ValueError("The adapter is no longer available.")
            data["selected"] = c["target"]
        elif operation == "power":
            if kind == "wifi" and c["enabled"] and not data["hardware"]:
                raise ValueError("Wi-Fi is blocked by the hardware switch.")
            data["enabled"] = c["enabled"]
        elif operation == "scan":
            if not data["enabled"]:
                raise ValueError("Enable the adapter before reloading.")
            if kind == "bluetooth":
                data["discovering"] = c["enabled"]
                data["ownDiscovery"] = c["enabled"]
        else:
            rows = data["networks" if kind == "wifi" else "devices"]
            row = next((r for r in rows if r["id"] == c["target"]), None)
            if row is None:
                raise ValueError("The selected item is no longer available.")
            if kind == "bluetooth" and row["blocked"] and operation in {"connect", "pair", "disconnect"}:
                raise ValueError("This device is blocked.")
            if operation == "pair":
                self.begin(action, row["id"])
                self.prompt = {"kind": "confirm", "token": uuid.uuid4().hex, "name": row["name"], "code": "123456"}
            elif operation == "rename":
                row["name"] = c["alias"].strip()
            elif operation == "unblock":
                row["blocked"] = False
            elif operation in {"connect", "retry"}:
                if kind == "wifi" and operation == "retry" and (not row["saved"] or row["security"] not in {"wpa", "sae"}):
                    raise ValueError("Configure this network in the connection editor.")
                if kind == "wifi" and row["advanced"] and not row["saved"]:
                    raise ValueError("Configure this network in Advanced settings.")
                if kind == "wifi" and operation != "retry" and row["saved"] and c.get("password"):
                    raise ValueError("Edit the saved password in Advanced settings.")
                if kind == "wifi" and (not row["saved"] or operation == "retry") and row["security"] in {"wpa", "sae"} and not valid_psk(c.get("password", ""), row["security"] == "sae"):
                    raise ValueError("Enter a valid Wi-Fi password.")
                if kind == "wifi":
                    for other in rows:
                        other["connected"] = False
                    row["saved"] = True
                    if "failed" in row:
                        row["failed"] = False
                    data["failure"] = None
                    data["phase"] = "connected"
                row["connected"] = True
            elif operation == "disconnect":
                row["connected"] = False
            elif operation == "trust":
                row["trusted"] = c["enabled"]
            elif operation == "forget":
                if kind == "wifi":
                    row["saved"] = row["connected"] = False
                else:
                    rows.remove(row)

    def cleanup(self):
        for timer in (self.timeout, self.emit_timer):
            if timer:
                GLib.source_remove(timer)
        self.timeout = self.emit_timer = 0
        self.cancel_operation()
        self.stop_discovery()
        if self.bus and self.agent_registered:
            try:
                self.bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", "UnregisterAgent",
                                   GLib.Variant("(o)", (self.agent_path,)), None, Gio.DBusCallFlags.NONE, 1000, None)
            except GLib.Error:
                pass
        if self.agent_registration:
            self.bus.unregister_object(self.agent_registration)

    def run(self):
        buffer = bytearray()
        os.set_blocking(sys.stdin.fileno(), False)
        def read(fd, condition):
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                return True
            if not chunk:
                self.cleanup()
                self.loop.quit()
                return False
            buffer.extend(chunk)
            if len(buffer) > 65536:
                buffer.clear()
                self.error = "Request is too large."
                self.emit()
            while b"\n" in buffer:
                line, _, rest = buffer.partition(b"\n")
                buffer[:] = rest
                try:
                    self.request(json.loads(line))
                except (ValueError, UnicodeError):
                    self.error = "Invalid request."
                    self.emit()
            return True
        GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, read)
        self.emit()
        self.loop.run()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--read-only", action="store_true")
    parser.add_argument("--snapshot", action="store_true")
    parser.add_argument("--fixture", type=Path)
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text()) if args.fixture else None
    read_only = args.read_only or args.snapshot or (fixture is None and os.getenv("QUICKSHELL_COMPARE") == "1")
    bridge = Bridge(read_only=read_only, fixture=fixture)
    if args.snapshot:
        bridge.emit()
    else:
        bridge.run()


if __name__ == "__main__":
    main()
