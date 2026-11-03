// SPDX-License-Identifier: MIT
// Port of Dux LauncherTile's icon-tile/pin interaction; backend and host replaced.
// Source: vendor/dux/upstream/quickshell/Modals/DLauncherV2/Components/LauncherTile.qml.
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
    Connections { target: LauncherData; function onFocusRequested() { picker.focusSearch(); } }
    title: ""
    placeholder: LauncherData.mode === "run" ? "Command" : LauncherData.mode === "files" ? "Path"
        : LauncherData.mode === "calc" ? "Calculate" : LauncherData.mode === "web" ? "Search the web"
        : LauncherData.mode === "emoji" ? "Search emoji" : "Search apps"
    itemCount: LauncherData.rows.length
    statusText: LauncherData.fileError
    query: LauncherData.query
    onQueryChanged: LauncherData.query = query
    selectedIndex: LauncherData.selectedIndex
    onSelectedIndexChanged: LauncherData.select(selectedIndex)
    onActivated: LauncherData.activate(selectedIndex)
    navigationColumns: Math.max(1, Math.floor(grid.width / 116))
    // Read on demand: hidden GridView model changes can defer count notification.
    function renderedCount(): int { return grid.count; }
    function firstRowTop(): real { const row = grid.itemAtIndex(0); return row ? row.y - grid.contentY : 0; }
    GridView {
        id: grid
        anchors.fill: parent
        cellWidth: width / picker.navigationColumns
        cellHeight: 96
        clip: true
        // Reset the model across query modes so pending grid delegates cannot
        // retain stale indices when a compact result set resizes the card.
        model: picker.renderVisible ? LauncherData.rows : []
        currentIndex: picker.selectedIndex
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ThemeScrollBar {}
        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            readonly property bool selected: picker.selectedIndex === index
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 12
                color: tile.selected ? Theme.pickerSelectedBackground : mouse.containsMouse ? Theme.panelSurface : Theme.transparentColor
                border.color: Theme.focusRing
                border.width: tile.selected ? 1 : 0
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Image {
                            id: image
                            anchors.fill: parent
                            source: tile.modelData.icon ? Quickshell.iconPath(tile.modelData.icon, true) : ""
                            sourceSize { width: 40; height: 40 }
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }
                        GlyphIcon { anchors.centerIn: parent; glyph: "󰀻"; size: 40; color: tile.selected ? Theme.pickerSelectedText : Theme.primaryInk; visible: image.status !== Image.Ready }
                    }
                    ThemeText {
                        Layout.fillWidth: true
                        text: tile.modelData.name
                        textRole: "display"
                        color: tile.selected ? Theme.pickerSelectedText : Theme.surfaceText
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
                GlyphIcon { anchors { top: parent.top; right: parent.right; margins: 5 } glyph: "󰐃"; size: 12; color: tile.selected ? Theme.pickerSelectedText : Theme.primaryInk; visible: LauncherData.pins.includes(tile.modelData.key) }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.RightButton) LauncherData.togglePin(tile.index);
                        else LauncherData.activate(tile.index);
                    }
                }
            }
        }
        ThemeText { anchors.centerIn: parent; text: "No results"; textRole: "label"; color: Theme.surfaceVariantText; visible: grid.count === 0 }
    }
}
