"""Deliver real Qt wheel/pointer events over clickable carousel-style delegates."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

COMPONENTS = Path(__file__).resolve().parents[1] / ".config/quickshell/components"


@unittest.skipUnless(importlib.util.find_spec("PyQt6"), "PyQt6 is not installed")
class CarouselScroll(unittest.TestCase):
    def test_mouse_touchpad_and_click_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / "wheel.qml"
            fixture.write_text('''import QtQuick
import "''' + COMPONENTS.as_uri() + '''" as Components
Components.ScrollStepper {
    id: stepper
    width: 500; height: 300
    property int selected: 2
    property int stepsSeen: 0
    property int clicks: 0
    property int doubleClicks: 0
    onStepped: steps => { stepsSeen++; selected = Math.max(0, Math.min(4, selected + steps)); }
    ListView {
        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false
        model: 5
        delegate: Rectangle {
            required property int index
            width: 180; height: 200
            color: "#283323"
            MouseArea {
                anchors.fill: parent
                onClicked: stepper.clicks++
                onDoubleClicked: stepper.doubleClicks++
            }
        }
    }
}
''')
            driver = r'''
import sys
from PyQt6.QtCore import QPoint, QPointF, Qt, QUrl
from PyQt6.QtGui import QGuiApplication, QWheelEvent, QPointingDevice, QInputDevice
from PyQt6.QtQuick import QQuickView
from PyQt6.QtTest import QTest
app = QGuiApplication([])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(sys.argv[1]))
assert not view.errors(), view.errors()
view.show()
QTest.qWait(30)
root = view.rootObject()
assert root

def wheel(ax=0, ay=0, px=0, py=0, pos=(90,90), inverted=False, phase=Qt.ScrollPhase.NoScrollPhase, device=None):
    point = QPointF(*pos)
    event = QWheelEvent(point, point, QPoint(px,py), QPoint(ax,ay), Qt.MouseButton.NoButton,
                        Qt.KeyboardModifier.NoModifier, phase, inverted,
                        Qt.MouseEventSource.MouseEventNotSynthesized, device or QPointingDevice.primaryPointingDevice())
    QGuiApplication.sendEvent(view, event)
    app.processEvents()

def expect(value):
    assert root.property('selected') == value, (root.property('selected'), value, root.property('stepsSeen'))

def reset(value=2):
    root.setProperty('selected', value)
    root.setProperty('remainder', 0.)

# Mouse wheel over the clickable slide, not only empty background.
wheel(ay=-120); expect(3)
wheel(ay=120); expect(2)
# Empty space within the same viewport also navigates.
wheel(ay=-120, pos=(450,260)); expect(3)
wheel(ax=120); expect(2)
wheel(ax=-120); expect(3)
# High-resolution angle events accumulate to one notch.
reset()
for i in range(3): wheel(ay=-30); expect(2)
wheel(ay=-30); expect(3)
# Real touchpad source and smooth pixel deltas; angleDelta may be zero.
touchpad = QPointingDevice('fixture touchpad', 99, QInputDevice.DeviceType.TouchPad,
    QPointingDevice.PointerType.Finger, QInputDevice.Capability.Position | QInputDevice.Capability.Scroll, 5, 0)
reset()
for i in range(2): wheel(py=-16, device=touchpad, phase=Qt.ScrollPhase.ScrollUpdate); expect(2)
wheel(py=-16, device=touchpad, phase=Qt.ScrollPhase.ScrollUpdate); expect(3)
reset()
wheel(px=-48, device=touchpad, phase=Qt.ScrollPhase.ScrollUpdate); expect(3)
# Diagonal events are consumed once, not once by each axis handler.
reset()
wheel(ax=-120, ay=-120); expect(3)
# Respect delivered/natural-scroll deltas, do not invert twice.
reset()
wheel(ay=-120, inverted=True); expect(3)
# Begin/end/no-delta events do not select the next image.
reset()
wheel(phase=Qt.ScrollPhase.ScrollBegin); expect(2)
wheel(phase=Qt.ScrollPhase.ScrollEnd); expect(2)
# Bounds, multiple notches and idle remainder reset.
reset(0); wheel(ay=120); expect(0)
reset(4); wheel(ay=-120); expect(4)
reset(1); wheel(ay=-240); expect(3)
reset(); wheel(ay=-60); expect(2)
QTest.qWait(250)
wheel(ay=-60); expect(2)
# No navigation outside the viewport or while disabled/hidden.
reset(); wheel(ay=-120, pos=(550,350)); expect(2)
root.setProperty('enabled', False); wheel(ay=-120); expect(2)
root.setProperty('enabled', True)
root.setProperty('visible', False); wheel(ay=-120); expect(2)
root.setProperty('visible', True)
# A one-image/temporarily non-scrolling viewport still accepts image clicks.
root.setProperty('scrollEnabled', False)
wheel(ay=-120); expect(2)
QTest.mouseClick(view, Qt.MouseButton.LeftButton, pos=QPoint(90,90))
app.processEvents()
assert root.property('clicks') > 0
root.setProperty('scrollEnabled', True)
# Pointer handlers must not steal ordinary selection/double-click actions.
QTest.mouseClick(view, Qt.MouseButton.LeftButton, pos=QPoint(90,90))
app.processEvents()
assert root.property('clicks') > 0, root.property('clicks')
QTest.mouseDClick(view, Qt.MouseButton.LeftButton, pos=QPoint(90,90))
app.processEvents()
assert root.property('doubleClicks') > 0, root.property('doubleClicks')
view.close()
print('PASS Qt wheel delivery: image/background, both axes, smooth touchpad, bounds, gestures, clicks')
'''
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            result = subprocess.run([sys.executable, "-c", driver, str(fixture)], env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stderr, r"TypeError|ReferenceError|Unable to assign|is not defined")


if __name__ == "__main__":
    unittest.main()
