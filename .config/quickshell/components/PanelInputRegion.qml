import QtQml.Models
import Quickshell
import qs.services

// Capture outside clicks, including the bar background. Only actual panel
// buttons are holes, so their first click can switch the requested panel.
Region {
    id: root
    required property var output
    required property var targetWindow
    required property real windowWidth
    required property real windowHeight
    property bool active: true
    width: active ? Math.max(0, windowWidth) : 0
    height: active ? Math.max(0, windowHeight) : 0
    function exclusions() { return Array.from(regions, region => ({x: region.x, y: region.y, width: region.width, height: region.height})); }
    function captures(x, y): bool {
        return active && x >= 0 && y >= 0 && x < width && y < height
            && !exclusions().some(rect => x >= rect.x && y >= rect.y && x < rect.x + rect.width && y < rect.y + rect.height);
    }
    property Instantiator cutouts: Instantiator {
        model: root.active ? UiState.panelTargets(root.output) : []
        delegate: Region {
            required property var modelData
            readonly property var bounds: UiState.panelTargetRect(root.targetWindow, modelData)
            intersection: Intersection.Subtract
            x: bounds.x
            y: bounds.y
            width: bounds.width
            height: bounds.height
        }
        onObjectAdded: (index, object) => root.regions.push(object)
        onObjectRemoved: (index, object) => {
            const remaining = Array.from(root.regions).filter(region => region !== object);
            // Reappend to retain child-change subscriptions after list removal.
            root.regions.length = 0;
            for (const region of remaining) root.regions.push(region);
        }
    }
}
