"""Offline audio/caffeine controls. No real routing, volume or idle changes."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"
SPEC = importlib.util.spec_from_file_location("caffeine", CONFIG / "scripts/caffeine.py")
CAFFEINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAFFEINE)


class CaffeineLease(unittest.TestCase):
    def test_logind_contract_requests_only_idle_with_bounded_timeout(self):
        gio, glib, reply, descriptors = MagicMock(), MagicMock(), MagicMock(), MagicMock()
        reply.unpack.return_value = (0,)
        descriptors.get.return_value = 42
        bus = gio.bus_get_sync.return_value
        bus.call_with_unix_fd_list_sync.return_value = (reply, descriptors)
        self.assertEqual(CAFFEINE.acquire(gio, glib), 42)
        args = bus.call_with_unix_fd_list_sync.call_args.args
        self.assertEqual(args[:4], ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Inhibit"))
        self.assertEqual(glib.Variant.call_args.args, ("(ssss)", ("idle", "Quickshell", "Caffeine mode", "block")))
        self.assertEqual(args[7], 5000)

    def test_owned_descriptor_closes_on_pipe_eof(self):
        descriptor = os.open("/dev/null", os.O_RDONLY)
        class Input:
            def __iter__(self):
                os.fstat(descriptor)  # Lease remains owned while the pipe is open.
                return iter(())
        output = io.StringIO()
        with contextlib.redirect_stdout(output), patch.object(CAFFEINE.sys, "stdin", Input()):
            self.assertEqual(CAFFEINE.serve(lambda: descriptor), 0)
        self.assertEqual(json.loads(output.getvalue()), {"enabled":True})
        with self.assertRaises(OSError): os.fstat(descriptor)

    def test_acquisition_failure_is_generic_and_never_claims_enabled(self):
        output = io.StringIO()
        def fail(): raise OSError("private diagnostic")
        with contextlib.redirect_stdout(output): self.assertEqual(CAFFEINE.serve(fail), 1)
        result = json.loads(output.getvalue())
        self.assertFalse(result["enabled"])
        self.assertNotIn("private", result["error"])


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class SoundPanel(unittest.TestCase):
    def test_fixture_devices_mutes_levels_application_identity_and_caffeine(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ("components", "theme", "services", "modules/controls", "scripts"):
                (root / folder).mkdir(parents=True)
            for file in (CONFIG / "components").glob("*.qml"):
                shutil.copy2(file, root / "components" / file.name)
            for file in (CONFIG / "theme").iterdir():
                if file.is_file(): shutil.copy2(file, root / "theme" / file.name)
            for name in ("AudioPage.qml", "AudioLevel.qml", "ValueSlider.qml"):
                shutil.copy2(CONFIG / "modules/controls" / name, root / "modules/controls" / name)
            for name in ("AudioService.qml", "CaffeineService.qml"):
                shutil.copy2(CONFIG / "services" / name, root / "services" / name)
            marker = root / "holder-started"
            (root / "scripts/caffeine.py").write_text('import pathlib,sys\npathlib.Path(' + repr(str(marker)) + ').touch()\nprint(\'{"enabled":true}\',flush=True)\nsys.stdin.read()\n')
            (root / "services/ShellProfile.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { property bool comparing: true }')
            (root / "services/SystemState.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { property var audioSink: null; function ignoredSink(node) { return false; } }')
            (root / "services/MotionService.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { readonly property var settings: ({enabled:false}) }')
            (root / "services/UiState.qml").write_text('''pragma Singleton
import Quickshell
Singleton { property string active: "controls"; readonly property real windowGap: 8; function show(name) { active=name; } function close(name) { active=""; } }
''')
            fixture = json.loads((Path(__file__).parent / "fixtures/connectivity.json").read_text())
            (root / "services/ConnectivityService.qml").write_text('''pragma Singleton
import Quickshell
Singleton {
    readonly property string fixture: "offline"
    property bool readOnly: false
    property bool ready: true
    property string page: "audio"
    property string audioReturn: "main"
    property var state: %s
    readonly property var bluetooth: state.bluetooth
    function open(kind) { page=kind; UiState.show("controls"); return true; }
}
''' % json.dumps({"audio":fixture["audio"], "bluetooth":fixture["bluetooth"]}))
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.controls
import qs.services
import qs.theme
Scope {
    id: scope
    property var watched: null
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const result=find(child,name); if (result) return result; }
        return null;
    }
    FloatingWindow {
        id: host; visible:true; implicitWidth:400; implicitHeight:520
        color: Theme.background
        AudioPage { id: page; anchors.fill:parent; anchors.margins:12 }
    }
    IpcHandler {
        target: "fixture"
        function state(): string { return JSON.stringify({audio:AudioService.status(), page:page.presentation(), caffeine:CaffeineService.status(), fonts:Theme.auditText(host.contentItem)}); }
        function action(target: string): bool { return page.activate(target); }
        function caffeine(): bool { return CaffeineService.toggle(); }
        function holder(): void { ShellProfile.comparing=false; }
        function readonly(value: bool): void { ConnectivityService.readOnly=value; }
        function remember(): bool { watched=scope.find(host.contentItem,"audio-application-browser-serial-1"); return watched !== null; }
        function same(): bool { return watched !== null && watched === scope.find(host.contentItem,"audio-application-browser-serial-1"); }
        function stale(): bool { return AudioService.setVolume("application","app-browser","old-serial",99); }
        function capture(path: string): void { page.grabToImage(result => result.saveToFile(path)); }
        function empty(): void { const data=JSON.parse(JSON.stringify(AudioService.fixtureAudio)); data.streams=[]; AudioService.fixtureAudio=data; }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_IM_MODULE="compose", QUICKSHELL_PALETTE=str(root / "missing.css"))
            env.pop("WAYLAND_DISPLAY", None)
            log_path = root / "log"
            with log_path.open("w") as log:
                process = subprocess.Popen(["qs", "-p", str(root / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ipc(method, *args):
                        result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "fixture", method, *map(str,args)], text=True, capture_output=True, timeout=5)
                        if result.returncode: raise AssertionError(result.stderr + log_path.read_text())
                        return result.stdout.strip()
                    def state(): return json.loads(ipc("state"))
                    deadline = time.monotonic()+10
                    while True:
                        try:
                            data=state()
                            if data["audio"]["output"]["available"] and data["fonts"]: break
                        except (AssertionError, ValueError):
                            if process.poll() is not None: raise
                        if time.monotonic()>deadline: self.fail(log_path.read_text())
                        time.sleep(.04)
                    self.assertEqual(data["audio"]["output"]["volume"], 50)
                    self.assertFalse(data["caffeine"]["enabled"])
                    self.assertTrue(data["caffeine"]["simulated"])
                    for _ in range(2): self.assertEqual(ipc("caffeine"), "true")
                    self.assertFalse(state()["caffeine"]["enabled"])
                    self.assertFalse(marker.exists(), "Comparison toggles must never launch an inhibitor")
                    ipc("holder")  # Fake process, no logind/idle calls.
                    self.assertEqual(ipc("caffeine"), "true")
                    deadline=time.monotonic()+5
                    while not state()["caffeine"]["enabled"] and time.monotonic()<deadline: time.sleep(.02)
                    self.assertTrue(state()["caffeine"]["enabled"] and marker.exists())
                    self.assertEqual(ipc("caffeine"), "true")
                    while state()["caffeine"]["pending"] and time.monotonic()<deadline: time.sleep(.02)
                    self.assertFalse(state()["caffeine"]["enabled"] or state()["caffeine"]["error"])
                    for action in ("mute:output", "mute:input", "volume:output:32", "volume:input:61", "applications"):
                        self.assertEqual(ipc("action",action), "true", action)
                    data=state()["audio"]
                    self.assertTrue(data["output"]["muted"] and data["input"]["muted"])
                    self.assertEqual((data["output"]["volume"],data["input"]["volume"]),(32,61))
                    self.assertEqual(ipc("remember"), "true")
                    for value in (10,25,45,73): self.assertEqual(ipc("action",f"volume:application:app-browser:{value}"),"true")
                    self.assertEqual(ipc("same"),"true", "Volume echoes must not recreate the dragged application delegate")
                    self.assertEqual(ipc("action","mute:application:app-browser"),"true")
                    apps=state()["audio"]["applications"]
                    self.assertEqual([(app["volume"],app["muted"]) for app in apps],[(73,True),(45,False)])
                    self.assertEqual(ipc("stale"),"false")
                    for action in ("volume:output:-1", "volume:input:101", "volume:application:gone:40", "volume:application:app-browser:no"):
                        self.assertEqual(ipc("action",action),"false", action)
                    for action in ("output:out-headphones", "input:in-headset", "profile:fixture-card:headset-head-unit"):
                        self.assertEqual(ipc("action",action),"true", action)
                    self.assertEqual(state()["audio"]["output"]["id"],"out-headphones")
                    ipc("readonly","true")
                    before=state()["audio"]
                    for action in ("mute:output", "mute:input", "volume:application:app-browser:50", "output:out-speakers"):
                        self.assertEqual(ipc("action",action),"false", action)
                    self.assertEqual(state()["audio"],before)
                    ipc("readonly","false")
                    # Optional isolated image contains fixture data only.
                    if os.environ.get("QUICKSHELL_SOUND_SCREENSHOT"):
                        ipc("capture",os.environ["QUICKSHELL_SOUND_SCREENSHOT"])
                        time.sleep(.3)
                    ipc("empty")
                    time.sleep(.1)
                    self.assertEqual(state()["audio"]["applications"],[])
                finally:
                    process.terminate()
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
            problems = [line for line in log_path.read_text().splitlines() if ("WARN" in line or "ERROR" in line) and "This plugin does not support setting window masks" not in line]
            self.assertEqual(problems, [], log_path.read_text())
