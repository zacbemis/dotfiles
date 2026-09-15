pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Read the palette generated for the existing Waybar theme without changing
// the Pywal/Matugen pipeline. The fallbacks keep the shell usable before the
// generated file exists.

QtObject {
    readonly property string fontFamily: "SF Pro Display"
    readonly property string iconFontFamily: "Mononoki Nerd Font Propo"

    readonly property QtObject generatedPalette: FileView {
        path: (Quickshell.env("HOME") || "") + "/.config/waybar/colors/colors.css"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }

    function cssColor(name, fallback) {
        const prefix = "@define-color " + name + " ";
        const lines = generatedPalette.text().split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (line.indexOf(prefix) === 0)
                return line.slice(prefix.length).replace(/;.*$/, "").trim();
        }
        return fallback;
    }

    readonly property color background: cssColor("background", "#202124")
    readonly property color backgroundAlpha: Qt.rgba(background.r, background.g, background.b, 0.95)
    readonly property color surfaceContainer: cssColor("surface_container", "#2b2d31")
    readonly property color surfaceContainerHigh: cssColor("surface_container_high", "#35373c")
    readonly property color surfaceText: cssColor("on_surface", "#f1f3f4")
    readonly property color surfaceVariantText: cssColor("on_surface_variant", "#c4c7c5")
    readonly property color outlineVariant: cssColor("outline_variant", "#565a61")

    readonly property color primary: cssColor("primary", "#a8c7fa")
    readonly property color primaryFixed: cssColor("primary_fixed", primary)
    readonly property color primaryText: cssColor("on_primary", "#0b1d33")
    readonly property color primaryContainer: cssColor("primary_container", "#244a73")
    readonly property color secondary: cssColor("secondary", "#b6c5e2")
    readonly property color secondaryText: cssColor("on_secondary", "#1a304f")
    readonly property color tertiary: cssColor("tertiary", "#f4b8c8")
    readonly property color tertiaryText: cssColor("on_tertiary", "#492532")
    readonly property color error: cssColor("error", "#ffb4ab")
    readonly property color errorText: cssColor("on_error", "#690005")
    readonly property color inversePrimary: cssColor("inverse_primary", "#4f6090")

    // The generated semantic scrim is opaque; overlays need a translucent layer.
    readonly property color scrim: "#99000000"
    readonly property color transparentColor: "#00000000"
}
