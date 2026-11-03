import QtQuick
import QtQuick.Controls
import qs.theme

ToolButton {
    id: root
    property string tooltip: ""
    property bool pickerStyle: false
    property bool iconOnly: false
    property bool outlined: false
    property color baseColor: Theme.transparentColor
    property color surfaceColor: Theme.backgroundAlpha
    property string textRole: "label"
    Accessible.name: tooltip || text
    readonly property font roleFont: Theme.fontForRole(textRole)
    font.family: roleFont.family
    font.pixelSize: roleFont.pixelSize
    font.weight: roleFont.weight
    font.hintingPreference: roleFont.hintingPreference
    implicitWidth: iconOnly ? 32 : Math.max(30, label.implicitWidth + 16)
    implicitHeight: 32
    padding: 6
    readonly property color effectiveSurface: buttonBackground.color
    readonly property color contentColor: !enabled ? Theme.disabledFor(effectiveSurface)
        : Theme.foregroundFor(effectiveSurface, pickerStyle && (hovered || down)
            ? Theme.pickerSelectedText : Theme.controlText)
    background: Rectangle {
        id: buttonBackground
        radius: 6
        // A solid backplate keeps intermediate animation frames readable even
        // when the surrounding translucent panel is close to middle gray.
        color: Qt.tint(Theme.opaque(root.surfaceColor), root.down
            ? (root.pickerStyle ? Theme.pickerSelectedBackground : Theme.controlPressedBackground)
            : root.hovered ? (root.pickerStyle ? Theme.pickerSelectedBackground : Theme.controlHoverBackground)
            : root.baseColor)
        border.width: root.activeFocus ? (root.outlined ? 2 : 1) : root.outlined ? 1 : 0
        border.color: root.activeFocus || !root.outlined ? Theme.focusRing : Theme.foregroundFor(color, Theme.outlineVariant, 3)
        // Picker selections are immediate; controls use CSS's 200ms ease.
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
            textRole: root.textRole
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
            font.weight: Font.Normal
        }
    }
    ThemeTooltip {
        target: root
        text: root.tooltip
        hovered: root.hovered
        suppressForOverlay: false
        textFont: Theme.bodyFont
    }
}
