#!/usr/bin/env python3
"""Focused synthetic checks for the source floor-fall compiler's safety boundaries.

No source media, private keys, network, Swift builds, or existing releases are
needed. The separate local compile validates the actual pinned original bytes.
"""
import copy
import io
import json
from pathlib import Path
import stat
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import source_floorfall_audio as floorfall


def source_node(value):
    if isinstance(value, list):
        return [source_node(x) for x in value]
    if isinstance(value, str) and value.startswith("enum"):
        return dict(kind="Enum", value=int(value[4:]))
    if isinstance(value, str) and value.startswith("op"):
        return dict(kind="RpnOperator", value=int(value[2:]))
    if isinstance(value, dict):
        key, payload = next(iter(value.items()))
        if len(key) > 1 and key[0] in "af" and key[1:].isdigit():
            return dict(kind="NamedData" if key[0] == "a" else "RpnFunction", id=int(key[1:]), value=source_node(payload))
        return dict(kind="ConditionData", fields=[None if key == "expr" else key,
                                                  source_node(payload) if key == "expr" else None,
                                                  source_node(payload) if key != "expr" else None])
    return value


def source_rule():
    def group(name):
        return {"expr": [{"f26": [{"f74": ["enum65537"]}]}, name, "op22"]}
    events = [{"a13": ["enum65537", None]}, {"a18": ["enum65537", "Floorfall"]}]
    conditions = [{"Not": [group("THROW_FALL"), group("PHYSICS_NO_SFX")]},
                  {"Or": [group("PHYSICS"), group("FALL")]}]
    trigger = dict(kind="TriggerData", fields=[None, None, None, source_node(events), source_node(conditions),
                                               source_node([{"a111": [floorfall.SOUND_VALUES, None, None]}])])
    sets = [None] * 99
    sets[97] = dict(kind="TriggerSetData", fields=["EFFECT__Dust_Down", [trigger]])
    sets[98] = dict(kind="TriggerSetData", fields=["EFFECT__Dust_Down_From_Throw",
        [dict(kind="TriggerData", fields=[None, None, None, source_node(events), None, []])]])
    return sets


def records_and_profile():
    names = ["h_hit_head_fall", "h17_root_spike_passive_end", "ninjato_stance", "s_ninjato_slash_passive"]
    groups = [["HIT", "FALL"], ["PASSIVE", "FALL"], ["STANCE_START_ROUND"], ["FALL", "THROW_FALL"]]
    records = []
    for selection, clip, tags in zip(floorfall.SOURCE_SELECTIONS, names, groups):
        entry, index, alias, accepted = selection
        interval = ["Floorfall", None, 20, 20] + [None] * 24
        records.append(dict(sourceEntry=entry, sourceSHA256="source fixture", sourceRecordIndex=index,
                            expectedAccepted=accepted, configuration=dict(Animation=alias, FileName=clip + ".bin",
                            Groups=tags, FirstFrame=None, MidFrames=None, Looped=None, Intervals=[interval])))
    profile = dict(id="sun_triad", sha256=floorfall.CHARACTER_SHA, clips=[dict(name=name, frames=frames, sha256=sha)
        for name, (frames, sha) in floorfall.MOTION_PINS.items()])
    return records, profile


def base_binding():
    return dict(version=2, profileID="sun_triad", characterSHA256=floorfall.CHARACTER_SHA,
                sourceConfigurationSHA256=floorfall.SOURCE_CONFIGURATION_SHA, context=dict(gender="Male", floor="Stone"),
                evidence=["Synthetic existing provenance, retained unchanged."],
                files=[dict(name="Original.wav", bytes=3, sha256=floorfall.digest(b"old"))],
                audio={}, cues=[], markers=[dict(id="old", clip="old", sourceFrame=1, files=["Original.wav"])],
                motionProfiles={"liu_hammers": "b" * 64})


