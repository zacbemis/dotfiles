"""Tool preferences are reproducible without publishing local account/trust state."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tool_settings", ROOT / "scripts/tool-settings.py")
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class ToolSources(unittest.TestCase):
    def test_manifest_sources_exist_parse_and_have_no_credential_literals(self):
        files = list(tools.managed_files(ROOT))
        self.assertEqual(len(files), len(set(files)))
        for required in (".config/herdr/config.toml", ".claude/settings.json", ".claude/CLAUDE.md",
                         ".pi/agent/AGENTS.md", ".pi/agent/settings.json", ".pi/agent/extensions/herdr-agent-state.ts",
                         ".copilot/settings.json", ".codex/hooks.json", ".config/Code/User/settings.json"):
            self.assertIn(Path(required), files)
        for relative in files:
            with self.subTest(path=relative):
                path = ROOT / relative
                text = path.read_text()
                self.assertIsNone(tools.CREDENTIAL.search(text), f"Credential-shaped data in {relative}")
                if path.suffix in {".json", ".jsonc"}:
                    tools.check_preferences(tools.jsonc(text))
                elif path.suffix == ".toml":
                    tomllib.loads(text)

    def test_preference_snapshots_have_only_owned_keys_and_no_private_state(self):
        for name, _, keys in tools.JSON_PREFERENCES:
            data = json.loads((ROOT / "tool-settings" / name).read_text())
            with self.subTest(snapshot=name):
                tools.check_preferences(data)
                self.assertLessEqual(set(data), set(keys))
        codex = json.loads((ROOT / "tool-settings/codex.json").read_text())
        tools.check_preferences(codex)
        self.assertLessEqual(set(codex), set(tools.CODEX_KEYS))

    def test_hook_commands_are_portable_and_scripts_are_included(self):
        configs = {
            ".claude/settings.json": ".claude/hooks/herdr-agent-state.sh",
            ".codex/hooks.json": ".codex/herdr-agent-state.sh",
            ".cursor/hooks.json": ".cursor/herdr-agent-state.sh",
            ".copilot/settings.json": ".copilot/hooks/herdr-agent-state.sh",
        }
        def commands(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key in {"command", "bash"} and isinstance(item, str):
                        yield item
                    else:
                        yield from commands(item)
            elif isinstance(value, list):
                for item in value:
                    yield from commands(item)

        with tempfile.TemporaryDirectory() as tmp:
            for config, script in configs.items():
                with self.subTest(tool=config):
                    data = (ROOT / config).read_text()
                    self.assertIn("$HOME/" + script, data)
                    self.assertNotIn("/home/zacb/", data)
                    path = ROOT / script
                    subprocess.run(["bash", "-n", str(path)], check=True, capture_output=True)
                    env = dict(os.environ, TMPDIR=tmp)
                    for key in ("HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID"):
                        env.pop(key, None)
                    result = subprocess.run(["bash", str(path), "session"], env=env, input="{}",
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    # Verify HOME expansion and argument delivery with both shell
                    # execution and direct argv parsing. Never contact real Herdr.
                    fake = Path(tmp) / script
                    fake.parent.mkdir(parents=True, exist_ok=True)
                    fake.write_text('#!/bin/sh\nprintf "%s" "$*" > "$TEST_LOG"\n')
                    marker = Path(tmp) / "arguments"
                    env.update(HOME=tmp, TEST_LOG=str(marker))
                    for command in commands(tools.jsonc(data)):
                        for argv in (["bash", "-c", command], shlex.split(command)):
                            marker.unlink(missing_ok=True)
                            subprocess.run(argv, env=env, check=True, capture_output=True, timeout=5)
                            self.assertEqual(marker.read_text(), "" if config == ".copilot/settings.json" else "session")

    @unittest.skipUnless(shutil.which("git"), "Git is not installed")
    def test_private_runtime_paths_are_ignored_and_managed_sources_are_not(self):
        private = [".ssh/config", ".ssh/id_ed25519", ".gnupg/private-keys-v1.d/key", ".npmrc", ".netrc",
                   ".bash_history", ".zsh_history", ".claude.json", ".claude/.credentials.json", ".claude/projects/example/history.jsonl",
                   ".claude/plugins/installed_plugins.json", ".codex/auth.json", ".codex/config.toml",
                   ".codex/state_5.sqlite", ".cursor/agent-cli-state.json", ".cursor/argv.json",
                   ".cursor/extensions/extensions.json", ".copilot/config.json", ".copilot/chats/private.json",
                   ".pi/agent/auth.json", ".pi/agent/models-store.json", ".pi/agent/trust.json",
                   ".pi/agent/npm/package.json", ".pi/agent/sessions/example.jsonl", ".pi/web-search-cache/private.json",
                   ".config/cursor/cli-config.json", ".config/pi/web-search-cache/private.json",
                   ".config/nvm/versions/node/bin/node", ".config/github-copilot/apps.json", ".config/gh/hosts.yml",
                   ".config/herdr/session.json", ".config/herdr/herdr.sock", ".config/opencode/node_modules/private.js",
                   ".config/Code/User/globalStorage/state.vscdb", ".config/Cursor/User/workspaceStorage/private.json",
                   ".gemini/antigravity-acp/settings.json"]
        managed = [str(path) for path in tools.managed_files(ROOT)]
        result = subprocess.run(["git", "check-ignore", "--no-index", "--stdin"], cwd=ROOT,
                                input="\n".join(private + managed) + "\n", text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(result.stdout.splitlines()), set(private))

    def test_extension_manifests_are_unique_identifiers_not_install_metadata(self):
        for name in ("vscode-extensions.txt", "cursor-extensions.txt"):
            ids = (ROOT / "tool-settings" / name).read_text().splitlines()
            self.assertEqual(ids, sorted(set(ids)))
            self.assertIn("vscodevim.vim", ids)
            for extension in ids:
                self.assertRegex(extension, r"^[a-zA-Z0-9-]+\.[a-zA-Z0-9_.-]+$")


class PreferenceBoundaries(unittest.TestCase):
    def setUp(self):
        output = redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        self.home = Path(self.tmp.name) / "home"
        self.backups = Path(self.tmp.name) / "private-backup"
        self.root.mkdir()
        self.home.mkdir()

    def put(self, base, relative, value):
        path = base / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value if isinstance(value, str) else json.dumps(value))
        return path

    def test_jsonc_keeps_urls_and_comment_like_text_inside_strings(self):
        text = '// comment\n{"url":"https://example.test/", "literal":",} /*keep*/ //keep", /*comment*/ "list":[1,],}'
        self.assertEqual(tools.jsonc(text), {"url": "https://example.test/", "literal": ",} /*keep*/ //keep", "list": [1]})

    def test_capture_filters_account_cache_and_project_hook_trust(self):
        self.put(self.home, ".config/cursor/cli-config.json", {
            "editor": {"vimMode": True}, "authInfo": {"token": "local-only"}, "privacyCache": {"account": "local-only"}})
        self.put(self.home, ".cursor/argv.json", {"password-store": "basic", "crash-reporter-id": "local-machine"})
        self.put(self.home, ".gemini/antigravity-cli/settings.json", {"model": "fixture", "trustedWorkspaces": ["/private"]})
        self.put(self.home, ".codex/config.toml", 'model = "fixture"\nmodel_reasoning_effort = "low"\n[features]\nhooks = true\n[projects."/private"]\ntrust_level = "trusted"\n[hooks.state.fixture]\ntrusted_hash = "private-hash"\n')
        tools.capture(self.root, self.home)
        snapshots = self.root / "tool-settings"
        self.assertEqual(json.loads((snapshots / "cursor-cli.json").read_text()), {"editor": {"vimMode": True}})
        self.assertEqual(json.loads((snapshots / "cursor-argv.json").read_text()), {"password-store": "basic"})
        self.assertEqual(json.loads((snapshots / "antigravity-cli.json").read_text()), {"model": "fixture"})
        self.assertEqual(json.loads((snapshots / "codex.json").read_text()), {"model": "fixture", "model_reasoning_effort": "low", "features": {"hooks": True}})

    def test_restore_preserves_private_json_and_existing_codex_toml(self):
        self.put(self.root, "tool-settings/cursor-cli.json", {"editor": {"vimMode": True}})
        path = self.put(self.home, ".config/cursor/cli-config.json", {"authInfo": {"token": "local-only"}, "editor": {"vimMode": False}})
        codex = self.put(self.home, ".codex/config.toml", 'model = "local"\n[projects."/private"]\ntrust_level = "trusted"\n')
        original = codex.read_bytes()
        tools.apply(self.root, self.home, self.backups)
        self.assertEqual(json.loads(path.read_text()), {"authInfo": {"token": "local-only"}, "editor": {"vimMode": True}})
        self.assertEqual(codex.read_bytes(), original)
        self.assertEqual(json.loads((self.backups / ".config/cursor/cli-config.json").read_text())["editor"], {"vimMode": False})
        self.assertEqual(path.stat().st_mode & 0o077, 0)

    def test_fresh_codex_restore_contains_preferences_but_no_trust(self):
        self.put(self.root, "tool-settings/codex.json", {"model": "fixture", "model_reasoning_effort": "low", "features": {"hooks": True}})
        tools.apply(self.root, self.home, self.backups)
        data = tomllib.loads((self.home / ".codex/config.toml").read_text())
        self.assertEqual(data, {"model": "fixture", "model_reasoning_effort": "low", "features": {"hooks": True}})

    def test_credential_shaped_or_nested_private_preferences_are_rejected(self):
        for value in ({"auth": "private"}, {"model": {"access_token": "private"}}, {"model": "gho_" + "X" * 36}):
            with self.assertRaises(ValueError):
                tools.check_preferences(value)
        self.put(self.root, "tool-settings/cursor-cli.json", {"unexpectedState": True})
        with self.assertRaises(ValueError):
            tools.apply(self.root, self.home, self.backups)
        self.assertFalse((self.home / ".config/cursor/cli-config.json").exists())

    def test_link_only_changes_manifest_files_and_keeps_private_siblings(self):
        self.put(self.root, "tool-settings/manifest.json", {"files": [".claude/settings.json"]})
        source = self.put(self.root, ".claude/settings.json", {"model": "fixture"})
        self.put(self.home, ".claude/settings.json", {"model": "previous"})
        private = self.put(self.home, ".claude/.credentials.json", "local-only")
        tools.link(self.root, self.home, self.backups)
        path = self.home / ".claude/settings.json"
        self.assertTrue(path.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(path)), "Stow must recognize the relative link")
        self.assertEqual(path.resolve(), source)
        self.assertEqual(json.loads((self.backups / ".claude/settings.json").read_text()), {"model": "previous"})
        self.assertEqual(private.read_text(), "local-only")
        tools.link(self.root, self.home, self.backups)
        self.assertEqual(json.loads((self.backups / ".claude/settings.json").read_text()), {"model": "previous"})

    def test_existing_absolute_link_is_normalized_for_stow(self):
        self.put(self.root, "tool-settings/manifest.json", {"files": [".claude/settings.json"]})
        source = self.put(self.root, ".claude/settings.json", {"model": "fixture"})
        path = self.home / ".claude/settings.json"
        path.parent.mkdir(parents=True)
        path.symlink_to(source)
        self.assertEqual(tools.link_status(source, path), "absolute")
        tools.link(self.root, self.home, self.backups)
        self.assertFalse(os.path.isabs(os.readlink(path)))
        self.assertEqual(path.resolve(), source)
        self.assertEqual(tools.link_status(source, path), "linked")
        if shutil.which("stow"):
            shutil.copy2(ROOT / ".stow-local-ignore", self.root / ".stow-local-ignore")
            result = subprocess.run(["stow", "--simulate", "--verbose", "--no-folding", "--dir", str(self.root), "--target", str(self.home), "."],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("LINK:", result.stdout + result.stderr)

    def test_existing_folded_directory_never_becomes_a_self_referencing_source_link(self):
        self.put(self.root, "tool-settings/manifest.json", {"files": [".claude/settings.json"]})
        source = self.put(self.root, ".claude/settings.json", {"model": "fixture"})
        folder = self.home / ".claude"
        folder.symlink_to(os.path.relpath(source.parent, self.home))
        original = source.read_bytes()
        tools.link(self.root, self.home, self.backups)
        self.assertFalse(source.is_symlink())
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual((folder / "settings.json").resolve(), source)
        self.assertEqual(tools.link_status(source, folder / "settings.json"), "linked")


if __name__ == "__main__":
    unittest.main()
