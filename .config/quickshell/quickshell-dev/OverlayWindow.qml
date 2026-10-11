import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property string route
    property bool dimBackground: true
    property bool popIn: true
    readonly property bool opened: UiState.active === route
    property real surfaceOpacity: opened ? 1 : 0
    property real surfaceScale: opened ? 1 : 0.85
    default property alias content: surface.data
    Behavior on surfaceOpacity {
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.fadeCurve }
    }
    Behavior on surfaceScale {
        NumberAnimation { id: scaleAnimation; duration: Theme.pickerDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.pickerCurve }
    }
    // Complete the invisible scale exit before the next opening. Rapid reversal
    // while fading continues smoothly from the current, not the initial, value.
    onSurfaceOpacityChanged: if (!opened && surfaceOpacity === 0) scaleAnimation.complete()
    Component.onCompleted: UiState.surfaces = [...UiState.surfaces, root]
    Component.onDestruction: if (UiState.surfaces) UiState.surfaces = UiState.surfaces.filter(item => item !== root)

    screen: UiState.screen
    visible: opened || surfaceOpacity > 0
    focusable: opened
    color: Theme.transparentColor
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-dev-" + route
    anchors { top: true; bottom: true; left: true; right: true }
    // Release input immediately on dismissal, not after the visual exit.
    mask: Region { width: root.opened ? root.width : 0; height: root.opened ? root.height : 0 }

    Rectangle {
        anchors.fill: parent
        color: root.dimBackground ? Theme.scrim : Theme.transparentColor
        opacity: root.surfaceOpacity
        MouseArea {
            anchors.fill: parent
            onClicked: UiState.close(root.route)
        }
    }

    Item {
        id: surface
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: UiState.close(root.route)
    }
}
