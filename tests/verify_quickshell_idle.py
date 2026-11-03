#!/usr/bin/env python3
"""Actual OSD regression with a fake backlight; never dims/restores real hardware."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from test_idle_brightness import HELPER, fake_backlight
from verify_quickshell import CONFIG, run, wait_for
from verify_quickshell_settings import owner


def main():
    original_owner = owner()
    with tempfile.TemporaryDirectory(prefix="quickshell-idle-fixture.") as tmp:
        root = Path(tmp)
        value, marker, calls, env = fake_backlight(root)
        env.update(QUICKSHELL_COMPARE="1", QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_STARTUP_UPDATES="0",
                   XDG_STATE_HOME=str(root / "state"), QT_NO_XDG_DESKTOP_PORTAL="1", QT_ACCESSIBILITY="0")
        log_path = root / "shell.log"
        with log_path.open("w") as log:
            process = subprocess.Popen(["bash", str(CONFIG / "compare.sh"), "current", "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                def ipc(target, method, *args):
                    return run("qs", "ipc", "--pid", str(process.pid), "call", target, method, *map(str, args))
                def state():
                    return json.loads(ipc("osd", "status"))
                def idle(action):
                    result = subprocess.run([sys.executable, str(HELPER), action], env=env, capture_output=True, text=True, timeout=10)
                    assert result.returncode == 0, result.stderr
                def sample(raw, serial, visible):
                    data = wait_for(state, lambda s: s["brightnessReady"] and s["brightness"] == raw)
                    assert data["serial"] == serial and data["visible"] == visible, data
                    return data
                def annotate(phase, raw, token, device="panel", expiry=None):
                    marker.parent.mkdir(parents=True, exist_ok=True)
                    marker.write_text(json.dumps({"version": 1, "device": device, "phase": phase, "raw": raw,
                        "token": token, "expires": expiry if expiry is not None else time.time_ns() // 1_000_000 + 4000}))
                wait_for(lambda: json.loads(ipc("shell", "status")), lambda s: s["notifications"] == "preview")
                wait_for(state, lambda s: s["brightnessReady"] and s["brightness"] == 40)
                for view in ("horizontal", "vertical"):
                    ipc("features", "set", "osd", view)
                    initial = wait_for(state, lambda s: s["armed"] and not s["visible"])
                    serial = initial["serial"]
                    idle("dim")
                    sample(10, serial, False)
                    idle("restore")
                    sample(40, serial, False)
                    # A real adjustment immediately after wake is not masked by
                    # a blanket grace timer, including returning to restore value.
                    value.write_text("35")
                    sample(35, serial + 1, True)
                    value.write_text("40")
                    sample(40, serial + 2, True)
                    wait_for(state, lambda s: not s["visible"], timeout=4)
                    # Dim+restore can both happen between brightness polls.
                    idle("dim"); idle("restore")
                    time.sleep(1.1)
                    sample(40, serial + 2, False)
                    # An unobserved restore target must not silence a manual
                    # different value, or a later manual return to that target.
                    idle("restore")
                    value.write_text("30")
                    sample(30, serial + 3, True)
                    value.write_text("40")
                    sample(40, serial + 4, True)
                    wait_for(state, lambda s: not s["visible"], timeout=4)
                    assert ipc("osd", "preview", "volume", 65) == "true"
                    shown = state()
                    assert shown["visible"] and shown["kind"] == "volume" and shown["value"] == 65
                    wait_for(state, lambda s: not s["visible"], timeout=4)
                serial = state()["serial"]
                annotate("pending", 10, "pending-test")
                value.write_text("10")
                sample(10, serial, False)
                annotate("complete", 10, "pending-test")
                time.sleep(1.1)
                value.write_text("25")
                sample(25, serial + 1, True)
                value.write_text("10")
                sample(10, serial + 2, True)
                serial += 2
                for raw, data in ((20, {"phase": "complete", "raw": 20, "token": "expired", "expiry": 1}),
                                  (30, {"phase": "complete", "raw": 30, "token": "other", "device": "other-device"}),
                                  (40, {"phase": "complete", "raw": 40, "token": "future", "expiry": time.time_ns() // 1_000_000 + 100000})):
                    annotate(**data)
                    value.write_text(str(raw))
                    serial += 1
                    sample(raw, serial, True)
                marker.write_text("not-json")
                value.write_text("45")
                sample(45, serial + 1, True)
                assert owner() == original_owner
                print("PASS both OSD layouts: automatic dim/restore stay quiet; bar values still update")
                print("PASS immediate manual adjustment/return after wake, coalesced idle events, pending operations and volume preview")
                print("PASS expired/malformed/wrong-device markers fail open; no real backlight/audio/notification changes")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
        problems = [line for line in log_path.read_text().splitlines() if "WARN" in line or "ERROR" in line]
        assert not problems, "\n".join(problems)


if __name__ == "__main__":
    main()
