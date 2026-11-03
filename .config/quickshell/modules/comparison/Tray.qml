import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.modules.bar
import qs.components
import qs.services

Row {
    id: root
    spacing: 6
    property alias menu: menu
    readonly property var items: SystemTray.items.values.slice().sort((a, b) => {
        const order = ["nm-applet", "blueman"];
        const rank = item => order.includes(item.id) ? order.indexOf(item.id) : order.length;
        return rank(a) - rank(b) || a.id.localeCompare(b.id);
    })
    TrayMenu { id: menu }
    function panelTargets() {
        const targets = [];
        for (let i = 0; i < repeater.count; ++i) {
            const item = repeater.itemAt(i);
            if (item && (["nm-applet", "blueman"].includes(item.modelData.id) || item.modelData.hasMenu)) targets.push(item);
        }
        return targets;
    }
    function geometry() {
        const result = [];
        for (let i = 0; i < repeater.count; ++i) {
            const item = repeater.itemAt(i);
            if (item && item.visible) result.push({key: "tray:" + item.modelData.id, x: x + item.x,
                width: item.width, iconX: x + item.x + item.iconCanvas.x, iconSize: item.iconCanvas.width,
                iconSource: item.modelData.icon, resolvedPath: item.iconCanvas.resolvedPath});
        }
        return result;
    }

    function click(item, target, button): void {
        if (ConnectivityService.openTray(item.id, button)) return;
        if (button === Qt.MiddleButton) item.secondaryActivate();
        else if (item.hasMenu) { UiState.close(""); menu.open(target, item); }
        else if (button === Qt.LeftButton) item.activate();
    }
    function open(id): bool { return ConnectivityService.openTray(id, Qt.LeftButton) || openMenu(id); }
    function openMenu(id): bool {
        for (let i = 0; i < repeater.count; ++i) {
            const target = repeater.itemAt(i);
            if (target && target.modelData.id === id && target.modelData.hasMenu) {
                UiState.close("");
                menu.open(target, target.modelData);
                return true;
            }
        }
        return false;
    }
    Repeater {
        id: repeater
        model: ScriptModel { values: root.items; objectProp: "id" }
        MouseArea {
            id: trayItem
            required property var modelData
            property alias iconCanvas: icon
            width: 22
            height: 26
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            Rectangle { anchors.fill: parent; radius: 4; color: trayItem.containsMouse ? Style.surface : "transparent" }
            TrayIcon { id: icon; anchors.horizontalCenter: parent.horizontalCenter; y: (parent.height - height) / 2; icon: trayItem.modelData.icon }
            onClicked: event => root.click(modelData, trayItem, event.button)
            onWheel: event => modelData.scroll(event.angleDelta.x || event.angleDelta.y, event.angleDelta.x !== 0)
            ThemeTooltip { target: trayItem; hovered: trayItem.containsMouse; text: trayItem.modelData.tooltipTitle || trayItem.modelData.title }
        }
    }
}
