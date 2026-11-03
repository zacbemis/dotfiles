pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var wallpapers: []
    property string query: ""
    property int selectedIndex: 0
    property string errorMessage: ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string directory: Quickshell.env("WALL_DIR") || home + "/Pictures/wallpapers"
    readonly property string setter: Quickshell.env("SETTER") || home + "/.config/hypr/scripts/set-wallpaper.sh"
    readonly property var filtered: wallpapers.filter(entry => entry.name.toLowerCase().includes(query.trim().toLowerCase()))
    readonly property var selected: filtered[selectedIndex] || null
    readonly property bool scanning: scanner.running
    readonly property bool busy: writer.running
    onQueryChanged: select(0)
    onFilteredChanged: select(selectedIndex)
    function select(index): void { selectedIndex = filtered.length ? Math.max(0, Math.min(index, filtered.length - 1)) : -1; }
    function rescan(): void { if (!scanner.running) { errorMessage = ""; scanner.running = true; } }
    function apply(): void {
        if (!selected || busy || scanning) return;
        errorMessage = "";
        writer.command = ["bash", setter, selected.path];
        writer.running = true;
    }
    Process {
        id: scanner
        command: ["python3", Quickshell.shellPath("scripts/wallpaper-scan.py"), root.directory,
            root.home + "/.config/hypr/current_wallpaper"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpapers = JSON.parse(text || "[]");
                    const current = root.filtered.findIndex(entry => entry.current);
                    root.select(current >= 0 ? current : 0);
                } catch (error) { root.wallpapers = []; root.errorMessage = "Could not read wallpaper list"; }
            }
        }
        onExited: code => { if (code !== 0) root.errorMessage = "Could not scan " + root.directory; }
    }
    Process {
        id: writer
        onExited: code => {
            if (code === 0) UiState.close("wallpaper");
            else root.errorMessage = "Wallpaper setter failed (exit " + code + ")";
        }
    }
}
