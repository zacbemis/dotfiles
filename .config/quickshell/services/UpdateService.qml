pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    FileView { id: cache; path: Quickshell.statePath("update-status.json"); blockLoading: true; printErrors: false }
    readonly property var saved: {
        try { const value = JSON.parse(cache.text() || "{}"); return Number.isInteger(value.count) && value.count >= 0 ? value : {}; }
        catch (error) { return {}; }
    }
    property int count: saved.count || 0
    readonly property bool checking: checker.running || feedback.running
    property double checkedAt: saved.checkedAt || 0
    property int serial: 0
    readonly property string summary: checking ? "Checking…" : error ? "Check failed" : known
        ? count === 0 ? "Up to date" : count + (count === 1 ? " update" : " updates") : "Updates"
    property bool known: saved.count !== undefined
    property string error: ""
    property bool pollingEnabled: false
    property bool resultReceived: false
    Component.onCompleted: if (Quickshell.env("QUICKSHELL_STARTUP_UPDATES") === "1") Qt.callLater(refresh)

    function refresh(): bool {
        if (checking) return false;
        resultReceived = false;
        error = "";
        serial++;
        feedback.restart();
        checker.running = true;
        return true;
    }
    function status() { return {count: count, known: known, checking: checking, error: error, summary: summary, checkedAt: checkedAt, serial: serial}; }
    // Keep fast/empty checks perceptible without delaying the actual query.
    Timer { id: feedback; interval: 600 }
    function runUpdates(): void {
        if (!runner.running) runner.running = true;
    }

    Process {
        id: checker
        command: ["python3", Quickshell.shellPath("scripts/check-updates.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (typeof result.ok !== "boolean" || !Number.isInteger(result.count) || result.count < 0)
                        throw new Error("Invalid result");
                    root.resultReceived = true;
                    root.known = result.ok;
                    root.error = Object.entries(result.errors || {}).map(([backend, message]) => backend + ": " + message).join("\n");
                    // Preserve the last successful count on failed/partial checks.
                    if (result.ok) {
                        root.count = result.count;
                        root.checkedAt = Date.now();
                        cache.setText(JSON.stringify({count: result.count, checkedAt: root.checkedAt}));
                    }
                } catch (error) {
                    root.known = false;
                    root.error = "Could not read update check result";
                }
            }
        }
        onExited: function(code) {
            if (code !== 0 || !root.resultReceived) {
                root.known = false;
                root.error = "Update checker failed (exit " + code + ")";
            }
        }
    }

    // UI owns demand; the service must not depend on overlay routing. Opening
    // the center still does not trigger an eager network check.
    Timer {
        interval: 300000
        running: root.pollingEnabled
        repeat: true
        onTriggered: root.refresh()
    }
    Process {
        id: runner
        command: ["kitty", "-e", "bash", "-lc", "yay -Syu; flatpak update"]
        onExited: root.refresh()
    }
}
