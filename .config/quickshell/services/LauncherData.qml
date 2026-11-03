// SPDX-License-Identifier: MIT
// MM query-mode source/license retained in vendor/mm2103/upstream/launcher/.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One controller for every launcher view. App launching and usage storage stay
// local; query-mode routing is adapted from MM-2103 LauncherService (MIT).
Singleton {
    id: root
    property string query: ""
    property int selectedIndex: 0
    property var lastPointerPosition: null
    signal focusRequested()
    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property var modeChoices: [{key: "apps", label: "Apps"}, {key: "run", label: "Run"},
        {key: "files", label: "Files"}, {key: "wallpaper", label: "Wallpapers"}]
    onQueryChanged: {
        selectedIndex = 0;
        fileRows = [];
        fileError = "";
        if (fileQuery.running) fileQuery.running = false;
        fileDelay.restart();
    }
    readonly property string mode: query.startsWith(">") ? "run"
        : query.startsWith("/") || query.startsWith("~/") ? "files"
        : query.startsWith("=") ? "calc" : query.startsWith("?") ? "web" : query.startsWith(";") ? "emoji" : "apps"
    function setMode(value): bool {
        if (value === "wallpaper") { UiState.show("wallpaper"); return true; }
        if (!["apps", "run", "files"].includes(value)) return false;
        query = value === "run" ? "> " : value === "files" ? home + "/" : "";
        focusRequested();
        return true;
    }
    function normalized(value): string {
        return String(value).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    }
    property var commands: []
    property bool commandsReady: false
    property var fileRows: []
    property string fileError: ""
    onModeChanged: if (mode === "run" && !commandsReady && !commandIndex.running) commandIndex.running = true
    FileView { id: runFile; path: Quickshell.statePath("launcher-run-history.json"); blockLoading: true; printErrors: false }
    property var runHistory: { const value = parse(runFile.text(), []); return Array.isArray(value) ? value.filter(x => typeof x === "string") : []; }
    Process {
        id: commandIndex
        command: ["python3", Quickshell.shellPath("scripts/launcher-index.py"), "commands"]
        stdout: StdioCollector { onStreamFinished: { root.commands = root.parse(text, []); root.commandsReady = true; } }
    }
    Timer {
        id: fileDelay; interval: 80
        onTriggered: if (root.mode === "files") {
            fileQuery.command = ["python3", Quickshell.shellPath("scripts/launcher-index.py"), "files", root.query];
            fileQuery.running = true;
        }
    }
    Process {
        id: fileQuery
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text, {});
                if (root.mode === "files" && result.query === root.query) {
                    root.fileRows = result.rows || [];
                    root.fileError = result.error || "";
                }
            }
        }
    }
    FileView {
        id: rofiFile
        path: (Quickshell.env("HOME") || "") + "/.cache/rofi3.druncache"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    FileView { id: usageFile; path: Quickshell.statePath("launcher-usage.json"); blockLoading: true; printErrors: false }
    FileView { id: pinsFile; path: Quickshell.statePath("launcher-pins.json"); blockLoading: true; printErrors: false }
    property var localUsage: {
        const value = parse(usageFile.text(), {});
        return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    }
    property var pins: {
        const value = parse(pinsFile.text(), []);
        return Array.isArray(value) ? value.filter(id => typeof id === "string") : [];
    }
    function parse(text, fallback) { try { return JSON.parse(text || ""); } catch (error) { return fallback; } }
    readonly property var rofiUsage: {
        const scores = {};
        for (const line of rofiFile.text().split("\n")) {
            const match = line.trim().match(/^(\d+)\s+(.+)$/);
            if (match) scores[match[2]] = Number(match[1]);
        }
        return scores;
    }
    function usageFor(entry): int {
        const id = String(entry.id || ""), base = id.endsWith(".desktop") ? id.slice(0, -8) : id;
        return (localUsage[id] || 0) + (rofiUsage[id] || rofiUsage[base] || rofiUsage[base + ".desktop"] || 0);
    }
    readonly property var apps: {
        const q = mode === "apps" ? normalized(query.trim()) : "";
        const terms = q.split(/\s+/).filter(Boolean);
        return [...DesktopEntries.applications.values].filter(entry => {
            const categories = entry.categories || [];
            if (entry.noDisplay || !entry.name || categories.includes("X-XFCE") || categories.includes("X-Xfce-Toplevel")) return false;
            const text = [entry.name, entry.genericName, entry.execString, ...(entry.keywords || []), ...categories].join(" ");
            const haystack = normalized(text);
            return terms.every(term => haystack.includes(term));
        }).sort((a, b) => {
            if (FeatureSettings.launcher === "grid" && !q && pins.includes(a.id) !== pins.includes(b.id)) return pins.includes(a.id) ? -1 : 1;
            const as = q && normalized(a.name).startsWith(q), bs = q && normalized(b.name).startsWith(q);
            return as !== bs ? (as ? -1 : 1) : usageFor(b) - usageFor(a) || a.name.localeCompare(b.name);
        });
    }
    property var emoji: []
    FileView {
        path: root.mode === "emoji" ? Quickshell.shellPath("vendor/mm2103/upstream/launcher/emoji.json") : ""
        printErrors: false
        onLoaded: root.emoji = root.parse(text(), [])
    }
    // MM's calculator allows only numeric arithmetic, never identifiers or shell
    // commands. Bound input length and reject non-finite results too.
    function calculate(text): string {
        const expression = text.trim().replace(/,/g, ".");
        if (!expression || expression.length > 256 || !/^[0-9+\-*/().%\s]+$/.test(expression)) return "";
        try {
            const value = (new Function("return (" + expression + ")"))();
            return typeof value === "number" && Number.isFinite(value) ? String(value) : "";
        } catch (error) { return ""; }
    }
    readonly property var rows: {
        const q = query.slice(1).trim();
        if (mode === "files") return fileRows;
        if (mode === "run") {
            const choices = [...new Set([...runHistory, ...commands])].filter(command => normalized(command).startsWith(normalized(q)));
            if (q && !choices.includes(q)) choices.unshift(q);
            return choices.slice(0, 100).map(command => ({key: "run:" + command, kind: "run", name: command,
                detail: "Run command · execution only on Enter/click", value: command, icon: "utilities-terminal"}));
        }
        if (mode === "calc") {
            const result = calculate(q);
            return result ? [{key: "calc", kind: "calc", name: result, detail: "Enter to copy · " + q, value: result, icon: "accessories-calculator"}] : [];
        }
        if (mode === "web") return q ? [{key: "web", kind: "web", name: "Search DuckDuckGo: " + q,
            detail: "Opens your browser only when activated", value: q, icon: "web-browser"}] : [];
        if (mode === "emoji") return emoji.filter(e => [e.description, ...(e.aliases || []), ...(e.tags || [])]
            .join(" ").toLowerCase().includes(q.toLowerCase())).slice(0, 80).map(e => ({key: "emoji:" + e.emoji,
                kind: "emoji", name: e.emoji + "  " + e.description, detail: "Enter to copy", value: e.emoji, icon: ""}));
        return apps.map(entry => ({key: entry.id, kind: "app", name: entry.name,
            detail: entry.genericName || "", icon: entry.icon || "", entry: entry}));
    }
    onRowsChanged: select(selectedIndex)
    function select(index): void { selectedIndex = rows.length ? Math.max(0, Math.min(index, rows.length - 1)) : -1; }
    function togglePin(index): bool {
        const row = rows[index];
        if (!row || row.kind !== "app") return false;
        pins = pins.includes(row.key) ? pins.filter(id => id !== row.key) : [...pins, row.key];
        pinsFile.setText(JSON.stringify(pins));
        return true;
    }
    function activate(index): void {
        const row = rows[index];
        if (!row) return;
        if (row.kind === "app") {
            if (row.entry.runInTerminal) Quickshell.execDetached(["kitty", "--directory", row.entry.workingDirectory || home, "-e", ...row.entry.command]);
            else row.entry.execute();
            const scores = Object.assign({}, localUsage);
            scores[row.entry.id] = (scores[row.entry.id] || 0) + 1;
            localUsage = scores;
            usageFile.setText(JSON.stringify(scores));
        } else if (row.kind === "directory") {
            query = row.value.replace(/\/$/, "") + "/";
            focusRequested();
            return;
        } else if (row.kind === "file") Quickshell.execDetached(["xdg-open", row.value]);
        else if (row.kind === "run") {
            runHistory = [row.value, ...runHistory.filter(command => command !== row.value)].slice(0, 25);
            runFile.setText(JSON.stringify(runHistory));
            Quickshell.execDetached(["bash", "-lc", row.value]);
        } else if (row.kind === "web") Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(row.value));
        else Quickshell.execDetached(["wl-copy", "--", row.value]);
        UiState.close("launcher");
    }
    function pointerMoved(position): bool {
        const previous = lastPointerPosition;
        lastPointerPosition = position;
        return previous !== null && (Math.abs(position.x - previous.x) > 0.25 || Math.abs(position.y - previous.y) > 0.25);
    }
}
