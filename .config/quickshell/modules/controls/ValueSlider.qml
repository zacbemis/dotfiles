// SPDX-License-Identifier: MIT
// Volume/brightness row adapted from MM-2103 controlcenter/SlidersBlock.qml.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.theme

RowLayout {
    id: root
    property string title: ""
    property string accessibleLabel: title
    property real value: 0
    signal adjusted(real value)
    spacing: 10
    onValueChanged: if (!slider.pressed) slider.value = value
    ThemeText { visible: root.title !== ""; text: root.title; textRole: "label"; font.pixelSize: 11; Layout.preferredWidth: 68 }
    Slider {
        id: slider
        Accessible.name: root.accessibleLabel
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 1
        value: root.value
        onMoved: root.adjusted(value)
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 7
            radius: 3
            color: Theme.sliderTrack
            // Keep a track-colored rim: the fill must contrast with the track,
            // while the rim identifies the control against the panel itself.
            Rectangle { x: 1; y: 1; width: slider.visualPosition * (parent.width - 2); height: parent.height - 2; radius: 2; color: Theme.sliderFill }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14; height: 18; radius: 6
            color: Theme.sliderFill
            border.width: slider.activeFocus ? 2 : 1
            border.color: slider.activeFocus ? Theme.focusRing : Theme.sliderTrack
        }
    }
    ThemeText { textRole: "display"; text: Math.round(root.value) + "%"; font.pixelSize: 11; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
}
