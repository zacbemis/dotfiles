pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // One keyboard-exclusive surface at a time. Pin it to the monitor where
    // it was opened, rather than moving it whenever pointer focus changes.
    property string active: ""
    property bool switching: false
    readonly property int panelWidth: 720
    readonly property int panelHeight: 420
    readonly property real windowGap: LayoutMetrics.windowGap
    property var surfaces: []
    property var bars: []
    property var navigationHost: null
    readonly property var navigationPage: surfaces.find(surface => surface.navigationPanel
        && surface.routeEnabled && surface.route === active) || null
    function motionStatus() { return surfaces.map(surface => surface.motionState()); }
    property string screenName: ""
    readonly property var screen: Quickshell.screens.find(s => s.name === screenName)
        || Quickshell.screens[0] || null

    function insets(targetScreen) {
        const monitor = targetScreen ? Hyprland.monitorFor(targetScreen) : null;
        const reserved = targetScreen && LayoutMetrics.reservations[targetScreen.name]
            ? LayoutMetrics.reservations[targetScreen.name] : monitor ? monitor.lastIpcObject.reserved : null;
        const area = LayoutMetrics.outer;
        return {left: area.left + (reserved ? Number(reserved[0]) || 0 : 0),
            top: area.top + (reserved ? Number(reserved[1]) || 0 : 0),
            right: area.right + (reserved ? Number(reserved[2]) || 0 : 0),
            bottom: area.bottom + (reserved ? Number(reserved[3]) || 0 : 0)};
    }
    function panelTargets(targetScreen) {
        if (!targetScreen) return [];
        const targets = [];
        for (const bar of bars) {
            if (!bar || !bar.visible || !bar.screen || bar.screen.name !== targetScreen.name) continue;
            for (const item of bar.panelTargets()) if (item && item.visible && item.enabled) targets.push(item);
        }
        return targets;
    }
    function panelTargetRect(targetWindow, item) {
        const empty = {x: 0, y: 0, width: 0, height: 0};
        const source = item ? item.QsWindow.window : null;
        if (!source || !targetWindow || !targetWindow.visible) return empty;
        // Observe all ancestors, not just the button: right-aligned rows move
        // when neighbouring readouts change, and auto-hide animates the parent.
        let geometry = 0;
        for (let parent = item; parent; parent = parent.parent) {
            if (!parent.visible) return empty;
            geometry += parent.x + parent.y + parent.width + parent.height + parent.scale + parent.rotation;
        }
        if (!Number.isFinite(geometry) || source.windowTransform === undefined || targetWindow.windowTransform === undefined) return empty;
        // Layer-shell does not provide global positions to Qt. Use the
        // compositor's owned-layer frame, relative to this fullscreen output.
        const frame = LayoutMetrics.barFrameFor(source.screen);
        const origin = targetWindow.screen ? LayoutMetrics.origins[targetWindow.screen.name] : null;
        const rect = frame && origin ? source.mapFromItem(item, 0, 0, item.width, item.height)
            : targetWindow.mapFromItem(item, 0, 0, item.width, item.height);
        if (frame && origin) { rect.x += frame.x - origin.x; rect.y += frame.y - origin.y; }
        const x = Math.floor(rect.x), y = Math.floor(rect.y);
        return {x: x, y: y, width: Math.max(0, Math.ceil(rect.x + rect.width) - x), height: Math.max(0, Math.ceil(rect.y + rect.height) - y)};
    }
    function topInset(targetScreen): real { return insets(targetScreen).top; }
    function layoutStatus() { return {outer: LayoutMetrics.outer, inner: LayoutMetrics.inner, windowGap: windowGap, insets: insets(screen)}; }

    function show(name): void {
        if (name !== "") LayoutMetrics.refresh();
        switching = active !== "";
        if (active === "") {
            screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : (Quickshell.screens[0] ? Quickshell.screens[0].name : "");
        }
        active = name;
    }

    function close(name): void {
        if (!name || active === name) { switching = false; active = ""; }
    }

    function toggle(name): void {
        if (active === name) close(name);
        else show(name);
    }
}
