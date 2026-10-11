import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property Item target
    property string text: ""
    property bool hovered: false
    property bool suppressForOverlay: true
    property font textFont: Theme.barFont
    anchor.item: target
    anchor.rect.y: target.height + 6
    visible: !delay.running && hovered && (!suppressForOverlay || UiState.active === "") && text !== ""
    color: Theme.transparentColor
    implicitWidth: label.implicitWidth + 20
    implicitHeight: label.implicitHeight + 14
    onHoveredChanged: if (hovered) delay.restart(); else delay.stop()
    Timer { id: delay; interval: 450 }
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.background
        border.color: Theme.outlineVariant
        ThemeText {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: Theme.surfaceText
            font: root.textFont
        }
    }
}
