import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Scope {
    id: root

    property var notificationUi: null
    property var barWindows: []
    readonly property var trayItems: SystemTray.items.values.slice().sort((a, b) => {
        // Preserve the current desktop's network/Bluetooth order even when
        // asynchronous DBus discovery completes in a different order on reload.
        const order = ["nm-applet", "blueman"];
        const rank = item => order.includes(item.id) ? order.indexOf(item.id) : order.length;
        return rank(a) - rank(b) || a.id.localeCompare(b.id);
    })

    // The click path and CLI verification share this dispatcher. Exported menus
    // take precedence over Activate (nm-applet exports a menu but onlyMenu=false).
    Connections {
        target: UiState
        function onActiveChanged() {
            if (UiState.active !== "") for (const window of root.barWindows) window.trayMenu.close();
        }
    }
    function clickTray(item, target, button, menu): void {
        if (button === Qt.MiddleButton) item.secondaryActivate();
        else if (item.hasMenu) { UiState.close(""); menu.open(target, item); }
        else if (button === Qt.LeftButton) item.activate();
    }

    IpcHandler {
        target: "tray"
        function items(): string {
            return JSON.stringify(SystemTray.items.values.map(item => ({id: item.id, title: item.title,
                hasMenu: item.hasMenu, onlyMenu: item.onlyMenu})));
        }
        function open(id: string): bool {
            const item = SystemTray.items.values.find(item => item.id === id);
            if (!item || !item.hasMenu) return false;
            for (const window of root.barWindows) {
                for (let i = 0; i < window.trayRepeater.count; ++i) {
                    const target = window.trayRepeater.itemAt(i);
                    if (target && target.modelData === item) {
                        root.clickTray(item, target, Qt.LeftButton, window.trayMenu);
                        return true;
                    }
                }
            }
            return false;
        }
        function close(): void { for (const window of root.barWindows) window.trayMenu.close(); }
        function submenu(label: string): bool {
            for (const window of root.barWindows) {
                const menu = window.trayMenu;
                const entry = menu.visible && menu.entries.find(entry => entry.text === label && entry.enabled && entry.hasChildren);
                if (entry) { menu.choose(entry); return true; }
            }
            return false;
        }
        function back(): void { for (const window of root.barWindows) if (window.trayMenu.visible) window.trayMenu.back(); }
        function next(): void { for (const window of root.barWindows) if (window.trayMenu.visible) window.trayMenu.navigate(1); }
        function status(): string {
            return JSON.stringify(root.barWindows.map(window => ({screen: window.screen.name,
                open: window.trayMenu.visible, depth: window.trayMenu.menuPath.length,
                selected: window.trayMenu.selectedIndex,
                hoverPoint: window.trayMenu.visible ? window.trayMenu.hoverPoint() : null,
                entries: window.trayMenu.entries.map(entry => ({text: entry.text, enabled: entry.enabled,
                    submenu: entry.hasChildren, separator: entry.isSeparator}))})));
        }
    }

    IpcHandler {
        target: "bar"
        function geometry(): string {
            return JSON.stringify(root.barWindows.map(window => window.geometry()));
        }
    }

    function appIcon(toplevel) {
        if (!toplevel) return "";
        const appId = toplevel.wayland ? toplevel.wayland.appId
            : (toplevel.lastIpcObject.class || "");
        const entry = appId ? DesktopEntries.heuristicLookup(appId) : null;
        return appId ? Quickshell.iconPath(entry && entry.icon ? entry.icon : appId, true) : "";
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            property alias trayRepeater: trayRepeater
            property alias trayMenu: trayMenu
            function geometry() {
                const bounds = item => ({x: item.mapToItem(barContent, 0, 0).x, y: item.y,
                    width: item.width, height: item.height});
                return {screen: screen.name, modules: {notification: bounds(notificationPill),
                    workspaces: bounds(workspacePill), clock: bounds(clockPill), tray: bounds(trayPill),
                    brightness: bounds(brightnessPill), volume: bounds(volumePill), battery: bounds(batteryPill)},
                    workspaces: Array.from({length: workspaceRepeater.count}, (_, i) => {
                        const button = workspaceRepeater.itemAt(i);
                        return {id: button.modelData.id, focused: button.modelData.focused, bounds: bounds(button),
                            width: button.width, targetWidth: button.targetWidth, height: button.height,
                            animating: button.widthAnimationRunning};
                    }), tray: Array.from({length: trayRepeater.count}, (_, i) => {
                        const item = trayRepeater.itemAt(i);
                        return {id: item.modelData.id, bounds: bounds(item), icon: item.modelData.icon,
                            imageWidth: item.iconImage.width, imageHeight: item.iconImage.height,
                            sourceWidth: item.iconImage.backer.sourceSize.width,
                            naturalWidth: item.iconImage.backer.implicitWidth, resolvedPath: item.iconImage.resolvedPath,
                            lookupPending: item.iconImage.lookupPending};
                    })};
            }
            Component.onCompleted: root.barWindows = [...root.barWindows, barWindow]
            Component.onDestruction: root.barWindows = root.barWindows.filter(window => window !== barWindow)
            TrayMenu { id: trayMenu }

            screen: modelData
            color: Theme.transparentColor
            aboveWindows: true
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 30

            anchors {
                top: true
                left: true
                right: true
            }
            margins.top: 8
            implicitHeight: 30

            Item {
                id: barContent
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                Row {
                    id: leftModules
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Same Arch notification glyph used by the current
                    // custom/notification Waybar module.
                    BarPill {
                        id: notificationPill
                        implicitWidth: notificationRow.implicitWidth + 2 * Theme.barPadding

                        Row {
                            id: notificationRow
                            anchors.centerIn: parent
                            spacing: 5
                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: ""
                                color: !root.notificationUi ? Theme.notificationIdle
                                    : root.notificationUi.dnd ? Theme.error
                                    : root.notificationUi.unreadCount > 0 ? Theme.tertiary : Theme.notificationIdle
                                font: Theme.barIconFont
                            }
                            ThemeText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.notificationUi && root.notificationUi.unreadCount > 0
                                text: root.notificationUi ? Math.min(99, root.notificationUi.unreadCount) : ""
                                color: Theme.surfaceText
                                font.family: Theme.barFontFamily
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                // Keep SwayNC as the live notification UI until
                                // Quickshell notifications are explicitly enabled.
                                if (!root.notificationUi) {
                                    Quickshell.execDetached([
                                        "swaync-client",
                                        mouse.button === Qt.RightButton ? "-d" : "-t",
                                        "-sw"
                                    ]);
                                    return;
                                }
                                if (mouse.button === Qt.RightButton)
                                    root.notificationUi.toggleDnd();
                                else
                                    root.notificationUi.toggleCenter();
                            }
                        }
                    }

                    BarPill {
                        id: workspacePill
                        implicitWidth: workspaceRow.implicitWidth + 14 // border + padding + button margins

                        Row {
                            id: workspaceRow
                            anchors.centerIn: parent
                            spacing: 6 // the two adjacent GTK button margins

                            Repeater {
                                id: workspaceRepeater
                                model: ScriptModel {
                                    objectProp: "id"
                                    values: Hyprland.workspaces.values.filter(w => w.id > 0
                                        && w.monitor && w.monitor.name === barWindow.screen.name)
                                        .sort((a, b) => a.id - b.id)
                                }

                                Rectangle {
                                    id: workspaceButton
                                    required property var modelData

                                    readonly property real targetWidth: Math.max(modelData.focused || modelData.urgent
                                        || workspaceMouse.containsMouse ? 40 : 0, workspaceInner.implicitWidth) + 12
                                    readonly property bool widthAnimationRunning: workspaceWidthAnimation.running
                                    implicitWidth: targetWidth
                                    implicitHeight: Theme.workspaceHeight
                                    radius: Theme.workspaceHeight / 2
                                    color: modelData.urgent ? Theme.error
                                         : workspaceMouse.containsMouse ? Theme.barHoverBackground
                                         : modelData.focused ? Theme.secondary
                                         : Theme.background

                                    Behavior on implicitWidth {
                                        NumberAnimation {
                                            id: workspaceWidthAnimation
                                            duration: Theme.workspaceDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.cssEaseInOut
                                        }
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.workspaceDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.cssEaseInOut
                                        }
                                    }

                                    Row {
                                        id: workspaceInner
                                        anchors.centerIn: parent
                                        spacing: workspaceSpace.advanceWidth
                                        TextMetrics { id: workspaceSpace; font: Theme.barFont; text: " " }

                                        ThemeText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: workspaceButton.modelData.name || workspaceButton.modelData.id
                                            color: workspaceButton.modelData.urgent ? Theme.errorText
                                                   : workspaceMouse.containsMouse ? Theme.barHoverText
                                                   : workspaceButton.modelData.focused ? Theme.secondaryText
                                                   : Theme.surfaceText
                                            font: Theme.barFont
                                            Behavior on color {
                                                ColorAnimation { duration: Theme.workspaceDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEaseInOut }
                                            }
                                        }

                                        Repeater {
                                            model: workspaceButton.modelData.toplevels

                                            Item {
                                                id: toplevelIcon
                                                anchors.verticalCenter: parent.verticalCenter
                                                required property var modelData
                                                width: 15
                                                height: 15

                                                Image {
                                                    id: toplevelImage
                                                    anchors.fill: parent
                                                    source: root.appIcon(toplevelIcon.modelData)
                                                    sourceSize.width: 15
                                                    sourceSize.height: 15
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: source !== ""
                                                }

                                                GlyphIcon {
                                                    anchors.centerIn: parent
                                                    glyph: ""
                                                    color: workspaceMouse.containsMouse ? Theme.barHoverText
                                                        : workspaceButton.modelData.focused ? Theme.secondaryText : Theme.surfaceVariantText
                                                    font: Theme.barIconFont
                                                    visible: toplevelImage.source === ""
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: workspaceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: workspaceButton.modelData.activate()
                                    }
                                }
                            }
                        }
                    }
                }

                BarPill {
                    id: clockPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenterOffset: 4 // centered GTK module includes its left margin
                    implicitWidth: clockText.implicitWidth + 2 * Theme.barPadding

                    SystemClock {
                        id: clock
                        precision: SystemClock.Minutes
                    }

                    ThemeText {
                        id: clockText
                        anchors.centerIn: parent
                        // Match Waybar `{:%I:%M %p}` (12-hour, zero-padded).
                        text: Qt.locale("en_US").toString(clock.date, "hh:mm AP")
                        color: Theme.inversePrimary
                        font: Theme.barFont
                    }

                    BarTooltip {
                        target: clockPill
                        hovered: clockMouse.containsMouse
                        text: Qt.formatDateTime(clock.date, "MM-dd-yyyy")
                            + "\nLeft click: apps · Right click: wallpapers"
                    }

                    MouseArea {
                        id: clockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => UiState.toggle(mouse.button === Qt.RightButton ? "wallpaper" : "launcher")
                    }
                }

                Row {
                    id: rightModules
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    BarPill {
                        id: trayPill
                        visible: SystemTray.items.values.length > 0
                        implicitWidth: trayRow.implicitWidth + 2 * Theme.barPadding

                        Row {
                            id: trayRow
                            anchors.centerIn: parent
                            spacing: Theme.traySpacing

                            Repeater {
                                id: trayRepeater
                                model: ScriptModel { values: root.trayItems; objectProp: "id" }

                                MouseArea {
                                    id: trayItem
                                    required property var modelData
                                    property alias iconImage: trayIcon
                                    width: Theme.barImageSize
                                    height: Theme.barImageSize
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor

                                    TrayIcon {
                                        id: trayIcon
                                        anchors.centerIn: parent
                                        icon: trayItem.modelData.icon
                                    }

                                    BarTooltip {
                                        target: trayItem
                                        hovered: trayItem.containsMouse
                                        text: trayItem.modelData.tooltipTitle || trayItem.modelData.title
                                    }
                                    onWheel: wheel => trayItem.modelData.scroll(
                                        wheel.angleDelta.x || wheel.angleDelta.y, wheel.angleDelta.x !== 0)
                                    onClicked: mouse => root.clickTray(trayItem.modelData, trayItem, mouse.button, trayMenu)
                                }
                            }
                        }
                    }

                    BarPill {
                        id: brightnessPill
                        visible: SystemState.brightnessAvailable
                        implicitWidth: brightnessText.implicitWidth + 2 * Theme.barPadding

                        BarLabel {
                            id: brightnessText
                            anchors.centerIn: parent
                            text: SystemState.brightnessPercent + "%"
                            icon: SystemState.brightnessIcon
                            color: Theme.secondary
                        }

                        BarTooltip {
                            target: brightnessPill
                            hovered: brightnessMouse.containsMouse
                            text: "Brightness · " + SystemState.brightnessPercent + "%\nScroll to adjust"
                        }
                        MouseArea {
                            id: brightnessMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            onWheel: function(wheel) {
                                if (wheel.angleDelta.y !== 0) SystemState.adjustBrightness(wheel.angleDelta.y);
                            }
                        }
                    }

                    BarPill {
                        id: volumePill
                        implicitWidth: volumeText.implicitWidth + 2 * Theme.barPadding

                        BarLabel {
                            id: volumeText
                            anchors.centerIn: parent
                            text: SystemState.volumePercent + "%"
                            icon: SystemState.volumeIcon
                            color: Theme.tertiary
                        }

                        BarTooltip {
                            target: volumePill
                            hovered: volumeMouse.containsMouse
                            text: (SystemState.audioSink ? SystemState.audioSink.description : "No audio output")
                                + "\n" + (SystemState.muted ? "Muted" : SystemState.volumePercent + "%")
                                + " · Click to mute · Scroll to adjust"
                        }
                        MouseArea {
                            id: volumeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemState.toggleMute()
                            onWheel: function(wheel) {
                                if (wheel.angleDelta.y !== 0)
                                    SystemState.adjustVolume(wheel.angleDelta.y > 0 ? 0.02 : -0.02);
                            }
                        }
                    }

                    BarPill {
                        id: batteryPill
                        visible: SystemState.batteryAvailable
                        implicitWidth: batteryText.implicitWidth + 2 * Theme.barPadding

                        BarLabel {
                            id: batteryText
                            anchors.centerIn: parent
                            text: SystemState.batteryPercent + "%"
                            icon: SystemState.batteryIcon // Waybar uses one glyph, including while charging
                            color: SystemState.batteryPercent <= 20 ? Theme.error
                                   : SystemState.batteryPercent <= 40 ? SystemState.batteryWarning
                                   : Theme.primary
                        }
                        HoverHandler { id: batteryHover }
                        BarTooltip {
                            target: batteryPill
                            hovered: batteryHover.hovered
                            text: (SystemState.batteryCharging ? "Charging" : SystemState.batteryPercent >= 99
                                ? "Fully charged" : "On battery") + " · " + SystemState.batteryPercent + "%"
                        }
                    }
                }
            }
        }
    }
}
