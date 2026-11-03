import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Item {
    id: workspacesRoot
    implicitWidth: workspacesLayout.implicitWidth
    implicitHeight: workspacesLayout.implicitHeight

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        
        onWheel: (wheel) => {
            var currentId = Hyprland.focusedWorkspace?.id;
            if (currentId !== undefined) {
                var target = currentId;
                if (wheel.angleDelta.y > 0) {
                    // Scroll up: switch to previous workspace (e.g. 2 -> 1, or 1 -> 5)
                    target = currentId - 1;
                    if (target < 1) target = 5;
                } else if (wheel.angleDelta.y < 0) {
                    // Scroll down: switch to next workspace (e.g. 4 -> 5, or 5 -> 1)
                    target = currentId + 1;
                    if (target > 5) target = 1;
                }
                Hyprland.dispatch("workspace " + target);
            }
        }
    }

    RowLayout {
        id: workspacesLayout
        anchors.fill: parent
        spacing: 8
        
        Repeater {
            model: 5

            Rectangle {
                property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
                property bool isOccupied: ws !== undefined

                implicitWidth: isActive ? 28 : 10
                implicitHeight: 10
                
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                
                // Slick scale transform on hover for premium feeling
                scale: wsMouse.containsMouse ? 1.15 : 1.0

                color: {
                    if (wsMouse.containsMouse) return "#cdd6f4"
                    if (isActive) return "#89b4fa"
                    if (isOccupied) return "#a6adc8"
                    return "#45475a" 
                }

                Behavior on implicitWidth { 
                    NumberAnimation { duration: 300; easing.type: Easing.OutExpo } 
                }
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on color { 
                    ColorAnimation { duration: 200 } 
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + (index + 1))
                }
            }
        }
    }
}
