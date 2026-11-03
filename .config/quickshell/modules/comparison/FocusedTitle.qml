// SPDX-License-Identifier: MIT
// Adapted from EnzoNotNice/quickshell-bar, WindowTitle.qml at 68d721985be796d2d9a344f73a8b3ae5495a738d.
// See vendor/enzo/upstream/LICENSE. Use the current activeToplevel API and elide
// to the available monitor width instead of truncating to forty characters.
import QtQuick
import Quickshell.Hyprland
import qs.components

ThemeText {
    readonly property string rawTitle: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
    text: rawTitle.replace(/ - (Mozilla Firefox|zsh|Alacritty)$/, "")
    color: Style.dim
    textRole: "bar"
    font.pixelSize: Style.font.pixelSize
    elide: Text.ElideRight
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
}
