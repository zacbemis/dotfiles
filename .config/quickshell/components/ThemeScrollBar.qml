import QtQuick
import QtQuick.Controls
import qs.theme

ScrollBar {
    id: root
    implicitWidth: 5
    minimumSize: 0.05
    contentItem: Rectangle {
        implicitWidth: 5
        implicitHeight: 24
        radius: 3
        color: Theme.primary
    }
    background: Rectangle {
        radius: 3
        color: Theme.surfaceContainer
        visible: root.size < 1
    }
    visible: size < 1
}
