import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme

Item {
    id: root
    readonly property real contentHeight: content.implicitHeight
    property bool applicationsVisible: false
    Component.onCompleted: { AudioService.viewers++; AudioService.ensure(); }
    Component.onDestruction: AudioService.viewers = Math.max(0, AudioService.viewers - 1)
    function presentation() { return {applicationsVisible: applicationsVisible, output: AudioService.output, input: AudioService.input, applications: AudioService.applications}; }
    function activate(target): bool {
        if (target === "applications") { applicationsVisible = !applicationsVisible; return true; }
        const split = target.indexOf(":");
        if (target.startsWith("profile:")) {
            const parts = target.slice(8).split(":");
            return parts.length === 2 && AudioService.profile(parts[0], parts[1]);
        }
        if (target.startsWith("mute:") || target.startsWith("volume:")) {
            const parts = target.split(":"), kind = parts[1];
            const state = AudioService.control(kind, kind === "application" ? parts[2] : "");
            return parts[0] === "mute" ? AudioService.toggleMuted(kind, state.id, state.key)
                : AudioService.setVolume(kind, state.id, state.key, Number(parts[kind === "application" ? 3 : 2]));
        }
        return AudioService.choose(target.slice(0, split), target.slice(split + 1));
    }
    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical: ThemeScrollBar {}
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 10
            ThemeText { Layout.fillWidth: true; visible: text !== ""; text: AudioService.error; textRole: "body"; color: Theme.error; wrapMode: Text.Wrap }
            Repeater {
                model: ["output", "input"]
                ColumnLayout {
                    id: section
                    required property string modelData
                    readonly property var reading: AudioService.control(modelData, "")
                    readonly property var devices: modelData === "output" ? AudioService.outputs : AudioService.inputs
                    property bool expanded: false
                    Layout.fillWidth: true
                    spacing: 4
                    AudioLevel { Layout.fillWidth: true; kind: section.modelData; title: kind === "output" ? "Sound" : "Microphone"; reading: section.reading }
                    ControlListItem {
                        Layout.fillWidth: true
                        text: section.reading.name || "No devices"
                        selected: section.expanded
                        enabled: section.devices.length > 0
                        onClicked: section.expanded = !section.expanded
                    }
                    Repeater {
                        model: section.expanded ? section.devices : []
                        ControlListItem {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name
                            tooltip: modelData.name
                            marked: modelData.selected
                            expandable: false
                            enabled: !AudioService.readOnly
                            onClicked: if (AudioService.choose(section.modelData, modelData.id)) section.expanded = false
                        }
                    }
                }
            }
            ControlListItem {
                Layout.fillWidth: true
                text: "Applications"
                selected: root.applicationsVisible
                onClicked: root.applicationsVisible = !root.applicationsVisible
            }
            ColumnLayout {
                visible: root.applicationsVisible
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    // Stable serial keys preserve pointer grabs while volumes update.
                    model: ScriptModel { values: AudioService.applications; objectProp: "key" }
                    AudioLevel {
                        required property var modelData
                        Layout.fillWidth: true
                        kind: "application"
                        title: modelData.name
                        reading: modelData
                    }
                }
                ThemeText { Layout.fillWidth: true; visible: AudioService.applications.length === 0; text: "No applications playing audio"; textRole: "body"; color: Theme.surfaceVariantText; wrapMode: Text.Wrap }
            }
            Repeater {
                model: AudioService.cards
                ColumnLayout {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4
                    ThemeText { Layout.fillWidth: true; text: card.modelData.name; textRole: "title"; font.pixelSize: 14; elide: Text.ElideRight }
                    Repeater {
                        model: card.modelData.profiles
                        ControlListItem {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name
                            tooltip: modelData.description || modelData.name
                            marked: modelData.selected
                            expandable: false
                            enabled: !AudioService.readOnly && !AudioService.busy
                            onClicked: AudioService.profile(card.modelData.id, modelData.id)
                        }
                    }
                }
            }
        }
    }
}
