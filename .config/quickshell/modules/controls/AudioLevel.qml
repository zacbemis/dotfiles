import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

ColumnLayout {
    id: root
    required property string kind
    required property string title
    required property var reading
    objectName: "audio-" + kind + "-" + reading.key
    spacing: 2
    RowLayout {
        Layout.fillWidth: true
        ThemeText { Layout.fillWidth: true; text: root.title; textRole: "label"; elide: Text.ElideRight }
        ControlButton {
            iconOnly: true
            text: root.kind === "input" ? (root.reading.muted ? "󰍭" : "󰍬") : root.reading.muted ? "󰝟" : "󰕾"
            tooltip: (root.reading.muted ? "Unmute " : "Mute ") + (root.kind === "input" ? "microphone" : root.kind === "output" ? "sound" : root.title)
            baseColor: root.reading.muted ? Theme.activeBackground : Theme.surfaceContainerHigh
            enabled: root.reading.available && !AudioService.readOnly
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.reading.muted
            onClicked: AudioService.toggleMuted(root.kind, root.reading.id, root.reading.key)
        }
    }
    ValueSlider {
        Layout.fillWidth: true
        accessibleLabel: root.title + " volume"
        value: root.reading.volume
        enabled: root.reading.available && !AudioService.readOnly
        onAdjusted: value => AudioService.setVolume(root.kind, root.reading.id, root.reading.key, value)
    }
}
