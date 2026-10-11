import QtQuick

Text {
    // Separate field bindings survive a delegate overriding just pixelSize.
    // A whole-font binding was dropped by those overrides, restoring FreeSans.
    font.family: Theme.uiFont.family
    font.pixelSize: Theme.uiFont.pixelSize
    font.bold: Theme.uiFont.bold
    font.hintingPreference: Theme.uiFont.hintingPreference
    // Match GTK/Pango's hinted glyph rendering, not distance-field text.
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Theme.surfaceText
    textFormat: Text.PlainText
}
