#!/usr/bin/env python3
"""CLI smoke tests and optional grim captures; never stops the existing UI stack."""
import argparse
import json
import os
import subprocess
import re
import tempfile
import time
from pathlib import Path

CONFIG = Path(__file__).resolve().parent


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def move_cursor(signature, x, y):
    # Current Hyprland uses typed Lua dispatchers; older releases use strings.
    try:
        return run("hyprctl", "-i", signature, "eval",
                   f"hl.dispatch(hl.dsp.cursor.move({{x={int(x)}, y={int(y)}}}))")
    except subprocess.CalledProcessError:
        return run("hyprctl", "-i", signature, "dispatch", "movecursor", f"{int(x)} {int(y)}")


def wait_for(probe, predicate, timeout=8):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = probe()
            if predicate(last):
                return last
        except (subprocess.CalledProcessError, ValueError):
            pass
        time.sleep(0.1)
    raise AssertionError(f"Timed out; last state: {last!r}")


def test_scanner():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for name in ("one/same.png", "two/same.png", "雪 #1\nwallpaper.JPG", "ignore.txt"):
            path = root / name
            path.parent.mkdir(exist_ok=True)
            path.touch()
        current = root / "current"
        current.symlink_to(root / "one/same.png")
        entries = json.loads(run("python3", str(CONFIG / "wallpaper-scan.py"), str(root), str(current)))
        assert len(entries) == 3
        assert sum(entry["current"] for entry in entries) == 1
        assert len({entry["path"] for entry in entries}) == 3
        assert any("\n" in entry["name"] for entry in entries)
        assert json.loads(run("python3", str(CONFIG / "wallpaper-scan.py"), str(root / "missing"), str(current))) == []
    print("PASS wallpaper discovery: Unicode, newline, duplicate names, current symlink, missing directory")


def test_ui_accuracy(ipc):
    geometry = wait_for(lambda: json.loads(ipc("bar", "geometry")),
                        lambda windows: bool(windows) and all(
                            not item["lookupPending"] and item["naturalWidth"] > 0
                            for window in windows for item in window["tray"]))
    for window in geometry:
        tray = window["tray"]
        assert window["modules"]["tray"]["width"] == len(tray) * 15 + max(0, len(tray) - 1) * 8 + 32
        for item in tray:
            assert item["imageWidth"] == item["imageHeight"] == 15, item
            # Papirus's larger variants add transparent padding to panel icons.
            if "Papirus" in item["resolvedPath"]:
                assert "/16x16" in item["resolvedPath"], item
        for previous, following in zip(tray, tray[1:]):
            assert abs(following["bounds"]["x"] - previous["bounds"]["x"] - 23) < 0.1, tray
        for workspace in window["workspaces"]:
            assert workspace["height"] == 18, workspace
            if workspace["focused"]:
                assert workspace["targetWidth"] >= 52, workspace
    print("PASS UI geometry: 15px tray canvases, GTK logical-size variants, 8px gaps, 18px workspace height")

    def motion():
        return json.loads(ipc("shell", "motion"))

    def surface(route):
        return next(item for item in motion()["surfaces"] if item["route"] == route)

    ipc("shell", "close")
    wait_for(motion, lambda state: all(not item["visible"] for item in state["surfaces"]))
    settings = motion()
    ipc("launcher", "open")
    samples = []
    deadline = time.monotonic() + settings["pickerDuration"] / 1000 + 2
    while time.monotonic() < deadline:
        sample = surface("launcher")
        samples.append(sample)
        if sample["scale"] < 1:
            assert json.loads(ipc("launcher", "status"))["selected"] == 0, "Pop-in must not move selection under a stationary pointer"
        assert sample["opened"] and sample["focusable"], sample
        assert 0.849 <= sample["scale"] <= 1.001 and 0 <= sample["opacity"] <= 1, sample
        if sample["scale"] == sample["opacity"] == 1:
            break
        time.sleep(0.04)
    else:
        raise AssertionError(samples)
    if settings["enabled"] and settings["pickerDuration"] >= 300:
        assert any(0.85 < sample["scale"] < 1 for sample in samples), samples
        assert all(a["scale"] <= b["scale"] for a, b in zip(samples, samples[1:])), samples
    ipc("launcher", "close")
    closing = surface("launcher")
    assert not closing["opened"] and not closing["focusable"], closing
    wait_for(lambda: surface("launcher"), lambda item: not item["visible"])
    # Reverse an exit and change routes while animations are in flight.
    for route in ("launcher", "wallpaper", "launcher"):
        ipc(route, "open")
    wait_for(motion, lambda state: all(item["opened"] == (item["route"] == "launcher")
                                      and (item["route"] == "launcher" or not item["visible"])
                                      for item in state["surfaces"]))
    ipc("shell", "close")
    wait_for(motion, lambda state: all(not item["visible"] for item in state["surfaces"]))
    if not settings["enabled"]:
        assert all(settings[key] == 0 for key in ("pickerDuration", "fadeDuration", "workspaceDuration", "controlDuration")), settings
    print("PASS motion: intermediate frames, monotonic pop-in, completed exits, immediate input release, rapid route reversal")


