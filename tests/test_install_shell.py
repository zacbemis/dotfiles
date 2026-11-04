"""Fresh-install shell prerequisites; Git clones are stubbed, never downloaded."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellBootstrap(unittest.TestCase):
    def test_configured_custom_plugins_are_installed_once_in_the_custom_directory(self):
        installer = (ROOT / "install.sh").read_text()
        block = re.search(r"(?ms)^# ── zsh plugins[^\n]*\n(.*?)^# ── nvm", installer)
        self.assertIsNotNone(block)
        shell = (ROOT / ".zshrc").read_text()
        for plugin in ("zsh-autosuggestions", "zsh-syntax-highlighting"):
            self.assertIn(plugin, shell)
            self.assertIn(plugin, block[1])
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, custom, binaries = root / "home", root / "custom", root / "bin"
            home.mkdir()
            binaries.mkdir()
            log = root / "clones.jsonl"
            git = binaries / "git"
            git.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
with open(os.environ["CLONE_LOG"], "a") as log: log.write(json.dumps(sys.argv[1:]) + "\\n")
pathlib.Path(sys.argv[-1]).mkdir(parents=True)
''')
            git.chmod(0o755)
            env = dict(os.environ, HOME=str(home), ZSH_CUSTOM=str(custom),
                       PATH=str(binaries) + ":" + os.environ["PATH"], CLONE_LOG=str(log))
            env.pop("BASH_ENV", None)
            env.pop("ENV", None)
            for _ in range(2):
                subprocess.run(["bash", "-euc", 'info() { :; }\n' + block[1]], env=env,
                               check=True, capture_output=True, text=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(calls), 2, "Existing plugins must not be recloned or reset")
            for plugin, call in zip(("zsh-autosuggestions", "zsh-syntax-highlighting"), calls):
                self.assertEqual(call, ["clone", "--depth=1", f"https://github.com/zsh-users/{plugin}.git", str(custom / "plugins" / plugin)])
                self.assertTrue((custom / "plugins" / plugin).is_dir())
            self.assertFalse((home / ".oh-my-zsh").exists(), "Honor a custom Oh My Zsh location")

    def test_nvm_initializer_uses_the_same_user_directory_as_both_shell_configs(self):
        installer = (ROOT / "install.sh").read_text()
        self.assertIn('NVM_DIR="$HOME/.config/nvm" bash -c \'source /usr/share/nvm/init-nvm.sh\'', installer)
        for name in (".zshenv", ".zshrc"):
            source = (ROOT / name).read_text()
            self.assertIn('export NVM_DIR="$HOME/.config/nvm"', source)
            self.assertIn('"$NVM_DIR/nvm.sh"', source)


if __name__ == "__main__":
    unittest.main()
