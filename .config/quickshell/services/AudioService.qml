pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root
    readonly property bool fixture: ConnectivityService.fixture !== ""
    readonly property bool readOnly: ConnectivityService.readOnly
    property bool fixtureLoaded: false
    property var fixtureAudio: ({outputs: [], inputs: [], cards: [], streams: []})
    property var realCards: []
    property string error: ""
    property bool pending: false
    property string deviceKey: ""
    readonly property bool busy: worker.running
    readonly property var sinks: Pipewire.nodes.values.filter(n => !n.isStream && n.isSink && (n.type & PwNodeType.Audio) && !SystemState.ignoredSink(n))
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isStream && !n.isSink && (n.type & PwNodeType.Audio) && !n.name.endsWith(".monitor"))
    readonly property var outputs: fixture ? fixtureAudio.outputs : sinks.map(n => ({id: String(n.id), name: n.description || n.name, selected: n === Pipewire.defaultAudioSink}))
    readonly property var inputs: fixture ? fixtureAudio.inputs : sources.map(n => ({id: String(n.id), name: n.description || n.name, selected: n === Pipewire.defaultAudioSource}))
    readonly property var cards: fixture ? fixtureAudio.cards : realCards
    property int viewers: 0
    readonly property bool active: UiState.active === "controls" && ConnectivityService.page === "audio"
    readonly property bool tracking: active || viewers > 0
    readonly property var streamNodes: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && (n.type & PwNodeType.Audio)).slice(0, 128)
    readonly property var applications: fixture ? (fixtureAudio.streams || []).map(row => fixtureReading(row))
        : tracking ? streamNodes.filter(n => n.ready && n.audio).map(n => reading(n)).sort((a, b) => a.name.localeCompare(b.name)) : []
    readonly property var output: fixture ? fixtureReading(fixtureAudio.outputs.find(row => row.selected)) : reading(SystemState.audioSink)
    readonly property var input: fixture ? fixtureReading(fixtureAudio.inputs.find(row => row.selected)) : reading(Pipewire.defaultAudioSource)
    PwObjectTracker { objects: root.fixture ? [] : root.sinks.concat(root.sources, root.tracking ? root.streamNodes : []) }
    function reading(node) {
        if (!node || !node.ready || !node.audio) return {id: "", key: "", name: "", available: false, volume: 0, muted: false};
        const properties = node.properties || {};
        const serial = properties["object.serial"], key = serial === undefined ? "" : String(serial);
        return {id: String(node.id), key: key, available: key !== "",
            name: String((node.isStream ? properties["application.name"] : "") || node.description || node.name).slice(0, 200),
            volume: Math.round(node.audio.volume * 100), muted: node.audio.muted};
    }
    function fixtureReading(row) {
        return row ? Object.assign({key: row.id, available: true, volume: 50, muted: false}, row)
            : {id: "", key: "", name: "", available: false, volume: 0, muted: false};
    }
    function control(kind, id) { return kind === "output" ? output : kind === "input" ? input
        : applications.find(row => row.id === id) || fixtureReading(null); }
    function resolve(kind, id, key) {
        const node = kind === "output" ? SystemState.audioSink : kind === "input" ? Pipewire.defaultAudioSource
            : kind === "application" && active ? streamNodes.find(node => String(node.id) === id) : null;
        return key !== "" && node && node.ready && node.audio && String(node.id) === id && reading(node).key === key ? node : null;
    }
    function change(kind, id, key, property, value): bool {
        if (readOnly || UiState.active !== "controls" || !["output", "input", "application"].includes(kind)
            || !["volume", "muted"].includes(property)) return false;
        if (fixture) {
            const next = JSON.parse(JSON.stringify(fixtureAudio));
            const rows = next[kind === "output" ? "outputs" : kind === "input" ? "inputs" : "streams"] || [];
            const row = rows.find(row => row.id === id && fixtureReading(row).key === key);
            if (!row || (kind !== "application" && !row.selected)) return false;
            row[property] = value;
            fixtureAudio = next;
        } else {
            const node = resolve(kind, id, key);
            if (!node) { error = "That audio device or application is no longer available."; return false; }
            if (property === "volume") node.audio.volume = value / 100;
            else node.audio.muted = value;
        }
        error = "";
        return true;
    }
    function setVolume(kind, id, key, value): bool {
        if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 100) return false;
        return change(kind, id, key, "volume", value);
    }
    function toggleMuted(kind, id, key): bool {
        const state = control(kind, id);
        if (!state.available || state.id !== id || state.key !== key) return false;
        return change(kind, id, key, "muted", !state.muted);
    }
    function open(): bool {
        if (UiState.active === "controls" && ConnectivityService.page === "audio") { UiState.close("controls"); return true; }
        const opened = ConnectivityService.open("audio");
        ConnectivityService.audioReturn = "main";
        return opened;
    }
    function ensure(): void {
        if (fixture) {
            if (!fixtureLoaded && ConnectivityService.state.audio) {
                fixtureAudio = JSON.parse(JSON.stringify(ConnectivityService.state.audio));
                fixtureLoaded = true;
            }
        } else refresh();
    }
    function refresh(): void {
        if (fixture) return;
        if (worker.running) { pending = true; return; }
        worker.command = ["python3", Quickshell.shellPath("scripts/audio-profiles.py"), "--snapshot"];
        worker.running = true;
    }
    function choose(kind, id): bool {
        if (readOnly || !["output", "input"].includes(kind)) return false;
        if (fixture) {
            const next = JSON.parse(JSON.stringify(fixtureAudio));
            const rows = next[kind === "output" ? "outputs" : "inputs"];
            if (!rows.some(row => row.id === id)) return false;
            rows.forEach(row => row.selected = row.id === id);
            fixtureAudio = next;
        } else {
            const node = (kind === "output" ? sinks : sources).find(n => String(n.id) === id);
            if (!node) { error = "That audio device is no longer available."; return false; }
            if (kind === "output") Pipewire.preferredDefaultAudioSink = node;
            else Pipewire.preferredDefaultAudioSource = node;
        }
        error = "";
        return true;
    }
    function profile(cardId, id): bool {
        if (readOnly || busy) return false;
        const card = cards.find(c => c.id === cardId);
        if (!card || !card.profiles.some(p => p.id === id)) return false;
        if (fixture) {
            const next = JSON.parse(JSON.stringify(fixtureAudio));
            next.cards.find(c => c.id === cardId).profiles.forEach(p => p.selected = p.id === id);
            fixtureAudio = next;
        } else {
            worker.command = ["python3", Quickshell.shellPath("scripts/audio-profiles.py"), "--card", card.id, "--name", card.key, "--profile", id];
            worker.running = true;
        }
        return true;
    }
    function status() { return {outputs: outputs, inputs: inputs, cards: cards, output: output, input: input,
        applications: applications, error: error, busy: busy, readOnly: readOnly}; }
    Connections {
        target: ConnectivityService
        function onReadyChanged() { if (ConnectivityService.ready && ConnectivityService.page === "audio") root.ensure(); }
        function onStateChanged() {
            if (root.fixture || ConnectivityService.page !== "audio") return;
            const bt = ConnectivityService.bluetooth;
            const key = JSON.stringify([bt.enabled, bt.devices.map(d => [d.id, d.connected, d.paired])]);
            if (key !== root.deviceKey) { root.deviceKey = key; refreshDelay.restart(); }
        }
    }
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { if (!root.fixture && ConnectivityService.page === "audio") refreshDelay.restart(); }
    }
    Timer { id: refreshDelay; interval: 150; onTriggered: root.refresh() }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.realCards = value.cards || [];
                    root.error = value.error || "";
                } catch (failure) { root.error = "Audio profiles unavailable."; }
            }
        }
        stderr: StdioCollector {} // Never forward arbitrary external diagnostic text.
        onExited: (code, status) => {
            if (code !== 0) root.error = "Audio profile service stopped.";
            if (root.pending) { root.pending = false; refreshDelay.restart(); }
        }
    }
}
