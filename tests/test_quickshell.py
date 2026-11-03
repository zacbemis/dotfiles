"""Offline Quickshell service regressions; never change real brightness or packages.

Run: python3 -m unittest discover -s tests -p test_quickshell.py -v
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"
spec = importlib.util.spec_from_file_location("check_updates", CONFIG / "scripts/check-updates.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class UpdateChecks(unittest.TestCase):
    def test_counts_and_no_updates_exit_code(self):
        results = [subprocess.CompletedProcess([], 2, "", ""),
                   subprocess.CompletedProcess([], 0, "aur-a 1 -> 2\n\naur-b 2 -> 3\n", ""),
                   subprocess.CompletedProcess([], 0, "org.example.App\n", "")]
        with patch.object(checker.shutil, "which", return_value="fixture"), \
                patch.object(checker.subprocess, "run", side_effect=results) as run:
            result = checker.check_updates()
        self.assertTrue(result["ok"])
        self.assertEqual(result["count"], 3)
        self.assertEqual(result["counts"], {"pacman": 0, "aur": 2, "flatpak": 1})
        self.assertTrue(all(call.kwargs["timeout"] == 60 for call in run.call_args_list))

    def test_empty_aur_exit_one_is_up_to_date_but_diagnostics_are_errors(self):
        results = [subprocess.CompletedProcess([], 2, "", ""), subprocess.CompletedProcess([], 1, "", ""), subprocess.CompletedProcess([], 0, "", "")]
        with patch.object(checker.shutil, "which", return_value="fixture"), patch.object(checker.subprocess, "run", side_effect=results):
            self.assertEqual(checker.check_updates(), {"count":0,"counts":{"pacman":0,"aur":0,"flatpak":0},"errors":{},"ok":True})
        for stdout, stderr in (("", "AUR unavailable"), ("partial result", "")):
            with patch.object(checker.shutil, "which", side_effect=[None, "fixture", None]), patch.object(checker.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, stdout, stderr)):
                result = checker.check_updates()
                self.assertFalse(result["ok"])
                self.assertIn("aur", result["errors"])

    def test_failure_is_not_zero_updates(self):
        with patch.object(checker.shutil, "which", return_value="fixture"), \
                patch.object(checker.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 1, "", "Network unavailable")):
            result = checker.check_updates()
        self.assertFalse(result["ok"])
        self.assertEqual(len(result["errors"]), 3)
        self.assertEqual(result["counts"], {})

    def test_missing_tools_and_timeout(self):
        with patch.object(checker.shutil, "which", return_value=None):
            self.assertFalse(checker.check_updates()["ok"])
        with patch.object(checker.shutil, "which", side_effect=["fixture", None, None]), \
                patch.object(checker.subprocess, "run", side_effect=subprocess.TimeoutExpired("checkupdates", 60)):
            result = checker.check_updates()
        self.assertFalse(result["ok"])
        self.assertIn("pacman", result["errors"])


class ComparisonConfig(unittest.TestCase):
    def test_imported_sources_are_pinned_and_unmodified(self):
        manifest = json.loads((CONFIG / "vendor/sources.json").read_text())
        self.assertEqual({source["profile"] for source in manifest["sources"]}, {"enzo", "mm2103", "dux"})
        for source in manifest["sources"]:
            self.assertRegex(source["commit"], r"^[0-9a-f]{40}$")
            self.assertEqual(source["license"], "MIT")
            self.assertIn("LICENSE", source["files"])
            folder = CONFIG / "vendor" / source["profile"] / "upstream"
            self.assertEqual(set(source["files"]), {str(path.relative_to(folder)) for path in folder.rglob("*") if path.is_file()})
            for relative, digest in source["files"].items():
                path = CONFIG / "vendor" / source["profile"] / "upstream" / relative
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest, str(path))

    def test_safe_comparison_wrapper(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            qs = root / "qs"
            qs.write_text('#!/usr/bin/python3\nimport json, os, sys\nprint(json.dumps({"args": sys.argv[1:], '
                          '"profile": os.getenv("QUICKSHELL_PROFILE"), "mode": os.getenv("QUICKSHELL_NOTIFICATIONS"), '
                          '"compare": os.getenv("QUICKSHELL_COMPARE")}))\n')
            qs.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"],
                       XDG_RUNTIME_DIR=str(root), QUICKSHELL_NOTIFICATIONS="server")
            result = subprocess.run(["bash", str(CONFIG / "compare.sh"), "enzo", "--no-color"],
                                    env=env, text=True, capture_output=True, check=True)
            output = json.loads(result.stdout)
            self.assertEqual(output, {"args": ["-p", str(CONFIG / "shell.qml"), "--no-color"],
                                     "profile": "enzo", "mode": "preview", "compare": "1"})
            for script, args in (("compare.sh", ["invalid"]), ("run.sh", ["--profile", "invalid"]),
                                 ("run.sh", ["--profile"])):
                bad = subprocess.run(["bash", str(CONFIG / script), *args], env=env, text=True, capture_output=True)
                self.assertEqual(bad.returncode, 2)
                self.assertEqual(bad.stdout, "", "Invalid profiles must fail before starting Quickshell")


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class QmlServices(unittest.TestCase):
    def test_comparison_backend_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            services = root / "services"
            services.mkdir()
            for name in ("ShellProfile.qml", "UiState.qml", "LayoutMetrics.qml", "NotificationService.qml", "NotificationBackend.qml",
                         "NotificationRecord.qml", "NotificationGroupData.qml", "NotificationText.js", "Preferences.qml", "StyleCatalog.js"):
                shutil.copy2(CONFIG / "services" / name, services / name)
            (root / "shell.qml").write_text('''import Quickshell
import Quickshell.Io
import qs.services
Scope {
    IpcHandler {
        target: "guard"
        function status(): string { return NotificationService.mode + ":" + ShellProfile.comparing; }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QUICKSHELL_COMPARE="1",
                       QUICKSHELL_NOTIFICATIONS="server", DBUS_SESSION_BUS_ADDRESS="unix:path=/does-not-exist")
            env.pop("WAYLAND_DISPLAY", None)
            with (root / "log").open("w") as log:
                process = subprocess.Popen(["qs", "-p", str(root / "shell.qml"), "--no-color"],
                                           env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 8
                    result = None
                    while time.monotonic() < deadline:
                        result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "guard", "status"],
                                                text=True, capture_output=True)
                        if result.returncode == 0:
                            break
                        time.sleep(0.05)
                    self.assertIsNotNone(result)
                    self.assertEqual(result.returncode, 0, (root / "log").read_text())
                    self.assertEqual(result.stdout.strip(), "preview:true")
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            self.assertNotRegex((root / "log").read_text(), r"WARN|ERROR")

    def test_isolated_services(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            panel = root / "backlight/panel"
            panel.mkdir(parents=True)
            value = panel / "brightness"
            value.write_text("40\n")
            calls = root / "brightness-calls"
            fail = root / "fail-updates"
            empty = root / "empty-updates"
            binaries = root / "bin"
            binaries.mkdir()
            brightness = binaries / "brightnessctl"
            brightness.write_text(f'''#!/usr/bin/python3
import pathlib, sys, time
p = pathlib.Path({str(value)!r})
with open({str(calls)!r}, "a") as log: log.write(" ".join(sys.argv[1:]) + "\\n")
if "info" in sys.argv:
    print("panel,backlight,40,40%,100")
else:
    time.sleep(0.08)
    step = sys.argv[-1]
    target = int(step[:-1]) if step.endswith("%") else int(p.read_text()) + int(step[:-2]) * (1 if step[-1] == "+" else -1)
    p.write_text(str(max(0, min(100, target))))
''')
            brightness.chmod(0o755)
            for name in ("checkupdates", "yay", "flatpak"):
                binary = binaries / name
                binary.write_text(f'#!/bin/sh\nif [ -e "{fail}" ]; then echo "fixture failure" >&2; exit 1; fi\nif [ -e "{empty}" ]; then exit {1 if name == "yay" else 2 if name == "checkupdates" else 0}; fi\nprintf "fixture-update\\n"\n')
                binary.chmod(0o755)
            services = root / "services"
            services.mkdir()
            for name in ("BrightnessService.qml", "UpdateService.qml"):
                shutil.copy2(CONFIG / "services" / name, services / name)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy2(CONFIG / "scripts/check-updates.py", scripts / "check-updates.py")
            harness = root / "shell.qml"
            harness.write_text(f'''import Quickshell
import Quickshell.Io
import qs.services as Dev
Scope {{
    IpcHandler {{
        target: "test"
        function status(): string {{
            return JSON.stringify({{available: Dev.BrightnessService.available,
                percent: Dev.BrightnessService.percent, steps: Dev.BrightnessService.pendingSteps,
                count: Dev.UpdateService.count, known: Dev.UpdateService.known,
                checking: Dev.UpdateService.checking, error: Dev.UpdateService.error,
                summary: Dev.UpdateService.summary, serial: Dev.UpdateService.serial,
                polling: Dev.UpdateService.pollingEnabled}});
        }}
        function adjust(delta: int): void {{ Dev.BrightnessService.adjust(delta); }}
        function brightness(value: int): void {{ Dev.BrightnessService.setPercent(value); }}
        function refresh(): void {{ Dev.UpdateService.refresh(); }}
    }}
}}
''')
            env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"],
                       QT_QPA_PLATFORM="offscreen", QUICKSHELL_BACKLIGHT_ROOT=str(panel.parent),
                       QUICKSHELL_BRIGHTNESS_AUTOMATION=str(root / "idle-marker.json"))
            env.pop("WAYLAND_DISPLAY", None)
            with (root / "log").open("w+") as log:
                process = subprocess.Popen(["qs", "-p", str(harness), "--no-color"],
                                           env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ipc(method, *args):
                        return subprocess.check_output(["qs", "ipc", "--pid", str(process.pid),
                            "call", "test", method, *map(str, args)], text=True, stderr=subprocess.STDOUT).strip()

                    def state():
                        return json.loads(ipc("status"))

                    def wait(predicate, timeout=8):
                        deadline = time.monotonic() + timeout
                        last = None
                        while time.monotonic() < deadline:
                            try:
                                last = state()
                                if predicate(last):
                                    return last
                            except (KeyError, ValueError, subprocess.CalledProcessError):
                                pass
                            time.sleep(0.05)
                        log.flush()
                        self.fail(f"Timed out: {last!r}\n{(root / 'log').read_text()}")

                    initial = wait(lambda s: s["available"])
                    self.assertEqual(initial["percent"], 40)
                    self.assertFalse(initial["known"] or initial["checking"] or initial["polling"])
                    time.sleep(2.2)
                    self.assertEqual(len(calls.read_text().splitlines()), 1, "Polling must not spawn brightnessctl")
                    value.write_text("73\n")
                    wait(lambda s: s["percent"] == 73)
                    value.write_text("")
                    wait(lambda s: not s["available"])
                    value.write_text("40\n")
                    wait(lambda s: s["available"] and s["percent"] == 40)
                    for _ in range(8):
                        ipc("adjust", 1)
                    wait(lambda s: s["percent"] == 80 and s["steps"] == 0)
                    for percent in (20, 30, 65, 100, 37):
                        ipc("brightness", percent)
                    wait(lambda s: s["percent"] == 37)
                    self.assertEqual(int(value.read_text()), 37, "Rapid slider writes must coalesce to the last target")
                    value.unlink()
                    wait(lambda s: not s["available"])
                    value.write_text("50\n")
                    wait(lambda s: s["available"] and s["percent"] == 50)
                    ipc("refresh")
                    wait(lambda s: not s["checking"] and s["known"] and s["count"] == 3)
                    fail.touch()
                    ipc("refresh")
                    failed = wait(lambda s: not s["checking"] and bool(s["error"]))
                    self.assertFalse(failed["known"])
                    self.assertEqual(failed["count"], 3, "Failures must preserve the last successful count")
                    fail.unlink()
                    ipc("refresh")
                    wait(lambda s: s["known"] and not s["checking"] and not s["error"])
                    empty.touch()
                    serial = state()["serial"]
                    ipc("refresh")
                    self.assertEqual(state()["summary"], "Checking…")
                    ipc("refresh")  # A second press during feedback cannot queue another check.
                    self.assertEqual(state()["serial"], serial + 1)
                    final = wait(lambda s: s["known"] and not s["checking"] and s["count"] == 0)
                    self.assertEqual(final["summary"], "Up to date")
                    self.assertEqual(final["error"], "")
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                log.flush()
                problems = [line for line in (root / "log").read_text().splitlines()
                            if "ERROR" in line or "WARN" in line]
                self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
