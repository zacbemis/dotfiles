import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../services/StyleCatalog.js" as Catalog

OverlayWindow {
    id: root
    route: "settings"
    navigationPanel: true
    popIn: false
    property int categoryIndex: 0
    readonly property var categories: Catalog.categories.concat([{key: "indicators", label: "Bar indicators", options: []}])
    readonly property var category: categories[categoryIndex]
    signal osdPreviewRequested()
    Shortcut { enabled: root.opened; sequence: "Ctrl+Tab"; onActivated: root.categoryIndex = (root.categoryIndex + 1) % root.categories.length }
    Shortcut { enabled: root.opened; sequence: "Ctrl+Shift+Tab"; onActivated: root.categoryIndex = (root.categoryIndex + root.categories.length - 1) % root.categories.length }

    function current(key) {
        if (BarIndicators.keys.includes(key)) return BarIndicators.value(key);
        return key === "bar" ? ShellProfile.name : key === "wallpaperColors" ? ShellProfile.wallpaperColors
            : key === "autoHide" ? ShellProfile.autoHide : key === "pinned" ? ShellProfile.pinned : FeatureSettings[key];
    }
    function choose(key, value): bool {
        if (!Catalog.valid(key, value)) return false;
        if (BarIndicators.keys.includes(key)) return BarIndicators.set(key, value);
        if (key === "bar") return ShellProfile.select(value);
        if (key === "wallpaperColors") ShellProfile.wallpaperColors = value;
        else if (key === "autoHide") ShellProfile.autoHide = value;
        else if (key === "pinned") ShellProfile.pinned = value;
        else return FeatureSettings.select(key, value);
        return true;
    }
    function apply(values): bool {
        if (!values || typeof values !== "object" || Array.isArray(values) || Object.keys(values).some(key => !Catalog.valid(key, values[key]))) return false;
        Preferences.beginBatch();
        try {
            // A profile selection resets pinning, so apply flags after all renderers.
            for (const key of Object.keys(values).filter(key => Preferences.choices[key])) choose(key, values[key]);
            for (const key of ["wallpaperColors", "autoHide", "pinned", ...BarIndicators.keys]) if (values[key] !== undefined) choose(key, values[key]);
        } finally { Preferences.endBatch(); }
        return true;
    }
    function preset(key): bool {
        const preset = Catalog.presets.find(value => value.key === key);
        return preset ? apply(Object.assign({wallpaperColors: true, autoHide: false, pinned: false}, preset.values)) : false;
    }
    function openCategory(key): bool {
        const index = categories.findIndex(value => value.key === key);
        if (index < 0) return false;
        categoryIndex = index;
        UiState.show("settings");
        return true;
    }
    function moveChoice(delta): void {
        const options = category.options;
        if (!options.length) return;
        const index = options.findIndex(value => value.key === current(category.key));
        const next = (index + delta + options.length) % options.length;
        choose(category.key, options[next].key);
        const card = optionRepeater.itemAt(next);
        if (card) card.forceActiveFocus();
    }
    function preview(): void {
        if (category.key === "osd") osdPreviewRequested();
        else if (["bar", "indicators"].includes(category.key)) UiState.close("settings");
        else UiState.show(category.key);
    }
    function status() {
        const state = {};
        for (const key of Object.keys(Catalog.defaults())) state[key] = current(key);
        return {opened: opened, visible: renderVisible, category: category.key, current: state,
            indicators: BarIndicators.status(), indicatorControls: indicatorEditor.presentation(),
            persistent: Preferences.persistent, path: Preferences.path, pending: Preferences.pending,
            error: Preferences.error, choices: Preferences.choices, presets: Catalog.presets, fonts: typography(),
            options: category.options.map((option, index) => {
                const item = optionRepeater.itemAt(index);
                const point = item ? item.mapToItem(optionViewport, 0, 0) : {x: 0, y: 0};
                return {key: option.key, selected: current(category.key) === option.key,
                    width: item ? item.width : 0, x: point.x, y: point.y,
                    fullyVisible: !!item && point.y >= -1 && point.y + item.height <= optionViewport.availableHeight + 1};
            }), viewportWidth: optionViewport.availableWidth,
            width: dimensions().width, height: dimensions().height, narrow: dimensions().width < 620};
    }

    Item {
        id: card
        anchors.fill: parent
        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Catalog.presets
                    ThemeButton { required property var modelData; text: modelData.label; tooltip: "Changes all six components · " + modelData.description; baseColor: Theme.panelSurface; onClicked: root.preset(modelData.key) }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                ColumnLayout {
                    visible: card.width >= 620
                    Layout.preferredWidth: 132
                    Layout.fillHeight: true
                    spacing: 6
                    Repeater {
                        model: root.categories
                        ThemeButton {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            text: modelData.label
                            Accessible.role: Accessible.PageTab
                            Accessible.selected: root.categoryIndex === index
                            baseColor: root.categoryIndex === index ? Theme.activeBackground : Theme.transparentColor
                            onClicked: root.categoryIndex = index
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    RowLayout {
                        visible: card.width < 620
                        Layout.fillWidth: true
                        ThemeText { Layout.fillWidth: true; text: root.category.label; textRole: "title"; font.pixelSize: 16 }
                        ThemeButton { text: "→"; tooltip: "Next section"; onClicked: root.categoryIndex = (root.categoryIndex + 1) % root.categories.length }
                    }
                    ScrollView {
                        id: indicatorViewport
                        visible: root.category.key === "indicators"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        IndicatorSettings { id: indicatorEditor; width: parent.width }
                    }
                    ScrollView {
                        id: optionViewport
                        visible: root.category.key !== "indicators"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        GridLayout {
                            width: parent.width
                            columns: width >= 380 ? 2 : 1
                            rowSpacing: 10
                            columnSpacing: 10
                            Repeater {
                                id: optionRepeater
                                model: root.category.options
                                ChoiceCard {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 92
                                    category: root.category.key
                                    option: modelData
                                    selected: root.current(root.category.key) === modelData.key
                                    onChosen: root.choose(root.category.key, modelData.key)
                                    Keys.onLeftPressed: root.moveChoice(-1)
                                    Keys.onRightPressed: root.moveChoice(1)
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        visible: root.category.key === "bar"
                        Layout.fillWidth: true
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            ThemeButton { text: "Wallpaper"; baseColor: ShellProfile.name === "current" || ShellProfile.wallpaperColors ? Theme.activeBackground : Theme.panelSurface; onClicked: root.choose("wallpaperColors", true) }
                            ThemeButton { text: "Upstream"; enabled: ShellProfile.name !== "current"; baseColor: ShellProfile.name !== "current" && !ShellProfile.wallpaperColors ? Theme.activeBackground : Theme.panelSurface; onClicked: root.choose("wallpaperColors", false) }
                        }
                        RowLayout {
                            visible: ShellProfile.name === "mm2103"
                            ThemeButton { text: "Auto-hide"; baseColor: ShellProfile.autoHide ? Theme.activeBackground : Theme.transparentColor; onClicked: root.choose("autoHide", !ShellProfile.autoHide) }
                            ThemeButton { text: "Pin"; visible: ShellProfile.autoHide; baseColor: ShellProfile.pinned ? Theme.activeBackground : Theme.transparentColor; onClicked: root.choose("pinned", !ShellProfile.pinned) }
                        }
                    }
                    ThemeButton {
                        visible: !["bar", "indicators"].includes(root.category.key)
                        text: "Preview"
                        enabled: root.category.key !== "osd" || FeatureSettings.osd !== "off"
                        onClicked: root.preview()
                    }
                }
            }
            ThemeText {
                Layout.fillWidth: true
                visible: text !== ""
                text: Preferences.error
                textRole: "body"
                font.pixelSize: 11
                color: Preferences.error ? Theme.error : Theme.surfaceVariantText
                wrapMode: Text.Wrap
            }
        }
    }
}
