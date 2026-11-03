"""Evaluate real Lua window rules without touching the live compositor."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
class WindowRulePolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = ROOT / ".config/hypr/hyprmodules/windowrules.lua"
        harness = r'''
local rules = {}
hl = { window_rule = function(rule) table.insert(rules, rule) end,
       layer_rule = function(_) end }
local function encode(value)
    if type(value) == "string" then
        return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    elseif type(value) == "boolean" or type(value) == "number" then
        return tostring(value)
    elseif type(value) == "table" then
        local fields = {}
        for key, item in pairs(value) do table.insert(fields, encode(key) .. ':' .. encode(item)) end
        return '{' .. table.concat(fields, ',') .. '}'
    end
    error('Unexpected rule value')
end
'''
        harness += "\ndofile(" + json.dumps(str(source)) + ")\n"
        harness += "local result = {}; for _, rule in ipairs(rules) do table.insert(result, encode(rule)) end; print('[' .. table.concat(result, ',') .. ']')"
        result = subprocess.run(["lua", "-e", harness], text=True, capture_output=True, check=True)
        cls.rules = json.loads(result.stdout)

    def effects(self, **fields):
        window = {"class": fields.get("class", "helium"), "title": fields.get("title", "Ordinary page - Helium"),
                  "modal": False, "float": False, "xwayland": False, "fullscreen": False, "pin": False}
        window.update(fields)
        window.setdefault("initial_class", window["class"])
        window.setdefault("initial_title", window["title"])
        result = {"float": window["float"], "center": False}
        for rule in self.rules:
            matches = all(re.fullmatch(expected, str(window.get(key, ""))) is not None
                          if isinstance(expected, str) else window.get(key, False) == expected
                          for key, expected in rule.get("match", {}).items())
            if matches:
                result.update({key: value for key, value in rule.items() if key not in {"name", "match"}})
        return result

    def assert_dialog(self, **fields):
        effects = self.effects(**fields)
        self.assertTrue(effects["float"], fields)
        self.assertTrue(effects["center"], fields)

    def test_unfamiliar_modal_dialogs_float(self):
        # In Hyprland 0.56.2 the modal matcher comes from XWayland metadata;
        # native Wayland transient parents use the built-in floating policy.
        self.assert_dialog(title="Application confirmation", modal=True, xwayland=True)
        self.assert_dialog(**{"class": "application", "title": "Question", "modal": True, "xwayland": True})

    def test_browser_blank_popup_stays_floating_after_its_title_changes(self):
        self.assert_dialog(initial_title="about:blank - Helium", title="Example login - Helium")
        self.assert_dialog(**{"class": "chromium", "initial_title": "about:blank - Chromium", "title": "Popup"})

    def test_browser_utilities_float_without_matching_all_browser_windows(self):
        for title in ("Picture in picture", "Picture-in-Picture", "DevTools - fixture", "Developer Tools - fixture"):
            with self.subTest(title=title):
                self.assert_dialog(title=title)

    def test_normal_browser_windows_and_later_page_title_changes_stay_tiled(self):
        for title in ("New Tab - Helium", "New Tab - Chromium", "Documentation - Helium", "Sign in - Helium"):
            with self.subTest(title=title):
                self.assertFalse(self.effects(title=title)["float"])
        self.assertFalse(self.effects(initial_title="New Tab - Helium", title="Save")["float"])
        self.assertFalse(self.effects(**{"class": "kitty", "title": "about:blank - Helium"})["float"])

    def test_file_and_portal_dialogs_float(self):
        for title in ("Open File", "Save As", "File Upload", "Choose File", "Select a Folder"):
            with self.subTest(title=title):
                self.assert_dialog(**{"class": "application", "title": title})
        for app in ("xdg-desktop-portal-gtk", "Xdg-desktop-portal-hyprland", "xdg-desktop-portal-kde", "org.gtk.Portal"):
            with self.subTest(app=app):
                self.assert_dialog(**{"class": app, "title": "A translated file chooser"})

    def test_builtin_transient_floating_and_xwayland_drag_workaround_remain(self):
        self.assertTrue(self.effects(**{"class": "native-transient", "float": True})["float"])
        drag = self.effects(**{"class": "", "title": "", "xwayland": True, "float": True})
        self.assertTrue(drag["no_focus"])


if __name__ == "__main__":
    unittest.main()
