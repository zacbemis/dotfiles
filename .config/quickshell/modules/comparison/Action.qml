import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme

// Shared adapter control, not an upstream widget. Labels and glyphs use
// separate fonts so a missing upstream font never hides a required feature.
Rectangle {
    id: root
    property string glyph: ""
    property string controlKey: ""
    property var indicatorState: null
    property bool labelWhenCompact: false
    function geometry() { const item = indicatorState ? statusIcon : icon;
        return {key: controlKey, x: x, width: width, iconX: x + label.x + item.x,
            iconSize: item.visible ? item.height : 0, iconWidth: item.visible ? item.width : 0, iconPaintSize: item.inkSize,
            text: text, textVisible: caption.visible, iconVisible: item.visible, iconColor: String(item.color)}; }
    property string text: ""
    property string tooltip: ""
    property color foreground: Style.text
    property color iconColor: Style.icon
    readonly property color contentColor: Theme.foregroundFor(Qt.tint(Style.background, color), foreground)
    property bool compact: false
    property bool interactive: true
    signal clicked(int button)
    signal scrolled(real delta)
    implicitWidth: label.implicitWidth + 12
    implicitHeight: 26
    radius: 5
    color: Qt.tint(Theme.opaque(Style.background), root.interactive && mouse.containsMouse ? Style.surface : "transparent")
    Behavior on color { ColorAnimation { duration: Style.duration } }
    Row {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2
        spacing: 5
        GlyphIcon {
            id: icon
            visible: !root.indicatorState && root.glyph !== ""
            y: (parent.height - height) / 2
            glyph: root.glyph
            color: root.iconColor
            size: 14
            inkSize: root.controlKey === "controls" ? Theme.barSettingsPaintSize : size
            font.family: Theme.iconFontFamily
        }
        StatusIcon {
            id: statusIcon
            y: (parent.height - height) / 2
            visible: !!root.indicatorState && root.indicatorState.icon
            reading: root.indicatorState || ({})
            color: root.iconColor
            size: 14
            inkSize: Theme.barStatusPaintSize(root.controlKey, size)
        }
        ThemeText {
            id: caption
            anchors.verticalCenter: parent.verticalCenter
            visible: (!root.compact || root.labelWhenCompact) && root.text !== ""
            text: root.text
            textRole: "bar"
            font.pixelSize: Style.font.pixelSize
            color: root.contentColor
            renderType: Text.NativeRendering
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: root.interactive ? Qt.LeftButton | Qt.RightButton | Qt.MiddleButton : Qt.NoButton
        onClicked: event => root.clicked(event.button)
        onWheel: event => { if (root.interactive && event.angleDelta.y) root.scrolled(event.angleDelta.y); else event.accepted = false; }
    }
    ThemeTooltip { target: root; hovered: mouse.containsMouse; text: root.tooltip }
}
