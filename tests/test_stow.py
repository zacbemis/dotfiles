"""Deployment hygiene: only source configs and intentional skills reach HOME."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RemovedArtifacts(unittest.TestCase):
    def test_obsolete_refactor_document_and_component_are_absent(self):
        self.assertFalse((ROOT / "hyprland-lua-refactor.md").exists())
        self.assertFalse((ROOT / ".config/quickshell/modules/comparison/FeatureChoice.qml").exists())


@unittest.skipUnless(shutil.which("stow"), "GNU Stow is not installed")
class StowDeployment(unittest.TestCase):
    def test_runtime_bytecode_tests_and_maintenance_scripts_are_not_deployed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package = root / "dotfiles"
            home = root / "home"
            package.mkdir()
            home.mkdir()
            shutil.copy2(ROOT / ".stow-local-ignore", package / ".stow-local-ignore")
            for relative in (
                ".config/demo/config.lua", ".config/demo/helper.py",
                ".config/demo/__pycache__/helper.cpython-314.pyc",
                ".config/demo/loose.pyc", ".config/demo/loose.pyo",
                "tests/test_demo.py", "scripts/setup-agent-dev-server.sh", "tool-settings/manifest.json",
                ".agents/skills/local/STATE.md", ".gemini/config/auth.json",
                "README.md", "skills/system/example/SKILL.md",
            ):
                path = package / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            subprocess.run(["stow", "--no-folding", "--dir", str(package), "--target", str(home), "."],
                           check=True, capture_output=True, text=True)
            for relative in (".config/demo/config.lua", ".config/demo/helper.py", "skills/system/example/SKILL.md"):
                with self.subTest(deployed=relative):
                    self.assertTrue((home / relative).is_symlink())
                    self.assertEqual((home / relative).resolve(), package / relative)
            for relative in (".config/demo/__pycache__", ".config/demo/loose.pyc", ".config/demo/loose.pyo",
                             "tests", "scripts", "tool-settings", ".agents", ".gemini", "README.md", ".stow-local-ignore"):
                with self.subTest(ignored=relative):
                    self.assertFalse((home / relative).exists())
                    self.assertFalse((home / relative).is_symlink())

    @unittest.skipUnless(shutil.which("git"), "Git is not installed")
    def test_entire_tracked_checkout_stows_unstows_and_restows_without_conflicts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package, home = root / "dotfiles", root / "home"
            package.mkdir()
            home.mkdir()
            names = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
            for name in filter(None, names):
                target = package / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, target)
            private = home / ".claude/.credentials.json"
            private.parent.mkdir()
            private.write_text("local-only")
            command = ["stow", "--no-folding", "--dir", str(package), "--target", str(home)]
            env = dict(os.environ, HOME=str(home))
            subprocess.run([*command, "."], env=env, check=True, capture_output=True, text=True)
            for name in (".gitconfig", ".config/hypr/hyprland.lua", ".config/hypr/scripts/display-power.sh",
                         ".config/quickshell/shell.qml", ".config/nvim/init.lua", ".pi/agent/settings.json",
                         ".claude/settings.json", "skills/system/run-workflow/SKILL.md"):
                with self.subTest(path=name):
                    self.assertTrue((home / name).is_symlink())
                    self.assertEqual((home / name).resolve(), package / name)
            for path in home.rglob("*"):
                if path.is_symlink():
                    self.assertFalse(os.path.isabs(os.readlink(path)), str(path))
                    self.assertTrue(path.resolve().is_relative_to(package))
            second = subprocess.run([*command, "--simulate", "--verbose", "."], env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertNotIn("LINK:", second.stdout + second.stderr)
            subprocess.run([*command, "--restow", "."], env=env, check=True, capture_output=True, text=True)
            self.assertTrue((home / ".claude/settings.json").is_symlink())
            self.assertEqual(private.read_text(), "local-only")
            subprocess.run([*command, "--delete", "."], env=env, check=True, capture_output=True, text=True)
            self.assertFalse((home / ".claude/settings.json").is_symlink())
            self.assertEqual(private.read_text(), "local-only")
            subprocess.run([*command, "."], env=env, check=True, capture_output=True, text=True)
            self.assertTrue((home / ".claude/settings.json").is_symlink())
            self.assertEqual(private.read_text(), "local-only")

    def test_installer_does_not_silently_adopt_local_files_into_git(self):
        installer = (ROOT / "install.sh").read_text()
        self.assertNotIn("--adopt .", installer)
        self.assertIn('stow --no-folding --target="$HOME" .', installer)


if __name__ == "__main__":
    unittest.main()
