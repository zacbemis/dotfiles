pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Match each old UI's typography, not Qt's platform defaults.
    readonly property string fontFamily: "Mononoki Nerd Font Propo"
    readonly property string barFontFamily: "SF Pro Display"
    readonly property string iconFontFamily: "Mononoki Nerd Font Propo"
    // Qt.font() ignores the unsupported `families` key without warning.
    // Use a real family, and render Nerd Font glyphs separately from text.
    readonly property font barFont: Qt.font({family: barFontFamily, pixelSize: 15, bold: true, hintingPreference: Font.PreferVerticalHinting})
    readonly property font barIconFont: Qt.font({family: "JetBrainsMono Nerd Font Propo", pixelSize: 15, bold: true, hintingPreference: Font.PreferVerticalHinting})
    readonly property font uiFont: Qt.font({family: fontFamily, pixelSize: 14, bold: true, hintingPreference: Font.PreferVerticalHinting})
    readonly property font menuFont: Qt.font({family: fontFamily, pixelSize: 15, bold: true, hintingPreference: Font.PreferVerticalHinting})

    // Logical pixels, shared by glyph canvases, image requests and hit targets.
    readonly property int barImageSize: 15
    readonly property int launcherIconSize: 24 // Rofi element-icon size
    readonly property int controlIconSize: 16
    readonly property int notificationIconSize: 50 // SwayNC notification-icon-size
    readonly property int barPadding: 16 // GTK's 15px padding + 1px border
    readonly property int moduleSpacing: 8
    readonly property int traySpacing: 8
    readonly property int workspaceHeight: 18
    readonly property int workspaceDuration: motionEnabled ? 300 : 0
    readonly property int controlDuration: motionEnabled ? 200 : 0
    readonly property var cssEaseInOut: [0.42, 0, 0.58, 1, 1, 1]
    readonly property var cssEase: [0.25, 0.1, 0.25, 1, 1, 1]
    property var compositorMotion: ({enabled: true, pickerDuration: 800, fadeDuration: 180,
        pickerCurve: [0, 0.75, 0.15, 1, 1, 1], fadeCurve: [0.05, 0.8, 0.1, 0.97, 1, 1]})
    readonly property bool motionEnabled: Quickshell.env("QUICKSHELL_REDUCED_MOTION") !== "1" && compositorMotion.enabled
    readonly property int pickerDuration: motionEnabled ? compositorMotion.pickerDuration : 0
    readonly property int fadeDuration: motionEnabled ? compositorMotion.fadeDuration : 0
    function acceptMotion(text): void {
        try {
            const data = JSON.parse(text), animations = data.animations[0], curves = data.animations[1];
            const inherited = names => names.map(name => animations.find(entry => entry.name === name))
                .find(entry => entry && entry.overridden);
            const layers = inherited(["layersIn", "layers", "global"]);
            const fade = inherited(["fadeLayersIn", "fadeLayers", "fade", "global"]);
            const curve = (entry, fallback) => {
                const found = curves.find(curve => curve.name === entry.bezier);
                return found ? [found.X0, found.Y0, found.X1, found.Y1, 1, 1] : fallback;
            };
            if (layers && fade) compositorMotion = {enabled: data.option.bool !== false
                    && data.option.int !== 0 && layers.enabled && fade.enabled,
                pickerDuration: Math.round(layers.speed * 100), fadeDuration: Math.round(fade.speed * 100),
                pickerCurve: curve(layers, [0, 0.75, 0.15, 1, 1, 1]),
                fadeCurve: curve(fade, [0.05, 0.8, 0.1, 0.97, 1, 1])};
        } catch (error) { /* outside Hyprland, retain the reference defaults */ }
    }
    Process {
        id: motionReader
        command: ["sh", "-c", "printf '{\"option\":'; hyprctl getoption animations:enabled -j; printf ',\"animations\":'; hyprctl animations -j; printf '}'"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.acceptMotion(text) }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: if (!motionReader.running) motionReader.running = true }

    readonly property var resolvedFonts: ({
        bar: fontDetails(barProbe), ui: fontDetails(uiProbe), menu: fontDetails(menuProbe),
        barIcon: fontDetails(iconProbe)
    })
    function fontDetails(probe) {
        return {family: probe.fontInfo.family, style: probe.fontInfo.styleName,
            pixelSize: probe.fontInfo.pixelSize, bold: probe.fontInfo.bold};
    }
    Text { id: barProbe; text: "0123456789 ABC"; font: root.barFont }
    Text { id: uiProbe; text: "Applications"; font: root.uiFont }
    Text { id: menuProbe; text: "Available networks"; font: root.menuFont }
    Text { id: iconProbe; text: "󰕾"; font: root.barIconFont }

    // Pywal's wal-post.sh symlinks this generated palette for Waybar. Matugen's
    // optional path writes the same file. Never regenerate or overwrite either.
    readonly property string palettePath: Quickshell.env("QUICKSHELL_PALETTE")
        || (Quickshell.env("HOME") || "") + "/.config/waybar/colors/colors.css"
    property var palette: ({})

    function acceptPalette(text): void {
        const result = {};
        const pattern = /@define-color\s+([\w-]+)\s+([^;]+);/g;
        let match;
        while ((match = pattern.exec(text)) !== null) result[match[1]] = match[2].trim();
        // Keep the last good palette during partial writes/missing symlink targets.
        if (result.background && result.primary && result.on_surface) palette = result;
    }
    function cssColor(name, fallback) {
        let value = palette[name];
        for (let i = 0; value && value.startsWith("@") && i < 16; ++i) value = palette[value.slice(1)];
        return value && !value.startsWith("@") ? value : fallback;
    }
    FileView {
        id: paletteFile
        path: root.palettePath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.acceptPalette(text())
    }
    // File watchers can lose atomic replacements or a recreated symlink. Reopen
    // the configured path as a recovery fallback; this also discovers new files.
    Timer { interval: 2000; running: true; repeat: true; onTriggered: paletteFile.reload() }
    Component.onCompleted: acceptPalette(paletteFile.text())

    function fileUrl(path): string {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    function alpha(color, opacity): color { return Qt.rgba(color.r, color.g, color.b, opacity); }
    function luminance(color): real {
        const linear = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
    }
    function contrast(a, b): real {
        const first = luminance(a), second = luminance(b);
        return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
    }
    function foregroundFor(background, preferred): color {
        if (preferred && contrast(background, preferred) >= 4.5) return preferred;
        return contrast(background, primaryText) > contrast(background, surfaceText) ? primaryText : surfaceText;
    }

    readonly property color background: cssColor("background", "#202124")
    readonly property color backgroundAlpha: alpha(background, 0.95)
    readonly property color surfaceContainer: cssColor("surface_container", "#2b2d31")
    readonly property color surfaceContainerHigh: cssColor("surface_container_high", "#35373c")
    readonly property color panelSurface: Qt.tint(background, alpha(surfaceText, 0.06))
    readonly property color surfaceText: cssColor("on_surface", "#f1f3f4")
    readonly property color surfaceVariantText: cssColor("on_surface_variant", "#c4c7c5")
    readonly property color outlineVariant: cssColor("outline_variant", "#565a61")
    readonly property color disabledText: alpha(surfaceText, 0.45)

    readonly property color primary: cssColor("primary", "#a8c7fa")
    readonly property color primaryFixed: cssColor("primary_fixed", primary)
    readonly property color batteryWarning: primaryFixed
    readonly property color primaryText: cssColor("on_primary", "#0b1d33")
    readonly property color primaryContainer: cssColor("primary_container", "#244a73")
    readonly property color secondary: cssColor("secondary", "#b6c5e2")
    readonly property color secondaryText: cssColor("on_secondary", "#1a304f")
    readonly property color tertiary: cssColor("tertiary", "#f4b8c8")
    readonly property color tertiaryText: cssColor("on_tertiary", "#492532")
    readonly property color error: cssColor("error", "#ffb4ab")
    readonly property color errorText: cssColor("on_error", "#690005")
    readonly property color inversePrimary: cssColor("inverse_primary", "#4f6090")

    // UI roles from Waybar, Rofi, SwayNC and GTK's accent colors. These aliases
    // are the single place to customize interactions; all derive from wallpaper.
    readonly property color barHoverBackground: primaryContainer
    readonly property color barHoverText: surfaceText
    readonly property color pickerSelectedBackground: primary
    readonly property color pickerSelectedText: primaryText
    readonly property color controlBackground: inversePrimary
    readonly property color controlText: primary
    // Pywal's inverse_primary can be light, unlike a dark Material container.
    // Keep the old background/hover roles but select readable palette text.
    readonly property color controlSurfaceText: foregroundFor(controlBackground, surfaceText)
    readonly property color controlHoverBackground: alpha(tertiary, 0.7)
    readonly property color controlPressedBackground: secondary
    readonly property color menuHoverBackground: primary
    readonly property color menuHoverText: primaryText
    readonly property color notificationIdle: "#ffffff" // Waybar custom/notification.none
    readonly property color notificationSurface: panelSurface
    readonly property color notificationText: surfaceText

    readonly property color scrim: "#99000000"
    readonly property color transparentColor: "#00000000"
}
