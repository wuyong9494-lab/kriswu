"""Narrow append/staging regression gates; synthetic fixtures, no media reads."""
from copy import deepcopy
import base64
import gzip
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import append_cached_stun_motions as append
import stage_cached_stun_release as stage


def glb(document, binary):
    document = deepcopy(document)
    document["buffers"] = [dict(byteLength=len(binary))]
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    return struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(binary)) + \
        struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(binary), 0x004E4942) + binary


class CachedStunBindingTests(unittest.TestCase):
    def test_exact_new_animation_set_preserves_original_container_and_binary(self):
        old = dict(nodes=[dict(name="own-bone")], meshes=[dict(name="own-mesh")],
            accessors=[dict(synthetic=True)], bufferViews=[dict(synthetic=True)],
            animations=[dict(name="existing")])
        new = deepcopy(old)
        new["animations"].extend(dict(name=m["name"]) for m in append.MOTIONS)
        before, after = glb(old, b"old!"), glb(new, b"old!new!")
        append.validate_stun_append(before, after, 1)
        for mutation in ("node", "old_animation", "new_animation", "binary"):
            broken = deepcopy(new); binary = b"old!new!"
            if mutation == "node": broken["nodes"][0]["name"] = "borrowed-bone"
            elif mutation == "old_animation": broken["animations"][0]["name"] = "changed"
            elif mutation == "new_animation": broken["animations"][-1]["name"] = "unreviewed"
            else: binary = b"bad!new!"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                append.validate_stun_append(before, glb(broken, binary), 1)

    def test_dependent_manifests_change_only_exact_character_digests(self):
        original = {"characterSHA256": append.PROFILES["sun"]["characterSHA"],
            "motionProfiles": {"liu_hammers": append.PROFILES["liu"]["characterSHA"]},
            "sourceFrames": [0, 52, 60], "pcm": "unchanged.wav"}
        raw = json.dumps(original, separators=(",", ":")).encode()
        revised = stage.rebind_identity(raw, ("sun", "liu"))
        expected = deepcopy(original)
        expected["characterSHA256"] = stage.NEW["sun"]["sha256"]
        expected["motionProfiles"]["liu_hammers"] = stage.NEW["liu"]["sha256"]
        self.assertEqual(json.loads(revised), expected)
        compressed = stage.rebind_identity(gzip.compress(raw), ("sun", "liu"), compressed=True)
        self.assertEqual(gzip.decompress(compressed), revised)
        for invalid in (b"{}", raw + raw):
            with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
                stage.rebind_identity(invalid, ("sun",))
        with self.assertRaisesRegex(ValueError, "gzip bound"):
            stage.rebind_identity(gzip.compress(raw) + b"trailing", ("sun",), compressed=True)

    def test_catalog_append_retains_later_production_rules_and_old_fk(self):
        motions = [dict(name="synthetic_" + str(i), role="sourceStun" + str(i), frames=2,
            bytes=1, sha256=stage.digest(bytes([i]))) for i in range(3)]
        profiles, candidates = [], {}
        for key, pin in append.PROFILES.items():
            old = dict(id=pin["id"], sha256=pin["characterSHA"], bytes=10,
                bodyID="unchanged-" + key, roles={"idle": "current"}, combatRules={"current": True},
                comboLinks=["later-source-fix"], clips=[dict(name="current", tracks={"productionFK": i}) for i in range(pin["count"])])
            profiles.append(old)
            # Candidate intentionally has different old tracks and combos.
            candidate = deepcopy(old)
            candidate.update(sha256=stage.NEW[key]["sha256"], comboLinks=["obsolete-standalone"])
            candidate["clips"] = [dict(name="current", tracks={"obsoleteFK": 0}) for _ in range(pin["count"])]
            for i, motion in enumerate(motions):
                candidate["clips"].append(dict(**{k: motion[k] for k in ("name", "frames", "sha256")},
                    bundle=append.BUNDLE, sourceBytesBase64=base64.b64encode(bytes([i])).decode()))
            candidates[key] = candidate
        base = dict(profiles=profiles, sourceFramesPerSecond=None)
        frozen = deepcopy(base)
        with mock.patch.object(stage, "MOTIONS", motions):
            result = stage.append_catalog(base, candidates)
        self.assertEqual(base, frozen)
        for before, after in zip(profiles, result["profiles"]):
            self.assertEqual(after["clips"][:-3], before["clips"])
            self.assertEqual(after["comboLinks"], before["comboLinks"])
            self.assertEqual(after["combatRules"], before["combatRules"])
            self.assertEqual(after["bodyID"], before["bodyID"])

    def test_existing_outputs_fail_before_archive_or_private_resource_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with mock.patch.object(append, "cached_motions", side_effect=AssertionError("Unexpected archive read")):
                with self.assertRaisesRegex(ValueError, "must be new"):
                    append.append(SimpleNamespace(output=output))
            with mock.patch.object(stage, "real_directory", side_effect=AssertionError("Unexpected source read")):
                with self.assertRaisesRegex(ValueError, "must be new"):
                    stage.stage(SimpleNamespace(output=output))


if __name__ == "__main__":
    unittest.main()
