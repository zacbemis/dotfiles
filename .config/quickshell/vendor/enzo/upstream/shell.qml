//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 34
    color: "transparent"

    margins {
        top: 8
        left: 12
        right: 12
    }

    property var config: ({
        "launcherCommand": "rofi -show drun",
        "launcherIcon": "",
        "wallpaperCommand": "qs ipc call wallpaper toggle",
        "wallpaperIcon": "",
        "powerCommand": "wlogout -b 2 -c 0 -r 0 -L 930 -R 930 -T 300 -B 300 --protocol layer-shell",
        "powerIcon": ""
    })

    Process {
        command: ["cat", Qt.resolvedUrl("config.json").toString().replace("file://", "")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.config = JSON.parse(this.text.trim());
                } catch (e) {
                    console.error("Failed to parse config.json:", e);
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#D91e1e2e"
        radius: 12
        border.color: "#33cdd6f4"
        border.width: 1

        // CENTER MODULES (Absolute Center)
        Mpris {
            anchors.centerIn: parent
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 0

            // LEFT MODULES
            RowLayout {
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: 16
                
                Launcher {}
                Workspaces {}
                WindowTitle {}
            }

            Item { Layout.fillWidth: true } // Spacer to push right modules

            // RIGHT MODULES
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 16
                
                Systray {}
                Network {}
                Audio {}
                SystemStats {}
                Battery {}
                Clock {}
                Buttons {}
            }
        }
    }
}
