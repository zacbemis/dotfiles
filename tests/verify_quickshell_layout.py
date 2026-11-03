#!/usr/bin/env python3
"""Read-only compositor-gap integration; only preview-owned UI is opened."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from verify_quickshell import CONFIG, run, wait_for
from verify_quickshell_settings import owner


def verify():
    original_owner = owner()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "walls").mkdir()
        env = dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_STARTUP_UPDATES="0",
                   WALL_DIR=str(root / "walls"), SETTER="/does-not-exist", XDG_STATE_HOME=str(root / "state"),
                   QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1", QT_IM_MODULE="compose")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))
                def state(target):
                    return json.loads(ipc(target, "status"))
                def metrics():
                    return json.loads(ipc("shell", "motion"))["spacing"]
                def css(option):
                    values = json.loads(run("hyprctl", "getoption", option, "-j"))["css"].split()
                    values = [int(value) for value in values]
                    return dict(zip(("top", "right", "bottom", "left"), values))
                wait_for(lambda: state("shell"), lambda value: value["notifications"] == "preview")
                expected_outer, expected_inner = css("general:gaps_out"), css("general:gaps_in")
                wait_for(metrics, lambda value: value["outer"] == expected_outer and value["inner"] == expected_inner)
                assert metrics()["windowGap"] == expected_inner["top"] + expected_inner["bottom"]
                for profile in ("current", "enzo", "mm2103"):
                    assert ipc("profile", "set", profile) == "true"
                    for view in ("compact", "tiles"):
                        assert ipc("features", "set", "controls", view) == "true"
                        ipc("controls", "open")
                        controls = wait_for(lambda: state("controls"), lambda value: value["opened"] and value["frame"]["width"] > 0)
                        screen = state("shell")["screen"]
                        monitor = next(value for value in json.loads(run("hyprctl", "monitors", "-j")) if value["name"] == screen)
                        width, height = monitor["width"], monitor["height"]
                        if monitor.get("transform", 0) % 2: width, height = height, width
                        width, height = width / monitor["scale"], height / monitor["scale"]
                        def current_insets():
                            reserved = next(value["reserved"] for value in json.loads(run("hyprctl", "monitors", "-j")) if value["name"] == screen)
                            return {key: expected_outer[key] + reserved[index] for index, key in enumerate(("left", "top", "right", "bottom"))}
                        controls, expected_insets = wait_for(lambda: (state("controls"), current_insets()), lambda pair: pair[0]["windowInsets"] == pair[1])
                        frame = controls["frame"]
                        assert frame["y"] == expected_insets["top"], controls
                        assert width - frame["x"] - frame["width"] == expected_insets["right"], controls
                        assert frame["y"] + frame["height"] <= height - expected_insets["bottom"], controls
                        ipc("shell", "close")
                    for view in ("current", "compact", "stacked"):
                        assert ipc("features", "set", "notifications", view) == "true"
                        ipc("notifications", "open")
                        wait_for(lambda: state("shell"), lambda value: value["active"] == "notifications")
                        value = state("notifications")
                        if view == "current":
                            frame = value["panel"]
                            assert frame["x"] == expected_insets["left"] and frame["y"] == expected_insets["top"], value
                        else:
                            frame = value["alternative"]["frame"]
                            assert frame["y"] == expected_insets["top"] and width - frame["x"] - frame["width"] == expected_insets["right"], value
                        assert frame["y"] + frame["height"] <= height - expected_insets["bottom"], value
                        assert value["panel"]["popupTop"] == expected_insets["top"]
                        assert value["panel"]["popupRight"] == expected_insets["right"]
                        ipc("shell", "close")
                    for view in ("horizontal", "vertical"):
                        ipc("features", "set", "osd", view)
                        ipc("osd", "preview", "volume", 47)
                        value = state("osd")
                        assert value["margins"] == {"bottom":expected_insets["bottom"], "right":expected_insets["right"]}, value
                    # Only display exported menus; never activate an entry.
                    tray = json.loads(ipc("tray", "items"))
                    target = next((item for item in tray if item["id"] == "nm-applet" and item["hasMenu"]), None)
                    if target:
                        assert ipc("tray", "menu", target["id"]) == "true"
                        menus = wait_for(lambda: state("tray"), lambda values: any(value["open"] and value["entries"] for value in values))
                        for menu in (value for value in menus if value["open"]):
                            frame = menu["frame"]
                            assert frame["y"] == expected_insets["top"], menu
                            assert frame["x"] >= expected_insets["left"] and frame["x"] + frame["width"] <= width - expected_insets["right"], menu
                            assert frame["y"] + frame["height"] <= height - expected_insets["bottom"], menu
                        ipc("tray", "close")
                    ipc("navigation", "select", "settings")
                    host = wait_for(lambda: json.loads(ipc("shell", "motion"))["navigationHost"], lambda value: value["opened"] and value["opacity"] == 1)
                    assert host["panel"]["width"] == 720 and host["panel"]["height"] == 420, host
                    ipc("shell", "close")
                    assert owner() == original_owner
                print("PASS live Hyprland gaps/reserved edges: three bars, two control layouts, three notification centers, tray menus and both OSDs")
                print("PASS centered navigation remains 720×420; no compositor options, hardware or live preferences changed")
            except Exception:
                print(log_path.read_text())
                raise
            finally:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
    assert owner() == original_owner
    print("PASS clean preview runtime and unchanged notification ownership")


if __name__ == "__main__":
    verify()
