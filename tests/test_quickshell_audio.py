"""Offline Bluetooth profile adapter coverage; never calls the host audio service."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("audio_profiles", ROOT / ".config/quickshell/scripts/audio-profiles.py")
AUDIO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIO)

CARD = {"index": 17, "name": "bluez_card.fixture", "properties": {"device.api": "bluez5", "device.description": "Fixture headset"},
        "active_profile": "a2dp-sink-sbc", "profiles": {
            "off": {"available": True, "priority": 0},
            "a2dp-sink-sbc": {"available": True, "priority": 10},
            "a2dp-sink-aac": {"available": True, "priority": 20},
            "headset-head-unit": {"available": True, "priority": 5},
            "headset-unavailable": {"available": False, "priority": 99}}}


class AudioProfiles(unittest.TestCase):
    def test_available_modes_preserve_active_codec_and_exclude_other_cards(self):
        other = dict(CARD, index=18, name="alsa_card.fixture", properties={})
        cards = AUDIO.cards_from([CARD, other])
        self.assertEqual(len(cards), 1)
        profiles = cards[0]["profiles"]
        self.assertEqual({p["id"] for p in profiles}, {"a2dp-sink-sbc", "headset-head-unit"})
        self.assertTrue(next(p for p in profiles if p["id"] == "a2dp-sink-sbc")["selected"])
        changed = copy.deepcopy(CARD)
        changed["active_profile"] = "headset-head-unit"
        self.assertIn("a2dp-sink-aac", {p["id"] for p in AUDIO.cards_from([changed])[0]["profiles"]})

    def test_exact_card_identity_and_live_profile_validation(self):
        with patch.object(AUDIO, "pactl", return_value=json.dumps([CARD])) as call:
            AUDIO.apply_profile("17", "bluez_card.fixture", "headset-head-unit")
            self.assertEqual(call.call_args.args, ("set-card-profile", "17", "headset-head-unit"))
        for card, key, profile in (("18", "bluez_card.fixture", "headset-head-unit"),
                                   ("17", "bluez_card.other", "headset-head-unit"),
                                   ("17", "bluez_card.fixture", "off"),
                                   ("17", "bluez_card.fixture", "headset-unavailable"),
                                   ("17", "bluez_card.fixture", "$(touch nope)")):
            with patch.object(AUDIO, "pactl", return_value=json.dumps([CARD])) as call:
                with self.assertRaises(ValueError):
                    AUDIO.apply_profile(card, key, profile)
                self.assertEqual(call.call_count, 1)
                self.assertEqual(call.call_args.args, ("--format=json", "list", "cards"))

    def test_read_only_blocks_before_any_command(self):
        with patch.object(AUDIO, "pactl") as call:
            with self.assertRaises(ValueError):
                AUDIO.apply_profile("17", "bluez_card.fixture", "headset-head-unit", True)
            call.assert_not_called()

    def test_bounded_fixed_argv_and_generic_external_errors(self):
        with patch.object(AUDIO.subprocess, "run") as run:
            run.return_value.returncode, run.return_value.stdout = 0, "[]"
            self.assertEqual(AUDIO.pactl("--format=json", "list", "cards"), "[]")
            self.assertEqual(run.call_args.args[0], ["pactl", "--format=json", "list", "cards"])
            self.assertEqual(run.call_args.kwargs["timeout"], 8)
            self.assertNotIn("shell", run.call_args.kwargs)
            run.return_value.returncode, run.return_value.stderr = 1, "private external text"
            with self.assertRaisesRegex(ValueError, "Audio service unavailable"):
                AUDIO.pactl("--format=json", "list", "cards")

    def test_native_routing_and_fixture_guards(self):
        code = (ROOT / ".config/quickshell/services/AudioService.qml").read_text()
        self.assertIn("Pipewire.preferredDefaultAudioSink = node", code)
        self.assertIn("Pipewire.preferredDefaultAudioSource = node", code)
        self.assertIn("if (fixture) return;", code)
        self.assertIn("if (readOnly || busy) return false", code)
        self.assertIn("SystemState.ignoredSink(n)", code)
        self.assertIn('if (readOnly || !["output", "input"].includes(kind)) return false', code)
