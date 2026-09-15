import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Scope {
    id: root

    property var notificationUi: null

    readonly property var currentMonitor: Hyprland.focusedMonitor

    function isFocused(screen) {
        const monitor = Hyprland.monitorFor(screen);
        return !Hyprland.focusedMonitor ||
            (monitor && monitor.name === Hyprland.focusedMonitor.name);
    }

    function appIcon(toplevel) {
        const appId = toplevel && toplevel.wayland ? toplevel.wayland.appId : "";
        return appId ? Quickshell.iconPath(appId, true) : "";
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData

            screen: modelData
            color: Theme.transparentColor
            aboveWindows: true
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 30

            anchors {
                top: true
                left: true
                right: true
            }
            margins.top: 8
            implicitHeight: 30

            Item {
                id: barContent
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Row {
                    id: leftModules
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Same Arch notification glyph used by the current
                    // custom/notification Waybar module.
                    Rectangle {
                        id: notificationPill
                        implicitWidth: notificationText.implicitWidth + 30
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Text {
                            id: notificationText
                            anchors.centerIn: parent
                            text: ""
                            color: {
                                if (!root.notificationUi) return "#ffffff";
                                if (root.notificationUi.dnd) return Theme.error;
                                if (root.notificationUi.count > 0) return Theme.tertiary;
                                return "#ffffff";
                            }
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 15
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                // Keep SwayNC as the live notification UI until
                                // Quickshell notifications are explicitly enabled.
                                if (!root.notificationUi) {
                                    Quickshell.execDetached([
                                        "swaync-client",
                                        mouse.button === Qt.RightButton ? "-d" : "-t",
                                        "-sw"
                                    ]);
                                    return;
                                }
                                if (mouse.button === Qt.RightButton)
                                    root.notificationUi.toggleDnd();
                                else
                                    root.notificationUi.toggleCenter();
                            }
                        }
                    }

                    Rectangle {
                        id: workspacePill
                        implicitWidth: workspaceRow.implicitWidth + 12
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Row {
                            id: workspaceRow
                            anchors.centerIn: parent
                            spacing: 3

                            Repeater {
                                model: Hyprland.workspaces

                                Rectangle {
                                    id: workspaceButton
                                    required property var modelData

                                    implicitWidth: Math.max(modelData.focused ? 40 : 26,
                                        workspaceInner.implicitWidth + 12)
                                    implicitHeight: 20
                                    radius: 10
                                    color: modelData.focused ? Theme.secondary
                                         : modelData.urgent ? Theme.error
                                         : workspaceMouse.containsMouse ? Theme.primaryContainer
                                         : Theme.background

                                    Behavior on implicitWidth {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    Row {
                                        id: workspaceInner
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: workspaceButton.modelData.name || workspaceButton.modelData.id
                                            color: workspaceButton.modelData.focused ? Theme.secondaryText
                                                   : workspaceButton.modelData.urgent ? Theme.errorText
                                                   : Theme.surfaceText
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: 11
                                            font.bold: workspaceButton.modelData.focused
                                        }

                                        Repeater {
                                            model: workspaceButton.modelData.toplevels

                                            Item {
                                                id: toplevelIcon
                                                required property var modelData
                                                width: 15
                                                height: 15

                                                Image {
                                                    id: toplevelImage
                                                    anchors.fill: parent
                                                    source: root.appIcon(toplevelIcon.modelData)
                                                    sourceSize.width: 15
                                                    sourceSize.height: 15
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: source !== ""
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ""
                                                    color: workspaceButton.modelData.focused
                                                        ? Theme.secondaryText : Theme.surfaceVariantText
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: 11
                                                    visible: toplevelImage.source === ""
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: workspaceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: workspaceButton.modelData.activate()
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: clockPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: clockText.implicitWidth + 30
                    implicitHeight: 30
                    radius: 15
                    color: Theme.background
                    border.color: Theme.outlineVariant
                    border.width: 1

                    SystemClock {
                        id: clock
                        precision: SystemClock.Minutes
                    }

                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        // Match Waybar `{:%I:%M %p}` (12-hour, zero-padded).
                        text: Qt.locale("en_US").toString(clock.date, "hh:mm AP")
                        color: Theme.inversePrimary
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: 15
                    }

                    Rectangle {
                        id: clockTooltip
                        anchors.top: parent.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: clockTooltipText.implicitWidth + 16
                        height: clockTooltipText.implicitHeight + 10
                        radius: 6
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1
                        visible: clockMouse.containsMouse
                        z: 20

                        Text {
                            id: clockTooltipText
                            anchors.centerIn: parent
                            text: Qt.formatDateTime(clock.date, "MM-dd-yyyy")
                            color: Theme.surfaceText
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: clockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                Row {
                    id: rightModules
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        id: trayPill
                        visible: SystemTray.items.values.length > 0
                        implicitWidth: trayRow.implicitWidth + 20
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Row {
                            id: trayRow
                            anchors.centerIn: parent
                            spacing: 6

                            Repeater {
                                model: SystemTray.items

                                MouseArea {
                                    id: trayItem
                                    required property var modelData
                                    width: 16
                                    height: 20
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor

                                    IconImage {
                                        anchors.centerIn: parent
                                        source: trayItem.modelData.icon
                                        implicitSize: 15
                                    }

                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.LeftButton)
                                            trayItem.modelData.activate();
                                        else if (mouse.button === Qt.MiddleButton)
                                            trayItem.modelData.secondaryActivate();
                                        else
                                            trayItem.modelData.display(barWindow, trayItem.x, trayItem.y + trayItem.height);
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: brightnessPill
                        visible: SystemState.brightnessAvailable
                        implicitWidth: brightnessText.implicitWidth + 30
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Text {
                            id: brightnessText
                            anchors.centerIn: parent
                            text: SystemState.brightnessPercent + "% " + SystemState.brightnessIcon
                            color: Theme.secondary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: function(wheel) {
                                SystemState.adjustBrightness(wheel.angleDelta.y);
                            }
                        }
                    }

                    Rectangle {
                        id: volumePill
                        implicitWidth: volumeText.implicitWidth + 30
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Text {
                            id: volumeText
                            anchors.centerIn: parent
                            text: SystemState.volumePercent + "% " + SystemState.volumeIcon
                            color: Theme.tertiary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemState.toggleMute()
                            onWheel: function(wheel) {
                                SystemState.adjustVolume(wheel.angleDelta.y > 0 ? 0.02 : -0.02);
                            }
                        }
                    }

                    Rectangle {
                        id: batteryPill
                        implicitWidth: batteryText.implicitWidth + 30
                        implicitHeight: 30
                        radius: 15
                        color: Theme.background
                        border.color: Theme.outlineVariant
                        border.width: 1

                        Text {
                            id: batteryText
                            anchors.centerIn: parent
                            text: SystemState.batteryPercent + "% " + SystemState.batteryIcon
                            color: SystemState.batteryPercent <= 20 ? Theme.error
                                   : SystemState.batteryPercent <= 40 ? SystemState.batteryWarning
                                   : Theme.primary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
