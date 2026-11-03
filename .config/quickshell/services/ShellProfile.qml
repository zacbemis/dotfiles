pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var names: Preferences.choices.bar
    property string name: names.includes(Quickshell.env("QUICKSHELL_PROFILE"))
        ? Quickshell.env("QUICKSHELL_PROFILE") : Preferences.value("bar", "current")
    readonly property bool comparing: Quickshell.env("QUICKSHELL_COMPARE") === "1"
    // Daily layouts always follow the wallpaper; upstream palettes are only
    // the initial baseline in the explicitly launched comparison session.
    property bool wallpaperColors: Preferences.value("wallpaperColors", !comparing)
    property bool autoHide: Preferences.value("autoHide", false)
    property bool pinned: Preferences.value("pinned", false)
    property bool ready: false
    Component.onCompleted: ready = true
    onNameChanged: if (ready) Preferences.set("bar", name)
    onWallpaperColorsChanged: if (ready) Preferences.set("wallpaperColors", wallpaperColors)
    onAutoHideChanged: if (ready) Preferences.set("autoHide", autoHide)
    onPinnedChanged: if (ready) Preferences.set("pinned", pinned)
    readonly property string title: name === "enzo" ? "Enzo · floating" : name === "mm2103" ? "MM-2103 · flat" : "Current · wallpaper pills"
    readonly property string source: name === "enzo" ? "https://github.com/EnzoNotNice/quickshell-bar"
        : name === "mm2103" ? "https://github.com/MM-2103/quickshell-bar" : "local"

    function select(value): bool {
        if (!names.includes(value)) return false;
        if (UiState.active !== "settings") UiState.close("");
        if (name === value) return true;
        name = value;
        pinned = false;
        return true;
    }
    function next(): void { select(names[(names.indexOf(name) + 1) % names.length]); }

    // The click handlers and comparison IPC use the same feature dispatcher.
    // No upstream shell commands, installer, wallpaper daemon or server runs.
    function activate(feature): bool {
        if ((feature === "notifications" || feature === "dnd") && NotificationService.mode === "off") {
            Quickshell.execDetached(["swaync-client", feature === "dnd" ? "-d" : "-t", "-sw"]);
            return true;
        }
        if (feature === "controls") { ConnectivityService.toggleOverview(); return true; }
        if (["launcher", "wallpaper", "notifications", "settings"].includes(feature)) {
            UiState.toggle(feature);
            return true;
        }
        if (feature === "sample") return NotificationService.addPreview("Comparison notification",
            "Shared notification records survive bar and feature-view changes.", "Quickshell comparison");
        if (feature === "dnd") { NotificationService.toggleDnd(); return true; }
        return false;
    }
}
