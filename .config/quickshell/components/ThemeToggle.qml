import QtQuick
import QtQuick.Controls
import qs.theme

// Backend-authoritative switch: clicks request a change, never flip local state
// optimistically or break the value binding when a request fails.
ToolButton {
    id: root
    property bool value: false
    property string label: ""
    property string tooltip: label
    signal requested(bool value)
    readonly property color effectiveSurface: track.color
    readonly property color thumbColor: thumb.color
    readonly property color boundaryColor: track.border.color
    readonly property real thumbPosition: thumb.x
    implicitWidth: 40
    implicitHeight: 24
    padding: 3
    checkable: false
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checkable: true
    Accessible.checked: value
    Accessible.onToggleAction: if (enabled) requested(!value)
    onClicked: requested(!value)
    background: Rectangle {
        id: track
        radius: height / 2
        color: root.value ? Theme.activeBackground : root.down ? Theme.controlPressedBackground
            : root.hovered ? Theme.controlHoverBackground : Theme.surfaceContainerHigh
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.focusRing : Theme.foregroundFor(color, Theme.outlineVariant, 3)
        Behavior on color { ColorAnimation { duration: Theme.controlDuration; easing.type: Easing.InOutQuad } }
    }
    contentItem: Item {
        Rectangle {
            id: thumb
            width: 18
            height: 18
            radius: 9
            x: root.value ? parent.width - width : 0
            y: (parent.height - height) / 2
            color: Theme.foregroundFor(track.color, root.enabled ? Theme.surfaceText : Theme.disabledFor(track.color), 3)
            Behavior on x { NumberAnimation { duration: Theme.controlDuration; easing.type: Easing.InOutQuad } }
        }
    }
    HoverHandler { enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    ThemeTooltip { target: root; text: root.tooltip; hovered: root.hovered; suppressForOverlay: false; textFont: Theme.bodyFont }
}
