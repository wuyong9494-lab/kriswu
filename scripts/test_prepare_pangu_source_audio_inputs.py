"""Focused checks for the new source-only Pangu audio input preparation."""
import copy
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import wave

import prepare_pangu_source_audio_inputs as audio


def wav_bytes():
    target = io.BytesIO()
    with wave.open(target, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(22050)
        wav.writeframes(b"\x01\x00\x02\x00\x03\x00\x04\x00")
    return target.getvalue()


class UndecodableClip:
    m_Name = "reviewed_sound"
    m_Channels = 1
    m_Frequency = 22050
    m_Length = 4 / 22050

    @property
    def samples(self):
        raise AssertionError("Reviewed original PCM must not be decoded again")


class PanguSourceAudioInputsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.wav = wav_bytes()
        self.path = audio.PREFIX + "voice/reviewed_sound.wav"
        self.identity = {"bundle": "original.bin", "bundleSHA256": "a" * 64,
                         "pathID": "123", "objectSHA256": "b" * 64,
                         "encodedSHA256": "c" * 64, "encodedBytes": 32}
        self.row = {"name": "reviewed.wav", "sourcePath": self.path,
                    "sourcePathID": "123", "sourceBundle": "original.bin",
                    "sourceBundleSHA256": "a" * 64, "sourceObjectSHA256": "b" * 64,
                    "encodedSHA256": "c" * 64, "encodedBytes": 32,
                    "sourceName": "reviewed_sound", "bytes": len(self.wav),
                    "sha256": audio.sha(self.wav), "sampleRate": 22050,
                    "channels": 1, "sampleFrames": 4, "sampleWidth": 2}
        (self.directory / "reviewed.wav").write_bytes(self.wav)
        self.receipt = {"name": "reviewed-provenance.json", "sha256": "d" * 64}

    def tearDown(self):
        self.temporary.cleanup()

    def test_actual_source_crop_keeps_marker_origin_and_alternative_routes(self):
        path = Path(__file__).with_name("pangu_source_motion_inventory_20261114.json")
        data = path.read_bytes()
        self.assertEqual(audio.sha(data), audio.MOTION_SHA256)
        inventory = json.loads(data)
        aliases, groups, identifiers = audio.marker_groups(inventory)
        self.assertEqual((len(aliases), len(groups), len(identifiers)), (5, 8, 25))
        blink = next(row for row in aliases if row["animation"] == "D19_Back_Blink_End")
        self.assertEqual(blink["rawTiming"]["FirstFrame"], 17)
        marker = next(row for row in groups if row["animation"] == "D19_Back_Blink_End")
        self.assertEqual((marker["rawFrame"], marker["sourceFrame"]), (17, 17))
        self.assertEqual(len(marker["sourceIdentifiers"]), 2)
        male = next(row for row in groups if row["animation"] == "D19_Missile"
                    and row["route"] == "Sounds.Gender.Male")
        self.assertEqual(male["sourceFrame"], 20)
        self.assertEqual(len(male["sourcePaths"]), 5)
        self.assertTrue(all(row["runtimeClip"] is None and row["runtimeTick"] is None for row in groups))
        self.assertEqual(blink["rawSoundMarkers"], next(row["soundMarkers"] for row in inventory["records"]
                         if row["animation"] == "D19_Back_Blink_End"))

    def test_negative_sound_frames_clamp_and_absent_frames_require_evidence(self):
        source = {"animation": "D19_Test", "configurationSource": {}, "motion": {
            key: None for key in ("sourceFile", "sourceBundle", "sourceObjectPath", "pathID", "bytes", "sha256")},
            "rawMarkers": {"FirstFrame": 12}, "soundMarkers": []}
        for frame in (-4, 0, 1):
            source["soundMarkers"].append({"Frame": frame,
                "Common": ["voice/reviewed_sound@Battle@Voice"], "Gender": None})
        _, groups, _ = audio.marker_groups({"records": [source]})
        self.assertEqual([row["sourceFrame"] for row in groups], [0, 0, 1])
        self.assertEqual([row["rawFrame"] for row in groups], [-4, 0, 1])
        for unsupported in (None, True):
            source["soundMarkers"][0]["Frame"] = unsupported
            with self.assertRaisesRegex(ValueError, "must be explicit"):
                audio.marker_groups({"records": [source]})

    def test_ambiguous_catalog_object_is_rejected(self):
        row = {"file": "original.bin", "bytes": 100, "sha256": "a" * 64,
               "crc_ok": True, "types": {"AudioClip": 1},
               "paths": [{"path": self.path, "file_id": 0, "path_id": 123}]}
        match = audio.catalog_matches([row], [self.path])
        self.assertEqual(match[self.path]["pathID"], "123")
        second = copy.deepcopy(row)
        second["paths"][0]["path_id"] = 456
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            audio.catalog_matches([row, second], [self.path])

    def test_reviewed_pcm_is_not_decoded_again_and_wrong_source_is_rejected(self):
        result, path = audio.reuse_pcm(self.path, self.identity, UndecodableClip(),
                                      (self.row, self.directory, self.receipt))
        self.assertTrue(result["reusedExistingPCM"])
        self.assertEqual(path.read_bytes(), self.wav)
        for key in ("pathID", "objectSHA256", "encodedSHA256"):
            with self.subTest(key=key):
                different = {**self.identity, key: "0"}
                with self.assertRaisesRegex(ValueError, "different source object"):
                    audio.reuse_pcm(self.path, different, UndecodableClip(),
                                    (self.row, self.directory, self.receipt))

    def test_altered_or_truncated_pcm_is_rejected(self):
        (self.directory / "reviewed.wav").write_bytes(self.wav[:-1] + b"\x01")
        with self.assertRaisesRegex(ValueError, "WAV bytes or PCM metadata"):
            audio.reuse_pcm(self.path, self.identity, UndecodableClip(),
                            (self.row, self.directory, self.receipt))
        with self.assertRaisesRegex(ValueError, "Truncated PCM"):
            audio.pcm_properties(self.wav[:-2], UndecodableClip())

    def test_new_decoder_cannot_change_original_format_or_overwrite_prior_pcm(self):
        wrong_format = SimpleNamespace(m_Name="new_sound", m_Frequency=44100,
                                       m_Channels=1, m_Length=4 / 44100,
                                       samples={"new_sound.wav": self.wav})
        with self.assertRaisesRegex(ValueError, "format differs"):
            audio.decode_new_pcm(self.identity, wrong_format, self.directory)
        self.assertEqual(len(list(self.directory.glob("*.wav"))), 1)
        target = self.directory / ("SF3PanguSource_reviewed_sound_" + "c" * 12 + ".wav")
        target.write_bytes(self.wav)
        with self.assertRaisesRegex(ValueError, "already exists"):
            audio.decode_new_pcm(self.identity, UndecodableClip(), self.directory)

    def test_partial_source_inputs_do_not_claim_complete_or_runtime_bound(self):
        rows = [{"status": "verified-local-pcm", "catalog": {"pathID": "123"},
                 "pcm": {"reusedExistingPCM": True}},
                {"status": "not-in-reviewed-catalog", "catalog": None}]
        result = audio.summarize([{}], [{}], rows)
        self.assertEqual(result["verifiedLocalPCM"], 1)
        self.assertEqual(result["indexedSoundIdentifiers"], 1)
        for key in ("allPlannedInputsAvailable", "sourceTimelineProjected", "runtimeAudioBindingCreated",
                    "panguModelCompleted", "productionPanguActivated"):
            self.assertIs(result[key], False)

    def test_missing_motion_retains_original_sound_and_weapon_armor_route(self):
        known = {"animation": "D19_Existing", "configurationSource": {"recordIndex": 0},
                 "motion": {"sourceFile": "known.bin"}, "rawMarkers": {"FirstFrame": None}, "soundMarkers": None}
        inventory = {"records": [known], "unrecovered": [{"animation": "D19_Back", "sourceFile": "missing.bin"}]}
        existing = [None] * len(audio.ANIMATION_FIELDS)
        existing[0:2] = ["D19_Existing", "known.bin"]
        missing = [None] * len(audio.ANIMATION_FIELDS)
        missing[0:2] = ["D19_Back", "missing.bin"]
        identifier = "set_d19/pangu_back_cast@Battle@WeaponAndArmor"
        missing[26] = [[2, [identifier], None, None]]
        result = audio.extend_motion_inventory(inventory, [existing, missing])
        self.assertIs(result["records"][0]["motionBytesRecovered"], True)
        self.assertIs(result["records"][1]["motionBytesRecovered"], False)
        self.assertIsNone(result["records"][1]["motion"]["sha256"])
        aliases, groups, identifiers = audio.marker_groups(result)
        self.assertEqual((len(aliases), len(groups), len(identifiers)), (1, 1, 1))
        self.assertEqual(groups[0]["sourceIdentifiers"], [identifier])
        self.assertEqual(groups[0]["sourceFrame"], 2)
        self.assertEqual(groups[0]["route"], "Sounds.Common")
        existing[26] = [[1, [identifier], None, None]]
        with self.assertRaisesRegex(ValueError, "Previously recovered alias differs"):
            audio.extend_motion_inventory(inventory, [existing, missing])

    def test_previous_preparation_reuse_requires_both_exact_snapshot_pins(self):
        plan, locations = self.directory / "plan.json", self.directory / "locations.json"
        plan.write_bytes(b"{}")
        locations.write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "prepared input plan differs"):
            audio.load_prepared_pcm(plan, locations, {self.path})
        with mock.patch.object(audio, "PRIOR_PLAN_SHA256", audio.sha(b"{}")):
            with self.assertRaisesRegex(ValueError, "locator receipt differs"):
                audio.load_prepared_pcm(plan, locations, {self.path})


if __name__ == "__main__":
    unittest.main()
