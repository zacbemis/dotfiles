// SPDX-License-Identifier: MIT
// Adapted from MM-2103/quickshell-bar, Bar.qml at d31a94da14648439da05457d57b1648da9b3b18e.
// See vendor/mm2103/upstream/LICENSE. Preserve edge-to-edge monochrome geometry,
// numbered chips, title, absolute centered clock and flat right-hand controls.
import QtQuick
import Quickshell
import qs.services

Rectangle {
    id: root
    required property string output
    property alias tray: features.tray
    property alias featureBar: features
    function panelTargets() { return features.panelTargets().concat([applicationsButton]); }
    color: Style.background
    Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: Style.border }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Row {
        id: left
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 8
        Action {
            id: applicationsButton
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰀻"
            tooltip: "Applications"
            onClicked: ShellProfile.activate("launcher")
        }
        MmWorkspaces { anchors.verticalCenter: parent.verticalCenter; output: root.output }
    }
    Action {
        id: center
        interactive: false
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd, MMM d  ·  hh:mm AP")
        tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")
    }
    FocusedTitle {
        anchors { left: left.right; right: center.left; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
        visible: width > 70
    }
    Row {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 14
        Media { anchors.verticalCenter: parent.verticalCenter; maximumWidth: 120; visible: player !== null && root.width > 1400 }
        Features { id: features; anchors.verticalCenter: parent.verticalCenter; showClock: false; compact: root.width < 1100 }
    }
}
