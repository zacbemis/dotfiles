import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: root

    required property var notification
    property int sequence: 0
    property bool popupVisible: true
    property bool hovered: false

    readonly property string summary: notification ? (notification.summary || "") : ""
    readonly property string body: notification ? (notification.body || "") : ""
    readonly property string appName: notification ? (notification.appName || "") : ""
    readonly property string appIcon: notification ? (notification.appIcon || "") : ""
    readonly property string image: notification ? (notification.image || "") : ""
    readonly property var actions: notification
        ? (notification.actions || []).filter(function(action) {
            return action.identifier !== "default";
        })
        : []
    readonly property int urgency: notification ? notification.urgency : NotificationUrgency.Normal

    readonly property int timeoutMs: {
        const fallback = urgency === NotificationUrgency.Critical ? 6000
                       : urgency === NotificationUrgency.Low ? 2000 : 4000;
        const requested = notification ? Number(notification.expireTimeout) : 0;
        if (!Number.isFinite(requested) || requested <= 0) return fallback;
        // Quickshell exposes the D-Bus expire-timeout in milliseconds.
        return Math.round(requested);
    }

    readonly property Connections notificationConnection: Connections {
        target: root.notification

        function onClosed() {
            NotificationService.remove(root);
            root.destroy();
        }
    }

    function dismiss(): void {
        root.popupVisible = false;
        if (root.notification) {
            try { root.notification.dismiss(); } catch (error) {}
        }
        NotificationService.remove(root);
        root.destroy();
    }

    function invokeDefaultAction(): void {
        if (!notification) return;
        const action = (notification.actions || []).find(function(item) {
            return item.identifier === "default";
        });
        if (action) {
            try { action.invoke(); } catch (error) {}
        }
    }

    function invokeAction(action): void {
        root.popupVisible = false;
        if (action) {
            try { action.invoke(); } catch (error) {}
        }
    }
}
