import QtQuick
import Quickshell
import qs.services
import qs.theme

Row {
    id: root
    property bool compact: false
    property bool showClock: true
    property alias tray: tray
    spacing: Style.enzo ? 8 : 4
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function panelTargets() {
        return children.filter(item => ["volume", "controls", "notifications"].includes(item.controlKey)).concat(tray.panelTargets());
    }
    function metrics() {
        const slots = tray.geometry();
        for (const item of children) if (item.controlKey && item.visible) slots.push(item.geometry());
        return {spacing: spacing, iconSize: 14,
            slots: slots.sort((a, b) => a.x - b.x)};
    }

    Tray { id: tray; anchors.verticalCenter: parent.verticalCenter }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "brightness"
        foreground: Style.icon
        indicatorState: Object.assign({icon: BarIndicators.icon("brightness")}, SystemState.indicator("brightness"))
        text: BarIndicators.percent("brightness") ? SystemState.brightnessPercent + "%" : ""
        labelWhenCompact: !BarIndicators.icon("brightness")
        compact: root.compact
        visible: SystemState.brightnessAvailable && BarIndicators.shown("brightness")
        tooltip: "Brightness · " + SystemState.brightnessPercent + "% · scroll for 5% steps"
        onScrolled: delta => SystemState.adjustBrightness(delta)
    }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "volume"
        indicatorState: Object.assign({icon: BarIndicators.icon("volume")}, SystemState.indicator("volume"))
        text: BarIndicators.percent("volume") ? (SystemState.muted ? "Muted" : SystemState.volumePercent + "%") : ""
        labelWhenCompact: !BarIndicators.icon("volume")
        visible: BarIndicators.shown("volume")
        foreground: SystemState.muted ? Theme.error : Style.icon
        compact: root.compact
        tooltip: SystemState.volumeTooltip
        onClicked: AudioService.open()
        onScrolled: delta => SystemState.adjustVolume(delta > 0 ? 0.02 : -0.02)
    }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "battery"
        indicatorState: Object.assign({icon: BarIndicators.icon("battery")}, SystemState.indicator("battery"))
        text: BarIndicators.percent("battery") ? SystemState.batteryPercent + "%" : ""
        labelWhenCompact: !BarIndicators.icon("battery")
        visible: SystemState.batteryAvailable && BarIndicators.shown("battery")
        compact: root.compact
        foreground: SystemState.batteryPercent <= 20 ? Theme.error : Style.icon
        tooltip: SystemState.batteryPercent + "%"
    }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "clock"
        interactive: false
        visible: root.showClock
        glyph: ""
        text: Qt.locale("en_US").toString(clock.date, "hh:mm AP")
        tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")
    }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "controls"
        glyph: "󰒓"
        tooltip: "Quick settings"
        onClicked: ShellProfile.activate("controls")
    }
    Action {
        anchors.verticalCenter: parent.verticalCenter
        controlKey: "notifications"
        iconColor: NotificationService.unreadCount > 0 ? Style.unreadIcon : Style.icon
        glyph: NotificationService.dnd ? "󰂛" : "󰂚"
        text: NotificationService.unreadCount ? String(NotificationService.unreadCount) : ""
        foreground: NotificationService.dnd ? Theme.error : Style.accent
        tooltip: "Notifications"
        onClicked: button => ShellProfile.activate(button === Qt.RightButton ? "dnd" : "notifications")
    }
}
