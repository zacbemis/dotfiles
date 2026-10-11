import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

IconImage {
    id: root
    property string icon: ""
    property string resolvedPath: ""
    readonly property bool lookupPending: lookup.running || resolver.running
    readonly property string themeName: icon.startsWith("image://icon/")
        ? decodeURIComponent(icon.slice("image://icon/".length).split("?")[0]) : ""
    implicitSize: Theme.barImageSize
    source: resolvedPath ? Theme.fileUrl(resolvedPath) : icon

    // Qt selects a larger, padded Papirus variant at HiDPI, shrinking the ink
    // inside the requested 15px canvas. GTK selects the 16px logical-size asset
    // first, then renders it at monitor scale. Match that selection, not a 22px
    // workaround which makes unpadded third-party tray icons oversized.
    function resolve(): void { resolvedPath = ""; lookup.restart(); }
    onIconChanged: resolve()
    onImplicitSizeChanged: resolve()
    Component.onCompleted: resolve()
    Connections { target: root.Window.window; function onScreenChanged() { root.resolve(); } }
    Timer {
        id: lookup
        interval: 30
        onTriggered: {
            if (!root.themeName) return;
            if (resolver.running) { restart(); return; }
            resolver.command = ["python3", Quickshell.shellPath("theme-icon.py"), root.themeName,
                String(Math.round(root.implicitSize)), String(root.Screen.devicePixelRatio)];
            resolver.running = true;
        }
    }
    Process {
        id: resolver
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.name === root.themeName) root.resolvedPath = result.path;
                } catch (error) { /* retain the native source on lookup failure */ }
            }
        }
    }
}
