pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.theme

Singleton {
    id: root

    function ignoredSink(node): bool {
        const names = node ? [node.name || "", node.description || ""] : [];
        return names.some(name => name.toLowerCase().replace(/[\s_-]/g, "") === "easyeffectssink");
    }
    readonly property var audioSinks: Pipewire.nodes.values.filter(node => node.isSink && !node.isStream && (node.type & PwNodeType.Audio))
    readonly property var audioSink: !ignoredSink(Pipewire.defaultAudioSink) ? Pipewire.defaultAudioSink
        : audioSinks.find(node => !ignoredSink(node)) || null
    readonly property var battery: UPower.displayDevice

    readonly property int volumePercent: {
        if (!root.audioSink || !root.audioSink.audio) return 0;
        return Math.round(root.audioSink.audio.volume * 100);
    }
    readonly property bool muted: Boolean(root.audioSink && root.audioSink.audio && root.audioSink.audio.muted)
    readonly property string volumeTooltip: (audioSink ? audioSink.description || audioSink.name : "No audio output")
        + "\n" + volumePercent + "%"
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

    readonly property int brightnessPercent: BrightnessService.percent
    readonly property bool brightnessAvailable: BrightnessService.available
    readonly property string brightnessIcon: brightnessPercent <= 33 ? "󰃞" : brightnessPercent <= 66 ? "󰃟" : "󰃠"

    readonly property bool batteryAvailable: Boolean(root.battery && root.battery.ready && root.battery.isPresent)
    readonly property int batteryPercent: batteryAvailable
        ? Math.round(root.battery.percentage * 100) : 0
    readonly property bool batteryCharging: batteryAvailable
        && root.battery.state === UPowerDeviceState.Charging
    readonly property bool batteryFull: batteryAvailable && root.battery.state === UPowerDeviceState.FullyCharged
    readonly property bool batteryPlugged: batteryAvailable && !UPower.onBattery
    readonly property string batteryStatus: batteryCharging ? "Charging" : batteryFull ? "Fully charged" : batteryPlugged ? "Plugged in" : "On battery"
    readonly property color batteryWarning: Theme.primaryFixed
    readonly property string batteryIcon: {
        if (root.batteryPercent <= 10) return "";
        if (root.batteryPercent <= 25) return "";
        if (root.batteryPercent <= 45) return "";
        if (root.batteryPercent <= 70) return "";
        return "";
    }

    function indicator(kind) {
        if (kind === "volume") return {kind: kind, value: volumePercent, muted: muted, bluetooth: bluetoothAudio, available: !!audioSink};
        if (kind === "brightness") return {kind: kind, value: brightnessPercent, available: brightnessAvailable};
        return {kind: "battery", value: batteryPercent, charging: batteryCharging, full: batteryFull, plugged: batteryPlugged, available: batteryAvailable};
    }

    // Pipewire properties are only valid after the node has been bound.
    PwObjectTracker {
        objects: root.audioSinks
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
        BrightnessService.adjust(delta);
    }
}
