pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "StyleCatalog.js" as Catalog

Singleton {
    id: root
    readonly property bool persistent: Quickshell.env("QUICKSHELL_COMPARE") !== "1"
        && Quickshell.env("QUICKSHELL_PERSIST_SETTINGS") !== "0"
        && (Quickshell.env("QUICKSHELL_PERSIST_SETTINGS") === "1" || Quickshell.env("QUICKSHELL_NOTIFICATIONS") === "server")
    readonly property string path: Quickshell.env("QUICKSHELL_PREFERENCES") || Quickshell.statePath("shell-preferences.json")
    readonly property var choices: Catalog.choices()
    property string error: ""
    property bool writing: false
    property int batchDepth: 0
    property bool dirty: false
    readonly property bool pending: dirty || writing
    property var values: {
        if (!persistent) return {};
        try {
            const value = JSON.parse(file.text() || "{}");
            return value.version === 1 ? Catalog.sanitize(value) : {};
        } catch (failure) { return {}; }
    }
    function value(key, fallback) { return values[key] === undefined ? fallback : values[key]; }
    function set(key, value): bool {
        if (!Catalog.valid(key, value)) return false;
        if (!persistent) return true;
        if (values[key] === value) return true;
        values = Object.assign({}, values, {[key]: value});
        error = "";
        dirty = true;
        if (batchDepth === 0) flush();
        return true;
    }
    function beginBatch(): void { batchDepth++; }
    function endBatch(): void {
        batchDepth = Math.max(0, batchDepth - 1);
        if (batchDepth === 0 && dirty) flush();
    }
    function flush(): void {
        if (!persistent) return;
        dirty = false;
        writing = true;
        file.setText(JSON.stringify(Object.assign({version: 1}, Catalog.sanitize(values)), null, 2));
    }
    FileView {
        id: file
        path: root.persistent ? root.path : ""
        blockLoading: true
        printErrors: false
        atomicWrites: true
        // Tiny state file; finish before the selection call returns. Process exit
        // does not reliably deliver QML destruction callbacks for a delayed save.
        blockWrites: true
        onSaved: { root.writing = false; root.error = ""; }
        onSaveFailed: error => { root.writing = false; root.error = "Could not save shell preferences (" + error + ")"; }
    }
}
