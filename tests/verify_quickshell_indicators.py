#!/usr/bin/env python3
"""Real bars/selector: indicator display modes only, no hardware writes."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from verify_quickshell import CONFIG, run, wait_for, wait_for_fonts
from verify_quickshell_settings import owner


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    original_owner = owner()
    with tempfile.TemporaryDirectory(prefix="quickshell-indicators.") as tmp:
        root = Path(tmp)
        preferences = root / "daily.json"
        original = '{"version":1,"volumeIndicator":"hidden"}'
        preferences.write_text(original)
        palette = root / "palette.css"
        def colors(primary):
            palette.write_text('@define-color background #101820; @define-color primary ' + primary
                + '; @define-color secondary #ddaa33; @define-color tertiary #de55d1; @define-color on_surface #eef4fa;')
        colors("#7aaad1")
        env = dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_STARTUP_UPDATES="0",
                   QUICKSHELL_PREFERENCES=str(preferences), QUICKSHELL_PALETTE=str(palette), XDG_STATE_HOME=str(root / "state"),
                   QT_NO_XDG_DESKTOP_PORTAL="1", QT_ACCESSIBILITY="0", QT_IM_MODULE="compose")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))
                def settings():
                    return json.loads(ipc("settings", "status"))
                def bars():
                    return json.loads(ipc("bar", "geometry"))
                def capture(name):
                    if args.screenshots:
                        time.sleep(.35)
                        run("grim", str(args.screenshots / (name + ".png")))
                wait_for(settings, lambda s: bool(s["current"]))
                assert set(settings()["indicators"].values()) == {"both"}  # Comparison never reads daily prefs.
                assert ipc("settings", "set", "wallpaperColors", "true") == "true"
                assert ipc("settings", "category", "indicators") == "true"
                wait_for_fonts(lambda: settings()["fonts"])
                capture("settings")
                assert {r["text"] for r in settings()["fonts"]} >= {"Sound", "Brightness", "Battery", "Icon + %", "Icon only", "% only", "Hidden"}
                assert len(settings()["indicatorControls"]) == 3
                for width in (340, 720):
                    ipc("settings", "size", width, 420)
                    wait_for(settings, lambda s: s["width"] == width and all(row["width"] > 0 for row in s["indicatorControls"]))
                    for row in settings()["indicatorControls"]:
                        assert len(row["options"]) == 4
                        assert all(button["width"] >= 28 and button["x"] >= 0 and button["x"] + button["width"] <= row["width"] + 1 for button in row["options"]), row
                assert ipc("features", "set", "osd", "vertical") == "true"
                for profile in ("current", "enzo", "mm2103"):
                    ipc("profile", "set", profile)
                    for mode in ("both", "icon", "percent", "hidden"):
                        payload = {key: mode for key in ("volumeIndicator", "brightnessIndicator", "batteryIndicator")}
                        assert ipc("settings", "apply", json.dumps(payload)) == "true"
                        assert settings()["opened"] and settings()["category"] == "indicators"
                        assert set(settings()["indicators"].values()) == {mode}
                        wait_for(bars, lambda data: data and all(b.get("profile", "current") == profile for b in data))
                        for bar in bars():
                            if profile == "current":
                                entries = bar["indicators"]
                                visibility = {key: bar["modules"][key]["visible"] for key in entries}
                            else:
                                entries = {slot["key"]: slot for slot in bar["controls"]["slots"] if slot["key"] in ("volume", "brightness", "battery")}
                                visibility = {key: key in entries for key in ("volume", "brightness", "battery")}
                            if mode == "hidden":
                                assert not any(visibility.values()), (profile, entries)
                            else:
                                assert visibility["volume"], (profile, entries)
                                for key, item in entries.items():
                                    if not visibility[key]:
                                        continue
                                    assert item["iconVisible"] == (mode != "percent"), (profile, mode, item)
                                    assert bool(item["text"]) == (mode != "icon"), (profile, mode, item)
                                    if item["iconVisible"]:
                                        assert item["iconColor"] == json.loads(ipc("shell", "theme"))["roles"]["barIcon"], (profile, item)
                            if profile != "current":
                                icon_colors = {slot["iconColor"] for slot in bar["controls"]["slots"] if slot.get("iconVisible") and "iconColor" in slot}
                                assert len(icon_colors) == 1, (profile, icon_colors)
                        assert json.loads(ipc("features", "status"))["osd"] == "vertical"
                        capture(profile + "-" + mode)
                    previous = settings()["indicators"]
                    assert ipc("settings", "apply", '{"volumeIndicator":"icon","batteryIndicator":"bad"}') == "false"
                    assert settings()["indicators"] == previous
                assert ipc("settings", "apply", '{"volumeIndicator":"icon","brightnessIndicator":"icon","batteryIndicator":"icon"}') == "true"
                previous_color = json.loads(ipc("shell", "theme"))["roles"]["barIcon"]
                colors("#cc9955")
                next_color = wait_for(lambda: json.loads(ipc("shell", "theme"))["roles"]["barIcon"], lambda color: color != previous_color)
                wait_for(bars, lambda data: all(slot["iconColor"] == next_color for bar in data for slot in bar["controls"]["slots"] if slot.get("iconVisible") and "iconColor" in slot))
                def notification_state():
                    return json.loads(ipc("notifications", "status"))
                def notification_color(profile):
                    data = bars()[0]
                    if profile == "current":
                        return data["notificationIconColor"]
                    return next(slot["iconColor"] for slot in data["controls"]["slots"] if slot["key"] == "notifications")
                palette_roles = json.loads(ipc("shell", "theme"))["roles"]
                normal, unread = palette_roles["barIcon"], palette_roles["barUnreadIcon"]
                assert normal != unread
                assert sum(int(normal[-6:][i:i+2], 16) for i in (0,2,4)) > sum(int(unread[-6:][i:i+2], 16) for i in (0,2,4))
                for profile in ("current", "enzo", "mm2103"):
                    ipc("profile", "set", profile)
                    wait_for(bars, lambda data: data and all(b.get("profile", "current") == profile for b in data))
                    for view in ("current", "compact", "stacked"):
                        ipc("features", "set", "notifications", view)
                        ipc("notifications", "clear")
                        wait_for(notification_state, lambda s: s["unread"] == 0)
                        assert notification_color(profile) == normal
                        assert ipc("notifications", "preview", "Unread fixture", "Offline color check") == "true"
                        wait_for(notification_state, lambda s: s["unread"] == 1)
                        wait_for(lambda: notification_color(profile), lambda color: color == unread)
                        if profile == "current" and view == "current":
                            wait_for(notification_state, lambda s: s["popups"] == 0, timeout=6)
                            assert notification_state()["unread"] == 1 and notification_color(profile) == unread
                        ipc("notifications", "open")
                        wait_for(notification_state, lambda s: s["unread"] == 0 and s["count"] == 1)
                        wait_for(lambda: notification_color(profile), lambda color: color == normal)
                        assert ipc("notifications", "preview", "Already visible fixture", "Created while the center is open") == "true"
                        wait_for(notification_state, lambda s: s["unread"] == 0 and s["count"] == 2)
                        assert notification_color(profile) == normal
                        ipc("notifications", "close")
                        ipc("settings", "open")
                        ipc("notifications", "dnd_toggle")
                        assert notification_color(profile) == normal
                        ipc("notifications", "preview", "DND fixture", "Unseen even without a popup")
                        wait_for(notification_state, lambda s: s["unread"] == 1 and s["dnd"])
                        wait_for(lambda: notification_color(profile), lambda color: color == unread)
                        ipc("notifications", "open")
                        wait_for(notification_state, lambda s: s["unread"] == 0)
                        assert notification_color(profile) == normal
                        ipc("notifications", "dnd_toggle")
                        ipc("notifications", "close")
                        ipc("settings", "open")
                assert ipc("settings", "set", "volumeIndicator", "icon") == "true"
                assert ipc("settings", "set", "brightnessIndicator", "hidden") == "true"
                assert ipc("settings", "set", "batteryIndicator", "percent") == "true"
                chosen = settings()["indicators"]
                ipc("settings", "preset", "classic")
                assert settings()["indicators"] == chosen
                ipc("features", "set", "osd", "vertical")
                assert ipc("osd", "preview", "brightness", 65) == "true"
                assert json.loads(ipc("osd", "status"))["visible"]  # Hiding the bar never disables popup feedback.
                wait_for(lambda: json.loads(ipc("osd", "status")), lambda s: not s["visible"], timeout=4)
                assert preferences.read_text() == original
                assert owner() == original_owner
                print("PASS all three bar profiles: icon+percent, icon-only, percent-only and hidden; independent modes and OSD")
                print("PASS near-white wallpaper tint and live palette replacement; unseen-only dark notification accent across 3 bars/3 centers, including expiry and DND")
                print("PASS indicator settings UI, atomic validation, preset independence, isolated preferences and no hardware/notification changes")
            finally:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)


if __name__ == "__main__":
    main()
