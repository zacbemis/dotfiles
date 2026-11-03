#!/usr/bin/env python3
"""Preserve idle save/dim/restore, while identifying automatic OSD samples.

Only a short-lived, device-specific raw value is written to the runtime directory.
No shell/desktop is started, no persistent preferences are changed.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid


def status(text):
    for line in text.strip().splitlines():
        fields = line.split(",")
        if len(fields) >= 5 and fields[1] == "backlight" and re.fullmatch(r"[\w.-]+", fields[0]):
            raw, maximum = int(fields[2]), int(fields[4])
            if 0 <= raw <= maximum and maximum > 0:
                return fields[0], raw, maximum
    raise ValueError("No backlight value")


def marker_path():
    override = os.getenv("QUICKSHELL_BRIGHTNESS_AUTOMATION")
    runtime = os.getenv("XDG_RUNTIME_DIR")
    return Path(override) if override else Path(runtime) / "quickshell-desktop/brightness-automation.json" if runtime else None


def write_marker(path, device, phase, raw, lifetime, token, saved):
    value = {"version": 1, "device": device, "phase": phase, "raw": raw, "token": token, "saved": saved,
             "expires": time.time_ns() // 1_000_000 + lifetime}
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".brightness-", delete=False) as file:
            name = file.name
            json.dump(value, file)
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def invoke(args):
    return subprocess.run(["brightnessctl", "--class=backlight", "--machine-readable", *args],
                          capture_output=True, text=True, timeout=5)


def clear_marker(path):
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def operation(action, path):
    arguments = ["-s", "set", "10"] if action == "dim" else ["-r"]
    device = None
    if path:
        try:
            info = invoke(["info"])
            device, raw, maximum = status(info.stdout)
            saved = raw if action == "dim" else None
            if action == "restore":
                try:
                    with path.open() as file:
                        previous = json.loads(file.read(2048))
                    candidate = previous.get("saved")
                    if previous.get("device") == device and type(candidate) is int and 0 <= candidate <= maximum:
                        saved = candidate
                except (OSError, ValueError, AttributeError):
                    pass
            token = uuid.uuid4().hex
            expected = min(10, maximum) if action == "dim" else saved if saved is not None else -1
            write_marker(path, device, "pending", expected, 10000, token, saved)
        except (OSError, ValueError, subprocess.SubprocessError):
            device = None  # Metadata must never prevent the original idle action.
    try:
        result = invoke((["--device=" + device] if device else []) + arguments)
        if path and device:
            try:
                changed_device, raw, _ = status(result.stdout)
                if result.returncode or changed_device != device:
                    raise ValueError("Backlight operation failed")
                write_marker(path, device, "complete", raw, 4000, token, saved)
            except (OSError, ValueError):
                clear_marker(path)
        return result.returncode
    except (OSError, subprocess.SubprocessError):
        if path and device:
            clear_marker(path)
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("dim", "restore"))
    args = parser.parse_args()
    path = marker_path()
    if path:
        try:
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            lock = (path.parent / "brightness-automation.lock").open("a")
        except OSError:
            return operation(args.action, None)
        with lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return operation(args.action, path)
    return operation(args.action, None)


if __name__ == "__main__":
    raise SystemExit(main())
