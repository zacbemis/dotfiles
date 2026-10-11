//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark

import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Off by default: never contend with the existing SwayNC service.
    readonly property string notificationMode: Quickshell.env("QUICKSHELL_NOTIFICATIONS")
        || (Quickshell.env("QUICKSHELL_ENABLE_NOTIFICATIONS") === "1" ? "server" : "off")

    LazyLoader {
        active: Quickshell.env("QUICKSHELL_BAR") !== "0"
        Bar { notificationUi: notificationLoader.item }
    }
    Launcher {}
    WallpaperPicker {}

    LazyLoader {
        id: notificationLoader
        active: root.notificationMode === "preview" || root.notificationMode === "server"
        Notifications {}
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
                fonts: {bar: Theme.barFontFamily, ui: Theme.fontFamily, menu: Theme.menuFont.family,
                    barBold: Theme.barFont.bold, uiBold: Theme.uiFont.bold},
                resolvedFonts: Theme.resolvedFonts});
        }
        function motion(): string {
            return JSON.stringify({enabled: Theme.motionEnabled, pickerDuration: Theme.pickerDuration,
                fadeDuration: Theme.fadeDuration, workspaceDuration: Theme.workspaceDuration,
                controlDuration: Theme.controlDuration, compositor: Theme.compositorMotion,
                surfaces: UiState.motionStatus()});
        }
        function status(): string {
            return JSON.stringify({active: UiState.active, screen: UiState.screenName,
                notifications: root.notificationMode});
        }
    }
}
