pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool simulated: ShellProfile.comparing
    property bool enabled: false
    property bool pending: false
    property bool stopping: false
    property string error: ""
    function set(value): bool {
        if (typeof value !== "boolean" || pending) return false;
        error = "";
        if (simulated) { enabled = value; return true; }
        if (value === enabled) return true;
        pending = true;
        stopping = !value;
        holder.running = value;
        return true;
    }
    function toggle(): bool { return set(!enabled); }
    function status() { return {enabled: enabled, pending: pending, error: error, simulated: simulated}; }
    Process {
        id: holder
        command: ["python3", Quickshell.shellPath("scripts/caffeine.py")]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const state = JSON.parse(line);
                    root.enabled = state.enabled === true;
                    root.error = state.error || "";
                    root.pending = false;
                } catch (failure) { root.error = "Could not enable caffeine mode."; holder.running = false; }
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (!running && root.pending && !root.stopping) {
                root.pending = false;
                root.error = "Could not enable caffeine mode.";
            }
        }
        onExited: (code, status) => {
            root.enabled = false;
            root.pending = false;
            if (!root.stopping && !root.error) root.error = "Caffeine mode stopped unexpectedly.";
            root.stopping = false;
        }
    }
}
