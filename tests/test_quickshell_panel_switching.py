"""One-click routing, precise button cutouts and bar-background dismissal."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

CONFIG = Path(__file__).resolve().parents[1] / ".config/quickshell"


class PanelInputPolicy(unittest.TestCase):
    def test_backdrops_only_exclude_panel_button_hitboxes(self):
        for name in ("components/OverlayWindow.qml", "components/NavigationWindow.qml", "modules/bar/TrayMenu.qml"):
            self.assertIn("mask: PanelInputRegion", (CONFIG / name).read_text(), name)
        for name in ("modules/bar/Bar.qml", "modules/comparison/ComparisonBar.qml"):
            text = (CONFIG / name).read_text()
            self.assertIn("UiState.bars = [...UiState.bars,", text)
            self.assertIn("UiState.bars.filter", text)
        mask = (CONFIG / "components/PanelInputRegion.qml").read_text()
        self.assertNotIn("barInputHeight", mask)
        self.assertIn("intersection: Intersection.Subtract", mask)
        self.assertIn("UiState.panelTargets", mask)
        profile = (CONFIG / "services/ShellProfile.qml").read_text()
        self.assertIn('if (feature === "controls") { ConnectivityService.toggleOverview(); return true; }', profile)


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class PanelSwitching(unittest.TestCase):
    def test_other_icons_switch_directly_and_same_target_toggles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ("services", "scripts", "components"):
                (root / directory).mkdir()
            for name in ("ShellProfile.qml", "Preferences.qml", "StyleCatalog.js", "UiState.qml", "LayoutMetrics.qml", "ConnectivityService.qml", "AudioService.qml"):
                shutil.copy2(CONFIG / "services" / name, root / "services" / name)
            shutil.copy2(CONFIG / "scripts/connectivity.py", root / "scripts/connectivity.py")
            shutil.copy2(CONFIG / "components/PanelInputRegion.qml", root / "components/PanelInputRegion.qml")
            (root / "services/NotificationService.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { readonly property string mode: "preview"; function toggleDnd() {} }')
            (root / "services/SystemState.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { property var audioSink: null; function ignoredSink(node) { return false; } }')
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
Scope {
    id: scope
    property var history: []
    property int regionChanges: 0
    FloatingWindow {
        id: bar
        visible: true
        implicitWidth: 800; implicitHeight: 42
        function panelTargets() { return [button, secondary]; }
        Item { id: buttonRow; x:100; y:8; Rectangle { id:button; width:40; height:24 } }
        Rectangle { id:secondary; x:500; y:8; width:30; height:24 }
    }
    FloatingWindow { id: overlay; visible:true; implicitWidth:800; implicitHeight:600; mask:region }
    Component.onCompleted: UiState.bars=[bar]
    Connections {
        target: UiState
        function onActiveChanged() {
            scope.history=[...scope.history,UiState.active];
            // Match the production QuickSettings close lifecycle.
            if (UiState.active !== "controls") ConnectivityService.closePanel();
        }
    }
    PanelInputRegion { id: region; output: bar.screen; targetWindow:overlay; windowWidth:800; windowHeight:600; active:UiState.active !== "" }
    Connections { target:region; function onChanged() { scope.regionChanges++; } }
    IpcHandler {
        target: "fixture"
        function state(): string { return JSON.stringify({active:UiState.active, page:ConnectivityService.page, history:scope.history,
            screen:UiState.screenName, region:{y:region.y,width:region.width,height:region.height},
            exclusions:region.exclusions(), regionChanges:scope.regionChanges, emptyBar:region.captures(1,1), otherWidget:region.captures(350,16)}); }
        function press(name: string): bool {
            if (name === "sound") return AudioService.open();
            if (name === "wifi" || name === "bluetooth") return ConnectivityService.openTray(name === "wifi" ? "nm-applet" : "blueman",Qt.LeftButton);
            return ShellProfile.activate(name);
        }
        function clear(): void { scope.history=[]; }
        function move(): void { buttonRow.x=200; }
        function moveSecondary(): void { secondary.x=550; }
        function compositorFrames(invalid: bool): bool {
            const layers={};
            layers[bar.screen.name]={levels:{"2":[
                {pid:Quickshell.processId, namespace:"quickshell-bar", x:1100,y:540,w:invalid ? -1 : 800,h:42},
                {pid:Quickshell.processId+1, namespace:"quickshell-compare-enzo", x:0,y:0,w:800,h:42}]}};
            return LayoutMetrics.accept(JSON.stringify({outer:{int:8},inner:{int:4},
                monitors:[{name:bar.screen.name,reserved:[0,0,0,0],x:1000,y:500}],layers:layers}));
        }
        function buttonVisible(value: bool): void { button.visible=value; }
        function captures(x: real, y: real): bool { return region.captures(x,y); }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_IM_MODULE="compose", HYPRLAND_INSTANCE_SIGNATURE="", QUICKSHELL_COMPARE="1",
                       QUICKSHELL_CONNECTIVITY_FIXTURE=str(Path(__file__).parent / "fixtures/connectivity.json"), XDG_STATE_HOME=str(root / "state"))
            env.pop("WAYLAND_DISPLAY", None)
            log_path=root / "log"
            with log_path.open("w") as log:
                process=subprocess.Popen(["qs","-p",str(root / "shell.qml"),"--no-color"],env=env,stdout=log,stderr=subprocess.STDOUT)
                try:
                    def ipc(method,*args):
                        result=subprocess.run(["qs","ipc","--pid",str(process.pid),"call","fixture",method,*map(str,args)],text=True,capture_output=True,timeout=5)
                        if result.returncode: raise AssertionError(result.stderr+log_path.read_text())
                        return result.stdout.strip()
                    def state(): return json.loads(ipc("state"))
                    deadline=time.monotonic()+8
                    while True:
                        try:
                            initial=state(); break
                        except (AssertionError,ValueError):
                            if process.poll() is not None or time.monotonic()>deadline: raise
                            time.sleep(.03)
                    self.assertEqual(initial["region"],{"y":0,"width":0,"height":0})
                    def press(name, active, page="main"):
                        self.assertEqual(ipc("press",name),"true")
                        data=state()
                        self.assertEqual((data["active"],data["page"]),(active,page),data)
                        return data
                    press("controls","controls")
                    self.assertEqual(state()["region"],{"y":0,"width":800,"height":600})
                    data=state()
                    self.assertTrue(data["emptyBar"] and data["otherWidget"], "The bar background/non-panel widgets must dismiss, not pass through")
                    self.assertEqual(len(data["exclusions"]),2)
                    first=next(rect for rect in data["exclusions"] if rect["width"]==40)
                    self.assertEqual((first["width"],first["height"]),(40,24))
                    self.assertEqual(ipc("captures",first["x"]+20,first["y"]+12),"false")
                    ipc("move")  # Ancestor movement must update the cutout.
                    moved=next(rect for rect in state()["exclusions"] if rect["width"]==40)
                    self.assertEqual(moved["x"]-first["x"],100)
                    self.assertEqual(ipc("captures",first["x"]+20,first["y"]+12),"true")
                    self.assertEqual(ipc("captures",moved["x"]+20,moved["y"]+12),"false")
                    ipc("buttonVisible","false")
                    self.assertEqual(len(state()["exclusions"]),1)
                    self.assertEqual(ipc("captures",moved["x"]+20,moved["y"]+12),"true")
                    changes=state()["regionChanges"]
                    ipc("moveSecondary")
                    self.assertGreater(state()["regionChanges"],changes, "Remaining cutouts must keep native mask change subscriptions")
                    ipc("buttonVisible","true")
                    self.assertEqual(len(state()["exclusions"]),2)
                    self.assertEqual(ipc("compositorFrames","false"),"true")
                    mapped=next(rect for rect in state()["exclusions"] if rect["width"]==40)
                    self.assertEqual((mapped["x"],mapped["y"]),(300,48), "Compositor frame/output origins must correct Qt's layer-shell coordinates")
                    self.assertEqual(ipc("compositorFrames","true"),"false")
                    self.assertEqual(next(rect for rect in state()["exclusions"] if rect["width"]==40),mapped)
                    self.assertTrue(state()["emptyBar"])
                    ipc("clear")
                    # Different icons in the same native controls host never close it.
                    press("sound","controls","audio")
                    press("wifi","controls","wifi")
                    press("bluetooth","controls","bluetooth")
                    press("controls","controls")
                    press("sound","controls","audio")
                    press("controls","controls")
                    self.assertEqual(state()["history"],[], "No transient close/reopen during detail/overview switches")
                    # Distinct top-level panels also switch in a single action.
                    for name in ("notifications","settings","launcher","wallpaper","controls"):
                        press(name,name)
                    self.assertNotIn("",state()["history"])
                    self.assertEqual(state()["screen"],initial["screen"])
                    self.assertTrue(state()["emptyBar"])
                    self.assertEqual(state()["region"],{"y":0,"width":800,"height":600})
                    press("controls","")
                    self.assertEqual(state()["region"]["height"],0)
                    press("sound","controls","audio")
                    press("sound","")
                    press("notifications","notifications")
                    press("notifications","")
                except Exception:
                    print(log_path.read_text())
                    raise
                finally:
                    process.terminate()
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
            expected=("$HYPRLAND_INSTANCE_SIGNATURE is unset", "Failed to create wl_display", "Compositor does not support hyprland-toplevel-mapping-v1", "This plugin does not support setting window masks")
            problems=[line for line in log_path.read_text().splitlines() if ("WARN" in line or "ERROR" in line) and not any(value in line for value in expected)]
            self.assertEqual(problems,[],log_path.read_text())
