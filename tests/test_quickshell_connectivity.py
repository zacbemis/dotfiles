"""Offline connection bridge tests; no system bus or radio actions."""
from contextlib import redirect_stdout
import copy
import importlib.util
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".config/quickshell/scripts/connectivity.py"
FIXTURE = Path(__file__).parent / "fixtures/connectivity.json"


@unittest.skipUnless(importlib.util.find_spec("gi"), "PyGObject is not installed")
class ConnectivityBridge(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("connectivity_bridge", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def setUp(self):
        self.bridge = self.module.Bridge(fixture=json.loads(FIXTURE.read_text()))
        self.output = io.StringIO()

    def tearDown(self):
        self.bridge.cleanup()

    def send(self, **command):
        with redirect_stdout(self.output):
            self.bridge.request(command)
        return self.bridge.snapshot()

    @unittest.skipUnless(shutil.which("node"), "Node.js is not installed")
    def test_qml_and_backend_input_validation_agree(self):
        passwords = ["", "short", "password", "é" * 31, "é" * 32, "1" * 64, "z" * 64, "abc\x00password", "\ud800"]
        names = ["Headphones", "雪" * 82, "雪" * 83, "", "  ", "bad\nname", "bad\x00name", "Name ; '&"]
        expected = {"psk": [[self.module.valid_psk(value, sae) for value in passwords] for sae in (False, True)], "alias": []}
        for name in names:
            try:
                self.module.validate({"action": "bluetooth.rename", "target": "bt1", "alias": name})
                expected["alias"].append(True)
            except ValueError:
                expected["alias"].append(False)
        script = r"""
const fs = require('node:fs'), vm = require('node:vm');
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8').replace('.pragma library', ''), c);
const data = JSON.parse(process.argv[2]);
console.log(JSON.stringify({psk: [false, true].map(sae => data.passwords.map(p => c.validPsk(p, sae))), alias: data.names.map(c.validAlias)}));
"""
        result = subprocess.run(["node", "-e", script, str(ROOT / ".config/quickshell/services/ConnectivityValidation.js"),
                                 json.dumps({"passwords": passwords, "names": names})], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), expected)

    def test_open_and_refresh_do_not_scan_or_mutate(self):
        before = self.bridge.snapshot()
        state = self.send(action="refresh")
        self.assertEqual(state, before)
        self.assertFalse(state["bluetooth"]["discovering"])
        self.assertEqual(state["wifi"]["networks"][1]["name"], "Café: ; & snow 雪")

    def test_password_stays_in_memory_and_target_is_exact(self):
        secret = "fixture private password"
        state = self.send(action="wifi.connect", target="ap2", password=secret)
        self.assertEqual([r["id"] for r in state["wifi"]["networks"] if r["connected"]], ["ap2"])
        self.assertNotIn(secret, self.output.getvalue())
        self.assertNotIn(secret, json.dumps(state))
        self.assertEqual(self.send(action="wifi.connect", target="does-not-exist")["wifi"], state["wifi"])
        self.assertEqual(self.send(action="wifi.connect", target="ap4")["wifi"], state["wifi"])
        self.assertIn("Advanced", self.bridge.error)

    def test_invalid_password_never_changes_connection(self):
        before = copy.deepcopy(self.bridge.snapshot()["wifi"])
        for password in ("x", "雪" * 30, "z" * 64):
            state = self.send(action="wifi.connect", target="ap2", password=password)
            self.assertEqual(state["wifi"], before)
            self.assertTrue(state["error"])
            self.assertNotIn(json.dumps(password, ensure_ascii=False), self.output.getvalue())
        self.assertTrue(self.module.valid_psk("a" * 64))
        self.assertTrue(self.module.valid_psk("x", sae=True))

    def test_pairing_requires_matching_token_and_explicit_acceptance(self):
        state = self.send(action="bluetooth.pair", target="bt2")
        token = state["prompt"]["token"]
        state = self.send(action="agent.reply", token="stale", accepted=True)
        self.assertFalse(state["bluetooth"]["devices"][1]["paired"])
        self.assertEqual(state["prompt"]["token"], token)
        state = self.send(action="agent.reply", token=token, accepted=True)
        self.assertTrue(state["bluetooth"]["devices"][1]["paired"])
        self.assertTrue(state["bluetooth"]["devices"][1]["connected"])
        self.assertFalse(state["busy"])
        self.assertIsNone(state["prompt"])

    def test_agent_pin_passkey_display_and_sender_validation(self):
        from types import SimpleNamespace
        methods = {method.name for method in self.module.Gio.DBusNodeInfo.new_for_xml(self.module.AGENT_XML).interfaces[0].methods}
        self.assertIn("RequestConfirmation", methods)
        self.bridge.bluez = SimpleNamespace(get_name_owner=lambda: ":fixture.bluez")
        self.bridge.bluetooth = lambda: self.bridge.fixture["bluetooth"]
        class Reply:
            def __init__(self):
                self.value = None
                self.error = None
            def return_value(self, value):
                self.value = value
            def return_dbus_error(self, name, message):
                self.error = name
        for method, value in (("RequestPinCode", "1234"), ("RequestPasskey", "001234")):
            self.send(action="bluetooth.pair", target="bt2")
            reply = Reply()
            with redirect_stdout(self.output):
                self.bridge.agent_call(None, ":fixture.bluez", "", "", method, SimpleNamespace(unpack=lambda: ("bt2",)), reply)
            token = self.bridge.prompt["token"]
            self.send(action="agent.reply", token=token, accepted=True, value=value)
            self.assertIsNone(reply.error)
            self.assertEqual(reply.value.unpack()[0], value if method == "RequestPinCode" else int(value))
        self.send(action="bluetooth.pair", target="bt2")
        reply = Reply()
        with redirect_stdout(self.output):
            self.bridge.agent_call(None, ":untrusted", "", "", "RequestPinCode", SimpleNamespace(unpack=lambda: ("bt2",)), reply)
        self.assertEqual(reply.error, "org.bluez.Error.Rejected")
        reply = Reply()
        with redirect_stdout(self.output):
            self.bridge.agent_call(None, ":fixture.bluez", "", "", "DisplayPasskey", SimpleNamespace(unpack=lambda: ("bt2", 42, 0)), reply)
        self.assertEqual(self.bridge.prompt["code"], "000042")
        self.send(action="panel.close")
        self.assertIsNone(self.bridge.prompt)

    def test_closing_cancels_pairing_and_only_owned_scan(self):
        self.send(action="bluetooth.scan", enabled=True)
        state = self.send(action="bluetooth.pair", target="bt2")
        self.assertTrue(state["bluetooth"]["ownDiscovery"])
        state = self.send(action="panel.close")
        self.assertFalse(state["bluetooth"]["discovering"])
        self.assertFalse(state["busy"])
        self.assertIsNone(state["prompt"])
        self.assertFalse(state["bluetooth"]["devices"][1]["paired"])

    def test_disconnect_trust_forget_and_blocked_devices(self):
        state = self.send(action="bluetooth.disconnect", target="bt1")
        self.assertFalse(state["bluetooth"]["devices"][0]["connected"])
        state = self.send(action="bluetooth.trust", target="bt1", enabled=False)
        self.assertFalse(state["bluetooth"]["devices"][0]["trusted"])
        state = self.send(action="bluetooth.connect", target="bt3")
        self.assertIn("blocked", state["error"])
        state = self.send(action="bluetooth.forget", target="bt1")
        self.assertNotIn("bt1", [d["id"] for d in state["bluetooth"]["devices"]])
        state = self.send(action="wifi.forget", target="ap1")
        self.assertFalse(state["wifi"]["networks"][0]["saved"])

    def test_failure_recovery_distinguishes_authentication_from_ip_failure(self):
        self.bridge.NM = SimpleNamespace(DeviceState=SimpleNamespace(FAILED=120, ACTIVATED=100),
            DeviceStateReason=lambda code: SimpleNamespace(value_nick={1: "no-secrets", 2: "ip-config-unavailable"}[code]))
        device = Mock(get_path=Mock(return_value="wifi0"))
        for code, auth in ((1, True), (2, False)):
            self.bridge.wifi_attempt = {"adapter": "wifi0", "target": "ap1"}
            self.bridge.wifi_state_changed(device, 120, 50, code)
            self.assertEqual(self.bridge.wifi_failure["auth"], auth)
            self.assertEqual(self.bridge.wifi_failure["target"], "ap1")
            self.assertIsNone(self.bridge.wifi_attempt)
        self.assertNotIn("authentication failed", self.bridge.error)
        self.bridge.wifi_attempt = {"adapter": "wifi0", "target": "ap1"}
        self.bridge.wifi_state_changed(device, 100, 70, 1)
        self.assertIsNone(self.bridge.wifi_failure)
        self.assertFalse(self.module.valid_psk("password\x00bad"))

    def test_personal_saved_password_retry_preserves_profile_and_secret_flags(self):
        import gi
        gi.require_version("NM", "1.0")
        from gi.repository import NM, GLib
        original = NM.SimpleConnection.new()
        identity = NM.SettingConnection.new()
        identity.props.id, identity.props.uuid, identity.props.type = "Fixture", "33333333-3333-4333-8333-333333333333", "802-11-wireless"
        identity.props.autoconnect = False
        original.add_setting(identity)
        wifi = NM.SettingWireless.new()
        wifi.props.ssid = GLib.Bytes.new(b"Fixture")
        original.add_setting(wifi)
        security = NM.SettingWirelessSecurity.new()
        security.props.key_mgmt, security.props.psk, security.props.psk_flags = "wpa-psk", "old fixture secret", NM.SettingSecretFlags.AGENT_OWNED
        original.add_setting(security)
        clone = NM.SimpleConnection.new_clone(original)
        profile = Mock(get_uuid=Mock(return_value=identity.props.uuid), get_connection_type=Mock(return_value="802-11-wireless"), get_version_id=Mock(return_value=7))
        ap = Mock(get_path=Mock(return_value="ap1"))
        device = Mock(get_path=Mock(return_value="wifi0"), get_access_points=Mock(return_value=[ap]))
        self.bridge.nm = Mock(get_nm_running=Mock(return_value=True), get_devices=Mock(return_value=[device]), get_connections=Mock(return_value=[profile]))
        self.bridge.NM = SimpleNamespace(SimpleConnection=SimpleNamespace(new_clone=lambda p: clone), ConnectionSerializationFlags=NM.ConnectionSerializationFlags, SettingsUpdate2Flags=NM.SettingsUpdate2Flags)
        self.bridge.wifi_adapter = "wifi0"
        self.bridge.wifi = Mock(return_value=self.bridge.fixture["wifi"])
        with redirect_stdout(self.output):
            self.bridge.wifi_action({"action": "wifi.retry", "target": "ap1", "password": "corrected fixture secret"})
        args = profile.update2.call_args.args
        settings = args[0].unpack()
        self.assertEqual(settings["802-11-wireless-security"]["psk"], "corrected fixture secret")
        self.assertEqual(settings["802-11-wireless-security"]["psk-flags"], int(NM.SettingSecretFlags.AGENT_OWNED))
        self.assertFalse(settings["connection"]["autoconnect"])
        self.assertEqual(args[2].unpack(), {"version-id": 7})
        self.assertEqual(original.get_setting_wireless_security().props.psk, "old fixture secret")
        self.bridge.nm.activate_connection_async.assert_not_called()
        with redirect_stdout(self.output):
            args[4](profile, object())
        self.assertIs(self.bridge.nm.activate_connection_async.call_args.args[0], profile)
        self.assertIs(self.bridge.nm.activate_connection_async.call_args.args[1], device)
        self.assertNotIn("corrected fixture secret", self.output.getvalue())

    def test_retry_saved_profile_and_forget_out_of_range_are_scoped(self):
        before = copy.deepcopy(self.bridge.fixture)
        state = self.send(action="wifi.retry", target="ap1", password="new fixture password")
        self.assertTrue(state["wifi"]["networks"][0]["saved"])
        self.assertEqual(state["vpn"], before["vpn"])
        self.assertNotIn("new fixture password", json.dumps(state))
        state = self.send(action="wifi.retry", target="ap1", password="bad")
        self.assertIn("valid Wi-Fi password", state["error"])
        profile = before["wifi"]["profiles"][1]["id"]
        state = self.send(action="wifi.profile.forget", target=profile)
        self.assertEqual(len(state["wifi"]["profiles"]), 1)
        self.assertEqual(state["wifi"]["networks"], before["wifi"]["networks"])
        self.assertEqual(state["bluetooth"], before["bluetooth"])

    def test_portal_urls_and_cached_internet_status(self):
        for uri in ("javascript:alert(1)", "file:///etc/passwd", "https://user:password@host/", "http://host/\nno", "https:///missing", None, 1):
            self.assertEqual(self.module.portal_uri(uri), "")
        self.assertEqual(self.module.portal_uri("http://login.example/check?q=1"), "http://login.example/check?q=1")
        states = SimpleNamespace(FULL=4, PORTAL=2, LIMITED=3, NONE=1)
        self.bridge.NM = SimpleNamespace(ConnectivityState=states)
        self.bridge.nm = Mock(get_nm_running=Mock(return_value=True), get_connectivity=Mock(return_value=2), connectivity_check_get_uri=Mock(return_value="http://login.example/"))
        self.assertEqual(self.bridge.internet()["state"], "portal")
        self.bridge.nm.check_connectivity_async.assert_not_called()
        before = copy.deepcopy(self.bridge.fixture)
        self.send(action="network.check")
        self.assertEqual(self.bridge.fixture, before)

    def test_bluetooth_rename_and_unblock_validate_and_target_only_device(self):
        name = "Headphones ; ' & 雪"
        state = self.send(action="bluetooth.rename", target="bt1", alias=name)
        self.assertEqual(state["bluetooth"]["devices"][0]["name"], name)
        state = self.send(action="bluetooth.unblock", target="bt3")
        self.assertFalse(next(d for d in state["bluetooth"]["devices"] if d["id"] == "bt3")["blocked"])
        self.assertFalse(next(d for d in state["bluetooth"]["devices"] if d["id"] == "bt3")["connected"])
        for alias in ("", "  ", "bad\nname", "bad\x00name", "雪" * 84):
            with self.assertRaises(ValueError):
                self.module.validate({"action": "bluetooth.rename", "target": "bt1", "alias": alias})
        self.bridge.bluetooth = Mock(return_value=self.bridge.fixture["bluetooth"])
        self.bridge.bt_property = Mock()
        with redirect_stdout(self.output):
            self.bridge.bluetooth_action({"action": "bluetooth.rename", "target": "bt1", "alias": "New name"})
        self.assertEqual(self.bridge.bt_property.call_args.args[:4], ("bt1", "org.bluez.Device1", "Alias", "New name"))

    def test_libnm_vpn_actions_never_target_the_base_connection(self):
        states = SimpleNamespace(ACTIVATED=2, ACTIVATING=1, DEACTIVATED=4)
        self.bridge.NM = SimpleNamespace(ActiveConnectionState=states)
        def profile(uuid, kind):
            return Mock(get_uuid=Mock(return_value=uuid), get_id=Mock(return_value=uuid),
                        get_connection_type=Mock(return_value=kind))
        wifi, vpn, wg = profile("wifi", "802-11-wireless"), profile("vpn", "vpn"), profile("wg", "wireguard")
        base = Mock(get_uuid=Mock(return_value="wifi"), get_state=Mock(return_value=2))
        tunnel = Mock(get_uuid=Mock(return_value="wg"), get_state=Mock(return_value=2))
        client = self.bridge.nm = Mock(get_nm_running=Mock(return_value=True),
            get_connections=Mock(return_value=[wifi, vpn, wg]), get_active_connections=Mock(return_value=[base, tunnel]))
        self.assertEqual({p["id"] for p in self.bridge.vpn()["profiles"]}, {"vpn", "wg"})
        with self.assertRaises(ValueError):
            self.bridge.vpn_action({"action": "vpn.disconnect", "target": "wifi"})
        client.deactivate_connection_async.assert_not_called()
        self.bridge.vpn_action({"action": "vpn.disconnect", "target": "wg"})
        self.assertIs(client.deactivate_connection_async.call_args.args[0], tunnel)
        self.bridge.finish()
        self.bridge.vpn_action({"action": "vpn.connect", "target": "vpn"})
        self.assertIs(client.activate_connection_async.call_args.args[0], vpn)
        self.assertIsNone(client.activate_connection_async.call_args.args[1])
        self.assertIsNone(client.activate_connection_async.call_args.args[2])

    def test_vpn_actions_are_scoped_to_saved_tunnel_profiles(self):
        before = copy.deepcopy(self.bridge.snapshot())
        profile = before["vpn"]["profiles"][0]
        state = self.send(action="vpn.connect", target=profile["id"])
        self.assertTrue(state["vpn"]["profiles"][0]["active"])
        self.assertEqual(state["wifi"], before["wifi"])
        self.assertEqual(state["bluetooth"], before["bluetooth"])
        state = self.send(action="vpn.disconnect", target=profile["id"])
        self.assertFalse(state["vpn"]["profiles"][0]["active"])
        for target in ("ap1", "not-a-profile"):
            state = self.send(action="vpn.disconnect", target=target)
            self.assertTrue(state["error"])
            self.assertEqual(state["wifi"], before["wifi"])
            self.assertEqual(state["vpn"], before["vpn"])

    def test_read_only_guard_rejects_every_mutation(self):
        self.bridge.read_only = True
        before = self.bridge.snapshot()
        for command in ({"action": "wifi.power", "enabled": False}, {"action": "wifi.scan"},
                        {"action": "wifi.connect", "target": "ap3"}, {"action": "wifi.disconnect", "target": "ap1"},
                        {"action": "wifi.forget", "target": "ap1"}, {"action": "wifi.retry", "target": "ap1", "password": "fixture password"},
                        {"action": "wifi.profile.forget", "target": "44444444-4444-4444-8444-444444444444"},
                        {"action": "network.check"}, {"action": "bluetooth.rename", "target": "bt1", "alias": "New name"},
                        {"action": "bluetooth.unblock", "target": "bt3"}, {"action": "bluetooth.power", "enabled": False},
                        {"action": "bluetooth.scan", "enabled": True}, {"action": "bluetooth.pair", "target": "bt2"},
                        {"action": "bluetooth.forget", "target": "bt1"},
                        {"action": "vpn.connect", "target": "11111111-1111-4111-8111-111111111111"},
                        {"action": "vpn.disconnect", "target": "22222222-2222-4222-8222-222222222222"}):
            state = self.send(**command)
            self.assertIn("read-only", state["error"])
            self.assertEqual(state["wifi"], before["wifi"])
            self.assertEqual(state["bluetooth"], before["bluetooth"])
            self.assertEqual(state["vpn"], before["vpn"])

    def test_validation_refuses_arbitrary_methods_and_bad_types(self):
        for value in (None, [], {"action": []}, {"action": "exec", "target": "touch /tmp/not-allowed"},
                      {"action": "wifi.power", "enabled": 1}, {"action": "wifi.scan", "password": "not allowed"},
                      {"action": "agent.reply", "token": "a", "accepted": "yes"}):
            with self.assertRaises(ValueError):
                self.module.validate(value)
        self.send(action="wifi.adapter", target="missing")
        self.assertIn("no longer available", self.bridge.error)

    def test_json_lines_transport_and_preview_environment(self):
        commands = [{"action": "wifi.power", "enabled": False}, {"action": "bluetooth.scan", "enabled": True}]
        result = subprocess.run([sys.executable, str(SCRIPT), "--fixture", str(FIXTURE), "--read-only"],
                                input="\n".join(map(json.dumps, commands)) + "\n", capture_output=True, text=True, timeout=10,
                                env=dict(os.environ, QUICKSHELL_COMPARE="1"))
        self.assertEqual(result.returncode, 0, result.stderr)
        states = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(states), 3)
        self.assertTrue(all(s["readOnly"] and s["fixture"] for s in states))
        self.assertTrue(all(s["wifi"]["enabled"] and not s["bluetooth"]["discovering"] for s in states))
        self.assertEqual(result.stderr, "")


