pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string backlightRoot: Quickshell.env("QUICKSHELL_BACKLIGHT_ROOT") || "/sys/class/backlight"
    property string device: ""
    property int maximum: 0
    property int percent: 0
    property bool available: false
    property int pendingSteps: 0
    property int pendingPercent: -1
    readonly property string automationPath: Quickshell.env("QUICKSHELL_BRIGHTNESS_AUTOMATION")
        || (Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-desktop/brightness-automation.json" : "")
    property string consumedAutomation: ""
    signal osdRequested(int value)

    function automaticSample(current): bool {
        if (!automationPath) return false;
        automationFile.reload();
        try {
            const marker = JSON.parse(automationFile.text());
            const remaining = marker.expires - Date.now();
            if (marker.version !== 1 || marker.device !== device || !Number.isFinite(remaining)
                    || remaining <= 0 || remaining > 10000 || typeof marker.token !== "string" || !marker.token
                    || !Number.isFinite(marker.raw)) return false;
            if (marker.phase === "pending") return marker.raw === current;
            if (marker.phase !== "complete" || marker.token === consumedAutomation) return false;
            // Consume on any valid poll, including unchanged values. A later
            // manual adjustment back to the restore value must still show OSD.
            consumedAutomation = marker.token;
            return marker.raw === current;
        } catch (error) { return false; }
    }
    function acceptValue(text): void {
        const value = text.trim();
        const current = Number(value);
        const hadValue = available;
        available = value !== "" && Number.isFinite(current) && current >= 0 && maximum > 0;
        if (available) {
            const automatic = automaticSample(current);
            const next = Math.max(0, Math.min(100, Math.floor(current * 100 / maximum)));
            const changed = percent !== next;
            percent = next;
            if (hadValue && changed && !automatic) osdRequested(next);
        }
    }
    FileView {
        id: automationFile
        path: root.automationPath
        preload: false
        blockAllReads: true
        printErrors: false
    }

    // Discover the same backlight brightnessctl will control. Never select a
    // keyboard LED on machines without a panel backlight.
    Process {
        id: discovery
        command: ["sh", "-c", "command -v brightnessctl >/dev/null 2>&1 && brightnessctl --class=backlight --machine-readable info 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(",");
                if (fields[1] === "backlight" && /^[\w.-]+$/.test(fields[0]) && Number(fields[4]) > 0) {
                    root.maximum = Number(fields[4]);
                    root.device = fields[0];
                    currentFile.reload();
                } else {
                    root.available = false;
                    root.device = "";
                }
            }
        }
    }

    FileView {
        id: currentFile
        path: root.device ? root.backlightRoot + "/" + root.device + "/brightness" : ""
        printErrors: false
        onLoaded: root.acceptValue(text())
        onLoadFailed: root.available = false
    }

    // sysfs attributes do not reliably emit inotify events. Read the tiny file
    // directly instead of spawning a shell and two brightnessctls every second.
    Timer {
        interval: 1000
        running: root.device !== ""
        repeat: true
        onTriggered: currentFile.reload()
    }
    Timer {
        interval: 30000
        running: !root.available
        repeat: true
        onTriggered: if (!discovery.running) discovery.running = true
    }

    function adjust(delta): void {
        if (!available || delta === 0) return;
        if (pendingPercent >= 0) pendingPercent = Math.max(0, Math.min(100, pendingPercent + (delta > 0 ? 5 : -5)));
        else pendingSteps += delta > 0 ? 1 : -1;
        flush();
    }
    function setPercent(value): void {
        if (!available || !Number.isFinite(value)) return;
        pendingSteps = 0;
        pendingPercent = Math.max(0, Math.min(100, Math.round(value)));
        flush();
    }
    function flush(): void {
        if (setter.running || (pendingSteps === 0 && pendingPercent < 0)) return;
        const setting = pendingPercent >= 0 ? pendingPercent + "%" : Math.abs(pendingSteps) * 5 + (pendingSteps > 0 ? "%+" : "%-");
        pendingSteps = 0;
        pendingPercent = -1;
        setter.command = ["brightnessctl", "--class=backlight", "--device=" + device, "set", setting];
        setter.running = true;
    }
    Process {
        id: setter
        onExited: {
            currentFile.reload();
            Qt.callLater(root.flush);
        }
    }
}