def test_shell(backend, screenshots):
    env = dict(os.environ, QUICKSHELL_NOTIFICATIONS="server" if backend else "preview",
               QUICKSHELL_BAR="0" if backend else "1",
               QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        env["XDG_STATE_HOME"] = str(root / "state")
        live_palette = Path.home() / ".config/waybar/colors/colors.css"
        base_css = live_palette.read_text() if live_palette.exists() else (
            "@define-color background #202124;\n@define-color primary #a8c7fa;\n"
            "@define-color on_surface #f1f3f4;\n@define-color tertiary #f4b8c8;\n")
        palette_source = root / "source.css"
        palette_source.write_text(base_css)
        palette_path = root / "colors.css"
        palette_path.symlink_to(palette_source)
        env["QUICKSHELL_PALETTE"] = str(palette_path)
        # Execute only a harmless fixture app and a stub wallpaper setter.
        # Real desktop entries, wallpaper selection and palette stay untouched.
        applications = root / "applications"
        applications.mkdir()
        marker = root / "launched"
        fixture = root / "fixture.py"
        fixture.write_text(f"from pathlib import Path\nPath({str(marker)!r}).touch()\n")
        (applications / "quickshell-smoke.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Quickshell Smoke Fixture\n"
            f"Exec=/usr/bin/python3 {fixture}\nIcon=application-x-executable\n")
        env["XDG_DATA_DIRS"] = str(root) + ":" + env.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
        setter_marker = root / "wallpaper-selected"
        setter = root / "setter.sh"
        setter.write_text(f'#!/bin/sh\nprintf "%s" "$1" > "{setter_marker}"\n')
        env["SETTER"] = str(setter)
        if not screenshots:
            import struct
            import zlib
            def chunk(kind, data):
                return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
            png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 2, 0, 0, 0))
                   + chunk(b"IDAT", zlib.compress(b"\x00\xff\x80\x00")) + chunk(b"IEND", b""))
            walls = root / "wallpapers"
            walls.mkdir()
            (walls / "test #雪.png").write_bytes(png)
            env["WALL_DIR"] = str(walls)
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "run.sh"), "--no-color"], env=env,
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))

                def status():
                    return json.loads(ipc("notifications", "status"))

                wait_for(status, lambda state: state["mode"] == env["QUICKSHELL_NOTIFICATIONS"])
                assert process.poll() is None, log_path.read_text()

                if not backend:
                    theme = json.loads(ipc("shell", "theme"))
                    assert theme["fonts"] == {"bar": "SF Pro Display", "ui": "Mononoki Nerd Font Propo",
                        "menu": "Mononoki Nerd Font Propo", "barBold": True, "uiBold": True}, theme
                    # Check the face Qt resolved, not just our requested strings.
                    # Qt.font({families: [...]}) silently rendered FreeSans before.
                    for role, family, pixels in (("bar", "SF Pro Display", 15),
                            ("ui", "Mononoki Nerd Font Propo", 14),
                            ("menu", "Mononoki Nerd Font Propo", 15),
                            ("barIcon", "JetBrainsMono Nerd Font Propo", 15)):
                        resolved = theme["resolvedFonts"][role]
                        assert resolved == {"family": family, "style": "Bold", "pixelSize": pixels, "bold": True}, resolved
                    print("PASS actual Qt font resolution: SF Pro Display / Mononoki / JetBrainsMono Bold")
                    test_ui_accuracy(ipc)
                    tray_items = json.loads(ipc("tray", "items"))
                    network = next((item for item in tray_items if item["id"] == "nm-applet" and item["hasMenu"]), None)
                    if network:
                        assert ipc("tray", "open", network["id"]) == "true"
                        def menu_state():
                            return next((state for state in json.loads(ipc("tray", "status")) if state["open"]), {})
                        menu = wait_for(menu_state, lambda state: bool(state.get("entries")))
                        if screenshots:
                            time.sleep(0.3)
                            run("grim", str(screenshots / "network-menu.png"))
                            # Real pointer hover, restored immediately. No menu actions
                            # are invoked and network connections are never changed.
                            instances = json.loads(run("hyprctl", "instances", "-j"))
                            pointer_cli = os.environ.get("QUICKSHELL_POINTER_CLI")
                            if len(instances) == 1 and pointer_cli:
                                signature = instances[0]["instance"]
                                saved = json.loads(run("hyprctl", "-i", signature, "cursorpos", "-j"))
                                try:
                                    point = wait_for(menu_state, lambda state: bool(state.get("hoverPoint")))["hoverPoint"]
                                    layers = json.loads(run("hyprctl", "-i", signature, "layers", "-j"))
                                    levels = layers[menu["screen"]]["levels"]
                                    origin = next(layer for group in levels.values() for layer in group
                                                  if layer["pid"] == process.pid and layer["namespace"] == "quickshell-dev-tray-menu")
                                    move_cursor(signature, point["x"] + origin["x"], point["y"] + origin["y"])
                                    run(pointer_cli)  # compositor warps alone do not emit real motion
                                    wait_for(menu_state, lambda state: state.get("selected", -1) >= 0)
                                    run("grim", str(screenshots / "network-menu-hover.png"))
                                finally:
                                    move_cursor(signature, saved["x"], saved["y"])
                            else:
                                ipc("tray", "next")
                                wait_for(menu_state, lambda state: state.get("selected", -1) >= 0)
                                run("grim", str(screenshots / "network-menu-selected.png"))
                        sub = next((entry for entry in menu["entries"] if entry["submenu"] and entry["enabled"]), None)
                        if sub:
                            assert ipc("tray", "submenu", sub["text"]) == "true"
                            wait_for(menu_state, lambda state: state.get("depth") == 2 and bool(state.get("entries")))
                            if screenshots:
                                time.sleep(0.3)
                                run("grim", str(screenshots / "network-submenu.png"))
                            ipc("tray", "back")
                            wait_for(menu_state, lambda state: state.get("depth") == 1 and bool(state.get("entries")))
                        ipc("tray", "close")
                        assert all(not state["open"] for state in json.loads(ipc("tray", "status")))
                        assert ipc("tray", "open", network["id"]) == "true"
                        ipc("launcher", "open")
                        assert all(not state["open"] for state in json.loads(ipc("tray", "status"))), "Picker must close the exclusive tray overlay"
                        print("PASS live nm-applet left-click path: themed dropdown, submenus, back/close (no network actions)")
                    else:
                        print("SKIP live network menu: nm-applet is not registered")
                    ipc("launcher", "open")
                    assert json.loads(ipc("shell", "status"))["active"] == "launcher"
                    assert isinstance(json.loads(ipc("launcher", "results")), list)
                    if screenshots:
                        time.sleep(2)
                        run("grim", str(screenshots / "launcher.png"))
                    ipc("launcher", "search", "no-such-app-5e96d05d")
                    assert json.loads(ipc("launcher", "results")) == []
                    if screenshots:
                        time.sleep(0.5)
                        run("grim", str(screenshots / "launcher-empty.png"))
                    ipc("wallpaper", "open")
                    assert json.loads(ipc("shell", "status"))["active"] == "wallpaper"
                    wait_for(lambda: json.loads(ipc("wallpaper", "results")), lambda result: isinstance(result, list))
                    if screenshots:
                        time.sleep(3)
                        run("grim", str(screenshots / "wallpaper.png"))
                    ipc("wallpaper", "size", 340, 420)
                    wait_for(lambda: json.loads(ipc("wallpaper", "status")),
                             lambda state: state["compact"] and not state["previewVisible"])
                    if screenshots:
                        time.sleep(0.3)
                        run("grim", str(screenshots / "wallpaper-compact.png"))
                    ipc("wallpaper", "size", 340, 600)
                    wait_for(lambda: json.loads(ipc("wallpaper", "status")),
                             lambda state: state["compact"] and state["previewVisible"])
                    if screenshots:
                        time.sleep(0.3)
                        run("grim", str(screenshots / "wallpaper-stacked.png"))
                    ipc("wallpaper", "size", 820, 500)
                    wait_for(lambda: json.loads(ipc("wallpaper", "status")), lambda state: not state["compact"])
                    ipc("wallpaper", "search", "no-such-wallpaper-5e96d05d")
                    assert json.loads(ipc("wallpaper", "results")) == []
                    ipc("shell", "close")
                    assert json.loads(ipc("shell", "status"))["active"] == ""
                    assert ipc("notifications", "preview", "Quickshell migration", "Native popups and history; SwayNC is still running.") == "true"
                    wait_for(status, lambda state: state["count"] == 1 and state["popups"] == 1)
                    if screenshots:
                        time.sleep(0.5)
                        run("grim", str(screenshots / "notification-popup.png"))
                    ipc("notifications", "open")
                    if screenshots:
                        time.sleep(0.8)
                        run("grim", str(screenshots / "notification-center.png"))
                    wait_for(status, lambda state: state["count"] == 1 and state["popups"] == 0)
                    assert status()["unread"] == 0
                    ipc("notifications", "clear")
                    ipc("shell", "close")
                    for index in range(4):
                        body = "\n".join(f"Line {line}: expandable message" for line in range(14)) if index == 3 else "A grouped notification"
                        assert ipc("notifications", "preview_app", "Mail", f"Message {index}", body) == "true"
                    ipc("notifications", "preview_app", "Chat", "New conversation", "Unread until the center opens")
                    wait_for(status, lambda state: state["count"] == 5 and state["unread"] == 5)
                    ipc("notifications", "open")
                    grouped = wait_for(status, lambda state: state["unread"] == 0
                        and len(state["groups"]) == 2 and all(group["rendered"] == group["shown"] for group in state["groups"]))
                    mail = next(group for group in grouped["groups"] if group["key"] == "mail")
                    assert mail["count"] == 4 and mail["shown"] == 3, mail
                    assert mail["font"] == {"family": "Mononoki Nerd Font Propo", "bold": True, "pixelSize": 12}, mail
                    long_message = grouped["records"][1]["sequence"]
                    def body_state():
                        group = next(group for group in status()["groups"] if group["key"] == "mail")
                        return next(body for body in group["bodies"] if body["sequence"] == long_message)
                    wait_for(body_state, lambda body: body["truncated"] and not body["expanded"])
                    assert ipc("notifications", "message_expand", long_message) == "true"
                    wait_for(body_state, lambda body: body["expanded"] and not body["truncated"])
                    assert ipc("notifications", "message_expand", long_message) == "true"
                    wait_for(body_state, lambda body: body["truncated"] and not body["expanded"])
                    assert all(record["receivedAt"] > 0 and record["seen"] for record in grouped["records"])
                    assert grouped["panel"]["y"] >= 12 and grouped["panel"]["height"] > 0
                    assert ipc("notifications", "group_toggle", "MAIL") == "true"
                    wait_for(status, lambda state: next(group for group in state["groups"] if group["key"] == "mail")["rendered"] == 0)
                    assert ipc("notifications", "group_expand", "mail") == "true"
                    wait_for(status, lambda state: next(group for group in state["groups"] if group["key"] == "mail")["rendered"] == 4)
                    if screenshots:
                        time.sleep(0.3)
                        run("grim", str(screenshots / "notification-groups.png"))
                    ipc("notifications", "group_dismiss", "Mail")
                    wait_for(status, lambda state: state["count"] == 1 and len(state["groups"]) == 1
                        and state["groups"][0]["key"] == "chat")
                    assert ipc("notifications", "group_toggle", "missing") == "false"
                    ipc("notifications", "clear")
                    wait_for(status, lambda state: state["count"] == 0 and state["groups"] == [])
                    print("PASS notifications: live groups, unread/read, derived font, collapse/expand, full bodies, group dismissal")
                    ipc("launcher", "search", "Quickshell Smoke Fixture")
                    assert json.loads(ipc("launcher", "results")) == ["Quickshell Smoke Fixture"]
                    ipc("launcher", "activate")
                    wait_for(marker.exists, bool)
                    usage = wait_for(lambda: list((root / "state").rglob("launcher-usage.json")), bool)
                    wait_for(lambda: json.loads(usage[0].read_text()) if usage else {},
                             lambda scores: scores.get("quickshell-smoke", scores.get("quickshell-smoke.desktop")) == 1)
                    ipc("wallpaper", "search", "")
                    selected = wait_for(lambda: json.loads(ipc("wallpaper", "results")), bool)
                    wait_for(lambda: json.loads(ipc("wallpaper", "status")), lambda state: not state["scanning"])
                    ipc("wallpaper", "select", len(selected) - 1)
                    assert json.loads(ipc("wallpaper", "status"))["path"] == selected[-1]["path"]
                    assert not setter_marker.exists(), "Selecting/previewing must not apply a wallpaper"
                    ipc("wallpaper", "activate")
                    wait_for(setter_marker.exists, bool)
                    assert setter_marker.read_text() in [entry["path"] for entry in selected]
                    wait_for(lambda: json.loads(ipc("shell", "status")), lambda state: state["active"] == "")
                    print("PASS pickers: search, empty results, exclusive routes, compact/stacked layouts, fixture launch/history, select-only preview, stub apply")
                    print("PASS preview popup expiry retains history")

                    def theme_state():
                        return json.loads(ipc("shell", "theme"))
                    def css_variant(colors):
                        css = base_css
                        for role, value in colors.items():
                            css = re.sub(r"(@define-color\s+" + role + r"\s+)[^;]+;",
                                         lambda match: match[1] + value + ";", css)
                        return css
                    alternative = css_variant({"background": "#142821", "primary": "#9ad8a1",
                        "tertiary": "#abd1ef", "secondary": "#efc98c", "inverse_primary": "#507268"})
                    palette_source.write_text(alternative)
                    changed = wait_for(theme_state, lambda state: state["primary"] == "#9ad8a1")
                    assert changed["menuHover"] == changed["pickerSelected"] == "#9ad8a1"
                    assert changed["controlHover"] != theme["controlHover"]
                    if screenshots:
                        ipc("launcher", "open")
                        time.sleep(0.4)
                        run("grim", str(screenshots / "palette-changed.png"))
                        ipc("shell", "close")
                    atomic = root / "atomic.css"
                    atomic.write_text(base_css)
                    atomic.replace(palette_source)
                    wait_for(theme_state, lambda state: state["primary"] == theme["primary"])
                    replacement = root / "replacement.css"
                    replacement.write_text(alternative)
                    palette_path.unlink()
                    palette_path.symlink_to(replacement)
                    wait_for(theme_state, lambda state: state["primary"] == "#9ad8a1")
                    replacement.unlink()
                    time.sleep(2.2)
                    assert theme_state()["primary"] == "#9ad8a1"  # last good palette
                    replacement.write_text("@define-color background #000000;\n")
                    time.sleep(2.2)
                    assert theme_state()["background"] == "#142821"  # partial write ignored
                    replacement.write_text(base_css)
                    wait_for(theme_state, lambda state: state["primary"] == theme["primary"])
                    print("PASS fonts and live palette: writes, atomic replacement, symlink replacement, missing/partial recovery")
                else:
                    # All notify-send calls use the private D-Bus session inherited
                    # from dbus-run-session, not the real desktop notification bus.
                    def notify(summary, timeout=0, *extra):
                        return run("notify-send", "-p", "-t", str(timeout), *extra, summary, "Smoke test body")

                    # Hide popup surfaces so the real pointer cannot pause timers.
                    ipc("notifications", "open")
                    notification_id = notify("Timed notification", 1200)
                    first = wait_for(status, lambda state: state["count"] == 1 and state["popups"] == 1)
                    assert first["records"][0]["timeoutMs"] == 1200, first
                    wait_for(status, lambda state: state["count"] == 1 and state["popups"] == 0)
                    notify("Replacement sticky", 0, "-r", notification_id)
                    wait_for(status, lambda state: state["count"] == 1 and state["summaries"] == ["Replacement sticky"])
                    time.sleep(1.5)
                    assert status()["popups"] == 1, status()
                    ipc("notifications", "dnd_toggle")
                    notify("DND history")
                    wait_for(status, lambda state: state["count"] == 2 and state["popups"] == 0)
                    ipc("notifications", "dnd_toggle")
                    ipc("notifications", "clear")
                    wait_for(status, lambda state: state["count"] == 0)
                    notify("Transient", 300, "-h", "int:transient:1")
                    wait_for(status, lambda state: state["count"] == 1)
                    wait_for(status, lambda state: state["count"] == 0)
                    for index in range(6):
                        last_id = notify(f"Popup limit {index}")
                    wait_for(status, lambda state: state["count"] == 6 and state["popups"] == 5)
                    # Closing from the client must also remove the record.
                    run("gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                        "--object-path", "/org/freedesktop/Notifications", "--method",
                        "org.freedesktop.Notifications.CloseNotification", last_id)
                    wait_for(status, lambda state: state["count"] == 5 and state["popups"] == 4)
                    run("gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                        "--object-path", "/org/freedesktop/Notifications", "--method",
                        "org.freedesktop.Notifications.Notify", "Smoke", "0", "", "Action buttons",
                        "Plain body", "['default', 'Open', 'accept', 'Accept', 'long', 'A longer wrapped action label']",
                        "{}", "0")
                    wait_for(status, lambda state: state["count"] == 6)
                    time.sleep(0.3)  # Let action delegates lay out before clear.
                    ipc("notifications", "clear")
                    for index in range(102):
                        notify(f"History limit {index}")
                    wait_for(status, lambda state: state["count"] == 100 and state["popups"] == 5)
                    print("PASS notification server: timeout, replacement, sticky, DND, transient, popup/history caps, client close, action layout")
                ipc("notifications", "clear")
                wait_for(status, lambda state: state["count"] == 0 and state["popups"] == 0)
                ipc("shell", "close")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        text = log_path.read_text()
        problems = [line for line in text.splitlines() if "ERROR" in line or "WARN" in line]
        assert not problems, "\n".join(problems)
        print("PASS clean Quickshell runtime log")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", action="store_true", help="internal: run on a private D-Bus session")
    parser.add_argument("--screenshots", type=Path, help="save desktop screenshots (may include your open apps)")
    args = parser.parse_args()
    if args.backend:
        if not os.environ.get("QUICKSHELL_PRIVATE_TEST_BUS"):
            parser.error("--backend must run on a private bus; use the default command instead")
        test_shell(True, None)
        return
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
        args.screenshots = args.screenshots.resolve()
    test_scanner()
    test_shell(False, args.screenshots)
    subprocess.run(["dbus-run-session", "--", "env", "QUICKSHELL_PRIVATE_TEST_BUS=1",
                    "python3", str(Path(__file__).resolve()), "--backend"], check=True)
    if args.screenshots:
        print(f"Screenshots: {args.screenshots}")


if __name__ == "__main__":
    main()
