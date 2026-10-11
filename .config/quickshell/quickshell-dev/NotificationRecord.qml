import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: root

    property var notification: null
    property var preview: null
    property int sequence: 0
    property bool popupVisible: false
    property bool hovered: false
    property bool removed: false
    property bool seen: false
    property double receivedAt: Date.now()
    readonly property var data: notification || preview || ({})
    readonly property string summary: data.summary || ""
    readonly property string body: data.body || ""
    readonly property string appName: data.appName || ""
    readonly property string appIcon: data.appIcon || ""
    readonly property string image: data.image || ""
    readonly property var actions: [...(data.actions || [])].filter(action => action.identifier !== "default")
    readonly property int urgency: data.urgency ?? NotificationUrgency.Normal
    readonly property int timeoutMs: {
        const requested = Number(data.expireTimeout);
        // Verified against Arch Quickshell 0.3.1: this is the raw D-Bus value
        // in milliseconds (the v0.3.0 web docs incorrectly say seconds).
        // Zero is sticky; negative values request the server's default timeout.
        if (requested === 0) return 0;
        if (Number.isFinite(requested) && requested > 0) return Math.round(requested);
        return urgency === NotificationUrgency.Critical ? 6000
             : urgency === NotificationUrgency.Low ? 2000 : 4000;
    }

    readonly property Timer popupTimer: Timer {
        interval: Math.max(1, root.timeoutMs)
        running: root.popupVisible && !root.hovered && root.timeoutMs > 0
        onTriggered: root.hidePopup()
    }
    readonly property Connections notificationConnection: Connections {
        target: root.notification
        function onClosed() {
            root.notification = null;
            NotificationService.remove(root);
        }
        // A replaces-id update may reuse the same Notification object without
        // emitting a new server notification; restart its popup timeout too.
        function onSummaryChanged() { root.showPopup(NotificationService.popupAllowed(root.data)); }
        function onBodyChanged() { root.showPopup(NotificationService.popupAllowed(root.data)); }
        function onUrgencyChanged() { root.showPopup(NotificationService.popupAllowed(root.data)); }
        function onAppNameChanged() {
            root.showPopup(NotificationService.popupAllowed(root.data));
            NotificationService.updateGroups();
        }
    }

    function showPopup(visible): void {
        receivedAt = Date.now();
        seen = UiState.active === "notifications";
        popupVisible = false;
        popupVisible = visible;
    }

    function hidePopup(): void {
        popupVisible = false;
        if (notification && notification.transient) notification.expire();
    }

    function dismiss(): void {
        if (removed) return;
        if (notification) notification.dismiss(); // closed() owns cleanup
        else NotificationService.remove(root);
    }

    function invokeDefaultAction(): void {
        const action = [...(data.actions || [])].find(item => item.identifier === "default");
        if (action) invokeAction(action);
    }

    function invokeAction(action): void {
        seen = true;
        popupVisible = false;
        if (action) action.invoke();
    }
}
