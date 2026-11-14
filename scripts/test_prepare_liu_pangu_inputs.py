#!/usr/bin/env python3
"""Small contract tests. Synthetic byte strings are not original D19 assets."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

import prepare_liu_pangu_inputs as prep


class PanguInputPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.identity = prep.reviewed_document(Path(prep.__file__).with_name(prep.IDENTITY_NAME), prep.IDENTITY_NAME)
        self.motions = prep.reviewed_document(Path(prep.__file__).with_name(prep.MOTIONS_NAME), prep.MOTIONS_NAME)

    def synthetic_motion(self, data=b"synthetic object, not source media"):
        return {"sourceFile": "common/example.bin", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    def candidate_bundle(self, model="Top100/wpn__twohanded_axe_01_02"):
        data = b"synthetic bundle; matching metadata does not prove original identity"
        row = {"file": "synthetic.bin", "bytes": len(data), "sha256": prep.digest(data),
               "bundle_names": [], "paths": [{"path": "assets/gamedata/resources/content/items/models/" + model + "/model.prefab"}]}
        (self.root / row["file"]).write_bytes(data)
        return row

    def test_pinned_inventory_cannot_be_replaced_by_self_authored_json(self):
        altered = deepcopy(self.identity)
        altered["items"][0]["model"] = "Top100/wpn__hammers_01_01"
        path = self.root / "inventory.json"
        path.write_text(json.dumps(altered))
        with self.assertRaisesRegex(ValueError, "reviewed pin"):
            prep.prepare(self.root, identity_path=path)

    def test_exact_equipment_guard_rejects_legacy_hammer_and_old_axe(self):
        for model in ["Top100/wpn__hammers_01_01", "Top100/wpn__twohanded_axe_01_01"]:
            altered = deepcopy(self.identity)
            altered["items"][0]["model"] = model
            with self.assertRaisesRegex(ValueError, "relabeled"):
                prep.validate_documents(altered, self.motions)

    def test_partial_plan_preserves_every_alias_and_deduplicates_source_inputs(self):
        plan = prep.prepare(self.root)
        self.assertEqual(plan["counts"]["recoveredMotionObjects"], 10)
        self.assertEqual(plan["counts"]["recoveredAliases"], 17)
        self.assertEqual(plan["counts"]["unrecoveredAliases"], 12)
        self.assertEqual(plan["counts"]["totalAliasMappings"], 29)
        self.assertEqual(len(plan["motionObjects"]), 10)
        self.assertEqual(sum(len(r["aliases"]) for r in plan["motionObjects"]), 17)
        self.assertEqual(len({r["animation"] for r in plan["aliasAssemblyTasks"]}), 29)
        missing = [r for r in plan["aliasAssemblyTasks"] if r["status"] == "unrecovered-original-motion"]
        self.assertTrue(all(r["sourceObjectSHA256"] is None for r in missing))
        self.assertFalse(plan["inputCoverageComplete"])
        self.assertFalse(plan["releaseActivationAllowed"])

    def test_verified_defaults_preserve_source_coordinate_and_unknown_speed(self):
        rows = {r["animation"]: r for r in prep.prepare(self.root)["aliasAssemblyTasks"]}
        wind = rows["D19_Upper_Wind_Blade_Model_Attack"]
        self.assertIsNone(wind["rawMarkers"]["FirstFrame"])
        self.assertEqual(wind["frameParametersWithVerifiedDefaults"]["FirstFrame"], 0)
        self.assertEqual(wind["frameParametersWithVerifiedDefaults"]["EndFrame"], 9)
        self.assertEqual(wind["frameParametersWithVerifiedDefaults"]["SelfEndFrame"], 0)
        blink = rows["D19_Back_Blink_End"]
        self.assertEqual(blink["frameParametersWithVerifiedDefaults"]["EndFrame"], 2147483647)
        self.assertEqual(blink["soundIdentifiersAndFrames"][0]["Frame"], 17)
        self.assertIsNone(blink["sourceFPS"])
        self.assertIsNone(blink["animationSpeed"])

    def test_verified_bytes_are_required_and_corruption_is_not_downgraded_to_missing(self):
        data = b"synthetic object, not source media"
        motion = self.synthetic_motion(data)
        self.assertIsNone(prep.locate_motion(self.root, motion))
        path = self.root / "example.bytes"
        path.write_bytes(data)
        self.assertEqual(prep.locate_motion(self.root, motion), "example.bytes")
        path.write_bytes(b"x" * len(data))
        with self.assertRaisesRegex(ValueError, "disagree"):
            prep.locate_motion(self.root, motion)

    def test_symlink_input_and_path_escape_are_rejected(self):
        outside = self.root / "outside.bytes"
        outside.write_bytes(b"synthetic object, not source media")
        (self.root / "example.bytes").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "Symbolic-link"):
            prep.locate_motion(self.root, self.synthetic_motion())
        for name in ("../example.bytes", "/tmp/example.bytes", "x\\example.bytes"):
            with self.assertRaises(ValueError):
                prep.local_file(self.root, name)

    def test_self_reported_model_path_and_valid_local_hash_remain_unverified(self):
        row = self.candidate_bundle()
        mapped = prep.equipment_mapping(self.identity, [row], "0" * 64, self.root)
        candidate = mapped[0]["candidates"][0]
        self.assertTrue(candidate["bytesVerified"])
        self.assertFalse(candidate["originalIdentityVerified"])
        self.assertEqual(mapped[0]["status"], "candidate-unverified")
        self.assertEqual(candidate["identityEvidence"], "unreviewed-catalog-candidate")

    def test_even_claimed_trusted_catalog_requires_reviewed_item_receipt_and_container_path(self):
        row = self.candidate_bundle()
        pin = next(r["sha256"] for r in self.identity["sourceMembers"] if r["member"].endswith("catalog.jsonl"))
        mapped = prep.equipment_mapping(self.identity, [row], pin, self.root)
        self.assertFalse(mapped[0]["candidates"][0]["originalIdentityVerified"])
        # Test the join contract independently; this synthetic dictionary never
        # passes prepare()'s reviewed-document pin and is not release evidence.
        test_identity = deepcopy(self.identity)
        test_identity["items"][0]["androidMatches"] = [{k: row[k] for k in ("file", "bytes", "sha256")}]
        row["paths"] = []
        row["bundle_names"] = ["resources-content-items-models-top100-wpn__twohanded_axe_01_02"]
        mapped = prep.equipment_mapping(test_identity, [row], pin, self.root)
        self.assertFalse(mapped[0]["candidates"][0]["originalIdentityVerified"])

    def test_old_weapon_candidate_cannot_satisfy_exact_model_match(self):
        for model in ["Top100/wpn__hammers_01_01", "Top100/wpn__twohanded_axe_01_01"]:
            row = self.candidate_bundle(model)
            mapped = prep.equipment_mapping(self.identity, [row], None, self.root)
            self.assertTrue(all(r["status"] == "missing-exact-model" and r["candidates"] == [] for r in mapped))

    def test_duplicate_alias_and_forged_completeness_fail_closed(self):
        altered = deepcopy(self.motions)
        altered["unrecovered"] = []
        with self.assertRaisesRegex(ValueError, "count mismatch"):
            prep.validate_documents(self.identity, altered)
        altered = deepcopy(self.motions)
        altered["unrecovered"][0]["animation"] = altered["records"][0]["animation"]
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            prep.validate_documents(self.identity, altered)

    def test_json_duplicates_and_nonfinite_values_are_not_accepted(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}'):
            with self.assertRaises(ValueError):
                prep.parse_json(raw)

    def test_cli_partial_exit_preserves_plan_without_runtime_artifact_or_absolute_paths(self):
        output = self.root / "inputs.json"
        command = [sys.executable, prep.__file__, "--motion-root", str(self.root), "--output", str(output)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(json.loads(result.stdout)["prepared"])
        text = output.read_text()
        self.assertNotIn(str(self.root), text)
        self.assertFalse(json.loads(text)["releaseActivationAllowed"])
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertFalse((self.root / "SF3_FighterRelease.json").exists())
        first = output.read_bytes()
        again = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(again.returncode, 1)
        self.assertEqual(output.read_bytes(), first)
        with self.assertRaisesRegex(ValueError, "runtime release"):
            prep.write_plan(self.root / "SF3_FighterRelease.json", {})


if __name__ == "__main__":
    unittest.main()
