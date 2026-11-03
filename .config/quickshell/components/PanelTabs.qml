import QtQuick
import qs.services
import qs.theme

Flickable {
    id: root
    implicitHeight: 32
    contentWidth: tabs.implicitWidth
    contentHeight: 32
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    function revealCurrent(): void {
        const index = ShellNavigation.items.findIndex(item => item.key === ShellNavigation.current);
        const button = buttons.itemAt(index);
        if (!button) return;
        if (button.x < contentX) contentX = button.x;
        else if (button.x + button.width > contentX + width) contentX = button.x + button.width - width;
        contentX = Math.max(0, Math.min(contentX, Math.max(0, contentWidth - width)));
    }
    onWidthChanged: Qt.callLater(revealCurrent)
    onContentWidthChanged: Qt.callLater(revealCurrent)
    Connections { target: ShellNavigation; function onCurrentChanged() { Qt.callLater(root.revealCurrent); } }
    Row {
        id: tabs
        spacing: 4
        Repeater {
            id: buttons
            model: ShellNavigation.items
            ThemeButton {
                required property var modelData
                text: modelData.label
                Accessible.role: Accessible.PageTab
                Accessible.selected: ShellNavigation.current === modelData.key
                baseColor: ShellNavigation.current === modelData.key ? Theme.activeBackground : Theme.transparentColor
                onClicked: ShellNavigation.select(modelData.key)
            }
        }
        ThemeText {
            visible: NotificationService.mode !== "server"
            text: "Preview"
            textRole: "body"
            font.pixelSize: 11
            color: Theme.surfaceVariantText
            height: 32
            leftPadding: 12
            verticalAlignment: Text.AlignVCenter
        }
    }
}
