import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.theme

AbstractButton {
    id: root
    required property string category
    required property var option
    property bool selected: false
    signal chosen()
    implicitWidth: 220
    implicitHeight: 92
    padding: 10
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.RadioButton
    Accessible.name: option.label + ". " + option.description
    Accessible.checkable: true
    Accessible.checked: selected
    onClicked: chosen()
    background: Rectangle {
        radius: 10
        color: root.selected || root.hovered ? Theme.surfaceContainer : Theme.panelSurface
        border.width: root.selected || root.activeFocus ? 1 : 0
        border.color: root.activeFocus ? Theme.focusRing : root.selected ? Theme.primaryInk : Theme.outlineVariant
    }
    ThemeTooltip { target: root; hovered: root.hovered; text: root.option.description; suppressForOverlay: false }
    contentItem: ColumnLayout {
        spacing: 7
        RowLayout {
            Layout.fillWidth: true
            ThemeText { Layout.fillWidth: true; text: root.option.label; textRole: "label"; font.pixelSize: 14; elide: Text.ElideRight }
            GlyphIcon { glyph: root.selected ? "" : ""; size: 15; color: root.selected ? Theme.primaryInk : Theme.surfaceVariantText }
        }
        ChoicePreview { Layout.fillWidth: true; Layout.preferredHeight: 40; category: root.category; variant: root.option.key }
    }
}
