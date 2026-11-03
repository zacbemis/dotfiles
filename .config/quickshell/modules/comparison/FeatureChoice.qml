import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

RowLayout {
    id: root
    required property string feature
    required property string title
    ThemeText { text: root.title; textRole: "title"; font.pixelSize: 11; Layout.preferredWidth: 82 }
    ThemeButton {
        Layout.fillWidth: true
        text: FeatureSettings[root.feature]
        tooltip: "Click to cycle: " + FeatureSettings.choices[root.feature].join(" → ")
        onClicked: FeatureSettings.cycle(root.feature)
    }
}
