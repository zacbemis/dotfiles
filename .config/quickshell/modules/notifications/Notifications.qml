import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.components
import qs.services
import qs.theme

Scope {
    id: root

    readonly property int count: NotificationService.notifications.length
    readonly property bool dnd: NotificationService.dnd
    readonly property int unreadCount: NotificationService.unreadCount
    property var collapsedGroups: []
    property var expandedGroups: []
    function toggleGroup(key): bool {
        key = key.toLowerCase();
        if (!NotificationService.groups.some(group => group.key === key)) return false;
        collapsedGroups = collapsedGroups.includes(key) ? collapsedGroups.filter(item => item !== key)
            : [...collapsedGroups, key];
        return true;
    }
    function expandGroup(key): bool {
        key = key.toLowerCase();
        if (!NotificationService.groups.some(group => group.key === key)) return false;
        collapsedGroups = collapsedGroups.filter(item => item !== key);
        expandedGroups = expandedGroups.includes(key) ? expandedGroups.filter(item => item !== key)
            : [...expandedGroups, key];
        return true;
    }
    Connections {
        target: NotificationService
        function onGroupsChanged() {
            const keys = NotificationService.groups.map(group => group.key);
            root.collapsedGroups = root.collapsedGroups.filter(key => keys.includes(key));
            root.expandedGroups = root.expandedGroups.filter(key => keys.includes(key));
        }
    }
    readonly property bool centerOpen: UiState.active === "notifications"
    function toggleCenter(): void { UiState.toggle("notifications"); }
    function toggleDnd(): void { NotificationService.toggleDnd(); }

    Binding { target: UpdateService; property: "pollingEnabled"; value: (root.centerOpen && FeatureSettings.notifications === "current") || UiState.active === "controls" }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleCenter(); }
        function open(): void { UiState.show("notifications"); }
        function close(): void { UiState.close("notifications"); }
        function clear(): void { NotificationService.dismissAll(); }
        function dnd_toggle(): void { root.toggleDnd(); }
        function preview(summary: string, body: string): bool {
            return NotificationService.addPreview(summary, body);
        }
        function preview_app(app: string, summary: string, body: string): bool {
            return NotificationService.addPreview(summary, body, app);
        }
        function group_toggle(app: string): bool { return FeatureSettings.notifications === "stacked" ? alternative.toggleGroup(app) : root.toggleGroup(app); }
        function filter(period: int): bool {
            if (FeatureSettings.notifications !== "stacked" || period < 0 || period > 2) return false;
            alternative.timeFilter = period;
            return true;
        }
        function group_expand(app: string): bool { return root.expandGroup(app); }
        function group_dismiss(app: string): void { NotificationService.dismissGroup(app); }
        function message_expand(sequence: int): bool {
            for (let i = 0; i < notificationList.count; ++i) {
                const group = notificationList.itemAtIndex(i);
                if (group && group.expandBody(sequence)) return true;
            }
            return false;
        }
        function status(): string {
            return JSON.stringify({mode: NotificationService.mode, count: root.count,
                popups: NotificationService.popups.length,
                view: FeatureSettings.notifications, alternative: alternative.metrics(),
                fonts: FeatureSettings.notifications === "current" ? Theme.auditText(centerCard) : alternative.typography(),
                popupEligibleCount: NotificationService.notifications.filter(record => record.popupVisible).length,
                dnd: root.dnd, unread: root.unreadCount,
                groups: NotificationService.groups.map((group, index) => ({key: group.key, name: group.name,
                    rendered: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).shown.length : -1,
                    font: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).resolvedFont : null,
                    bodies: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).bodyStates() : [],
                    count: group.records.length, collapsed: root.collapsedGroups.includes(group.key),
                    shown: root.collapsedGroups.includes(group.key) ? 0
                        : root.expandedGroups.includes(group.key) ? group.records.length : Math.min(3, group.records.length)})),
                panel: {x: centerCard.x, y: centerCard.y, width: centerCard.width, height: centerCard.height, insets: centerWindow.windowInsets,
                    popupTop: popupWindow.margins.top, popupRight: popupWindow.margins.right},
                summaries: NotificationService.notifications.map(record => record.summary),
                records: NotificationService.notifications.map(record => ({
                    id: record.notification ? record.notification.id : record.sequence, sequence: record.sequence,
                    timeoutMs: record.timeoutMs, hovered: record.hovered, seen: record.seen,
                    receivedAt: record.receivedAt}))});
        }
    }

    // One popup surface, on the current monitor. Never steals keyboard focus.
    PanelWindow {
        id: popupWindow
        readonly property var windowInsets: UiState.insets(screen)
        screen: {
            const monitor = Hyprland.focusedMonitor;
            return Quickshell.screens.find(s => monitor && s.name === monitor.name)
                || Quickshell.screens[0] || null;
        }
        visible: UiState.active === "" && NotificationService.popups.length > 0
        color: Theme.transparentColor
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-dev-notification-popups"
        anchors { top: true; left: FeatureSettings.notifications === "current"; right: FeatureSettings.notifications !== "current" }
        margins { top: popupWindow.windowInsets.top; left: popupWindow.windowInsets.left; right: popupWindow.windowInsets.right }
        implicitWidth: Math.min(360, screen ? Math.max(0, screen.width - windowInsets.left - windowInsets.right) : 360)
        implicitHeight: Math.min(popupColumn.implicitHeight,
            screen ? Math.max(1, screen.height - margins.top - windowInsets.bottom) : 700)
        Flickable {
            anchors.fill: parent
            contentHeight: popupColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: popupColumn
                width: popupWindow.width
                spacing: 8
                Repeater {
                    model: ScriptModel { values: NotificationService.popups; objectProp: "sequence" }
                    Loader {
                        id: popupDelegate
                        required property var modelData
                        width: popupColumn.width
                        height: item ? item.implicitHeight : 0
                        sourceComponent: FeatureSettings.notifications === "current" ? original : compact
                        Component { id: original; NotificationCard { width: popupDelegate.width; record: popupDelegate.modelData } }
                        Component { id: compact; CompactCard { width: popupDelegate.width; record: popupDelegate.modelData } }
                    }
                }
            }
        }
    }

    AlternativeCenter { id: alternative }

    OverlayWindow {
        id: centerWindow
        routeEnabled: FeatureSettings.notifications === "current"
        route: "notifications"
        dimBackground: false
        popIn: false
        onOpenedChanged: if (opened) NotificationService.markRead()

        Rectangle {
            id: centerCard
            opacity: centerWindow.surfaceOpacity
            x: centerWindow.windowInsets.left
            y: centerWindow.windowInsets.top
            width: Math.max(0, Math.min(360, parent.width - centerWindow.windowInsets.left - centerWindow.windowInsets.right))
            height: Math.max(0, Math.min(root.count > 0 ? 560 : 300, parent.height - y - centerWindow.windowInsets.bottom))
            radius: 12
            color: Theme.background
            border.color: Theme.outlineVariant
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ThemeText {
                        Layout.fillWidth: true
                        text: NotificationService.mode === "preview" ? "Notifications · Preview" : "Notifications"
                        textRole: "title"
                        color: Theme.surfaceText
                        font.pixelSize: 18
                        elide: Text.ElideRight
                    }
                    ThemeToggle {
                        label: "Do not disturb"
                        value: NotificationService.dnd
                        onRequested: value => { if (value !== NotificationService.dnd) NotificationService.toggleDnd(); }
                    }
                    ThemeButton {
                        text: "󰎟"
                        iconOnly: true
                        baseColor: Theme.controlBackground
                        enabled: root.count > 0
                        onClicked: NotificationService.dismissAll()
                        tooltip: "Clear all notifications"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: UpdateService.known || UpdateService.checking || UpdateService.error !== ""
                    implicitHeight: 38
                    radius: 8
                    color: Theme.controlBackground
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        ThemeText {
                            Layout.fillWidth: true
                            text: UpdateService.checking ? "Checking updates…"
                                : UpdateService.error ? "Update check failed"
                                : !UpdateService.known ? "Updates not checked"
                                : UpdateService.count > 0 ? UpdateService.count + " updates available"
                                : "System up to date"
                            color: Theme.controlSurfaceText
                            textRole: "body"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            enabled: !UpdateService.checking
                            onClicked: UpdateService.refresh()
                            tooltip: UpdateService.error || "Check updates"
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            onClicked: UpdateService.runUpdates()
                            tooltip: "Open updater in Kitty"
                        }
                    }
                }

                Rectangle {
                    id: mediaCard
                    Layout.fillWidth: true
                    implicitHeight: 60
                    radius: 8
                    color: Theme.controlBackground
                    visible: player !== null
                    property int playerIndex: -1
                    readonly property var player: (playerIndex >= 0 ? Mpris.players.values[playerIndex] : null)
                        || Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        ColumnLayout {
                            Layout.fillWidth: true
                            ThemeText {
                                Layout.fillWidth: true
                                text: mediaCard.player ? mediaCard.player.trackTitle || mediaCard.player.identity : ""
                                textRole: "display"
                                color: Theme.controlSurfaceText
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            ThemeText {
                                Layout.fillWidth: true
                                text: mediaCard.player ? mediaCard.player.trackArtist : ""
                                color: Theme.surfaceVariantText
                                textRole: "body"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            enabled: !!mediaCard.player && mediaCard.player.canGoPrevious
                            onClicked: mediaCard.player.previous()
                            tooltip: "Previous track"
                        }
                        ThemeButton {
                            text: mediaCard.player && mediaCard.player.isPlaying ? "" : ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            enabled: !!mediaCard.player && mediaCard.player.canTogglePlaying
                            onClicked: mediaCard.player.togglePlaying()
                            tooltip: "Play / pause"
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            enabled: !!mediaCard.player && mediaCard.player.canGoNext
                            onClicked: mediaCard.player.next()
                            tooltip: "Next track"
                        }
                        ThemeButton {
                            text: "󰑓"
                            iconOnly: true
                            visible: Mpris.players.values.length > 1
                            surfaceColor: Theme.controlBackground
                            tooltip: "Switch player · " + (mediaCard.player ? mediaCard.player.identity : "")
                            onClicked: mediaCard.playerIndex = (Mpris.players.values.indexOf(mediaCard.player) + 1) % Mpris.players.values.length
                        }
                    }
                }

                ListView {
                    id: notificationList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ThemeScrollBar {}
                    model: ScriptModel { values: NotificationService.groups; objectProp: "key" }
                    delegate: NotificationGroup {
                        required property var modelData
                        width: notificationList.width - 8
                        group: modelData
                        collapsed: modelData ? root.collapsedGroups.includes(modelData.key) : false
                        expanded: modelData ? root.expandedGroups.includes(modelData.key) : false
                        onToggleRequested: if (modelData) root.toggleGroup(modelData.key)
                        onExpandRequested: if (modelData) root.expandGroup(modelData.key)
                    }
                    ThemeText {
                        anchors.centerIn: parent
                        text: "No notifications"
                        textRole: "label"
                        color: Theme.surfaceVariantText
                        font.pixelSize: 13
                        visible: notificationList.count === 0
                    }
                }
            }
        }
    }
}
