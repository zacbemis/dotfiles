import QtQuick
import qs.components
import qs.theme

Rectangle {
    id: root
    required property string category
    required property string variant
    implicitHeight: 64
    radius: 7
    color: Theme.background
    border.width: 0
    readonly property color ink: Theme.primaryInk
    Item {
        anchors { fill: parent; margins: 9 }
        Item {
            anchors.fill: parent
            visible: root.category === "bar"
            Rectangle {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 24
                radius: root.variant === "enzo" ? 8 : root.variant === "current" ? 12 : 0
                color: Theme.surfaceContainerHigh
                Repeater {
                    model: 3
                    Rectangle { required property int index; x: 8 + index * 12; y: 9; width: 8; height: 6; radius: 3; color: root.ink }
                }
                Rectangle { anchors.centerIn: parent; width: 24; height: 5; radius: 2; color: Theme.surfaceText }
                Rectangle { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } width: 22; height: 5; radius: 2; color: root.ink }
            }
        }
        Repeater {
            model: root.category === "launcher" ? (root.variant === "grid" ? 8 : 3)
                : root.category === "wallpaper" ? (root.variant === "gallery" ? 6 : root.variant === "carousel" ? 3 : 1)
                : root.category === "notifications" ? 3 : root.category === "controls" ? (root.variant === "tiles" ? 6 : 3) : 0
            Rectangle {
                required property int index
                readonly property bool grid: (root.category === "launcher" && root.variant === "grid")
                    || (root.category === "wallpaper" && root.variant === "gallery") || (root.category === "controls" && root.variant === "tiles")
                readonly property int columns: root.category === "launcher" ? 4 : 3
                readonly property bool splitPreview: root.category === "wallpaper" && root.variant === "current"
                readonly property bool carousel: root.category === "wallpaper" && root.variant === "carousel"
                width: splitPreview ? parent.width * 0.64 : carousel ? parent.width * 0.52 : grid ? (parent.width - (columns - 1) * 5) / columns : parent.width - 12
                height: splitPreview ? parent.height : carousel ? parent.height - 4 : grid ? (parent.height - 5) / 2 : (parent.height - 10) / 3
                x: splitPreview ? parent.width * 0.36 : carousel ? parent.width / 2 - width / 2 + (index - 1) * parent.width * 0.22 : grid ? (index % columns) * (width + 5) : index * (root.variant === "stacked" ? 4 : 0)
                y: splitPreview ? 0 : grid ? Math.floor(index / columns) * (height + 5) : carousel ? 2 : index * (height + 5)
                z: carousel && index === 1 ? 2 : 0
                radius: root.variant === "mm2103" ? 2 : 4
                color: carousel && index === 1 ? Theme.primary : Theme.surfaceContainerHigh
                border.color: root.ink
                border.width: carousel || (root.category === "wallpaper") ? 1 : 0
                Rectangle { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 5 } height: 3; radius: 1; color: root.ink; visible: !parent.grid && !parent.carousel && root.category !== "wallpaper" }
            }
        }
        Column {
            visible: root.category === "wallpaper" && root.variant === "current"
            width: parent.width * 0.28
            spacing: 5
            Repeater { model: 3; Rectangle { width: parent.width; height: 5; radius: 2; color: root.ink } }
        }
        Item {
            anchors.fill: parent
            visible: root.category === "osd"
            ThemeText { anchors.centerIn: parent; text: "Disabled"; textRole: "body"; font.pixelSize: 11; color: Theme.surfaceVariantText; visible: root.variant === "off" }
            Rectangle {
                anchors.centerIn: parent
                visible: root.variant !== "off"
                width: root.variant === "vertical" ? 14 : parent.width * 0.72
                height: root.variant === "vertical" ? parent.height : 10
                radius: 5
                color: Theme.sliderTrack
                Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height * 0.65 - 1; radius: 4; color: Theme.sliderFill }
            }
        }
    }
}
