"""Shell startup remains usable on both the desktop and a headless server."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
class ZshEnvironment(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin"}

    def nvm(self, directory):
        directory.mkdir(parents=True)
        (directory / "nvm.sh").write_text('export TEST_NVM_LOADED=1\nnvm() { return 0; }\n')
        return directory

    def run_zsh(self, command):
        result = subprocess.run(
            ["zsh", "-dfc", 'source "$1"; ' + command, "zsh", str(ROOT / ".zshenv")],
            env=self.env, capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        return result.stdout.strip()

    def test_nvm_uses_existing_server_install(self):
        directory = self.nvm(self.home / ".nvm")
        self.assertEqual(self.run_zsh('print -r -- "$NVM_DIR:$TEST_NVM_LOADED"'), f"{directory}:1")

    def test_nvm_prefers_xdg_install(self):
        directory = self.nvm(self.home / "config/nvm")
        self.nvm(self.home / ".nvm")
        self.env["XDG_CONFIG_HOME"] = str(self.home / "config")
        self.assertEqual(self.run_zsh('print -r -- "$NVM_DIR:$TEST_NVM_LOADED"'), f"{directory}:1")

    def test_nvm_respects_explicit_install(self):
        directory = self.nvm(self.home / "custom-nvm")
        self.env["NVM_DIR"] = str(directory)
        self.assertEqual(self.run_zsh('print -r -- "$NVM_DIR:$TEST_NVM_LOADED"'), f"{directory}:1")

    def test_missing_nvm_and_agent_are_not_errors(self):
        self.assertEqual(self.run_zsh('print -r -- "${SSH_AUTH_SOCK-unset}"'), "unset")

    def test_forwarded_agent_is_preserved(self):
        self.env["SSH_AUTH_SOCK"] = "/forwarded/agent.sock"
        self.assertEqual(self.run_zsh('print -r -- "$SSH_AUTH_SOCK"'), "/forwarded/agent.sock")

    def test_desktop_agent_is_used_only_when_socket_exists(self):
        self.env["XDG_RUNTIME_DIR"] = str(self.home)
        path = self.home / "ssh-agent.socket"
        self.assertEqual(self.run_zsh('print -r -- "${SSH_AUTH_SOCK-unset}"'), "unset")
        with socket.socket(socket.AF_UNIX) as agent:
            agent.bind(str(path))
            self.assertEqual(self.run_zsh('print -r -- "$SSH_AUTH_SOCK"'), str(path))
            self.env["SSH_AUTH_SOCK"] = "/forwarded/agent.sock"
            self.assertEqual(self.run_zsh('print -r -- "$SSH_AUTH_SOCK"'), "/forwarded/agent.sock")

    def test_user_executables_are_available_without_interactive_startup(self):
        self.assertEqual(
            self.run_zsh('print -r -- "$path[1]:$path[2]"'),
            f"{self.home}/.local/bin:{self.home}/.cargo/bin",
        )

    def test_dotnet_root_is_set_only_for_existing_install(self):
        self.assertEqual(self.run_zsh('print -r -- "${DOTNET_ROOT-unset}"'), "unset")
        (self.home / ".dotnet").mkdir()
        self.assertEqual(self.run_zsh('print -r -- "$DOTNET_ROOT"'), str(self.home / ".dotnet"))
        self.env["DOTNET_ROOT"] = "/custom/dotnet"
        self.assertEqual(self.run_zsh('print -r -- "$DOTNET_ROOT"'), "/custom/dotnet")


class BashEnvironment(unittest.TestCase):
    def test_login_retains_host_profile_and_interactive_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".profile").write_text('export TEST_HOST_SDK=loaded\n')
            (home / ".bashrc").write_text('export TEST_BASHRC=loaded\n')
            env = dict(os.environ, HOME=tmp)
            result = subprocess.run(
                ["bash", "--noprofile", "--norc", "-c",
                 'source "$1"; printf "%s:%s" "$TEST_HOST_SDK" "$TEST_BASHRC"',
                 "bash", str(ROOT / ".bash_profile")],
                env=env, capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "loaded:loaded")
