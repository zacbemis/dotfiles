pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var choices: ({launcher: Preferences.choices.launcher, wallpaper: Preferences.choices.wallpaper,
        notifications: Preferences.choices.notifications, controls: Preferences.choices.controls, osd: Preferences.choices.osd})
    property string launcher: Preferences.value("launcher", "current")
    property string wallpaper: Preferences.value("wallpaper", "current")
    property string notifications: Preferences.value("notifications", "current")
    property string controls: Preferences.value("controls", "compact")
    property string osd: Preferences.value("osd", "off")
    property bool ready: false
    Component.onCompleted: ready = true
    onLauncherChanged: if (ready) Preferences.set("launcher", launcher)
    onWallpaperChanged: if (ready) Preferences.set("wallpaper", wallpaper)
    onNotificationsChanged: if (ready) Preferences.set("notifications", notifications)
    onControlsChanged: if (ready) Preferences.set("controls", controls)
    onOsdChanged: if (ready) Preferences.set("osd", osd)

    function select(feature, value): bool {
        if (!Object.keys(choices).includes(feature) || !choices[feature].includes(value)) return false;
        // Close before changing renderers. IPC/data controllers are not unloaded.
        if (UiState.active !== "settings") UiState.close("");
        root[feature] = value;
        return true;
    }
    function cycle(feature): bool {
        const list = choices[feature];
        return list ? select(feature, list[(list.indexOf(root[feature]) + 1) % list.length]) : false;
    }
    function status() {
        return {launcher: launcher, wallpaper: wallpaper, notifications: notifications,
            controls: controls, osd: osd, choices: choices};
    }
}
