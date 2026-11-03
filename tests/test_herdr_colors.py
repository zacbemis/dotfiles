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
        self.palette.write_text("foreground #d4d4d4\nbackground #131d0c\ncolor4 #d69c0a\n")

    def sync(self):
        return COLORS.sync_colors(self.config, self.palette)

    def assert_readable_selection(self, custom, background, foreground):
        selected = custom["accent"]
        rgb = tuple(int(selected[i:i + 2], 16) for i in (1, 3, 5))
        self.assertGreaterEqual(COLORS.contrast(rgb, background), 2.2)
        self.assertGreaterEqual(COLORS.contrast(rgb, foreground), 4.5)
        for key in ("active_row_bg", "selection_bg"):
            self.assertEqual(custom[key], selected, key)
        return rgb

    def test_normal_background_and_visible_selections_preserve_other_settings(self):
        self.assertTrue(self.sync())
        parsed = tomllib.loads(self.config.read_text())
        custom = parsed["theme"]["custom"]
        for key in ("panel_bg", "sidebar_bg", "surface0", "surface_dim"):
            self.assertEqual(custom[key], "reset", key)
        rgb = self.assert_readable_selection(custom, (19, 29, 12), (212, 212, 212))
        self.assertGreater(rgb[0], rgb[1])  # Retain the wallpaper's golden accent.
        self.assertGreater(rgb[1], rgb[2])
        self.assertEqual(custom["blue"], "#abcdef")
        self.assertEqual(parsed["keys"]["new_tab"], "alt+n")
        self.assertFalse(parsed["ui"]["confirm_close"])
        self.assertFalse(self.sync())

    def test_wallpaper_change_to_light_palette(self):
        self.sync()
        old = tomllib.loads(self.config.read_text())["theme"]["custom"]["accent"]
        self.palette.write_text("background #FFFFFF # light palette\nforeground #202020\ncolor4 #705090\n")
        self.sync()
        custom = tomllib.loads(self.config.read_text())["theme"]["custom"]
        self.assertEqual(custom["sidebar_bg"], "reset")
        self.assertNotEqual(custom["accent"], old)
        self.assert_readable_selection(custom, (255, 255, 255), (32, 32, 32))

    def test_subdued_accent_is_adjusted_for_visibility(self):
        self.palette.write_text("background #101308\nforeground #c3c4c1\ncolor4 #202610\n")
        self.sync()
        custom = tomllib.loads(self.config.read_text())["theme"]["custom"]
        self.assert_readable_selection(custom, (16, 19, 8), (195, 196, 193))

    def test_background_only_palettes_have_readable_fallbacks(self):
        for background, foreground in (((0, 0, 0), (255, 255, 255)),
                                       ((255, 255, 255), (0, 0, 0))):
            self.palette.write_text("background #" + "".join(f"{c:02x}" for c in background) + "\n")
            self.sync()
            custom = tomllib.loads(self.config.read_text())["theme"]["custom"]
            self.assert_readable_selection(custom, background, foreground)

    def test_selection_background_is_used_without_primary(self):
        self.palette.write_text("background #000000\nforeground #ffffff\nselection_background #4090b0\n")
        self.sync()
        custom = tomllib.loads(self.config.read_text())["theme"]["custom"]
        rgb = self.assert_readable_selection(custom, (0, 0, 0), (255, 255, 255))
        self.assertLess(rgb[0], rgb[1])
        self.assertLess(rgb[1], rgb[2])

    def test_unreadable_palette_keeps_last_good_settings(self):
        self.sync()
        before = self.config.read_text()
        self.palette.write_text("background #101010\nforeground #777777\ncolor4 #303030\n")
        with self.assertRaises(ValueError):
            self.sync()
        self.assertEqual(self.config.read_text(), before)

    def test_dotfiles_symlink_is_preserved(self):
        target = self.root / "dotfiles.toml"
        self.config.rename(target)
        self.config.symlink_to(target)
        self.sync()
        self.assertTrue(self.config.is_symlink())
        self.assertIn('sidebar_bg = "reset"', target.read_text())
        custom = tomllib.loads(target.read_text())["theme"]["custom"]
        self.assert_readable_selection(custom, (19, 29, 12), (212, 212, 212))
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
