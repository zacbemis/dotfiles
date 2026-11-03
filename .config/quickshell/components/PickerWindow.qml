import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.theme

OverlayWindow {
    id: root
    navigationPanel: true
    property string title: ""
    property string statusText: ""
    property string actionText: "open"
    property string placeholder: "Search…"
    property int cardRadius: 14
    property int itemCount: 0
    property int navigationColumns: 1
    property var controller: null
    property var modeChoices: []
    property string activeMode: ""
    property bool wrapNavigation: false
    signal modeChosen(string mode)
    function focusSearch(): void { Qt.callLater(() => { search.forceActiveFocus(); search.cursorPosition = search.text.length; }); }
    function moveSelection(delta): void {
        const next = selectedIndex + delta;
        select(wrapNavigation && itemCount ? ((next % itemCount) + itemCount) % itemCount : next);
    }
    Connections {
        target: root.controller
        function onQueryChanged() { if (root.query !== root.controller.query) root.query = root.controller.query; }
        function onSelectedIndexChanged() { if (root.selectedIndex !== root.controller.selectedIndex) root.selectedIndex = root.controller.selectedIndex; }
    }
    property int selectedIndex: itemCount > 0 ? 0 : -1
    property alias query: search.text
    default property alias pickerContent: resultBody.data
    signal activated()
    signal refreshRequested()
    property bool refreshable: false

    function handleKey(event): void {
        if (((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier))
                || ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && (event.modifiers & Qt.ShiftModifier))) {
            const back = event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || Boolean(event.modifiers & Qt.ShiftModifier);
            ShellNavigation.step(back ? -1 : 1);
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_Down: moveSelection(navigationColumns); break;
        case Qt.Key_Up: moveSelection(-navigationColumns); break;
        case Qt.Key_Left: if (navigationColumns === 1) return; select(selectedIndex - 1); break;
        case Qt.Key_Right: if (navigationColumns === 1) return; select(selectedIndex + 1); break;
        case Qt.Key_Home: if (navigationColumns === 1) return; select(0); break;
        case Qt.Key_End: if (navigationColumns === 1) return; select(itemCount - 1); break;
        case Qt.Key_PageDown: select(selectedIndex + Math.max(6, navigationColumns * 3)); break;
        case Qt.Key_PageUp: select(selectedIndex - Math.max(6, navigationColumns * 3)); break;
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
    onQueryChanged: {
        select(0);
        if (controller && controller.query !== query) controller.query = query;
    }
    onOpenedChanged: {
        if (opened) {
            query = "";
            select(0);
            Qt.callLater(() => { if (root.opened) search.forceActiveFocus(); });
        }
    }
    Item {
        anchors.fill: parent
        Keys.onPressed: event => root.handleKey(event)
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 8
                    color: Theme.panelSurface
                    border.color: search.activeFocus ? Theme.focusRing : Theme.outlineVariant
                    RowLayout {
                        anchors.fill: parent
                        anchors { leftMargin: 12; rightMargin: 8; topMargin: 6; bottomMargin: 6 }
                        spacing: 10
                        GlyphIcon { glyph: ""; color: Theme.surfaceVariantText; font: Theme.iconFont }
                        TextInput {
                            id: search
                            property string textRole: "label"
                            Layout.fillWidth: true
                            color: Theme.surfaceText
                            selectionColor: Theme.pickerSelectedBackground
                            selectedTextColor: Theme.pickerSelectedText
                            font: Theme.labelFont
                            renderType: TextInput.NativeRendering
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true
                            activeFocusOnTab: true
                            Keys.onPressed: event => root.handleKey(event)
                            ThemeText {
                                anchors.fill: parent
                                text: root.placeholder
                                textRole: "body"
                                color: Theme.surfaceVariantText
                                font: Theme.bodyFont
                                visible: parent.text === ""
                            }
                        }
                    }
                }
                ThemeButton { visible: root.refreshable; text: ""; iconOnly: true; tooltip: "Rescan wallpapers"; onClicked: root.refreshRequested() }
            }
            ThemeText { Layout.fillWidth: true; visible: text !== ""; text: root.statusText; textRole: "body"; font.pixelSize: 11; color: Theme.surfaceVariantText; elide: Text.ElideRight }
            Item { id: resultBody; Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }
}
