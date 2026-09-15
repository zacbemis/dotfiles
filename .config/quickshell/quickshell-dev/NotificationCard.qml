import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

Rectangle {
    id: root

    required property var record
    property bool centerCard: false

    implicitHeight: cardContent.implicitHeight + 24
    radius: 10
    color: root.centerCard ? Theme.inversePrimary : Theme.backgroundAlpha
    border.color: root.record.urgency === NotificationUrgency.Critical
                  ? Theme.error : Theme.secondary
    border.width: root.record.urgency === NotificationUrgency.Critical ? 2 : 1
    clip: true

    function iconSource(icon) {
        if (!icon) return "";
        if (icon.startsWith("file://") || icon.startsWith("image://")) return icon;
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, true);
    }

    HoverHandler {
        onHoveredChanged: root.record.hovered = hovered
    }

    Timer {
        id: popupTimer
        interval: root.record.timeoutMs
        running: !root.centerCard && root.record.popupVisible && !root.record.hovered
        onTriggered: root.record.popupVisible = false
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        onClicked: root.record.invokeDefaultAction()
    }

    ColumnLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20

                Image {
                    anchors.fill: parent
                    source: root.iconSource(root.record.appIcon)
                    sourceSize.width: 20
                    sourceSize.height: 20
                    fillMode: Image.PreserveAspectFit
                    visible: source !== ""
                }

                Text {
                    anchors.centerIn: parent
                    text: root.record.urgency === NotificationUrgency.Critical ? "󰀦" : "󰂚"
                    color: root.record.urgency === NotificationUrgency.Critical ? Theme.error : Theme.tertiary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 16
                    visible: root.record.appIcon === ""
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.record.appName || "Notification"
                color: Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 6
                color: closeMouse.containsMouse ? Theme.secondary : Theme.transparentColor

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeMouse.containsMouse ? Theme.primaryText : Theme.primary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.record.dismiss()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.record.summary
            color: Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 14
            font.bold: true
            wrapMode: Text.Wrap
            visible: text !== ""
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.record.body !== "" || root.record.image !== ""

            Text {
                Layout.fillWidth: true
                text: root.record.body
                color: Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: 12
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: root.centerCard ? 5 : 3
                elide: Text.ElideRight
                visible: text !== ""
            }

            Image {
                Layout.preferredWidth: root.centerCard ? 100 : 80
                Layout.preferredHeight: root.centerCard ? 80 : 64
                source: root.record.image
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: source !== ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.record.actions.length > 0

            Repeater {
                model: root.record.actions

                Rectangle {
                    id: actionButton
                    required property var modelData
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: actionLabel.implicitWidth + 20
                    radius: 8
                    color: actionMouse.containsMouse ? Theme.tertiary
                                                     : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.6)

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: actionButton.modelData.text || ""
                        color: actionMouse.containsMouse ? Theme.tertiaryText : Theme.primary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.record.invokeAction(actionButton.modelData)
                    }
                }
            }
        }
    }
}
