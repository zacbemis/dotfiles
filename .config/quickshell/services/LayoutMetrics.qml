pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root
    property var outer: ({top: 8, right: 8, bottom: 8, left: 8})
    property var inner: ({top: 4, right: 4, bottom: 4, left: 4})
    property var reservations: Object.create(null)
    property var origins: Object.create(null)
    property var layerFrames: Object.create(null)
    readonly property real windowGap: inner.top + inner.bottom
    function parse(option) {
        if (!option || typeof option !== "object") return null;
        const source = option.css !== undefined ? option.css : option.int;
        if (typeof source === "string" && !source.trim()) return null;
        const values = typeof source === "number" ? [source] : typeof source === "string" ? source.trim().split(/\s+/).map(Number) : [];
        if (!values.length || values.length > 4 || values.some(value => !Number.isFinite(value) || value < 0 || value > 1024)) return null;
        const top = values[0], right = values.length > 1 ? values[1] : top;
        return {top: top, right: right, bottom: values.length > 2 ? values[2] : top, left: values.length > 3 ? values[3] : right};
    }
    function parseReservations(monitors) {
        if (!Array.isArray(monitors)) return null;
        const result = Object.create(null);
        for (const monitor of monitors) {
            if (!monitor || typeof monitor.name !== "string" || !Array.isArray(monitor.reserved)
                || monitor.reserved.length !== 4 || monitor.reserved.some(value => typeof value !== "number" || !Number.isFinite(value) || value < 0)) return null;
            result[monitor.name] = monitor.reserved;
        }
        return result;
    }
    function parseLayers(layers) {
        if (!layers || typeof layers !== "object" || Array.isArray(layers)) return null;
        const frames = Object.create(null);
        for (const [name, monitor] of Object.entries(layers)) {
            if (!monitor || !monitor.levels || typeof monitor.levels !== "object") return null;
            frames[name] = [];
            for (const level of Object.values(monitor.levels)) {
                if (!Array.isArray(level)) return null;
                for (const layer of level) {
                    if (layer.pid !== Quickshell.processId) continue;
                    if (typeof layer.namespace !== "string" || [layer.x, layer.y, layer.w, layer.h].some(value => typeof value !== "number" || !Number.isFinite(value)) || layer.w < 0 || layer.h < 0) return null;
                    frames[name].push({namespace: layer.namespace, x: layer.x, y: layer.y, width: layer.w, height: layer.h});
                }
            }
        }
        return frames;
    }
    function barFrameFor(screen) {
        const frames = screen ? (layerFrames[screen.name] || []).filter(frame => ["quickshell-bar", "quickshell-compare-enzo", "quickshell-compare-mm2103"].includes(frame.namespace)) : [];
        return frames.length === 1 ? frames[0] : null;
    }
    function accept(text): bool {
        try {
            const value = JSON.parse(text), nextOuter = parse(value.outer), nextInner = parse(value.inner);
            const nextReservations = value.monitors === undefined ? reservations : parseReservations(value.monitors);
            const nextFrames = value.layers === undefined ? layerFrames : parseLayers(value.layers);
            const nextOrigins = value.monitors === undefined ? origins : Object.create(null);
            if (!nextOuter || !nextInner || !nextReservations || !nextFrames) return false;
            if (value.monitors !== undefined) for (const monitor of value.monitors) {
                if (monitor.x === undefined && monitor.y === undefined) continue;
                if (![monitor.x, monitor.y].every(value => typeof value === "number" && Number.isFinite(value))) return false;
                nextOrigins[monitor.name] = {x: monitor.x, y: monitor.y};
            }
            outer = nextOuter;
            inner = nextInner;
            reservations = nextReservations;
            origins = nextOrigins;
            layerFrames = nextFrames;
            return true;
        } catch (failure) { return false; }
    }
    function refresh(): void { if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "") refreshTimer.restart(); }
    Timer {
        id: refreshTimer
        interval: 100
        onTriggered: { if (reader.running) restart(); else reader.running = true; }
    }
    Process {
        id: reader
        command: ["sh", "-c", "printf '{\"outer\":'; hyprctl getoption general:gaps_out -j; printf ',\"inner\":'; hyprctl getoption general:gaps_in -j; printf ',\"monitors\":'; hyprctl monitors -j; printf ',\"layers\":'; hyprctl layers -j; printf '}'"]
        running: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
        stderr: StdioCollector {}
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || event.name.startsWith("monitor")
                || event.name === "openlayer" || event.name === "closelayer") root.refresh();
        }
    }
    Timer {
        interval: 60000
        running: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
        repeat: true
        onTriggered: root.refresh()
    }
}
