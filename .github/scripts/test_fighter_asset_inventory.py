import json
import tempfile
import unittest
from pathlib import Path
from fighter_asset_inventory import inspect


class FighterAssetInventoryTests(unittest.TestCase):
    def manifests(self, folder, *, remove=None, duplicate=False):
        a = {
            "version": 1,
            "files": [
                {"file": "Sun_Herald_Katana.glb"},
                {"file": "Liu_Legion_Hammers.glb"},
                {"file": "SF3_DistinctFighters.json"},
                {"file": "SF3FX_manifest.json"},
                {"file": "SF3WE_manifest.json"},
                {"file": "SF3FX_katanaHit_1.wav"},
            ],
            "parts": [{"file": "chunk"}],
        }
        if remove:
            a["files"] = [x for x in a["files"] if x["file"] != remove]
        if duplicate:
            a["files"].append(a["files"][0])
        b = {"version": 1, "assets": [
            {"file": name, "bytes": 100, "parts": [{"bytes": 120}]}
            for name in ("Sun_OriginalRig_ActionSet.glb", "Liu_OriginalRig_ActionSet.glb")
        ]}
        p, q = Path(folder) / "distinct.json", Path(folder) / "original.json"
        p.write_text(json.dumps(a))
        q.write_text(json.dumps(b))
        return p, q

    def test_inventory_is_metadata_only(self):
        with tempfile.TemporaryDirectory() as folder:
            p, q = self.manifests(folder)
            report = inspect(p, q)
            self.assertEqual(report["status"], "manifest_only")
            self.assertEqual(report["counts"]["characters"], 2)
            self.assertEqual(report["counts"]["original_rigs"], 2)

    def test_missing_character_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p, q = self.manifests(folder, remove="Liu_Legion_Hammers.glb")
            with self.assertRaises(ValueError):
                inspect(p, q)

    def test_duplicate_entries_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            p, q = self.manifests(folder, duplicate=True)
            with self.assertRaises(ValueError):
                inspect(p, q)


if __name__ == "__main__":
    unittest.main()
