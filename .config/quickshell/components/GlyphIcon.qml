import QtQuick
import qs.theme

Item {
    id: root
    property string glyph: ""
    property color color: Theme.surfaceText
    // Bind fields separately: overriding only pixelSize must not reset the
    // family to Sans Serif (QML drops whole-font defaults on subfield writes).
    property font font
    font.family: Theme.iconFont.family
    font.pixelSize: Theme.iconFont.pixelSize
    font.weight: Theme.iconFont.weight
    font.hintingPreference: Theme.iconFont.hintingPreference
    property real size: font.pixelSize
    property real inkSize: size
    // Keep a consistent canvas for controls, but preserve the true advance
    // width in inline labels (battery and speaker glyphs are wider than 15px).
    property bool inlineLabel: false
    readonly property font renderFont: Qt.font({family: font.family, pixelSize: inkSize,
        weight: font.weight, italic: font.italic, hintingPreference: font.hintingPreference})
    implicitWidth: inlineLabel ? metrics.advanceWidth : size
    implicitHeight: size
    TextMetrics { id: metrics; text: root.glyph; font: root.renderFont }
    ThemeText {
        id: ink
        text: root.glyph
        textRole: "icon"
        font: root.renderFont
        color: root.color
        // Text's line box is not its visible ink. Center by the actual glyph
        // bounds so close/refresh/media icons cannot drift with font ascenders.
        x: (root.width - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x
        y: (root.height - metrics.tightBoundingRect.height) / 2 - metrics.tightBoundingRect.y - baselineOffset
    }
}
