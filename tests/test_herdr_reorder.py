"""Check Herdr's Rust helper wiring; socket/ordering tests live in its Cargo crate."""

import json
from pathlib import Path
import subprocess
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HerdrControlConfigTests(unittest.TestCase):
    def setUp(self):
        self.config = tomllib.loads((ROOT / ".config/herdr/config.toml").read_text())
        self.commands = {
            command["key"]: command for command in self.config["keys"]["command"]
        }

    def test_shortcuts_use_installed_rust_binary(self):
        for key, action in (
            ("alt+n", "new-tab"),
            ("alt+shift+h", "tab-left"),
            ("alt+shift+l", "tab-right"),
            ("alt+shift+j", "workspace-down"),
            ("alt+shift+k", "workspace-up"),
        ):
            with self.subTest(key=key):
                command = self.commands[key]
                self.assertEqual(command["type"], "shell")
                self.assertEqual(
                    command["command"], f'"$HOME/.local/bin/herdr-control" {action}'
                )
        self.assertEqual(self.config["keys"]["new_tab"], "")

    def test_python_helper_is_removed(self):
        self.assertFalse((ROOT / ".config/herdr/reorder.py").exists())
        manifest = json.loads((ROOT / "tool-settings/manifest.json").read_text())
        self.assertNotIn(".config/herdr/reorder.py", manifest["files"])

    def test_rust_sources_and_lockfile_are_not_ignored(self):
        crate = ROOT / "tools/herdr-control"
        paths = [crate / "Cargo.toml", crate / "Cargo.lock", *crate.glob("src/*.rs")]
        result = subprocess.run(
            ["git", "check-ignore", *map(str, paths)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        build = subprocess.run(
            ["git", "check-ignore", "tools/herdr-control/target/release/herdr-control"],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(build.returncode, 0)


if __name__ == "__main__":
    unittest.main()
