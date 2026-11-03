import QtQuick
import QtQuick.Layouts

Item {
    id: rootClock
    implicitWidth: layout.implicitWidth
    implicitHeight: 30

    property string timeString: ""
    property string dateString: ""
    property bool altFormat: false

    function updateTime() {
        var date = new Date();
        rootClock.timeString = date.toLocaleTimeString(Qt.locale("en_US"), "hh:mm A");
        rootClock.dateString = date.toLocaleDateString(Qt.locale("en_US"), "ddd, MMM d");
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: rootClock.updateTime()
        Component.onCompleted: rootClock.updateTime()
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: rootClock.altFormat ? "" : ""
            color: clockMouse.containsMouse ? "#cdd6f4" : "#89dceb"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Text {
            text: rootClock.altFormat ? rootClock.dateString : rootClock.timeString
            color: clockMouse.containsMouse ? "#cdd6f4" : "#89dceb"
            font.family: "sans-serif"
            font.pixelSize: 14
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    MouseArea {
        id: clockMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rootClock.altFormat = !rootClock.altFormat
    }
}
