import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.theme

Scope {
    IpcHandler {
        target: "launcher"
        function toggle(): void { UiState.toggle("launcher"); }
        function open(): void { UiState.show("launcher"); }
        function close(): void { UiState.close("launcher"); }
        function search(query: string): void { UiState.show("launcher"); LauncherData.query = query; }
        function mode(value: string): bool { UiState.show("launcher"); return LauncherData.setMode(value); }
        function results(): string { return JSON.stringify(LauncherData.rows.map(row => row.name)); }
        function status(): string {
            return JSON.stringify({selected: LauncherData.selectedIndex, query: LauncherData.query,
                view: FeatureSettings.launcher, mode: LauncherData.mode, pins: LauncherData.pins,
                error: LauncherData.fileError, indexing: LauncherData.mode === "files" && LauncherData.fileRows.length === 0,
                rows: LauncherData.rows.map(row => ({name: row.name, kind: row.kind, value: row.value || ""})),
                rendered: view.item ? view.item.renderedCount() : 0, columns: view.item ? view.item.navigationColumns : 1,
                firstRowTop: view.item ? view.item.firstRowTop() : 0,
                fonts: view.item ? view.item.typography() : [],
                size: view.item ? view.item.dimensions() : null,
                iconSize: FeatureSettings.launcher === "grid" ? 40 : FeatureSettings.launcher === "mm2103" ? 32 : Theme.launcherIconSize,
                selectedName: LauncherData.rows[LauncherData.selectedIndex] ? LauncherData.rows[LauncherData.selectedIndex].name : ""});
        }
        function navigate(direction: string): bool {
            const keys = {up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right, home: Qt.Key_Home, end: Qt.Key_End};
            if (!view.item || keys[direction] === undefined) return false;
            view.item.handleKey({key: keys[direction], accepted: false});
            return true;
        }
        function select(index: int): void { LauncherData.select(index); }
        function pin(index: int): bool { return LauncherData.togglePin(index); }
        function activate(): void { LauncherData.activate(LauncherData.selectedIndex); }
    }
    Connections {
        target: UiState
        function onActiveChanged() {
            if (UiState.active === "launcher") { LauncherData.query = ""; LauncherData.select(0); }
        }
    }
    Loader {
        id: view
        sourceComponent: FeatureSettings.launcher === "grid" ? grid : list
    }
    Component { id: list; ListPicker {} }
    Component { id: grid; GridPicker {} }
}
