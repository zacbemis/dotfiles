#!/usr/bin/env python3
"""Preview-only shared tab/frame integration. Stops only its own shell instance."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from verify_quickshell import CONFIG, run, wait_for, wait_for_fonts
from verify_quickshell_settings import owner


def verify(screenshots):
    original_owner = owner()
    keys = ["apps", "run", "files", "wallpaper", "settings"]
    labels = {"Apps", "Run", "Files", "Wallpapers", "Settings"}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        walls = root / "walls"
        walls.mkdir()
        env = dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_STARTUP_UPDATES="0",
                   WALL_DIR=str(walls), SETTER="/does-not-exist", XDG_STATE_HOME=str(root / "state"),
                   QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))
                def state(target):
                    return json.loads(ipc(target, "status"))
                def motion():
                    return json.loads(ipc("shell", "motion"))
                def opened():
                    return [surface for surface in motion()["surfaces"] if surface["opened"]]
                def host_layers():
                    layers = json.loads(run("hyprctl", "layers", "-j"))
                    return [layer for monitor in layers.values() for level in monitor["levels"].values()
                            for layer in level if layer.get("pid") == process.pid
                            and layer.get("namespace") in {"quickshell-dev-panel", "quickshell-dev-launcher",
                                                           "quickshell-dev-wallpaper", "quickshell-dev-settings"}]
                def current_frame():
                    values = wait_for(opened, lambda values: len(values) == 1 and values[0]["panel"]["width"] > 0 and values[0]["scale"] == 1)
                    assert values[0]["navigation"] and values[0]["focusable"], values
                    return values[0]["panel"]
                def fonts():
                    key = state("navigation")["current"]
                    return state("settings" if key == "settings" else "wallpaper" if key == "wallpaper" else "launcher")["fonts"]
                def check(key, reference, continuous=True):
                    nonlocal host_address
                    assert state("navigation")["current"] == key
                    if not continuous:
                        # Feature IPC intentionally closes the UI before replacing
                        # a renderer; reopening is allowed its normal entrance fade.
                        wait_for(lambda: motion()["navigationHost"], lambda host: host["opacity"] == 1)
                        host_address = wait_for(host_layers, lambda layers: len(layers) == 1)[0]["address"]
                    host = motion()["navigationHost"]
                    assert host["opened"] and host["visible"] and host["opacity"] == host["backdropOpacity"] == 1, host
                    # No new scrim/blur layer may map or fade at a route boundary.
                    layers = host_layers()
                    assert len(layers) == 1 and layers[0]["namespace"] == "quickshell-dev-panel", layers
                    assert layers[0]["address"] == host_address, (layers, host_address)
                    assert current_frame() == reference, (key, current_frame(), reference)
                    assert labels <= {record["text"] for record in wait_for_fonts(fonts)}
                    if key in ("apps", "run", "files"):
                        assert state("launcher")["mode"] == key
                    assert owner() == original_owner

                wait_for(lambda: state("shell"), lambda value: value["notifications"] == "preview")
                assert [item["key"] for item in state("navigation")["items"]] == keys
                assert ipc("navigation", "next") == "false"  # Closed panels must not be opened accidentally.
                assert ipc("navigation", "select", "apps") == "true"
                # A quick tab press must finish, not replay, the initial pop-in.
                assert ipc("navigation", "next") == "true"
                assert opened()[0]["scale"] == 1
                assert ipc("navigation", "previous") == "true"
                reference = current_frame()
                wait_for(lambda: motion()["navigationHost"], lambda host: host["opacity"] == 1)
                layers = wait_for(host_layers, lambda layers: len(layers) == 1)
                host_address = layers[0]["address"]
                assert reference["width"] == 720 and reference["height"] == 420, reference
                screen = state("shell")["screen"]
                for key in keys[1:] + ["apps"]:
                    assert ipc("navigation", "next") == "true"
                    check(key, reference)
                    assert state("shell")["screen"] == screen
                    if screenshots:
                        time.sleep(0.3)
                        run("grim", str(screenshots / (key + ".png")))
                for key in list(reversed(keys[1:])) + ["apps"]:
                    assert ipc("navigation", "previous") == "true"
                    check(key, reference)
                for rejected in ("notifications", "controls", "bad"):
                    assert ipc("navigation", "select", rejected) == "false"
                    check("apps", reference)
                for view in ("current", "mm2103", "grid"):
                    assert ipc("features", "set", "launcher", view) == "true"
                    ipc("navigation", "select", "apps")
                    check("apps", reference, continuous=False)
                    for query in ("no-such-app-82f9a4", "= 2 + 2", "? test", "> echo harmless"):
                        ipc("launcher", "search", query)
                        assert current_frame() == reference
                        assert labels <= {record["text"] for record in wait_for_fonts(fonts)}
                for view in ("current", "gallery", "carousel"):
                    assert ipc("features", "set", "wallpaper", view) == "true"
                    ipc("navigation", "select", "wallpaper")
                    check("wallpaper", reference, continuous=False)
                    ipc("navigation", "next")
                    check("settings", reference)
                    ipc("navigation", "previous")
                    check("wallpaper", reference)
                ipc("shell", "close")
                assert ipc("navigation", "previous") == "false"
                assert not opened()
                print("PASS five tabs in every renderer, wrap both ways, mode routing, fixed geometry across queries/views, monitor pinning and exclusive focus")
                print("PASS one unchanged native surface across tabs; backdrop opacity remains 1 with no duplicate scrim/blur layers")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
    assert owner() == original_owner
    print("PASS clean navigation runtime and unchanged live notification ownership")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, help="captures your open desktop/apps")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    verify(args.screenshots)


if __name__ == "__main__":
    main()
