import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

Item {
    id: root
    readonly property var vpnData: ConnectivityService.vpn
    readonly property bool canChange: ConnectivityService.ready && vpnData.available && !ConnectivityService.readOnly && !ConnectivityService.busy
    readonly property bool canEdit: canChange && !ConnectivityService.fixture
    property string expanded: ""
    readonly property real preferredHeightHint: Math.max(140, Math.min(400, vpnData.profiles.length * 54 + 42 + (expanded ? 40 : 0) + (ConnectivityService.error ? 60 : 0)))
    function reset(): void { expanded = ""; }
    function select(target): void { expanded = expanded === target ? "" : target; }
    function activate(profile): void {
        const sent = ConnectivityService.send({action: profile.active ? "vpn.disconnect" : "vpn.connect", target: profile.id});
        // Release our surface for the existing NetworkManager credential agent.
        if (sent && !profile.active && !ConnectivityService.fixture) UiState.close("controls");
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        ThemeText { visible: ConnectivityService.readOnly; text: "Preview"; textRole: "body"; color: Theme.surfaceVariantText; font.pixelSize: 11 }
        ThemeText { Layout.fillWidth: true; visible: text !== ""; text: ConnectivityService.error; textRole: "body"; font.pixelSize: 12; color: Theme.error; wrapMode: Text.Wrap }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.vpnData.profiles
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThemeScrollBar {}
            delegate: ColumnLayout {
                id: row
                required property var modelData
                width: list.width - 8
                spacing: 6
                ControlListItem {
                    Layout.fillWidth: true
                    text: String(row.modelData.name).replace(/[\r\n]+/g, " ")
                    subtitle: (row.modelData.type === "wireguard" ? "WireGuard" : "VPN") + " · "
                        + (row.modelData.connecting ? "Connecting" : row.modelData.connected ? "Connected" : "Disconnected")
                    marked: row.modelData.active
                    selected: root.expanded === row.modelData.id
                    onClicked: root.select(row.modelData.id)
                }
                RowLayout {
                    visible: root.expanded === row.modelData.id
                    Layout.alignment: Qt.AlignRight
                    ControlButton {
                        text: ConnectivityService.busy && ConnectivityService.state.target === row.modelData.id ? "…"
                            : row.modelData.connecting ? "Cancel" : row.modelData.active ? "Disconnect" : "Connect"
                        font.pixelSize: 12
                        enabled: root.canChange
                        onClicked: root.activate(row.modelData)
                    }
                    ControlButton { quiet: true; text: "Configure"; font.pixelSize: 12; enabled: root.canEdit; onClicked: ConnectivityService.configureVpn(row.modelData.id, "") }
                }
            }
            ThemeText {
                anchors.centerIn: parent
                text: !ConnectivityService.ready ? "Loading…" : !root.vpnData.available ? "NetworkManager unavailable" : "No VPN profiles"
                textRole: "body"; color: Theme.surfaceVariantText; visible: list.count === 0
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ControlButton { quiet: true; text: "Add VPN"; enabled: root.canEdit; onClicked: ConnectivityService.configureVpn("", "vpn") }
            Item { Layout.fillWidth: true }
            ControlButton { quiet: true; text: "Add WireGuard"; enabled: root.canEdit; onClicked: ConnectivityService.configureVpn("", "wireguard") }
        }
    }
}
