import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { UiState.toggle("wallpaper"); }
        function open(): void { UiState.show("wallpaper"); }
        function close(): void { UiState.close("wallpaper"); }
        function search(query: string): void { UiState.show("wallpaper"); WallpaperData.query = query; }
        function results(): string { return JSON.stringify(WallpaperData.filtered); }
        function activate(): void { WallpaperData.apply(); }
        function select(index: int): void { WallpaperData.select(index); }
        function size(width: int, height: int): void {
            if (view.item) view.item.resize(Math.max(260, Math.min(1200, width)), Math.max(260, Math.min(900, height)));
        }
        function status(): string {
            return JSON.stringify(Object.assign({view: FeatureSettings.wallpaper, selected: WallpaperData.selectedIndex,
                path: WallpaperData.selected ? WallpaperData.selected.path : "",
                current: Boolean(WallpaperData.selected && WallpaperData.selected.current),
                fonts: view.item ? view.item.typography() : [],
                busy: WallpaperData.busy, scanning: WallpaperData.scanning, error: WallpaperData.errorMessage},
                view.item ? view.item.metrics() : {}));
        }
    }
    Connections {
        target: UiState
        function onActiveChanged() {
            if (UiState.active === "wallpaper") { WallpaperData.query = ""; WallpaperData.rescan(); }
        }
    }
    Loader { id: view; sourceComponent: FeatureSettings.wallpaper === "gallery" ? gallery : FeatureSettings.wallpaper === "carousel" ? carousel : list }
    Component { id: list; ListPicker {} }
    Component { id: gallery; GalleryPicker {} }
    Component { id: carousel; CarouselPicker {} }
}
