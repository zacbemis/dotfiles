"""Window gaps and actual popup centering in an isolated offscreen shell."""
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
class LayoutAndTooltips(unittest.TestCase):
    def test_centered_multiline_popup_and_validated_live_gap_model(self):
        for scale in (1, 2):
            with self.subTest(scale=scale), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for directory in ("services", "components", "theme"):
                    (root / directory).mkdir()
                for name in ("UiState.qml", "LayoutMetrics.qml"):
                    shutil.copy2(CONFIG / "services" / name, root / "services" / name)
                (root / "services/MotionService.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { readonly property var settings: ({enabled:false}) }\n')
                for name in ("Theme.qml", "ColorMath.js"):
                    shutil.copy2(CONFIG / "theme" / name, root / "theme" / name)
                for name in ("ThemeTooltip.qml", "ThemeText.qml"):
                    shutil.copy2(CONFIG / "components" / name, root / "components" / name)
                (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services
Scope {
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 320
        implicitHeight: 200
        Rectangle { id: opener; x: 80; y: 30; width: 40; height: 24; color: "gray" }
        ThemeTooltip { id: tip; target: opener; hovered: true; text: "Current output\\n45%"; suppressForOverlay: false }
    }
    IpcHandler {
        target: "fixture"
        function state(): string { return JSON.stringify({tip:tip.layoutStatus(), gaps:UiState.layoutStatus(), screen:host.screen.name}); }
        function move(x: int, width: int): void { opener.x=x; opener.width=width; }
        function gaps(payload: string): bool { return LayoutMetrics.accept(payload); }
    }
}
''')
                env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_SCALE_FACTOR=str(scale), QT_QUICK_BACKEND="software",
                           HYPRLAND_INSTANCE_SIGNATURE="", QUICKSHELL_PALETTE=str(root / "missing.css"), QT_IM_MODULE="compose")
                env.pop("WAYLAND_DISPLAY", None)
                log_path = root / "shell.log"
                with log_path.open("w") as log:
                    process = subprocess.Popen(["qs", "-p", str(root / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
                    try:
                        def ipc(method, *args):
                            result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "fixture", method, *map(str, args)], capture_output=True, text=True, timeout=5)
                            if result.returncode:
                                raise AssertionError(result.stderr + log_path.read_text())
                            return result.stdout.strip()
                        def state():
                            return json.loads(ipc("state"))
                        def wait(predicate):
                            deadline = time.monotonic() + 8
                            last = None
                            while time.monotonic() < deadline:
                                try:
                                    last = state()
                                    if predicate(last): return last
                                except (AssertionError, ValueError):
                                    if process.poll() is not None: raise
                                time.sleep(.04)
                            self.fail(f"Timed out: {last!r}\n{log_path.read_text()}")
                        def centered(data):
                            tip = data["tip"]; target = tip["target"]
                            return tip["visible"] and abs(tip["x"] + tip["width"]/2 - target["x"] - target["width"]/2) <= 1 \
                                and abs(tip["y"] - target["y"] - target["height"] - data["gaps"]["windowGap"]) <= 1
                        initial = wait(centered)
                        self.assertEqual(initial["gaps"]["outer"], {"top":8,"right":8,"bottom":8,"left":8})
                        self.assertEqual(initial["gaps"]["windowGap"], 8)
                        self.assertEqual(initial["tip"]["label"]["alignment"], 4)
                        self.assertAlmostEqual(initial["tip"]["label"]["x"] + initial["tip"]["label"]["width"]/2, initial["tip"]["width"]/2, delta=1)
                        ipc("move", 130, 60)
                        wait(lambda data: data["tip"]["target"]["width"] == 60 and centered(data))
                        variants = [({"css":"12"}, {"int":6}, {"top":12,"right":12,"bottom":12,"left":12}, 12),
                                    ({"css":"10 14"}, {"css":"3 5"}, {"top":10,"right":14,"bottom":10,"left":14}, 6),
                                    ({"css":"10 14 18"}, {"css":"2 3 4 5"}, {"top":10,"right":14,"bottom":18,"left":14}, 6),
                                    ({"css":"1 2 3 4"}, {"int":0}, {"top":1,"right":2,"bottom":3,"left":4}, 0)]
                        for outer, inner, expected, gap in variants:
                            self.assertEqual(ipc("gaps", json.dumps({"outer":outer,"inner":inner})), "true")
                            data = wait(lambda data: data["gaps"]["windowGap"] == gap and centered(data))
                            self.assertEqual(data["gaps"]["outer"], expected)
                            self.assertEqual(data["gaps"]["insets"], expected)  # No compositor-reserved area in this fixture.
                        self.assertEqual(ipc("gaps", json.dumps({"outer":{"css":"1 2 3 4"}, "inner":{"int":0},
                            "monitors":[{"name":state()["screen"], "reserved":[2,32,4,6]}]})), "true")
                        self.assertEqual(state()["gaps"]["insets"], {"left":6,"top":33,"right":6,"bottom":9})
                        before = state()["gaps"]
                        for payload in ("not-json", "[]", '{"outer":{"css":""},"inner":{"int":4}}', '{"outer":{"int":-1},"inner":{"int":4}}', '{"outer":{"css":"1 2 3 4 5"},"inner":{"int":4}}', '{"outer":{"int":8},"inner":{"int":4},"monitors":[{"name":"eDP-1","reserved":[0,-1,0,0]}]}'):
                            self.assertEqual(ipc("gaps", json.dumps([payload])), "false")
                            self.assertEqual(state()["gaps"], before)
                    finally:
                        process.terminate()
                        try: process.wait(timeout=5)
                        except subprocess.TimeoutExpired: process.kill(); process.wait()
                expected = ("Failed to create wl_display", "Compositor does not support hyprland-toplevel-mapping-v1", "$HYPRLAND_INSTANCE_SIGNATURE is unset", "This plugin does not support setting window masks")
                problems = [line for line in log_path.read_text().splitlines() if ("WARN" in line or "ERROR" in line) and not any(text in line for text in expected)]
                self.assertEqual(problems, [])


class WindowSpacingPolicy(unittest.TestCase):
    def test_exterior_margins_are_shared_without_changing_internal_padding(self):
        tooltip = (CONFIG / "components/ThemeTooltip.qml").read_text()
        self.assertIn("anchor.edges: Edges.Top", tooltip)
        self.assertIn("anchor.rect.width: target ? Math.max(1, target.width) : 1", tooltip)
        self.assertIn("anchor.gravity: Edges.Bottom", tooltip)
        self.assertIn("horizontalAlignment: Text.AlignHCenter", tooltip)
        for file in ("modules/controls/QuickSettings.qml", "modules/notifications/AlternativeCenter.qml", "modules/bar/TrayMenu.qml"):
            code = (CONFIG / file).read_text()
            self.assertIn("windowInsets", code, file)
            self.assertNotIn("Math.max(16, parent.width - width - 16)", code)
        nav = (CONFIG / "components/NavigationWindow.qml").read_text()
        self.assertIn("anchors.margins: 16", nav)
        self.assertIn("windowInsets", nav)
