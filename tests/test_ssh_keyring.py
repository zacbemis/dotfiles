"""SSH login setup uses mocked packages/services, never the real agent or secrets."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SSHKeyringSetup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.log = self.home / "calls.jsonl"
        mock = self.bin / "mock"
        mock.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + "\\n")
if name == "id": print(os.environ.get("TEST_UID", "1000"))
if name == "pacman": sys.exit(int(os.environ.get("MISSING_PACKAGES", "0")))
if name == "sudo": sys.exit(int(os.environ.get("INSTALL_FAILURE", "0")))
''')
        mock.chmod(0o755)
        for command in ("id", "pacman", "sudo", "systemctl"):
            (self.bin / command).symlink_to(mock)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin), CALL_LOG=str(self.log))
        self.env.pop("BASH_ENV", None)
        self.env.pop("ENV", None)

    def run_setup(self, **overrides):
        return subprocess.run(["/bin/bash", str(ROOT / "scripts/setup-ssh-keyring.sh")],
                              env=dict(self.env, **overrides), capture_output=True, text=True, timeout=5)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_existing_packages_enable_keyring_without_stopping_live_agent(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertFalse(any(call[0] == "sudo" for call in calls))
        self.assertIn(["systemctl", "--user", "disable", "ssh-agent.socket", "ssh-agent.service"], calls)
        self.assertIn(["systemctl", "--user", "enable", "--now",
                       "gnome-keyring-daemon.socket", "gcr-ssh-agent.socket"], calls)
        self.assertFalse(any("stop" in call or "restart" in call for call in calls))

    def test_missing_packages_are_installed_before_services(self):
        result = self.run_setup(MISSING_PACKAGES="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        install = ["sudo", "pacman", "-S", "--needed", "openssh", "gcr-4", "gnome-keyring", "seahorse"]
        self.assertIn(install, calls)
        self.assertLess(calls.index(install), next(i for i, call in enumerate(calls) if call[0] == "systemctl"))

    def test_failed_install_leaves_agents_unchanged(self):
        result = self.run_setup(MISSING_PACKAGES="1", INSTALL_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "systemctl" for call in self.calls()))

    def test_root_is_rejected_before_changes(self):
        self.assertNotEqual(self.run_setup(TEST_UID="0").returncode, 0)
        self.assertEqual(self.calls(), [["id", "-u"]])

    def test_desktop_session_uses_gcr_socket(self):
        self.assertEqual((ROOT / ".config/environment.d/10-ssh-agent.conf").read_text(),
                         "SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/gcr/ssh\n")


if __name__ == "__main__":
    unittest.main()
