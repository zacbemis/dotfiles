"""Isolated real-QML preference validation, save/restart and preview boundaries."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class ShellPreferences(unittest.TestCase):
    @contextmanager
    def session(self, root, allow_save_failure=False, **overrides):
        services = root / "services"
        services.mkdir(exist_ok=True)
        for name in ("Preferences.qml", "StyleCatalog.js", "ShellProfile.qml", "FeatureSettings.qml", "BarIndicators.qml", "UiState.qml", "LayoutMetrics.qml",
                     "NotificationService.qml", "NotificationBackend.qml", "NotificationRecord.qml",
                     "NotificationGroupData.qml", "NotificationText.js"):
            shutil.copy2(CONFIG / "services" / name, services / name)
        (root / "shell.qml").write_text('''import Quickshell
import Quickshell.Io
import qs.services
Scope {
    IpcHandler {
        target: "fixture"
        function state(): string { return JSON.stringify({bar: ShellProfile.name, features: FeatureSettings.status(),
            colors: ShellProfile.wallpaperColors, autoHide: ShellProfile.autoHide, pinned: ShellProfile.pinned,
            indicators: BarIndicators.status(), persistent: Preferences.persistent, error: Preferences.error, active: UiState.active,
            notificationMode: NotificationService.mode}); }
        function select(key: string, value: string): bool { return key === "bar" ? ShellProfile.select(value) : BarIndicators.keys.includes(key) ? BarIndicators.set(key, value) : FeatureSettings.select(key, value); }
        function flags(colors: bool, hide: bool, pinned: bool): void { ShellProfile.wallpaperColors = colors; ShellProfile.autoHide = hide; ShellProfile.pinned = pinned; }
        function dispatch(feature: string): bool { return ShellProfile.activate(feature); }
        function settings(): void { UiState.show("settings"); }
        function flush(): void { Preferences.flush(); }
    }
}
''')
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QUICKSHELL_COMPARE="0", QUICKSHELL_NOTIFICATIONS="off",
                   QUICKSHELL_PERSIST_SETTINGS="1", QUICKSHELL_PREFERENCES=str(root / "preferences.json"),
                   XDG_STATE_HOME=str(root / "state"), DBUS_SESSION_BUS_ADDRESS="unix:path=/does-not-exist")
        env.pop("QUICKSHELL_PROFILE", None)
        env.pop("WAYLAND_DISPLAY", None)
        env.update(overrides)
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["qs", "-p", str(root / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(method, *args):
                    result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "fixture", method, *map(str, args)],
                                            text=True, capture_output=True, timeout=5)
                    if result.returncode:
                        raise AssertionError(result.stderr + log_path.read_text())
                    return result.stdout.strip()
                deadline = time.monotonic() + 8
                while True:
                    try:
                        ipc("state")
                        break
                    except AssertionError:
                        if time.monotonic() > deadline or process.poll() is not None:
                            raise
                        time.sleep(0.05)
                yield ipc
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        # UiState's monitor lookup has no Wayland compositor in offscreen tests.
        expected = ("Failed to create wl_display", "Compositor does not support hyprland-toplevel-mapping-v1")
        lines = [line for line in log_path.read_text().splitlines() if not any(message in line for message in expected)]
        if allow_save_failure:
            lines = [line for line in lines if not ("QML FileView" in line and "Write of" in line and "failed:" in line)]
        self.assertNotRegex("\n".join(lines), r"WARN|ERROR")

    def wait(self, callback, predicate):
        deadline = time.monotonic() + 5
        while True:
            value = callback()
            if predicate(value):
                return value
            if time.monotonic() > deadline:
                self.fail(repr(value))
            time.sleep(0.03)

    def test_independent_choices_survive_restart_and_keep_settings_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.session(root) as ipc:
                self.assertEqual(json.loads(ipc("state"))["bar"], "current")
                ipc("settings")
                self.assertEqual(ipc("select", "bar", "mm2103"), "true")
                self.assertEqual(json.loads(ipc("state"))["features"]["launcher"], "current")
                for key, value in {"launcher": "grid", "wallpaper": "carousel", "notifications": "stacked", "controls": "tiles", "osd": "vertical"}.items():
                    self.assertEqual(ipc("select", key, value), "true")
                ipc("flags", "true", "true", "true")
                self.assertEqual(ipc("select", "bar", "mm2103"), "true")  # Same radio choice must not unpin.
                before = json.loads(ipc("state"))
                self.assertEqual(before["active"], "settings")
                self.assertTrue(before["pinned"])
                for key, value in (("bar", "invalid"), ("launcher", "invalid"), ("toString", "current"), ("constructor", "current")):
                    self.assertEqual(ipc("select", key, value), "false")
                self.assertEqual(json.loads(ipc("state")), before)
                path = root / "preferences.json"
                self.wait(lambda: json.loads(path.read_text()) if path.exists() else {}, lambda value: value.get("pinned") is True)
                saved = json.loads(path.read_text())
                self.assertEqual(saved["version"], 1)
                self.assertEqual(saved["bar"], "mm2103")
                self.assertEqual(saved["notifications"], "stacked")
            with self.session(root) as ipc:
                restored = json.loads(ipc("state"))
                before["active"] = ""
                self.assertEqual(restored, before)

    def test_indicator_preferences_are_independent_persistent_and_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.session(root) as ipc:
                initial = json.loads(ipc("state"))
                self.assertEqual(set(initial["indicators"].values()), {"both"})
                ipc("settings")
                for key, mode in (("volumeIndicator", "icon"), ("brightnessIndicator", "hidden"), ("batteryIndicator", "percent")):
                    self.assertEqual(ipc("select", key, mode), "true")
                changed = json.loads(ipc("state"))
                self.assertEqual(changed["active"], "settings")
                self.assertEqual(changed["features"], initial["features"])
                self.assertEqual(ipc("select", "bar", "mm2103"), "true")
                self.assertEqual(json.loads(ipc("state"))["indicators"], changed["indicators"])
                for mode in ("bad", "true", "constructor"):
                    self.assertEqual(ipc("select", "volumeIndicator", mode), "false")
                self.assertEqual(json.loads(ipc("state"))["indicators"], changed["indicators"])
            with self.session(root) as ipc:
                self.assertEqual(json.loads(ipc("state"))["indicators"], changed["indicators"])
            data = json.loads((root / "preferences.json").read_text())
            self.assertEqual(data["brightnessIndicator"], "hidden")
            self.assertEqual(data["batteryIndicator"], "percent")

    def test_disabled_notifications_never_dispatch_to_another_server(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.session(Path(tmp)) as ipc:
                self.assertEqual(json.loads(ipc("state"))["notificationMode"], "off")
                ipc("settings")
                for profile in ("current", "enzo", "mm2103"):
                    self.assertEqual(ipc("select", "bar", profile), "true")
                    for feature in ("notifications", "dnd"):
                        with self.subTest(profile=profile, feature=feature):
                            self.assertEqual(ipc("dispatch", feature), "false")
                            self.assertEqual(json.loads(ipc("state"))["active"], "settings")

    def test_immediate_shutdown_preserves_latest_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.session(root) as ipc:
                self.assertEqual(ipc("select", "bar", "enzo"), "true")
            self.assertEqual(json.loads((root / "preferences.json").read_text())["bar"], "enzo")

    def test_invalid_partial_and_malformed_preferences_fall_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "preferences.json"
            path.write_text(json.dumps({"version": 1, "bar": "invalid", "launcher": {}, "wallpaper": "gallery",
                                        "notifications": "stacked", "autoHide": "true", "wallpaperColors": False, "unknown": "ignored",
                                        "volumeIndicator": "bad", "brightnessIndicator": "icon", "batteryIndicator": False}))
            with self.session(root) as ipc:
                state = json.loads(ipc("state"))
                self.assertEqual(state["bar"], "current")
                self.assertEqual(state["features"]["launcher"], "current")
                self.assertEqual(state["features"]["wallpaper"], "gallery")
                self.assertEqual(state["features"]["notifications"], "stacked")
                self.assertFalse(state["autoHide"])
                self.assertFalse(state["colors"])
                self.assertEqual(state["indicators"], {"volumeIndicator": "both", "brightnessIndicator": "icon", "batteryIndicator": "both"})
            for content in ("{broken", '{"version":2,"bar":"mm2103"}', "[]", "null"):
                path.write_text(content)
                with self.session(root) as ipc:
                    state = json.loads(ipc("state"))
                    self.assertEqual(state["bar"], "current")
                    self.assertEqual(state["features"]["wallpaper"], "current")
                    self.assertTrue(state["colors"])
                self.assertEqual(path.read_text(), content)

    def test_preview_and_disabled_persistence_never_read_or_write_daily_choices(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "preferences.json"
            original = '{"version":1,"bar":"mm2103","launcher":"grid"}'
            path.write_text(original)
            for overrides in ({"QUICKSHELL_COMPARE": "1"}, {"QUICKSHELL_PERSIST_SETTINGS": "0"},
                              {"QUICKSHELL_PERSIST_SETTINGS": "", "QUICKSHELL_NOTIFICATIONS": "preview"}):
                with self.session(root, **overrides) as ipc:
                    state = json.loads(ipc("state"))
                    self.assertFalse(state["persistent"])
                    self.assertEqual(state["bar"], "current")
                    self.assertEqual(state["features"]["launcher"], "current")
                    self.assertEqual(ipc("select", "bar", "enzo"), "true")
                    self.assertEqual(ipc("select", "launcher", "mm2103"), "true")
                    ipc("flush")
                    time.sleep(0.2)
                self.assertEqual(path.read_text(), original)

    def test_save_failure_is_reported_without_reverting_live_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "preferences.json").mkdir()
            with self.session(root, allow_save_failure=True) as ipc:
                self.assertEqual(ipc("select", "bar", "enzo"), "true")
                state = self.wait(lambda: json.loads(ipc("state")), lambda value: bool(value["error"]))
                self.assertEqual(state["bar"], "enzo")
                self.assertIn("Could not save", state["error"])
            self.assertTrue((root / "preferences.json").is_dir())
