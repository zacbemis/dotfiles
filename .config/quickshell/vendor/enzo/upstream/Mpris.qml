import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: rootMpris
    implicitWidth: layout.implicitWidth
    implicitHeight: 30

    property string mprisText: ""
    property string mprisStatus: ""
    property string mprisPlayer: ""

    property string titleIcon: {
        if (rootMpris.mprisText === "") return "";
        if (rootMpris.mprisStatus === "Paused") return "󰏤";
        if (rootMpris.mprisPlayer.indexOf("spotify") !== -1) return "󰓇";
        if (rootMpris.mprisPlayer.indexOf("firefox") !== -1) return "󰈹";
        if (rootMpris.mprisPlayer.indexOf("chromium") !== -1) return "";
        return "󰎆";
    }
    
    property string titleTextContent: {
        var text = rootMpris.mprisText;
        if (text.length > 40) return text.substring(0, 37) + "...";
        return text;
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            mprisMetaProc.running = true;
            mprisStatusProc.running = true;
        }
    }

    Process {
        id: mprisMetaProc
        command: ["sh", "-c", "playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null || echo ''"]
        stdout: StdioCollector {
            id: metaOut
            onStreamFinished: rootMpris.mprisText = metaOut.text.trim();
        }
    }

    Process {
        id: mprisStatusProc
        command: ["sh", "-c", "playerctl status 2>/dev/null; playerctl -l 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                var lines = statusOut.text.trim().split("\n");
                if (lines.length > 0) rootMpris.mprisStatus = lines[0];
                if (lines.length > 1) rootMpris.mprisPlayer = lines[1].toLowerCase();
            }
        }
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: rootMpris.titleIcon
            visible: rootMpris.titleIcon !== ""
            color: mprisMouse.containsMouse ? "#f5c2e7" : "#cba6f7"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Text {
            text: rootMpris.titleTextContent
            visible: rootMpris.titleTextContent !== ""
            color: mprisMouse.containsMouse ? "#f5c2e7" : "#cba6f7"
            font.family: "sans-serif"
            font.pixelSize: 14
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    MouseArea {
        id: mprisMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mprisToggleProc.running = true
    }

    Process {
        id: mprisToggleProc
        command: ["playerctl", "play-pause"]
    }
}
