import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

OverlayWindow {
    id: root

    property string title: ""
    property string statusText: ""
    property string actionText: "open"
    property string placeholder: "Search…"
    property int preferredWidth: 600
    property int preferredHeight: 460
    property int itemCount: 0
    property int selectedIndex: itemCount > 0 ? 0 : -1
    property alias query: search.text
    default property alias pickerContent: body.data
    signal activated()
    signal refreshRequested()
    property bool refreshable: false

    function handleKey(event): void {
        switch (event.key) {
        case Qt.Key_Down: select(selectedIndex + 1); break;
        case Qt.Key_Up: select(selectedIndex - 1); break;
        case Qt.Key_PageDown: select(selectedIndex + 6); break;
        case Qt.Key_PageUp: select(selectedIndex - 6); break;
        case Qt.Key_Return:
        case Qt.Key_Enter: if (selectedIndex >= 0) activated(); break;
        case Qt.Key_Escape: UiState.close(route); break;
        default: return;
        }
        event.accepted = true;
    }

    function select(index): void {
        selectedIndex = itemCount > 0 ? Math.max(0, Math.min(index, itemCount - 1)) : -1;
    }

    onItemCountChanged: select(selectedIndex)
    onQueryChanged: select(0)
    onOpenedChanged: {
        if (opened) {
            query = "";
            select(0);
            Qt.callLater(() => { if (root.opened) search.forceActiveFocus(); });
        }
    }

    Rectangle {
        anchors.centerIn: parent
        opacity: root.surfaceOpacity
        scale: root.surfaceScale
        transformOrigin: Item.Center
        width: Math.min(root.preferredWidth, parent.width - 32)
        height: Math.min(root.preferredHeight, parent.height - 48)
        radius: 14
        color: Theme.background
        border.color: Theme.outlineVariant
        Keys.onPressed: event => root.handleKey(event)
        // Block outside-click dismissal inside the card.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.width < 420 ? 16 : 24
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                ThemeText {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                }
                ThemeText {
                    text: root.statusText
                    color: Theme.surfaceVariantText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                ThemeButton {
                    visible: root.refreshable
                    text: ""
                    iconOnly: true
                    pickerStyle: true
                    onClicked: root.refreshRequested()
                    tooltip: "Rescan wallpapers"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: 8
                color: Theme.panelSurface
                border.color: search.activeFocus ? Theme.primary : Theme.outlineVariant

                RowLayout {
                    anchors.fill: parent
                    anchors { leftMargin: 12; rightMargin: 8; topMargin: 6; bottomMargin: 6 }
                    spacing: 10
                    GlyphIcon {
                        glyph: ""
                        color: Theme.surfaceVariantText
                        font: Theme.uiFont
                    }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: Theme.surfaceText
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.primaryText
                        font: Theme.uiFont
                        renderType: TextInput.NativeRendering
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        Keys.onPressed: event => root.handleKey(event)
                        ThemeText {
                            anchors.fill: parent
                            text: root.placeholder
                            color: Theme.surfaceVariantText
                            font: parent.font
                            visible: parent.text === ""
                        }
                    }
                    ThemeButton {
                        visible: search.text !== ""
                        text: ""
                        iconOnly: true
                        pickerStyle: true
                        tooltip: "Clear search"
                        onClicked: { search.text = ""; search.forceActiveFocus(); }
                    }
                }
            }

            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            ThemeText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "↑↓ navigate     ⏎ " + root.actionText + "     esc close"
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
