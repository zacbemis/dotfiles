import QtQuick
import QtQuick.Controls

ToolButton {
    id: root
    property string tooltip: ""
    property bool pickerStyle: false
    property bool iconOnly: false
    property color baseColor: Theme.transparentColor
    property color surfaceColor: Theme.background
    font: Theme.uiFont
    implicitWidth: iconOnly ? 32 : Math.max(30, label.implicitWidth + 16)
    implicitHeight: 32
    padding: 6
    readonly property color contentColor: !enabled ? Theme.alpha(Theme.foregroundFor(surfaceColor, Theme.surfaceText), 0.45)
        : pickerStyle ? (hovered || down ? Theme.pickerSelectedText
            : Theme.foregroundFor(Qt.tint(surfaceColor, buttonBackground.color), Theme.surfaceText))
        : Theme.foregroundFor(Qt.tint(surfaceColor, buttonBackground.color), Theme.controlText)
    background: Rectangle {
        id: buttonBackground
        radius: 6
        color: root.down ? (root.pickerStyle ? Theme.pickerSelectedBackground : Theme.controlPressedBackground)
            : root.hovered ? (root.pickerStyle ? Theme.pickerSelectedBackground : Theme.controlHoverBackground)
            : root.baseColor
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.secondary
        // Rofi selections are immediate; SwayNC controls use CSS's 200ms ease.
        Behavior on color {
            enabled: !root.pickerStyle
            ColorAnimation { duration: Theme.controlDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEase }
        }
    }
    contentItem: Item {
        ThemeText {
            id: label
            anchors.fill: parent
            visible: !root.iconOnly
            text: root.text
            textFormat: Text.PlainText
            font: root.font
            color: root.contentColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        GlyphIcon {
            anchors.centerIn: parent
            visible: root.iconOnly
            glyph: root.text
            color: root.contentColor
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.controlIconSize
            font.bold: true
        }
    }
    BarTooltip {
        target: root
        text: root.tooltip
        hovered: root.hovered
        suppressForOverlay: false
        textFont: Theme.uiFont
    }
}
