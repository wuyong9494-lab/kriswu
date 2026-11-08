import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import fighter_private_model as envelope
import fighter_sf3_assets as assets


class PersonalAssetStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "encrypted"
        self.source.mkdir()
        self.destination = Path(self.temp.name) / "output"
        self.clear = {"First.glb": b"synthetic first model", "Last.glb": b"synthetic scenery"}
        expected = {name: (len(data), assets.digest(data)) for name, data in self.clear.items()}
        self.enterContext(patch.object(assets, "EXPECTED", expected))
        self.enterContext(patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY="c7" * 32))
        self.manifest = {"version": 1, "assets": []}
        for name, data in self.clear.items():
            cipher = envelope.seal(data, "asset:" + name)
            parts = []
            for index, offset in enumerate(range(0, len(cipher), 37)):
                part = cipher[offset:offset + 37]
                filename = f"{name}.enc.{index:03}"
                (self.source / filename).write_bytes(part)
                parts.append(dict(file=filename, bytes=len(part), sha256=assets.digest(part)))
            self.manifest["assets"].append(dict(file=name, bytes=len(data),
                sha256=assets.digest(data), purpose="asset:" + name,
                cipher_sha256=assets.digest(cipher), parts=parts))
        self.write_manifest(self.manifest)

    def write_manifest(self, manifest):
        (self.source / "manifest.json").write_text(json.dumps(manifest))

    def test_stages_complete_verified_set(self):
        assets.stage(self.source, self.destination)
        self.assertEqual({p.name: p.read_bytes() for p in self.destination.iterdir()}, self.clear)

    def test_rejects_missing_reordered_redirected_or_wrong_purpose_parts(self):
        variants = []
        missing = copy.deepcopy(self.manifest); missing["assets"].pop(); variants.append(missing)
        reordered = copy.deepcopy(self.manifest)
        reordered["assets"][-1]["parts"].reverse(); variants.append(reordered)
        redirect = copy.deepcopy(self.manifest)
        redirect["assets"][-1]["parts"][0]["file"] = "../elsewhere"; variants.append(redirect)
        purpose = copy.deepcopy(self.manifest)
        purpose["assets"][-1]["purpose"] = "model"; variants.append(purpose)
        for manifest in variants:
            with self.subTest(manifest=manifest):
                self.write_manifest(manifest)
                with self.assertRaises(ValueError):
                    assets.stage(self.source, self.destination)
                self.assertFalse(self.destination.exists())

    def test_tampered_last_asset_never_partially_installs(self):
        row = self.manifest["assets"][-1]
        part = row["parts"][-1]
        path = self.source / part["file"]
        changed = bytearray(path.read_bytes()); changed[-1] ^= 1; path.write_bytes(changed)
        # Updating public checksums still cannot forge the authenticated envelope.
        part["sha256"] = assets.digest(changed)
        row["cipher_sha256"] = assets.digest(b"".join((self.source / p["file"]).read_bytes() for p in row["parts"]))
        self.write_manifest(self.manifest)
        with self.assertRaises(ValueError):
            assets.stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
