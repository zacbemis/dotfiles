import QtQuick

Item {
    id: root
    property string text: ""
    property string icon: ""
    property color color: Theme.surfaceText
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Do not let a Nerd Font fallback change the text face or its line box.
    Row {
        id: row
        anchors.centerIn: parent
        spacing: space.advanceWidth
        TextMetrics { id: space; text: " "; font: Theme.barFont }
        ThemeText {
            text: root.text
            color: root.color
            font: Theme.barFont
            anchors.verticalCenter: parent.verticalCenter
        }
        GlyphIcon {
            glyph: root.icon
            color: root.color
            font: Theme.barIconFont
            inlineLabel: true
            anchors.verticalCenter: parent.verticalCenter
            visible: glyph !== ""
        }
    }
}
