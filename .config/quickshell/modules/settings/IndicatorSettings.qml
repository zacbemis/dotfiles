import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../services/StyleCatalog.js" as Catalog

ColumnLayout {
    id: root
    spacing: 12
    function presentation() {
        return Catalog.indicators.map((entry, index) => {
            const item = rows.itemAt(index);
            return {key: entry.key, value: BarIndicators.value(entry.key),
                width: item ? item.width : 0, height: item ? item.height : 0, options: item ? item.optionGeometry() : []};
        });
    }
    Repeater {
        id: rows
        model: Catalog.indicators
        ColumnLayout {
            id: row
            required property var modelData
            Layout.fillWidth: true
            spacing: 4
            function optionGeometry() {
                return Catalog.indicatorModes.map((mode, index) => {
                    const button = choices.itemAt(index);
                    const point = button ? button.mapToItem(row, 0, 0) : {x: 0, y: 0};
                    return {key: mode.key, x: point.x, width: button ? button.width : 0};
                });
            }
            RowLayout {
                Layout.fillWidth: true
                StatusIcon { size: 18; reading: SystemState.indicator(row.modelData.kind); color: Theme.primaryInk }
                ThemeText { Layout.fillWidth: true; text: row.modelData.label; textRole: "label" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    id: choices
                    model: Catalog.indicatorModes
                    ControlButton {
                        required property var modelData
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        text: modelData.label
                        tooltip: row.modelData.label + " · " + modelData.label + ". Tooltips keep exact values; OSD settings are independent."
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: BarIndicators.value(row.modelData.key) === modelData.key
                        baseColor: BarIndicators.value(row.modelData.key) === modelData.key ? Theme.activeBackground : Theme.surfaceContainerHigh
                        onClicked: BarIndicators.set(row.modelData.key, modelData.key)
                    }
                }
            }
        }
    }
}
