pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "ColorMath.js" as Colors

Singleton {
    id: root

    // One text face throughout Quickshell: bold headings/bars, regular UI.
    // Icon glyphs remain separate; terminal monospace choices do not leak in.
    readonly property string fontFamily: "SF Pro Display"
    readonly property string bodyFontFamily: fontFamily
    readonly property string titleFontFamily: fontFamily
    readonly property string displayFontFamily: titleFontFamily
    readonly property string barFontFamily: displayFontFamily
    readonly property string iconFontFamily: "Symbols Nerd Font"
    // Qt.font() ignores the unsupported `families` key without warning.
    // Use a real family, and render Nerd Font glyphs separately from text.
    readonly property font barFont: Qt.font({family: barFontFamily, pixelSize: 15, weight: Font.Bold, hintingPreference: Font.PreferVerticalHinting})
    readonly property font barIconFont: Qt.font({family: "JetBrainsMono Nerd Font Propo", pixelSize: 15, weight: Font.Bold, hintingPreference: Font.PreferVerticalHinting})
    readonly property font titleFont: Qt.font({family: titleFontFamily, pixelSize: 18, weight: Font.Bold, hintingPreference: Font.PreferVerticalHinting})
    readonly property font displayFont: Qt.font({family: displayFontFamily, pixelSize: 14, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    readonly property font labelFont: Qt.font({family: displayFontFamily, pixelSize: 14, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    readonly property font uiFont: labelFont
    readonly property font bodyFont: Qt.font({family: bodyFontFamily, pixelSize: 14, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    readonly property font iconFont: Qt.font({family: iconFontFamily, pixelSize: 14, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    readonly property font menuFont: Qt.font({family: displayFontFamily, pixelSize: 15, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    readonly property font tooltipFont: Qt.font({family: bodyFontFamily, pixelSize: 15, weight: Font.Normal, hintingPreference: Font.PreferVerticalHinting})
    function fontForRole(role) {
        return role === "title" ? titleFont : role === "display" ? displayFont
            : role === "bar" ? barFont : role === "menu" ? menuFont
            : role === "body" ? bodyFont : role === "tooltip" ? tooltipFont
            : role === "icon" ? iconFont : labelFont;
    }

    // Logical pixels, shared by glyph canvases, image requests and hit targets.
    readonly property int barImageSize: 15
    // Calibrated against the actual 15px tray artwork at desktop scale.
    // Balance visible width/ink area, not height alone: batteries are horizontal.
    // Painted sizes are independent of each profile's existing layout slots.
    readonly property int barSoundPaintSize: 18
    readonly property int barBatteryPaintSize: 15
    readonly property int barSettingsPaintSize: 15
    function barStatusPaintSize(kind, fallback) { return kind === "volume" ? barSoundPaintSize : kind === "battery" ? barBatteryPaintSize : fallback; }
    readonly property int launcherIconSize: 24
    readonly property int controlIconSize: 16
    readonly property int notificationIconSize: 50
    readonly property int barPadding: 16 // GTK's 15px padding + 1px border
    readonly property int moduleSpacing: 8
    readonly property int traySpacing: 8
    readonly property int workspaceHeight: 18
    readonly property int workspaceDuration: motionEnabled ? 300 : 0
    readonly property int controlDuration: motionEnabled ? 200 : 0
    readonly property var cssEaseInOut: [0.42, 0, 0.58, 1, 1, 1]
    readonly property var cssEase: [0.25, 0.1, 0.25, 1, 1, 1]
    readonly property var compositorMotion: MotionService.settings
    readonly property bool motionEnabled: Quickshell.env("QUICKSHELL_REDUCED_MOTION") !== "1" && compositorMotion.enabled
    readonly property int pickerDuration: motionEnabled ? compositorMotion.pickerDuration : 0
    readonly property int fadeDuration: motionEnabled ? compositorMotion.fadeDuration : 0
    readonly property var resolvedFonts: ({
        bar: fontDetails(barProbe), ui: fontDetails(uiProbe), body: fontDetails(bodyProbe),
        menu: fontDetails(menuProbe),
        title: fontDetails(titleProbe), display: fontDetails(displayProbe), label: fontDetails(labelProbe),
        tooltip: fontDetails(tooltipProbe), barIcon: fontDetails(iconProbe)
    })
    function fontDetails(probe) {
        return {family: probe.fontInfo.family, style: probe.fontInfo.styleName,
            pixelSize: probe.fontInfo.pixelSize, bold: probe.fontInfo.bold};
    }
    // Inspect rendered items, not merely a font copied into a separate probe.
    // Called only by diagnostic IPC/tests, never on an animation/render timer.
    function auditText(item) {
        const result = [];
        function visit(node) {
            if (!node || node.visible === false || node.sensitive === true) return;
            if (node.fontInfo && node.text !== undefined && String(node.text).length) {
                result.push(Object.assign({text: String(node.text).slice(0, 96),
                    role: node.textRole || "unassigned", requested: node.font.family}, fontDetails(node)));
            }
            if (node.children) for (const child of node.children) visit(child);
        }
        visit(item);
        return result;
    }
    Text { id: barProbe; text: "0123456789 ABC"; font: root.barFont }
    Text { id: uiProbe; text: "Interface labels"; font: root.uiFont }
    Text { id: bodyProbe; text: "Supporting text"; font: root.bodyFont }
    Text { id: titleProbe; text: "Applications"; font: root.titleFont }
    Text { id: displayProbe; text: "12:34 Wallpaper"; font: root.displayFont }
    Text { id: menuProbe; text: "Available networks"; font: root.menuFont }
    Text { id: labelProbe; text: "Volume Apply Wallpapers"; font: root.labelFont }
    Text { id: tooltipProbe; text: "Scroll to adjust"; font: root.tooltipFont }
    Text { id: iconProbe; text: "󰕾"; font: root.barIconFont }

    // Canonical Pywal/Matugen output, watched read-only.
    readonly property string palettePath: Quickshell.env("QUICKSHELL_PALETTE")
        || (Quickshell.env("HOME") || "") + "/.config/quickshell/colors.css"
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
    function channels(value) {
        const color = typeof value === "string" ? Qt.color(value) : value;
        return [color.r, color.g, color.b, color.a];
    }
    function fromChannels(value): color { return Qt.rgba(value[0], value[1], value[2], value[3]); }
    function opaque(value): color { return fromChannels(Colors.rgb(channels(value))); }
    function mix(first, second, amount): color { return fromChannels(Colors.mix(channels(first), channels(second), amount)); }
    function luminance(value): real { return Colors.luminance(channels(value)); }
    function backgroundTargets(value) {
        const color = channels(value);
        // Translucent panels can cover any wallpaper/app. Test both extremes,
        // rather than pretending alpha does not affect the rendered contrast.
        return color[3] < 1 ? [Colors.rgb(Colors.over(color, [0, 0, 0, 1])),
            Colors.rgb(Colors.over(color, [1, 1, 1, 1]))] : [Colors.rgb(color)];
    }
    function contrast(foreground, background): real {
        return Math.min(...backgroundTargets(background).map(bg =>
            Colors.contrast(Colors.rgb(Colors.over(channels(foreground), bg)), bg)));
    }
    function readableOn(seed, backgrounds, minimum): color {
        const targets = [];
        for (const bg of backgrounds) targets.push(...backgroundTargets(bg));
        return fromChannels(Colors.readable(channels(seed), targets, minimum));
    }
    function foregroundFor(background, preferred, minimum): color {
        return readableOn(preferred || surfaceText, [background], minimum === undefined ? 4.5 : minimum);
    }
    function disabledFor(background): color {
        return foregroundFor(background, mix(opaque(background), foregroundFor(background, surfaceText), 0.5), 3);
    }
    function tonalSurface(hint, separation): color {
        return fromChannels(Colors.surface(channels(background), channels(hint), separation));
    }

    // Preserve extracted accent seeds. Rendered roles below may change tone,
    // but never regenerate the palette or replace its hue with a preset theme.
    readonly property color background: opaque(cssColor("background", "#202124"))
    readonly property color backgroundAlpha: alpha(background, Colors.panelOpacity(channels(background)))
    readonly property color primary: cssColor("primary", "#a8c7fa")
    readonly property color secondary: cssColor("secondary", "#b6c5e2")
    readonly property color tertiary: cssColor("tertiary", "#f4b8c8")
    readonly property color primaryContainer: cssColor("primary_container", primary)
    readonly property color inversePrimary: cssColor("inverse_primary", primary)

    // Many Pywal palettes give every raised surface the same bright color.
    // Re-tone those wallpaper seeds into a restrained, ordered surface ladder.
    readonly property color panelSurface: tonalSurface(cssColor("surface_container_low", primary), 1.12)
    readonly property color surfaceContainer: tonalSurface(cssColor("surface_container", primary), 1.32)
    readonly property color surfaceContainerHigh: tonalSurface(cssColor("surface_container_high", primary), 1.58)
    readonly property var textSurfaces: [background, panelSurface, surfaceContainer, surfaceContainerHigh, backgroundAlpha]
    readonly property color sourceSurfaceText: cssColor("on_surface", "#f1f3f4")
    readonly property color sourceVariantText: cssColor("on_surface_variant", sourceSurfaceText)
    readonly property color surfaceText: readableOn(sourceSurfaceText, textSurfaces, 7)
    readonly property color surfaceVariantText: readableOn(sourceVariantText, textSurfaces, 4.5)
    readonly property color outlineVariant: readableOn(cssColor("outline_variant", primary), textSurfaces, 3)
    readonly property color disabledText: readableOn(mix(background, surfaceText, 0.5), textSurfaces, 3)
    readonly property color primaryInk: readableOn(primary, textSurfaces, 4.5)
    readonly property color secondaryInk: readableOn(secondary, textSurfaces, 4.5)
    readonly property color tertiaryInk: readableOn(tertiary, textSurfaces, 4.5)
    readonly property color inversePrimaryInk: readableOn(inversePrimary, textSurfaces, 4.5)
    readonly property color primaryFixed: readableOn(cssColor("primary_fixed", primary), textSurfaces, 4.5)
    readonly property color batteryWarning: primaryFixed
    readonly property color error: readableOn(cssColor("error", "#ffb4ab"), textSurfaces, 4.5)
    readonly property color primaryText: foregroundFor(primary, cssColor("on_primary", background))
    readonly property color secondaryText: foregroundFor(secondary, cssColor("on_secondary", background))
    readonly property color tertiaryText: foregroundFor(tertiary, cssColor("on_tertiary", background))
    readonly property color errorText: foregroundFor(error, cssColor("on_error", background))

    readonly property color barHoverBackground: tonalSurface(primaryContainer, 1.8)
    readonly property color barHoverText: foregroundFor(barHoverBackground, surfaceText)
    // Near-white wallpaper tint for ordinary status icons. Only unseen
    // notifications use the previous, darker wallpaper-primary accent.
    readonly property color barIconSeed: mix(primary, "#ffffff", 0.85)
    readonly property color barIconColor: readableOn(barIconSeed, textSurfaces.concat([barHoverBackground]), 4.5)
    readonly property color barUnreadIconColor: readableOn(primary, textSurfaces.concat([barHoverBackground]), 4.5)
    readonly property color pickerSelectedBackground: readableOn(primary, [background, panelSurface], 3)
    readonly property color pickerSelectedText: foregroundFor(pickerSelectedBackground, cssColor("on_primary", background))
    readonly property color activeBackground: readableOn(secondary, [background, panelSurface, surfaceContainer], 3)
    readonly property color activeText: foregroundFor(activeBackground, cssColor("on_secondary", background))
    readonly property color controlBackground: surfaceContainer
    readonly property color controlText: surfaceText
    readonly property color controlSurfaceText: surfaceText
    readonly property color controlHoverBackground: tonalSurface(primary, 1.7)
    readonly property color controlPressedBackground: tonalSurface(secondary, 1.92)
    readonly property color menuHoverBackground: pickerSelectedBackground
    readonly property color menuHoverText: pickerSelectedText
    readonly property color notificationIdle: surfaceText
    readonly property color notificationSurface: panelSurface
    readonly property color notificationText: surfaceText
    readonly property color focusRing: readableOn(primary, textSurfaces, 3)
    readonly property color sliderTrack: readableOn(cssColor("outline_variant", primary), [background, panelSurface, backgroundAlpha], 3)
    readonly property color sliderFill: foregroundFor(sliderTrack, primary, 3)

    function contrastReport() {
        const pairs = [];
        const add = (name, foreground, background, minimum) => pairs.push({name: name,
            foreground: String(foreground), background: String(background),
            ratio: contrast(foreground, background), minimum: minimum});
        for (const [name, bg] of [["base", background], ["panel", panelSurface], ["surface", surfaceContainer],
                ["raised", surfaceContainerHigh], ["translucent", backgroundAlpha]]) {
            add("text/" + name, surfaceText, bg, 4.5);
            add("muted/" + name, surfaceVariantText, bg, 4.5);
            add("disabled/" + name, disabledText, bg, 3);
            add("accent/" + name, primaryInk, bg, 4.5);
            add("border/" + name, outlineVariant, bg, 3);
        }
        add("selection/text", pickerSelectedText, pickerSelectedBackground, 4.5);
        add("selection/boundary", pickerSelectedBackground, panelSurface, 3);
        add("active/text", activeText, activeBackground, 4.5);
        add("active/boundary", activeBackground, surfaceContainer, 3);
        add("menu/text", menuHoverText, menuHoverBackground, 4.5);
        add("bar/hover", barHoverText, barHoverBackground, 4.5);
        for (const [name, bg] of [["base", background], ["surface", surfaceContainer], ["hover", barHoverBackground]]) {
            add("bar/icon-" + name, barIconColor, bg, 4.5);
            add("bar/unread-icon-" + name, barUnreadIconColor, bg, 4.5);
        }
        add("slider/fill-track", sliderFill, sliderTrack, 3);
        add("slider/track-base", sliderTrack, background, 3);
        add("slider/track-panel", sliderTrack, panelSurface, 3);
        for (const [name, bg] of [["normal", controlBackground], ["hover", controlHoverBackground], ["pressed", controlPressedBackground]]) {
            add("control/" + name, foregroundFor(bg, controlText), bg, 4.5);
            add("control-disabled/" + name, disabledFor(bg), bg, 3);
        }
        return pairs;
    }

    readonly property color scrim: "#99000000"
    readonly property color transparentColor: "#00000000"
}
