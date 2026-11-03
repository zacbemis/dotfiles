import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import "../../services/ConnectivityValidation.js" as Validation
import qs.theme

Item {
    id: root
    required property string kind
    readonly property bool wifiMode: kind === "wifi"
    readonly property var connectionState: wifiMode ? ConnectivityService.wifi : ConnectivityService.bluetooth
    readonly property var prompt: UiState.active === "controls" && ConnectivityService.page === kind ? ConnectivityService.prompt : null
    property var passwordNetwork: null
    property var forgetting: null
    property string expanded: ""
    property string options: ""
    property var renaming: null
    readonly property bool canChange: ConnectivityService.ready && !ConnectivityService.readOnly && !ConnectivityService.busy
    readonly property real preferredHeightHint: {
        const rows = connectionState.enabled ? (wifiMode ? connectionState.networks.length : connectionState.devices.length) : 0;
        const form = passwordNetwork || forgetting || prompt || renaming;
        const banner = wifiMode && connectionState.enabled && !!ConnectivityService.connectedWifi && ConnectivityService.internet.state !== "full";
        return Math.min(400, Math.max(160, (form ? 220 : rows * 54 + 42 + (expanded ? 40 : 0) + (options ? 40 : 0))
            + (banner ? 42 : 0) + (connectionState.adapters.length > 1 || ConnectivityService.readOnly ? 42 : 0)
            + (ConnectivityService.error ? 60 : 0) + (["connecting", "authentication", "address"].includes(connectionState.phase) ? 28 : 0)));
    }
    function clean(value) { return String(value || "").replace(/[\r\n]+/g, " "); }
    function action(value): bool { return ConnectivityService.send(value); }
    function clearSensitive(): void { password.text = ""; pairing.text = ""; }
    function reset(): void {
        clearSensitive();
        passwordNetwork = forgetting = renaming = null;
        expanded = options = "";
        aliasEntry.text = "";
    }
    function select(target): void { expanded = expanded === target ? "" : target; options = ""; }
    function showOptions(target): void { expanded = target; options = options === target ? "" : target; }
    function reload(): bool {
        if (!canChange || !connectionState.enabled) return false;
        return action(wifiMode ? {action: "wifi.scan"} : {action: "bluetooth.scan", enabled: !connectionState.ownDiscovery});
    }
    function presentation() {
        const point = reloadButton.mapToItem(root, 0, 0);
        return {selected: expanded, options: options, height: height, width: width,
            footerVisible: footer.visible, footerY: footer.y, footerHeight: footer.height,
            reload: {x: point.x, y: point.y, width: reloadButton.width, height: reloadButton.height}};
    }
    function editPassword(row): void {
        password.text = "";
        passwordNetwork = row;
        Qt.callLater(() => { if (UiState.active === "controls" && root.wifiMode && root.passwordNetwork) password.focusInput(); });
    }
    function startRename(row): void {
        renaming = row;
        aliasEntry.text = row.name;
        Qt.callLater(() => { if (UiState.active === "controls" && root.renaming) aliasEntry.focusInput(); });
    }
    function renameDevice(): void {
        const name = aliasEntry.text.trim();
        if (!Validation.validAlias(name)) { ConnectivityService.error = "Enter a device name of 1–248 bytes without control characters."; return; }
        if (renaming && action({action: "bluetooth.rename", target: renaming.id, alias: name})) {
            renaming = null;
            aliasEntry.text = "";
        }
    }
    function activate(row): void {
        if (wifiMode) {
            if (row.failed && row.retryPassword && row.saved && ["wpa", "sae"].includes(row.security)) { editPassword(row); return; }
            if (row.connected) action({action: "wifi.disconnect", target: row.id});
            else if (row.advanced && !row.saved) ConnectivityService.advanced("wifi");
            else if (!row.saved && ["wpa", "sae"].includes(row.security)) editPassword(row);
            else {
                const sent = action({action: "wifi.connect", target: row.id});
                if (sent && !ConnectivityService.fixture) UiState.close("controls");
            }
        } else action({action: row.blocked ? "bluetooth.unblock" : row.connected ? "bluetooth.disconnect" : row.paired ? "bluetooth.connect" : "bluetooth.pair", target: row.id});
    }
    function connectPassword(): void {
        if (!passwordNetwork || !password.text) return;
        const sae = (passwordNetwork.passwordKind || passwordNetwork.security) === "sae";
        if (!Validation.validPsk(password.text, sae)) {
            password.text = "";
            ConnectivityService.error = sae ? "Enter 1–63 UTF-8 bytes." : "Enter 8–63 UTF-8 bytes or a 64-digit hex key.";
            return;
        }
        const sent = action({action: passwordNetwork.saved ? "wifi.retry" : "wifi.connect", target: passwordNetwork.id, password: password.text});
        password.text = "";
        passwordNetwork = null;
        // Release the exclusive surface for existing credential/polkit agents.
        if (sent && !ConnectivityService.fixture) UiState.close("controls");
    }
    function reply(accepted): void {
        if (!prompt) return;
        action({action: "agent.reply", token: prompt.token, accepted: accepted, value: pairing.text});
        pairing.text = "";
    }
    function cycleAdapter(): void {
        const adapters = connectionState.adapters;
        const index = adapters.findIndex(adapter => adapter.id === connectionState.selected);
        if (adapters.length) action({action: kind + ".adapter", target: adapters[(index + 1) % adapters.length].id});
        reset();
    }
    function securityLabel(row) {
        return {open: "Open", wpa: "WPA/WPA2", sae: "WPA3", owe: "Enhanced open", enterprise: "Enterprise", wep: "WEP"}[row.security] || "Secured";
    }
    function subtitle(row) {
        if (wifiMode) return row.connecting ? "Connecting…" : row.failed ? "Connection failed" : row.connected ? "Connected" : securityLabel(row);
        return (row.connected ? "Connected" : row.blocked ? "Blocked" : row.paired ? "Paired" : "Nearby") + (row.battery >= 0 ? " · " + row.battery + "%" : "");
    }
    Connections {
        target: ConnectivityService
        function onStateChanged() {
            const rows = root.wifiMode ? ConnectivityService.wifi.networks : ConnectivityService.bluetooth.devices;
            if (root.expanded && !rows.some(row => row.id === root.expanded)) root.expanded = root.options = "";
            if (!root.connectionState.enabled) { root.clearSensitive(); root.passwordNetwork = null; root.expanded = root.options = ""; }
            if (root.passwordNetwork && !ConnectivityService.wifi.networks.some(row => row.id === root.passwordNetwork.id)) {
                password.text = "";
                root.passwordNetwork = null;
            }
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            visible: root.connectionState.adapters.length > 1 || ConnectivityService.readOnly
            Layout.fillWidth: true
            ControlButton {
                visible: root.connectionState.adapters.length > 1
                Layout.minimumWidth: 32
                Layout.fillWidth: true
                text: root.clean((root.connectionState.adapters.find(adapter => adapter.id === root.connectionState.selected) || {}).name)
                tooltip: "Switch adapter"
                enabled: root.canChange
                onClicked: root.cycleAdapter()
            }
            ThemeText { visible: ConnectivityService.readOnly; text: "Preview"; textRole: "body"; font.pixelSize: 11; color: Theme.surfaceVariantText }
        }
        RowLayout {
            visible: root.wifiMode && root.connectionState.enabled && !!ConnectivityService.connectedWifi && ConnectivityService.internet.state !== "full"
            Layout.fillWidth: true
            ThemeText {
                Layout.fillWidth: true
                text: ({portal: "Sign-in required", limited: "Limited connectivity", none: "No internet", unknown: "Internet status unknown"})[ConnectivityService.internet.state] || "Internet status unknown"
                textRole: "body"; font.pixelSize: 12; color: Theme.surfaceVariantText; elide: Text.ElideRight
            }
            ControlButton { text: "Open login page"; visible: ConnectivityService.internet.state === "portal"; enabled: !ConnectivityService.readOnly && !ConnectivityService.fixture && ConnectivityService.internet.uri !== ""; onClicked: ConnectivityService.openPortal() }
            ControlButton { quiet: true; text: ConnectivityService.internet.checking ? "Checking…" : "Check connection"; visible: ConnectivityService.internet.state !== "portal"; enabled: root.canChange; onClicked: root.action({action: "network.check"}) }
        }
        ThemeText { Layout.fillWidth: true; visible: root.wifiMode && root.connectionState.available && !root.connectionState.hardware; text: "Wi-Fi blocked by hardware switch"; textRole: "body"; color: Theme.error; wrapMode: Text.Wrap }
        ThemeText {
            visible: root.wifiMode && ["connecting", "authentication", "address"].includes(root.connectionState.phase)
            text: ({connecting: "Connecting…", authentication: "Waiting for authentication…", address: "Getting network address…"})[root.connectionState.phase] || ""
            textRole: "body"; color: Theme.surfaceVariantText
        }
        ColumnLayout {
            visible: root.passwordNetwork !== null
            Layout.fillWidth: true
            ThemeText { Layout.fillWidth: true; text: root.passwordNetwork ? root.clean(root.passwordNetwork.name) : ""; textRole: "title"; font.pixelSize: 14; elide: Text.ElideRight }
            SecureEntry { id: password; Layout.fillWidth: true; placeholder: root.passwordNetwork && root.passwordNetwork.saved ? "New Wi-Fi password" : "Wi-Fi password"; onAccepted: if (root.canChange) root.connectPassword() }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                ControlButton { text: "Cancel"; onClicked: { password.text = ""; root.passwordNetwork = null; } }
                ControlButton { text: root.passwordNetwork && root.passwordNetwork.saved ? "Retry" : "Connect"; enabled: root.canChange && password.text !== ""; onClicked: root.connectPassword() }
            }
        }
        ColumnLayout {
            visible: !root.wifiMode && !!root.prompt
            Layout.fillWidth: true
            ThemeText { Layout.fillWidth: true; text: root.prompt ? root.clean(root.prompt.name) : ""; textRole: "title"; font.pixelSize: 14; elide: Text.ElideRight }
            ThemeText { Layout.fillWidth: true; text: !root.prompt ? "" : root.prompt.kind === "confirm" ? "Does this code match?" : root.prompt.kind === "display" ? "Pairing code" : root.prompt.kind === "authorize" ? "Allow this connection?" : "Enter the pairing code"; textRole: "body"; color: Theme.surfaceVariantText }
            ThemeText { property bool sensitive: true; visible: !!root.prompt && root.prompt.code !== ""; text: root.prompt ? root.prompt.code : ""; textRole: "display"; font.pixelSize: 24 }
            SecureEntry { id: pairing; Layout.fillWidth: true; visible: !!root.prompt && ["pin", "passkey"].includes(root.prompt.kind); placeholder: "Pairing code"; numeric: !!root.prompt && root.prompt.kind === "passkey"; onAccepted: root.reply(true) }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                ControlButton { text: "Cancel"; onClicked: root.reply(false) }
                ControlButton { visible: !!root.prompt && root.prompt.kind !== "display"; text: "Confirm"; onClicked: root.reply(true) }
            }
        }
        ColumnLayout {
            visible: root.renaming !== null
            Layout.fillWidth: true
            ThemeEntry { id: aliasEntry; Layout.fillWidth: true; placeholder: "Device name"; onAccepted: if (root.canChange) root.renameDevice() }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                ControlButton { text: "Cancel"; onClicked: { root.renaming = null; aliasEntry.text = ""; } }
                ControlButton { text: "Rename"; enabled: root.canChange && aliasEntry.text.trim() !== ""; onClicked: root.renameDevice() }
            }
        }
        ColumnLayout {
            visible: root.forgetting !== null
            Layout.fillWidth: true
            ThemeText { Layout.fillWidth: true; text: root.forgetting ? "Forget " + root.clean(root.forgetting.name) + "?" : ""; textRole: "body"; wrapMode: Text.Wrap }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                ControlButton { text: "Cancel"; onClicked: root.forgetting = null }
                ControlButton { text: "Forget"; enabled: root.canChange; onClicked: { root.action({action: root.kind + ".forget", target: root.forgetting.id}); root.forgetting = null; } }
            }
        }
        ThemeText { Layout.fillWidth: true; visible: text !== ""; text: ConnectivityService.error; textRole: "body"; font.pixelSize: 12; color: Theme.error; wrapMode: Text.Wrap }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.passwordNetwork && !root.forgetting && !root.prompt && !root.renaming
            model: !root.connectionState.enabled ? [] : root.wifiMode ? root.connectionState.networks : root.connectionState.devices
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThemeScrollBar {}
            delegate: ColumnLayout {
                id: row
                required property var modelData
                width: list.width - 8
                spacing: 6
                ControlListItem {
                    Layout.fillWidth: true
                    text: root.clean(row.modelData.name)
                    subtitle: root.subtitle(row.modelData)
                    glyph: root.wifiMode ? (row.modelData.strength > 65 ? "󰤨" : row.modelData.strength > 30 ? "󰤥" : "󰤟") : ""
                    tooltip: root.wifiMode ? row.modelData.strength + "% signal · " + root.securityLabel(row.modelData) : root.clean(row.modelData.name)
                    marked: !!row.modelData.connected
                    selected: root.expanded === row.modelData.id
                    onClicked: root.select(row.modelData.id)
                }
                RowLayout {
                    visible: root.expanded === row.modelData.id
                    Layout.alignment: Qt.AlignRight
                    ControlButton {
                        text: ConnectivityService.state.target === row.modelData.id && ConnectivityService.busy ? "…" : row.modelData.connecting ? "Connecting…" : row.modelData.blocked ? "Unblock" : row.modelData.connected ? "Disconnect" : !root.wifiMode && !row.modelData.paired ? "Pair" : root.wifiMode && row.modelData.advanced && !row.modelData.saved ? "Configure" : row.modelData.failed ? "Retry" : "Connect"
                        font.pixelSize: 12
                        enabled: root.canChange && root.connectionState.enabled && !row.modelData.connecting
                        onClicked: root.activate(row.modelData)
                    }
                    ControlButton { text: "Options"; quiet: true; visible: !root.wifiMode || row.modelData.saved; onClicked: root.showOptions(row.modelData.id) }
                }
                RowLayout {
                    visible: root.expanded === row.modelData.id && root.options === row.modelData.id
                    Layout.alignment: Qt.AlignRight
                    ControlButton { visible: root.wifiMode && row.modelData.saved; text: "Configure"; enabled: !ConnectivityService.readOnly && !ConnectivityService.fixture; onClicked: ConnectivityService.configureWifi(row.modelData.profile) }
                    ControlButton { visible: root.wifiMode && row.modelData.saved && ["wpa", "sae"].includes(row.modelData.security); text: row.modelData.retryPassword ? "Retry password" : "Change password"; enabled: root.canChange; onClicked: root.editPassword(row.modelData) }
                    ControlButton { visible: !root.wifiMode; text: "Rename"; enabled: root.canChange; onClicked: root.startRename(row.modelData) }
                    ControlButton { visible: !root.wifiMode; text: row.modelData.trusted ? "Untrust" : "Trust"; enabled: root.canChange; onClicked: root.action({action: "bluetooth.trust", target: row.modelData.id, enabled: !row.modelData.trusted}) }
                    ControlButton { text: "Forget"; enabled: root.canChange; onClicked: root.forgetting = row.modelData }
                }
            }
            ThemeText {
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: !ConnectivityService.ready ? "Loading…" : !root.connectionState.available ? (root.wifiMode ? "No Wi-Fi adapter" : "No Bluetooth adapter")
                    : !root.connectionState.enabled ? (root.wifiMode ? "Wi-Fi is off" : "Bluetooth is off")
                    : !root.wifiMode && root.connectionState.discovering ? "Looking for devices…" : root.wifiMode ? "No cached networks" : "No devices"
                textRole: "body"; color: Theme.surfaceVariantText; visible: list.count === 0
            }
        }
        Item { Layout.fillHeight: true; visible: !list.visible }
        RowLayout {
            id: footer
            visible: list.visible
            Layout.fillWidth: true
            ControlButton { quiet: true; text: root.wifiMode ? "Network settings…" : "Bluetooth settings…"; enabled: !ConnectivityService.readOnly && !ConnectivityService.fixture; onClicked: ConnectivityService.advanced(root.kind) }
            Item { Layout.fillWidth: true }
            ControlButton { quiet: true; visible: !root.wifiMode; text: "󰓃"; iconOnly: true; tooltip: "Audio devices"; onClicked: ConnectivityService.open("audio") }
            ControlButton {
                id: reloadButton
                quiet: true
                text: !root.wifiMode && root.connectionState.ownDiscovery ? "" : ""
                iconOnly: true
                tooltip: !root.wifiMode && root.connectionState.ownDiscovery ? "Stop discovery" : root.wifiMode ? "Reload networks" : "Reload devices"
                enabled: root.canChange && root.connectionState.enabled
                onClicked: root.reload()
            }
        }
    }
}
