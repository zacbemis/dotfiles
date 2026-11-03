// SPDX-License-Identifier: MIT
// Adapted from MM-2103 notifications/NotificationCard.qml (vendor/mm2103).
// Our records retain timers/actions; no NotificationServer or new expiry policy.
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

Rectangle {
    id: root
    required property var record
    property bool centerCard: false
    readonly property bool showAppName: !centerCard || FeatureSettings.notifications !== "stacked"
    property bool expanded: false
    readonly property var details: record && !record.removed ? record : null
    implicitHeight: content.implicitHeight + 20
    radius: 6
    color: centerCard ? Theme.panelSurface : Theme.backgroundAlpha
    border.color: details && details.urgency === 2 ? Theme.error : Theme.outlineVariant
    border.width: !centerCard || (details && details.urgency === 2) ? 1 : 0
    activeFocusOnTab: true
    Keys.onDeletePressed: if (record) record.dismiss()
    Keys.onReturnPressed: if (record) record.invokeDefaultAction()
    HoverHandler { id: cardHover; onHoveredChanged: if (root.details && !root.centerCard) root.details.hovered = hovered }
    Component.onDestruction: if (record && !record.removed) record.hovered = false
    MouseArea { anchors.fill: parent; onClicked: if (root.details) root.details.invokeDefaultAction() }
    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
        spacing: 7
        RowLayout {
            Layout.fillWidth: true
            ThemeText { Layout.fillWidth: true; visible: root.showAppName; text: root.details ? root.details.appName : ""; textRole: "label"; textFormat: Text.PlainText; font.pixelSize: 11; color: Theme.surfaceVariantText; elide: Text.ElideRight }
            Item { Layout.fillWidth: true; visible: !root.showAppName }
            ThemeText { text: root.details ? NotificationService.age(root.details.receivedAt) : ""; textRole: "body"; font.pixelSize: 10; color: Theme.surfaceVariantText }
            ThemeButton { text: "󰆴"; iconOnly: true; surfaceColor: root.color; tooltip: "Dismiss"; implicitWidth: 24; implicitHeight: 24; opacity: cardHover.hovered || root.activeFocus || activeFocus ? 1 : 0; enabled: opacity > 0; onClicked: if (root.details) root.details.dismiss() }
        }
        ThemeText {
            Layout.fillWidth: true
            text: root.details ? root.details.summary : ""
            textRole: "title"
            textFormat: Text.PlainText
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        ThemeText {
            id: body
            Layout.fillWidth: true
            text: root.details ? root.details.formattedBody : ""
            textRole: "body"
            textFormat: Text.StyledText
            linkColor: Theme.primaryInk
            onLinkActivated: link => { if (root.record) root.record.openLink(link); }
            font.pixelSize: 11
            color: Theme.surfaceVariantText
            wrapMode: Text.Wrap
            maximumLineCount: root.expanded ? 2147483647 : 4
            elide: Text.ElideRight
            visible: text !== ""
        }
        ThemeButton { visible: root.centerCard && (body.truncated || root.expanded); text: root.expanded ? "Less" : "More"; surfaceColor: root.color; onClicked: root.expanded = !root.expanded }
        Image {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            source: root.details ? root.details.image : ""
            visible: Boolean(root.details && root.details.image !== "")
            sourceSize { width: 380; height: 240 }
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 5
            Repeater {
                model: root.details ? root.details.actions : []
                ThemeButton {
                    required property var modelData
                    width: Math.min(implicitWidth, parent ? parent.width : implicitWidth)
                    text: modelData ? modelData.text || "" : ""
                    tooltip: text
                    surfaceColor: root.color
                    onClicked: if (root.details && modelData) root.details.invokeAction(modelData)
                }
            }
        }
    }
}
