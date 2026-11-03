// SPDX-License-Identifier: MIT
// Adapted from MM-2103/quickshell-bar, workspaces/Workspaces.qml at d31a94da14648439da05457d57b1648da9b3b18e.
// See vendor/mm2103/upstream/LICENSE. Changes: native Hyprland objects instead
// of the upstream compositor facade, app icons, our tooltip and reduced motion.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.components
import qs.theme

Row {
    id: root
    required property string output
    spacing: 4
    Repeater {
        model: ScriptModel {
            objectProp: "id"
            values: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === root.output)
                .sort((a, b) => a.id - b.id)
        }
        MouseArea {
            id: chip
            required property var modelData
            readonly property bool focused: modelData.focused
            implicitWidth: Math.max(22, content.implicitWidth + 10)
            implicitHeight: 22
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.activate()
            Rectangle {
                id: chipBackground
                anchors.fill: parent
                radius: 4
                color: Qt.tint(Theme.opaque(Style.background), chip.modelData.urgent ? Theme.error
                    : chip.focused ? Style.accent : chip.containsMouse ? Style.surface : "transparent")
                Behavior on color { ColorAnimation { duration: Style.duration } }
            }
            Row {
                id: content
                anchors.centerIn: parent
                spacing: 5
                ThemeText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.name || chip.modelData.id
                    color: Theme.foregroundFor(Qt.tint(Style.background, chipBackground.color),
                        chip.focused ? Style.accentText : Style.dim)
                    textRole: "bar"
                    font.pixelSize: Style.font.pixelSize
                    renderType: Text.NativeRendering
                }
                WorkspaceApps { anchors.verticalCenter: parent.verticalCenter; workspace: chip.modelData }
            }
            ThemeTooltip { target: chip; hovered: chip.containsMouse; text: "Workspace " + chip.modelData.name }
        }
    }
}
