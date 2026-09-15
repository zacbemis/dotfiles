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
    property int selectedIndex: 0

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
        }
    }

    function launch(entry): void {
        if (!entry) return;
        entry.execute();
        root.open = false;
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle(); }
    }

    // Reuse Rofi's drun frequency cache so the empty list order matches.
    FileView {
        id: drunCache
        path: (Quickshell.env("HOME") || "") + "/.cache/rofi3.druncache"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }

    readonly property var usageScores: {
        const scores = {};
        const text = drunCache.text();
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line) continue;
            const space = line.indexOf(" ");
            if (space < 0) continue;
            const count = Number(line.slice(0, space));
            const id = line.slice(space + 1).trim();
            if (id) scores[id] = Number.isFinite(count) ? count : 0;
        }
        return scores;
    }

    function isHiddenDesktop(entry): bool {
        if (!entry || entry.noDisplay || !entry.name) return true;
        const cats = entry.categories || [];
        for (let i = 0; i < cats.length; ++i) {
            const cat = String(cats[i]);
            if (cat === "X-XFCE" || cat === "X-Xfce-Toplevel") return true;
        }
        return false;
    }

    function usageFor(entry): int {
        const scores = root.usageScores;
        const id = entry && entry.id ? String(entry.id) : "";
        if (!id) return 0;
        const candidates = [id];
        if (id.endsWith(".desktop"))
            candidates.push(id.slice(0, -8));
        else
            candidates.push(id + ".desktop");
        const base = id.split("/").pop();
        if (base && candidates.indexOf(base) < 0) candidates.push(base);
        for (let i = 0; i < candidates.length; ++i) {
            const score = scores[candidates[i]];
            if (score != null) return score;
        }
        return 0;
    }

    ScriptModel {
        id: filteredApps
        objectProp: "id"
        values: {
            const query = root.searchText.trim().toLowerCase();
            const apps = [...DesktopEntries.applications.values];

            return apps.filter(function(entry) {
                if (root.isHiddenDesktop(entry)) return false;
                if (query === "") return true;
                const values = [
                    entry.name || "",
                    entry.genericName || "",
                    entry.execString || "",
                    ...(entry.keywords || []),
                    ...(entry.categories || [])
                ];
                return values.some(function(value) {
                    return String(value).toLowerCase().includes(query);
                });
            }).sort(function(a, b) {
                const an = (a.name || "").toLowerCase();
                const bn = (b.name || "").toLowerCase();
                const ascore = root.usageFor(a);
                const bscore = root.usageFor(b);
                if (query !== "") {
                    const aStarts = an.startsWith(query);
                    const bStarts = bn.startsWith(query);
                    if (aStarts && !bStarts) return -1;
                    if (!aStarts && bStarts) return 1;
                }
                if (ascore !== bscore) return bscore - ascore;
                return an.localeCompare(bn);
            });
        }
    }

    onSearchTextChanged: {
        if (filteredApps.values.length === 0) root.selectedIndex = -1;
        else root.selectedIndex = 0;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: launcherWindow
            required property var modelData

            screen: modelData
            visible: root.open && root.isFocused(modelData)
            focusable: true
            color: Theme.transparentColor
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-dev-launcher"

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
                id: launcherBox
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

                    Text {
                        text: "  Applications"
                        color: Theme.surfaceText
                        font.family: Theme.iconFontFamily
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
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
                                Layout.alignment: Qt.AlignVCenter
                                text: root.searchText
                                color: Theme.surfaceText
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                clip: true
                                focus: launcherWindow.visible
                                selectByMouse: true

                                onTextChanged: {
                                    if (root.searchText !== text) root.searchText = text;
                                }

                                Keys.onEscapePressed: root.open = false
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Down) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.min(root.selectedIndex + 1, filteredApps.values.length - 1);
                                        results.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Up) {
                                        event.accepted = true;
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0);
                                        results.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        event.accepted = true;
                                        if (root.selectedIndex >= 0)
                                            root.launch(filteredApps.values[root.selectedIndex]);
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

                    Text {
                        text: results.count + " application" + (results.count === 1 ? "" : "s")
                        color: Theme.surfaceVariantText
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 10
                    }

                    ListView {
                        id: results
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: filteredApps
                        currentIndex: root.selectedIndex
                        clip: true
                        spacing: 3
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: appDelegate
                            required property var modelData
                            required property int index

                            width: results.width
                            height: 38
                            radius: 8
                            color: root.selectedIndex === index ? Theme.primary : Theme.transparentColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12

                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24

                                    Image {
                                        anchors.fill: parent
                                        source: appDelegate.modelData.icon
                                            ? Quickshell.iconPath(appDelegate.modelData.icon, true) : ""
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        fillMode: Image.PreserveAspectFit
                                        visible: source !== ""
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰀻"
                                        color: root.selectedIndex === appDelegate.index
                                            ? Theme.primaryText : Theme.primary
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 18
                                        visible: appDelegate.modelData.icon === ""
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: appDelegate.modelData.name || ""
                                    color: root.selectedIndex === appDelegate.index
                                        ? Theme.primaryText : Theme.surfaceText
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 12
                                    font.bold: root.selectedIndex === appDelegate.index
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = appDelegate.index
                                onClicked: root.launch(appDelegate.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "No applications found"
                            color: Theme.surfaceVariantText
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            visible: results.count === 0
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 5
                            radius: 3
                            color: Theme.surfaceContainerHigh
                            visible: results.contentHeight > results.height
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: 5
                            y: results.visibleArea.yPosition * results.height
                            height: Math.max(24, results.visibleArea.heightRatio * results.height)
                            radius: 3
                            color: Theme.primary
                            visible: results.contentHeight > results.height
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
                            text: "⏎ launch"
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
                focus: launcherWindow.visible
                Keys.onEscapePressed: root.open = false
            }

            onVisibleChanged: {
                if (visible) Qt.callLater(function() { searchInput.forceActiveFocus(); });
            }
        }
    }
}
