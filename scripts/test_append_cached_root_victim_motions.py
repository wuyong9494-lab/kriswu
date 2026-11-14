#!/usr/bin/env python3
"""Small importer gates with synthetic bytes and rigs; no private media IO."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock

import numpy as np

import append_cached_root_victim_motions as importer


def fixture():
    document = dict(nodes=[dict(name="pelvis"), dict(name="hand_l")])
    bindings = [dict(name="pelvis", targetNode=0, sourceID=0),
                dict(name="hand_l", targetNode=1, sourceID=1)]
    masses = dict(characterSHA256="synthetic-liu-identity", bones=[
        dict(name="pelvis", targetNode=0, mass=3.0),
        dict(name="hand_l", targetNode=1, mass=1.0)])
    return document, bindings, masses


class CachedRootVictimImporterTests(unittest.TestCase):
    def test_checked_rig_accepts_only_matching_own_nodes_and_source_ids(self):
        document, bindings, masses = fixture()
        before = deepcopy((document, bindings, masses))
        names, bones = importer.checked_rig(document, bindings, masses, "synthetic-liu-identity")
        self.assertEqual(names, {"pelvis": 0, "hand_l": 1})
        self.assertEqual(bones, {0: "pelvis", 1: "hand_l"})
        self.assertEqual((document, bindings, masses), before)
        for mutation in ("duplicate_name", "duplicate_source_id", "wrong_target", "boolean_target"):
            document, bindings, masses = fixture()
            if mutation == "duplicate_name": bindings[1]["name"] = "pelvis"
            elif mutation == "duplicate_source_id": bindings[1]["sourceID"] = 0
            elif mutation == "wrong_target": bindings[1]["targetNode"] = 0
            else: bindings[1]["targetNode"] = True
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                importer.checked_rig(document, bindings, masses, "synthetic-liu-identity")

    def test_mass_identity_and_bone_binding_cannot_be_borrowed_from_another_rig(self):
        for mutation in ("character", "bone", "target", "duplicate"):
            document, bindings, masses = fixture()
            if mutation == "character": masses["characterSHA256"] = "synthetic-sun-identity"
            elif mutation == "bone": masses["bones"][1]["name"] = "another_hand"
            elif mutation == "target": masses["bones"][1]["targetNode"] = 0
            else: masses["bones"].append(deepcopy(masses["bones"][0]))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                importer.checked_rig(document, bindings, masses, "synthetic-liu-identity")

    def test_nonfinite_negative_and_zero_total_mass_are_rejected(self):
        for bad in (float("nan"), float("inf"), -1.0, 0.0):
            document, bindings, masses = fixture()
            for row in masses["bones"]: row["mass"] = bad
            with self.subTest(mass=bad), self.assertRaises(ValueError):
                importer.checked_rig(document, bindings, masses, "synthetic-liu-identity")

    def test_center_uses_supplied_own_worlds_and_retains_native_float_order(self):
        world = [np.eye(4), np.eye(4)]
        world[0][:3, 3] = [2, 4, 6]
        world[1][:3, 3] = [6, 8, 10]
        masses = [dict(targetNode=0, mass=3.0), dict(targetNode=1, mass=1.0)]
        # Own source weighted position is (3,5,7); RIGHT maps it to(-7,5,3).
        np.testing.assert_array_equal(importer.weighted_center(world, masses), [-7, 5, 3])
        # Recovered Float traversal drops the middle1 at 2**24. A double
        # accumulator or reordering would silently change the saved source COM.
        world = [np.eye(4) for _ in range(3)]
        for matrix, x in zip(world, (2**24, 1, -(2**24))): matrix[0, 3] = x
        masses = [dict(targetNode=i, mass=1.0) for i in range(3)]
        np.testing.assert_array_equal(importer.weighted_center(world, masses), [0, 0, 0])

    def test_pins_check_actual_bytes_bounds_and_symlink_free_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "synthetic.bytes"
            path.write_bytes(b"original")
            pin = importer.digest(b"original")
            self.assertEqual(importer.pinned(path, pin, 32), b"original")
            with self.assertRaisesRegex(ValueError, "identity changed"):
                importer.pinned(path, importer.digest(b"different"), 32)
            with self.assertRaisesRegex(ValueError, "bounded regular"):
                importer.pinned(path, pin, 3)
            link = root / "linked.bytes"
            link.symlink_to(path)
            with self.assertRaisesRegex(ValueError, "symbolic"):
                importer.pinned(link, pin, 32)
            self.assertEqual(path.read_bytes(), b"original")

    def test_existing_output_is_rejected_before_any_private_source_read(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "existing"
            output.mkdir()
            sentinel = output / "keep.txt"
            sentinel.write_bytes(b"unchanged")
            with mock.patch.object(importer, "pinned", side_effect=AssertionError("Unexpected source IO")):
                with self.assertRaisesRegex(ValueError, "must be new"):
                    importer.append(SimpleNamespace(output=output))
            self.assertEqual(sentinel.read_bytes(), b"unchanged")


if __name__ == "__main__":
    unittest.main()
