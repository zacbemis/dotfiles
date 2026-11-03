import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import qs.theme

// Render exported DBusMenu entries ourselves: native Qt platform menus do not
// inherit GTK's Pywal CSS/fonts, and nm-applet's Activate does not open its menu.
PanelWindow {
    id: root

    property var sourceItem: null
    property var menuPath: []
    property int selectedIndex: -1
    readonly property var currentOpener: menuPath.length ? menuPath[menuPath.length - 1] : null
    readonly property var entries: currentOpener ? currentOpener.children.values : []
    property var targetItem: null
    property string title: ""
    readonly property var windowInsets: UiState.insets(screen)
    readonly property int menuY: windowInsets.top
    readonly property int menuWidth: Math.max(0, Math.min(screen ? screen.width - windowInsets.left - windowInsets.right : 420,
        420, Math.max(280, longestLabel.width + 74)))
    readonly property int menuHeight: Math.max(0, Math.min(screen ? screen.height - menuY - windowInsets.bottom : 700,
        (menuPath.length > 1 ? 36 : 0) + 16
        + (entries.length ? entries.reduce((height, entry) => height + (entry.isSeparator ? 10 : 34), 0) : 40)))

    // A transparent overlay avoids Qt's input-serial and resize limitations for
    // xdg_popups anchored to layer-shell bars. Only mapped while a menu is open.
    screen: targetItem && targetItem.QsWindow.window ? targetItem.QsWindow.window.screen : Quickshell.screens[0]
    visible: false
    focusable: true
    color: Theme.transparentColor
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-dev-tray-menu"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: PanelInputRegion { output: root.screen; targetWindow: root; windowWidth: root.width; windowHeight: root.height; active: root.visible }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // Keep ancestor openers referenced: closing the root DBusMenu can destroy
    // its child handles. A single opener switched to a child yields empty menus.
    Component { id: openerComponent; QsMenuOpener {} }
    TextMetrics {
        id: longestLabel
        font: Theme.menuFont
        text: root.entries.reduce((longest, entry) => entry.text.length > longest.length ? entry.text : longest, "")
    }

    function label(text): string {
        return text.replace(/__|_(.)/g, (match, char) => match === "__" ? "_" : char);
    }

    function open(target, item): void {
        if (!item || !item.hasMenu) return;
        if (visible && sourceItem === item) { close(); return; }
        if (visible) close();
        sourceItem = item;
        title = item.title || item.id;
        targetItem = target;
        menuPath = [openerComponent.createObject(root, {menu: item.menu})];
        selectedIndex = -1;
        visible = true;
        Qt.callLater(() => menuContent.forceActiveFocus());
    }

    function hoverPoint() {
        const index = entries.findIndex(entry => entry.enabled && !entry.isSeparator);
        const row = index >= 0 ? list.itemAtIndex(index) : null;
        if (!row) return null;
        const point = row.mapToGlobal(row.width / 2, row.height / 2);
        return {x: Math.round(point.x), y: Math.round(point.y)};
    }

    function close(): void { visible = false; }
    function back(): void {
        if (menuPath.length > 1) {
            const old = currentOpener;
            menuPath = menuPath.slice(0, -1);
            old.destroy();
            selectedIndex = -1;
        } else close();
    }
    function choose(entry): void {
        if (!entry || !entry.enabled || entry.isSeparator) return;
        if (entry.hasChildren) {
            menuPath = [...menuPath, openerComponent.createObject(root, {menu: entry})];
            selectedIndex = -1;
        } else {
            entry.triggered();
            close();
        }
    }
    function layoutStatus() { return {x: menuContent.x, y: menuContent.y, width: menuContent.width, height: menuContent.height, insets: windowInsets}; }
    function navigate(delta): void {
        const count = entries.length;
        if (!count) return;
        let index = selectedIndex;
        for (let i = 0; i < count; ++i) {
            index = (index + delta + count) % count;
            if (entries[index].enabled && !entries[index].isSeparator) {
                selectedIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
                return;
            }
        }
    }

    onSourceItemChanged: if (!sourceItem && visible) close()
    onVisibleChanged: if (!visible) {
        const old = menuPath;
        menuPath = [];
        sourceItem = null;
        selectedIndex = -1;
        for (const opener of old.reverse()) opener.destroy();
    }
    Connections { target: UiState; function onActiveChanged() { if (UiState.active !== "") root.close(); } }
    Connections {
        target: root.sourceItem
        function onHasMenuChanged() { if (!root.sourceItem.hasMenu) root.close(); }
    }

    Rectangle {
        id: menuContent
        x: Math.max(root.windowInsets.left, Math.min(root.width - width - root.windowInsets.right,
            root.targetItem && root.targetItem.QsWindow.window ? root.targetItem.mapToItem(root.targetItem.QsWindow.window.contentItem, 0, 0).x : root.windowInsets.left))
        y: root.menuY
        width: root.menuWidth
        height: root.menuHeight
        radius: 8
        color: Theme.background
        border.color: Theme.outlineVariant
        focus: true
        MouseArea { anchors.fill: parent }
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Down: root.navigate(1); break;
            case Qt.Key_Up: root.navigate(-1); break;
            case Qt.Key_Left: root.back(); break;
            case Qt.Key_Escape: root.close(); break;
            case Qt.Key_Right:
            case Qt.Key_Return:
            case Qt.Key_Enter: root.choose(root.entries[root.selectedIndex]); break;
            default: return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 0
            ThemeButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                visible: root.menuPath.length > 1
                text: "‹  Back"
                pickerStyle: true
                font: Theme.menuFont
                onClicked: root.back()
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.currentOpener ? root.currentOpener.children : null
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: menuRow
                    required property var modelData
                    required property int index
                    readonly property bool highlighted: index === root.selectedIndex && modelData.enabled
                    width: list.width
                    height: modelData.isSeparator ? 10 : 34
                    radius: 5
                    color: highlighted ? Theme.menuHoverBackground : Theme.transparentColor
                    Rectangle {
                        visible: menuRow.modelData.isSeparator
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                        height: 1
                        color: Theme.outlineVariant
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        visible: !menuRow.modelData.isSeparator
                        Item {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            Image {
                                anchors.fill: parent
                                source: menuRow.modelData.icon
                                sourceSize { width: 18; height: 18 }
                                visible: menuRow.modelData.buttonType === QsMenuButtonType.None
                                fillMode: Image.PreserveAspectFit
                            }
                            GlyphIcon {
                                anchors.centerIn: parent
                                glyph: menuRow.modelData.buttonType === QsMenuButtonType.RadioButton
                                    ? (menuRow.modelData.checkState === Qt.Checked ? "" : "")
                                    : (menuRow.modelData.checkState === Qt.Checked ? "" : "")
                                visible: menuRow.modelData.buttonType !== QsMenuButtonType.None
                                color: menuRow.highlighted ? Theme.menuHoverText : Theme.surfaceText
                                font: Theme.iconFont
                            }
                        }
                        ThemeText {
                            Layout.fillWidth: true
                            text: root.label(menuRow.modelData.text)
                            textFormat: Text.PlainText
                            color: !menuRow.modelData.enabled ? Theme.disabledText
                                : menuRow.highlighted ? Theme.menuHoverText : Theme.surfaceText
                            textRole: "menu"
                            elide: Text.ElideRight
                        }
                        GlyphIcon {
                            glyph: ""
                            size: 12
                            visible: menuRow.modelData.hasChildren
                            color: menuRow.highlighted ? Theme.menuHoverText : Theme.surfaceText
                            font: Theme.iconFont
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: menuRow.modelData.enabled && !menuRow.modelData.isSeparator
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIndex = menuRow.index
                        onClicked: root.choose(menuRow.modelData)
                    }
                }
                ThemeText {
                    anchors.centerIn: parent
                    text: "Loading menu…"
                    textRole: "tooltip"
                    color: Theme.surfaceVariantText
                    visible: root.entries.length === 0
                }
            }
        }
    }
}
