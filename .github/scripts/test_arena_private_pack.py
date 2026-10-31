import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest

import arena_private_pack as release

SOURCE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pack_builder", SOURCE / "scripts/assets/build_resource_pack.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PrivatePackReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "note.txt").write_bytes(b"synthetic test data")
        payload = self.root / "note.txt"
        manifest = {
            "schemaVersion": 1, "id": "synthetic", "title": "Synthetic", "sourceDescription": "Test data",
            "sourceSHA256": "0" * 64, "heroes": [], "themes": [], "music": [], "maps": [], "musicBindings": {},
            "files": [{"path": "note.txt", "kind": "notice", "bytes": payload.stat().st_size,
                       "sha256": builder.sha_file(payload)}],
        }
        header = self.root / "manifest.json"
        header.write_text(json.dumps(manifest))
        self.pack = self.root / release.PACK_NAME
        builder.build(header, self.root, self.pack)
        self.expected = {"id": "synthetic", "bytes": self.pack.stat().st_size, "sha256": builder.sha_file(self.pack)}

    def tearDown(self):
        self.temporary.cleanup()

    def testArchiveContainsExactVerifiedPayload(self):
        archive = self.root / "build.xcarchive"
        app = archive / "Products/Applications/ShiftReminder.app"
        app.mkdir(parents=True)
        shutil.copyfile(self.pack, app / release.PACK_NAME)
        report = release.archive(self.expected, SOURCE, archive)
        self.assertTrue(report["all_payload_hashes_verified"])
        self.assertNotIn("path", report)
        self.assertEqual(report["sha256"], self.expected["sha256"])
        (app / "duplicate").mkdir()
        shutil.copyfile(self.pack, app / "duplicate" / release.PACK_NAME)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            release.archive(self.expected, SOURCE, archive)

    def testEvenRehashedOuterFileCannotConcealBadInternalPayload(self):
        data = bytearray(self.pack.read_bytes())
        data[-1] ^= 1
        self.pack.write_bytes(data)
        expected = {**self.expected, "sha256": hashlib.sha256(data).hexdigest()}
        with self.assertRaises(AssertionError):
            release.verify(self.pack, expected, SOURCE)

    def testPackInsideWidgetCannotPassMainAppValidation(self):
        archive = self.root / "misplaced.xcarchive"
        widget = archive / "Products/Applications/ShiftReminder.app/PlugIns/ShiftWidget.appex"
        widget.mkdir(parents=True)
        shutil.copyfile(self.pack, widget / release.PACK_NAME)
        with self.assertRaisesRegex(ValueError, "bundle root"):
            release.archive(self.expected, SOURCE, archive)

    def testChangedPackOrIdentityCannotReachUpload(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            release.verify(self.pack, {**self.expected, "sha256": "0" * 64}, SOURCE)
        with self.assertRaisesRegex(ValueError, "identity"):
            release.verify(self.pack, {**self.expected, "id": "another-pack"}, SOURCE)

    def testRequestCannotContainPrivateURL(self):
        self.assertIsNone(release.specification({}))
        self.assertEqual(release.specification({"private_resource_pack": self.expected}), self.expected)
        with self.assertRaises(ValueError):
            release.specification({"private_resource_pack": {**self.expected, "url": "https://private.invalid/key"}})

    def testResourceSourceVersionCannotOmitPackMetadata(self):
        source = self.root / "source"
        (source / "App").mkdir(parents=True)
        (source / "App/Info.plist").write_bytes(plistlib.dumps({"ArenaResourcePackRequiredForPromotion": True}))
        with self.assertRaisesRegex(ValueError, "requires private_resource_pack"):
            release.required_specification({}, source)
        self.assertEqual(release.required_specification({"private_resource_pack": self.expected}, source), self.expected)


if __name__ == "__main__":
    unittest.main()
