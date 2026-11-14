#!/usr/bin/env python3
"""Small assembly-boundary checks; fixture bytes are not original audio assets."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import stat
import tempfile
import unittest
from unittest import mock

import stage_h17_floorfall_release as stage
from source_floorfall_audio import SOURCE_CONFIGURATION_SHA


def bindings():
    files = [dict(name=f"Existing_{i:03}.wav", bytes=3, sha256=stage.digest(b"old")) for i in range(88)]
    base = dict(version=2, profileID="sun_triad", characterSHA256=stage.CHARACTER_SHA,
                sourceConfigurationSHA256=SOURCE_CONFIGURATION_SHA,
                context=dict(gender="Male", floor="Stone"), evidence=["Synthetic contract fixture, not source media"],
                files=files, cues=[], audio={"ninjatoHit": [r["name"] for r in files[:32]],
                    "ninjatoBlock": [r["name"] for r in files[32:64]],
                    "ninjatoWhoosh": [r["name"] for r in files[64:]]},
                markers=[dict(id=f"existing_{i}", clip="synthetic", sourceFrame=1,
                              files=[files[i % 88]["name"]]) for i in range(112)])
    candidate = deepcopy(base)
    new = [dict(name=f"Added_{i}.wav", bytes=3, sha256=stage.digest(b"new")) for i in range(7)]
    candidate["files"] += new
    for clip in stage.MOTION_PINS:
        candidate["markers"].append(dict(id="source_floorfall_923_97_" + clip, clip=clip,
            sourceFrame=20, clock="intervalStart", context="Common", files=[r["name"] for r in new]))
    release = dict(schemaVersion=2, id="h17-source-recovery-20261114", panguAudio=None,
                   triadAudio=dict(name=stage.AUDIO_NAME, bytes=1, sha256="a" * 64),
                   catalog={"unchanged": True}, triadMorph={"unchanged": "liu_hammers"},
                   profiles=[dict(id="sun_triad", characterSHA256=stage.CHARACTER_SHA,
                       motions=[dict(clip=clip, frames=frames, sourceSHA256=sha,
                                     sourceFramesPerSecond=30, exportFramesPerSecond=30)
                                for clip, (frames, sha) in stage.MOTION_PINS.items()]),
                             dict(id="liu_hammers", characterSHA256="b" * 64, motions=[])])
    return base, candidate, release


class FloorfallReleaseStageTests(unittest.TestCase):
    def test_caller_authored_package_cannot_replace_the_reviewed_pin(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "self-authored.json"
            path.write_bytes(stage.encoded(dict(releaseSHA256=stage.BASE_RELEASE_SHA)))
            with self.assertRaisesRegex(ValueError, "pin differs"):
                stage.pinned_json(path, stage.BASE_PACK_SHA, 2_000_000)

    def test_exact_append_retains_all_existing_bindings_and_variant_order(self):
        base, candidate, release = bindings()
        before = deepcopy((base, candidate, release))
        added = stage.audio_delta(base, candidate, release)
        self.assertEqual(len(added), 7)
        self.assertEqual([r["name"] for r in added], candidate["markers"][-1]["files"])
        self.assertEqual((base, candidate, release), before)

    def test_existing_binding_or_pcm_change_cannot_hide_in_the_append(self):
        for changed in ("context", "pcm", "marker", "cues"):
            base, candidate, release = bindings()
            if changed == "context":
                candidate["context"]["floor"] = "Wood"
            elif changed == "pcm":
                candidate["files"][0]["sha256"] = "c" * 64
            elif changed == "marker":
                candidate["markers"][0]["sourceFrame"] = 2
            else:
                candidate["cues"] = [dict(id="extra", files=[candidate["files"][0]["name"]])]
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                stage.audio_delta(base, candidate, release)

    def test_marker_clock_variant_order_and_release_motion_pin_cannot_drift(self):
        for changed in ("clock", "variants", "motion", "fps"):
            base, candidate, release = bindings()
            if changed == "clock":
                candidate["markers"][-1]["clock"] = "soundFrame"
            elif changed == "variants":
                candidate["markers"][-1]["files"].reverse()
            elif changed == "motion":
                release["profiles"][0]["motions"][0]["sourceSHA256"] = "e" * 64
            else:
                release["profiles"][0]["motions"][0]["sourceFramesPerSecond"] = None
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                stage.audio_delta(base, candidate, release)

    def test_release_update_preserves_catalog_characters_morph_and_pangu_boundary(self):
        _, _, base = bindings()
        before = deepcopy(base)
        audio = stage.record(stage.AUDIO_NAME, b"synthetic binding metadata")
        target = stage.revised_release(base, audio)
        self.assertEqual(base, before)
        self.assertEqual({k for k in target if target[k] != base[k]}, {"id", "triadAudio"})
        self.assertEqual(target["id"], stage.TARGET_ID)
        self.assertIsNone(target["panguAudio"])
        self.assertEqual(target["profiles"][1]["id"], "liu_hammers")

    def test_actual_bytes_and_regular_file_requirement_are_enforced(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row = stage.record("Synthetic.wav", b"old")
            path = root / row["name"]
            path.write_bytes(b"bad")
            with self.assertRaisesRegex(ValueError, "reviewed inventory"):
                stage.checked_file(root, row)
            path.unlink()
            (root / "real.wav").write_bytes(b"old")
            path.symlink_to(root / "real.wav")
            with self.assertRaises(OSError):
                stage.checked_file(root, row)
            with self.assertRaisesRegex(ValueError, "basename"):
                stage.checked_file(root, dict(row, name="../real.wav"))

    def test_repeated_output_is_rejected_before_source_io(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "existing"
            output.mkdir()
            with mock.patch.object(stage, "pinned_json", side_effect=AssertionError("Unexpected source IO")):
                with self.assertRaisesRegex(ValueError, "must be new"):
                    stage.stage(SimpleNamespace(output=output))

    def test_output_cannot_modify_repository_or_source_directories(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            stage.fresh_output(stage.REPOSITORY / "not-created-by-test")
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)
            with self.assertRaisesRegex(ValueError, "outside"):
                stage.fresh_output(source / "inside-input", (source,))
            link = source / "linked"
            link.symlink_to(source, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symbolic"):
                stage.fresh_output(link / "new")

    def test_private_writes_cannot_overwrite_old_files(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "record.json"
            stage.write_private(path, b"original")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                stage.write_private(path, b"replacement")
            self.assertEqual(path.read_bytes(), b"original")

    def test_inventory_receipt_mismatch_and_ambiguous_json_are_rejected(self):
        rows = [dict(file=f"Synthetic_{i}.bin", bytes=1, sha256="a" * 64) for i in range(295)]
        replacements = ["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"]
        pack = dict(files=rows, replacements=replacements, releaseSHA256=stage.BASE_RELEASE_SHA)
        receipt = dict(files=[dict(name=r["file"], bytes=r["bytes"], sha256=r["sha256"]) for r in rows],
                       release=dict(sha256=stage.BASE_RELEASE_SHA), replacements=replacements)
        receipt["files"][0]["sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "does not match"):
            stage.base_inventory(pack, receipt)
        for raw in (b'{"pin":1,"pin":2}', b'{"value":NaN}'):
            with self.assertRaises(ValueError):
                stage.parse_json(raw)


if __name__ == "__main__":
    unittest.main()
