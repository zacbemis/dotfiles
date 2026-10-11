import QtQuick

Item {
    id: root
    property string glyph: ""
    property color color: Theme.surfaceText
    property font font: Theme.uiFont
    property real size: font.pixelSize
    // Keep a consistent canvas for controls, but preserve the true advance
    // width in inline labels (battery and speaker glyphs are wider than 15px).
    property bool inlineLabel: false
    readonly property font renderFont: Qt.font({family: font.family, pixelSize: size,
        bold: font.bold, italic: font.italic, hintingPreference: font.hintingPreference})
    implicitWidth: inlineLabel ? metrics.advanceWidth : size
    implicitHeight: size
    TextMetrics { id: metrics; text: root.glyph; font: root.renderFont }
    ThemeText {
        id: ink
        text: root.glyph
        font: root.renderFont
        color: root.color
        // Text's line box is not its visible ink. Center by the actual glyph
        // bounds so close/refresh/media icons cannot drift with font ascenders.
        x: (root.width - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x
        y: (root.height - metrics.tightBoundingRect.height) / 2 - metrics.tightBoundingRect.y - baselineOffset
    }
}
