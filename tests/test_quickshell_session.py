"""Desktop helpers: read-only indexes, checked startup and safe markup."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".config/quickshell"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class LauncherIndexes(unittest.TestCase):
    def test_commands_and_directory_queries_are_inert_and_json_safe(self):
        index = module("launcher_index", CONFIG / "scripts/launcher-index.py")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            executable = root / "a-command"
            executable.write_text("DO NOT EXECUTE")
            executable.chmod(0o755)
            (root / "not-executable").touch()
            (root / "Café folder").mkdir()
            (root / "雪 #file\nname.txt").write_text("fixture")
            with patch.dict(os.environ, PATH=str(root)):
                self.assertEqual(index.commands(), ["a-command"])
            rows = index.files(str(root) + "/")["rows"]
            self.assertEqual(rows[0]["name"], "..")
            self.assertEqual(rows[1]["name"], "Café folder")
            self.assertIn(str(root / "雪 #file\nname.txt"), [row["value"] for row in rows])
            self.assertEqual(index.files(str(root / "cafe"))["rows"][1]["name"], "Café folder")
            self.assertTrue(index.files(str(root / "missing" / "" ) + "/")["error"])


class DesktopSession(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.session = module("desktop_session", CONFIG / "scripts/desktop-session.py")
        self.session.STATE = Path(self.tmp.name) / "state"
        self.session.RUNTIME = Path(self.tmp.name) / "runtime"
        binaries = patch.object(self.session.shutil, "which", side_effect=lambda name: "/fixture/" + name)
        binaries.start()
        self.addCleanup(binaries.stop)

    def test_start_is_idempotent_when_healthy(self):
        with patch.object(self.session, "healthy", return_value=True), \
             patch.object(self.session, "spawn") as spawn, \
             patch.object(self.session, "terminate") as terminate:
            self.session.activate()
            self.session.activate()
            spawn.assert_not_called()
            terminate.assert_not_called()

    def test_start_spawns_only_the_daily_supervisor(self):
        with patch.object(self.session, "healthy", side_effect=[False, True]), \
             patch.object(self.session, "notification_owner", return_value=None), \
             patch.object(self.session, "session", return_value={}), \
             patch.object(self.session, "spawn") as spawn:
            self.session.activate()
            spawn.assert_called_once_with(
                [self.session.sys.executable, str(CONFIG / "scripts/desktop-session.py"), "serve"], "desktop")

    def test_unknown_notification_owner_is_never_evicted(self):
        with patch.object(self.session, "notification_owner", return_value=999), \
             patch.object(self.session, "healthy", return_value=False), \
             patch.object(self.session, "terminate") as terminate, \
             patch.object(self.session, "spawn") as spawn:
            with self.assertRaisesRegex(RuntimeError, "owned by PID 999"):
                self.session.activate()
            terminate.assert_not_called()
            spawn.assert_not_called()

    def test_missing_dependencies_fail_before_stopping_anything(self):
        with patch.object(self.session.shutil, "which", return_value=None), \
             patch.object(self.session, "stop_shell") as stop, \
             patch.object(self.session.sys, "argv", ["desktop.sh", "restart"]):
            with self.assertRaisesRegex(RuntimeError, "Missing"):
                self.session.main()
            stop.assert_not_called()

    def test_failed_start_does_not_launch_an_alternative_ui(self):
        with patch.object(self.session, "healthy", return_value=False), \
             patch.object(self.session, "notification_owner", return_value=None), \
             patch.object(self.session, "spawn") as spawn, \
             patch.object(self.session.time, "monotonic", side_effect=[0, 16]):
            with self.assertRaisesRegex(RuntimeError, "health check"):
                self.session.activate()
            self.assertEqual(spawn.call_count, 1)
            self.assertEqual(spawn.call_args.args[1], "desktop")

    # Compatibility guards only: retired state/commands must never revive a UI.
    def test_retired_mode_file_cannot_redirect_start_or_panel_actions(self):
        self.session.atomic(self.session.STATE / "mode", "legacy\n")
        for action in ("start", "activate", "launcher", "run", "files", "wallpaper", "notifications", "controls", "settings"):
            with self.subTest(action=action), \
                 patch.object(self.session.sys, "argv", ["desktop.sh", action]), \
                 patch.object(self.session, "start_shell") as start, \
                 patch.object(self.session, "ipc", return_value="true") as ipc, \
                 patch("sys.stdout", new_callable=io.StringIO):
                self.session.main()
                start.assert_called_once()
                if action in {"start", "activate"}:
                    ipc.assert_not_called()
                elif action in {"run", "files"}:
                    ipc.assert_called_once_with("launcher", "mode", action)
                else:
                    ipc.assert_called_once_with(action, "toggle")

    def test_status_always_reports_quickshell(self):
        self.session.atomic(self.session.STATE / "mode", "legacy\n")
        with patch.object(self.session.sys, "argv", ["desktop.sh", "status"]), \
             patch.object(self.session, "healthy", return_value=True), \
             patch.object(self.session, "notification_owner", return_value=123), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            self.session.main()
        self.assertEqual(json.loads(output.getvalue())["mode"], "quickshell")

    def test_removed_actions_fail_without_starting_or_stopping_anything(self):
        for action in ("legacy", "palette"):
            with patch.object(self.session.sys, "argv", ["desktop.sh", action]), \
                 patch.object(self.session, "spawn") as spawn, \
                 patch.object(self.session, "stop_shell") as stop:
                with self.assertRaisesRegex(RuntimeError, "usage"):
                    self.session.main()
                spawn.assert_not_called()
                stop.assert_not_called()

    def test_restart_stops_own_shell_before_starting_and_skips_login_check(self):
        calls = []
        with patch.object(self.session.sys, "argv", ["desktop.sh", "restart"]), \
             patch.object(self.session, "stop_shell", side_effect=lambda: calls.append("stop")), \
             patch.object(self.session, "start_shell", side_effect=lambda: calls.append("start")):
            self.session.main()
        self.assertEqual(calls, ["stop", "start"])
        self.assertEqual(self.session.ENV["QUICKSHELL_STARTUP_UPDATES"], "0")

    def test_stop_only_targets_the_recorded_supervisor_and_shell(self):
        supervisor = {"pid": 123, "start": "1"}
        shell = {"pid": 124, "start": "2"}
        with patch.object(self.session, "session", return_value={"supervisor": supervisor, "shell": shell}), \
             patch.object(self.session, "alive", return_value=True), \
             patch.object(self.session, "terminate") as terminate:
            self.session.stop_shell()
        self.assertEqual([call.args[0] for call in terminate.call_args_list], [[supervisor], [shell]])

    def test_health_requires_server_mode_and_ownership_by_recorded_shell(self):
        data = {"supervisor": {"pid": 123, "start": "1"}, "shell": {"pid": 124, "start": "2"}}
        for notifications, owner, expected in (("server", 124, True), ("preview", 124, False), ("server", 999, False)):
            with self.subTest(notifications=notifications, owner=owner), \
                 patch.object(self.session, "session", return_value=data), \
                 patch.object(self.session, "alive", return_value=True), \
                 patch.object(self.session, "ipc", return_value=json.dumps({"notifications": notifications})), \
                 patch.object(self.session, "notification_owner", return_value=owner):
                self.assertEqual(self.session.healthy(), expected)

    def test_pid_identity_and_config_scope(self):
        own = self.session.identity(os.getpid())
        self.assertTrue(self.session.alive(own))
        self.assertFalse(self.session.alive(dict(own, start="not-the-same-process")))
        self.session.atomic(self.session.RUNTIME / "session.json", json.dumps({"config": "/other/config", "shell": own}))
        self.assertEqual(self.session.session(), {})


@unittest.skipUnless(shutil.which("node"), "Node.js is not installed")
class NotificationMarkup(unittest.TestCase):
    def test_basic_markup_without_resource_loading_or_unsafe_links(self):
        script = r'''
const vm = require('node:vm'), fs = require('node:fs'), assert = require('node:assert/strict');
const c = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1],'utf8').replace('.pragma library',''),c);
assert.equal(c.format('<b>title</b>\n<i>detail</i>'), '<b>title</b><br/><i>detail</i>');
assert.ok(c.format('<img src="file:///private">').includes('&lt;img'));
assert.ok(!c.format('<img src="https://tracking.invalid/">').includes('<img'));
assert.ok(!c.format('<a href="javascript:alert(1)">bad</a>').includes('href'));
assert.ok(c.format('<a href="https://example.org/?a=1&amp;b=2">open</a>').includes('href="https://example.org/?a=1&amp;b=2"'));
for (const link of ['file:///etc/passwd','javascript:foo','data:text/html,foo','https://example.org/\nunsafe']) assert.equal(c.safeLink(link),false);
for (const link of ['https://example.org/','http://example.org/','mailto:a@example.org']) assert.equal(c.safeLink(link),true);
'''
        result = subprocess.run(["node", "-e", script, str(CONFIG / "services/NotificationText.js")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
