"""Toggle input/binding semantics with real Qt events, never physical radios."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class ConnectivityAffordances(unittest.TestCase):
    def test_action_buttons_are_scoped_and_radio_buttons_are_removed(self):
        button = (CONFIG / "components/ControlButton.qml").read_text()
        self.assertIn("property bool quiet: false", button)
        self.assertIn("outlined: !quiet", button)
        self.assertIn("Theme.surfaceContainerHigh", button)
        self.assertIn("property bool outlined: false", (CONFIG / "components/ThemeButton.qml").read_text())
        for name in ("ConnectivityPage", "VpnPage", "AudioPage", "QuickSettings"):
            source = (CONFIG / f"modules/controls/{name}.qml").read_text()
            self.assertNotIn("ThemeButton {", source, name)
            self.assertTrue("ControlButton {" in source or "ControlListItem {" in source, name)
        page = (CONFIG / "modules/controls/ConnectivityPage.qml").read_text()
        self.assertNotIn('? "On" : "Off"', page)
        self.assertNotIn('root.kind + ".power"', page)
        self.assertNotIn("savedMode", page)
        self.assertNotIn("toggleSaved", page)
        self.assertNotIn('text: "Scan"', page)
        self.assertIn('id: footer', page)
        self.assertIn('id: reloadButton', page)
        self.assertIn('"Reload networks" : "Reload devices"', page)
        self.assertIn('onClicked: root.select(row.modelData.id)', page)
        self.assertIn('root.expanded === row.modelData.id', page)
        toggle = (CONFIG / "components/ThemeToggle.qml").read_text()
        self.assertIn('implicitWidth: 40', toggle)
        self.assertIn('implicitHeight: 24', toggle)
        controls = (CONFIG / "modules/controls/QuickSettings.qml").read_text()
        self.assertEqual(controls.count("ThemeToggle {"), 2)
        self.assertIn('visible: root.renderedPage === "wifi"', controls)
        self.assertIn('visible: root.renderedPage === "bluetooth"', controls)


@unittest.skipUnless(importlib.util.find_spec("PyQt6"), "PyQt6 is not installed")
class ToggleInput(unittest.TestCase):
    def test_mouse_keyboard_disabled_accessibility_and_rejected_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            theme = root / "qs/theme"
            theme.mkdir(parents=True)
            (theme / "qmldir").write_text("module qs.theme\nsingleton Theme 1.0 Theme.qml\n")
            (theme / "Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property color activeBackground: "#88aa66"
    readonly property color surfaceContainerHigh: "#303840"
    readonly property color controlPressedBackground: "#414850"
    readonly property color controlHoverBackground: "#394048"
    readonly property color focusRing: "#aacc88"
    readonly property color outlineVariant: "#cccccc"
    readonly property color surfaceText: "#ffffff"
    readonly property int controlDuration: 0
    readonly property font bodyFont: Qt.font({pixelSize: 14})
    readonly property font iconFont: Qt.font({pixelSize: 14})
    readonly property color primaryInk: "#88aa66"
    readonly property color surfaceVariantText: "#ccddee"
    readonly property color surfaceContainer: "#283038"
    readonly property color transparentColor: "#00000000"
    function fontForRole(role) { return Qt.font({pixelSize: 14}); }
    function foregroundFor(bg, preferred, minimum) { return preferred; }
    function disabledFor(bg) { return "#999999"; }
}
''')
            for name in ("ThemeToggle.qml", "ControlListItem.qml", "GlyphIcon.qml", "ThemeText.qml"):
                shutil.copy2(CONFIG / "components" / name, root / name)
            (root / "ThemeTooltip.qml").write_text('''import QtQuick
QtObject { property var target; property string text; property bool hovered; property bool suppressForOverlay; property font textFont }
''')
            (root / "input.qml").write_text('''import QtQuick
Item {
    id: root
    width: 360; height: 100
    property bool radio: false
    property bool accepting: false
    property bool controlEnabled: true
    property int requests: 0
    property bool lastRequest: false
    property alias switchValue: toggle.value
    property bool accessibleChecked: toggle.Accessible.checked
    property bool rowSelected: false
    property int rowClicks: 0
    function focusRow() { entry.forceActiveFocus(); }
    ControlListItem {
        id: entry
        x: 100; y: 20; width: 220
        text: "Fixture network"
        subtitle: "Secured"
        selected: root.rowSelected
        enabled: root.controlEnabled
        onClicked: { root.rowSelected = !root.rowSelected; root.rowClicks++; }
    }
    function focusToggle() { toggle.forceActiveFocus(); }
    ThemeToggle {
        id: toggle
        x: 20; y: 20
        label: "Fixture radio"
        value: root.radio
        enabled: root.controlEnabled
        onRequested: value => { root.requests++; root.lastRequest = value; if (root.accepting) root.radio = value; }
    }
}
''')
            driver = r'''
import sys
from PyQt6.QtCore import QMetaObject, QPoint, Qt, QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView
from PyQt6.QtTest import QTest
app = QGuiApplication([])
view = QQuickView()
view.engine().addImportPath(sys.argv[1])
view.setSource(QUrl.fromLocalFile(sys.argv[1] + '/input.qml'))
assert not view.errors(), view.errors()
view.show(); view.requestActivate(); QTest.qWait(60)
root = view.rootObject()
def expect(value, requests):
    QTest.qWait(10)
    assert root.property('radio') == value
    assert root.property('switchValue') == value
    assert root.property('accessibleChecked') == value
    assert root.property('requests') == requests, root.property('requests')
def click(): QTest.mouseClick(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(45,36))
def key():
    QMetaObject.invokeMethod(root, 'focusToggle')
    QTest.keyClick(view, Qt.Key.Key_Space)
click(); expect(False, 1)  # Rejected request must never flip local state.
assert root.property('lastRequest')
root.setProperty('accepting', True)
key(); expect(True, 2)
root.setProperty('accepting', False)
key(); expect(True, 3)
assert not root.property('lastRequest')
root.setProperty('accepting', True)
click(); expect(False, 4)
root.setProperty('controlEnabled', False)
click(); key(); expect(False, 4)
root.setProperty('radio', True); expect(True, 4)
root.setProperty('controlEnabled', True)
key(); expect(False, 5)
QTest.mouseClick(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(170,40))
QTest.qWait(10)
assert root.property('rowSelected') and root.property('rowClicks') == 1
expect(False, 5)  # Selecting a row must not issue a radio request.
QMetaObject.invokeMethod(root, 'focusRow')
QTest.keyClick(view, Qt.Key.Key_Space)
QTest.qWait(10)
assert not root.property('rowSelected') and root.property('rowClicks') == 2
root.setProperty('controlEnabled', False)
QTest.mouseClick(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(170,40))
QTest.keyClick(view, Qt.Key.Key_Space)
QTest.qWait(10)
assert root.property('rowClicks') == 2
view.close()
print('PASS compact toggle and list-row mouse/Space, disabled input, accessibility and backend-authoritative binding')
'''
            result = subprocess.run([sys.executable, "-c", driver, str(root)],
                                    env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software"),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("Binding loop", result.stderr)
