#!/usr/bin/env python3
"""Isolated Hyprland color/startup regressions; never lock the live display."""
import json
import os
from pathlib import Path
import resource
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest

REPO = Path(__file__).resolve().parents[1]
PALETTE = "$primary = rgba(123456ff)\n$secondary = rgba(abcdefFF)\n$inverse_primary = rgba(ffffffFF)\n"


class HyprlandConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hypr-config-test-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.config = self.home / ".config"
        self.state = root / "state" / "hypr"
        self.cache = self.home / ".cache" / "wal"
        self.bins = root / "bin"
        self.log = root / "commands"
        for directory in [self.config / "hypr/colors", self.config / "kitty", self.state, self.cache, self.bins]:
            directory.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_STATE_HOME=str(self.state.parent), XDG_CACHE_HOME=str(self.home / ".cache"),
                        PYWAL_CACHE_DIR=str(self.cache), PATH=f"{self.bins}:{os.environ['PATH']}",
                        TEST_LOG=str(self.log), XDG_RUNTIME_DIR=str(root), WAYLAND_DISPLAY="missing-display")
        mock = '''#!/usr/bin/env bash
printf '%s' "${0##*/}" >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\\n' >> "$TEST_LOG"
if [[ ${0##*/} == hyprctl ]]; then
    [[ -s "$XDG_STATE_HOME/hypr/color-generator" ]] || exit 2
    exit "${RELOAD_STATUS:-0}"
fi
'''
        for name in ["wal", "matugen", "hyprctl", "pkill", "gsettings"]:
            executable = self.bins / name
            executable.write_text(mock)
            executable.chmod(0o755)

    def run_script(self, path):
        return subprocess.run(["bash", str(REPO / path)], env=self.env, check=True, capture_output=True, text=True)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def generator(self, name):
        (self.state / "color-generator").write_text(name + "\n")

    def test_matugen_palette_is_preserved(self):
        self.generator("matugen")
        palette = self.config / "hypr/colors/colors.conf"
        palette.write_text(PALETTE)
        (self.cache / "colors.json").write_text("{}")
        self.run_script(".config/hypr/scripts/restore-colors.sh")
        self.assertEqual(self.calls(), [])
        self.assertEqual(palette.read_text(), PALETTE)

    def test_missing_matugen_palette_is_regenerated(self):
        self.generator("matugen")
        (self.config / "hypr/current_wallpaper").touch()
        self.run_script(".config/hypr/scripts/restore-colors.sh")
        self.assertEqual(self.calls(), [f"matugen image {self.config}/hypr/current_wallpaper"])

    def test_pywal_cache_is_restored_with_or_without_marker(self):
        (self.cache / "colors.json").write_text("{}")
        for marker in [None, "pywal"]:
            with self.subTest(marker=marker):
                if marker:
                    self.generator(marker)
                self.log.unlink(missing_ok=True)
                self.run_script(".config/hypr/scripts/restore-colors.sh")
                self.assertEqual(self.calls(), [f"wal -R -n -q -o {self.config}/wal/scripts/wal-post.sh"])

    def test_deleted_pywal_cache_uses_current_wallpaper(self):
        (self.config / "hypr/current_wallpaper").touch()
        self.run_script(".config/hypr/scripts/restore-colors.sh")
        self.assertEqual(self.calls(), [f"wal -n -q -i {self.config}/hypr/current_wallpaper --cols16 lighten -o {self.config}/wal/scripts/wal-post.sh"])

    def test_fresh_install_without_wallpaper_is_safe(self):
        self.run_script(".config/hypr/scripts/restore-colors.sh")
        self.assertEqual(self.calls(), [])

    def test_unknown_generator_does_not_restore_pywal(self):
        self.generator("unknown")
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_script(".config/hypr/scripts/restore-colors.sh")
        self.assertEqual(self.calls(), [])

    def test_hooks_record_generator_before_reload_and_tolerate_no_compositor(self):
        (self.cache / "colors-hyprland-custom.conf").write_text(PALETTE)
        for script, generator in [(".config/wal/scripts/wal-post.sh", "pywal"),
                                  (".config/matugen/hooks/reload-hyprland.sh", "matugen")]:
            for status in ["0", "1"]:
                with self.subTest(generator=generator, status=status):
                    self.log.unlink(missing_ok=True)
                    (self.state / "color-generator").unlink(missing_ok=True)
                    self.env["RELOAD_STATUS"] = status
                    self.run_script(script)
                    self.assertEqual((self.state / "color-generator").read_text().strip(), generator)
                    self.assertEqual(self.calls()[0], "hyprctl reload")
        config = tomllib.loads((REPO / ".config/matugen/config.toml").read_text())
        self.assertEqual(config["templates"]["hyprland"]["post_hook"], "~/.config/matugen/hooks/reload-hyprland.sh")

    def test_lua_is_the_only_compositor_entrypoint(self):
        config = REPO / ".config/hypr"
        self.assertTrue((config / "hyprland.lua").is_file())
        self.assertFalse((config / "hyprland.conf").exists())
        self.assertEqual(list((config / "hyprmodules").glob("*.conf")), [])
        self.assertTrue((config / "hyprlock.conf").is_file())
        self.assertTrue((config / "hypridle.conf").is_file())
        modules = re.findall(r'require\("hyprmodules\.([^"\n]+)"\)', (config / "hyprland.lua").read_text())
        self.assertEqual(set(modules), {path.stem for path in (config / "hyprmodules").glob("*.lua")})

    def test_only_unique_used_animation_curves_are_defined(self):
        source = (REPO / ".config/hypr/hyprmodules/lookandfeel.lua").read_text()
        curves = re.findall(r'hl\.curve\("([^"\n]+)"', source)
        selected = set(re.findall(r'bezier = "([^"\n]+)"', source))
        self.assertEqual(len(curves), len(set(curves)), "Duplicate curves shadow earlier definitions")
        self.assertEqual(set(curves), selected, "Every custom curve must be selected by an animation")
        self.assertEqual(selected, {"wind", "winIn", "liner", "md3_decel", "menu_decel", "easeOutCirc"})

    def test_obsolete_renderer_flags_and_placeholder_device_are_absent(self):
        modules = REPO / ".config/hypr/hyprmodules"
        environment = (modules / "enviromentvars.lua").read_text()
        self.assertNotRegex(environment, r"WLR_RENDERER|WLR_DRM_NO_ATOMIC")
        self.assertIn('hl.env("LIBVA_DRIVER_NAME", "iHD")', environment)
        inputs = (modules / "input.lua").read_text()
        self.assertNotIn("epic-mouse-v1", inputs)
        self.assertIn('kb_options = "caps:escape"', inputs)

    @unittest.skipUnless(shutil.which("lua"), "Lua is not installed")
    def test_palette_fallback_and_valid_colors(self):
        path = self.config / "hypr/colors/colors.conf"
        fallback = ["rgba(89b4faff)", "rgba(cba6f7ff)"]
        for palette, expected in [(None, fallback), ("", fallback),
                                  ("$primary = invalid\n$secondary =\n", fallback),
                                  (PALETTE, ["rgba(123456ff)", "rgba(abcdefFF)"]),
                                  ("$primary = rgb(123456)\n", ["rgb(123456)", fallback[1]])]:
            with self.subTest(palette=palette):
                if palette is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_text(palette)
                code = f"local c = dofile({json.dumps(str(REPO / '.config/hypr/hyprmodules/colors.lua'))}); print(c.primary); print(c.secondary)"
                result = subprocess.run(["lua", "-e", code],
                                        env=self.env, check=True, capture_output=True, text=True)
                self.assertEqual(result.stdout.splitlines(), expected)

    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_lua_config_without_generated_colors(self):
        shutil.copytree(REPO / ".config/hypr", self.config / "hypr", dirs_exist_ok=True)
        result = subprocess.run(["Hyprland", "--verify-config", "--config", str(self.config / "hypr/hyprland.lua")],
                                env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("hyprlock"), "Hyprlock is not installed")
    def test_hyprlock_parses_without_connecting_to_live_display(self):
        (self.config / "hypr/colors/colors.conf").write_text(PALETTE)
        result = subprocess.run(["hyprlock", "--config", str(REPO / ".config/hypr/hyprlock.conf"),
                                 "--display", self.tmp.name + "/missing-display"],
                                env=self.env, capture_output=True, text=True, timeout=10,
                                preexec_fn=lambda: resource.setrlimit(resource.RLIMIT_CORE, (0, 0)))
        output = result.stdout + result.stderr
        self.assertNotIn("Config error", output)
        self.assertNotIn("Config has errors", output)
        self.assertIn("Couldn't connect to a wayland compositor", output)


if __name__ == "__main__":
    unittest.main()
