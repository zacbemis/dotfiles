#!/usr/bin/env python3
"""Offline Wi-Fi/Bluetooth UI fixture integration; never touches real radios."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from verify_quickshell import CONFIG, run, wait_for, wait_for_fonts
from verify_quickshell_settings import owner

FIXTURE = Path(__file__).parent / "fixtures/connectivity.json"


def verify(screenshots):
    original_owner = owner()
    original_fixture = FIXTURE.read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "walls").mkdir()
        env = dict(os.environ, QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_STARTUP_UPDATES="0",
                   QUICKSHELL_CONNECTIVITY_FIXTURE=str(FIXTURE.resolve()), XDG_STATE_HOME=str(root / "state"),
                   WALL_DIR=str(root / "walls"), SETTER="/does-not-exist", QT_ACCESSIBILITY="0", QT_NO_XDG_DESKTOP_PORTAL="1")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))
                def state(target="connectivity"):
                    return json.loads(ipc(target, "status"))
                def capture(name):
                    if screenshots:
                        time.sleep(0.4)
                        run("grim", str(screenshots / (name + ".png")))
                def layer():
                    data = json.loads(run("hyprctl", "layers", "-j"))
                    return [entry for monitor in data.values() for level in monitor["levels"].values()
                            for entry in level if entry.get("pid") == process.pid and entry.get("namespace") == "quickshell-dev-controls"]
                wait_for(lambda: state("shell"), lambda s: s["notifications"] == "preview")
                assert ipc("connectivity", "open", "unknown") == "false"
                ipc("controls", "open")
                initial = wait_for(state, lambda s: s["ready"])
                assert not initial["readOnly"]  # Entirely offline fixture, never the real backend.
                assert initial["wifi"]["networks"] == 4 and initial["bluetooth"]["devices"] == 3
                assert not initial["bluetooth"]["discovering"]
                initial_layer = wait_for(layer, lambda layers: len(layers) == 1)[0]["address"]
                for view in ("compact", "tiles"):
                    ipc("features", "set", "controls", view)
                    ipc("controls", "open")
                    wait_for(lambda: state("controls"), lambda s: s["opened"] and s["view"] == view)
                    wait_for_fonts(lambda: state("controls")["fonts"])
                    capture("overview-" + view)
                    for kind, key in (("wifi", "network"), ("bluetooth", "bluetooth")):
                        before = wait_for(layer, lambda layers: len(layers) == 1)[0]["address"]
                        assert ipc("controls", "activate", key) == "true"
                        wait_for(state, lambda s: s["page"] == kind and s["ready"])
                        records = wait_for_fonts(lambda: state("controls")["fonts"])
                        texts = {r["text"] for r in records}
                        assert ("Home Wi-Fi" if kind == "wifi" else "Headphones") in texts, texts
                        assert layer()[0]["address"] == before
                        assert state("shell")["active"] == "controls"
                        assert not state()["bluetooth"]["discovering"]  # Opening never starts scanning.
                        details = state("controls")
                        switch = next(s for s in details["switches"] if s["kind"] == kind)
                        assert switch["visible"] and switch["enabled"] and switch["value"], switch
                        assert abs(switch["x"] + switch["width"] - (details["frame"]["width"] - 12)) < 1, details
                        row = details["networkTabs"] if kind == "wifi" else details["header"]
                        assert abs(switch["y"] + switch["height"] / 2 - (row["y"] + row["height"] / 2)) < 1, details
                        if kind == "wifi":
                            assert switch["x"] > details["networkTabs"]["vpnRight"], details
                        assert ipc("connectivity", "fixture_activate", "power") == "true"
                        wait_for(state, lambda s: not s[kind]["enabled"])
                        wait_for(lambda: state("controls"), lambda s: not next(t for t in s["switches"] if t["kind"] == kind)["value"])
                        capture(kind + "-off-" + view)
                        assert ipc("connectivity", "fixture_activate", "power") == "true"
                        wait_for(state, lambda s: s[kind]["enabled"])
                        wait_for_fonts(lambda: state("controls")["fonts"])
                        assert layer()[0]["address"] == before
                        capture(kind + "-" + view)
                        details = wait_for(lambda: state("controls"), lambda s: s["details"] and s["details"]["footerVisible"])
                        layout = details["details"]
                        assert abs(layout["footerY"] + layout["footerHeight"] - layout["height"]) < 1, layout
                        assert abs(layout["reload"]["x"] + layout["reload"]["width"] - layout["width"]) < 1, layout
                        assert layout["reload"]["y"] >= layout["footerY"], layout
                        assert ipc("connectivity", "fixture_activate", "reload") == "true"
                        if kind == "bluetooth":
                            wait_for(state, lambda s: s["bluetooth"]["discovering"])
                            assert ipc("connectivity", "fixture_activate", "reload") == "true"
                            wait_for(state, lambda s: not s["bluetooth"]["discovering"])
                        assert switch["width"] == 40 and switch["height"] == 24, switch
                        quiet = {r["text"] for r in wait_for_fonts(lambda: state("controls")["fonts"])}
                        assert not {"Saved networks", "Scan", "Advanced", "Connect", "Disconnect", "Pair", "Options"} & quiet, quiet
                        original_state = state()
                        selected = "ap1" if kind == "wifi" else "bt1"
                        assert ipc("connectivity", "fixture_activate", "row:" + selected) == "true"
                        records = wait_for_fonts(lambda: state("controls")["fonts"])
                        assert {"Disconnect", "Options"} <= {r["text"] for r in records}
                        assert state() == original_state  # Row selection never changes connections.
                        capture(kind + "-selected-" + view)
                        assert ipc("connectivity", "fixture_activate", "row:" + selected) == "true"
                        if kind == "wifi":
                            assert {"Sign-in required", "Open login page"} <= texts, texts
                            assert ipc("connectivity", "fixture_activate", "saved") == "false"
                            assert "Network settings…" in quiet, quiet
                            assert ipc("connectivity", "fixture_activate", "options:ap1") == "true"
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert {"Configure", "Change password", "Forget"} <= {r["text"] for r in records}
                            assert ipc("connectivity", "fixture_activate", "row:ap1") == "true"
                            assert ipc("connectivity", "fixture_activate", "password:ap1") == "true"
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert "Retry" in {r["text"] for r in records}
                            capture("wifi-retry-" + view)
                            assert ipc("connectivity", "fixture_activate", "ap2") == "true"
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert "Café: ; & snow 雪" in {r["text"] for r in records}
                            capture("wifi-password")
                            # Back destroys the private password field without connecting.
                            ipc("connectivity", "back")
                            assert state()["wifi"]["networks"] == 4
                        else:
                            assert "Bluetooth settings…" in quiet, quiet
                            assert ipc("connectivity", "fixture_activate", "row:bt3") == "true"
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert "Unblock" in {r["text"] for r in records}
                            assert ipc("connectivity", "fixture_activate", "row:bt3") == "true"
                            assert ipc("connectivity", "fixture_activate", "rename:bt1") == "true"
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert "Rename" in {r["text"] for r in records}
                            capture("bluetooth-rename-" + view)
                            ipc("connectivity", "back")
                            ipc("connectivity", "open", "bluetooth")
                            assert ipc("connectivity", "fixture_activate", "bt2") == "true"
                            wait_for(state, lambda s: s["prompt"] and s["prompt"]["kind"] == "confirm")
                            records = wait_for_fonts(lambda: state("controls")["fonts"])
                            assert all("123456" not in record["text"] for record in records), records
                            capture("bluetooth-confirm")
                            ipc("connectivity", "back")
                            wait_for(state, lambda s: not s["busy"] and not s["prompt"])
                        assert state()["page"] == "main"
                        assert not state()["error"]
                    ipc("connectivity", "open", "bluetooth")
                    ipc("connectivity", "open", "audio")
                    audio = lambda: json.loads(ipc("connectivity", "audio_status"))
                    wait_for(audio, lambda s: len(s["cards"]) == 1 and len(s["outputs"]) == 2)
                    texts = {r["text"] for r in wait_for_fonts(lambda: state("controls")["fonts"])}
                    assert {"Built-in speakers", "Fixture headphones", "Built-in microphone", "High quality", "Headset + microphone"} <= texts, texts
                    assert ipc("connectivity", "fixture_activate", "output:out-headphones") == "true"
                    assert ipc("connectivity", "fixture_activate", "input:in-headset") == "true"
                    assert ipc("connectivity", "fixture_activate", "profile:fixture-card:headset-head-unit") == "true"
                    changed = audio()
                    assert next(row for row in changed["outputs"] if row["selected"])["id"] == "out-headphones"
                    assert next(row for row in changed["inputs"] if row["selected"])["id"] == "in-headset"
                    assert next(row for row in changed["cards"][0]["profiles"] if row["selected"])["id"] == "headset-head-unit"
                    assert ipc("connectivity", "fixture_activate", "output:missing") == "false"
                    capture("audio-" + view)
                    ipc("connectivity", "back")
                    assert state()["page"] == "bluetooth"
                    # Both physical click dispatchers call this exact shared route.
                    for icon, kind in (("nm-applet", "wifi"), ("blueman", "bluetooth")):
                        for button in ("left", "right"):
                            assert ipc("connectivity", "click", icon, button) == "true"
                            wait_for(state, lambda s: s["page"] == kind)
                            assert state("shell")["active"] == "controls"
                            assert all(not menu["open"] for menu in json.loads(ipc("tray", "status")))
                    assert ipc("connectivity", "open", "vpn") == "true"
                    wait_for(state, lambda s: s["page"] == "vpn" and s["vpn"]["profiles"] == 2)
                    assert all(not s["visible"] for s in state("controls")["switches"])
                    assert ipc("connectivity", "fixture_activate", "power") == "false"  # No ambiguous global VPN/radio toggle.
                    texts = {r["text"] for r in wait_for_fonts(lambda: state("controls")["fonts"])}
                    assert {"Wi-Fi", "VPN", "Add VPN", "Add WireGuard", "Fixture VPN", "Fixture WireGuard"} <= texts, texts
                    assert "Configure" not in texts and "Connect" not in texts
                    capture("vpn-" + view)
                    profile = "11111111-1111-4111-8111-111111111111"
                    assert ipc("connectivity", "fixture_activate", "row:" + profile) == "true"
                    texts = {r["text"] for r in wait_for_fonts(lambda: state("controls")["fonts"])}
                    assert {"Connect", "Configure"} <= texts, texts
                    assert ipc("connectivity", "fixture_activate", profile) == "true"
                    wait_for(state, lambda s: s["vpn"]["active"] == 2)
                    assert ipc("connectivity", "fixture_activate", profile) == "true"
                    wait_for(state, lambda s: s["vpn"]["active"] == 1)
                    assert state()["wifi"]["enabled"]
                    ipc("shell", "close")
                ipc("connectivity", "open", "bluetooth")
                assert ipc("connectivity", "fixture_activate", "bt3") == "true"
                wait_for(lambda: {r["text"] for r in wait_for_fonts(lambda: state("controls")["fonts"])}, lambda texts: "Unblock" not in texts)
                assert not state()["error"]
                # A detail close must fade that detail, not replace it with the
                # overview (or unload its body) while the native surface is visible.
                motion_enabled = json.loads(ipc("shell", "motion"))["fadeDuration"] > 0
                exit_samples = 0
                for view in ("compact", "tiles"):
                    ipc("features", "set", "controls", view)
                    for kind in ("wifi", "bluetooth", "vpn", "audio"):
                        ipc("connectivity", "open", kind)
                        if kind == "wifi":
                            assert ipc("connectivity", "fixture_activate", "ap2") == "true"
                        elif kind == "bluetooth":
                            assert ipc("connectivity", "fixture_activate", "bt2") == "true"
                            wait_for(state, lambda s: bool(s["prompt"]))
                        before = wait_for(lambda: state("controls"), lambda s: s["opened"] and s["opacity"] == 1 and s["detailsLoaded"])
                        ipc("controls", "close")
                        deadline = time.monotonic() + 3
                        while True:
                            sample = state("controls")
                            assert not sample["opened"]
                            if not sample["visible"]:
                                assert not sample["detailsLoaded"], sample
                                break
                            assert sample["page"] == kind, sample
                            assert sample["detailsLoaded"], sample
                            assert sample["frame"] == before["frame"], (before["frame"], sample)
                            assert sample["connectivity"]["page"] == "main"  # Cleanup is immediate, rendering isn't.
                            exit_samples += int(0 < sample["opacity"] < 1)
                            assert time.monotonic() < deadline, sample
                        wait_for(state, lambda s: not s["busy"] and not s["prompt"] and not s["bluetooth"]["discovering"])
                        # Opening the gear during an exit must still show the
                        # overview, while opening another tray icon shows its detail.
                        ipc("connectivity", "open", kind)
                        wait_for(lambda: state("controls"), lambda s: s["opacity"] == 1)
                        ipc("controls", "close")
                        ipc("controls", "open")
                        wait_for(lambda: state("controls"), lambda s: s["opened"] and s["page"] == "main" and not s["detailsLoaded"])
                        ipc("connectivity", "open", kind)
                        wait_for(lambda: state("controls"), lambda s: s["opacity"] == 1)
                        ipc("controls", "close")
                        other = "bluetooth" if kind != "bluetooth" else "wifi"
                        ipc("connectivity", "open", other)
                        wait_for(lambda: state("controls"), lambda s: s["opened"] and s["page"] == other and s["detailsLoaded"])
                        ipc("shell", "close")
                        wait_for(lambda: state("controls"), lambda s: not s["visible"])
                assert not motion_enabled or exit_samples > 0, "No intermediate exit frames observed"
                assert FIXTURE.read_bytes() == original_fixture
                assert owner() == original_owner
                print("PASS compact toggle pills, quiet selectable lists, no favourites button, footer reload icon and progressive actions")
                print("PASS aligned Wi-Fi/Bluetooth switches, fixture on/off and no global VPN toggle")
                print("PASS both control layouts: native detail pages, adapter/connection lists, private password form, pairing confirmation/cancel and no scan-on-open")
                print("PASS saved-profile options via selected rows/settings, corrected-password form, captive portal status, Bluetooth rename/unblock UI")
                print("PASS native audio page: fixture output/input/profile selection, back routing and no physical audio changes")
                print("PASS matching left/right native panels, visible VPN/WireGuard configuration controls, scoped fixture connect/disconnect")
                print("PASS detail exit frames retain content/geometry, immediate logical cleanup, hidden loader release and rapid gear/tray reopening")
                print("PASS same native controls surface during detail navigation, resolved SF roles, redacted credential/code audit and unchanged notification ownership")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)
    print("PASS clean fixture runtime; no real radio, connection, pairing, trust or profile changes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=Path, help="captures open desktop/apps")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    verify(args.screenshots)


if __name__ == "__main__":
    main()
