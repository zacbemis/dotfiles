pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var notifications: []
    property var popups: []
    property bool dnd: false
    property int sequence: 0

    Component {
        id: recordComponent
        NotificationRecord {}
    }

    NotificationServer {
        id: server

        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false

        onNotification: function(notification) {
            notification.tracked = true;

            // Replace a previous notification with the same D-Bus id.
            const old = root.notifications.find(function(record) {
                return record.notification && record.notification.id === notification.id;
            });
            if (old) root.remove(old);

            const record = recordComponent.createObject(root, {
                notification: notification,
                sequence: root.sequence++,
                popupVisible: !root.dnd
            });

            root.notifications = [record, ...root.notifications];
            if (!root.dnd) root.popups = [record, ...root.popups];

            // Keep the history bounded while matching SwayNC's visible-popup
            // limit closely.
            if (root.notifications.length > 100) {
                const oldest = root.notifications[root.notifications.length - 1];
                root.remove(oldest);
            }
            while (root.popups.length > 5) {
                root.popups[root.popups.length - 1].popupVisible = false;
                root.popups = root.popups.slice(0, -1);
            }
        }
    }

    function remove(record): void {
        root.notifications = root.notifications.filter(function(item) {
            return item !== record;
        });
        root.popups = root.popups.filter(function(item) {
            return item !== record;
        });
    }

    function dismissAll(): void {
        const records = [...root.notifications];
        root.notifications = [];
        root.popups = [];

        for (const record of records) {
            if (record.notification) {
                try { record.notification.dismiss(); } catch (error) {}
            }
            record.destroy();
        }
    }

    function toggleDnd(): void {
        root.dnd = !root.dnd;
        if (root.dnd) {
            for (const record of root.popups) record.popupVisible = false;
            root.popups = [];
        }
    }
}
