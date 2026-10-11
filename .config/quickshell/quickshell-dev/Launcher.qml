import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var lastPointerPosition: null
    function pointerMoved(position): bool {
        const previous = lastPointerPosition;
        lastPointerPosition = position;
        return previous !== null && (Math.abs(position.x - previous.x) > 0.25
            || Math.abs(position.y - previous.y) > 0.25);
    }

    // Read Rofi history, but keep new launcher usage in Quickshell's own state.
    FileView {
        id: drunCache
        path: (Quickshell.env("HOME") || "") + "/.cache/rofi3.druncache"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        blockLoading: true
        printErrors: false
    }
    property var localUsage: {
        try { return JSON.parse(usageFile.text() || "{}"); }
        catch (error) { return {}; }
    }
    readonly property var rofiUsage: {
        const scores = {};
        for (const line of drunCache.text().split("\n")) {
            const match = line.trim().match(/^(\d+)\s+(.+)$/);
            if (match) scores[match[2]] = Number(match[1]);
        }
        return scores;
    }

    function usageFor(entry): int {
        const id = String(entry.id || "");
        const base = id.endsWith(".desktop") ? id.slice(0, -8) : id;
        return (root.localUsage[id] || 0) + (root.rofiUsage[id] || root.rofiUsage[base] || root.rofiUsage[base + ".desktop"] || 0);
    }

    function launch(entry): void {
        if (!entry) return;
        entry.execute();
        const scores = Object.assign({}, root.localUsage);
        scores[entry.id] = (scores[entry.id] || 0) + 1;
        root.localUsage = scores;
        usageFile.setText(JSON.stringify(scores));
        UiState.close("launcher");
    }

    readonly property var apps: {
        const terms = picker.query.trim().toLowerCase().split(/\s+/).filter(Boolean);
        return [...DesktopEntries.applications.values].filter(entry => {
            if (entry.noDisplay || !entry.name) return false;
            const categories = entry.categories || [];
            if (categories.includes("X-XFCE") || categories.includes("X-Xfce-Toplevel")) return false;
            const haystack = [entry.name, entry.genericName, entry.execString,
                ...(entry.keywords || []), ...categories].join(" ").toLowerCase();
            return terms.every(term => haystack.includes(term));
        }).sort((a, b) => {
            const query = picker.query.trim().toLowerCase();
            const aStarts = query && a.name.toLowerCase().startsWith(query);
            const bStarts = query && b.name.toLowerCase().startsWith(query);
            if (aStarts !== bStarts) return aStarts ? -1 : 1;
            return root.usageFor(b) - root.usageFor(a) || a.name.localeCompare(b.name);
        });
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { UiState.toggle("launcher"); }
        function open(): void { UiState.show("launcher"); }
        function close(): void { UiState.close("launcher"); }
        function search(query: string): void { UiState.show("launcher"); picker.query = query; }
        function results(): string { return JSON.stringify(root.apps.map(entry => entry.name)); }
        function status(): string {
            return JSON.stringify({selected: picker.selectedIndex, query: picker.query,
                iconSize: Theme.launcherIconSize, selectedName: root.apps[picker.selectedIndex]
                    ? root.apps[picker.selectedIndex].name : ""});
        }
        function activate(): void { root.launch(root.apps[picker.selectedIndex]); }
    }

    PickerWindow {
        id: picker
        route: "launcher"
        title: "Applications"
        statusText: itemCount + " apps"
        actionText: "launch"
        itemCount: root.apps.length
        onActivated: root.launch(root.apps[selectedIndex])

        ListView {
            id: results
            anchors.fill: parent
            model: ScriptModel { values: root.apps; objectProp: "id" }
            currentIndex: picker.selectedIndex
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThemeScrollBar {}

            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index
                readonly property bool selected: picker.selectedIndex === index
                readonly property string icon: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                width: results.width - 10
                height: 48
                radius: 8
                color: selected ? Theme.pickerSelectedBackground : Theme.transparentColor

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    Item {
                        Layout.preferredWidth: Theme.launcherIconSize
                        Layout.preferredHeight: Theme.launcherIconSize
                        Image {
                            id: appImage
                            anchors.fill: parent
                            source: appRow.icon
                            sourceSize { width: Theme.launcherIconSize; height: Theme.launcherIconSize }
                            fillMode: Image.PreserveAspectFit
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            size: Theme.launcherIconSize
                            glyph: "󰀻"
                            font.family: Theme.iconFontFamily
                            color: appRow.selected ? Theme.primaryText : Theme.primary
                            visible: appImage.status !== Image.Ready
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        ThemeText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            color: appRow.selected ? Theme.pickerSelectedText : Theme.surfaceText
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        ThemeText {
                            Layout.fillWidth: true
                            text: appRow.modelData.genericName || ""
                            visible: text !== "" && text !== appRow.modelData.name
                            color: appRow.selected ? Theme.pickerSelectedText : Theme.surfaceVariantText
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // A pop-in changes local pointer coordinates without any real
                    // movement. Do not let that shift selection during entry.
                    onPositionChanged: mouse => {
                        const moved = root.pointerMoved(appRow.mapToItem(picker.contentItem, mouse.x, mouse.y));
                        if (moved && containsMouse && picker.surfaceScale === 1
                            && picker.surfaceOpacity === 1) picker.select(appRow.index);
                    }
                    onClicked: root.launch(appRow.modelData)
                }
            }

            ThemeText {
                anchors.centerIn: parent
                text: "No applications match your search"
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: 13
                visible: results.count === 0
            }
        }
    }
}
