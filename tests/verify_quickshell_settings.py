#!/usr/bin/env python3
"""Exercise the selector in a preview-only instance; never stop the daily shell.

Optional screenshots include your open desktop/apps. No apps, setters, updates or
hardware controls are activated. The production notification owner is checked.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from verify_quickshell import CONFIG, run, wait_for, wait_for_fonts


def owner():
    result = subprocess.run(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                             "org.freedesktop.DBus", "GetNameOwner", "s", "org.freedesktop.Notifications"],
                            text=True, capture_output=True, timeout=5)
    return result.returncode, result.stdout.strip()


def verify_persistence():
    """Real selector API + restart, but preview notifications and a private file."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "walls").mkdir()
        path = root / "preferences.json"
        env = dict(os.environ, QUICKSHELL_COMPARE="0", QUICKSHELL_NOTIFICATIONS="preview", QUICKSHELL_PERSIST_SETTINGS="1",
                   QUICKSHELL_PREFERENCES=str(path), QUICKSHELL_STARTUP_UPDATES="0", XDG_STATE_HOME=str(root / "state"),
                   WALL_DIR=str(root / "walls"), SETTER="/does-not-exist", QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
        env.pop("QUICKSHELL_PROFILE", None)
        expected = None
        for attempt in range(2):
            log_path = root / (str(attempt) + ".log")
            with log_path.open("w") as log:
                process = subprocess.Popen(["bash", str(CONFIG / "run.sh"), "--preview", "--no-bar", "--no-color"],
                                           env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ipc(target, method, *args):
                        return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *args)
                    def state():
                        return json.loads(ipc("settings", "status"))
                    wait_for(state, lambda value: value["persistent"])
                    assert json.loads(ipc("shell", "status"))["notifications"] == "preview"
                    if attempt == 0:
                        assert ipc("settings", "preset", "mm2103") == "true"
                        expected = state()["current"]
                        saved = path.read_text()  # Save is complete when the IPC call returns.
                        for key, value in state()["presets"][1]["values"].items():
                            assert json.loads(saved)[key] == value
                        assert ipc("settings", "apply", '{"bar":"current","osd":"bad"}') == "false"
                        assert path.read_text() == saved and state()["current"] == expected
                        assert ipc("settings", "apply", '{"launcher":"grid","wallpaperColors":false,"autoHide":true,"pinned":true}') == "true"
                        expected = state()["current"]
                        assert json.loads(path.read_text())["pinned"]
                    else:
                        assert state()["current"] == expected
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            assert not [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line], log_path.read_text()
    print("PASS real selector preset/batched apply, synchronous atomic save and full-shell restart with isolated preferences")


def verify(screenshots):
    original_owner = owner()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        walls = root / "walls"
        walls.mkdir()
        preferences = root / "daily-preferences.json"
        original_preferences = '{"version":1,"bar":"mm2103","launcher":"grid"}'
        preferences.write_text(original_preferences)
        env = dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_PERSIST_SETTINGS="1",
                   QUICKSHELL_PREFERENCES=str(preferences), QUICKSHELL_STARTUP_UPDATES="0", WALL_DIR=str(walls),
                   SETTER="/does-not-exist", XDG_STATE_HOME=str(root / "state"), QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))

                def state(target="settings"):
                    return json.loads(ipc(target, "status"))

                def capture(name):
                    if screenshots:
                        time.sleep(0.5)
                        run("grim", str(screenshots / (name + ".png")))

                wait_for(lambda: state("shell"), lambda value: value["notifications"] == "preview")
                assert state()["current"]["bar"] == "current"  # Never read the seeded daily file.
                assert not state()["persistent"]
                assert ipc("notifications", "preview", "Selector fixture", "History must survive all renderer changes.") == "true"
                ipc("notifications", "dnd_toggle")
                history = state("notifications")
                ipc("settings", "open")
                initial = wait_for(state, lambda value: value["opened"] and value["width"] > 0)
                assert initial["width"] <= 720 and initial["height"] <= 420, initial
                for category, choices in state()["choices"].items():
                    assert ipc("settings", "category", category) == "true"
                    for choice in choices:
                        before = state()["current"]
                        assert ipc("settings", "set", category, choice) == "true"
                        selected = wait_for(state, lambda value: value["opened"] and value["current"][category] == choice)
                        for key in before.keys() - {category, "pinned"}:
                            assert selected["current"][key] == before[key], (key, before, selected)
                        assert sum(option["selected"] for option in selected["options"]) == 1
                        assert all(option["width"] <= selected["viewportWidth"] + 1 for option in selected["options"])
                        wait_for_fonts(lambda: state()["fonts"])
                        notices = state("notifications")
                        assert notices["mode"] == "preview" and notices["count"] == history["count"] and notices["dnd"] == history["dnd"]
                        assert owner() == original_owner
                    capture(category)
                    print(f"PASS {category}: actual cards/fonts, independent live choices, modal remains open, shared history/DND")
                before = state()["current"]
                for key, value in (("bar", "bad"), ("notifications", "bad"), ("wallpaperColors", "maybe"), ("mode", "server"), ("toString", "bad")):
                    assert ipc("settings", "set", key, value) == "false"
                for payload in ('{"launcher":"grid","osd":"bad"}', "not-json", "null", "[]", '{"constructor":"bad"}'):
                    result = ipc("settings", "apply", json.dumps([payload]))  # CLI [] otherwise means zero arguments.
                    assert result == "false", (payload, result, state()["current"])
                    assert state()["current"] == before
                assert ipc("settings", "preset", "bad") == "false"
                for preset in state()["presets"]:
                    assert ipc("settings", "preset", preset["key"]) == "true"
                    selected = state()
                    assert selected["opened"]
                    for key, value in preset["values"].items():
                        assert selected["current"][key] == value
                    assert selected["current"]["wallpaperColors"] and not selected["current"]["autoHide"]
                assert ipc("settings", "apply", '{"bar":"mm2103","wallpaperColors":true,"autoHide":true,"pinned":true}') == "true"
                assert state()["current"]["pinned"]
                assert ipc("settings", "set", "bar", "mm2103") == "true"
                assert state()["current"]["pinned"]
                ipc("settings", "category", "bar")
                wait_for(state, lambda value: all(option["fullyVisible"] for option in value["options"]))
                capture("bar-all-choices")
                for width in (420, 340):
                    ipc("settings", "size", width, 620)
                    selected = wait_for(state, lambda value: value["narrow"] and value["width"] == width)
                    assert all(option["width"] <= selected["viewportWidth"] + 1 for option in selected["options"])
                    capture("narrow-" + str(width))
                ipc("settings", "size", 0, 0)
                for category in ("launcher", "wallpaper", "notifications", "controls"):
                    ipc("settings", "category", category)
                    ipc("settings", "preview")
                    wait_for(lambda: state("shell"), lambda value: value["active"] == category)
                    assert not state()["opened"]
                ipc("settings", "category", "osd")
                ipc("settings", "set", "osd", "vertical")
                ipc("settings", "preview")
                wait_for(lambda: state("osd"), lambda value: value["visible"] and value["value"] == 65)
                assert state()["opened"]
                ipc("settings", "close")
                wait_for(lambda: state("shell"), lambda value: value["active"] == "")
                assert preferences.read_text() == original_preferences
                print("PASS presets, rejected atomic updates, pinning, narrow cards, live view/OSD previews and isolated persistence")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
    verify_persistence()
    assert owner() == original_owner
    print("PASS clean runtime log and unchanged production notification owner")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, help="capture the desktop, including open apps")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    verify(args.screenshots)


if __name__ == "__main__":
    main()
