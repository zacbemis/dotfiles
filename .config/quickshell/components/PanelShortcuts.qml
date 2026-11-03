import QtQuick

Item {
    id: root
    property bool shortcutEnabled: false
    signal stepped(int delta)
    Shortcut { enabled: root.shortcutEnabled; sequence: "Alt+H"; onActivated: root.stepped(-1) }
    Shortcut { enabled: root.shortcutEnabled; sequence: "Alt+L"; onActivated: root.stepped(1) }
}
