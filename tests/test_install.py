"""Run the complete installer in a temporary HOME with all system/network work mocked.

Stow, optional offline Hyprlock parsing and filesystem utilities are real. No packages are installed,
services started, login shells changed, or network requests made.
"""
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
STOW = shutil.which("stow")

MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["INSTALL_LOG"], "a") as log:
    log.write(json.dumps({"command": name, "args": args, "cwd": os.getcwd()}) + "\n")
home = pathlib.Path(os.environ["HOME"])
bin = pathlib.Path(os.environ["MOCK_BIN"])
if name == "id":
    print(os.environ.get("MOCK_UID", "1000"))
elif name == "getent":
    shell = pathlib.Path(os.environ["SHELL_STATE"]).read_text().strip()
    print(f"fixture:x:1000:1000::{home}:{shell}")
elif name == "yay":
    sys.exit(int(os.environ.get("YAY_FAIL", "0")))
elif name == "sudo":
    if not args or args[0] not in {"pacman", "systemctl"}:
        raise SystemExit("Unexpected privileged command")
elif name == "git":
    assert args[:2] == ["clone", "--depth=1"] or args[0] == "clone", args
    pathlib.Path(args[-1]).mkdir(parents=True)
elif name == "makepkg":
    if os.environ.get("MAKEPKG_FAIL"):
        raise SystemExit(1)
    (bin / "yay").symlink_to(pathlib.Path(__file__).resolve())
elif name == "curl":
    if os.environ.get("CURL_FAIL"):
        raise SystemExit(22)
    print(''' + repr('''printf '%s:%s:%s\n' "${RUNZSH:-}" "${KEEP_ZSHRC:-}" "${CHSH:-}" > "$OMZ_FLAGS"
mkdir -p "$HOME/.oh-my-zsh"
if [ ! -f "$HOME/.zshrc" ]; then printf '# generated Oh My Zsh settings\n' > "$HOME/.zshrc"; fi
''') + r''')
elif name == "bash":
    assert args == ["-c", "source /usr/share/nvm/init-nvm.sh"], args
    directory = pathlib.Path(os.environ["NVM_DIR"])
    directory.mkdir(parents=True, exist_ok=True)
    for script in ("nvm.sh", "nvm-exec"):
        path = directory / script
        if not path.exists(): path.write_text("fixture loader")
elif name == "gsettings":
    if args == ["list-schemas"]:
        # More than a pipe buffer: grep -q would exit early and break pipefail.
        print("org.gnome.desktop.interface")
        sys.stdout.write("".join(f"org.example.fixture{i}\n" for i in range(12000)))
    elif args[:1] != ["set"]:
        raise SystemExit("Unexpected gsettings operation")
    elif os.environ.get("GSETTINGS_FAIL"):
        raise SystemExit(1)
elif name == "chsh":
    assert args == ["-s", str(bin / "zsh")], args
    pathlib.Path(os.environ["SHELL_STATE"]).write_text(str(bin / "zsh"))
elif name == "systemctl":
    if args and args[0] == "is-enabled": raise SystemExit(0)
    if args and args[0] == "is-active": raise SystemExit(1)
elif name not in {"pacman", "zsh"}:
    raise SystemExit("Unexpected mock command: " + name)
