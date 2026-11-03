#!/usr/bin/env python3
"""Native surface/input-region smoke test; no pointer injection or hardware writes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from verify_quickshell import CONFIG, run, wait_for
from verify_quickshell_settings import owner


def verify():
    previous_owner=owner()
    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp)
        (root / "walls").mkdir()
        env=dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="preview", QUICKSHELL_STARTUP_UPDATES="0",
                 QUICKSHELL_CONNECTIVITY_FIXTURE=str(Path(__file__).parent / "fixtures/connectivity.json"),
                 XDG_STATE_HOME=str(root / "state"), WALL_DIR=str(root / "walls"), SETTER="/does-not-exist", QT_IM_MODULE="compose")
        log_path=root / "log"
        with log_path.open("w") as log:
            process=subprocess.Popen(["bash",str(CONFIG / "compare.sh"),"current","--no-color"],env=env,stdout=log,stderr=subprocess.STDOUT)
            try:
                def ipc(target,method,*args): return run("qs","ipc","--pid",str(process.pid),"call",target,method,*map(str,args))
                def state(target): return json.loads(ipc(target,"status"))
                def motion(): return json.loads(ipc("shell","motion"))
                def controls_layer():
                    layers=json.loads(run("hyprctl","layers","-j"))
                    return [item for monitor in layers.values() for level in monitor["levels"].values() for item in level
                            if item.get("pid")==process.pid and item.get("namespace")=="quickshell-dev-controls"]
                def bar_layer():
                    layers=json.loads(run("hyprctl","layers","-j"))
                    return [item for monitor in layers.values() for level in monitor["levels"].values() for item in level
                            if item.get("pid")==process.pid and item.get("namespace") in {"quickshell-bar", "quickshell-compare-enzo", "quickshell-compare-mm2103"}]
                def check_controls(page,address=None):
                    wait_for(lambda: state("controls"),lambda value:value["opened"] and value["page"]==page)
                    surface=wait_for(lambda:next(item for item in motion()["surfaces"] if item["route"]=="controls"),
                                     lambda item:item["inputRegion"]["width"]>0 and item["inputRegion"]["height"]>0)
                    region=wait_for(lambda:next(item for item in motion()["surfaces"] if item["route"]=="controls")["inputRegion"],
                                    lambda region:len([rect for rect in region["exclusions"] if rect["width"]>0 and rect["height"]>0])>=3)
                    assert region["y"]==0,region
                    def aligned(pair):
                        region, frames=pair
                        if len(frames)!=1: return False
                        frame=frames[0]
                        rects=[rect for rect in region["exclusions"] if rect["width"] and rect["height"]]
                        return len(rects)>=3 and all(frame["x"]-1<=rect["x"] and rect["x"]+rect["width"]<=frame["x"]+frame["w"]+1
                            and frame["y"]-1<=rect["y"] and rect["y"]+rect["height"]<=frame["y"]+frame["h"]+1 for rect in rects)
                    region,frames=wait_for(lambda:(next(item for item in motion()["surfaces"] if item["route"]=="controls")["inputRegion"],bar_layer()),aligned)
                    assert not any(rect["x"]<=1<rect["x"]+rect["width"] and rect["y"]<=1<rect["y"]+rect["height"] for rect in region["exclusions"]),region
                    layers=wait_for(controls_layer,lambda values:len(values)==1)
                    if address is not None: assert layers[0]["address"]==address,layers
                    return layers[0]["address"]
                wait_for(lambda:state("shell"),lambda value:value["notifications"]=="preview")
                for profile in ("current","enzo","mm2103"):
                    ipc("profile","set",profile)
                    wait_for(lambda:json.loads(ipc("bar","geometry")),bool)
                    ipc("controls","open")
                    address=check_controls("main")
                    for target,page in (("audio","audio"),("nm-applet","wifi"),("blueman","bluetooth")):
                        if target=="audio": assert ipc("audio","open")=="true"
                        else: assert ipc("connectivity","click",target,"left")=="true"
                        check_controls(page,address)
                        assert ipc("profile","activate","controls")=="true"
                        check_controls("main",address)
                    ipc("audio","open")
                    check_controls("audio",address)
                    ipc("connectivity","click","nm-applet","right")
                    check_controls("wifi",address)
                    ipc("connectivity","click","blueman","right")
                    check_controls("bluetooth",address)
                    for target in ("notifications","launcher","wallpaper","settings","controls"):
                        assert ipc("profile","activate",target)=="true"
                        assert state("shell")["active"]==target,state("shell")
                    check_controls("main")
                    ipc("profile","activate","controls")
                    assert state("shell")["active"]==""
                    surface=next(item for item in motion()["surfaces"] if item["route"]=="controls")
                    assert surface["inputRegion"]["height"]==0 and surface["inputRegion"]["width"]==0,surface
                    assert owner()==previous_owner
                print("PASS three bars: Sound/Wi-Fi/Bluetooth/gear reuse the native controls surface; cross-panel icons route directly")
                print("PASS only panel button hitboxes pass through; bar background/edges remain dismissible, input releases on close, notification ownership unchanged")
            except Exception:
                print(log_path.read_text())
                raise
            finally:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        problems=[line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems,"\n".join(problems)
    assert owner()==previous_owner


if __name__=="__main__": verify()
