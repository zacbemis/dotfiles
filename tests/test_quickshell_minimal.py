"""Guard minimal chrome without removing meaningful confirmation or dismissal."""
from pathlib import Path
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class MinimalShellDesign(unittest.TestCase):
    def test_no_close_buttons_or_always_visible_instructions(self):
        for folder in ("components", "modules"):
            for path in (CONFIG / folder).rglob("*.qml"):
                source = path.read_text()
                self.assertNotRegex(source, r'text:\s*"(?:×|)"', str(path))
                for fragment in ("esc close", "↑↓ navigate", "Changes apply immediately", "Saved automatically",
                                 "Shared notification history", "Uses your existing Pywal wallpaper pipeline",
                                 "Click feature names to cycle"):
                    self.assertNotIn(fragment, source, str(path))
        settings = (CONFIG / "modules/settings/SettingsPanel.qml").read_text()
        self.assertNotIn('text: "Reset defaults"', settings)  # Classic already does this.
        self.assertNotIn("root.category.description", settings)
        card = (CONFIG / "modules/settings/ChoiceCard.qml").read_text()
        self.assertIn("ThemeTooltip", card)  # Descriptions remain discoverable, not permanent paragraphs.

    def test_small_shared_panel_defaults(self):
        state = (CONFIG / "services/UiState.qml").read_text()
        self.assertIn("panelWidth: 720", state)
        self.assertIn("panelHeight: 420", state)
        picker = (CONFIG / "components/PickerWindow.qml").read_text()
        self.assertIn("navigationPanel: true", picker)
        self.assertNotIn("contentHeightHint", picker)
        settings = (CONFIG / "modules/settings/SettingsPanel.qml").read_text()
        self.assertIn("navigationPanel: true", settings)

    def test_wallpaper_selection_still_requires_explicit_activation(self):
        for name in ("ListPicker.qml", "GalleryPicker.qml", "CarouselPicker.qml"):
            source = (CONFIG / "modules/wallpaper" / name).read_text()
            self.assertEqual(source.count('"Set wallpaper"'), 1, name)
            self.assertIn("onDoubleClicked:", source)
            self.assertNotRegex(source, r"onClicked:[^\n]*select\([^\n]*apply\(")
        source = (CONFIG / "components/OverlayWindow.qml").read_text()
        self.assertIn("Keys.onEscapePressed", source)
        self.assertIn("onClicked: UiState.close", source)

    def test_bar_gear_opens_quick_settings_without_duplicate_notification_shortcuts(self):
        source = (CONFIG / "modules/comparison/Features.qml").read_text()
        self.assertNotIn('glyph: ""', source)
        self.assertNotIn('ShellProfile.activate("settings")', source)
        self.assertEqual(source.count('ShellProfile.activate("controls")'), 1)
        self.assertLess(source.index('controlKey: "battery"'), source.index('controlKey: "controls"'))
        self.assertLess(source.index('controlKey: "controls"'), source.index('controlKey: "notifications"'))
        original = (CONFIG / "modules/bar/Bar.qml").read_text()
        self.assertIn('ShellProfile.activate("controls")', original)
        for name in ("Notifications.qml", "AlternativeCenter.qml"):
            self.assertNotIn('UiState.show("controls")', (CONFIG / "modules/notifications" / name).read_text())

    def test_dnd_is_a_notification_header_switch_not_a_quick_settings_tile(self):
        controls = (CONFIG / "modules/controls/QuickSettings.qml").read_text()
        self.assertNotIn('key: "dnd"', controls)
        self.assertNotIn('"DND on"', controls)
        self.assertNotIn('"DND off"', controls)
        for name in ("Notifications.qml", "AlternativeCenter.qml"):
            source = (CONFIG / "modules/notifications" / name).read_text()
            self.assertNotIn('text: "DND"', source)
            self.assertIn('label: "Do not disturb"\n', source)
            self.assertIn('value: NotificationService.dnd', source)
            self.assertIn('onRequested: value => { if (value !== NotificationService.dnd) NotificationService.toggleDnd(); }', source)
            self.assertIn("ThemeToggle {", source)

    def test_sound_is_a_quick_settings_tile_without_a_volume_arrow(self):
        source = (CONFIG / "modules/controls/QuickSettings.qml").read_text()
        self.assertIn('{key: "audio", label: "Sound", glyph: "󰕾"}', source)
        self.assertIn('if (key === "audio") return AudioService.open();', source)
        self.assertNotIn('tooltip: "Sound"; onClicked: AudioService.open()', source)

    def test_hidden_dismiss_controls_cannot_take_invisible_clicks(self):
        for name in ("NotificationCard.qml", "CompactCard.qml", "NotificationGroup.qml", "AlternativeCenter.qml"):
            source = (CONFIG / "modules/notifications" / name).read_text()
            self.assertIn("󰆴", source, name)
            self.assertIn("opacity:", source, name)
            self.assertIn("enabled: opacity > 0", source, name)
            self.assertIn("Keys.onDeletePressed", source, name)
