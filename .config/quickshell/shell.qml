//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.modules.bar
import qs.modules.comparison
import qs.modules.controls
import qs.modules.osd
import qs.modules.settings
import qs.modules.launcher
import qs.modules.notifications
import qs.modules.wallpaper
import qs.services
import qs.theme

Scope {
    id: root
    Component.onCompleted: LayoutMetrics.refresh()

    // Isolated runners default off. The checked daily-session helper explicitly
    // enables server mode only after releasing/checking notification ownership.
    readonly property string notificationMode: ShellProfile.comparing ? "preview"
        : Quickshell.env("QUICKSHELL_NOTIFICATIONS")
            || (Quickshell.env("QUICKSHELL_ENABLE_NOTIFICATIONS") === "1" ? "server" : "off")

    readonly property var activeBar: ShellProfile.name === "current" ? currentBarLoader.item : comparisonBarLoader.item

    LazyLoader {
        id: currentBarLoader
        active: Quickshell.env("QUICKSHELL_BAR") !== "0" && ShellProfile.name === "current"
        Bar { notificationUi: notificationLoader.item }
    }
    LazyLoader {
        id: comparisonBarLoader
        active: Quickshell.env("QUICKSHELL_BAR") !== "0" && ShellProfile.name !== "current"
        ComparisonBar { notificationUi: notificationLoader.item }
    }
    LazyLoader {
        active: ShellProfile.comparing
        ComparePanel { onOsdPreviewRequested: osd.preview("volume", 65) }
    }
    NavigationWindow { id: navigationWindow }
    Connections {
        target: ShellProfile
        function onNameChanged() { LayoutMetrics.refresh(); }
        function onAutoHideChanged() { LayoutMetrics.refresh(); }
        function onPinnedChanged() { LayoutMetrics.refresh(); }
    }
    Launcher {}
    WallpaperPicker {}
    QuickSettings { id: controls; trayApi: root.activeBar ? root.activeBar.trayApi : null }
    Osd { id: osd }
    SettingsPanel { id: styleSettings; onOsdPreviewRequested: osd.preview("volume", 65) }

    LazyLoader {
        id: notificationLoader
        active: root.notificationMode === "preview" || root.notificationMode === "server"
        Notifications {}
    }

    // Stable IPC endpoints outlive bar loaders. Registering endpoints inside
    // both layouts races during profile switches and produces duplicate targets.
    IpcHandler {
        target: "bar"
        function geometry(): string { return root.activeBar ? root.activeBar.barApi.geometry() : "[]"; }
        function toggle(): void { if (root.activeBar && ShellProfile.name !== "current") root.activeBar.barApi.toggle(); }
        function reveal(): void { if (root.activeBar && ShellProfile.name !== "current") root.activeBar.barApi.reveal(); }
        function hide(): void { if (root.activeBar && ShellProfile.name !== "current") root.activeBar.barApi.hide(); }
    }
    IpcHandler {
        target: "tray"
        function items(): string { return root.activeBar ? root.activeBar.trayApi.items() : "[]"; }
        function open(id: string): bool { return root.activeBar ? root.activeBar.trayApi.open(id) : false; }
        function menu(id: string): bool { return root.activeBar ? root.activeBar.trayApi.menu(id) : false; }
        function close(): void { if (root.activeBar) root.activeBar.trayApi.close(); }
        function submenu(label: string): bool { return root.activeBar ? root.activeBar.trayApi.submenu(label) : false; }
        function back(): void { if (root.activeBar) root.activeBar.trayApi.back(); }
        function next(): void { if (root.activeBar) root.activeBar.trayApi.next(); }
        function status(): string { return root.activeBar ? root.activeBar.trayApi.status() : "[]"; }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { UiState.toggle("settings"); }
        function open(): void { UiState.show("settings"); }
        function close(): void { UiState.close("settings"); }
        function category(key: string): bool { return styleSettings.openCategory(key); }
        function set(key: string, value: string): bool {
            if (["wallpaperColors", "autoHide", "pinned"].includes(key)) {
                if (!["true", "false"].includes(value)) return false;
                return styleSettings.choose(key, value === "true");
            }
            return styleSettings.choose(key, value);
        }
        function preset(key: string): bool { return styleSettings.preset(key); }
        function apply(payload: string): bool {
            try { return styleSettings.apply(JSON.parse(payload)); } catch (failure) { return false; }
        }
        function preview(): void { styleSettings.preview(); }
        function size(width: int, height: int): void {
            if (ShellProfile.comparing) { styleSettings.preferredWidth = width > 0 ? width : UiState.panelWidth; styleSettings.preferredHeight = height > 0 ? height : UiState.panelHeight; }
        }
        function status(): string { return JSON.stringify(styleSettings.status()); }
    }
    IpcHandler {
        target: "navigation"
        function select(key: string): bool { return ShellNavigation.select(key); }
        function next(): bool { return ShellNavigation.step(1); }
        function previous(): bool { return ShellNavigation.step(-1); }
        function status(): string { return JSON.stringify(ShellNavigation.status()); }
    }
    IpcHandler {
        target: "features"
        function set(feature: string, view: string): bool { return FeatureSettings.select(feature, view); }
        function cycle(feature: string): bool { return FeatureSettings.cycle(feature); }
        function status(): string { return JSON.stringify(FeatureSettings.status()); }
    }
    IpcHandler {
        target: "controls"
        function toggle(): void { ConnectivityService.toggleOverview(); }
        function open(): void { ConnectivityService.openOverview(); }
        function close(): void { UiState.close("controls"); }
        function activate(feature: string): bool { return controls.activate(feature); }
        function status(): string { return JSON.stringify(controls.status()); }
    }
    IpcHandler {
        target: "connectivity"
        function open(kind: string): bool { return ConnectivityService.open(kind); }
        function click(id: string, button: string): bool {
            if (!["left", "right"].includes(button)) return false;
            return ConnectivityService.openTray(id, button === "left" ? Qt.LeftButton : Qt.RightButton);
        }
        function back(): void { ConnectivityService.back(); }
        function fixture_activate(target: string): bool { return controls.fixtureActivate(target); }
        function status(): string { return JSON.stringify(ConnectivityService.status()); }
        function audio_status(): string { return JSON.stringify(AudioService.status()); }
    }
    IpcHandler {
        target: "audio"
        function open(): bool { return AudioService.open(); }
        function status(): string { return JSON.stringify(AudioService.status()); }
    }
    IpcHandler {
        target: "caffeine"
        function toggle(): bool { return CaffeineService.toggle(); }
        function status(): string { return JSON.stringify(CaffeineService.status()); }
    }
    IpcHandler {
        target: "updates"
        function refresh(): bool { return UpdateService.refresh(); }
        function run(): void { UpdateService.runUpdates(); }
        function status(): string { return JSON.stringify(UpdateService.status()); }
    }
    IpcHandler {
        target: "osd"
        function preview(kind: string, value: int): bool { return osd.preview(kind, value); }
        function status(): string { return JSON.stringify(osd.status()); }
    }

    IpcHandler {
        target: "profile"
        function set(name: string): bool { return ShellProfile.select(name); }
        function next(): void { ShellProfile.next(); }
        function colors(): void { ShellProfile.wallpaperColors = !ShellProfile.wallpaperColors; }
        function autohide(): void { ShellProfile.autoHide = !ShellProfile.autoHide; }
        function activate(feature: string): bool { return ShellProfile.activate(feature); }
        function status(): string {
            return JSON.stringify({name: ShellProfile.name, title: ShellProfile.title, source: ShellProfile.source,
                choices: ShellProfile.names, comparing: ShellProfile.comparing, features: FeatureSettings.status(),
                colors: ShellProfile.name === "current" || ShellProfile.wallpaperColors ? "wallpaper" : "upstream", autoHide: ShellProfile.autoHide});
        }
    }

    IpcHandler {
        target: "shell"
        function close(): void { UiState.close(""); }
        function theme(): string {
            return JSON.stringify({path: Theme.palettePath,
                background: String(Theme.background), primary: String(Theme.primary),
                secondary: String(Theme.secondary), tertiary: String(Theme.tertiary),
                barHover: String(Theme.barHoverBackground), pickerSelected: String(Theme.pickerSelectedBackground),
                menuHover: String(Theme.menuHoverBackground), controlHover: String(Theme.controlHoverBackground),
                fonts: {bar: Theme.barFontFamily, ui: Theme.fontFamily, body: Theme.bodyFontFamily,
                    menu: Theme.menuFont.family,
                    title: Theme.titleFontFamily, display: Theme.displayFontFamily,
                    label: Theme.labelFont.family, tooltip: Theme.tooltipFont.family,
                    barBold: Theme.barFont.bold, uiBold: Theme.uiFont.bold},
                resolvedFonts: Theme.resolvedFonts,
                roles: {text: String(Theme.surfaceText), muted: String(Theme.surfaceVariantText),
                    panel: String(Theme.panelSurface), surface: String(Theme.surfaceContainer),
                    raised: String(Theme.surfaceContainerHigh), accentInk: String(Theme.primaryInk), barIcon: String(Theme.barIconColor), barUnreadIcon: String(Theme.barUnreadIconColor)},
                contrast: Theme.contrastReport()});
        }
        function motion(): string {
            return JSON.stringify({enabled: Theme.motionEnabled, pickerDuration: Theme.pickerDuration,
                fadeDuration: Theme.fadeDuration, workspaceDuration: Theme.workspaceDuration,
                controlDuration: Theme.controlDuration, compositor: Theme.compositorMotion,
                surfaces: UiState.motionStatus(), navigationHost: navigationWindow.status(), spacing: UiState.layoutStatus()});
        }
        function status(): string {
            return JSON.stringify({active: UiState.active, screen: UiState.screenName,
                notifications: root.notificationMode, profile: ShellProfile.name});
        }
    }
}
