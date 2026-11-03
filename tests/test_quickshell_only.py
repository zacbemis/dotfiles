"""Quickshell-only configuration and isolated color-hook regressions."""
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuickshellOnly(unittest.TestCase):
    def test_retired_configs_and_activation_override_are_removed(self):
        for relative in (
            ".config/waybar/config.jsonc", ".config/rofi/config.rasi",
            ".config/swaync/config.json", ".config/matugen/hooks/reload-swaync.sh",
            ".config/matugen/templates/rofi-colors.css",
            ".config/wal/templates/colors-rofi-custom.rasi",
            ".config/wal/templates/colors-swaync-custom.css",
            ".config/wal/templates/colors-waybar-custom.css",
            ".local/share/dbus-1/services/org.erikreider.swaync.cc.service",
        ):
            self.assertFalse((ROOT / relative).exists(), relative)
        activation = (ROOT / ".local/share/dbus-1/services/org.freedesktop.Notifications.service").read_text()
        self.assertIn('desktop.sh\\" start', activation)

    def test_active_configs_have_no_retired_ui_dependencies(self):
        paths = [ROOT / "install.sh"]
        for folder in ("hypr", "matugen", "wal", "quickshell"):
            paths.extend(path for path in (ROOT / ".config" / folder).rglob("*")
                         if path.is_file() and "vendor" not in path.parts
                         and path.suffix in {".sh", ".py", ".qml", ".lua", ".conf", ".toml"})
        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                self.assertNotRegex(path.read_text(), r"(?i)\b(?:waybar|rofi|swaync|INSTALL_LEGACY_UI)\b")

    def test_matugen_only_generates_supported_app_palettes(self):
        config = tomllib.loads((ROOT / ".config/matugen/config.toml").read_text())
        self.assertEqual(set(config["templates"]), {"quickshell", "hyprland", "kitty", "neovim", "gtk3", "gtk4"})
        self.assertEqual(config["templates"]["quickshell"]["output_path"], "~/.config/quickshell/colors.css")
        self.assertNotIn("post_hook", config["templates"]["quickshell"])
        for template in config["templates"].values():
            self.assertTrue((ROOT / template["input_path"].removeprefix("~/")).is_file())

    def test_pywal_publishes_only_supported_palettes_without_restarting_ui(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            cache = home / ".cache/wal"
            cache.mkdir(parents=True)
            for source in (ROOT / ".config/wal/templates").iterdir():
                (cache / source.name).write_text("fixture palette")
            (home / ".config/kitty").mkdir(parents=True)
            binaries = home / "bin"
            binaries.mkdir()
            log = home / "calls"
            for name in ("hyprctl", "pkill", "gsettings"):
                command = binaries / name
                command.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$TEST_LOG"\n')
                command.chmod(0o755)
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / "state"),
                       PATH=str(binaries) + ":" + os.environ["PATH"], TEST_LOG=str(log))
            subprocess.run(["bash", str(ROOT / ".config/wal/scripts/wal-post.sh")],
                           env=env, capture_output=True, text=True, check=True)
            palette = home / ".config/quickshell/colors.css"
            self.assertEqual(palette.resolve(), cache / "colors-quickshell-custom.css")
            self.assertEqual(palette.read_text(), "fixture palette")
            for retired in ("waybar", "rofi", "swaync"):
                self.assertFalse((home / ".config" / retired).exists())
            calls = log.read_text()
            self.assertNotRegex(calls, r"waybar|rofi|swaync|quickshell|SIGUSR2")
            self.assertIn("hyprctl reload", calls)
            self.assertIn("pkill -USR1 -x kitty", calls)
            self.assertEqual((home / "state/hypr/color-generator").read_text(), "pywal\n")


if __name__ == "__main__":
    unittest.main()
