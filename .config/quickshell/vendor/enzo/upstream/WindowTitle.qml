import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

RowLayout {
    spacing: 8

    property string rawTitle: Hyprland.focusedWindow?.title ?? ""
    
    property string titleIcon: {
        var t = rawTitle
        if (t === "") return ""
        if (t.match(/.* - Mozilla Firefox$/)) return "󰈹"
        if (t.match(/.* - zsh$/)) return ""
        if (t.match(/.* - Alacritty$/)) return ""
        return "󰣆" // Default window icon
    }
    
    property string titleTextContent: {
        var t = rawTitle
        if (t === "") return ""
        if (t.match(/.* - Mozilla Firefox$/)) t = t.replace(/ - Mozilla Firefox$/, "")
        if (t.match(/.* - zsh$/)) t = t.replace(/ - zsh$/, "")
        if (t.match(/.* - Alacritty$/)) t = t.replace(/ - Alacritty$/, "")
        if (t.length > 40) return t.substring(0, 37) + "..."
        return t
    }

    Text {
        text: titleIcon
        visible: titleIcon !== ""
        color: "#a6adc8"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
    }
    Text {
        text: titleTextContent
        visible: titleTextContent !== ""
        color: "#a6adc8"
        font.family: "sans-serif"
        font.pixelSize: 14
        font.weight: Font.Medium
    }
}
