pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var battery: UPower.displayDevice

    readonly property int volumePercent: {
        if (!root.audioSink || !root.audioSink.audio) return 0;
        return Math.round(root.audioSink.audio.volume * 100);
    }
    readonly property bool muted: Boolean(root.audioSink && root.audioSink.audio && root.audioSink.audio.muted)
    readonly property bool bluetoothAudio: {
        if (!root.audioSink) return false;
        const name = (root.audioSink.name || "").toLowerCase();
        const description = (root.audioSink.description || "").toLowerCase();
        const properties = root.audioSink.properties || {};
        return name.includes("bluez") || description.includes("bluetooth")
            || Boolean(properties["api.bluez5.address"]);
    }
    readonly property string volumeIcon: {
        if (root.muted) return "";
        const description = (root.audioSink && root.audioSink.description || "").toLowerCase();
        const icon = description.includes("headphone") ? ""
                   : root.volumePercent < 33 ? ""
                   : root.volumePercent < 66 ? "" : "";
        return icon + (root.bluetoothAudio ? "" : "");
    }

    property int brightnessPercent: 0
    property bool brightnessAvailable: false
    readonly property string brightnessIcon: {
        return clock.hours >= 17 || clock.hours < 5 ? "" : "󰃠";
    }

    readonly property bool batteryAvailable: Boolean(root.battery && root.battery.ready && root.battery.isPresent)
    readonly property int batteryPercent: batteryAvailable
        ? Math.round(root.battery.percentage * 100) : 0
    readonly property bool batteryCharging: batteryAvailable
        && root.battery.state === UPowerDeviceState.Charging
    readonly property color batteryWarning: Theme.primaryFixed
    readonly property string batteryIcon: {
        if (root.batteryPercent <= 10) return "";
        if (root.batteryPercent <= 25) return "";
        if (root.batteryPercent <= 45) return "";
        if (root.batteryPercent <= 70) return "";
        return "";
    }

    property int updateCount: 0
    property bool updateCheckRunning: false
    property bool updatesKnown: false

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Pipewire properties are only valid after the node has been bound.
    PwObjectTracker {
        objects: root.audioSink ? [root.audioSink] : []
    }

    Process {
        id: brightnessProcess
        command: [
            "sh", "-c",
            "cur=$(brightnessctl get 2>/dev/null || true); max=$(brightnessctl max 2>/dev/null || true); printf '%s\\n%s\\n' \"$cur\" \"$max\""
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split(/\s+/);
                root.brightnessAvailable = false;
                const current = Number(lines[0]);
                const maximum = Number(lines[1]);
                if (Number.isFinite(current) && Number.isFinite(maximum) && maximum > 0) {
                    root.brightnessPercent = Math.floor(current * 100 / maximum);
                    root.brightnessAvailable = true;
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: if (!brightnessProcess.running) brightnessProcess.running = true
    }

    Process {
        id: updateProcess
        command: [
            "sh", "-c",
            "pac=0; aur=0; flat=0; command -v checkupdates >/dev/null 2>&1 && pac=$(checkupdates 2>/dev/null | wc -l); command -v yay >/dev/null 2>&1 && aur=$(yay -Qua 2>/dev/null | wc -l); command -v flatpak >/dev/null 2>&1 && flat=$(flatpak remote-ls --updates 2>/dev/null | wc -l); printf '%s\\n' $((pac + aur + flat))"
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const count = Number(this.text.trim());
                root.updateCount = Number.isFinite(count) ? count : 0;
                root.updatesKnown = Number.isFinite(count);
                root.updateCheckRunning = false;
            }
        }

        onStarted: root.updateCheckRunning = true
        onExited: root.updateCheckRunning = false
    }

    Timer {
        interval: 300000
        running: UiState.active === "notifications"
        repeat: true
        onTriggered: root.refreshUpdates()
    }

    Process {
        id: updateRunner
        command: ["kitty", "-e", "bash", "-lc", "yay -Syu; flatpak update"]
        running: false
        onExited: root.refreshUpdates()
    }

    Component.onCompleted: {
        brightnessProcess.running = true;
    }

    function refreshUpdates(): void {
        if (!updateProcess.running) updateProcess.running = true;
    }

    function runUpdates(): void {
        if (!updateRunner.running) updateRunner.running = true;
    }

    function toggleMute(): void {
        if (root.audioSink && root.audioSink.audio)
            root.audioSink.audio.muted = !root.audioSink.audio.muted;
    }

    function adjustVolume(delta): void {
        if (!root.audioSink || !root.audioSink.audio) return;
        root.audioSink.audio.volume = Math.max(0, Math.min(1.0, root.audioSink.audio.volume + delta));
    }

    function adjustBrightness(delta): void {
        Quickshell.execDetached(["brightnessctl", "set", delta > 0 ? "5%+" : "5%-"]);
        // Poll after the command finishes instead of racing its old value.
        brightnessRefresh.restart();
    }

    Timer {
        id: brightnessRefresh
        interval: 150
        onTriggered: if (!brightnessProcess.running) brightnessProcess.running = true
    }
}
