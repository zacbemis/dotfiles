import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.theme

// Quiet OS-style list entry. Selecting/expanding is deliberately separate from
// connecting or disconnecting; explicit actions belong beneath the selected row.
AbstractButton {
    id: root
    property string subtitle: ""
    property string glyph: ""
    property string tooltip: ""
    property bool selected: false
    property bool marked: false
    property bool expandable: true
    readonly property color effectiveSurface: Qt.tint(Theme.background, plate.color)
    readonly property color contentColor: enabled ? Theme.foregroundFor(effectiveSurface, Theme.surfaceText) : Theme.disabledFor(effectiveSurface)
    readonly property color supportingColor: Theme.foregroundFor(effectiveSurface, Theme.surfaceVariantText)
    implicitWidth: 180
    implicitHeight: Math.max(40, labels.implicitHeight + 16)
    padding: 8
    focusPolicy: Qt.StrongFocus
    Accessible.name: text + (marked ? ", selected" : "")
    Accessible.description: subtitle
    Accessible.selected: selected || marked
    background: Rectangle {
        id: plate
        radius: 8
        color: root.selected || root.marked ? Theme.surfaceContainer : root.hovered || root.down ? Theme.surfaceContainerHigh : Theme.transparentColor
        border.width: root.activeFocus ? 1 : 0
        border.color: Theme.focusRing
    }
    contentItem: RowLayout {
        spacing: 10
        GlyphIcon { visible: root.glyph !== ""; glyph: root.glyph; size: 19; color: Theme.foregroundFor(root.effectiveSurface, Theme.primaryInk) }
        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 2
            ThemeText { Layout.fillWidth: true; text: root.text; textRole: "label"; color: root.contentColor; elide: Text.ElideRight }
            ThemeText { Layout.fillWidth: true; visible: root.subtitle !== ""; text: root.subtitle; textRole: "body"; font.pixelSize: 11; color: root.supportingColor; elide: Text.ElideRight }
        }
        GlyphIcon { visible: root.marked; glyph: ""; size: 13; color: Theme.foregroundFor(root.effectiveSurface, Theme.primaryInk) }
        GlyphIcon { visible: root.expandable; glyph: root.selected ? "" : ""; size: 10; color: Theme.foregroundFor(root.effectiveSurface, Theme.surfaceVariantText) }
    }
    HoverHandler { enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    ThemeTooltip { target: root; text: root.tooltip; hovered: root.hovered; suppressForOverlay: false; textFont: Theme.bodyFont }
}
