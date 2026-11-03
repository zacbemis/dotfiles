"""Deployment hygiene: only source configs and intentional skills reach HOME."""
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
                "tests/test_demo.py", "scripts/setup-agent-dev-server.sh",
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
                             "tests", "scripts", "README.md", ".stow-local-ignore"):
                with self.subTest(ignored=relative):
                    self.assertFalse((home / relative).exists())
                    self.assertFalse((home / relative).is_symlink())


if __name__ == "__main__":
    unittest.main()
