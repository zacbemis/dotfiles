//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark

import Quickshell

Scope {
    id: root

    // Leave this disabled while SwayNC is running. Enable it for notification
    // testing with: QUICKSHELL_ENABLE_NOTIFICATIONS=1 qs -p shell.qml
    readonly property bool enableNotifications:
        (Quickshell.env("QUICKSHELL_ENABLE_NOTIFICATIONS") || "") === "1"

    Bar {
        notificationUi: notificationLoader.item
    }

    Launcher {}
    WallpaperPicker {}

    // Lazy loading keeps the development shell compatible with the existing
    // SwayNC daemon until notification work is ready to test.
    LazyLoader {
        id: notificationLoader
        active: root.enableNotifications
        Notifications {}
    }
}
