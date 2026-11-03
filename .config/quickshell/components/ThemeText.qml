import QtQuick
import qs.theme

Text {
    // Separate fields retain the chosen family when delegates override size or
    // weight. Bind weight explicitly so role changes retain the correct face.
    property string textRole: "label"
    readonly property font roleFont: Theme.fontForRole(textRole)
    font.family: roleFont.family
    font.pixelSize: roleFont.pixelSize
    font.weight: roleFont.weight
    font.hintingPreference: roleFont.hintingPreference
    // Match GTK/Pango's hinted glyph rendering, not distance-field text.
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Theme.surfaceText
    textFormat: Text.PlainText
}
