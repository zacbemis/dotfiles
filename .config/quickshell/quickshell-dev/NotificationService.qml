pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property string mode: Quickshell.env("QUICKSHELL_NOTIFICATIONS")
        || (Quickshell.env("QUICKSHELL_ENABLE_NOTIFICATIONS") === "1" ? "server" : "off")
    property var notifications: []
    readonly property var popups: notifications.filter(record => record.popupVisible).slice(0, 5)
    property bool dnd: false
    property int sequence: 0
    readonly property int unreadCount: notifications.filter(record => !record.seen).length
    property var groups: []
    onNotificationsChanged: updateGroups()
    function updateGroups(): void {
        const previous = groups || [];
        const result = [];
        for (const record of notifications) {
            const name = record.appName || "Notifications";
            const key = name.toLowerCase();
            let group = result.find(group => group.key === key);
            if (!group) {
                group = {key: key, name: name, records: []};
                result.push(group);
            }
            group.records.push(record);
        }
        // ScriptModel preserves objects with matching keys. Mutable QObjects
        // keep existing delegates live when another record joins the same app.
        const next = result.map(info => {
            const group = previous.find(group => group.key === info.key)
                || groupComponent.createObject(root, {key: info.key});
            group.name = info.name;
            group.records = info.records;
            return group;
        });
        groups = next;
        for (const group of previous) if (!next.includes(group)) Qt.callLater(() => group.destroy());
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function age(timestamp): string {
        const minutes = Math.max(0, Math.floor((clock.date.getTime() - timestamp) / 60000));
        return minutes < 1 ? "now" : minutes < 60 ? minutes + "m"
            : minutes < 1440 ? Math.floor(minutes / 60) + "h" : Math.floor(minutes / 1440) + "d";
    }
    function markRead(): void { for (const record of notifications) record.seen = true; }
    function dismissGroup(key): void {
        for (const record of [...notifications])
            if ((record.appName || "Notifications").toLowerCase() === key.toLowerCase()) record.dismiss();
    }

    LazyLoader {
        active: root.mode === "server"
        NotificationBackend {}
    }

    Component { id: recordComponent; NotificationRecord {} }
    Component { id: groupComponent; NotificationGroupData {} }

    function popupAllowed(data): bool {
        return !dnd && !data.lastGeneration
            && !(data.appName === "Spotify" && data.urgency === NotificationUrgency.Low);
    }

    function receive(notification): void {
        notification.tracked = true;
        const old = notifications.find(record => record.notification === notification
            || (record.notification && record.notification.id === notification.id));
        if (old) {
            old.notification = notification;
            old.showPopup(popupAllowed(notification));
            notifications = [old, ...notifications.filter(record => record !== old)];
            return;
        }
        add(notification, null);
    }

    function add(notification, preview): void {
        const data = notification || preview;
        const record = recordComponent.createObject(root, {
            notification: notification,
            preview: preview,
            sequence: sequence++,
            seen: UiState.active === "notifications" || Boolean(data.lastGeneration),
            popupVisible: popupAllowed(data)
        });
        notifications = [record, ...notifications];
        // Limit mapped popups and history independently. Timers live on records,
        // so opening the center does not reset expiration or leak old popups.
        const visible = notifications.filter(item => item.popupVisible);
        for (const item of visible.slice(5)) item.hidePopup();
        if (notifications.length > 100) notifications[notifications.length - 1].dismiss();
    }

    function addPreview(summary, body, appName): bool {
        if (mode !== "preview") return false;
        add(null, {summary: summary, body: body, appName: appName || "Quickshell preview",
            appIcon: "preferences-desktop-notification", image: "", urgency: NotificationUrgency.Normal,
            expireTimeout: 4000, actions: [], transient: false});
        return true;
    }

    function remove(record): void {
        if (record.removed) return;
        record.removed = true;
        notifications = notifications.filter(item => item !== record);
        record.destroy();
    }

    function dismissAll(): void {
        for (const record of [...notifications]) record.dismiss();
    }

    function toggleDnd(): void {
        dnd = !dnd;
        if (dnd) for (const record of [...popups]) record.hidePopup();
    }
}
