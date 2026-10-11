"""Regression tests for wallpaper-derived Herdr surfaces (no running server needed)."""

import importlib.util
from pathlib import Path
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("herdr_colors", ROOT / ".config/herdr/sync-colors.py")
COLORS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COLORS)

CONFIG = '''[theme]
name = "terminal"
[theme.custom]
blue = "#abcdef"
# BEGIN managed wallpaper surfaces
panel_bg = "#000000"
# END managed wallpaper surfaces
[keys]
new_tab = "alt+n"
[ui]
confirm_close = false
'''


class HerdrColorsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "config.toml"
        self.palette = self.root / "colors.conf"
        self.config.write_text(CONFIG)
        self.palette.write_text("foreground #d4d4d4\nbackground #131d0c\n")

    def sync(self):
        return COLORS.sync_colors(self.config, self.palette)

    def test_normal_background_and_darker_selections_preserve_other_settings(self):
        self.assertTrue(self.sync())
        parsed = tomllib.loads(self.config.read_text())
        custom = parsed["theme"]["custom"]
        for key in ("panel_bg", "sidebar_bg", "surface0", "surface_dim"):
            self.assertEqual(custom[key], "reset", key)
        for key in ("active_row_bg", "selection_bg", "accent"):
            self.assertEqual(custom[key], "#10180a", key)
        self.assertEqual(custom["blue"], "#abcdef")
        self.assertEqual(parsed["keys"]["new_tab"], "alt+n")
        self.assertFalse(parsed["ui"]["confirm_close"])
        self.assertFalse(self.sync())

    def test_wallpaper_change_and_lua_style_rounding(self):
        self.sync()
        self.palette.write_text("background #FFFFFF # light palette\n")
        self.sync()
        custom = tomllib.loads(self.config.read_text())["theme"]["custom"]
        self.assertEqual(custom["sidebar_bg"], "reset")
        self.assertEqual(custom["active_row_bg"], "#d6d6d6")
        self.assertEqual(custom["accent"], "#d6d6d6")

    def test_dotfiles_symlink_is_preserved(self):
        target = self.root / "dotfiles.toml"
        self.config.rename(target)
        self.config.symlink_to(target)
        self.sync()
        self.assertTrue(self.config.is_symlink())
        self.assertIn('sidebar_bg = "reset"', target.read_text())
        self.assertIn('accent = "#10180a"', target.read_text())
        self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_partial_palette_keeps_last_good_settings(self):
        self.sync()
        before = self.config.read_text()
        self.palette.write_text("background #123\n")
        with self.assertRaises(ValueError):
            self.sync()
        self.assertEqual(self.config.read_text(), before)

    def test_missing_or_ambiguous_managed_block_is_not_overwritten(self):
        for text in ("[theme]\nname = 'terminal'\n", CONFIG + "\n" + COLORS.BEGIN):
            self.config.write_text(text)
            with self.assertRaises(ValueError):
                self.sync()
            self.assertEqual(self.config.read_text(), text)


if __name__ == "__main__":
    unittest.main()
