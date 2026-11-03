pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var items: [
        {key: "apps", label: "Apps"}, {key: "run", label: "Run"}, {key: "files", label: "Files"},
        {key: "wallpaper", label: "Wallpapers"}, {key: "settings", label: "Settings"}
    ]
    readonly property string current: UiState.active === "launcher"
        ? (["run", "files"].includes(LauncherData.mode) ? LauncherData.mode : "apps") : UiState.active
    function select(key): bool {
        if (!items.some(item => item.key === key)) return false;
        if (["apps", "run", "files"].includes(key)) {
            UiState.show("launcher");
            return LauncherData.setMode(key);
        }
        UiState.show(key);
        return true;
    }
    function step(delta): bool {
        if (!UiState.active || !Number.isInteger(delta)) return false;
        const index = items.findIndex(item => item.key === current);
        if (index < 0) return false;
        return select(items[((index + delta) % items.length + items.length) % items.length].key);
    }
    function status() { return {current: current, items: items, screen: UiState.screenName}; }
}
