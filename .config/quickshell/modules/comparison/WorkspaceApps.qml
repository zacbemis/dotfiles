import QtQuick
import Quickshell
import qs.components

Row {
    id: root
    required property var workspace
    spacing: 3
    Repeater {
        model: root.workspace.toplevels
        Item {
            id: app
            required property var modelData
            width: 14
            height: 14
            readonly property string icon: {
                const id = modelData.wayland ? modelData.wayland.appId : modelData.lastIpcObject.class || "";
                const entry = id ? DesktopEntries.heuristicLookup(id) : null;
                return id ? Quickshell.iconPath(entry && entry.icon ? entry.icon : id, true) : "";
            }
            Image {
                id: image
                anchors.fill: parent
                source: app.icon
                sourceSize { width: 14; height: 14 }
                fillMode: Image.PreserveAspectFit
            }
            GlyphIcon { anchors.horizontalCenter: parent.horizontalCenter; y: (parent.height - height) / 2; glyph: ""; size: 13; color: Style.dim; visible: image.status !== Image.Ready }
        }
    }
}
