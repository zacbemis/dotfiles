// MM-2103 multi-mode list adaptation (MIT); upstream launcher source/license in
// vendor/mm2103/upstream/. The current variant preserves our original app list.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme

PickerWindow {
    id: picker
    route: "launcher"
    controller: LauncherData
    modeChoices: LauncherData.modeChoices
    activeMode: LauncherData.mode
    wrapNavigation: true
    onModeChosen: mode => LauncherData.setMode(mode)
    readonly property bool mm: FeatureSettings.launcher === "mm2103"
    cardRadius: mm ? 6 : 14
    title: ""
    placeholder: LauncherData.mode === "run" ? "Command" : LauncherData.mode === "files" ? "Path"
        : LauncherData.mode === "calc" ? "Calculate" : LauncherData.mode === "web" ? "Search the web"
        : LauncherData.mode === "emoji" ? "Search emoji" : "Search apps"
    statusText: LauncherData.fileError
    actionText: ["apps", "files"].includes(LauncherData.mode) ? "open" : LauncherData.mode === "run" ? "run" : LauncherData.mode === "web" ? "search web" : "copy"
    itemCount: LauncherData.rows.length
    query: LauncherData.query
    onQueryChanged: LauncherData.query = query
    selectedIndex: LauncherData.selectedIndex
    onSelectedIndexChanged: LauncherData.select(selectedIndex)
    onActivated: LauncherData.activate(selectedIndex)
    function renderedCount(): int { return results.count; }
    function firstRowTop(): real { const row = results.itemAtIndex(0); return row ? row.y - results.contentY : 0; }
    Connections {
        target: LauncherData
        function onRowsChanged() { Qt.callLater(() => results.syncPosition()); }
        function onFocusRequested() { picker.focusSearch(); }
    }
    ListView {
        id: results
        anchors.fill: parent
        // Reset the virtualized list on query-mode changes. Diffing app and
        // calculator/emoji rows together can retain a negative Qt view origin.
        model: picker.renderVisible ? LauncherData.rows : []
        currentIndex: picker.selectedIndex
        function syncPosition(): void {
            if (!picker.renderVisible || currentIndex < 0) return;
            forceLayout();
            if (currentIndex === 0) positionViewAtBeginning();
            else positionViewAtIndex(currentIndex, ListView.Contain);
        }
        onCurrentIndexChanged: Qt.callLater(syncPosition)
        onCountChanged: Qt.callLater(syncPosition)
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThemeScrollBar {}
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: picker.selectedIndex === index
            width: results.width - 10
            height: LauncherData.mode === "files" ? 48 : 42
            radius: picker.mm ? 4 : 8
            color: picker.mm ? (selected ? Theme.surfaceContainerHigh : Theme.transparentColor) : selected ? Theme.pickerSelectedBackground : Theme.transparentColor
            readonly property color foreground: picker.mm ? Theme.foregroundFor(Qt.tint(Theme.background, color), Theme.surfaceText) : selected ? Theme.pickerSelectedText : Theme.surfaceText
            Rectangle { visible: picker.mm && row.selected; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 4 } width: 2; radius: 1; color: Theme.focusRing }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10
                Item {
                    Layout.preferredWidth: picker.mm ? 32 : Theme.launcherIconSize
                    Layout.preferredHeight: picker.mm ? 32 : Theme.launcherIconSize
                    Image {
                        id: icon
                        anchors.fill: parent
                        source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                        sourceSize { width: picker.mm ? 32 : Theme.launcherIconSize; height: picker.mm ? 32 : Theme.launcherIconSize }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    GlyphIcon {
                        anchors.centerIn: parent
                        size: Theme.launcherIconSize
                        glyph: "󰀻"
                        font.family: Theme.iconFontFamily
                        color: picker.mm ? row.foreground : row.selected ? Theme.pickerSelectedText : Theme.primaryInk
                        visible: icon.status !== Image.Ready && row.modelData.kind !== "emoji"
                    }
                    Text { property string textRole: "emoji"; anchors.centerIn: parent; text: row.modelData.kind === "emoji" ? row.modelData.value : ""; visible: row.modelData.kind === "emoji"; font.pixelSize: 28 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    ThemeText { Layout.fillWidth: true; textRole: "display"; text: row.modelData.name; color: row.foreground; font.pixelSize: picker.mm ? 13 : 14; elide: Text.ElideRight }
                    ThemeText {
                        Layout.fillWidth: true
                        text: row.modelData.detail
                        textRole: "body"
                        visible: LauncherData.mode === "files" && text !== "" && text !== row.modelData.name
                        color: picker.mm || !row.selected ? Theme.surfaceVariantText : Theme.pickerSelectedText
                        font.pixelSize: picker.mm ? 11 : 10
                        elide: Text.ElideRight
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: event => {
                    const moved = LauncherData.pointerMoved(row.mapToItem(picker.host.contentItem, event.x, event.y));
                    if (moved && containsMouse && picker.surfaceScale === 1 && picker.surfaceOpacity === 1) picker.select(row.index);
                }
                onClicked: LauncherData.activate(row.index)
            }
        }
        ThemeText { anchors.centerIn: parent; text: LauncherData.mode === "calc" ? "Enter a numeric expression" : "No results"; textRole: LauncherData.mode === "calc" ? "body" : "label"; color: Theme.surfaceVariantText; visible: results.count === 0 }
    }
}
