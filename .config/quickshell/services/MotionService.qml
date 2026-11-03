pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property var settings: ({enabled: true, pickerDuration: 800, fadeDuration: 180,
        pickerCurve: [0, 0.75, 0.15, 1, 1, 1], fadeCurve: [0.05, 0.8, 0.1, 0.97, 1, 1]})

    function accept(text): void {
        try {
            const data = JSON.parse(text), animations = data.animations[0], curves = data.animations[1];
            const inherited = names => names.map(name => animations.find(entry => entry.name === name))
                .find(entry => entry && entry.overridden);
            const layers = inherited(["layersIn", "layers", "global"]);
            const fade = inherited(["fadeLayersIn", "fadeLayers", "fade", "global"]);
            const curve = (entry, fallback) => {
                const found = curves.find(curve => curve.name === entry.bezier);
                return found ? [found.X0, found.Y0, found.X1, found.Y1, 1, 1] : fallback;
            };
            if (layers && fade) settings = {enabled: data.option.bool !== false
                    && data.option.int !== 0 && layers.enabled && fade.enabled,
                pickerDuration: Math.round(layers.speed * 100), fadeDuration: Math.round(fade.speed * 100),
                pickerCurve: curve(layers, [0, 0.75, 0.15, 1, 1, 1]),
                fadeCurve: curve(fade, [0.05, 0.8, 0.1, 0.97, 1, 1])};
        } catch (error) { /* outside Hyprland, retain the last valid settings */ }
    }

    // Coalesce reload bursts, including a reload arriving during an IPC read.
    function refresh(): void { refreshTimer.restart(); }
    Timer {
        id: refreshTimer
        interval: 100
        onTriggered: {
            if (reader.running) restart();
            else reader.running = true;
        }
    }
    Process {
        id: reader
        command: ["sh", "-c", "printf '{\"option\":'; hyprctl getoption animations:enabled -j; printf ',\"animations\":'; hyprctl animations -j; printf '}'"]
        running: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.refresh();
        }
    }
    // Runtime keyword changes need not emit configreloaded. Keep a slow recovery
    // poll, not a pair of hyprctl subprocesses every five seconds.
    Timer {
        interval: 60000
        running: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
        repeat: true
        onTriggered: root.refresh()
    }
}
