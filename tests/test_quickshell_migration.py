"""Migration helpers: read-only indexes, checked handoff/rollback and safe markup."""
import importlib.util
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


class SessionTransactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.session = module("desktop_session", CONFIG / "scripts/desktop-session.py")
        self.session.STATE = Path(self.tmp.name) / "state"
        self.session.RUNTIME = Path(self.tmp.name) / "runtime"
        binaries = patch.object(self.session.shutil, "which", side_effect=lambda name: "/fixture/" + name)
        binaries.start()
        self.addCleanup(binaries.stop)
        self.old_notification = {"pid": 123, "start": "1"}
        self.old_bar = {"pid": 124, "start": "2"}

    def processes(self, name):
        return [self.old_notification] if name == "swaync" else [self.old_bar]

    def test_activate_keeps_old_bar_until_healthy(self):
        order = []
        with patch.object(self.session, "legacy_pids", side_effect=self.processes), \
             patch.object(self.session, "notification_owner", return_value=123), \
             patch.object(self.session, "healthy", return_value=False), \
             patch.object(self.session, "terminate", side_effect=lambda rows: order.append(rows)), \
             patch.object(self.session, "start_shell", side_effect=lambda: order.append("ready")):
            self.session.activate()
        self.assertEqual(order, [[self.old_notification], "ready", [self.old_bar]])
        self.assertEqual(self.session.mode(), "quickshell")

    def test_failed_handoff_restores_legacy_without_killing_bar(self):
        order = []
        with patch.object(self.session, "legacy_pids", side_effect=self.processes), \
             patch.object(self.session, "notification_owner", return_value=123), \
             patch.object(self.session, "healthy", return_value=False), \
             patch.object(self.session, "terminate", side_effect=lambda rows: order.append(rows)), \
             patch.object(self.session, "start_shell", side_effect=RuntimeError("fixture failure")), \
             patch.object(self.session, "stop_shell", side_effect=lambda: order.append("stop-own")), \
             patch.object(self.session, "start_legacy", side_effect=lambda: order.append("restore")):
            with self.assertRaisesRegex(RuntimeError, "fixture failure"):
                self.session.activate()
        self.assertEqual(order, [[self.old_notification], "stop-own", "restore"])
        self.assertEqual(self.session.mode(), "legacy")

    def test_unknown_notification_owner_is_never_evicted(self):
        with patch.object(self.session, "legacy_pids", return_value=[]), \
             patch.object(self.session, "notification_owner", return_value=999), \
             patch.object(self.session, "healthy", return_value=False), \
             patch.object(self.session, "terminate") as terminate:
            with self.assertRaisesRegex(RuntimeError, "unrelated"):
                self.session.activate()
            terminate.assert_not_called()

    def test_missing_dependencies_fail_before_stopping_anything(self):
        with patch.object(self.session.shutil, "which", return_value=None), patch.object(self.session, "terminate") as terminate:
            with self.assertRaisesRegex(RuntimeError, "Missing"):
                self.session.activate()
            terminate.assert_not_called()

    def test_pid_identity_and_bus_scope(self):
        own = self.session.identity(os.getpid())
        self.assertTrue(self.session.alive(own))
        self.assertFalse(self.session.alive(dict(own, start="not-the-same-process")))
        self.assertEqual(self.session.bus_path("unix:path=/run/user/1000/bus,guid=abc"), "/run/user/1000/bus")

    def test_production_palette_hook_cannot_revive_legacy(self):
        with patch.object(self.session, "legacy_pids") as pids, patch.object(self.session, "run") as run:
            self.session.palette()
            pids.assert_not_called()
            run.assert_not_called()


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
