#!/usr/bin/env python3
"""Exercise imported layouts without launching apps, applying wallpapers or changing hardware.

Optional --screenshots captures your open desktop/apps, just like verify_quickshell.py.
"""
import argparse
import html
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from verify_quickshell import CONFIG, check_text_fonts, run, wait_for


def verify(screenshots):
    env = dict(os.environ, QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_COMPARE="1",
               QUICKSHELL_BAR="1", QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
    # Deliberately inherit server mode: comparison must override it before any
    # notification backend is instantiated. Preview checks never use notify-send.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        walls = root / "wallpapers"
        walls.mkdir()
        # Use a tiny raster fixture, never the real wallpaper library/setter.
        import struct
        import zlib
        def chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        (walls / "comparison.png").write_bytes(b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\x24\x4a\x73")) + chunk(b"IEND", b""))
        env.update(WALL_DIR=str(walls), XDG_STATE_HOME=str(root / "state"), SETTER="/does-not-exist")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))

                def status():
                    return json.loads(ipc("shell", "status"))

                def capture(profile, surface):
                    if screenshots:
                        time.sleep(1)
                        run("grim", str(screenshots / f"{profile}-{surface}.png"))

                wait_for(status, lambda state: state["notifications"] == "preview")
                assert ipc("profile", "set", "not-a-profile") == "false"
                assert ipc("profile", "activate", "not-a-feature") == "false"
                for profile in ("current", "enzo", "mm2103", "enzo", "current"):
                    assert ipc("profile", "set", profile) == "true"
                    wait_for(status, lambda state: state["profile"] == profile and state["active"] == "")
                    wait_for(lambda: json.loads(ipc("bar", "geometry")),
                             lambda bars: bool(bars) and all(bar.get("profile", "current") == profile for bar in bars))
                    for bar in json.loads(ipc("bar", "geometry")):
                        check_text_fonts(bar["fonts"], bar_only=True)
                        assert any(item["role"] == "bar" for item in bar["fonts"]), bar
                        if profile != "current":
                            controls = bar["controls"]
                            slots = controls["slots"]
                            keys = [slot["key"] for slot in slots]
                            assert keys[-2:] == ["controls", "notifications"] and keys.count("controls") == 1, keys
                            assert "wallpaper" not in keys and "settings" not in keys
                    profile_state = json.loads(ipc("profile", "status"))
                    assert profile_state["comparing"] and profile_state["name"] == profile
                    assert json.loads(ipc("notifications", "status"))["mode"] == "preview"
                    capture(profile, "bar")

                    for feature in ("launcher", "wallpaper", "notifications", "controls"):
                        assert ipc("profile", "activate", feature) == "true"
                        wait_for(status, lambda state: state["active"] == feature)
                        if feature == "launcher":
                            assert isinstance(json.loads(ipc(feature, "results")), list)
                        elif feature == "wallpaper":
                            wait_for(lambda: json.loads(ipc(feature, "results")), lambda entries: len(entries) == 1)
                        elif feature == "controls":
                            assert json.loads(ipc("controls", "status"))["opened"]
                        else:
                            assert ipc("profile", "activate", "sample") == "true"
                            wait_for(lambda: json.loads(ipc("notifications", "status")), lambda state: state["count"] > 0)
                        capture(profile, feature)
                        ipc("shell", "close")
                    # Preview history belongs to the shared service, not to a bar
                    # loader; it must survive repeated profile destruction/reload.
                    assert json.loads(ipc("notifications", "status"))["count"] > 0

                    tray = json.loads(ipc("tray", "items"))
                    network = next((item for item in tray if item["id"] == "nm-applet" and item["hasMenu"]), None)
                    if network:
                        assert ipc("tray", "menu", network["id"]) == "true"
                        wait_for(lambda: json.loads(ipc("tray", "status")),
                                 lambda menus: any(menu["open"] and menu["entries"] for menu in menus))
                        ipc("profile", "activate", "launcher")
                        wait_for(lambda: json.loads(ipc("tray", "status")), lambda menus: all(not menu["open"] for menu in menus))
                        ipc("shell", "close")
                    if profile != "current":
                        ipc("profile", "colors")
                        wait_for(lambda: json.loads(ipc("bar", "geometry")),
                                 lambda bars: all(bar["palette"] == "wallpaper" for bar in bars))
                        for bar in json.loads(ipc("bar", "geometry")):
                            check_text_fonts(bar["fonts"], bar_only=True)
                        capture(profile, "wal-colors")
                        ipc("profile", "colors")
                    if profile == "mm2103":
                        ipc("profile", "autohide")
                        ipc("bar", "reveal")
                        wait_for(lambda: json.loads(ipc("bar", "geometry")),
                                 lambda bars: all(bar["revealed"] and bar["exclusiveZone"] == 0 for bar in bars))
                        ipc("bar", "hide")
                        wait_for(lambda: json.loads(ipc("bar", "geometry")),
                                 lambda bars: all(not bar["revealed"] and bar["maskHeight"] == 2 for bar in bars))
                        ipc("bar", "toggle")
                        wait_for(lambda: json.loads(ipc("bar", "geometry")),
                                 lambda bars: all(bar["revealed"] and bar["exclusiveZone"] == 32 for bar in bars))
                        ipc("profile", "autohide")
                    print(f"PASS {profile}: actual SF bar text, live layout, feature routes, preview history, tray, palette and lifecycle")
                ipc("notifications", "clear")
                ipc("shell", "close")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
        print("PASS clean comparison runtime log; no real apps, wallpaper setter, updates or hardware controls invoked")
    if screenshots:
        cards = []
        for profile in ("current", "enzo", "mm2103"):
            images = "".join(f'<h3>{html.escape(surface)}</h3><img src="{profile}-{surface}.png">'
                             for surface in ("bar", "launcher", "wallpaper", "notifications"))
            cards.append(f"<section><h2>{profile}</h2>{images}</section>")
        (screenshots / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Quickshell comparison</title>'
            '<style>body{background:#16181c;color:#eee;font:14px sans-serif}main{display:flex;gap:16px}section{flex:1;min-width:0}img{width:100%}</style>'
            '<h1>Imported bar/layout comparisons</h1><p>Pickers and notification surfaces intentionally share our implementation.</p><main>'
            + "".join(cards) + "</main>")
        print(f"Gallery: {screenshots / 'index.html'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, help="capture the desktop, including your open apps")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
        args.screenshots = args.screenshots.resolve()
    verify(args.screenshots)


if __name__ == "__main__":
    main()
