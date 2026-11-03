// SPDX-License-Identifier: MIT
// Auto-hide/input-region adaptation of MM-2103/quickshell-bar, Bar.qml at
// d31a94da14648439da05457d57b1648da9b3b18e. See vendor/mm2103/upstream/LICENSE.
// Host both imported layouts on every monitor; share our services and tray UI.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.services
import qs.theme

Scope {
    id: root
    property var notificationUi: null
    property var windows: []
    property alias trayApi: trayController
    property alias barApi: barController

    QtObject {
        id: barController
        function geometry(): string { return JSON.stringify(root.windows.map(window => window.status())); }
        function toggle(): void { ShellProfile.pinned = !ShellProfile.pinned; }
        function reveal(): void { for (const window of root.windows) window.manualReveal = true; }
        function hide(): void { for (const window of root.windows) window.dismiss(); }
    }
    QtObject {
        id: trayController
        function items(): string {
            return JSON.stringify(SystemTray.items.values.map(item => ({id: item.id, title: item.title,
                hasMenu: item.hasMenu, onlyMenu: item.onlyMenu})));
        }
        function open(id: string): bool {
            for (const window of root.windows) if (window.tray && window.tray.open(id)) return true;
            return false;
        }
        function menu(id: string): bool {
            for (const window of root.windows) if (window.tray && window.tray.openMenu(id)) return true;
            return false;
        }
        function close(): void { for (const window of root.windows) if (window.tray) window.tray.menu.close(); }
        function next(): void { for (const window of root.windows) if (window.tray && window.tray.menu.visible) window.tray.menu.navigate(1); }
        function back(): void { for (const window of root.windows) if (window.tray && window.tray.menu.visible) window.tray.menu.back(); }
        function submenu(label: string): bool {
            for (const window of root.windows) {
                const menu = window.tray ? window.tray.menu : null;
                const entry = menu && menu.visible && menu.entries.find(entry => entry.text === label && entry.enabled && entry.hasChildren);
                if (entry) { menu.choose(entry); return true; }
            }
            return false;
        }
        function status(): string {
            return JSON.stringify(root.windows.filter(window => window.tray).map(window => ({screen: window.screen.name,
                open: window.tray.menu.visible, depth: window.tray.menu.menuPath.length,
                selected: window.tray.menu.selectedIndex, frame: window.tray.menu.layoutStatus(),
                entries: window.tray.menu.entries.map(entry => ({text: entry.text, enabled: entry.enabled,
                    submenu: entry.hasChildren, separator: entry.isSeparator}))})));
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            readonly property bool enzo: ShellProfile.name === "enzo"
            readonly property bool hiding: !enzo && ShellProfile.autoHide
            readonly property var tray: layout.item ? layout.item.tray : null
            property bool manualReveal: false
            property bool hoverRevealed: false
            readonly property bool revealed: !hiding || ShellProfile.pinned || manualReveal || hoverRevealed
                || UiState.active !== "" || Boolean(tray && tray.menu.visible)
            function dismiss(): void {
                revealTimer.stop();
                hideTimer.stop();
                manualReveal = false;
                hoverRevealed = false;
            }
            function panelTargets() { return layout.item ? layout.item.panelTargets() : []; }
            function status() {
                return {profile: ShellProfile.name, screen: screen.name, width: width, height: height,
                    visible: visible, autoHide: hiding, revealed: revealed, maskHeight: revealed ? height : 2,
                    exclusiveZone: exclusiveZone, palette: ShellProfile.wallpaperColors ? "wallpaper" : "upstream",
                    brightness: SystemState.brightnessAvailable, battery: SystemState.batteryAvailable,
                    tray: tray ? tray.items.length : 0,
                    fonts: Theme.auditText(layout.item),
                    controls: layout.item ? layout.item.featureBar.metrics() : null,
                    workspaces: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === screen.name)
                        .map(w => ({id: w.id, apps: w.toplevels.values.length}))};
            }
            Component.onCompleted: {
                root.windows = [...root.windows, bar];
                UiState.bars = [...UiState.bars, bar];
            }
            Component.onDestruction: {
                if (root.windows) root.windows = root.windows.filter(window => window !== bar);
                if (UiState.bars) UiState.bars = UiState.bars.filter(window => window !== bar);
            }
            screen: modelData
            color: "transparent"
            aboveWindows: true
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-compare-" + ShellProfile.name
            anchors { top: true; left: true; right: true }
            margins { top: bar.enzo ? 8 : 0; left: bar.enzo ? 12 : 0; right: bar.enzo ? 12 : 0 }
            implicitHeight: enzo ? 34 : 32
            exclusiveZone: hiding && !ShellProfile.pinned ? 0 : implicitHeight
            mask: Region { width: bar.width; height: bar.revealed ? bar.height : 2 }

            Timer { id: revealTimer; interval: 250; onTriggered: bar.hoverRevealed = true }
            Timer { id: hideTimer; interval: 400; onTriggered: bar.hoverRevealed = false }
            MouseArea {
                id: hover
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                onContainsMouseChanged: {
                    if (containsMouse) { hideTimer.stop(); revealTimer.restart(); }
                    else { revealTimer.stop(); hideTimer.restart(); }
                }
                Loader {
                    id: layout
                    width: parent.width
                    height: parent.height
                    y: bar.revealed ? 0 : -height
                    visible: y > -height
                    Behavior on y { NumberAnimation { duration: Style.duration; easing.type: Easing.OutCubic } }
                    sourceComponent: bar.enzo ? enzoLayout : mmLayout
                }
            }
            Component { id: enzoLayout; EnzoLayout { output: bar.screen.name } }
            Component { id: mmLayout; MmLayout { output: bar.screen.name } }
        }
    }
}
