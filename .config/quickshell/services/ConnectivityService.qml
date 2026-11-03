pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string fixture: Quickshell.env("QUICKSHELL_CONNECTIVITY_FIXTURE")
    readonly property bool readOnly: Quickshell.env("QUICKSHELL_CONNECTIVITY_READ_ONLY") === "1"
        || (ShellProfile.comparing && fixture === "")
    property string page: "main"
    property string audioReturn: "main"
    property bool ready: false
    property bool started: false
    property string error: ""
    property var state: ({wifi: {available: false, enabled: false, hardware: false, adapters: [], networks: [], selected: ""},
        bluetooth: {available: false, enabled: false, discovering: false, ownDiscovery: false, adapters: [], devices: [], selected: ""}, vpn: {available: false, profiles: []}, busy: "", target: "", prompt: null})
    readonly property var wifi: state.wifi
    readonly property var bluetooth: state.bluetooth
    readonly property var vpn: state.vpn || {available: false, profiles: []}
    readonly property var internet: state.internet || {state: "unknown", uri: "", checking: false}
    readonly property bool busy: !!state.busy
    readonly property var prompt: state.prompt
    readonly property var connectedWifi: wifi.networks.find(row => row.connected) || null
    function ensure(): void { if (!worker.running) { error = ""; worker.running = true; } }
    function open(kind): bool {
        if (!["wifi", "bluetooth", "vpn", "audio"].includes(kind)) return false;
        if (kind === "audio" && page !== "audio") audioReturn = page;
        if (page !== kind) closeDetails();
        page = kind;
        ensure();
        if (started) send({action: "refresh"});
        UiState.show("controls");
        return true;
    }
    function openTray(id, button): bool {
        if (![Qt.LeftButton, Qt.RightButton].includes(button) || !["nm-applet", "blueman"].includes(id)) return false;
        return open(id === "nm-applet" ? "wifi" : "bluetooth");
    }
    function configureVpn(target, kind): bool {
        if (readOnly || fixture) { error = "VPN editing is disabled in preview/fixture mode."; return false; }
        let args;
        if (target) {
            if (!vpn.profiles.some(profile => profile.id === target)
                    || !/^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(target)) {
                error = "That VPN profile is no longer available.";
                return false;
            }
            args = ["nm-connection-editor", "--edit", target];
        } else {
            if (!["vpn", "wireguard"].includes(kind)) return false;
            args = ["nm-connection-editor", "--create", "--type", kind];
        }
        UiState.close("controls");
        Quickshell.execDetached(args);
        return true;
    }
    function configureWifi(target): bool {
        if (readOnly || fixture) { error = "Wi-Fi editing is disabled in preview/fixture mode."; return false; }
        if (!(wifi.profiles || []).some(profile => profile.id === target)
                || !/^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(target)) {
            error = "That saved Wi-Fi profile is no longer available.";
            return false;
        }
        UiState.close("controls");
        Quickshell.execDetached(["nm-connection-editor", "--edit", target]);
        return true;
    }
    function openPortal(): bool {
        if (readOnly || fixture || internet.state !== "portal" || !/^https?:\/\//.test(internet.uri)
                || /[\x00-\x20\x7f]/.test(internet.uri) || /^https?:\/\/[^/?#]*@/.test(internet.uri)) return false;
        UiState.close("controls");
        Quickshell.execDetached(["xdg-open", internet.uri]);
        return true;
    }
    function back(): void {
        if (page === "audio" && ["wifi", "bluetooth", "vpn"].includes(audioReturn)) open(audioReturn);
        else overview();
    }
    function openOverview(): void { overview(); UiState.show("controls"); }
    function toggleOverview(): void {
        if (UiState.active === "controls" && page === "main") UiState.close("controls");
        else openOverview();
    }
    function overview(): void { closeDetails(); page = "main"; }
    function closeDetails(): void { if (started) send({action: "panel.close"}); }
    function closePanel(): void { closeDetails(); page = "main"; }
    function send(command): bool {
        if (!started) { error = "Connection service is starting."; ensure(); return false; }
        if (readOnly && !["refresh", "panel.close", "cancel"].includes(command.action)) {
            error = "Preview mode is read-only.";
            return false;
        }
        error = "";
        worker.write(JSON.stringify(command) + "\n");
        return true;
    }
    function receive(line): void {
        try {
            const value = JSON.parse(line);
            if (value.type !== "state" || !value.wifi || !value.bluetooth) return;
            state = value;
            ready = true;
            error = value.error || "";
            if (value.prompt && (UiState.active !== "controls" || page !== "bluetooth")) closeDetails();
        } catch (failure) { error = "Invalid connection service response."; }
    }
    function advanced(kind): void {
        if (readOnly || fixture) { error = "Advanced settings are disabled in preview/fixture mode."; return; }
        UiState.close("controls");
        Quickshell.execDetached([kind === "wifi" ? "nm-connection-editor" : "blueman-manager"]);
    }
    function status() {
        return {page: page, ready: ready, readOnly: readOnly, busy: state.busy, error: error,
            wifi: {available: wifi.available, enabled: wifi.enabled, adapters: wifi.adapters.length, networks: wifi.networks.length},
            bluetooth: {available: bluetooth.available, enabled: bluetooth.enabled, adapters: bluetooth.adapters.length,
                devices: bluetooth.devices.length, discovering: bluetooth.discovering},
            vpn: {available: vpn.available, profiles: vpn.profiles.length, active: vpn.profiles.filter(profile => profile.active).length},
            internet: {state: internet.state, checking: internet.checking},
            savedWifi: (wifi.profiles || []).length,
            prompt: prompt ? {kind: prompt.kind, name: prompt.name} : null};
    }
    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("scripts/connectivity.py")]
            .concat(root.readOnly ? ["--read-only"] : [])
            .concat(root.fixture ? ["--fixture", root.fixture] : [])
        stdinEnabled: true
        onStarted: root.started = true
        onExited: (code, status) => {
            root.started = false;
            root.ready = false;
            if (code !== 0) root.error = "Connection service stopped (" + code + "). Reopen to retry.";
        }
        stdout: SplitParser { onRead: line => root.receive(line) }
        // Backend errors never include command payloads, passwords or pairing replies.
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = "Connection service failed. Check its dependencies." }
    }
}
