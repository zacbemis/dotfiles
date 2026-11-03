// SPDX-License-Identifier: MIT
// Visual adaptation of EnzoNotNice/quickshell-bar, Mpris.qml at 68d721985be796d2d9a344f73a8b3ae5495a738d.
// See vendor/enzo/upstream/LICENSE. Replace playerctl polling with native MPRIS.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.components

Item {
    id: root
    property real maximumWidth: 240
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    implicitWidth: player ? Math.min(maximumWidth, row.implicitWidth) : 0
    implicitHeight: 26
    visible: player !== null && maximumWidth > 30
    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 6
        GlyphIcon {
            glyph: root.player && root.player.isPlaying ? "󰎆" : "󰏤"
            color: Style.icon
            size: 14
        }
        ThemeText {
            Layout.fillWidth: true
            text: root.player ? root.player.trackTitle || root.player.identity : ""
            textFormat: Text.PlainText
            textRole: "bar"
            font.pixelSize: Style.font.pixelSize
            color: Style.media
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
    }
    ThemeTooltip { target: root; hovered: mouse.containsMouse; text: root.player ? root.player.trackTitle + "\nClick: play / pause" : "" }
}
