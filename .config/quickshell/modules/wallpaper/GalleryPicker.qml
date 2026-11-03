// SPDX-License-Identifier: MIT
// Adapted from MM-2103 WallpaperPickerPopup.qml (vendor/mm2103/upstream).
// Keep its lazy thumbnail gallery; use our scanner, selection and explicit Apply.
// Output/fill controls are intentionally absent: our setter accepts a path only.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme

PickerWindow {
    id: picker
    route: "wallpaper"
    controller: WallpaperData
    title: "Wallpapers"
    itemCount: WallpaperData.filtered.length
    statusText: WallpaperData.scanning ? "Scanning…" : ""
    query: WallpaperData.query
    onQueryChanged: WallpaperData.query = query
    selectedIndex: WallpaperData.selectedIndex
    onSelectedIndexChanged: WallpaperData.select(selectedIndex)
    onActivated: WallpaperData.apply()
    refreshable: true
    onRefreshRequested: WallpaperData.rescan()
    navigationColumns: Math.max(1, Math.floor(grid.width / 150))
    function resize(width, height): void { preferredWidth = width; preferredHeight = height; }
    function metrics() { return {size: dimensions(), compact: navigationColumns < 3, previewVisible: false, renderedRows: grid.count, previewSource: "", columns: navigationColumns}; }
    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: width / picker.navigationColumns
            cellHeight: cellWidth * 9 / 16 + 34
            clip: true
            model: picker.renderVisible ? WallpaperData.filtered : []
            currentIndex: picker.selectedIndex
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThemeScrollBar {}
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 8
                    color: picker.selectedIndex === cell.index ? Theme.pickerSelectedBackground : Theme.panelSurface
                    border.color: picker.selectedIndex === cell.index ? Theme.focusRing : Theme.outlineVariant
                    clip: true
                    Image {
                        id: image
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 3 }
                        height: parent.height - 28
                        source: Theme.fileUrl(cell.modelData.path)
                        sourceSize { width: 320; height: 180 }
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        ThemeText { anchors.centerIn: parent; text: image.status === Image.Error ? "Preview unavailable" : "…"; textRole: "body"; visible: image.status !== Image.Ready; font.pixelSize: 10; color: picker.selectedIndex === cell.index ? Theme.pickerSelectedText : Theme.surfaceText }
                    }
                    ThemeText {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 6 }
                        text: (cell.modelData.current ? "✓ " : "") + cell.modelData.name.replace(/[\r\n]+/g, " ↵ ")
                        textRole: "display"
                        color: picker.selectedIndex === cell.index ? Theme.pickerSelectedText : Theme.surfaceText
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperData.select(cell.index)
                        onDoubleClicked: { WallpaperData.select(cell.index); WallpaperData.apply(); }
                    }
                }
            }
            ThemeText { anchors.centerIn: parent; text: "No wallpapers found"; textRole: "label"; visible: grid.count === 0; color: Theme.surfaceVariantText }
        }
        RowLayout {
            Layout.fillWidth: true
            ThemeText {
                Layout.fillWidth: true
                text: WallpaperData.errorMessage
                visible: text !== ""
                textRole: "body"
                color: WallpaperData.errorMessage ? Theme.error : Theme.surfaceText
                elide: Text.ElideMiddle
                font.pixelSize: 12
            }
            Item { Layout.fillWidth: true }
            ThemeButton { text: WallpaperData.busy ? "Setting…" : "Set wallpaper"; enabled: !!WallpaperData.selected && !WallpaperData.busy && !WallpaperData.scanning; onClicked: WallpaperData.apply() }
        }
    }
}
