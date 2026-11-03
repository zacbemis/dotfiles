import QtQuick
import Quickshell
import qs.services
import qs.theme

PopupWindow {
    id: root
    required property Item target
    property string text: ""
    property bool hovered: false
    property bool suppressForOverlay: true
    property font textFont: Theme.tooltipFont
    function layoutStatus() {
        const point = contentItem.mapToGlobal(0, 0);
        const source = target ? target.mapToGlobal(0, 0) : {x: 0, y: 0};
        return {visible: visible, x: point.x, y: point.y, width: width, height: height,
            target: {x: source.x, y: source.y, width: target ? target.width : 0, height: target ? target.height : 0},
            label: {x: label.x, width: label.width, alignment: label.horizontalAlignment}};
    }
    anchor.item: target
    // A thin anchor below the hit area avoids inclusive-bottom/margin offsets.
    // With no horizontal edge/gravity, the popup is centered on this rectangle.
    anchor.rect.x: 0
    anchor.rect.y: (target ? target.height : 0) + UiState.windowGap
    anchor.rect.width: target ? Math.max(1, target.width) : 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Bottom
    visible: !!target && target.visible && !delay.running && hovered && (!suppressForOverlay || UiState.active === "") && text !== ""
    color: Theme.transparentColor
    implicitWidth: label.implicitWidth + 20
    implicitHeight: label.implicitHeight + 14
    onHoveredChanged: if (hovered) delay.restart(); else delay.stop()
    onImplicitWidthChanged: if (visible) anchor.updateAnchor()
    Connections {
        target: root.target
        function onXChanged() { if (root.visible) root.anchor.updateAnchor(); }
        function onYChanged() { if (root.visible) root.anchor.updateAnchor(); }
        function onWidthChanged() { if (root.visible) root.anchor.updateAnchor(); }
        function onHeightChanged() { if (root.visible) root.anchor.updateAnchor(); }
    }
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
            textRole: "tooltip"
            horizontalAlignment: Text.AlignHCenter
            color: Theme.surfaceText
            font: root.textFont
        }
    }
}
