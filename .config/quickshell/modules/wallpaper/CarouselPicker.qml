// SPDX-License-Identifier: MIT
// Adapted from Dux DDash/WallpaperCarousel.qml, retained in vendor/dux/upstream.
// Preserve centered overlapping slides and index-driven navigation; replace
// shared-library caching/session writers with bounded images and our controller.
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

PickerWindow {
    id: picker
    route: "wallpaper"
    controller: WallpaperData
    title: "Wallpapers"
    query: WallpaperData.query
    onQueryChanged: WallpaperData.query = query
    selectedIndex: WallpaperData.selectedIndex
    onSelectedIndexChanged: WallpaperData.select(selectedIndex)
    itemCount: WallpaperData.filtered.length
    statusText: WallpaperData.scanning ? "Scanning…" : ""
    actionText: "apply · ←→ or wheel to browse"
    onActivated: WallpaperData.apply()
    navigationColumns: 2
    refreshable: true
    onRefreshRequested: WallpaperData.rescan()
    function resize(width, height): void { preferredWidth = width; preferredHeight = height; }
    function metrics() { return {size: dimensions(), compact: false, previewVisible: renderVisible, renderedRows: slides.count,
        scrollEnabled: viewport.scrollEnabled, scrollRemainder: viewport.remainder,
        currentSlide: slides.currentIndex, contentX: slides.contentX,
        centerError: slides.currentItem ? slides.currentItem.x - slides.contentX + slides.slideWidth / 2 - slides.width / 2 : null,
        previewSource: renderVisible && WallpaperData.selected ? Theme.fileUrl(WallpaperData.selected.path) : ""}; }
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        ScrollStepper {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            scrollEnabled: picker.renderVisible && WallpaperData.filtered.length > 1 && !WallpaperData.scanning
            onStepped: steps => WallpaperData.select(WallpaperData.selectedIndex + steps)
            ListView {
                id: slides
                anchors.fill: parent
                orientation: ListView.Horizontal
                readonly property real slideWidth: Math.min(340, width * 0.62)
                spacing: -slideWidth * 0.16
                model: picker.renderVisible ? WallpaperData.filtered : []
                currentIndex: picker.selectedIndex
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - slideWidth) / 2
                preferredHighlightEnd: preferredHighlightBegin + slideWidth
                highlightMoveDuration: Theme.motionEnabled ? 220 : 0
                interactive: false
                keyNavigationEnabled: false
                clip: true
                cacheBuffer: slideWidth * 2
                delegate: Item {
                    id: slide
                    required property var modelData
                    required property int index
                    readonly property real offset: (x - slides.contentX + width / 2 - slides.width / 2) / Math.max(1, slides.slideWidth + slides.spacing)
                    readonly property real distance: Math.min(1, Math.abs(offset))
                    width: slides.slideWidth
                    height: slides.height
                    scale: 1 - 0.15 * distance
                    z: -Math.abs(offset)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: Math.min(parent.height - 16, parent.width * 0.65)
                        radius: 12
                        color: Theme.panelSurface
                        border.width: picker.selectedIndex === slide.index ? 3 : 1
                        border.color: picker.selectedIndex === slide.index ? Theme.focusRing : Theme.outlineVariant
                        clip: true
                        Image {
                            id: image
                            anchors.fill: parent
                            anchors.margins: 4
                            source: Theme.fileUrl(slide.modelData.path)
                            opacity: 1 - 0.45 * slide.distance
                            sourceSize { width: 800; height: 520 }
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        ThemeText { anchors.centerIn: parent; text: image.status === Image.Error ? "Preview unavailable" : "…"; textRole: "body"; visible: image.status !== Image.Ready }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperData.select(slide.index)
                            onDoubleClicked: { WallpaperData.select(slide.index); WallpaperData.apply(); }
                        }
                    }
                }
                ThemeText { anchors.centerIn: parent; text: "No wallpapers found"; textRole: "label"; visible: slides.count === 0; color: Theme.surfaceVariantText }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ThemeText {
                Layout.fillWidth: true
                text: WallpaperData.errorMessage || (WallpaperData.selected ? WallpaperData.selected.name.replace(/[\r\n]+/g, " ↵ ") : "")
                textRole: WallpaperData.errorMessage ? "body" : "display"
                color: WallpaperData.errorMessage ? Theme.error : Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }
            ThemeButton { text: WallpaperData.busy ? "Setting…" : "Set wallpaper"; enabled: !!WallpaperData.selected && !WallpaperData.busy && !WallpaperData.scanning; onClicked: WallpaperData.apply() }
        }
    }
}