class ConnectivitySafetyPolicy(unittest.TestCase):
    def test_left_and_right_share_the_native_route_and_vpn_editor_is_explicit(self):
        config = ROOT / ".config/quickshell"
        service = (config / "services/ConnectivityService.qml").read_text()
        self.assertIn("[Qt.LeftButton, Qt.RightButton].includes(button)", service)
        self.assertIn('["nm-connection-editor", "--edit", target]', service)
        self.assertIn('["nm-connection-editor", "--create", "--type", kind]', service)
        for relative in ("modules/bar/Bar.qml", "modules/comparison/Tray.qml"):
            self.assertIn("ConnectivityService.openTray(item.id, button)", (config / relative).read_text())
        page = (config / "modules/controls/VpnPage.qml").read_text()
        self.assertIn('text: "Add VPN"', page)
        self.assertIn('text: "Add WireGuard"', page)
        self.assertIn('text: "Configure"', page)

    def test_detail_exit_retains_rendered_page_but_clears_sensitive_inputs(self):
        config = ROOT / ".config/quickshell"
        controls = (config / "modules/controls/QuickSettings.qml").read_text()
        self.assertIn('property string renderedPage: "main"', controls)
        self.assertIn("if (root.opened) root.syncPage()", controls)
        self.assertIn("active: !root.overview && root.renderVisible", controls)
        self.assertLess(controls.index("connectionView.item.clearSensitive();"), controls.index("ConnectivityService.closePanel();"))
        page = (config / "modules/controls/ConnectivityPage.qml").read_text()
        self.assertIn('function clearSensitive(): void { password.text = ""; pairing.text = ""; }', page)
        self.assertIn('UiState.active === "controls" && ConnectivityService.page === kind ? ConnectivityService.prompt : null', page)

    def test_no_shell_or_credential_argv_and_sensitive_diagnostics(self):
        source = SCRIPT.read_text()
        self.assertNotIn("subprocess", source)
        self.assertNotIn("shell=True", source)
        self.assertNotIn("RequestDefaultAgent", source)
        theme = (ROOT / ".config/quickshell/theme/Theme.qml").read_text()
        self.assertIn("node.sensitive === true", theme)
        service = (ROOT / ".config/quickshell/services/ConnectivityService.qml").read_text()
        self.assertIn("worker.write(JSON.stringify(command)", service)
        self.assertNotIn("console.log", service)
