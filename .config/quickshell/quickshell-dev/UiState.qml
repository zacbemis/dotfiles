pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // One keyboard-exclusive surface at a time. Pin it to the monitor where
    // it was opened, rather than moving it whenever pointer focus changes.
    property string active: ""
    property var surfaces: []
    function motionStatus() {
        return surfaces.map(surface => ({route: surface.route, opened: surface.opened,
            visible: surface.visible, opacity: surface.surfaceOpacity,
            scale: surface.popIn ? surface.surfaceScale : 1, focusable: surface.focusable}));
    }
    property string screenName: ""
    readonly property var screen: Quickshell.screens.find(s => s.name === screenName)
        || Quickshell.screens[0] || null

    function topInset(targetScreen): real {
        const monitor = targetScreen ? Hyprland.monitorFor(targetScreen) : null;
        const reserved = monitor ? monitor.lastIpcObject.reserved : null;
        return Math.max(12, (reserved ? Number(reserved[1]) || 0 : 0) + 12);
    }

    function show(name): void {
        if (active === "") {
            screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : (Quickshell.screens[0] ? Quickshell.screens[0].name : "");
        }
        active = name;
    }

    function close(name): void {
        if (!name || active === name) active = "";
    }

    function toggle(name): void {
        if (active === name) close(name);
        else show(name);
    }
}
