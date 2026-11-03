import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme

Item {
    id: root
    required property var group
    property bool collapsed: false
    property bool expanded: false
    signal toggleRequested()
    signal expandRequested()
    readonly property var records: group ? group.records : []
    readonly property var shown: collapsed ? [] : expanded ? records : records.slice(0, 3)
    implicitHeight: content.implicitHeight
    HoverHandler { id: groupHover }
    activeFocusOnTab: true
    Keys.onDeletePressed: if (root.group) NotificationService.dismissGroup(root.group.key)
    function bodyStates() {
        const result = [];
        for (let i = 0; i < cards.count; ++i) {
            const card = cards.itemAt(i);
            if (card && card.record && !card.record.removed) result.push({sequence: card.record.sequence,
                truncated: card.bodyTruncated, expanded: card.expandedBody});
        }
        return result;
    }
    function expandBody(sequence): bool {
        for (let i = 0; i < cards.count; ++i) {
            const card = cards.itemAt(i);
            if (card && card.record && !card.record.removed && card.record.sequence === sequence) {
                card.toggleBody();
                return true;
            }
        }
        return false;
    }
    readonly property var resolvedFont: ({family: groupName.fontInfo.family,
        bold: groupName.fontInfo.bold, pixelSize: groupName.fontInfo.pixelSize})

    ColumnLayout {
        id: content
        width: parent.width
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ThemeButton {
                text: root.collapsed ? "" : ""
                iconOnly: true
                tooltip: root.collapsed ? "Expand group" : "Collapse group"
                onClicked: root.toggleRequested()
            }
            ThemeText {
                id: groupName
                Layout.fillWidth: true
                text: root.group ? root.group.name : ""
                textRole: "title"
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            ThemeText {
                text: root.records.length
                textRole: "body"
                color: Theme.surfaceVariantText
                font.pixelSize: 11
            }
            ThemeButton {
                text: "󰆴"
                iconOnly: true
                opacity: groupHover.hovered || root.activeFocus || activeFocus ? 1 : 0
                enabled: opacity > 0
                tooltip: "Dismiss this application's notifications"
                onClicked: if (root.group) NotificationService.dismissGroup(root.group.key)
            }
        }
        Repeater {
            id: cards
            model: ScriptModel { values: root.shown; objectProp: "sequence" }
            NotificationCard {
                required property var modelData
                Layout.fillWidth: true
                record: modelData
                centerCard: true
                showAppName: false
            }
        }
        ThemeButton {
            Layout.fillWidth: true
            visible: !root.collapsed && root.records.length > 3
            text: root.expanded ? "Show fewer" : "Show " + (root.records.length - 3) + " older"
            onClicked: root.expandRequested()
        }
    }
}
