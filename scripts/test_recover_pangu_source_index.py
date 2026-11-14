#!/usr/bin/env python3
"""Small synthetic regressions; no network, game execution or real asset conversion."""
import gzip
import io
import json
from pathlib import Path
import stat
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import recover_pangu_source_index as source


def vi(value):
    value &= (1 << 64) - 1
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    return bytes(result + bytes([value]))


def field(number, value):
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return vi(number * 8 + 2) + vi(len(value)) + value
    return vi(number * 8) + vi(value)


def archive(key="fixture", name="fixture", assets=(), dependencies=()):
    body = field(2, 100) + field(4, "opaque-hash") + field(5, 1) + field(10, name)
    body += b"".join(field(8, asset) for asset in assets)
    body += b"".join(field(9, item) for item in dependencies)
    return field(1, field(1, key) + field(2, body))


class RecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scripts = Path(__file__).parent
        cls.specs = source.targets(
            source.load_json(scripts / "pangu_source_motion_inventory_20261114.json", source.MOTION_SHA),
            source.load_json(scripts / "pangu_source_identity_20261114.json", source.EQUIPMENT_SHA))
        cls.motion = next(x for x in cls.specs if x["kind"] == "motion")

    def test_actual_descriptor_shape_preserves_signed_int64_paths(self):
        payload = archive() + field(2, field(1, -7) + field(2, "source/path"))
        result = source.parse_bconfig(payload)
        self.assertEqual(result["paths"], {-7: "source/path"})
        self.assertEqual(result["archives"]["fixture"]["realHash"], "opaque-hash")

    def test_old_string_key_interpretation_is_rejected(self):
        with self.assertRaises(ValueError):
            source.parse_bconfig(archive() + field(2, field(1, "not-an-int64") + field(2, "path")))

    def test_duplicate_archive_or_path_entries_are_rejected(self):
        item = field(2, field(1, 1) + field(2, "path"))
        for value in (archive() + archive(), archive() + item + item):
            with self.subTest(value=len(value)), self.assertRaises(ValueError):
                source.parse_bconfig(value)

    def test_truncation_overflow_and_unexpected_wire_are_rejected(self):
        for value in (b"\x0a\x05x", b"\x08" + b"\xff" * 10, b"\x0d0000", b"\x00"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                source.wire(value)

    def test_wrong_archive_boolean_or_negative_size_is_rejected(self):
        for value in (field(5, 2), field(2, -1)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                source.parse_archive(value)

    def test_dedicated_motion_paths_match_exactly(self):
        expected = self.motion["id"]
        self.assertEqual(source.matching_targets(self.motion["exactPaths"][1].upper(), self.specs), [expected])
        self.assertEqual(source.matching_targets(self.motion["exactPaths"][1] + ".bak", self.specs), [])
        self.assertEqual(source.motion_names(Path(expected).stem, self.specs), [expected])

    def test_existing_hammers_and_ordinary_axes_do_not_match(self):
        for name in ("axes_attack_01", "liu_hammers", "content/items/models/Top100/wpn__axe_01/mesh"):
            self.assertEqual(source.matching_targets(name, self.specs), [])
            self.assertEqual(source.motion_names(name, self.specs), [])

    def test_equipment_requires_exact_prefix_boundary(self):
        spec = next(x for x in self.specs if x["id"] == "WPN_TWOHANDEDAXE_02")
        self.assertEqual(source.matching_targets(spec["prefixes"][0] + "mesh.asset", self.specs), [spec["id"]])
        self.assertEqual(source.matching_targets(spec["prefixes"][0][:-1] + "other/mesh", self.specs), [])

    def test_dependency_cycles_are_closed_once(self):
        index = source.parse_bconfig(archive("a", "A", dependencies=["B"]) + archive("b", "B", dependencies=["a"]))
        self.assertEqual(source.dependency_closure(index, ["a"]), (["a", "b"], []))

    def test_unresolved_dependencies_remain_explicit(self):
        index = source.parse_bconfig(archive("a", "A", dependencies=["missing", "duplicate"]) +
                                     archive("b", "duplicate") + archive("c", "duplicate"))
        self.assertEqual(source.dependency_closure(index, ["a"]), (["a"], ["duplicate", "missing"]))

    def test_path_map_does_not_invent_archive_ownership(self):
        value = archive() + field(2, field(1, 1) + field(2, self.motion["exactPaths"][0]))
        result = source.index_matches(source.parse_bconfig(value), self.specs)
        self.assertEqual(result["matches"], {})
        self.assertEqual(result["pathMapEntries"], 1)

    def test_metadata_url_uses_only_actual_typed_values(self):
        result = source.metadata_url({"platforms": {"iOS": 17}, "baseUrl": "https://example.test/actual"}, "iOS")
        self.assertEqual(result, "https://example.test/actual/iOS-17.zip")

    def test_invalid_metadata_cannot_generate_a_route(self):
        cases = [
            {"platforms": {"iOS": True}, "baseUrl": "https://example.test"},
            {"platforms": {"iOS": "17"}, "baseUrl": "https://example.test"},
            {"platforms": {"iOS": -1}, "baseUrl": "https://example.test"},
            {"platforms": {"iOS": 1}, "baseUrl": "https://user:password@example.test"},
            {"platforms": {"iOS": 1}, "baseUrl": "https://example.test/path?token=fixture"},
            {"platforms": {"iOS": 1}, "baseUrl": "http://example.test"},
            {"platforms": {"iOS": 1}, "baseUrl": "https://example.test/../other"},
        ]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                source.metadata_url(value, "iOS")

    def test_json_duplicate_fields_are_not_an_index(self):
        self.assertIsNone(source.sniff_index(b'{"platforms":{},"platforms":{},"baseUrl":"https://example.test"}'))

    def test_gzip_wrapper_and_empty_payload(self):
        self.assertEqual(source.sniff_index(gzip.compress(archive()))["wrapper"], "gzip")
        self.assertIsNone(source.sniff_index(gzip.compress(b"")))
        with patch.object(source, "MAX_INDEX", 100), self.assertRaises(ValueError):
            source.sniff_index(gzip.compress(b"x" * 101))

    def test_private_outputs_are_new_and_reject_symlink_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = source.private_output(root / "private")
            source.write_private(output / "receipt.json", b"{}")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((output / "receipt.json").stat().st_mode), 0o600)
            with self.assertRaises(ValueError):
                source.private_output(output)
            (root / "link").symlink_to(output, target_is_directory=True)
            with self.assertRaises(ValueError):
                source.private_output(root / "link" / "child")

    def test_original_content_type_finds_opaque_named_textasset(self):
        with tempfile.TemporaryDirectory() as temporary:
            obj = SimpleNamespace(type=SimpleNamespace(name="TextAsset"), path_id=7,
                                  read=lambda: SimpleNamespace(m_Name="opaque123", m_Script=archive()))
            module = SimpleNamespace(config=SimpleNamespace(), load=lambda data: SimpleNamespace(container={}, objects=[obj]))
            scanner = source.Scan(self.specs, Path(temporary))
            with patch.dict(sys.modules, {"UnityPy": module}):
                scanner.container(b"UnityFS\x00fixture", "opaque.bin")
            self.assertEqual(scanner.report["typedTextAssets"], 1)
            self.assertEqual(scanner.report["indexes"][0]["kind"], "BConfigData")

    def test_serialized_header_does_not_require_assets_suffix(self):
        payload = struct.pack(">4I", 5, 64, 21, 32) + bytes(48)
        self.assertTrue(source.serialized_header(payload))
        self.assertTrue(source.supported_header(payload[:48], 64))
        self.assertFalse(source.serialized_header(b"other" * 15))

    def test_corrupt_unity_container_is_recorded_without_crashing_scan(self):
        with tempfile.TemporaryDirectory() as temporary:
            def failed(_):
                raise RuntimeError("untrusted content never appears in receipt")
            scanner = source.Scan(self.specs, Path(temporary))
            module = SimpleNamespace(config=SimpleNamespace(), load=failed)
            with patch.dict(sys.modules, {"UnityPy": module}):
                scanner.container(b"UnityFS\x00fixture", "opaque.bin")
            self.assertEqual(scanner.report["errors"], [{"source": "opaque.bin", "kind": "RuntimeError"}])

    def test_zip_member_content_and_duplicate_hash_are_used(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "original.zip"
            with ZipFile(path, "w") as zipped:
                zipped.writestr("cache/unknown.bin", archive())
                zipped.writestr("cache/also-unknown.bytes", archive())
            scanner = source.Scan(self.specs, root)
            scanner.archive(path)
            self.assertEqual(len(scanner.report["indexes"]), 1)
            self.assertEqual(scanner.report["duplicateContainersReused"], 1)

    def test_zip_wrapped_index_uses_member_bytes_not_filename(self):
        with tempfile.TemporaryDirectory() as temporary:
            blob = io.BytesIO()
            with ZipFile(blob, "w") as zipped:
                zipped.writestr("unobvious-member", archive())
                zipped.writestr("internalSettings", b"excluded fixture")
            scanner = source.Scan(self.specs, Path(temporary))
            scanner.inspect_payload(blob.getvalue(), "wrapped.bytes")
            self.assertEqual(len(scanner.report["indexes"]), 1)
            self.assertIn("::ZIP:unobvious-member", scanner.report["indexes"][0]["source"])
            self.assertEqual(scanner.report["zipPayloadMembers"], 1)
            self.assertEqual(len(scanner.report["skipped"]), 1)

    def test_corrupt_and_oversized_zip_are_explicit_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            scanner = source.Scan(self.specs, Path(temporary))
            scanner.inspect_payload(b"PK\x03\x04not-a-zip", "bad.bytes")
            blob = io.BytesIO()
            with ZipFile(blob, "w") as zipped:
                zipped.writestr("member", b"12345")
            with patch.object(source, "MAX_ZIP_EXPANDED", 4):
                scanner.inspect_payload(blob.getvalue(), "large.bytes")
            self.assertEqual([e["kind"] for e in scanner.report["errors"]], ["BadZipFile", "ValueError"])

    def test_resource_manager_paths_do_not_depend_on_assetbundle_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            pointer = SimpleNamespace(m_PathID=99, m_FileID=1)
            obj = SimpleNamespace(type=SimpleNamespace(name="ResourceManager"), path_id=7,
                                  read=lambda: SimpleNamespace(m_Container=[(self.motion["exactPaths"][1], pointer)]))
            module = SimpleNamespace(config=SimpleNamespace(), load=lambda data: SimpleNamespace(container={}, objects=[obj]))
            scanner = source.Scan(self.specs, Path(temporary))
            with patch.dict(sys.modules, {"UnityPy": module}):
                scanner.container(b"UnityFS\x00fixture", "opaque.bin")
            self.assertEqual(scanner.report["resourceManagerPaths"], 1)
            candidate = scanner.report["containerCandidates"][0]
            self.assertFalse(candidate["modelComplete"])
            self.assertFalse(candidate["runtimeInstalled"])
            self.assertEqual(candidate["paths"][0]["fileID"], 1)

    def test_extensionless_zip_member_is_found_by_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "original.zip"
            with ZipFile(path, "w") as zipped:
                zipped.writestr("Data/unknown-cache", archive())
                zipped.writestr("unrelated.txt", b"not source index content")
            scanner = source.Scan(self.specs, root)
            scanner.archive(path)
            self.assertEqual(len(scanner.report["indexes"]), 1)
            self.assertTrue(scanner.report["indexes"][0]["source"].endswith("Data/unknown-cache"))


if __name__ == "__main__":
    unittest.main()
