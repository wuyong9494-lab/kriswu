import copy
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import fighter_private_model as envelope
import fighter_sf3_distinct as assets


class DistinctFighterStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "encrypted"
        self.source.mkdir()
        self.destination = Path(self.temp.name) / "staged"
        self.enterContext(patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY="e3" * 32))
        self.original = assets.verified_assets
        self.files = {"Sun_Herald_Katana.glb": b"synthetic model", "SF3UI_fist.png": b"synthetic UI"}
        self.build(self.files)
        self.enterContext(patch.object(assets, "verified_assets", self.verify))

    def build(self, files):
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as z:
            for name, data in files.items():
                z.writestr(name, data)
        clear = out.getvalue()
        self.identity = (len(clear), assets.digest(clear), len(files))
        cipher = envelope.seal(clear, assets.PURPOSE)
        parts = []
        for index, offset in enumerate(range(0, len(cipher), 128)):
            data = cipher[offset:offset + 128]
            name = f"distinct.pack.enc.{index:03}"
            (self.source / name).write_bytes(data)
            parts.append(dict(file=name, bytes=len(data), sha256=assets.digest(data)))
        self.manifest = dict(version=1, purpose=assets.PURPOSE, bytes=len(clear), sha256=assets.digest(clear),
                             cipher_sha256=assets.digest(cipher), parts=parts,
                             files=[dict(file=k, bytes=len(v), sha256=assets.digest(v)) for k, v in files.items()])
        self.write_manifest()

    def write_manifest(self):
        (self.source / "manifest.json").write_text(json.dumps(self.manifest))

    def verify(self, source):
        return self.original(source, *self.identity)

    def test_complete_authenticated_set_stages_without_altering_existing_assets(self):
        self.destination.mkdir()
        existing = self.destination / "Existing.glb"
        existing.write_bytes(b"keep existing verified model")
        assets.stage(self.source, self.destination)
        for name, data in self.files.items():
            self.assertEqual((self.destination / name).read_bytes(), data)
        self.assertEqual(existing.read_bytes(), b"keep existing verified model")

    def test_last_chunk_tampering_cannot_be_hidden_by_rewriting_public_hashes(self):
        part = self.manifest["parts"][-1]
        path = self.source / part["file"]
        data = bytearray(path.read_bytes()); data[-1] ^= 1; path.write_bytes(data)
        part["sha256"] = assets.digest(data)
        self.manifest["cipher_sha256"] = assets.digest(b"".join((self.source / p["file"]).read_bytes() for p in self.manifest["parts"]))
        self.write_manifest()
        with self.assertRaises(ValueError):
            assets.stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_wrong_identity_reordered_parts_and_manifest_redirection_are_rejected(self):
        baseline = copy.deepcopy(self.manifest)
        variants = []
        wrong = copy.deepcopy(baseline); wrong["purpose"] = "model"; variants.append(wrong)
        wrong = copy.deepcopy(baseline); wrong["parts"].reverse(); variants.append(wrong)
        wrong = copy.deepcopy(baseline); wrong["parts"][0]["file"] = "../outside"; variants.append(wrong)
        for variant in variants:
            self.manifest = variant; self.write_manifest()
            with self.assertRaises(ValueError):
                assets.stage(self.source, self.destination)
            self.assertFalse(self.destination.exists())

    def test_authenticated_unsafe_zip_and_symbolic_destination_are_still_rejected(self):
        self.build({"../SF3UI_fist.png": b"synthetic traversal"})
        with self.assertRaises(ValueError):
            assets.stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())
        self.build(self.files)
        self.destination.mkdir()
        outside = Path(self.temp.name) / "outside"
        outside.write_bytes(b"untouched")
        (self.destination / "SF3UI_fist.png").symlink_to(outside)
        with self.assertRaises(ValueError):
            assets.stage(self.source, self.destination)
        self.assertEqual(outside.read_bytes(), b"untouched")
        self.assertFalse((self.destination / "Sun_Herald_Katana.glb").exists())


if __name__ == "__main__":
    unittest.main()
