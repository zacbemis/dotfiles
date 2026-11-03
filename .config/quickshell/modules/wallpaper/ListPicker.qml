import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.services
import qs.theme

Scope {
    id: root

    readonly property var filtered: WallpaperData.filtered
    readonly property var selected: WallpaperData.selected
    readonly property string errorMessage: WallpaperData.errorMessage
    readonly property string wallpaperDirectory: WallpaperData.directory
    function rescan(): void { WallpaperData.rescan(); }
    function apply(): void { WallpaperData.apply(); }
    function resize(width, height): void { picker.preferredWidth = width; picker.preferredHeight = height; }
    function typography() { return picker.typography(); }
    function metrics() {
        return {size: picker.dimensions(), compact: contentLayout.columns === 1, previewVisible: previewCard.visible,
            renderedRows: results.count, previewSource: String(preview.source)};
    }

    PickerWindow {
        id: picker
        route: "wallpaper"
        controller: WallpaperData
        query: WallpaperData.query
        onQueryChanged: WallpaperData.query = query
        selectedIndex: WallpaperData.selectedIndex
        onSelectedIndexChanged: WallpaperData.select(selectedIndex)
        title: "Wallpapers"
        itemCount: root.filtered.length
        actionText: "apply"
        statusText: WallpaperData.scanning ? "Scanning…" : ""
        refreshable: true
        onRefreshRequested: root.rescan()
        onActivated: root.apply()
        onRenderVisibleChanged: {
            if (renderVisible) root.rescan();
            Qt.callLater(() => results.positionViewAtIndex(picker.selectedIndex, ListView.Contain));
        }

        GridLayout {
            id: contentLayout
            anchors.fill: parent
            columns: width < 520 ? 1 : 2
            rowSpacing: 12
            columnSpacing: 16

            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 330
                Layout.preferredHeight: contentLayout.columns === 1 ? 150 : 300
                // Keep data/IPC alive, but release thumbnail delegates when the
                // exit animation finishes. Hidden pickers should not decode images.
                model: picker.renderVisible ? root.filtered : []
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
                                textRole: thumbnail.status === Image.Error ? "icon" : "body"
                                color: Theme.surfaceVariantText
                                visible: thumbnail.status !== Image.Ready
                            }
                        }
                        ThemeText {
                            Layout.fillWidth: true
                            text: wallpaperRow.modelData.name
                            textRole: "display"
                            color: wallpaperRow.selected || mouse.containsMouse ? Theme.pickerSelectedText : Theme.surfaceText
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                        GlyphIcon {
                            glyph: ""
                            visible: wallpaperRow.modelData.current
                            color: wallpaperRow.selected || mouse.containsMouse ? Theme.pickerSelectedText : Theme.primaryInk
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
                visible: contentLayout.columns > 1 || contentLayout.height > 340
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
                        source: picker.renderVisible && root.selected ? Theme.fileUrl(root.selected.path) : ""
                        sourceSize { width: 800; height: 600 }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        ThemeText {
                            anchors.centerIn: parent
                            text: WallpaperData.scanning || preview.status === Image.Loading ? "Loading…"
                                : preview.status === Image.Error ? "Preview unavailable" : "No wallpapers found"
                            visible: !root.selected || preview.status === Image.Error || preview.status === Image.Loading
                            color: Theme.surfaceVariantText
                            textRole: "body"
                        }
                    }
                }
            }
            RowLayout {
                Layout.columnSpan: contentLayout.columns
                Layout.fillWidth: true
                ThemeText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.errorMessage
                    textRole: "body"
                    color: Theme.error
                    wrapMode: Text.Wrap
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                ThemeButton {
                    text: WallpaperData.busy ? "Setting…" : "Set wallpaper"
                    pickerStyle: true
                    enabled: Boolean(root.selected) && !WallpaperData.busy && !WallpaperData.scanning
                    onClicked: root.apply()
                }
            }
        }
    }
}
