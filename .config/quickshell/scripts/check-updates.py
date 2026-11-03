#!/usr/bin/env python3
"""Read-only update checks with explicit errors; never run an upgrade."""
import json
import shutil
import subprocess

BACKENDS = (
    ("pacman", ("checkupdates",), (0, 2)),  # 2 means no updates, not a failure.
    ("aur", ("yay", "-Qua"), (0,)),
    ("flatpak", ("flatpak", "remote-ls", "--updates", "--columns=application"), (0,)),
)


def check_updates():
    counts, errors = {}, {}
    for name, command, success_codes in BACKENDS:
        if not shutil.which(command[0]):
            continue
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            # yay follows pacman's query convention: exit 1 with no output
            # means no matching upgrades. Diagnostics/partial output still fail.
            empty_aur = name == "aur" and result.returncode == 1 and not result.stdout.strip() and not result.stderr.strip()
            if result.returncode not in success_codes and not empty_aur:
                errors[name] = (result.stderr.strip() or f"exit {result.returncode}")[:500]
            else:
                counts[name] = sum(bool(line.strip()) for line in result.stdout.splitlines())
        except (OSError, subprocess.TimeoutExpired) as error:
            errors[name] = str(error)[:500]
    if not counts and not errors:
        errors["backends"] = "No supported update checker is installed"
    return {"count": sum(counts.values()), "counts": counts, "errors": errors,
            "ok": not errors}


if __name__ == "__main__":
    print(json.dumps(check_updates()))
