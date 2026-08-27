import Quickshell
import QtQuick

// Development-only shell. It intentionally does not start a notification
// server, launcher, or any other component that conflicts with the existing
// Waybar, SwayNC, and Rofi setup.

Variants {
    model: Quickshell.screens

    PanelWindow {
        required property var modelData

        screen: modelData
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 36

        Rectangle {
            anchors.fill: parent
            color: "#1e1e2e"
            border.color: "#89b4fa"
            border.width: 1

            Text {
                anchors.centerIn: parent
                color: "#cdd6f4"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                text: "Quickshell dev"
            }
        }
    }
}
