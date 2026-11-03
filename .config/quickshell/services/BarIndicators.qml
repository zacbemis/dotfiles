pragma Singleton
import QtQuick
import Quickshell
import "StyleCatalog.js" as Catalog

Singleton {
    id: root
    readonly property var keys: Catalog.indicators.map(item => item.key)
    property string volumeIndicator: Preferences.value("volumeIndicator", "both")
    property string brightnessIndicator: Preferences.value("brightnessIndicator", "both")
    property string batteryIndicator: Preferences.value("batteryIndicator", "both")
    property bool ready: false
    Component.onCompleted: ready = true
    onVolumeIndicatorChanged: if (ready) Preferences.set("volumeIndicator", volumeIndicator)
    onBrightnessIndicatorChanged: if (ready) Preferences.set("brightnessIndicator", brightnessIndicator)
    onBatteryIndicatorChanged: if (ready) Preferences.set("batteryIndicator", batteryIndicator)
    function value(key): string { return keys.includes(key) ? root[key] : "hidden"; }
    function set(key, mode): bool {
        if (!keys.includes(key) || !Catalog.valid(key, mode)) return false;
        root[key] = mode;
        return true;
    }
    function mode(kind): string { return value(kind + "Indicator"); }
    function icon(kind): bool { return ["both", "icon"].includes(mode(kind)); }
    function percent(kind): bool { return ["both", "percent"].includes(mode(kind)); }
    function shown(kind): bool { return mode(kind) !== "hidden"; }
    function status() { return {volumeIndicator: volumeIndicator, brightnessIndicator: brightnessIndicator, batteryIndicator: batteryIndicator}; }
}
