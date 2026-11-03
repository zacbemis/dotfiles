#!/usr/bin/env python3
"""Verify feature-level adapters with a harmless app and stub wallpaper setter.

Optional screenshots include your open desktop/apps. No real wallpaper, clipboard,
package, audio, brightness, network or Bluetooth changes are made.
"""
import argparse
import html
import json
import os
import shlex
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import zlib

from verify_quickshell import CONFIG, run, wait_for, wait_for_fonts


def verify(screenshots):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        walls = root / "walls"
        walls.mkdir()
        def chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\x00\x24\x4a\x73")) + chunk(b"IEND", b"")
        for name in ("One.png", "雪 #two.png", "Three\nwall.png"):
            (walls / name).write_bytes(png)
        setter_marker = root / "wallpaper-applied"
        setter = root / "setter.sh"
        setter.write_text(f'#!/bin/sh\nprintf "%s" "$1" > "{setter_marker}"\n')
        apps = root / "applications"
        apps.mkdir()
        app_marker = root / "app-launched"
        (apps / "quickshell-feature-fixture.desktop").write_text(
            '[Desktop Entry]\nType=Application\nName=Quickshell Feature Fixture\n'
            f'Exec=/usr/bin/touch {app_marker}\nIcon=application-x-executable\n')
        terminal_marker = root / "terminal-app"
        (apps / "quickshell-terminal-fixture.desktop").write_text(
            '[Desktop Entry]\nType=Application\nName=Quickshell Terminal Fixture\nTerminal=true\n'
            f'Exec=/usr/bin/touch {terminal_marker}\nIcon=utilities-terminal\n')
        browser = root / "browser"
        browser.mkdir()
        (browser / "Nested folder").mkdir()
        target_file = browser / "雪 ; file\nname.txt"
        target_file.write_text("fixture")
        opened_marker = root / "file-opened"
        binaries = root / "bin"
        binaries.mkdir()
        opener = binaries / "xdg-open"
        opener.write_text('#!/usr/bin/python3\nimport pathlib,sys\npathlib.Path(' + repr(str(opened_marker)) + ').write_text(sys.argv[1])\n')
        opener.chmod(0o755)
        terminal = binaries / "kitty"
        terminal.write_text('#!/usr/bin/python3\nimport subprocess,sys\na=sys.argv[sys.argv.index("-e")+1:]\n'
            + 'assert a == ["/usr/bin/touch", ' + repr(str(terminal_marker)) + ']\nsubprocess.run(a,check=True)\n')
        terminal.chmod(0o755)
        env = dict(os.environ, PATH=str(binaries) + ":" + os.environ["PATH"], QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_COMPARE="1",
                   QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1", XDG_STATE_HOME=str(root / "state"),
                   WALL_DIR=str(walls), SETTER=str(setter),
                   XDG_DATA_DIRS=str(root) + ":" + os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share"))
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "enzo", "--no-color"],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))

                def state(target):
                    return json.loads(ipc(target, "status"))

                def select(feature, view):
                    assert ipc("features", "set", feature, view) == "true"
                    wait_for(lambda: state("features"), lambda s: s[feature] == view)

                def capture(name):
                    if screenshots:
                        time.sleep(1)
                        run("grim", str(screenshots / f"{name}.png"))

                wait_for(lambda: state("shell"), lambda s: s["notifications"] == "preview")
                assert ipc("features", "set", "unknown", "current") == "false"
                assert ipc("features", "set", "wallpaper", "unknown") == "false"
                for view in ("mm2103", "grid", "current", "grid"):
                    select("launcher", view)
                    ipc("launcher", "search", "Quickshell Feature Fixture")
                    wait_for(lambda: json.loads(ipc("launcher", "results")), lambda rows: rows == ["Quickshell Feature Fixture"])
                    assert state("launcher")["view"] == view
                    size = wait_for(lambda: state("launcher")["size"], lambda size: 0 < size["height"] <= 420)
                    assert 0 < size["width"] <= 720, size
                    if view == "grid":
                        before = state("launcher")["pins"]
                        assert ipc("launcher", "pin", 0) == "true"
                        assert state("launcher")["pins"] != before
                    if view in ("mm2103", "grid"):
                        wait_for(lambda: state("launcher"), lambda s: s["selectedName"] == "Quickshell Feature Fixture" and s["selected"] == 0)
                        ipc("launcher", "activate")
                        wait_for(app_marker.exists, bool)
                        app_marker.unlink()
                        usage = wait_for(lambda: list((root / "state").rglob("launcher-usage.json")), bool)
                        assert sum(json.loads(usage[0].read_text()).values()) >= 1
                    if view != "current":
                        ipc("launcher", "search", "= (12 + 3) * 2")
                        wait_for(lambda: json.loads(ipc("launcher", "results")), lambda rows: rows == ["30"])
                        for invalid in ("= Math.random()", "= 1/0", "= while(true){}"):
                            ipc("launcher", "search", invalid)
                            assert json.loads(ipc("launcher", "results")) == []
                        ipc("launcher", "search", "? snow & ice")
                        assert state("launcher")["mode"] == "web"
                        assert len(json.loads(ipc("launcher", "results"))) == 1
                        # Do not activate web/calc/emoji: leave browser/clipboard alone.
                        ipc("launcher", "search", "; grinning")
                        wait_for(lambda: json.loads(ipc("launcher", "results")), bool)
                    ipc("launcher", "search", "")
                    ipc("launcher", "select", 0)
                    wait_for(lambda: state("launcher"), lambda s: s["rendered"] > 0 and abs(s["firstRowTop"]) < 1)
                    wait_for_fonts(lambda: state("launcher")["fonts"])
                    capture("launcher-" + view)
                    if view == "grid":
                        columns = state("launcher")["columns"]
                        assert ipc("launcher", "navigate", "down") == "true"
                        assert state("launcher")["selected"] == columns
                        ipc("launcher", "navigate", "right")
                        assert state("launcher")["selected"] == columns + 1
                    ipc("shell", "close")
                    wait_for(lambda: state("launcher"), lambda s: s["rendered"] == 0)
                print("PASS launchers: common app/usage backend, pins, calculator bounds, web/emoji queries, 2D navigation, delegate release")
                for view in ("current", "mm2103", "grid"):
                    select("launcher", view)
                    ipc("launcher", "search", "Quickshell Terminal Fixture")
                    wait_for(lambda: json.loads(ipc("launcher", "results")), lambda rows: rows == ["Quickshell Terminal Fixture"])
                    ipc("launcher", "select", 0)
                    ipc("launcher", "activate")
                    wait_for(terminal_marker.exists, bool)
                    terminal_marker.unlink()
                    marker = root / ("command-" + view)
                    command = "printf '%s' 'fixture value' > " + shlex.quote(str(marker))
                    assert ipc("launcher", "mode", "run") == "true"
                    ipc("launcher", "search", "> " + command)
                    wait_for(lambda: state("launcher"), lambda s: s["mode"] == "run" and s["rows"] and s["rows"][0]["value"] == command)
                    assert not marker.exists(), "Typing a command must never execute it"
                    ipc("launcher", "select", 0)
                    ipc("launcher", "activate")
                    wait_for(marker.exists, bool)
                    assert marker.read_text() == "fixture value"
                    ipc("launcher", "search", str(browser) + "/")
                    s = wait_for(lambda: state("launcher"), lambda s: any(row["value"] == str(target_file) for row in s["rows"]))
                    directory = next(i for i, row in enumerate(s["rows"]) if row["name"] == "Nested folder")
                    ipc("launcher", "select", directory)
                    ipc("launcher", "activate")
                    wait_for(lambda: state("launcher"), lambda s: s["query"].endswith("Nested folder/"))
                    assert state("shell")["active"] == "launcher"
                    ipc("launcher", "search", str(browser) + "/")
                    s = wait_for(lambda: state("launcher"), lambda s: any(row["value"] == str(target_file) for row in s["rows"]))
                    index = next(i for i, row in enumerate(s["rows"]) if row["value"] == str(target_file))
                    assert not opened_marker.exists(), "Browsing must not open a file"
                    ipc("launcher", "select", index)
                    ipc("launcher", "activate")
                    wait_for(opened_marker.exists, bool)
                    assert opened_marker.read_text() == str(target_file)
                    opened_marker.unlink()
                print("PASS Quickshell launcher: all views support terminal apps, explicit Run execution and exact-path file browsing/opening")

                for view in ("gallery", "carousel", "current", "gallery"):
                    select("wallpaper", view)
                    ipc("wallpaper", "open")
                    entries = wait_for(lambda: json.loads(ipc("wallpaper", "results")), lambda rows: len(rows) == 3)
                    wait_for(lambda: state("wallpaper"), lambda s: not s["scanning"] and s["view"] == view)
                    selected = next(index for index, entry in enumerate(entries) if "\n" in entry["path"])
                    ipc("wallpaper", "select", selected)
                    assert state("wallpaper")["path"] == entries[selected]["path"]
                    assert not setter_marker.exists(), "Selecting a preview must not apply it"
                    wait_for_fonts(lambda: state("wallpaper")["fonts"])
                    size = state("wallpaper")["size"]
                    limit = (720, 420)
                    assert 0 < size["width"] <= limit[0] and 0 < size["height"] <= limit[1], size
                    if view == "carousel":
                        before = wait_for(lambda: state("wallpaper"), lambda s: s["currentSlide"] == selected and s["centerError"] is not None and abs(s["centerError"]) < 1)
                        assert before["scrollEnabled"]
                        ipc("wallpaper", "select", 0)
                        wait_for(lambda: state("wallpaper"), lambda s: s["currentSlide"] == 0 and abs(s["contentX"] - before["contentX"]) > 1)
                        ipc("wallpaper", "select", selected)
                        wait_for(lambda: state("wallpaper"), lambda s: s["currentSlide"] == selected and abs(s["centerError"]) < 1)
                        assert not setter_marker.exists(), "Browsing must not apply a wallpaper"
                    capture("wallpaper-" + view)
                    ipc("wallpaper", "activate")
                    wait_for(setter_marker.exists, bool)
                    assert setter_marker.read_text() == entries[selected]["path"]
                    setter_marker.unlink()
                    wait_for(lambda: state("shell"), lambda s: s["active"] == "")
                    wait_for(lambda: state("wallpaper"), lambda s: s["renderedRows"] == 0 and s["previewSource"] == "")
                print("PASS wallpapers: all views use exact-path stub setter, no apply on selection, shared scan/selection, hidden image release")

                ipc("notifications", "clear")
                for index in range(8):
                    ipc("notifications", "preview_app", "Mail" if index < 5 else "Chat", f"Message {index}", "A notification for the selected view.\nPlain text <b>not markup</b>.")
                for view in ("compact", "stacked", "current", "compact"):
                    select("notifications", view)
                    ipc("notifications", "open")
                    s = wait_for(lambda: state("notifications"), lambda s: s["view"] == view and s["count"] == 8 and s["unread"] == 0)
                    assert s["mode"] == "preview" and s["popupEligibleCount"] <= 5
                    if view != "current":
                        wait_for(lambda: state("notifications"), lambda s: s["alternative"]["opened"] and s["alternative"]["count"] == 8
                                 and 0 < s["alternative"]["firstCardHeight"] < 180)
                    if view == "stacked":
                        assert ipc("notifications", "filter", 1) == "true"
                        assert state("notifications")["alternative"]["filter"] == 1
                        assert ipc("notifications", "group_toggle", "Mail") == "true"
                        assert "mail" in state("notifications")["alternative"]["collapsed"]
                        ipc("notifications", "group_toggle", "Mail")
                    wait_for_fonts(lambda: state("notifications")["fonts"])
                    capture("notifications-" + view)
                    ipc("shell", "close")
                    # A bar switch must not reset the independent notification view.
                    ipc("profile", "set", "mm2103")
                    assert state("features")["notifications"] == view
                    assert state("notifications")["count"] == 8
                ipc("notifications", "group_dismiss", "Mail")
                wait_for(lambda: state("notifications"), lambda s: s["count"] == 3)
                print("PASS notification views: shared preview records/history, unread state, grouping/filter, dismissal and independent bar selection")

                for view in ("compact", "tiles"):
                    select("controls", view)
                    ipc("controls", "open")
                    s = wait_for(lambda: state("controls"), lambda s: s["opened"] and s["view"] == view)
                    assert len(s["tiles"]) == 9
                    wait_for_fonts(lambda: state("controls")["fonts"])
                    capture("controls-" + view)
                    # Exercise the same route dispatcher, but never hardware/update actions.
                    assert ipc("controls", "activate", "launcher") == "true"
                    assert state("shell")["active"] == "launcher"
                    assert ipc("controls", "activate", "unknown") == "false"
                    ipc("shell", "close")
                for view in ("horizontal", "vertical"):
                    select("osd", view)
                    assert ipc("osd", "preview", "volume", 65) == "true"
                    wait_for(lambda: state("osd"), lambda s: s["visible"] and s["view"] == view and s["value"] == 65)
                    capture("osd-" + view)
                    wait_for(lambda: state("osd"), lambda s: not s["visible"], timeout=4)
                select("osd", "off")
                assert ipc("osd", "preview", "volume", 65) == "false"
                ipc("notifications", "clear")
                print("PASS quick settings and OSD: independent layouts, routed actions, synthetic previews and expiry; hardware/clipboard unchanged")
            finally:
                import sys
                if sys.exc_info()[0]:
                    log.flush()
                    print(log_path.read_text())
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
        print("PASS clean feature-comparison runtime log")
    if screenshots:
        groups = {"launcher": ["current", "mm2103", "grid"], "wallpaper": ["current", "gallery", "carousel"],
                  "notifications": ["current", "compact", "stacked"], "controls": ["compact", "tiles"], "osd": ["horizontal", "vertical"]}
        sections = []
        for feature, views in groups.items():
            cards = "".join(f'<article><h3>{html.escape(view)}</h3><img src="{feature}-{view}.png"></article>' for view in views)
            sections.append(f'<h2>{feature}</h2><section>{cards}</section>')
        (screenshots / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Quickshell features</title>'
            '<style>body{background:#16181c;color:#eee;font:14px sans-serif}section{display:flex;gap:12px}article{flex:1;min-width:0}img{width:100%}</style>'
            '<h1>Independent feature comparisons</h1><p>Shared services; fixture wallpapers/app and preview notifications.</p>' + "".join(sections))
        print(f"Gallery: {screenshots / 'index.html'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, help="capture your desktop/open apps")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
        args.screenshots = args.screenshots.resolve()
    verify(args.screenshots)


if __name__ == "__main__":
    main()
