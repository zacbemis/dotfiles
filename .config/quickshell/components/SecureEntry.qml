import QtQuick
import qs.theme

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: "Password"
    property bool numeric: false
    // The text audit must never traverse a password/PIN field or its children.
    readonly property bool sensitive: true
    signal accepted()
    function focusInput(): void { input.forceActiveFocus(); }
    implicitHeight: 38
    radius: 7
    color: Theme.panelSurface
    border.color: input.activeFocus ? Theme.focusRing : Theme.outlineVariant
    TextInput {
        id: input
        property string textRole: "label"
        readonly property bool sensitive: true
        Accessible.name: root.placeholder
        anchors { fill: parent; margins: 10 }
        font: Theme.labelFont
        color: Theme.surfaceText
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | (root.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone)
        maximumLength: root.numeric ? 6 : 128
        selectionColor: Theme.pickerSelectedBackground
        selectedTextColor: Theme.pickerSelectedText
        selectByMouse: true
        activeFocusOnTab: true
        clip: true
        onAccepted: root.accepted()
        ThemeText { anchors.fill: parent; visible: input.text === ""; text: root.placeholder; textRole: "body"; color: Theme.surfaceVariantText }
    }
}
