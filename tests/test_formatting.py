from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("clang-format"), "clang-format is not installed")
class ClangFormatting(unittest.TestCase):
    def test_home_defaults_to_four_spaces_and_project_style_wins(self):
        source = "int main() {\nif (1) {\nreturn 0;\n}\nreturn 1;\n}\n"
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".clang-format").symlink_to(ROOT / ".clang-format")
            project = home / "project"
            project.mkdir()

            def format_source(filename):
                return subprocess.run(
                    ["clang-format", "--style=file", f"--assume-filename={project / filename}"],
                    input=source, text=True, capture_output=True, check=True, timeout=5,
                ).stdout.splitlines()

            for filename in ("main.c", "main.cpp"):
                with self.subTest(filename=filename):
                    self.assertEqual(format_source(filename)[1:3], ["    if (1) {", "        return 0;"])

            (project / ".clang-format").write_text("BasedOnStyle: LLVM\nIndentWidth: 2\n")
            self.assertEqual(format_source("main.c")[1:3], ["  if (1) {", "    return 0;"])
