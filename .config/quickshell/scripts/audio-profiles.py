#!/usr/bin/env python3
"""Bounded Bluetooth profile adapter for the installed PipeWire Pulse interface.

Quickshell handles default-node routing natively; its installed API has no card
profile interface. Only explicit, validated Bluetooth profile selection mutates.
"""
import argparse
import json
import os
import subprocess


def pactl(*args):
    result = subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=8)
    if result.returncode:
        raise ValueError("Audio service unavailable or the device rejected the profile.")
    if len(result.stdout) > 2_000_000:
        raise ValueError("Audio response is too large.")
    return result.stdout


def cards_from(raw):
    cards = []
    for card in raw[:128]:
        props = card.get("properties", {})
        if not (card.get("name", "").startswith("bluez_card.") or props.get("device.api") == "bluez5"):
            continue
        active = card.get("active_profile", "")
        groups = {}
        for name, profile in list(card.get("profiles", {}).items())[:128]:
            if profile.get("available") in (False, "no", "not available"):
                continue
            if "sinks" in profile and int(profile["sinks"]) == 0:
                continue
            mode = "headset" if "headset" in name or "handsfree" in name or ("bap" in name and int(profile.get("sources", 0)) > 0) else "headphones" if "a2dp" in name or "bap" in name else ""
            if not mode:
                continue
            row = {"id": name, "name": "High quality" if mode == "headphones" else "Headset + microphone",
                   "description": profile.get("description", name), "selected": name == active,
                   "priority": int(profile.get("priority", 0))}
            if mode not in groups or (row["selected"], row["priority"]) > (groups[mode]["selected"], groups[mode]["priority"]):
                groups[mode] = row
        cards.append({"id": str(card["index"]), "key": card["name"], "name": props.get("device.description", card["name"]),
                      "profiles": list(groups.values())})
    return cards


def apply_profile(card_id, key, profile, read_only=False):
    if read_only:
        raise ValueError("Preview mode is read-only.")
    cards = json.loads(pactl("--format=json", "list", "cards"))
    card = next((c for c in cards if str(c["index"]) == card_id and c["name"] == key
                 and (c["name"].startswith("bluez_card.") or c.get("properties", {}).get("device.api") == "bluez5")), None)
    option = card.get("profiles", {}).get(profile) if card else None
    if not option or option.get("available") in (False, "no", "not available") or not any(s in profile for s in ("a2dp", "bap", "headset", "handsfree")):
        raise ValueError("That Bluetooth audio profile is no longer available.")
    pactl("set-card-profile", card_id, profile)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", action="store_true")
    parser.add_argument("--card")
    parser.add_argument("--name")
    parser.add_argument("--profile")
    args = parser.parse_args()
    try:
        if not args.snapshot:
            apply_profile(args.card, args.name, args.profile,
                          os.getenv("QUICKSHELL_COMPARE") == "1" or os.getenv("QUICKSHELL_CONNECTIVITY_READ_ONLY") == "1")
        cards = cards_from(json.loads(pactl("--format=json", "list", "cards")))
        print(json.dumps({"cards": cards, "error": ""}))
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        print(json.dumps({"cards": [], "error": "Audio profiles unavailable. Check the device and PipeWire Pulse service."}))


if __name__ == "__main__":
    main()
