// SPDX-License-Identifier: MIT
// Adapted from EnzoNotNice/quickshell-bar, Workspaces.qml at 68d721985be796d2d9a344f73a8b3ae5495a738d.
// See vendor/enzo/upstream/LICENSE. Changes: per-monitor live workspaces,
// QObject activation (Lua-compatible), app icons, shared colors/reduced motion.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.components
import qs.theme

RowLayout {
    id: root
    required property string output
    spacing: 8
    Repeater {
        model: ScriptModel {
            objectProp: "id"
            values: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === root.output)
                .sort((a, b) => a.id - b.id)
        }
        Rectangle {
            id: pill
            required property var modelData
            readonly property bool active: modelData.focused
            implicitWidth: Math.max(active ? 28 : 10, apps.implicitWidth ? apps.implicitWidth + 12 : 0)
            implicitHeight: apps.implicitWidth ? 22 : 10
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            scale: mouse.containsMouse ? 1.1 : 1
            color: modelData.urgent ? Theme.error : mouse.containsMouse ? Style.text : active ? Style.accent : Style.surface
            Behavior on implicitWidth { NumberAnimation { duration: Theme.motionEnabled ? 300 : 0; easing.type: Easing.OutExpo } }
            Behavior on scale { NumberAnimation { duration: Theme.motionEnabled ? 150 : 0; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Style.duration } }
            WorkspaceApps { id: apps; anchors.centerIn: parent; workspace: pill.modelData }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pill.modelData.activate()
            }
            ThemeTooltip { target: pill; hovered: mouse.containsMouse; text: "Workspace " + pill.modelData.name }
        }
    }
}
