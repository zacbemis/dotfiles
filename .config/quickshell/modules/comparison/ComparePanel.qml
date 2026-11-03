import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import qs.theme

// Preview-only toolbar. Component choices live in the same selector as daily UI.
PanelWindow {
    id: root
    signal osdPreviewRequested()
    screen: UiState.screen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-compare-controls"
    anchors { bottom: true; right: true }
    margins { bottom: UiState.insets(screen).bottom; right: UiState.insets(screen).right }
    implicitWidth: Math.min(440, screen ? Math.max(0, screen.width - UiState.insets(screen).left - UiState.insets(screen).right) : 440)
    implicitHeight: toolbar.implicitHeight + 16
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.backgroundAlpha
        border.color: Theme.outlineVariant
        Flow {
            id: toolbar
            x: 8; y: 8
            width: parent.width - 16
            spacing: 4
            ThemeText { height: 32; verticalAlignment: Text.AlignVCenter; text: "Preview"; textRole: "body"; font.pixelSize: 11; color: Theme.surfaceVariantText }
            Repeater {
                model: ShellProfile.names
                ThemeButton {
                    required property string modelData
                    text: modelData === "current" ? "Current" : modelData === "enzo" ? "Enzo" : "MM-2103"
                    baseColor: ShellProfile.name === modelData ? Theme.activeBackground : Theme.transparentColor
                    onClicked: ShellProfile.select(modelData)
                }
            }
            ThemeButton { text: "󰒓"; iconOnly: true; tooltip: "Shell settings"; onClicked: ShellProfile.activate("settings") }
            ThemeButton { text: "󰂚"; iconOnly: true; tooltip: "Sample notification"; onClicked: ShellProfile.activate("sample") }
            ThemeButton { visible: FeatureSettings.osd !== "off"; text: "󰕾"; iconOnly: true; tooltip: "Preview OSD"; onClicked: root.osdPreviewRequested() }
        }
    }
}