class SourceFloorfallTests(unittest.TestCase):
    def test_original_alternatives_array_order_and_null_position_are_retained(self):
        rule = floorfall.rule_from_sources(source_rule())
        self.assertEqual(rule["sounds"], floorfall.SOUND_VALUES)
        self.assertEqual(len(rule["sounds"]), 7)
        self.assertFalse(rule["loop"])
        self.assertIsNone(rule["position"])
        self.assertEqual(rule["positionResolution"], "pending_native_default")
        self.assertEqual(rule["physicsFloorHit"], "not_integrated")

    def test_removed_throw_exclusion_is_rejected(self):
        sets = source_rule()
        sets[97]["fields"][1][0]["fields"][4] = []
        with self.assertRaisesRegex(ValueError, "group guards"):
            floorfall.rule_from_sources(sets)

    def test_unreviewed_sound_or_spatial_override_is_rejected(self):
        for replacement in ([floorfall.SOUND_VALUES[::-1], None, None],
                            [floorfall.SOUND_VALUES, None, [0, 0]]):
            with self.subTest(replacement=replacement):
                sets = source_rule()
                sets[97]["fields"][1][0]["fields"][5] = source_node([{"a111": replacement}])
                with self.assertRaisesRegex(ValueError, "sounds or playback flags"):
                    floorfall.rule_from_sources(sets)

    def test_throw_fall_cannot_inherit_the_common_body_sound(self):
        sets = source_rule()
        sets[98]["fields"][1][0]["fields"][5] = source_node([{"a111": [floorfall.SOUND_VALUES, None, None]}])
        with self.assertRaisesRegex(ValueError, "separate semantics"):
            floorfall.rule_from_sources(sets)

    def test_two_exact_intervals_bind_at_38_and_stance_and_throw_are_excluded(self):
        records, profile = records_and_profile()
        markers, accepted, excluded = floorfall.compile_markers(records, profile, ["Body.wav"])
        self.assertEqual([x["playbackTick"] for x in accepted], [38, 38])
        self.assertEqual([x["sourceFrame"] for x in markers], [20, 20])
        self.assertTrue(all(x["clock"] == "intervalStart" for x in markers))
        self.assertEqual({x["clip"] for x in markers}, set(floorfall.MOTION_PINS))
        self.assertEqual([x["reason"] for x in excluded], ["No PHYSICS/FALL group", "THROW_FALL excluded"])

    def test_physics_no_sfx_appearing_on_accepted_clip_fails_closed(self):
        records, profile = records_and_profile()
        records[0]["configuration"]["Groups"].append("PHYSICS_NO_SFX")
        with self.assertRaisesRegex(ValueError, "acceptance changed"):
            floorfall.compile_markers(records, profile, ["Body.wav"])

    def test_changed_motion_hash_duration_crop_or_interval_requires_review(self):
        for field in ("hash", "duration", "crop", "interval"):
            with self.subTest(field=field):
                records, profile = records_and_profile()
                if field == "hash":
                    profile["clips"][0]["sha256"] = "c" * 64
                elif field == "duration":
                    profile["clips"][0]["playbackTicks"] = 37
                elif field == "crop":
                    records[0]["configuration"]["FirstFrame"] = 1
                else:
                    records[0]["configuration"]["Intervals"][0][2] = 21
                with self.assertRaises(ValueError):
                    floorfall.compile_markers(records, profile, ["Body.wav"])

    def test_candidate_only_appends_files_and_markers_and_preserves_old_objects(self):
        base = base_binding()
        before = copy.deepcopy(base)
        markers = [dict(id="floorfall", clip="h_hit_head_fall", sourceFrame=20,
                        clock="intervalStart", context="Common", files=["Body.wav", "Body.wav"])]
        sounds = [dict(name="Body.wav", bytes=3, sha256=floorfall.digest(b"new"))]
        candidate = floorfall.candidate_manifest(base, markers, sounds)
        self.assertEqual(base, before)
        self.assertEqual(candidate["markers"][:-1], before["markers"])
        self.assertEqual(candidate["files"][:-1], before["files"])
        for key in set(base) - {"files", "markers"}:
            self.assertEqual(candidate[key], before[key])
        self.assertEqual(candidate["markers"][-1]["files"], ["Body.wav", "Body.wav"])

    def test_duplicate_marker_or_unreferenced_media_is_rejected(self):
        base = base_binding()
        with self.assertRaisesRegex(ValueError, "already exists"):
            floorfall.candidate_manifest(base, [copy.deepcopy(base["markers"][0])], [])
        with self.assertRaisesRegex(ValueError, "unreferenced"):
            floorfall.candidate_manifest(base, [], [dict(name="Body.wav", bytes=3, sha256="d" * 64)])

    def test_private_candidate_is_new_0700_with_0600_files_and_keeps_input_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = root / "old"
            old.mkdir()
            (old / "Original.wav").write_bytes(b"old")
            original_sha = floorfall.digest((old / "Original.wav").read_bytes())
            media = floorfall.existing_media(base_binding(), old)
            target = root / "candidate"
            floorfall.write_candidate(target, base_binding(), media, {"synthetic": True})
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
            self.assertTrue(all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in target.iterdir()))
            self.assertEqual(floorfall.digest((old / "Original.wav").read_bytes()), original_sha)
            self.assertEqual((target / "Original.wav").read_bytes(), b"old")
            with self.assertRaisesRegex(ValueError, "new and outside"):
                floorfall.write_candidate(target, base_binding(), media, {})

    def test_symlinks_and_corrupt_existing_pcm_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "original").write_bytes(b"old")
            (root / "Original.wav").symlink_to(root / "original")
            with self.assertRaisesRegex(ValueError, "non-symlink"):
                floorfall.existing_media(base_binding(), root)
            (root / "Original.wav").unlink()
            (root / "Original.wav").write_bytes(b"bad")
            with self.assertRaisesRegex(ValueError, "identity differs"):
                floorfall.existing_media(base_binding(), root)

    def test_repeated_successful_output_is_rejected_before_any_source_read_or_decode(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "existing-candidate"
            target.mkdir()
            # No other arguments: touching even the first source input would
            # fail with AttributeError instead of the intended early refusal.
            with patch.object(floorfall, "decode_sounds") as decode, patch.object(floorfall, "existing_media") as media:
                with self.assertRaisesRegex(ValueError, "new and outside"):
                    floorfall.compile_candidate(SimpleNamespace(output=target))
                decode.assert_not_called()
                media.assert_not_called()

    def test_repository_output_is_rejected_before_decode(self):
        target = floorfall.REPOSITORY / "synthetic-uncreated-floorfall-candidate"
        self.assertFalse(target.exists())
        with patch.object(floorfall, "decode_sounds") as decode, patch.object(floorfall, "existing_media") as media:
            with self.assertRaisesRegex(ValueError, "new and outside"):
                floorfall.compile_candidate(SimpleNamespace(output=target))
            decode.assert_not_called()
            media.assert_not_called()
        self.assertFalse(target.exists())

    def assert_early_base_refusal(self, document):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "base.json"
            manifest.write_bytes(floorfall.json_bytes(document))
            args = SimpleNamespace(output=root / "candidate", audio_manifest=manifest)
            with patch.object(floorfall, "decode_sounds") as decode, patch.object(floorfall, "existing_media") as media:
                with self.assertRaises(ValueError):
                    floorfall.compile_candidate(args)
                decode.assert_not_called()
                media.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_invalid_base_identity_is_rejected_before_source_read_or_decode(self):
        for key, value in (("version", 1), ("profileID", "liu_hammers"),
                           ("characterSHA256", "a" * 64), ("sourceConfigurationSHA256", "a" * 64)):
            with self.subTest(key=key):
                document = base_binding()
                document[key] = value
                self.assert_early_base_refusal(document)

    def test_base_counts_total_bytes_duplicates_and_reference_closure_fail_before_media_io(self):
        for issue in ("file_count", "total_bytes", "marker_count", "duplicates", "references"):
            with self.subTest(issue=issue):
                document = base_binding()
                if issue in ("file_count", "total_bytes"):
                    count, size = (97, 1) if issue == "file_count" else (9, 4_000_000)
                    document["files"] = [dict(name=f"Synthetic_{i}.wav", bytes=size, sha256="a" * 64) for i in range(count)]
                    document["markers"] = [dict(id=f"synthetic_{i}", clip="test", sourceFrame=1, files=[f["name"]])
                                           for i, f in enumerate(document["files"])]
                elif issue == "marker_count":
                    document["markers"] = [dict(id=f"synthetic_{i}", clip="test", sourceFrame=1, files=["Original.wav"])
                                           for i in range(1025)]
                elif issue == "duplicates":
                    document["files"].append(copy.deepcopy(document["files"][0]))
                else:
                    document["markers"][0]["files"] = ["Missing.wav"]
                self.assert_early_base_refusal(document)

    def test_malformed_explicit_playback_ticks_do_not_fall_back_to_default(self):
        for ticks in (0, False, "", -1, "116", 116.0):
            with self.subTest(ticks=ticks):
                records, profile = records_and_profile()
                profile["clips"][0]["playbackTicks"] = ticks
                with self.assertRaisesRegex(ValueError, "motion duration changed"):
                    floorfall.compile_markers(records, profile, ["Body.wav"])

    def test_raw_source_pin_is_checked_before_the_storage_parser(self):
        with tempfile.TemporaryDirectory() as directory:
            nested = io.BytesIO()
            with ZipFile(nested, "w") as archive:
                archive.writestr("lock_923.bytes", b"x" * floorfall.SOURCE_PINS["lock_923.bytes"][0])
            path = Path(directory) / "splits.zip"
            with ZipFile(path, "w") as outer:
                outer.writestr("splits/split_battle_triggers.bytes", nested.getvalue())
            with self.assertRaisesRegex(ValueError, "Raw source member pin differs"):
                floorfall.source_inputs(path)

    def test_typed_storage_consumes_all_bytes_and_bounds_references(self):
        # Empty synthetic storage with a null root, no pools and seven empty banks.
        payload = b"\x00" + struct.pack("<I", 0) + struct.pack("<I", 0) * len(floorfall.POOL_LAYOUT)
        payload += struct.pack("<III", 0, 0, 7) + struct.pack("<I", 0) * 7
        storage = floorfall.Storage(payload)
        self.assertIsNone(storage.value(storage.root))
        with self.assertRaisesRegex(ValueError, "trailing"):
            floorfall.Storage(payload + b"x")
        with self.assertRaisesRegex(ValueError, "pool reference"):
            storage.value(6 << 27)
        with self.assertRaisesRegex(ValueError, "handle reference"):
            storage.value(9 << 27)


if __name__ == "__main__":
    unittest.main()