'''


@unittest.skipUnless(BASH and STOW, "Bash and GNU Stow are required")
class InstallerFlow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-installer-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "checkout"
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        for directory in (self.repo, self.home, self.bin, self.root / "tmp"):
            directory.mkdir()
        shutil.copy2(ROOT / "install.sh", self.repo / "install.sh")
        shutil.copy2(ROOT / ".stow-local-ignore", self.repo / ".stow-local-ignore")
        (self.repo / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/tool-settings.py", self.repo / "scripts/tool-settings.py")
        files = {".bashrc": "# repository bashrc\n", ".bash_profile": "# repository login\n",
                 ".zshrc": "# repository zshrc\n", ".claude/settings.json": '{"model":"fixture"}\n'}
        for name, data in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        (self.repo / "tool-settings").mkdir()
        (self.repo / "tool-settings/manifest.json").write_text(json.dumps({"files": list(files)}))
        (self.repo / ".config/demo").mkdir(parents=True)
        (self.repo / ".config/demo/settings.conf").write_text("repository settings\n")
        (self.repo / ".config/hypr").mkdir()
        shutil.copy2(ROOT / ".config/hypr/hyprlock.conf", self.repo / ".config/hypr/hyprlock.conf")
        (self.home / ".bashrc").write_text("# Arch skeleton bashrc\n")
        (self.home / ".bash_profile").write_text("# Arch skeleton profile\n")
        self.private = self.home / ".claude/.credentials.json"
        self.private.parent.mkdir()
        self.private.write_text("local-only-auth")
        self.log = self.root / "commands.jsonl"
        self.state = self.root / "login-shell"
        self.state.write_text("/bin/bash")
        driver = self.root / "mock-command.py"
        driver.write_text(MOCK)
        driver.chmod(0o755)
        for name in ("id", "getent", "yay", "sudo", "pacman", "git", "curl", "makepkg", "bash", "gsettings", "chsh", "systemctl", "zsh"):
            (self.bin / name).symlink_to(driver)
        for name in ("mkdir", "rm", "mv", "mktemp", "dirname", "grep", "sh", "python3", "stow"):
            executable = shutil.which(name)
            self.assertIsNotNone(executable, name)
            (self.bin / name).symlink_to(executable)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin),
                        TMPDIR=str(self.root / "tmp"), SHELL="/bin/bash", INSTALL_LOG=str(self.log),
                        MOCK_BIN=str(self.bin), SHELL_STATE=str(self.state), OMZ_FLAGS=str(self.root / "omz-flags"),
                        XDG_STATE_HOME=str(self.home / ".local/state"), XDG_CONFIG_HOME=str(self.home / ".config"))
        for key in ("BASH_ENV", "ENV", "ZSH", "ZSH_CUSTOM", "NVM_DIR", "NVM_BIN", "NVM_INC"):
            self.env.pop(key, None)

    def run_installer(self, *arguments, **overrides):
        return subprocess.run([BASH, str(self.repo / "install.sh"), *arguments], cwd=self.repo,
                              env=dict(self.env, **overrides), text=True, capture_output=True, timeout=20)

    def calls(self, command):
        if not self.log.exists():
            return []
        return [row for row in (json.loads(line) for line in self.log.read_text().splitlines()) if row["command"] == command]

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.private.read_text(), "local-only-auth")
        for name in (".bashrc", ".bash_profile", ".zshrc", ".claude/settings.json", ".config/demo/settings.conf"):
            path = self.home / name
            self.assertTrue(path.is_symlink(), name)
            self.assertFalse(os.path.isabs(os.readlink(path)), name)
            self.assertEqual(path.resolve(), self.repo / name)

    def test_fresh_home_defaults_are_backed_up_then_stowed(self):
        result = self.run_installer()
        self.assert_success(result)
        self.assertEqual((self.root / "omz-flags").read_text().strip(), "no:yes:no")
        palette = self.home / ".config/hypr/colors/colors.conf"
        self.assertIn("$primary = rgba(", palette.read_text())
        self.assertIn("$inverse_primary = rgba(", palette.read_text())
        if hyprlock := shutil.which("hyprlock"):
            parsed = subprocess.run([hyprlock, "--config", str(self.home / ".config/hypr/hyprlock.conf"),
                                     "--display", str(self.root / "missing-display")],
                                    env=self.env, text=True, capture_output=True, timeout=10,
                                    preexec_fn=lambda: resource.setrlimit(resource.RLIMIT_CORE, (0, 0)))
            output = parsed.stdout + parsed.stderr
            self.assertNotIn("Config error", output)
            self.assertNotIn("Config has errors", output)
            self.assertIn("Couldn't connect to a wayland compositor", output)
        backups = list((self.home / ".local/state/dotfiles-tool-settings").glob("*/.bashrc"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "# Arch skeleton bashrc\n")
        installed = {package for call in self.calls("yay") for package in call["args"]}
        self.assertTrue({"base-devel", "curl", "git", "github-cli", "playerctl", "quickshell", "helium-browser-bin", "xdg-desktop-portal-gtk"}.issubset(installed))
        self.assertNotIn("waybar", installed)
        self.assertEqual(len(self.calls("gsettings")), 3, "Schema probe must drain its producer and apply both fonts")
        self.assertEqual([row["args"] for row in self.calls("sudo")],
                         [["systemctl", "enable", "--now", "NetworkManager"], ["systemctl", "enable", "--now", "bluetooth"]])

    def test_repeat_run_keeps_checkout_and_does_not_reclone_or_repeat_chsh(self):
        self.assert_success(self.run_installer())
        first_clones = len(self.calls("git"))
        self.assert_success(self.run_installer())
        self.assertEqual(len(self.calls("git")), first_clones)
        self.assertEqual(len(self.calls("chsh")), 1, "Read the actual login shell, not stale SHELL")
        self.assertEqual((self.repo / ".bashrc").read_text(), "# repository bashrc\n")

    def test_missing_yay_is_built_and_temporary_build_is_removed(self):
        (self.bin / "yay").unlink()
        self.assert_success(self.run_installer())
        self.assertEqual(self.calls("sudo")[0]["args"], ["pacman", "-S", "--needed", "--noconfirm", "base-devel", "git"])
        self.assertEqual(len(self.calls("makepkg")), 1)
        self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_failed_yay_build_cleans_up_and_stops(self):
        (self.bin / "yay").unlink()
        result = self.run_installer(MAKEPKG_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((self.root / "tmp").iterdir()), [])
        self.assertFalse((self.home / ".bashrc").is_symlink())
        self.assertEqual(self.private.read_text(), "local-only-auth")

    def test_failed_oh_my_zsh_download_does_not_continue_with_an_empty_script(self):
        result = self.run_installer(CURL_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / ".oh-my-zsh").exists())
        self.assertFalse((self.home / ".bashrc").is_symlink())
        self.assertEqual(self.calls("chsh"), [])

    def test_unreviewed_desktop_conflict_is_not_adopted_or_overwritten(self):
        path = self.home / ".config/demo/settings.conf"
        path.parent.mkdir(parents=True)
        path.write_text("unreviewed local settings\n")
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), "unreviewed local settings\n")
        self.assertEqual((self.repo / ".config/demo/settings.conf").read_text(), "repository settings\n")
        self.assertEqual(self.private.read_text(), "local-only-auth")
        self.assertEqual(self.calls("chsh"), [])

    def test_root_and_non_arch_preflights_fail_before_package_operations(self):
        result = self.run_installer(MOCK_UID="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("normal user", result.stdout)
        self.assertEqual(self.calls("yay"), [])
        self.assertEqual(self.calls("sudo"), [])
        (self.bin / "pacman").unlink()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Arch Linux", result.stdout)
        self.assertEqual(self.calls("yay"), [])

    def test_missing_graphical_settings_bus_warns_without_aborting_install(self):
        result = self.run_installer(GSETTINGS_FAIL="1")
        self.assert_success(result)
        self.assertIn("Could not apply GTK/portal font preferences", result.stdout)
        self.assertEqual(len(self.calls("chsh")), 1)

    def test_package_install_failure_stops_before_config_changes(self):
        result = self.run_installer(YAY_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / ".bashrc").is_symlink())
        self.assertEqual((self.home / ".bashrc").read_text(), "# Arch skeleton bashrc\n")
        self.assertEqual(self.private.read_text(), "local-only-auth")
        self.assertEqual(self.calls("curl"), [])
        self.assertEqual(self.calls("chsh"), [])

    def test_existing_palette_and_generator_recovery_state_are_preserved(self):
        palette = self.home / ".config/hypr/colors/colors.conf"
        palette.parent.mkdir(parents=True)
        palette.write_text("existing custom palette\n")
        marker = self.home / ".local/state/hypr/color-generator"
        marker.parent.mkdir(parents=True)
        marker.write_text("matugen\n")
        self.assert_success(self.run_installer())
        self.assertEqual(palette.read_text(), "existing custom palette\n")
        self.assertEqual(marker.read_text(), "matugen\n")
        palette.unlink()
        self.assert_success(self.run_installer())
        self.assertFalse(palette.exists(), "Do not mask a saved generator's missing-palette recovery")
        self.assertEqual(marker.read_text(), "matugen\n")

    def test_help_and_unsupported_options_never_start_an_install(self):
        result = self.run_installer("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage: ./install.sh", result.stdout)
        result = self.run_installer("--dry-run")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls("yay"), [])
        self.assertEqual(self.calls("sudo"), [])
        self.assertFalse((self.home / ".bashrc").is_symlink())

    def test_unset_shell_environment_is_supported(self):
        self.env.pop("SHELL", None)
        self.assert_success(self.run_installer())
        self.assertEqual(len(self.calls("chsh")), 1)


if __name__ == "__main__":
    unittest.main()
