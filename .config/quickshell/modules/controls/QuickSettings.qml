// SPDX-License-Identifier: MIT
// Original shared controls over the retained MM-2103 tile/slider adaptation.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.components
import qs.services
import qs.theme

OverlayWindow {
    id: root
    route: "controls"
    popIn: false
    dimBackground: false
    property var trayApi: null
    property int playerIndex: -1
    // Logical navigation resets on close, but outgoing content must survive
    // until the native surface has finished fading out.
    property string renderedPage: "main"
    property real exitHeight: 520
    readonly property bool overview: renderedPage === "main"
    readonly property var player: (playerIndex >= 0 ? Mpris.players.values[playerIndex] : null)
        || Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property var tiles: [
        {key: "launcher", label: "Applications", glyph: "󰀻"},
        {key: "wallpaper", label: "Wallpapers", glyph: ""},
        {key: "notifications", label: "Notifications", glyph: "󰂚"},
        {key: "audio", label: "Sound", glyph: "󰕾"},
        {key: "caffeine", label: CaffeineService.pending ? "Caffeine…" : CaffeineService.enabled ? "Caffeine on" : "Caffeine off", glyph: "󰅶"},
        {key: "media", label: player && player.isPlaying ? "Pause media" : "Play media", glyph: "󰎆"},
        {key: "network", label: "Network", glyph: "󰤨"},
        {key: "bluetooth", label: ConnectivityService.ready && !ConnectivityService.bluetooth.enabled ? "Bluetooth off" : "Bluetooth", glyph: ""},
        {key: "updates", label: UpdateService.summary, glyph: ""}
    ]
    readonly property var visibleTiles: tiles.filter(tile => !["launcher", "wallpaper", "media"].includes(tile.key))
    function syncPage(): void {
        if (connectionView.item && typeof connectionView.item.reset === "function") connectionView.item.reset();
        renderedPage = ConnectivityService.page;
    }
    Connections {
        target: ConnectivityService
        function onPageChanged() { if (root.opened) root.syncPage(); }
    }
    onOpenedChanged: {
        if (opened) { syncPage(); ConnectivityService.ensure(); if (AudioService.fixture) AudioService.ensure(); }
        else {
            if (connectionView.item && typeof connectionView.item.clearSensitive === "function") connectionView.item.clearSensitive();
            ConnectivityService.closePanel();
        }
    }
    function available(key): bool {
        if (key === "mute") return AudioService.output.available && !AudioService.readOnly;
        if (key === "caffeine") return !CaffeineService.pending;
        if (key === "media") return !!(player && player.canTogglePlaying);
        if (key === "updates") return !UpdateService.checking;
        return true;
    }
    function activate(key): bool {
        if (!available(key)) return false;
        if (["launcher", "wallpaper", "notifications", "settings"].includes(key)) return ShellProfile.activate(key);
        if (key === "mute") return AudioService.toggleMuted("output", AudioService.output.id, AudioService.output.key);
        if (key === "caffeine") return CaffeineService.toggle();
        if (key === "media") { player.togglePlaying(); return true; }
        if (key === "updates") return UpdateService.refresh();
        if (key === "audio") return AudioService.open();
        if (key === "network" || key === "bluetooth") return ConnectivityService.open(key === "network" ? "wifi" : "bluetooth");
        return false;
    }
    function requestPower(kind, value): bool {
        const state = kind === "wifi" ? ConnectivityService.wifi : ConnectivityService.bluetooth;
        if (!opened || !["wifi", "bluetooth"].includes(kind) || !ConnectivityService.ready
                || ConnectivityService.readOnly || ConnectivityService.busy || !state.available) return false;
        return ConnectivityService.send({action: kind + ".power", enabled: value});
    }
    function switchStatus(control, kind) {
        const point = control.mapToItem(panel, 0, 0);
        return {kind: kind, value: control.value, enabled: control.enabled, visible: control.visible && root.visible,
            x: point.x, y: point.y, width: control.width, height: control.height};
    }
    function fixtureActivate(target): bool {
        if (!ShellProfile.comparing || !ConnectivityService.fixture || !connectionView.item) return false;
        if (target === "power") {
            const control = renderedPage === "wifi" ? wifiSwitch : renderedPage === "bluetooth" ? bluetoothSwitch : null;
            if (!control || !control.visible || !control.enabled) return false;
            control.requested(!control.value);
            return true;
        }
        if (renderedPage === "audio") return connectionView.item.activate(target);
        if (["wifi", "bluetooth"].includes(renderedPage) && target === "reload") return connectionView.item.reload();
        if (["wifi", "bluetooth", "vpn"].includes(renderedPage) && (target.startsWith("row:") || target.startsWith("options:"))) {
            const rows = renderedPage === "wifi" ? ConnectivityService.wifi.networks : renderedPage === "vpn" ? ConnectivityService.vpn.profiles : ConnectivityService.bluetooth.devices;
            const id = target.slice(target.indexOf(":") + 1);
            if (!rows.some(row => row.id === id)) return false;
            if (target.startsWith("row:")) connectionView.item.select(id);
            else if (typeof connectionView.item.showOptions === "function") connectionView.item.showOptions(id);
            else return false;
            return true;
        }
        if (renderedPage === "wifi" && target.startsWith("password:")) {
            const network = ConnectivityService.wifi.networks.find(row => row.id === target.slice(9));
            if (!network) return false;
            connectionView.item.editPassword(network);
            return true;
        }
        if (renderedPage === "bluetooth" && target.startsWith("rename:")) {
            const device = ConnectivityService.bluetooth.devices.find(row => row.id === target.slice(7));
            if (!device) return false;
            connectionView.item.startRename(device);
            return true;
        }
        const rows = renderedPage === "vpn" ? ConnectivityService.vpn.profiles
            : renderedPage === "wifi" ? ConnectivityService.wifi.networks : ConnectivityService.bluetooth.devices;
        const row = rows.find(row => row.id === target);
        if (!row) return false;
        connectionView.item.activate(row);
        return true;
    }
    function status() {
        return {view: FeatureSettings.controls, opened: opened, visible: visible, fonts: root.typography(),
            page: renderedPage, opacity: surfaceOpacity, detailsLoaded: !!connectionView.item,
            frame: {x: panel.x, y: panel.y, width: panel.width, height: panel.height}, windowInsets: windowInsets,
            switches: [switchStatus(wifiSwitch, "wifi"), switchStatus(bluetoothSwitch, "bluetooth")],
            header: {y: header.mapToItem(panel, 0, 0).y, height: header.height},
            details: connectionView.item && typeof connectionView.item.presentation === "function" ? connectionView.item.presentation() : null,
            networkTabs: {x: networkTabs.mapToItem(panel, 0, 0).x, y: networkTabs.mapToItem(panel, 0, 0).y, height: networkTabs.height,
                vpnRight: vpnTab.mapToItem(panel, vpnTab.width, 0).x},
            brightness: SystemState.brightnessAvailable, volume: SystemState.volumePercent,
            connectivity: ConnectivityService.status(), caffeine: CaffeineService.status(), updates: UpdateService.status(),
            tiles: tiles.map(tile => ({key: tile.key, enabled: available(tile.key)}))};
    }
    Rectangle {
        id: panel
        opacity: root.surfaceOpacity
        x: Math.max(root.windowInsets.left, parent.width - width - root.windowInsets.right)
        y: root.windowInsets.top
        width: Math.max(0, Math.min(root.overview ? (FeatureSettings.controls === "tiles" ? 360 : 340) : 400,
            parent.width - root.windowInsets.left - root.windowInsets.right))
        onHeightChanged: if (root.opened) root.exitHeight = height
        height: !root.opened ? root.exitHeight : Math.min(root.overview ? header.implicitHeight + mainContent.implicitHeight + 34
            : root.renderedPage === "audio" ? Math.min(520, Math.max(180, header.implicitHeight + (connectionView.item && typeof connectionView.item.contentHeight === "number" ? connectionView.item.contentHeight : 280) + 34))
            : Math.min(520, header.implicitHeight + (["wifi", "vpn"].includes(root.renderedPage) ? networkTabs.implicitHeight + 10 : 0)
                + (connectionView.item && typeof connectionView.item.preferredHeightHint === "number" ? connectionView.item.preferredHeightHint : 280) + 34), Math.max(0, parent.height - root.windowInsets.top - root.windowInsets.bottom))
        radius: 12
        color: Theme.background
        border.color: Theme.outlineVariant
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            RowLayout {
                id: header
                Layout.fillWidth: true
                ControlButton { visible: !root.overview; text: ""; iconOnly: true; tooltip: root.renderedPage === "audio" && ConnectivityService.audioReturn !== "main" ? (ConnectivityService.audioReturn === "bluetooth" ? "Bluetooth" : "Network") : "Quick settings"; onClicked: ConnectivityService.back() }
                ThemeText { Layout.fillWidth: true; textRole: "title"; text: root.overview ? "Quick settings" : root.renderedPage === "bluetooth" ? "Bluetooth" : root.renderedPage === "audio" ? "Sound" : "Network"; font.pixelSize: 16 }
                ControlButton { visible: root.overview; text: "󰒓"; iconOnly: true; tooltip: "Customize shell components"; onClicked: ShellProfile.activate("settings") }
                ThemeToggle {
                    id: bluetoothSwitch
                    visible: root.renderedPage === "bluetooth"
                    label: "Bluetooth"
                    value: ConnectivityService.bluetooth.enabled
                    enabled: root.opened && ConnectivityService.ready && !ConnectivityService.readOnly && !ConnectivityService.busy && ConnectivityService.bluetooth.available
                    tooltip: value ? "Turn Bluetooth off" : "Turn Bluetooth on"
                    onRequested: value => root.requestPower("bluetooth", value)
                }
            }
            RowLayout {
                id: networkTabs
                visible: ["wifi", "vpn"].includes(root.renderedPage)
                Layout.fillWidth: true
                ControlButton { text: "Wi-Fi"; baseColor: root.renderedPage === "wifi" ? Theme.activeBackground : Theme.surfaceContainerHigh; onClicked: ConnectivityService.open("wifi") }
                ControlButton { id: vpnTab; text: "VPN"; baseColor: root.renderedPage === "vpn" ? Theme.activeBackground : Theme.surfaceContainerHigh; onClicked: ConnectivityService.open("vpn") }
                Item { Layout.fillWidth: true }
                ThemeToggle {
                    id: wifiSwitch
                    visible: root.renderedPage === "wifi"
                    label: "Wi-Fi"
                    value: ConnectivityService.wifi.enabled
                    enabled: root.opened && ConnectivityService.ready && !ConnectivityService.readOnly && !ConnectivityService.busy
                        && ConnectivityService.wifi.available && (value || ConnectivityService.wifi.hardware)
                    tooltip: !ConnectivityService.wifi.hardware ? "Wi-Fi blocked by hardware switch" : value ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                    onRequested: value => root.requestPower("wifi", value)
                }
            }
            Item {
                visible: root.overview
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    id: mainContent
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    spacing: 10
                    ValueSlider {
                        Layout.fillWidth: true
                        title: AudioService.output.muted ? "Muted" : "Volume"
                        value: AudioService.output.volume
                        enabled: root.available("mute")
                        onAdjusted: value => AudioService.setVolume("output", AudioService.output.id, AudioService.output.key, value)
                    }
                    ValueSlider {
                        Layout.fillWidth: true
                        visible: SystemState.brightnessAvailable
                        title: "Brightness"
                        value: SystemState.brightnessPercent
                        onAdjusted: value => BrightnessService.setPercent(value)
                    }
                    RowLayout {
                        visible: root.player !== null
                        Layout.fillWidth: true
                        ThemeText { Layout.fillWidth: true; textRole: "display"; text: root.player ? root.player.trackTitle || root.player.identity : ""; font.pixelSize: 12; elide: Text.ElideRight }
                        ControlButton { text: ""; iconOnly: true; enabled: !!root.player && root.player.canGoPrevious; tooltip: "Previous track"; onClicked: root.player.previous() }
                        ControlButton { text: root.player && root.player.isPlaying ? "" : ""; iconOnly: true; enabled: !!root.player && root.player.canTogglePlaying; tooltip: "Play / pause"; onClicked: root.player.togglePlaying() }
                        ControlButton { text: ""; iconOnly: true; enabled: !!root.player && root.player.canGoNext; tooltip: "Next track"; onClicked: root.player.next() }
                        ControlButton { text: "󰑓"; iconOnly: true; visible: Mpris.players.values.length > 1; tooltip: "Switch player"; onClicked: root.playerIndex = (Mpris.players.values.indexOf(root.player) + 1) % Mpris.players.values.length }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: FeatureSettings.controls === "tiles" ? 3 : 1
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: root.visibleTiles
                            ControlButton {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: FeatureSettings.controls === "tiles" ? 42 : 28
                                text: modelData.label
                                font.pixelSize: 12
                                enabled: root.available(modelData.key)
                                baseColor: modelData.key === "caffeine" && CaffeineService.enabled ? Theme.activeBackground : Theme.surfaceContainerHigh
                                tooltip: modelData.key === "updates" ? "Check for updates" : modelData.key === "caffeine" ? "Keep awake while caffeine mode is on" : modelData.label
                                onClicked: root.activate(modelData.key)
                            }
                        }
                    }
                    ThemeText { Layout.fillWidth: true; visible: text !== ""; text: [UpdateService.error, CaffeineService.error].filter(message => message !== "").join("\n"); textRole: "body"; color: Theme.error; font.pixelSize: 10; wrapMode: Text.Wrap }
                }
            }
            Loader {
                id: connectionView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.overview
                active: !root.overview && root.renderVisible
                sourceComponent: root.renderedPage === "vpn" ? vpnPage : root.renderedPage === "audio" ? audioPage : radioPage
            }
        }
    }
    Component { id: vpnPage; VpnPage {} }
    Component { id: audioPage; AudioPage {} }
    Component { id: radioPage; ConnectivityPage { kind: root.renderedPage } }
}
