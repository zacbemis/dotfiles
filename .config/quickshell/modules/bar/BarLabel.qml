import QtQuick
import qs.components
import qs.theme

Item {
    id: root
    property string text: ""
    property string icon: ""
    property var indicatorState: null
    property color color: Theme.surfaceText
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    function presentation() { return {text: text, iconVisible: status.visible, textVisible: caption.visible, iconColor: String(status.color), iconPaintSize: status.inkSize}; }

    // Do not let a Nerd Font fallback change the text face or its line box.
    Row {
        id: row
        anchors.centerIn: parent
        spacing: space.advanceWidth
        TextMetrics { id: space; text: " "; font: Theme.barFont }
        ThemeText {
            id: caption
            visible: root.text !== ""
            text: root.text
            textRole: "bar"
            color: root.color
            anchors.verticalCenter: parent.verticalCenter
        }
        GlyphIcon {
            glyph: root.icon
            color: Theme.barIconColor
            font: Theme.barIconFont
            inlineLabel: true
            y: (parent.height - height) / 2
            visible: !root.indicatorState && glyph !== ""
        }
        StatusIcon {
            id: status
            y: (parent.height - height) / 2
            visible: !!root.indicatorState && root.indicatorState.icon
            reading: root.indicatorState || ({})
            size: Theme.barIconFont.pixelSize
            inkSize: Theme.barStatusPaintSize(status.kind, size)
            color: Theme.barIconColor
        }
    }
}
