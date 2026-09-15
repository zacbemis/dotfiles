import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool open: false
    property string searchText: ""
    property var wallpapers: []
    property int selectedIndex: 0
    readonly property string wallpaperDirectory: (Quickshell.env("HOME") || "") + "/Pictures/wallpapers"
    readonly property string setter: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/set-wallpaper.sh"
    readonly property string thumbDirectory: (Quickshell.env("HOME") || "") + "/.cache/rofi-wallpaper-thumbs"

    function thumbSource(path): string {
        const base = path.split("/").pop();
        return "file://" + root.thumbDirectory + "/" + base + ".png";
    }

    function isFocused(screen) {
        const monitor = Hyprland.monitorFor(screen);
        return !Hyprland.focusedMonitor ||
            (monitor && monitor.name === Hyprland.focusedMonitor.name);
    }

    function toggle(): void {
        root.open = !root.open;
        if (root.open) {
            root.searchText = "";
            root.selectedIndex = 0;
            root.rescan();
        }
    }

    function rescan(): void {
        if (!scanner.running) scanner.running = true;
    }

    function apply(path): void {
        if (!path) return;
        Quickshell.execDetached([root.setter, path]);
        root.open = false;
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle(); }
    }

    readonly property var filteredWallpapers: {
        const query = root.searchText.trim().toLowerCase();
        return root.wallpapers.filter(function(path) {
            return query === "" || path.split("/").pop().toLowerCase().includes(query);
        });
    }

    Process {
        id: scanner
        command: [
            "sh", "-c",
            "find \"$HOME/Pictures/wallpapers\" -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -print 2>/dev/null | sort"
        ]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const output = this.text.trim();
                root.wallpapers = output === "" ? [] : output.split("\n").filter(path => path !== "");
                root.selectedIndex = root.filteredWallpapers.length > 0 ? 0 : -1;
            }
        }
    }

    Component.onCompleted: root.rescan()

    onSearchTextChanged: {
        root.selectedIndex = root.filteredWallpapers.length > 0 ? 0 : -1;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wallpaperWindow
            required property var modelData

            screen: modelData
            visible: root.open && root.isFocused(modelData)
            focusable: true
            color: Theme.transparentColor
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-dev-wallpaper"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.scrim

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.open = false
                }
            }

            Rectangle {
                id: wallpaperBox
                anchors.centerIn: parent
                width: 600
                height: 430
                radius: 10
                color: Theme.background
                border.color: Theme.outlineVariant
                border.width: 1
                z: 2

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true; }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 30
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "  Wallpapers"
                            color: Theme.surfaceText
                            font.family: Theme.iconFontFamily
                            font.bold: true
                            font.pixelSize: 14
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.filteredWallpapers.length + " images"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 10
                        }

                        Rectangle {
                            width: 28
                            height: 26
                            radius: 8
                            color: refreshMouse.containsMouse ? Theme.surfaceContainerHigh : Theme.transparentColor

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: Theme.surfaceVariantText
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: refreshMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.rescan()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 8
                        color: Theme.transparentColor
                        border.color: searchInput.activeFocus ? Theme.primary : Theme.outlineVariant
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: ""
                                color: Theme.surfaceVariantText
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                text: root.searchText
                                color: Theme.surfaceText
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 13
                                clip: true
                                focus: wallpaperWindow.visible

                                onTextChanged: {
                                    if (root.searchText !== text) root.searchText = text;
                                }

                                Keys.onEscapePressed: root.open = false
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Down) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.min(root.selectedIndex + 1, root.filteredWallpapers.length - 1);
                                        wallpapersList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Up) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0);
                                        wallpapersList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        event.accepted = true;
                                        if (root.selectedIndex >= 0)
                                            root.apply(root.filteredWallpapers[root.selectedIndex]);
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    text: "Search..."
                                    color: Theme.surfaceVariantText
                                    font: parent.font
                                    verticalAlignment: Text.AlignVCenter
                                    visible: parent.text === ""
                                }
                            }
                        }
                    }

                    ListView {
                        id: wallpapersList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.filteredWallpapers
                        currentIndex: root.selectedIndex
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: wallpaperDelegate
                            required property string modelData
                            required property int index

                            width: wallpapersList.width
                            height: 38
                            radius: 8
                            color: root.selectedIndex === index ? Theme.primary : Theme.transparentColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                Image {
                                    id: wallpaperThumb
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    source: root.thumbSource(wallpaperDelegate.modelData)
                                    sourceSize.width: 256
                                    sourceSize.height: 256
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            source = "file://" + wallpaperDelegate.modelData;
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: wallpaperDelegate.modelData.split("/").pop()
                                    color: root.selectedIndex === wallpaperDelegate.index
                                        ? Theme.primaryText : Theme.surfaceText
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    text: wallpaperDelegate.index + 1
                                    color: root.selectedIndex === wallpaperDelegate.index
                                        ? Theme.primaryText : Theme.surfaceVariantText
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = wallpaperDelegate.index
                                onClicked: root.apply(wallpaperDelegate.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "No wallpapers found\nAdd images to ~/Pictures/wallpapers/"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            visible: wallpapersList.count === 0
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 5
                            radius: 3
                            color: Theme.surfaceContainerHigh
                            visible: wallpapersList.contentHeight > wallpapersList.height
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: 5
                            y: wallpapersList.visibleArea.yPosition * wallpapersList.height
                            height: Math.max(24, wallpapersList.visibleArea.heightRatio * wallpapersList.height)
                            radius: 3
                            color: Theme.primary
                            visible: wallpapersList.contentHeight > wallpapersList.height
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Text {
                            text: "↑↓ navigate"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            text: "⏎ apply"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            text: "esc close"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            Item {
                focus: wallpaperWindow.visible
                Keys.onEscapePressed: root.open = false
            }

            onVisibleChanged: {
                if (visible) Qt.callLater(function() { searchInput.forceActiveFocus(); });
            }
        }
    }
}
