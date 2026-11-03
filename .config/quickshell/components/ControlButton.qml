import QtQuick
import qs.theme

// Explicit action affordance for system controls, without changing bar styling.
ThemeButton {
    id: root
    property bool quiet: false
    baseColor: quiet ? Theme.transparentColor : Theme.surfaceContainerHigh
    outlined: !quiet
    HoverHandler { enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
}
