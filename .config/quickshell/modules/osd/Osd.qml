// SPDX-License-Identifier: MIT
// Horizontal pill adapted from MM-2103 osd/Osd.qml. Vertical rendering is a local
// alternative. Both observe the existing services; no extra hardware poller.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import qs.theme

Scope {
    id: root
    property bool armed: false
    property string kind: "volume"
    property real level: 0
    property int serial: 0
    readonly property bool vertical: FeatureSettings.osd === "vertical"
    Timer { id: grace; interval: 1000; running: true; onTriggered: root.armed = true }
    Timer { id: hide; interval: 1500 }
    function preview(type, value): bool {
        if (FeatureSettings.osd === "off" || !["volume", "brightness"].includes(type) || !Number.isFinite(value)) return false;
        serial++;
        kind = type;
        level = Math.max(0, Math.min(100, value));
        hide.restart();
        return true;
    }
    function status() { return {view: FeatureSettings.osd, visible: window.visible, kind: kind, value: level,
        serial: serial, armed: armed, brightness: BrightnessService.percent, brightnessReady: BrightnessService.available,
        margins: {right: window.margins.right, bottom: window.margins.bottom}}; }
    Connections {
        target: FeatureSettings
        function onOsdChanged() { hide.stop(); root.armed = false; grace.restart(); }
    }
    Connections {
        target: SystemState
        function onVolumePercentChanged() { if (root.armed) root.preview("volume", SystemState.volumePercent); }
        function onMutedChanged() { if (root.armed) root.preview("volume", SystemState.muted ? 0 : SystemState.volumePercent); }
    }
    Connections {
        target: BrightnessService
        function onOsdRequested(value) { if (root.armed) root.preview("brightness", value); }
    }
    PanelWindow {
        id: window
        screen: UiState.screen
        visible: FeatureSettings.osd !== "off" && hide.running
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-compare-osd"
        mask: Region {}
        anchors { bottom: !root.vertical; right: root.vertical }
        margins { bottom: UiState.insets(window.screen).bottom; right: UiState.insets(window.screen).right }
        implicitWidth: root.vertical ? 56 : 280
        implicitHeight: root.vertical ? 180 : 48
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.backgroundAlpha
            border.color: Theme.outlineVariant
            GlyphIcon {
                id: icon
                x: root.vertical ? (parent.width - width) / 2 : 16
                y: root.vertical ? 10 : (parent.height - height) / 2
                glyph: root.kind === "brightness" ? "󰃠" : "󰕾"
                color: Theme.primaryInk
                size: 18
            }
            Rectangle {
                x: root.vertical ? 23 : 46
                y: root.vertical ? 36 : 21
                width: root.vertical ? 10 : parent.width - 104
                height: root.vertical ? parent.height - 70 : 6
                radius: 5
                color: Theme.sliderTrack
                Rectangle {
                    x: 1
                    y: root.vertical ? parent.height - 1 - height : 1
                    width: root.vertical ? parent.width - 2 : (parent.width - 2) * root.level / 100
                    height: root.vertical ? (parent.height - 2) * root.level / 100 : parent.height - 2
                    radius: 4
                    color: Theme.sliderFill
                }
            }
            ThemeText {
                x: root.vertical ? 0 : parent.width - 52
                y: root.vertical ? parent.height - 32 : (parent.height - height) / 2
                width: root.vertical ? parent.width : 44
                text: Math.round(root.level) + "%"
                textRole: "display"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
            }
        }
    }
}
