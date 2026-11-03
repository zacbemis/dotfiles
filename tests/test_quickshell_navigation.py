"""Real Qt Alt+H/L shortcut delivery from text fields and focused controls."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class SharedNavigationPolicy(unittest.TestCase):
    def test_one_native_backdrop_owner(self):
        shell = (CONFIG / "shell.qml").read_text()
        self.assertEqual(shell.count("NavigationWindow {"), 1)
        host = (CONFIG / "components/NavigationWindow.qml").read_text()
        self.assertIn('WlrLayershell.namespace: "quickshell-dev-panel"', host)
        self.assertIn("readonly property bool opened: UiState.navigationPage !== null", host)
        self.assertEqual(host.count("PanelTabs {"), 1)
        overlay = (CONFIG / "components/OverlayWindow.qml").read_text()
        self.assertIn("visible: !navigationPanel &&", overlay)
        self.assertIn("root.host.bodyItem", overlay)
        self.assertNotIn("PanelTabs {", overlay)

    def test_one_frame_and_five_tabs(self):
        source = (CONFIG / "services/ShellNavigation.qml").read_text()
        self.assertNotIn('key: "notifications"', source)
        self.assertNotIn('key: "controls"', source)
        for key in ("apps", "run", "files", "wallpaper", "settings"):
            self.assertIn('key: "' + key + '"', source)
        for relative in ("components/PickerWindow.qml", "modules/settings/SettingsPanel.qml"):
            self.assertIn("navigationPanel: true", (CONFIG / relative).read_text())
        for relative in ("modules/launcher/ListPicker.qml", "modules/launcher/GridPicker.qml",
                         "modules/wallpaper/ListPicker.qml", "modules/wallpaper/GalleryPicker.qml", "modules/wallpaper/CarouselPicker.qml"):
            source = (CONFIG / relative).read_text()
            self.assertNotRegex(source, r"(?m)^\s+preferredWidth:")
            self.assertNotRegex(source, r"(?m)^\s+preferredHeight:")
            self.assertNotIn("contentHeightHint:", source)


@unittest.skipUnless(importlib.util.find_spec("PyQt6"), "PyQt6 is not installed")
class NavigationKeys(unittest.TestCase):
    def test_alt_h_l_with_input_and_button_focus(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "keys.qml"
            fixture.write_text('''import QtQuick
import QtQuick.Controls
import "''' + (CONFIG / "components").as_uri() + '''" as Components
Item {
    id: root
    width: 500; height: 150
    property int selected: 0
    property bool shortcutsActive: true
    property int presses: 0
    property alias query: search.text
    function focusSearch() { search.forceActiveFocus(); }
    function focusButton() { button.forceActiveFocus(); }
    Components.PanelShortcuts {
        shortcutEnabled: root.shortcutsActive
        onStepped: delta => root.selected = (root.selected + delta + 5) % 5
    }
    TextInput { id: search; x: 20; y: 20; width: 300; height: 40; text: "untouched query"; focus: true }
    Button { id: button; x: 20; y: 80; text: "A focused control"; onClicked: root.presses++ }
}
''')
            driver = r'''
import sys
from PyQt6.QtCore import QMetaObject, Qt, QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView
from PyQt6.QtTest import QTest
app = QGuiApplication([])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(sys.argv[1]))
assert not view.errors(), view.errors()
view.show()
view.requestActivate()
QTest.qWait(100)
root = view.rootObject()
def key(code, modifier=Qt.KeyboardModifier.AltModifier):
    QTest.keyClick(view, code, modifier)
    QTest.qWait(20)
def expect(index):
    assert root.property('selected') == index, (root.property('selected'), index)
    assert root.property('query') == 'untouched query'
QMetaObject.invokeMethod(root, 'focusSearch')
key(Qt.Key.Key_L); expect(1)
key(Qt.Key.Key_H); expect(0)
key(Qt.Key.Key_H); expect(4)
key(Qt.Key.Key_L); expect(0)
QMetaObject.invokeMethod(root, 'focusButton')
for i in range(1, 6): key(Qt.Key.Key_L); expect(i % 5)
key(Qt.Key.Key_H); expect(4)
assert root.property('presses') == 0
root.setProperty('shortcutsActive', False)
key(Qt.Key.Key_L); expect(4)
key(Qt.Key.Key_H); expect(4)
root.setProperty('shortcutsActive', True)
key(Qt.Key.Key_L); expect(0)
view.close()
print('PASS real Qt Alt+H/L: text/control focus, wrap, unchanged query, disabled shortcuts')
'''
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            result = subprocess.run([sys.executable, "-c", driver, str(fixture)], env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Binding loop", result.stderr)
