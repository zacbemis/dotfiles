import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Rectangle {
    id: root

    required property var record
    property bool centerCard: false
    property bool showAppName: true
    property bool expandedBody: false
    readonly property bool bodyTruncated: bodyText.truncated
    function toggleBody(): void { expandedBody = !expandedBody; }
    // Records can disappear a frame before their ListView delegate is removed.
    readonly property var details: record && !record.removed ? ({
        urgency: record.urgency, appIcon: record.appIcon, appName: record.appName,
        summary: record.summary, body: record.body, image: record.image, receivedAt: record.receivedAt,
        actions: record.actions.map(action => ({text: action.text, handle: action}))
    }) : ({urgency: NotificationUrgency.Normal,
        appIcon: "", appName: "", summary: "", body: "", image: "", receivedAt: Date.now(), actions: []})
    implicitHeight: content.implicitHeight + 24
    radius: 10
    color: centerCard ? Theme.notificationSurface : Theme.backgroundAlpha
    border.color: details.urgency === NotificationUrgency.Critical ? Theme.error : Theme.outlineVariant
    border.width: details.urgency === NotificationUrgency.Critical ? 2 : 1
    clip: true

    function iconSource(icon): string {
        if (!icon) return "";
        if (icon.startsWith("file://") || icon.startsWith("image://")) return icon;
        return icon.startsWith("/") ? Theme.fileUrl(icon) : Quickshell.iconPath(icon, true);
    }

    HoverHandler {
        enabled: !root.centerCard
        onHoveredChanged: if (root.record) root.record.hovered = hovered
    }
    Component.onDestruction: if (record && !record.removed) record.hovered = false
    MouseArea {
        anchors.fill: parent
        onClicked: if (root.record) root.record.invokeDefaultAction()
    }

    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ThemeText {
                Layout.fillWidth: true
                text: root.details.appName || "Notification"
                visible: root.showAppName
                color: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Item { Layout.fillWidth: true; visible: !root.showAppName }
            ThemeText {
                text: NotificationService.age(root.details.receivedAt)
                color: Theme.surfaceVariantText
                font.pixelSize: 10
            }
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 6
                color: closeMouse.containsMouse ? Theme.controlPressedBackground : Theme.transparentColor
                Behavior on color {
                    ColorAnimation { duration: Theme.controlDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEase }
                }
                GlyphIcon {
                    anchors.centerIn: parent
                    glyph: ""
                    color: Theme.foregroundFor(Qt.tint(Qt.tint(Theme.background, root.color), parent.color), Theme.controlText)
                    font.pixelSize: Theme.controlIconSize
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.record) root.record.dismiss()
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Item {
                Layout.preferredWidth: Theme.notificationIconSize
                Layout.preferredHeight: Theme.notificationIconSize
                Layout.alignment: Qt.AlignTop
                visible: !root.centerCard
                Image {
                    id: appIcon
                    anchors.fill: parent
                    source: root.iconSource(root.details.appIcon)
                    sourceSize { width: Theme.notificationIconSize; height: Theme.notificationIconSize }
                    fillMode: Image.PreserveAspectFit
                }
                GlyphIcon {
                    anchors.centerIn: parent
                    glyph: "󰂚"
                    font.pixelSize: Theme.notificationIconSize
                    color: Theme.primary
                    visible: appIcon.status !== Image.Ready
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                ThemeText {
                    Layout.fillWidth: true
                    text: root.details.summary
                    textFormat: Text.PlainText
                    color: root.centerCard ? Theme.notificationText : Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    visible: text !== ""
                }
                ThemeText {
                    id: bodyText
                    Layout.fillWidth: true
                    text: root.details.body
                    color: root.centerCard ? Theme.notificationText : Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: root.centerCard
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: root.expandedBody ? 2147483647 : root.centerCard ? 8 : 4
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }
        ThemeButton {
            Layout.fillWidth: true
            visible: root.centerCard && (bodyText.truncated || root.expandedBody)
            text: root.expandedBody ? "Show less" : "Read full message"
            surfaceColor: Theme.notificationSurface
            onClicked: root.toggleBody()
        }
        Image {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            source: root.details.image
            sourceSize { width: 400; height: 280 }
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: root.details.image !== ""
        }
        Flow {
            id: actions
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 6
            visible: root.details.actions.length > 0
            Repeater {
                model: root.details.actions
                Rectangle {
                    id: action
                    required property var modelData
                    height: 28
                    width: Math.min(label.implicitWidth + 20, actions.width)
                    radius: 6
                    color: actionMouse.pressed ? Theme.controlPressedBackground
                        : actionMouse.containsMouse ? (root.centerCard ? Theme.controlPressedBackground : Theme.controlHoverBackground)
                        : root.centerCard ? Theme.alpha(Theme.secondary, 0.6) : Theme.controlBackground
                    Behavior on color {
                        ColorAnimation { duration: Theme.controlDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.cssEase }
                    }
                    ThemeText {
                        id: label
                        anchors.centerIn: parent
                        width: parent.width - 20
                        text: action.modelData.text || ""
                        color: Theme.foregroundFor(Qt.tint(Qt.tint(Theme.background, root.color), action.color), Theme.controlText)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.record) root.record.invokeAction(action.modelData.handle)
                    }
                }
            }
        }
    }
}
