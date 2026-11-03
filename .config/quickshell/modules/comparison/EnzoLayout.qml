// SPDX-License-Identifier: MIT
// Adapted from EnzoNotNice/quickshell-bar, shell.qml at 68d721985be796d2d9a344f73a8b3ae5495a738d.
// See vendor/enzo/upstream/LICENSE. Preserve the rounded floating frame,
// workspace pills, active title and centered media; inject our feature adapters.
import QtQuick
import qs.services

Rectangle {
    id: root
    required property string output
    property alias tray: features.tray
    property alias featureBar: features
    function panelTargets() { return features.panelTargets().concat([applicationsButton]); }
    color: Style.background
    radius: 12
    border.color: Style.border
    border.width: 1

    Row {
        id: left
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 16
        Action {
            id: applicationsButton
            anchors.verticalCenter: parent.verticalCenter
            glyph: ""
            foreground: Style.accent
            tooltip: "Applications"
            onClicked: ShellProfile.activate("launcher")
        }
        EnzoWorkspaces { anchors.verticalCenter: parent.verticalCenter; output: root.output }
    }
    Media {
        id: media
        anchors.centerIn: parent
        maximumWidth: Math.max(0, Math.min(260, parent.width - 2 * Math.max(left.width, features.width) - 48))
    }
    FocusedTitle {
        anchors { left: left.right; right: media.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 16 }
        visible: width > 70
    }
    Features {
        id: features
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        compact: root.width < 1100
    }
}
