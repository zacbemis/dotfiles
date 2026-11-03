pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.theme

// Native upstream bar colors by default; the common overlays keep our Theme.
Singleton {
    readonly property bool enzo: ShellProfile.name === "enzo"
    readonly property color background: ShellProfile.wallpaperColors ? Theme.backgroundAlpha
        : enzo ? "#d91e1e2e" : "#16181c"
    readonly property color border: ShellProfile.wallpaperColors ? Theme.outlineVariant
        : enzo ? "#33cdd6f4" : "#2a2a2e"
    readonly property var textSurfaces: [background, surface]
    readonly property color text: Theme.readableOn(ShellProfile.wallpaperColors ? Theme.surfaceText
        : enzo ? "#cdd6f4" : "#fcfcfc", textSurfaces, 4.5)
    readonly property color dim: Theme.readableOn(ShellProfile.wallpaperColors ? Theme.surfaceVariantText
        : enzo ? "#a6adc8" : "#909090", textSurfaces, 4.5)
    readonly property color surface: ShellProfile.wallpaperColors ? Theme.surfaceContainer
        : enzo ? "#45475a" : "#26262a"
    readonly property color accent: ShellProfile.wallpaperColors ? Theme.pickerSelectedBackground
        : enzo ? "#89b4fa" : "#ffffff"
    readonly property color accentText: Theme.foregroundFor(accent, ShellProfile.wallpaperColors ? Theme.pickerSelectedText : "#16181c")
    readonly property color media: Theme.readableOn(ShellProfile.wallpaperColors ? Theme.tertiaryInk
        : enzo ? "#cba6f7" : text, textSurfaces, 4.5)
    readonly property color icon: ShellProfile.wallpaperColors ? Theme.barIconColor
        : Theme.readableOn(Theme.barIconSeed, textSurfaces, 4.5)
    readonly property color unreadIcon: ShellProfile.wallpaperColors ? Theme.barUnreadIconColor
        : Theme.readableOn(Theme.primary, textSurfaces, 4.5)
    readonly property color audio: icon
    // Normalize primary bar text to our display role, not upstream platform
    // defaults. Profile-specific colors, geometry and sizes stay unchanged.
    readonly property font font: Qt.font({family: Theme.barFont.family,
        pixelSize: enzo ? 14 : 13, weight: Theme.barFont.weight,
        hintingPreference: Font.PreferVerticalHinting})
    readonly property int duration: Theme.motionEnabled ? (enzo ? 200 : 140) : 0
}
