"""Bounded synthetic append/binding checks; no private media or conversion."""
import argparse
import base64
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import stage_h17_shared_root_release as subject


def glb(document, binary):
    raw = subject.encoded(document).rstrip(b"\n")
    raw += b" " * (-len(raw) % 4)
    binary += b"\0" * (-len(binary) % 4)
    return (struct.pack("<III", 0x46546C67, 2, 28 + len(raw) + len(binary))
            + struct.pack("<II", len(raw), 0x4E4F534A) + raw
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def synthetic_inputs():
    """Small format fixtures, never a representation of original resource quality."""
    old_document = dict(asset={"version": "2.0"}, buffers=[{"byteLength": 32}],
        nodes=[{"name": "untouched-node"}], skins=[{"joints": [0]}], meshes=[{"name": "untouched-mesh"}],
        animations=[{"name": f"old_{i}", "channels": [], "samplers": []} for i in range(56)],
        accessors=[{"count": 1}], bufferViews=[{"buffer": 0, "byteLength": 32}])
    new_document = deepcopy(old_document)
    new_document["buffers"][0]["byteLength"] = 48
    new_document["animations"].extend({"name": c["name"], "channels": [], "samplers": []} for c in subject.CLIPS)
    new_document["accessors"].append({"count": 2})
    new_document["bufferViews"].append({"buffer": 0, "byteOffset": 32, "byteLength": 16})
    old_model = glb(old_document, bytes(range(32)))
    new_model = glb(new_document, bytes(range(32)) + b"ROOT" * 4)
    clips, pins = [], []
    for original in subject.CLIPS:
        source = ("fixture-" + original["name"]).encode()
        tracks = dict(samplesPerSourceFrame=2, hurtCapsules=[{"id": i} for i in range(15)], root=[0, 0, 0])
        pin = dict(original, bytes=len(source), sha256=subject.digest(source), tracksSHA256=subject.digest(subject.encoded(tracks)))
        pins.append(pin)
        clips.append(dict(name=pin["name"], frames=pin["frames"], sha256=pin["sha256"], bundle=subject.SOURCE_BUNDLE,
            sourceBytesBase64=base64.b64encode(source).decode(), sourceArrayCount=2, sourceBoneIDs=list(range(58)), tracks=tracks))
    old_catalog = dict(schemaVersion=1, coordinateSpace="preserved", provenance={"same": True}, profiles=[
        dict(id="sun_triad", clips=[{"name": "h17-original"}], rules={"preserved": True}),
        dict(id="liu_hammers", bytes=10_438_952, sha256=subject.digest(old_model), bodyID="arm__str_03",
             weaponID="wpn__hammers_01_01", roles={"idle": "old_0"}, comboLinks=[{"from": "old_0", "to": "old_1"}],
             ordinaryThrows=[{"source": "kept"}], clips=[{"name": f"old_{i}", "tracks": {"finalCatalog": i}} for i in range(56)])])
    audio = dict(version=2, profileID="sun_triad", characterSHA256="a" * 64,
        motionProfiles={"liu_hammers": subject.digest(old_model)}, files=[{"name": f"old_{i}.wav"} for i in range(95)],
        markers=[{"id": f"old_{i}", "clip": "unchanged"} for i in range(113)])
    audio["markers"].append(dict(id="source_floorfall_923_97_h17_root_spike_passive_end",
        clip=subject.CLIPS[-1]["name"], sourceFrame=20, clock="intervalStart", context="Common", files=subject.FLOORFALL_NAMES))
    morph = dict(version=2, ownerProfileID="sun_triad", ownerCharacterSHA256="a" * 64,
        targetProfileID="liu_hammers", targetCharacterSHA256=subject.digest(old_model), mask={"unchanged": [1, 2]})
    trails = dict(version=3, profiles=[{"id": "sun_triad", "same": True}], legacy=dict(profileIDs=["liu_hammers"],
        manifest={"name": "retained.json", "sha256": "b" * 64}, rebindings=[dict(id="liu_hammers", mode="appendSourceAnimations",
        fromSHA256="c" * 64, toSHA256=subject.digest(old_model))]))
    release = dict(schemaVersion=2, id="h17-source-floorfall-20261114", panguAudio=None,
        catalog=subject.record(subject.CATALOG_NAME, subject.encoded(old_catalog)),
        triadAudio=subject.record(subject.AUDIO_NAME, subject.encoded(audio)),
        triadMorph=subject.record(subject.MORPH_NAME, subject.encoded(morph)),
        sourceTrails=subject.record(subject.TRAILS_NAME, subject.encoded(trails)),
        triadSummons={"untouched": True}, triadEffects={"untouched": True}, profiles=[
            {"id": "sun_triad", "characterSHA256": "a" * 64, "motions": [{"clip": "keep-h17"}], "materials": ["keep"]},
            {"id": "liu_hammers", "characterSHA256": subject.digest(old_model), "bodyID": "arm__str_03",
             "weaponID": "wpn__hammers_01_01", "motions": [{"clip": f"old_{i}"} for i in range(56)],
             "evidence": "retained", "sourceVersion": "retained", "skinRoots": ["keep"]}])
    return dict(old_model=old_model, new_model=new_model, old_document=old_document, new_document=new_document,
                clips=clips, pins=pins, catalog=old_catalog, audio=audio, morph=morph, trails=trails, release=release)


def fixture_pins(stack, fixture):
    values = dict(CLIPS=fixture["pins"], OLD_CHARACTER_SHA=subject.digest(fixture["old_model"]),
        CHARACTER_SHA=subject.digest(fixture["new_model"]), NEW_CHARACTER_BYTES=len(fixture["new_model"]),
        CATALOG_SHA=subject.digest(subject.encoded(fixture["catalog"])),
        MORPH_SHA=subject.digest(subject.encoded(fixture["morph"])), TRAILS_SHA=subject.digest(subject.encoded(fixture["trails"])))
    for name, value in values.items():
        stack.enter_context(patch.object(subject, name, value))


class SharedRootStageTests(unittest.TestCase):
    def setUp(self):
        self.fixture = synthetic_inputs()
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        fixture_pins(self.stack, self.fixture)

    def test_glb_round_trip_preserves_old_bin_and_56_animations(self):
        old, new = self.fixture["old_model"], self.fixture["new_model"]
        patch_raw, receipt = subject.glb_patch(old, new)
        self.assertEqual(subject.rebuild_glb(old, patch_raw), new)
        self.assertEqual(receipt["retainedBINBytes"], 32)
        self.assertEqual(receipt["appendedBINBytes"], 16)
        self.assertEqual(len(patch_raw), 24 + receipt["jsonChunkBytes"] + 16)
        self.assertEqual(subject.glb_chunks(new)[0]["animations"][:56], self.fixture["old_document"]["animations"])

    def test_glb_append_rejects_changed_old_binary(self):
        bad = glb(self.fixture["new_document"], b"X" + bytes(range(1, 32)) + b"ROOT" * 4)
        with self.assertRaises(ValueError):
            subject.glb_patch(self.fixture["old_model"], bad)

    def test_glb_append_rejects_model_skin_or_old_animation_change(self):
        for key in ("meshes", "skins", "animations"):
            with self.subTest(key=key):
                bad = deepcopy(self.fixture["new_document"])
                bad[key][0]["injected"] = True
                with self.assertRaises(ValueError):
                    subject.glb_patch(self.fixture["old_model"], glb(bad, bytes(range(32)) + b"ROOT" * 4))

    def test_glb_patch_cannot_trim_prefix_or_accept_truncated_suffix(self):
        raw, _ = subject.glb_patch(self.fixture["old_model"], self.fixture["new_model"])
        changed = bytearray(raw)
        struct.pack_into("<I", changed, 8, 28)
        for value in (bytes(changed), raw[:-4], raw + b"JUNK"):
            with self.subTest(size=len(value)), self.assertRaises(ValueError):
                subject.rebuild_glb(self.fixture["old_model"], value)

    def test_catalog_append_preserves_actual_old_tracks_rules_and_h17(self):
        original = deepcopy(self.fixture["catalog"])
        result = subject.append_catalog(self.fixture["catalog"], self.fixture["clips"])
        old, new = original["profiles"][1], result["profiles"][1]
        self.assertEqual(self.fixture["catalog"], original)
        self.assertEqual(result["profiles"][0], original["profiles"][0])
        self.assertEqual(new["clips"][:56], old["clips"])
        self.assertEqual(len(new["clips"]), 59)
        self.assertEqual({k: v for k, v in new.items() if k not in ("clips", "bytes", "sha256")},
                         {k: v for k, v in old.items() if k not in ("clips", "bytes", "sha256")})

    def test_catalog_patch_round_trip_and_original_pin_gate(self):
        old = subject.encoded(self.fixture["catalog"])
        raw, target = subject.catalog_patch(old, self.fixture["clips"])
        self.assertEqual(subject.rebuild_catalog(old, raw), target)
        with self.assertRaises(ValueError):
            subject.rebuild_catalog(old + b" ", raw)
        document = subject.parse_json(raw)
        document["target"]["sha256"] = "f" * 64
        with self.assertRaises(ValueError):
            subject.rebuild_catalog(old, subject.encoded(document))

    def test_catalog_patch_rejects_extra_mutation_fields(self):
        old = subject.encoded(self.fixture["catalog"])
        raw, _ = subject.catalog_patch(old, self.fixture["clips"])
        document = subject.parse_json(raw)
        document["replaceOldClips"] = []
        with self.assertRaises(ValueError):
            subject.rebuild_catalog(old, subject.encoded(document))

    def test_new_clip_source_track_and_bone_identity_are_verified(self):
        for field in ("sourceBytesBase64", "tracks", "frames", "sourceBoneIDs"):
            bad = deepcopy(self.fixture["clips"])
            bad[0][field] = {"sourceBytesBase64": "AAAA", "tracks": {}, "frames": 999, "sourceBoneIDs": []}[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                subject.validate_new_clips(bad)

    def test_audio_keeps_114_markers_and_adds_explicit_liu_interval_marker(self):
        original = deepcopy(self.fixture["audio"])
        result = subject.revised_audio(self.fixture["audio"])
        self.assertEqual(self.fixture["audio"], original)
        self.assertEqual(result["markers"][:114], original["markers"])
        self.assertEqual(result["files"], original["files"])
        self.assertEqual(result["motionProfiles"], {"liu_hammers": subject.CHARACTER_SHA})
        marker = result["markers"][-1]
        self.assertEqual((marker["profileID"], marker["clip"], marker["clock"], marker["sourceFrame"], marker["context"]),
                         ("liu_hammers", "h17_root_spike_passive_end", "intervalStart", 20, "Common"))
        self.assertEqual(2 * (marker["sourceFrame"] - 1), 38)
        self.assertEqual(marker["files"], subject.FLOORFALL_NAMES)

    def test_audio_rejects_changed_source_event_or_reordered_sound_variants(self):
        for field, value in (("clock", "stance"), ("sourceFrame", 19), ("files", list(reversed(subject.FLOORFALL_NAMES)))):
            bad = deepcopy(self.fixture["audio"])
            bad["markers"][-1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                subject.revised_audio(bad)

    def test_morph_and_trails_preserve_encoding_and_every_other_field(self):
        for name, transform in (("morph", subject.revised_morph), ("trails", subject.revised_trails)):
            old = subject.encoded(self.fixture[name])
            result = subject.rebind_json_raw(old, subject.digest(old), transform)
            with self.subTest(name=name):
                self.assertEqual(result, old.replace(subject.OLD_CHARACTER_SHA.encode(), subject.CHARACTER_SHA.encode(), 1))
                self.assertEqual(len(result), len(old))
                self.assertEqual(subject.parse_json(result), transform(self.fixture[name]))

    def test_binding_rebind_rejects_extra_old_hash_occurrence_or_other_target(self):
        bad = deepcopy(self.fixture["morph"])
        bad["unrelated"] = subject.OLD_CHARACTER_SHA
        raw = subject.encoded(bad)
        with self.assertRaises(ValueError):
            subject.rebind_json_raw(raw, subject.digest(raw), subject.revised_morph)
        bad = deepcopy(self.fixture["trails"])
        bad["legacy"]["rebindings"][0]["id"] = "sun_triad"
        with self.assertRaises(ValueError):
            subject.revised_trails(bad)

    def test_release_updates_all_four_refs_and_retains_profiles_and_missing_pangu(self):
        rows = [subject.record(n, b"new-binding") for n in
                (subject.CATALOG_NAME, subject.AUDIO_NAME, subject.MORPH_NAME, subject.TRAILS_NAME)]
        original = deepcopy(self.fixture["release"])
        result = subject.revised_release(self.fixture["release"], *rows)
        self.assertEqual(self.fixture["release"], original)
        self.assertEqual(result["profiles"][0], original["profiles"][0])
        self.assertIsNone(result["panguAudio"])
        for key, row in zip(("catalog", "triadAudio", "triadMorph", "sourceTrails"), rows):
            self.assertEqual(result[key], row)
        self.assertEqual(result["profiles"][1]["motions"][:56], original["profiles"][1]["motions"])
        self.assertEqual(len(result["profiles"][1]["motions"]), 59)
        self.assertEqual(result["profiles"][1]["weaponID"], "wpn__hammers_01_01")
        self.assertEqual(result["profiles"][1]["bodyID"], "arm__str_03")
        self.assertEqual(result["profiles"][1]["evidence"], "retained")

    def test_existing_output_is_rejected_before_any_input_load(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(subject, "real_directory") as inputs:
            with self.assertRaises(ValueError):
                subject.stage(argparse.Namespace(output=Path(directory)))
            inputs.assert_not_called()

    def test_symlink_parent_and_repository_output_fail_before_input_load(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "real").mkdir()
            (root / "alias").symlink_to(root / "real", target_is_directory=True)
            for output in (root / "alias" / "result", subject.ROOT / "never-create-private-test"):
                with self.subTest(output=output.name), patch.object(subject, "real_directory") as inputs:
                    with self.assertRaises(ValueError):
                        subject.stage(argparse.Namespace(output=output))
                    inputs.assert_not_called()


if __name__ == "__main__":
    unittest.main()
