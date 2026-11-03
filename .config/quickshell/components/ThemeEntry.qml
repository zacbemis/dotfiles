import QtQuick
import qs.theme

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: ""
    signal accepted()
    function focusInput(): void { input.forceActiveFocus(); }
    implicitHeight: 38
    radius: 7
    color: Theme.panelSurface
    border.color: input.activeFocus ? Theme.focusRing : Theme.outlineVariant
    TextInput {
        id: input
        property string textRole: "label"
        Accessible.name: root.placeholder
        anchors { fill: parent; margins: 10 }
        font: Theme.labelFont
        color: Theme.surfaceText
        maximumLength: 128
        selectionColor: Theme.pickerSelectedBackground
        selectedTextColor: Theme.pickerSelectedText
        selectByMouse: true
        activeFocusOnTab: true
        clip: true
        onAccepted: root.accepted()
        ThemeText { anchors.fill: parent; visible: input.text === ""; text: root.placeholder; textRole: "body"; color: Theme.surfaceVariantText }
    }
}
