import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Wayland

Scope {
    id: root

    readonly property int count: NotificationService.notifications.length
    readonly property bool dnd: NotificationService.dnd
    property bool centerOpen: false

    function isFocused(screen) {
        const monitor = Hyprland.monitorFor(screen);
        return !Hyprland.focusedMonitor ||
            (monitor && monitor.name === Hyprland.focusedMonitor.name);
    }

    function toggleCenter(): void {
        root.centerOpen = !root.centerOpen;
    }

    function toggleDnd(): void {
        NotificationService.toggleDnd();
    }

    function dismissAll(): void {
        NotificationService.dismissAll();
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleCenter(); }
        function clear(): void { root.dismissAll(); }
        function dnd_toggle(): void { root.toggleDnd(); }
    }

    // Floating notification popups. SwayNC is positioned at the left/top in
    // the current setup, so these intentionally use the same corner.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popupWindow
            required property var modelData

            screen: modelData
            visible: !root.centerOpen && root.isFocused(modelData) && popupModel.values.length > 0
            focusable: false
            color: Theme.transparentColor
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell-dev-notification-popups"

            anchors {
                top: true
                left: true
            }
            margins {
                top: 16
                left: 16
            }

            implicitWidth: 400
            implicitHeight: popupColumn.implicitHeight

            ScriptModel {
                id: popupModel
                values: NotificationService.popups.filter(function(record) {
                    return record.popupVisible;
                })
                objectProp: "sequence"
            }

            Column {
                id: popupColumn
                width: 400
                spacing: 8

                Repeater {
                    model: popupModel

                    NotificationCard {
                        required property var modelData
                        width: popupColumn.width
                        record: modelData
                        centerCard: false
                    }
                }
            }
        }
    }

    // SwayNC's left/top control center. It is a full-screen transparent layer
    // only while open so clicking outside the panel closes it.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: centerWindow
            required property var modelData

            screen: modelData
            visible: root.centerOpen && root.isFocused(modelData)
            focusable: true
            color: Theme.transparentColor
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell-dev-control-center"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.centerOpen = false
            }

            Rectangle {
                id: centerPanel
                x: 18
                y: 18
                width: 350
                height: 700
                radius: 10
                color: Theme.backgroundAlpha
                border.color: Theme.secondary
                border.width: 1
                z: 2

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true; }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        height: 2
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 10
                        color: Theme.inversePrimary

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: SystemState.updateCount > 0 ? "" : ""
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                            }

                            Text {
                                Layout.fillWidth: true
                                text: SystemState.updateCount > 0
                                    ? SystemState.updateCount + " updates available"
                                    : "System up to date"
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                            }

                            Text {
                                text: "󰑐"
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemState.runUpdates()
                        }
                    }

                    Rectangle {
                        id: mediaCard
                        Layout.fillWidth: true
                        height: 42
                        radius: 10
                        color: Theme.inversePrimary
                        visible: activePlayer !== null

                        property var activePlayer: {
                            const players = Mpris.players.values;
                            if (!players || players.length === 0) return null;
                            for (const player of players) {
                                if (player.isPlaying) return player;
                            }
                            return players[0];
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: "󰎆"
                                color: Theme.tertiary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 16
                            }

                            Text {
                                Layout.fillWidth: true
                                text: mediaCard.activePlayer
                                    ? mediaCard.activePlayer.trackTitle : ""
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const player = mediaCard.activePlayer;
                                if (player && player.canTogglePlaying) player.togglePlaying();
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 10
                        color: Theme.transparentColor

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Text {
                                Layout.fillWidth: true
                                text: "Do not disturb"
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 12
                            }

                            Rectangle {
                                id: dndSwitch
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 26
                                radius: 8
                                color: NotificationService.dnd ? Theme.secondary : Theme.inversePrimary

                                Rectangle {
                                    id: dndKnob
                                    width: 20
                                    height: 20
                                    radius: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: NotificationService.dnd ? parent.width - width - 3 : 3
                                    color: Theme.primary

                                    Behavior on x {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDnd()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: Theme.primary
                            font.family: Theme.iconFontFamily
                            font.bold: true
                            font.pixelSize: 16
                        }

                        Rectangle {
                            width: 30
                            height: 28
                            radius: 8
                            color: clearMouse.containsMouse ? Theme.secondary : Theme.inversePrimary

                            Text {
                                anchors.centerIn: parent
                                text: "󰎟"
                                color: Theme.primary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 15
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dismissAll()
                            }
                        }
                    }

                    ListView {
                        id: notificationList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel {
                            values: NotificationService.notifications
                            objectProp: "sequence"
                        }

                        delegate: NotificationCard {
                            required property var modelData
                            width: notificationList.width
                            record: modelData
                            centerCard: true
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "No notifications"
                            color: Theme.primary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                            visible: notificationList.count === 0
                        }
                    }
                }
            }

            Item {
                focus: centerWindow.visible
                Keys.onEscapePressed: root.centerOpen = false
            }
        }
    }
}
