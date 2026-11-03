"""Wallpaper contrast: tone math plus actual Qt roles, buttons and live palette changes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class ContrastMath(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "Node.js is not installed")
    def test_tones_across_grayscale_and_colored_wallpapers(self):
        script = r"""
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8').replace('.pragma library', ''), c);
assert.equal(c.contrast([0,0,0,1], [1,1,1,1]), 21);
assert.ok(Math.abs(c.contrast([119/255,119/255,119/255,1], [1,1,1,1]) - 4.4781) < .0001);
assert.deepEqual(Array.from(c.readable([1,1,1,1], [[0,0,0,1]], 7)), [1,1,1,1]);
assert.deepEqual(Array.from(c.rgb(c.over([1,1,1,.5], [0,0,0,1]))), [128/255,128/255,128/255,1]);
let state = 42;
const random = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return (state >>> 24) / 255; };
const wallpapers = Array.from({length:256}, (_, i) => [i/255,i/255,i/255,1]);
for (let i=0; i<200; ++i) wallpapers.push([random(),random(),random(),1]);
for (const bg of wallpapers) {
    const seed = [random(), random(), random(), 1];
    const panel = c.surface(bg, seed, 1.12);
    const surface = c.surface(bg, seed, 1.32);
    const raised = c.surface(bg, seed, 1.58);
    const translucent = [...bg.slice(0,3), c.panelOpacity(bg)];
    const surfaces = [bg, panel, surface, raised, c.rgb(c.over(translucent,[0,0,0,1])), c.rgb(c.over(translucent,[1,1,1,1]))];
    for (const minimum of [3, 4.5, 7]) {
        const fg = c.readable(seed, surfaces, minimum);
        const ratio = c.minimumContrast(fg, surfaces);
        const available = Math.max(c.minimumContrast([0,0,0,1],surfaces), c.minimumContrast([1,1,1,1],surfaces));
        const required = available >= minimum ? minimum : Math.min(minimum,4.5);
        assert.ok(ratio >= required, JSON.stringify({bg,seed,fg,ratio,minimum,available}));
        for (const channel of fg) assert.ok(Number.isFinite(channel) && channel >= 0 && channel <= 1);
    }
    const selected = c.readable(seed, [bg,panel], 3);
    assert.ok(c.minimumContrast(selected,[bg,panel]) >= 3);
    assert.ok(c.minimumContrast(c.readable(bg,[selected],4.5),[selected]) >= 4.5);
}
console.log('456 wallpaper tones: normal/muted/disabled text, alpha extremes and selections pass');
"""
        result = subprocess.run(["node", "-e", script, str(CONFIG / "theme/ColorMath.js")],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class ContrastRoles(unittest.TestCase):
    def test_qt_palette_roles_button_states_and_transition_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ("theme", "components", "services"):
                (root / folder).mkdir()
            for name in ("Theme.qml", "ColorMath.js"):
                shutil.copy2(CONFIG / "theme" / name, root / "theme" / name)
            for name in ("ThemeButton.qml", "ControlButton.qml", "ControlListItem.qml", "ThemeToggle.qml", "ThemeText.qml", "GlyphIcon.qml"):
                shutil.copy2(CONFIG / "components" / name, root / "components" / name)
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
    id: root
    property bool controlsEnabled: true
    property bool held: false
    ThemeButton { id: plain; text: "Normal"; enabled: root.controlsEnabled; down: root.held }
    ThemeButton { id: accent; text: "Accent"; baseColor: Theme.primary; enabled: root.controlsEnabled; down: root.held }
    ThemeButton { id: active; text: "Selected"; baseColor: Theme.activeBackground; enabled: root.controlsEnabled; down: root.held }
    ThemeButton { id: picker; text: "Picker"; pickerStyle: true; enabled: root.controlsEnabled; down: root.held }
    ThemeButton { id: raised; text: "Raised"; surfaceColor: Theme.surfaceContainer; enabled: root.controlsEnabled; down: root.held }
    ControlButton { id: framed; text: "Action"; enabled: root.controlsEnabled; down: root.held }
    ThemeToggle { id: off; label: "Off"; value: false; enabled: root.controlsEnabled; down: root.held }
    ThemeToggle { id: on; label: "On"; value: true; enabled: root.controlsEnabled; down: root.held }
    ControlListItem { id: listRow; text: "Network"; subtitle: "Secured"; enabled: root.controlsEnabled; down: root.held }
    ControlListItem { id: selectedRow; text: "Connected"; marked: true; enabled: root.controlsEnabled; down: root.held }
    IpcHandler {
        target: "colors"
        function apply(css: string): void { Theme.acceptPalette(css); }
        function state(value: string): void { root.controlsEnabled = value !== "disabled"; root.held = value === "pressed"; }
        function status(): string {
            const buttons = [plain,accent,active,picker,raised,framed,listRow,selectedRow].map(button => ({name: button.text,
                foreground: String(button.contentColor), background: String(button.effectiveSurface),
                ratio: Theme.contrast(button.contentColor, button.effectiveSurface), minimum: button.enabled ? 4.5 : 3}));
            buttons.push({name: "action/boundary", ratio: Theme.contrast(framed.background.border.color, framed.effectiveSurface), minimum: 3});
            for (const control of [off,on]) {
                for (const [name, foreground] of [["thumb",control.thumbColor],["boundary",control.boundaryColor]])
                    buttons.push({name: control.label + "/" + name, ratio: Theme.contrast(foreground, control.effectiveSurface), minimum: 3});
            }
            let worst = 21;
            // Check intermediate alpha/RGB states, not only animation endpoints.
            const paths = [[Theme.transparentColor,Theme.controlHoverBackground],
                [Theme.controlHoverBackground,Theme.controlPressedBackground],
                [Theme.primary,Theme.controlPressedBackground],
                [Theme.activeBackground,Theme.barHoverBackground], [Theme.surfaceContainerHigh,Theme.controlHoverBackground]];
            for (const [first,last] of paths) for (let step=0; step<=20; ++step) {
                const t = step/20;
                const color = Qt.rgba(first.r+(last.r-first.r)*t, first.g+(last.g-first.g)*t,
                    first.b+(last.b-first.b)*t, first.a+(last.a-first.a)*t);
                const bg = Qt.tint(Theme.opaque(Theme.backgroundAlpha),color);
                worst = Math.min(worst,Theme.contrast(Theme.foregroundFor(bg,Theme.surfaceText),bg));
            }
            return JSON.stringify({pairs: Theme.contrastReport(), buttons: buttons, frames: worst,
                primary: String(Theme.primary), background: String(Theme.background)});
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
                        return subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "colors", method, *args],
                                              capture_output=True, text=True, timeout=10)
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        result = ipc("status")
                        if result.returncode == 0:
                            break
                        if process.poll() is not None:
                            self.fail((root / "log").read_text())
                        time.sleep(0.05)
                    else:
                        self.fail((root / "log").read_text())
                    fixtures = []
                    current = Path.home() / ".config/waybar/colors/colors.css"
                    if current.exists():
                        fixtures.append(("current wallpaper", current.read_text()))
                    seeds = ["#000000", "#111111", "#747474", "#757575", "#767676", "#777777", "#787878",
                             "#999999", "#ffffff", "#00ff00", "#ff0000", "#0000ff"]
                    keys = ("background", "primary", "secondary", "tertiary", "inverse_primary", "error", "on_primary",
                            "on_secondary", "on_tertiary", "on_error", "on_surface", "on_surface_variant",
                            "surface_container", "surface_container_high", "outline_variant")
                    for seed in seeds:
                        fixtures.append(("flat " + seed, "\n".join(f"@define-color {key} {seed};" for key in keys)))
                    fixtures.extend([
                        ("light warm", "@define-color background #f3e9dd; @define-color primary #a87030; @define-color on_surface #e3d9cd; @define-color on_surface_variant #eadbcf; @define-color surface_container #805020;"),
                        ("alpha and aliases", "@define-color background #131d0c; @define-color primary #748d63; @define-color foreground #50ffffff; @define-color on_surface @foreground; @define-color on_surface_variant #339aab81;"),
                    ])
                    for label, css in fixtures:
                        with self.subTest(palette=label):
                            self.assertEqual(ipc("apply", css).returncode, 0)
                            for mode in ("normal", "pressed", "disabled"):
                                self.assertEqual(ipc("state", mode).returncode, 0)
                                result = ipc("status")
                                self.assertEqual(result.returncode, 0, result.stderr)
                                value = json.loads(result.stdout)
                                for pair in value["pairs"] + value["buttons"]:
                                    self.assertGreaterEqual(pair["ratio"], pair["minimum"], (label, mode, pair))
                                self.assertGreaterEqual(value["frames"], 4.5, (label, mode, value))
                            if label == "current wallpaper":
                                # The renderer must not rewrite its wallpaper accent seed.
                                self.assertIn(value["primary"].lower(), css.lower())
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            self.assertNotRegex((root / "log").read_text(), r"WARN|ERROR")


if __name__ == "__main__":
    unittest.main()
