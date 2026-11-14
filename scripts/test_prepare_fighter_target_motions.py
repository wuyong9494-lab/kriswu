"""Synthetic corruption/decoder/privacy tests; no game assets or network needed."""
import copy
import gzip
import io
import json
from pathlib import Path
import stat
import struct
import tempfile
import unittest
import warnings
from unittest.mock import patch
from zipfile import ZipFile, ZipInfo

import prepare_fighter_target_motions as target


def raw_motion(frames=2, ids=(1, 7), expanded=False):
    packed = 8 + 2 * len(ids) + 12 * frames * len(ids)
    declared = 8 + 2 * len(ids) + (28 if expanded else 12) * frames * len(ids)
    header = struct.pack("<QHQQ", target.MAGIC, 2, declared, declared)
    # Source-frame translation and approximately identity quaternion with w omitted.
    transform = struct.pack("<eeeHHH", 1.0, -2.0, 0.5, (3 << 13) | 4096, 8192, 16384)
    array = struct.pack("<II", frames, len(ids)) + struct.pack("<" + "H" * len(ids), *ids)
    array += transform * frames * len(ids)
    assert len(array) == packed
    return header + array + array


class TargetMotionPreparationTests(unittest.TestCase):
    def test_decodes_known_translation_quaternion_and_preserves_frames_bones(self):
        arrays = target.decode_motion(raw_motion())
        self.assertEqual(len(arrays), 2)
        for item in arrays:
            self.assertEqual(item["frameCount"], 2)
            self.assertEqual(item["boneIDs"], [1, 7])
            self.assertEqual(item["positions"][1][1], [1.0, -2.0, 0.5])
            for component in item["rotations"][1][1][:3]:
                self.assertAlmostEqual(component, 0.0, delta=0.00005)
            self.assertAlmostEqual(item["rotations"][1][1][3], 1.0, places=7)
        self.assertEqual(arrays, target.decode_motion(raw_motion(expanded=True)))

    def test_rejects_truncation_dimension_overflow_and_trailing_bytes(self):
        valid = raw_motion()
        enormous = bytearray(valid)
        struct.pack_into("<I", enormous, 26, 2**32 - 1)
        for raw in (b"", valid[:25], valid[:-1], valid + b"event?", bytes(enormous), b"\0" * 8 + valid[8:]):
            with self.subTest(size=len(raw)), self.assertRaises(target.PreparationError):
                target.decode_motion(raw)

    def test_rejects_duplicate_bones_nonfinite_translation_and_invalid_quaternion(self):
        duplicate = raw_motion(ids=(1, 1))
        nonfinite = bytearray(raw_motion())
        struct.pack_into("<e", nonfinite, 38, float("inf"))
        invalid_rotation = bytearray(raw_motion())
        struct.pack_into("<HHH", invalid_rotation, 44, 0, 0, 0)
        for raw in (duplicate, bytes(nonfinite), bytes(invalid_rotation)):
            with self.assertRaises(target.PreparationError):
                target.decode_motion(raw)

    def test_rejects_zip_traversal_duplicate_members_symlink_and_oversized_metadata(self):
        unsafe = ["../private.bytes", "/private.bytes", "safe\\..\\private.bytes"]
        for name in unsafe:
            with self.subTest(name=name):
                data = io.BytesIO()
                with ZipFile(data, "w") as archive:
                    archive.writestr(name, b"x")
                with ZipFile(data) as archive, self.assertRaises(target.PreparationError):
                    target.checked_members(archive)
        data = io.BytesIO()
        info = ZipInfo("symlink")
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with ZipFile(data, "w") as archive:
            archive.writestr(info, b"outside")
        with ZipFile(data) as archive, self.assertRaises(target.PreparationError):
            target.checked_members(archive)
        data = io.BytesIO()
        with warnings.catch_warnings(), ZipFile(data, "w") as archive:
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("duplicate", b"first")
            archive.writestr("duplicate", b"second")
        with ZipFile(data) as archive, self.assertRaises(target.PreparationError):
            target.checked_members(archive)
        data = io.BytesIO()
        with ZipFile(data, "w") as archive:
            archive.writestr("bounded", b"two")
        with ZipFile(data) as archive, patch.object(target, "MAX_MEMBER_BYTES", 2), \
             self.assertRaises(target.PreparationError):
            target.checked_members(archive)
        with self.assertRaises(target.PreparationError):
            target.parse_json('{"frames": 1, "frames": 2}')

    def fixture(self, root, corrupt=None):
        raw = raw_motion()
        bundle = b"synthetic container, decoded through a test reader"
        row = {"name": "ninjato_slash_1", "bundle": "fixture.bin", "path_id": 2**60 + 9,
               "bytes": len(raw), "sha256": target.digest(raw), "arrays": 2,
               "frames": 2, "bone_ids": [1, 7], "playback_fps": None}
        if corrupt:
            corrupt(row)
        pin = {"target": "synthetic", "bundle": "fixture.bin", "sha256": target.digest(bundle),
               "bytes": len(bundle), "prefix": "ninjato_", "count": 1}
        archive_path = root / "fixture.zip"
        with ZipFile(archive_path, "w") as archive:
            archive.writestr("bundles/fixture.bin", bundle)
            archive.writestr(target.MOTION_CATALOG, json.dumps({"error_count": 0, "motions": [row]}))
            archive.writestr(target.BUNDLE_CATALOG, json.dumps({"paths": [{"path": "assets/ninjato"}]}))
        assets = {2**60 + 9: ("ninjato_slash_1", raw)}
        return archive_path, pin, assets

    def test_real_decoder_stages_only_private_transforms_and_emits_no_raw_public_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, pin, assets = self.fixture(root)
            private = root / "private"
            output = root / "public.json"
            with patch.object(target, "ARCHIVE_SHA256", target.file_digest(archive)), \
                 patch.object(target, "TARGETS", (pin,)), \
                 patch.object(target, "read_text_assets", return_value=assets):
                result = target.prepare(archive, private, output)
            self.assertEqual(result["verifiedMotionCount"], 1)
            self.assertEqual(result["decodedArrayCount"], 2)
            self.assertIsNone(result["sourceFramesPerSecond"])
            self.assertFalse(result["contactWindowsRecovered"])
            self.assertFalse(result["gameRulesRecovered"])
            self.assertFalse(result["permitsGameplayEnablement"])
            self.assertEqual(result["pangu"]["status"], "unmapped")
            self.assertEqual(result["targets"][0]["motions"][0]["sourcePathID"], str(2**60 + 9))
            public = output.read_text()
            for field in ('"positions"', '"rotations"', 'sourceBytesBase64', '"damage"', '"contactWindows"'):
                self.assertNotIn(field, public)
            self.assertEqual((private / "raw/ninjato_slash_1.bytes").read_bytes(), raw_motion())
            decoded = json.loads(gzip.decompress((private / "decoded/ninjato_slash_1.json.gz").read_bytes()))
            self.assertEqual(decoded["arrays"][0]["positions"][0][0], [1, -2, 0.5])
            self.assertEqual(stat.S_IMODE(private.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((private / "raw/ninjato_slash_1.bytes").stat().st_mode), 0o600)

    def test_wrong_archive_bundle_or_motion_hash_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, pin, assets = self.fixture(root)
            with self.assertRaises(target.PreparationError):
                target.inspect_archive(archive)
            wrong = copy.deepcopy(pin)
            wrong["sha256"] = "0" * 64
            with patch.object(target, "ARCHIVE_SHA256", target.file_digest(archive)), \
                 patch.object(target, "TARGETS", (wrong,)), \
                 self.assertRaises(target.PreparationError):
                target.inspect_archive(archive)
            assets[2**60 + 9] = ("ninjato_slash_1", b"corrupted")
            with patch.object(target, "ARCHIVE_SHA256", target.file_digest(archive)), \
                 patch.object(target, "TARGETS", (pin,)), \
                 patch.object(target, "read_text_assets", return_value=assets), \
                 self.assertRaises(target.PreparationError):
                target.inspect_archive(archive)

    def test_changed_frames_or_asserted_fps_cannot_be_silently_accepted(self):
        for field, value in (("frames", 3), ("playback_fps", 30)):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                archive, pin, assets = self.fixture(Path(directory), lambda row: row.update({field: value}))
                with patch.object(target, "ARCHIVE_SHA256", target.file_digest(archive)), \
                     patch.object(target, "TARGETS", (pin,)), \
                     patch.object(target, "read_text_assets", return_value=assets), \
                     self.assertRaises(target.PreparationError):
                    target.inspect_archive(archive)

    def test_private_output_inside_repo_or_existing_directory_is_rejected(self):
        with self.assertRaises(target.PreparationError):
            target.ensure_private_destination(target.REPOSITORY / "temporary-private")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(target.PreparationError):
                target.ensure_private_destination(root)
            link = root / "link"
            link.symlink_to(root, target_is_directory=True)
            with self.assertRaises(target.PreparationError):
                target.ensure_private_destination(link / "output")


if __name__ == "__main__":
    unittest.main()
