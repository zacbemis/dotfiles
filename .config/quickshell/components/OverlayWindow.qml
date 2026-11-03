import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.theme

PanelWindow {
    id: root
    required property string route
    readonly property var windowInsets: UiState.insets(screen)
    property bool navigationPanel: false
    property int preferredWidth: UiState.panelWidth
    property int preferredHeight: UiState.panelHeight
    readonly property var host: UiState.navigationHost
    readonly property bool renderVisible: navigationPanel
        ? !!host && host.page === root && host.visible : visible
    function typography() {
        return navigationPanel && host
            ? Theme.auditText(host.tabsItem).concat(Theme.auditText(body)) : Theme.auditText(body);
    }
    function dimensions() {
        return navigationPanel && host ? host.dimensions()
            : {x: 0, y: 0, width: surface.width, height: surface.height};
    }
    function motionState() {
        return {route: route, opened: opened, visible: renderVisible, opacity: surfaceOpacity,
            scale: displayScale, focusable: navigationPanel ? opened && !!host && host.focusable : focusable,
            navigation: navigationPanel, panel: dimensions(),
            inputRegion: {y: root.mask.y, width: root.mask.width, height: root.mask.height, exclusions: root.mask.exclusions()}};
    }
    property bool dimBackground: true
    property bool popIn: true
    property bool routeEnabled: true
    readonly property bool opened: routeEnabled && UiState.active === route
    property real surfaceOpacity: navigationPanel ? (renderVisible ? host.surfaceOpacity : 0) : opened ? 1 : 0
    property real surfaceScale: navigationPanel && host ? host.surfaceScale : opened ? 1 : 0.85
    readonly property real displayScale: navigationPanel && host ? host.displayScale : popIn ? surfaceScale : 1
    default property alias content: body.data
    Behavior on surfaceOpacity {
        enabled: !root.navigationPanel
        NumberAnimation { duration: Theme.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.fadeCurve }
    }
    Behavior on surfaceScale {
        enabled: !root.navigationPanel && root.popIn
        NumberAnimation { id: scaleAnimation; duration: Theme.pickerDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.compositorMotion.pickerCurve }
    }
    onSurfaceOpacityChanged: if (!navigationPanel && !opened && surfaceOpacity === 0) scaleAnimation.complete()
    Component.onCompleted: UiState.surfaces = [...UiState.surfaces, root]
    Component.onDestruction: {
        if (UiState.surfaces) UiState.surfaces = UiState.surfaces.filter(item => item !== root);
        if (navigationPanel && host && host.page === root) host.page = null;
    }

    screen: UiState.screen
    // Tabbed pages provide content only. Their native windows never map.
    visible: !navigationPanel && (opened || surfaceOpacity > 0)
    focusable: !navigationPanel && opened
    color: Theme.transparentColor
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !navigationPanel && opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-dev-" + route
    anchors { top: true; bottom: true; left: true; right: true }
    mask: PanelInputRegion { output: root.screen; targetWindow: root; windowWidth: root.width; windowHeight: root.height; active: !root.navigationPanel && root.opened }

    Rectangle {
        anchors.fill: parent
        color: root.dimBackground ? Theme.scrim : Theme.transparentColor
        opacity: root.surfaceOpacity
        MouseArea { anchors.fill: parent; onClicked: UiState.close(root.route) }
    }
    Item { id: surface; anchors.fill: parent }
    Item {
        id: body
        // Visual reparenting keeps the existing renderer/controller lifetime while
        // using the same persistent native window, frame and backdrop for all tabs.
        parent: root.navigationPanel && root.host ? root.host.bodyItem : surface
        anchors.fill: parent
        visible: !root.navigationPanel || root.renderVisible
        focus: root.opened
        Keys.onEscapePressed: UiState.close(root.route)
    }
}
