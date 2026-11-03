import QtQuick

// Discrete navigation, not a background MouseArea hidden behind clickable slides.
// Pointer handlers on the viewport see wheel input over its descendants too.
Item {
    id: root
    signal stepped(int steps)
    property bool scrollEnabled: true
    property real remainder: 0
    property int lastAxis: 0
    property bool lastWasPixels: false
    property real pixelStep: 48

    function reset(): void { remainder = 0; lastAxis = 0; idle.stop(); }
    function consume(event, axis): void {
        // Prefer vertical for diagonal gestures: never process one event twice.
        if (axis === Qt.Horizontal && (event.pixelDelta.y || event.angleDelta.y)) {
            event.accepted = false;
            return;
        }
        const pixels = axis === Qt.Vertical ? event.pixelDelta.y : event.pixelDelta.x;
        const angle = axis === Qt.Vertical ? event.angleDelta.y : event.angleDelta.x;
        const delta = pixels || angle;
        if (!delta) { event.accepted = false; return; }
        const usePixels = pixels !== 0;
        if (lastAxis !== axis || lastWasPixels !== usePixels) remainder = 0;
        lastAxis = axis;
        lastWasPixels = usePixels;
        // Deltas already reflect the system's natural-scroll setting.
        remainder -= delta;
        const threshold = usePixels ? pixelStep : 120;
        const steps = Math.trunc(remainder / threshold);
        if (steps) { remainder -= steps * threshold; stepped(steps); }
        event.accepted = true;
        idle.restart();
    }
    onEnabledChanged: reset()
    onScrollEnabledChanged: reset()
    onVisibleChanged: reset()
    Timer { id: idle; interval: 200; onTriggered: root.reset() }
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Vertical
        enabled: root.scrollEnabled
        onWheel: event => root.consume(event, Qt.Vertical)
    }
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Horizontal
        enabled: root.scrollEnabled
        onWheel: event => root.consume(event, Qt.Horizontal)
    }
}
