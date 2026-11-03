"""Idle brightness origin markers; all brightnessctl calls are wholly offline."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / ".config/hypr/scripts/idle-brightness.py"
spec = importlib.util.spec_from_file_location("idle_brightness", HELPER)
IDLE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(IDLE)


def fake_backlight(root):
    panel = root / "backlight/panel"
    panel.mkdir(parents=True)
    value = panel / "brightness"
    value.write_text("40")
    saved = root / "saved"
    calls = root / "calls"
    marker = root / "runtime/brightness-automation.json"
    binaries = root / "bin"
    binaries.mkdir()
    binary = binaries / "brightnessctl"
    binary.write_text(f'''#!/usr/bin/python3
import json, pathlib, sys
value = pathlib.Path({str(value)!r})
saved = pathlib.Path({str(saved)!r})
with open({str(calls)!r}, "a") as log: log.write(json.dumps(sys.argv[1:]) + "\\n")
args = sys.argv[1:]
if "set" in args:
    if "-s" in args: saved.write_text(value.read_text())
    value.write_text(args[args.index("set") + 1])
elif "-r" in args and saved.exists():
    value.write_text(saved.read_text())
print("panel,backlight," + value.read_text() + ",0%,100")
''')
    binary.chmod(0o755)
    env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"],
               QUICKSHELL_BACKLIGHT_ROOT=str(panel.parent), QUICKSHELL_BRIGHTNESS_AUTOMATION=str(marker))
    return value, marker, calls, env


class IdleBrightness(unittest.TestCase):
    def test_dim_restore_preserve_original_values_and_write_private_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            value, marker, calls, env = fake_backlight(root)
            for action, expected in (("dim", 10), ("restore", 40), ("restore", 40)):
                result = subprocess.run([sys.executable, str(HELPER), action], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(int(value.read_text()), expected)
                data = json.loads(marker.read_text())
                self.assertEqual((data["device"], data["phase"], data["raw"], data["saved"]), ("panel", "complete", expected, 40))
                self.assertTrue(0 < data["expires"] - time.time_ns() // 1_000_000 <= 4000)
                self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
                self.assertEqual(len(data["token"]), 32)
            commands = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual(sum("info" in args for args in commands), 3)
            self.assertIn(["--class=backlight", "--machine-readable", "--device=panel", "-s", "set", "10"], commands)
            self.assertEqual(sum("-r" in args for args in commands), 2)

    def test_failure_clears_pending_marker_and_does_not_hide_manual_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "marker.json"
            with patch.object(IDLE, "invoke", side_effect=[subprocess.CompletedProcess([], 0, "panel,backlight,40,40%,100"), subprocess.CompletedProcess([], 1, "")]):
                self.assertEqual(IDLE.operation("dim", marker), 1)
            self.assertFalse(marker.exists())

    def test_no_runtime_or_marker_failure_does_not_prevent_brightness_command(self):
        with patch.object(IDLE, "invoke", return_value=subprocess.CompletedProcess([], 0, "")) as invoke:
            self.assertEqual(IDLE.operation("restore", None), 0)
            invoke.assert_called_once_with(["-r"])
        with patch.object(IDLE, "invoke", return_value=subprocess.CompletedProcess([], 0, "panel,backlight,40,40%,100")) as invoke, patch.object(IDLE, "write_marker", side_effect=PermissionError):
            self.assertEqual(IDLE.operation("dim", Path("/unwritable/marker")), 0)
            self.assertEqual(invoke.call_args.args[0], ["-s", "set", "10"])

    def test_idle_routes_only_dim_and_restore_through_origin_helper(self):
        source = (ROOT / ".config/hypr/hypridle.conf").read_text()
        self.assertEqual(source.count("idle-brightness.py restore"), 2)
        self.assertEqual(source.count("idle-brightness.py dim"), 1)
        for unchanged in ("timeout = 150", "timeout = 300", "timeout = 330", "timeout = 1800", "timeout = 3600", "systemctl suspend", "systemctl poweroff", "display-power.sh off"):
            self.assertIn(unchanged, source)
        osd = (ROOT / ".config/quickshell/modules/osd/Osd.qml").read_text()
        self.assertNotIn("function onBrightnessPercentChanged", osd)
        self.assertIn("function onOsdRequested", osd)
        self.assertIn("function onVolumePercentChanged", osd)
