"""Headless typography roles: actual Qt faces, size overrides and live role changes."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class Typography(unittest.TestCase):
    def test_sf_primary_and_current_supporting_face(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ("components", "theme", "services"):
                (root / folder).mkdir()
            for name in ("ThemeText.qml", "ThemeButton.qml", "GlyphIcon.qml"):
                shutil.copy2(CONFIG / "components" / name, root / "components" / name)
            for name in ("Theme.qml", "ColorMath.js"):
                shutil.copy2(CONFIG / "theme" / name, root / "theme" / name)
            # Isolate typography from compositor IPC and popup-window creation.
            (root / "services/MotionService.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { readonly property var settings: ({enabled: false, pickerDuration: 0, fadeDuration: 0}) }\n')
            (root / "components/ThemeTooltip.qml").write_text('''import QtQuick
QtObject {
    property var target
    property string text
    property bool hovered
    property bool suppressForOverlay
    property font textFont
}
''')
            (root / "shell.qml").write_text('''//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.theme
Scope {
    ThemeText { id: title; text: "Applications"; textRole: "title"; font.pixelSize: 12 }
    ThemeText { id: display; text: "12:34"; textRole: "display"; font.pixelSize: 22 }
    ThemeText { id: body; text: "Supporting text"; textRole: "body"; font.pixelSize: 11 }
    ThemeText { id: defaultText; text: "Primary text" }
    ThemeText { id: label; text: "Volume"; textRole: "label"; font.pixelSize: 12 }
    ThemeText { id: barText; text: "Bar text"; font: Theme.barFont }
    ThemeText { id: regular; text: "Title weight override"; textRole: "title"; font.weight: Font.Normal }
    ThemeText { id: flexible; text: "Changing role"; font.pixelSize: 10 }
    ThemeButton { id: button; text: "Mail"; textRole: "title"; font.pixelSize: 13 }
    Text { id: buttonProbe; text: "Mail"; font: button.font }
    ThemeButton { id: defaultButton; text: "Apply"; font.pixelSize: 13 }
    Text { id: defaultButtonProbe; text: "Apply"; font: defaultButton.font }
    ThemeButton { id: supportingButton; text: "Supporting action"; textRole: "body" }
    Text { id: supportingButtonProbe; text: "Supporting action"; font: supportingButton.font }
    Text { id: menuProbe; text: "Networks"; font: Theme.menuFont }
    Text { id: tooltipProbe; text: "Scroll to adjust"; font: Theme.tooltipFont }
    GlyphIcon { id: glyph; glyph: "󰂚" }
    GlyphIcon { id: resizedGlyph; glyph: ""; font.pixelSize: 16 }
    Text { id: glyphProbe; text: glyph.glyph; font: glyph.renderFont }
    IpcHandler {
        target: "type"
        function role(value: string): void { flexible.textRole = value; }
        function status(): string {
            return JSON.stringify({bodyFamily: Theme.bodyFontFamily, title: Theme.fontDetails(title), display: Theme.fontDetails(display),
                body: Theme.fontDetails(body), label: Theme.fontDetails(label), regular: Theme.fontDetails(regular),
                defaultText: Theme.fontDetails(defaultText),
                defaultButton: Theme.fontDetails(defaultButtonProbe), supportingButton: Theme.fontDetails(supportingButtonProbe),
                menu: Theme.fontDetails(menuProbe), tooltip: Theme.fontDetails(tooltipProbe),
                actualBar: Theme.fontDetails(barText), actualButton: Theme.fontDetails(defaultButton.contentItem.children[0]),
                actualGlyph: Theme.fontDetails(glyph.children[0]), resizedGlyph: Theme.fontDetails(resizedGlyph.children[0]),
                flexible: Theme.fontDetails(flexible), button: Theme.fontDetails(buttonProbe),
                glyph: Theme.fontDetails(glyphProbe)});
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QUICKSHELL_PALETTE=str(root / "absent.css"))
            env.pop("WAYLAND_DISPLAY", None)
            with (root / "log").open("w") as log:
                process = subprocess.Popen(["qs", "-p", str(root / "shell.qml"), "--no-color"],
                                           env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ipc(method, *args):
                        return subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "type", method, *args],
                                              text=True, capture_output=True)
                    deadline = time.monotonic() + 8
                    while time.monotonic() < deadline:
                        result = ipc("status")
                        if result.returncode == 0:
                            break
                        time.sleep(0.05)
                    else:
                        self.fail((root / "log").read_text())
                    state = json.loads(result.stdout)
                    self.assertEqual(state["bodyFamily"], "SF Pro Display")
                    for key, family, style, pixels in (("title", "SF Pro Display", "Bold", 12),
                            ("display", "SF Pro Display", "Regular", 22),
                            ("body", state["bodyFamily"], "Regular", 11),
                            ("defaultText", "SF Pro Display", "Regular", 14),
                            ("label", "SF Pro Display", "Regular", 12),
                            ("defaultButton", "SF Pro Display", "Regular", 13),
                            ("supportingButton", "SF Pro Display", "Regular", 14),
                            ("menu", "SF Pro Display", "Regular", 15),
                            ("tooltip", "SF Pro Display", "Regular", 15),
                            ("actualBar", "SF Pro Display", "Bold", 15),
                            ("actualButton", "SF Pro Display", "Regular", 13),
                            ("actualGlyph", "Symbols Nerd Font", "Regular", 14),
                            ("resizedGlyph", "Symbols Nerd Font", "Regular", 16),
                            ("regular", "SF Pro Display", "Regular", 18),
                            ("button", "SF Pro Display", "Bold", 13),
                            ("glyph", "Symbols Nerd Font", "Regular", 14)):
                        self.assertEqual((state[key]["family"], state[key]["style"], state[key]["pixelSize"]),
                                         (family, style, pixels), state)
                    for role, family, style in (("title", "SF Pro Display", "Bold"),
                            ("display", "SF Pro Display", "Regular"), ("label", "SF Pro Display", "Regular"),
                            ("bar", "SF Pro Display", "Bold"), ("menu", "SF Pro Display", "Regular"),
                            ("body", state["bodyFamily"], "Regular")):
                        self.assertEqual(ipc("role", role).returncode, 0)
                        value = json.loads(ipc("status").stdout)["flexible"]
                        self.assertEqual((value["family"], value["style"], value["pixelSize"]), (family, style, 10))
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            self.assertNotRegex((root / "log").read_text(), r"WARN|ERROR")


class TypographyPolicy(unittest.TestCase):
    def test_no_ubuntu_text_faces_in_quickshell(self):
        paths = [CONFIG / "theme/Theme.qml"]
        paths += list((CONFIG / "components").rglob("*.qml"))
        paths += list((CONFIG / "modules").rglob("*.qml"))
        for path in paths:
            self.assertNotRegex(path.read_text(), r"Ubuntu(?:\s+Sans|Mono|\s+Mono)", str(path))

    def test_runtime_text_declares_its_role(self):
        # A small source guard, backed by actual-rendered-item desktop checks.
        # Prevent new secondary labels from silently inheriting the primary face.
        for folder in ("components", "modules"):
            for path in (CONFIG / folder).rglob("*.qml"):
                source = path.read_text()
                for match in re.finditer(r"\bThemeText\s*\{", source):
                    position, depth, quote = match.end(), 1, None
                    while position < len(source) and depth:
                        char = source[position]
                        if quote:
                            if char == "\\":
                                position += 2
                                continue
                            if char == quote:
                                quote = None
                        elif char in ("'", '"'):
                            quote = char
                        else:
                            depth += (char == "{") - (char == "}")
                        position += 1
                    block = source[match.end():position - 1]
                    self.assertRegex(block, r"\btextRole\s*:", f"{path}:{source[:match.start()].count(chr(10)) + 1}")


if __name__ == "__main__":
    unittest.main()
