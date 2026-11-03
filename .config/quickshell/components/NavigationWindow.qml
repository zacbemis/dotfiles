import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.theme

// One native surface owns the scrim, blur, frame and tabs for the whole session.
// Changing pages must never map another full-screen dimming/blur surface.
PanelWindow {
    id: root
    property var page: null
    readonly property bool opened: UiState.navigationPage !== null
    readonly property var windowInsets: UiState.insets(screen)
    property real surfaceOpacity: opened ? 1 : 0
    property real surfaceScale: opened ? 1 : 0.85
    readonly property real displayScale: UiState.switching || !page || !page.popIn ? 1 : surfaceScale
    property alias bodyItem: body
    property alias tabsItem: tabs
    property alias panelItem: frame
    function dimensions() { return {x: frame.x, y: frame.y, width: frame.width, height: frame.height}; }
    function status() {
        return {opened: opened, visible: visible, opacity: surfaceOpacity, scale: displayScale,
            backdropOpacity: scrim.opacity, route: page ? page.route : "", panel: dimensions(),
            namespace: "quickshell-dev-panel", inputRegion: {y: root.mask.y, width: root.mask.width, height: root.mask.height, exclusions: root.mask.exclusions()}};
    }
    Connections {
        target: UiState
        function onNavigationPageChanged() { if (UiState.navigationPage) root.page = UiState.navigationPage; }
    }
    Component.onCompleted: {
        UiState.navigationHost = root;
        if (UiState.navigationPage) page = UiState.navigationPage;
    }
    Component.onDestruction: if (UiState.navigationHost === root) UiState.navigationHost = null
    Behavior on surfaceOpacity {
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.fadeCurve }
    }
    Behavior on surfaceScale {
        NumberAnimation { id: scaleAnimation; duration: Theme.pickerDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.pickerCurve }
    }
    onSurfaceOpacityChanged: if (!opened && surfaceOpacity === 0) scaleAnimation.complete()

    screen: UiState.screen
    visible: opened || surfaceOpacity > 0
    focusable: opened
    color: Theme.transparentColor
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-dev-panel"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: PanelInputRegion { output: root.screen; targetWindow: root; windowWidth: root.width; windowHeight: root.height; active: root.opened }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.surfaceOpacity
        MouseArea { anchors.fill: parent; onClicked: UiState.close("") }
    }
    PanelShortcuts { shortcutEnabled: root.opened; onStepped: delta => ShellNavigation.step(delta) }
    Item {
        id: frame
        x: root.windowInsets.left + (parent.width - root.windowInsets.left - root.windowInsets.right - width) / 2
        y: Math.max(root.windowInsets.top, Math.min((parent.height - height) / 2, parent.height - height - root.windowInsets.bottom))
        width: Math.max(0, Math.min(root.page ? root.page.preferredWidth : UiState.panelWidth,
            parent.width - root.windowInsets.left - root.windowInsets.right))
        height: Math.max(0, Math.min(root.page ? root.page.preferredHeight : UiState.panelHeight,
            parent.height - root.windowInsets.top - root.windowInsets.bottom))
        opacity: root.surfaceOpacity
        scale: root.displayScale
        Keys.onEscapePressed: UiState.close("")
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.background
            border.color: Theme.outlineVariant
            MouseArea { anchors.fill: parent }
        }
        PanelTabs { id: tabs; x: 16; y: 16; width: Math.max(0, parent.width - 32); height: 32 }
        Item {
            id: body
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 60
        }
    }
}
