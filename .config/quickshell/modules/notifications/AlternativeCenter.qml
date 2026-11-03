// SPDX-License-Identifier: MIT
// Compact frame/list adapted from MM-2103 NotificationCenterPopup.qml. Stacked
// card/time-filter presentation adapted from Dux Center sources (vendor/dux).
// Both are renderer-only ports over our single preview/live notification service.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme

OverlayWindow {
    id: root
    route: "notifications"
    routeEnabled: FeatureSettings.notifications !== "current"
    dimBackground: false
    popIn: false
    readonly property bool stacked: FeatureSettings.notifications === "stacked"
    property int timeFilter: 0
    property var collapsed: []
    SystemClock { id: clock; precision: SystemClock.Minutes }
    onOpenedChanged: if (opened) NotificationService.markRead()
    function recent(record): bool {
        const now = clock.date.getTime();
        const start = new Date(clock.date); start.setHours(0, 0, 0, 0);
        return timeFilter === 0 || record.receivedAt >= (timeFilter === 1 ? now - 3600000 : start.getTime());
    }
    function records(group) { return group && group.records ? group.records.filter(record => recent(record)) : []; }
    readonly property var shown: NotificationService.notifications.filter(record => recent(record))
    readonly property var groups: NotificationService.groups.filter(group => records(group).length > 0)
    function toggleGroup(key): bool {
        key = key.toLowerCase();
        if (!groups.some(group => group.key === key)) return false;
        collapsed = collapsed.includes(key) ? collapsed.filter(value => value !== key) : [...collapsed, key];
        return true;
    }
    function metrics() {
        const first = stacked ? stackList.itemAtIndex(0) : flatList.itemAtIndex(0);
        return {opened: opened, visible: visible, count: shown.length, groups: groups.length, fonts: root.typography(),
            filter: timeFilter, collapsed: collapsed, frame: {x: card.x, y: card.y, width: card.width, height: card.height}, insets: root.windowInsets,
            firstCardHeight: first ? (stacked ? first.firstCardHeight() : first.implicitHeight) : 0};
    }
    Rectangle {
        id: card
        opacity: root.surfaceOpacity
        x: Math.max(root.windowInsets.left, parent.width - width - root.windowInsets.right)
        y: root.windowInsets.top
        width: Math.max(0, Math.min(root.stacked ? 380 : 360, parent.width - root.windowInsets.left - root.windowInsets.right))
        height: Math.max(0, Math.min(root.shown.length ? (root.stacked ? 560 : 480) : 220, parent.height - y - root.windowInsets.bottom))
        radius: root.stacked ? 16 : 6
        color: Theme.background
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                ThemeText { Layout.fillWidth: true; textRole: "title"; text: NotificationService.mode === "preview" ? "Notifications · Preview" : "Notifications"; font.pixelSize: 15; elide: Text.ElideRight }
                ThemeButton { text: "󰎟"; iconOnly: true; tooltip: "Clear notifications"; enabled: NotificationService.notifications.length > 0; onClicked: NotificationService.dismissAll() }
                ThemeToggle {
                    label: "Do not disturb"
                    value: NotificationService.dnd
                    onRequested: value => { if (value !== NotificationService.dnd) NotificationService.toggleDnd(); }
                }
            }
            RowLayout {
                visible: root.stacked
                Repeater {
                    model: ["All", "Last hour", "Today"]
                    ThemeButton {
                        required property int index
                        required property string modelData
                        text: modelData
                        baseColor: root.timeFilter === index ? Theme.activeBackground : Theme.transparentColor
                        onClicked: root.timeFilter = index
                    }
                }
            }
            ListView {
                id: flatList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.stacked
                clip: true
                spacing: 6
                model: ScriptModel { values: root.visible && !root.stacked ? root.shown : []; objectProp: "sequence" }
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThemeScrollBar {}
                delegate: CompactCard { required property var modelData; width: flatList.width - 8; record: modelData; centerCard: true }
                ThemeText { anchors.centerIn: parent; text: "No notifications"; textRole: "label"; color: Theme.surfaceVariantText; visible: flatList.count === 0 }
            }
            ListView {
                id: stackList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.stacked
                clip: true
                spacing: 10
                model: ScriptModel { values: root.visible && root.stacked ? root.groups : []; objectProp: "key" }
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThemeScrollBar {}
                delegate: Rectangle {
                    id: group
                    required property var modelData
                    readonly property var members: root.records(modelData)
                    readonly property bool collapsed: root.collapsed.includes(modelData.key)
                    function firstCardHeight() { const card = cards.itemAt(0); return card ? card.implicitHeight : 0; }
                    width: stackList.width - 8
                    implicitHeight: column.implicitHeight + 16
                    radius: 14
                    color: Theme.surfaceContainer
                    HoverHandler { id: groupHover }
                    activeFocusOnTab: true
                    Keys.onDeletePressed: NotificationService.dismissGroup(group.modelData.key)
                    ColumnLayout {
                        id: column
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            ThemeButton {
                                Layout.fillWidth: true
                                text: (group.collapsed ? "▸ " : "▾ ") + group.modelData.name + " (" + group.members.length + ")"
                                textRole: "title"
                                font.pixelSize: 14
                                surfaceColor: Theme.surfaceContainer
                                onClicked: root.toggleGroup(group.modelData.key)
                            }
                            ThemeButton { text: "󰆴"; iconOnly: true; surfaceColor: Theme.surfaceContainer; tooltip: "Dismiss group"; opacity: groupHover.hovered || group.activeFocus || activeFocus ? 1 : 0; enabled: opacity > 0; onClicked: NotificationService.dismissGroup(group.modelData.key) }
                        }
                        Repeater {
                            id: cards
                            model: group.collapsed ? [] : group.members
                            CompactCard { required property var modelData; Layout.fillWidth: true; record: modelData; centerCard: true }
                        }
                    }
                }
                ThemeText { anchors.centerIn: parent; text: "No notifications in this period"; textRole: "label"; color: Theme.surfaceVariantText; visible: stackList.count === 0 }
            }
        }
    }
}
