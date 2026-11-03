"""Optional bar indicators and real vector rendering without hardware writes."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class IndicatorPolicy(unittest.TestCase):
    def test_icon_rows_preserve_fractional_vertical_centers(self):
        for relative in ('components/StatusIcon.qml', 'modules/bar/BarLabel.qml', 'modules/comparison/Action.qml', 'modules/comparison/Tray.qml'):
            self.assertIn('y: (parent.height - height) / 2', (CONFIG / relative).read_text(), relative)
        bar = (CONFIG / 'modules/bar/Bar.qml').read_text()
        for item in ('volumeText','batteryText','brightnessText','trayRow','notificationRow'):
            self.assertIn('id: ' + item + '\n                            anchors.horizontalCenter: parent.horizontalCenter\n                            y: (parent.height - height) / 2', bar)

    def test_bar_icon_ink_sizes_do_not_resize_profile_layout_slots(self):
        theme = (CONFIG / "theme/Theme.qml").read_text()
        for name, size in (("barSoundPaintSize",18),("barBatteryPaintSize",15),("barSettingsPaintSize",15)):
            self.assertIn(f"readonly property int {name}: {size}", theme)
        action = (CONFIG / "modules/comparison/Action.qml").read_text()
        self.assertEqual(action.count("size: 14"),2)
        self.assertIn('root.controlKey === "controls" ? Theme.barSettingsPaintSize : size', action)
        self.assertIn("inkSize: Theme.barStatusPaintSize(root.controlKey, size)", action)
        self.assertIn("inkSize: Theme.barStatusPaintSize(status.kind, size)", (CONFIG / "modules/bar/BarLabel.qml").read_text())
        self.assertIn("inkSize: Theme.barSettingsPaintSize", (CONFIG / "modules/bar/Bar.qml").read_text())

    def test_clock_is_display_only_in_all_profiles(self):
        bar = (CONFIG / "modules/bar/Bar.qml").read_text()
        self.assertNotIn("clockMouse", bar)
        self.assertIn("HoverHandler { id: clockHover }", bar)
        self.assertNotIn("[notificationPill, clockPill,", bar)
        for relative in ("modules/comparison/Features.qml", "modules/comparison/MmLayout.qml"):
            code = (CONFIG / relative).read_text()
            self.assertIn("interactive: false", code)
            self.assertNotIn('button === Qt.RightButton ? "wallpaper" : "launcher"', code)
        self.assertNotIn("[applicationsButton, center]", (CONFIG / "modules/comparison/MmLayout.qml").read_text())
        action = (CONFIG / "modules/comparison/Action.qml").read_text()
        self.assertIn("cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor", action)
        self.assertIn("Qt.MiddleButton : Qt.NoButton", action)

    def test_clock_tooltips_show_full_date_without_click_directions(self):
        for relative in ("modules/bar/Bar.qml", "modules/comparison/Features.qml", "modules/comparison/MmLayout.qml"):
            code = (CONFIG / relative).read_text()
            self.assertIn('Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")', code)
            for directions in ('Left click: apps', 'Left: apps', 'Left: applications'):
                self.assertNotIn(directions, code)

    def test_battery_tooltip_is_only_percentage(self):
        for relative in ("modules/bar/Bar.qml", "modules/comparison/Features.qml"):
            code = (CONFIG / relative).read_text()
            self.assertNotIn('SystemState.batteryStatus + " · "', code)
        self.assertIn('tooltip: SystemState.batteryPercent + "%"', (CONFIG / "modules/comparison/Features.qml").read_text())
        self.assertIn('hovered: batteryHover.hovered\n                            text: SystemState.batteryPercent + "%"', (CONFIG / "modules/bar/Bar.qml").read_text())

    def test_notification_tooltip_has_no_directions(self):
        code = (CONFIG / "modules/comparison/Features.qml").read_text()
        self.assertIn('tooltip: "Notifications"', code)
        self.assertNotIn("right-click: DND", code)
        self.assertIn('button === Qt.RightButton ? "dnd" : "notifications"', code)

    def test_sound_tooltip_is_only_output_and_percentage(self):
        state = (CONFIG / "services/SystemState.qml").read_text()
        self.assertIn('readonly property string volumeTooltip: (audioSink ? audioSink.description || audioSink.name : "No audio output")', state)
        self.assertIn('+ "\\n" + volumePercent + "%"', state)
        for relative in ("modules/bar/Bar.qml", "modules/comparison/Features.qml"):
            code = (CONFIG / relative).read_text()
            self.assertIn("SystemState.volumeTooltip", code)
            self.assertNotIn("Click to mute", code)
            self.assertNotIn("click to mute", code)
            self.assertNotIn("scroll for 2% steps", code)

    def test_bar_status_icons_share_wallpaper_ink_even_for_semantic_states(self):
        action = (CONFIG / "modules/comparison/Action.qml").read_text()
        labels = (CONFIG / "modules/bar/BarLabel.qml").read_text()
        self.assertIn("property color iconColor: Style.icon", action)
        self.assertEqual(action.count("color: root.iconColor"), 2)
        self.assertEqual(labels.count("color: Theme.barIconColor"), 2)
        style = (CONFIG / "modules/comparison/Style.qml").read_text()
        self.assertIn("ShellProfile.wallpaperColors ? Theme.barIconColor", style)
        self.assertIn("Theme.readableOn(Theme.barIconSeed, textSurfaces, 4.5)", style)
        self.assertIn("Theme.readableOn(Theme.primary, textSurfaces, 4.5)", style)
        self.assertIn("readonly property color audio: icon", style)
        features = (CONFIG / "modules/comparison/Features.qml").read_text()
        self.assertNotIn("Style.audio", features)
        self.assertIn("NotificationService.unreadCount > 0 ? Style.unreadIcon : Style.icon", features)
        theme = (CONFIG / "theme/Theme.qml").read_text()
        self.assertIn('barIconSeed: mix(primary, "#ffffff", 0.85)', theme)
        bar = (CONFIG / "modules/bar/Bar.qml").read_text()
        self.assertIn("root.notificationUi.unreadCount > 0 ? Theme.barUnreadIconColor : Theme.barIconColor", bar)
        self.assertIn("color: Style.icon", (CONFIG / "modules/comparison/Media.qml").read_text())

    def test_all_profiles_use_independent_visibility_and_keep_tooltips(self):
        for relative in ("modules/bar/Bar.qml", "modules/comparison/Features.qml"):
            code = (CONFIG / relative).read_text()
            for kind in ("volume", "brightness", "battery"):
                self.assertIn(f'BarIndicators.icon("{kind}")', code)
                self.assertIn(f'BarIndicators.percent("{kind}")', code)
                self.assertIn(f'BarIndicators.shown("{kind}")', code)
                self.assertIn(f'SystemState.indicator("{kind}")', code)
            self.assertIn("tooltip", code.lower())
        action = (CONFIG / "modules/comparison/Action.qml").read_text()
        self.assertIn("root.labelWhenCompact", action)
        state = (CONFIG / "services/SystemState.qml").read_text()
        self.assertNotIn("clock.hours", state)
        self.assertIn("UPowerDeviceState.FullyCharged", state)
        self.assertNotIn("FeatureSettings.osd", (CONFIG / "services/BarIndicators.qml").read_text())


@unittest.skipUnless(importlib.util.find_spec("PyQt6"), "PyQt6 is not installed")
class IndicatorRendering(unittest.TestCase):
    def test_all_bar_icon_footprints_against_actual_tray_artwork_at_2x(self):
        if not Path('/usr/share/icons/Papirus-Dark/16x16@2x/panel/nm-signal-75-secure.svg').exists():
            self.skipTest('Papirus tray reference is not installed')
        result = subprocess.run([sys.executable, str(Path(__file__).parent / 'measure_quickshell_icons.py')],
            env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_SCALE_FACTOR='2'),
            capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        import json
        report = json.loads(result.stdout)
        icons = {item['icon']: item for item in report['icons']}
        wifi, bluetooth = icons['wifi'], icons['bluetooth']
        self.assertEqual(report['scale'], 2)
        for name, icon in icons.items():
            if name == 'sound-bluetooth':  # Two explicit symbols, not an oversized single icon.
                self.assertLessEqual(icon['width'], wifi['width'] * 1.7, name)
            else:
                self.assertLessEqual(icon['width'], wifi['width'] * 1.15, name)
            self.assertLessEqual(icon['height'], max(wifi['height'], bluetooth['height']) * 1.1, name)
        for name in ('battery', 'battery-full', 'battery-charging', 'battery-plugged', 'sound-high', 'settings'):
            self.assertLessEqual(icons[name]['inkArea'], wifi['inkArea'] * 1.1, name)
        self.assertGreaterEqual(icons['settings']['inkArea'], bluetooth['inkArea'] * .8)

    def test_rendered_vertical_centers_match_for_both_bar_slot_sizes(self):
        if not Path('/usr/share/icons/Papirus-Dark/16x16@2x/panel/nm-signal-75-secure.svg').exists():
            self.skipTest('Papirus tray reference is not installed')
        import json
        for size in (14,15):
            result = subprocess.run([sys.executable, str(Path(__file__).parent / 'measure_quickshell_icons.py'), '--slot-size', str(size)],
                env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_SCALE_FACTOR='2'),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            icons = {icon['icon']:icon for icon in json.loads(result.stdout)['icons']}
            for name, icon in icons.items():
                if name == 'sound-boost': continue  # Its extra boost badge intentionally sits above the centered speaker.
                self.assertLessEqual(abs(icon['centerOffsetY']), .5, (size,name,icon))
            for name in ('sound','sound-high','sound-muted','sound-bluetooth','battery','battery-full','battery-charging','battery-plugged'):
                self.assertEqual(icons[name]['centerOffsetY'], 0, (size,name,icons[name]))

    def test_small_vectors_distinguish_levels_mute_charging_and_bluetooth(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "icons.qml").write_text('''import QtQuick
import "''' + (CONFIG / "components").as_uri() + '''" as Components
Rectangle {
    width: 64; height: 32; color: "black"
    property alias reading: icon.reading
    property alias description: icon.description
    property alias inkSize: icon.inkSize
    property alias slotWidth: icon.width
    property alias slotHeight: icon.height
    Components.StatusIcon { id: icon; x: 4; y: 4; size: 14; color: "white" }
}
''')
            driver = r'''
import hashlib, sys
from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView
from PyQt6.QtTest import QTest
app = QGuiApplication([])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(sys.argv[1]))
assert not view.errors(), view.errors()
view.show(); QTest.qWait(60)
root = view.rootObject()
states = [
    {'kind':'battery','value':0}, {'kind':'battery','value':10}, {'kind':'battery','value':50}, {'kind':'battery','value':100},
    {'kind':'battery','value':0,'charging':True}, {'kind':'battery','value':10,'charging':True},
    {'kind':'battery','value':100,'charging':True}, {'kind':'battery','value':100,'full':True},
    {'kind':'battery','value':50,'plugged':True},
    {'kind':'brightness','value':0}, {'kind':'brightness','value':10}, {'kind':'brightness','value':50}, {'kind':'brightness','value':100},
    {'kind':'volume','value':0}, {'kind':'volume','value':20}, {'kind':'volume','value':50}, {'kind':'volume','value':80},
    {'kind':'volume','value':80,'muted':True}, {'kind':'volume','value':80,'bluetooth':True}, {'kind':'volume','value':140},
    {'kind':'volume','value':0,'available':False}]
hashes = []
for reading in states:
    root.setProperty('reading', reading)
    QTest.qWait(35)
    image = view.grabWindow()
    assert not image.isNull()
    data = image.bits().asstring(image.sizeInBytes())
    checksum = hashlib.sha256(data).hexdigest()
    assert checksum not in hashes, (reading, root.property('description'))
    hashes.append(checksum)
    assert root.property('description')
def ink_height(image):
    ys = [y for y in range(image.height()) for x in range(image.width()) if image.pixelColor(x,y).red() > 25]
    return max(ys)-min(ys)+1
for kind, size in [('volume',18),('battery',15)]:
    root.setProperty('reading', {'kind':kind,'value':50})
    root.setProperty('inkSize',14)
    QTest.qWait(35)
    before = ink_height(view.grabWindow())
    slot = (root.property('slotWidth'),root.property('slotHeight'))
    root.setProperty('inkSize',size)
    QTest.qWait(35)
    after = ink_height(view.grabWindow())
    assert 9 <= after <= 14 and after >= before, (kind,before,after)
    assert slot == (root.property('slotWidth'),root.property('slotHeight'))
view.close()
print('PASS optically balanced sound/battery ink without resizing the layout slots')
print('PASS distinct real 14px vector states for battery fill/charge/full/plug, brightness levels, sound/mute/Bluetooth/boost/unavailable')
'''
            result = subprocess.run([sys.executable, "-c", driver, str(root / "icons.qml")],
                                    env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software"),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stderr, r"TypeError|ReferenceError|Binding loop")
