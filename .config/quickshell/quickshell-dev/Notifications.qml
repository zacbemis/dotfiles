import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

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
        function group_toggle(app: string): bool { return root.toggleGroup(app); }
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
                popups: NotificationService.popups.length, dnd: root.dnd, unread: root.unreadCount,
                groups: NotificationService.groups.map((group, index) => ({key: group.key, name: group.name,
                    rendered: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).shown.length : -1,
                    font: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).resolvedFont : null,
                    bodies: notificationList.itemAtIndex(index) ? notificationList.itemAtIndex(index).bodyStates() : [],
                    count: group.records.length, collapsed: root.collapsedGroups.includes(group.key),
                    shown: root.collapsedGroups.includes(group.key) ? 0
                        : root.expandedGroups.includes(group.key) ? group.records.length : Math.min(3, group.records.length)})),
                panel: {y: centerCard.y, height: centerCard.height, popupTop: popupWindow.margins.top},
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
        anchors { top: true; left: true }
        margins { top: UiState.topInset(popupWindow.screen); left: 16 }
        implicitWidth: Math.min(400, screen ? screen.width - 32 : 400)
        implicitHeight: Math.min(popupColumn.implicitHeight,
            screen ? Math.max(1, screen.height - margins.top - 16) : 700)
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
                    NotificationCard {
                        required property var modelData
                        width: popupColumn.width
                        record: modelData
                    }
                }
            }
        }
    }

    OverlayWindow {
        id: centerWindow
        route: "notifications"
        dimBackground: false
        popIn: false
        onOpenedChanged: if (opened) NotificationService.markRead()

        Rectangle {
            id: centerCard
            opacity: centerWindow.surfaceOpacity
            x: 16
            y: Math.min(UiState.topInset(centerWindow.screen), Math.max(12, parent.height - 200))
            width: Math.min(380, parent.width - 32)
            height: Math.max(0, Math.min(700, parent.height - y - 16))
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
                        text: "Notifications"
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                    ThemeButton {
                        text: "󰀻"
                        iconOnly: true
                        onClicked: UiState.show("launcher")
                        tooltip: "Applications"
                    }
                    ThemeButton {
                        text: ""
                        iconOnly: true
                        onClicked: UiState.show("wallpaper")
                        tooltip: "Wallpapers"
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

                ThemeText {
                    Layout.fillWidth: true
                    visible: NotificationService.mode === "preview"
                    text: "Preview mode · SwayNC is still handling live notifications"
                    wrapMode: Text.Wrap
                    color: Theme.surfaceVariantText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 8
                    color: Theme.controlBackground
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        ThemeText {
                            Layout.fillWidth: true
                            text: SystemState.updateCheckRunning ? "Checking updates…"
                                : !SystemState.updatesKnown ? "Updates not checked"
                                : SystemState.updateCount > 0 ? SystemState.updateCount + " updates available"
                                : "System up to date"
                            color: Theme.controlSurfaceText
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            enabled: !SystemState.updateCheckRunning
                            onClicked: SystemState.refreshUpdates()
                            tooltip: "Check updates"
                        }
                        ThemeButton {
                            text: ""
                            iconOnly: true
                            surfaceColor: Theme.controlBackground
                            onClicked: SystemState.runUpdates()
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
                    readonly property var player: Mpris.players.values.find(p => p.isPlaying)
                        || Mpris.players.values[0] || null
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        ColumnLayout {
                            Layout.fillWidth: true
                            ThemeText {
                                Layout.fillWidth: true
                                text: mediaCard.player ? mediaCard.player.trackTitle || mediaCard.player.identity : ""
                                color: Theme.controlSurfaceText
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            ThemeText {
                                Layout.fillWidth: true
                                text: mediaCard.player ? mediaCard.player.trackArtist : ""
                                color: Theme.alpha(Theme.controlSurfaceText, 0.8)
                                font.family: Theme.fontFamily
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
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    ThemeText {
                        Layout.fillWidth: true
                        text: "Do not disturb"
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                    Switch {
                        id: dndSwitch
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 26
                        checked: root.dnd
                        onClicked: root.toggleDnd()
                        indicator: Rectangle {
                            implicitWidth: 46
                            implicitHeight: 24
                            y: (dndSwitch.height - height) / 2
                            radius: 8
                            color: dndSwitch.hovered ? Theme.controlHoverBackground
                                : dndSwitch.checked ? Theme.controlPressedBackground : Theme.controlBackground
                            border.color: dndSwitch.activeFocus ? Theme.primary : Theme.outlineVariant
                            Behavior on color {
                                ColorAnimation { duration: Theme.controlDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEase }
                            }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                y: 3
                                x: dndSwitch.checked ? 25 : 3
                                color: Theme.controlText
                                Behavior on x {
                                    NumberAnimation { duration: Theme.controlDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEase }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    ThemeText {
                        Layout.fillWidth: true
                        text: root.count + (root.count === 1 ? " notification" : " notifications")
                        color: Theme.surfaceVariantText
                        font.pixelSize: 11
                    }
                    ThemeText {
                        text: root.dnd ? "Popups paused" : "Popups enabled"
                        color: root.dnd ? Theme.tertiary : Theme.surfaceVariantText
                        font.pixelSize: 10
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
                        color: Theme.surfaceVariantText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        visible: notificationList.count === 0
                    }
                }
            }
        }
    }
}
