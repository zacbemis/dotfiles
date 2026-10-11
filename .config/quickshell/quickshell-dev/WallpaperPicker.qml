import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var wallpapers: []
    property string errorMessage: ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string wallpaperDirectory: Quickshell.env("WALL_DIR") || home + "/Pictures/wallpapers"
    readonly property string setter: Quickshell.env("SETTER") || home + "/.config/hypr/scripts/set-wallpaper.sh"
    readonly property var filtered: wallpapers.filter(entry =>
        entry.name.toLowerCase().includes(picker.query.trim().toLowerCase()))
    readonly property var selected: filtered[picker.selectedIndex] || null

    function rescan(): void {
        if (!scanner.running) {
            errorMessage = "";
            scanner.running = true;
        }
    }

    function apply(): void {
        if (!selected || setterProcess.running) return;
        errorMessage = "";
        setterProcess.command = ["bash", root.setter, selected.path];
        setterProcess.running = true;
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { UiState.toggle("wallpaper"); }
        function open(): void { UiState.show("wallpaper"); }
        function close(): void { UiState.close("wallpaper"); }
        function search(query: string): void { UiState.show("wallpaper"); picker.query = query; }
        function results(): string { return JSON.stringify(root.filtered); }
        function activate(): void { root.apply(); }
        function select(index: int): void { picker.select(index); }
        // Development-only sizing hook: exercise narrow cards without changing
        // monitor resolution or the live desktop's output layout.
        function size(width: int, height: int): void {
            picker.preferredWidth = Math.max(260, Math.min(1200, width));
            picker.preferredHeight = Math.max(260, Math.min(900, height));
        }
        function status(): string {
            return JSON.stringify({selected: picker.selectedIndex, path: root.selected ? root.selected.path : "",
                current: Boolean(root.selected && root.selected.current), busy: setterProcess.running,
                scanning: scanner.running, compact: contentLayout.columns === 1, previewVisible: previewCard.visible});
        }
    }

    Process {
        id: scanner
        command: ["python3", Quickshell.shellPath("wallpaper-scan.py"),
            root.wallpaperDirectory, root.home + "/.config/hypr/current_wallpaper"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wallpapers = JSON.parse(text || "[]");
                    const current = root.filtered.findIndex(entry => entry.current);
                    picker.select(current >= 0 ? current : 0);
                } catch (error) {
                    root.wallpapers = [];
                    root.errorMessage = "Could not read wallpaper list";
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) root.errorMessage = "Could not scan " + root.wallpaperDirectory;
        }
    }

    Process {
        id: setterProcess
        onExited: function(code) {
            if (code === 0) UiState.close("wallpaper");
            else root.errorMessage = "Wallpaper setter failed (exit " + code + ")";
        }
    }

    PickerWindow {
        id: picker
        route: "wallpaper"
        title: "Wallpapers"
        preferredWidth: 820
        preferredHeight: 500
        itemCount: root.filtered.length
        actionText: "apply"
        statusText: scanner.running ? "Scanning…" : itemCount + " images"
        refreshable: true
        onRefreshRequested: root.rescan()
        onActivated: root.apply()
        onVisibleChanged: if (visible) root.rescan()

        GridLayout {
            id: contentLayout
            anchors.fill: parent
            columns: width < 600 ? 1 : 2
            rowSpacing: 12
            columnSpacing: 16

            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 330
                Layout.preferredHeight: contentLayout.columns === 1 ? 150 : 300
                model: root.filtered
                currentIndex: picker.selectedIndex
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                clip: true
                spacing: 5
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThemeScrollBar {}

                delegate: Rectangle {
                    id: wallpaperRow
                    required property var modelData
                    required property int index
                    readonly property bool selected: picker.selectedIndex === index
                    width: results.width - 10
                    height: 58
                    radius: 8
                    color: selected || mouse.containsMouse ? Theme.pickerSelectedBackground : Theme.transparentColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 44
                            color: Theme.panelSurface
                            radius: 4
                            clip: true
                            Image {
                                id: thumbnail
                                anchors.fill: parent
                                source: Theme.fileUrl(wallpaperRow.modelData.path)
                                sourceSize { width: 128; height: 88 }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            ThemeText {
                                anchors.centerIn: parent
                                text: thumbnail.status === Image.Error ? "" : "…"
                                color: Theme.surfaceVariantText
                                visible: thumbnail.status !== Image.Ready
                            }
                        }
                        ThemeText {
                            Layout.fillWidth: true
                            text: wallpaperRow.modelData.name
                            color: wallpaperRow.selected || mouse.containsMouse ? Theme.pickerSelectedText : Theme.surfaceText
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                        GlyphIcon {
                            glyph: ""
                            visible: wallpaperRow.modelData.current
                            color: wallpaperRow.selected || mouse.containsMouse ? Theme.pickerSelectedText : Theme.primary
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.select(wallpaperRow.index)
                        onDoubleClicked: { picker.select(wallpaperRow.index); root.apply(); }
                    }
                }
            }

            Rectangle {
                id: previewCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 370
                Layout.preferredHeight: 250
                visible: contentLayout.columns > 1 || contentLayout.height > 300
                radius: 10
                color: Theme.panelSurface
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Image {
                        id: preview
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        source: root.selected ? Theme.fileUrl(root.selected.path) : ""
                        sourceSize { width: 800; height: 600 }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        ThemeText {
                            anchors.centerIn: parent
                            text: scanner.running || preview.status === Image.Loading ? "Loading…"
                                : preview.status === Image.Error ? "Preview unavailable" : "No wallpapers found"
                            visible: !root.selected || preview.status === Image.Error || preview.status === Image.Loading
                            color: Theme.surfaceVariantText
                            font.family: Theme.fontFamily
                        }
                    }
                    ThemeText {
                        Layout.fillWidth: true
                        text: root.selected ? root.selected.name : "Add images to " + root.wallpaperDirectory
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideMiddle
                    }
                    ThemeText {
                        Layout.fillWidth: true
                        text: root.errorMessage || (root.selected && root.selected.current
                            ? "Current wallpaper" : "Uses your existing Pywal wallpaper pipeline")
                        color: root.errorMessage ? Theme.error : Theme.surfaceVariantText
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                    ThemeButton {
                        Layout.fillWidth: true
                        text: setterProcess.running ? "Applying…" : "Apply wallpaper"
                        pickerStyle: true
                        baseColor: Theme.primary
                        enabled: Boolean(root.selected) && !setterProcess.running && !scanner.running
                        onClicked: root.apply()
                    }
                }
            }
        }
    }
}
