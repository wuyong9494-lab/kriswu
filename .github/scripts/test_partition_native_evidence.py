import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import partition_native_evidence as evidence


class PartitionNativeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / evidence.CIPHERTEXT_NAME
        self.parts = self.root / "parts"
        self.metadata = {
            "repository": evidence.REPOSITORY, "runID": evidence.SOURCE_RUN, "runAttempt": 1,
            "headSHA": evidence.SOURCE_HEAD, "runStatus": "completed", "runConclusion": "failure",
            "runURL": f"https://github.com/{evidence.REPOSITORY}/actions/runs/{evidence.SOURCE_RUN}",
            "runStartedAt": "2026-11-09T02:46:59Z", "runUpdatedAt": "2026-11-09T03:30:00Z",
            "artifactID": 123, "artifactName": evidence.ARTIFACT_NAME,
            "artifactDigest": "sha256:" + "a" * 64, "artifactBytes": 4096,
            "artifactCreatedAt": "2026-11-09T03:29:00Z",
        }

    def payload(self, size=195):
        # Deliberately synthetic opaque bytes: no key, encryption or valid MAC.
        header = evidence.PREFIX + b"Salted__"
        return header + bytes(index % 251 for index in range(size - len(header)))

    def create(self, size=195):
        data = self.payload(size)
        self.source.write_bytes(data)
        manifest = evidence.partition(self.source, self.parts, self.metadata, part_bytes=64)
        return data, manifest

    def save_manifest(self, manifest):
        (self.parts / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def test_round_trip_preserves_all_bytes_hashes_and_failed_source_conclusion(self):
        data, manifest = self.create()
        self.assertEqual([part["bytes"] for part in manifest["parts"]], [64, 64, 64, 3])
        self.assertEqual(manifest["source"], self.metadata)
        self.assertEqual(manifest["source"]["runConclusion"], "failure")
        self.assertEqual(manifest["ciphertext"]["sha256"], hashlib.sha256(data).hexdigest())
        for part in manifest["parts"]:
            content = (self.parts / part["name"]).read_bytes()
            self.assertEqual(content, data[part["offset"]:part["offset"] + part["bytes"]])
            self.assertEqual(hashlib.sha256(content).hexdigest(), part["sha256"])
        self.assertEqual(evidence.verify(self.parts), manifest)
        output = self.root / "reassembled.enc"
        evidence.reassemble(self.parts, output)
        self.assertEqual(output.read_bytes(), data)
        self.assertIn("no decryption", manifest["verification"])

    def test_exact_partition_boundary_and_maximum_eight_parts(self):
        for size, count in [(128, 2), (129, 3), (512, 8)]:
            with self.subTest(size=size):
                self.source.write_bytes(self.payload(size))
                output = self.root / f"parts-{size}"
                manifest = evidence.partition(self.source, output, self.metadata, part_bytes=64)
                self.assertEqual(manifest["partCount"], count)
                evidence.verify(output)

    def test_empty_wrong_purpose_wrong_openssl_header_and_truncation_are_rejected(self):
        for data in [b"", b"secret" * 100, b"FIGHTER1\0model\0Salted__" + b"x" * 100,
                     evidence.PREFIX + b"x" * 100, self.payload(evidence.MIN_BYTES - 1)]:
            with self.subTest(size=len(data)):
                self.source.write_bytes(data)
                with self.assertRaises(ValueError):
                    evidence.partition(self.source, self.parts, self.metadata, part_bytes=64)
                self.assertFalse(self.parts.exists())

    def test_oversize_part_and_excess_part_count_are_rejected_without_partial_output(self):
        self.source.write_bytes(self.payload(513))
        for limit in [64, 0, True, evidence.PART_BYTES + 1]:
            with self.subTest(limit=limit), self.assertRaises(ValueError):
                evidence.partition(self.source, self.parts, self.metadata, part_bytes=limit)
        self.assertFalse(self.parts.exists())
        self.assertEqual(list(self.root.iterdir()), [self.source])

    def test_source_identity_status_digest_attempt_and_timestamps_are_bound(self):
        changes = [
            ("repository", "somewhere/else"), ("runID", evidence.SOURCE_RUN + 1),
            ("headSHA", "f" * 40), ("runStatus", "in_progress"), ("runConclusion", None),
            ("artifactName", "fighter-native"), ("artifactDigest", "sha256:bad"),
            ("artifactID", 0), ("runAttempt", True), ("artifactBytes", 0),
            ("artifactBytes", evidence.MAX_ARCHIVE_BYTES + 1),
            ("runURL", "https://example.com"),
            ("artifactCreatedAt", "2026-11-09T01:00:00Z"),
            ("artifactCreatedAt", "2026-11-09T04:00:00Z"),
            ("runStartedAt", "2026-11-09T02:46:59"),
        ]
        for key, value in changes:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                evidence.validate_source({**self.metadata, key: value})
        with self.assertRaises(ValueError):
            evidence.validate_source({**self.metadata, "unrelatedPrivateData": "must not be copied"})

    def test_corrupt_part_cannot_be_verified_or_published_as_reassembled_evidence(self):
        _, manifest = self.create()
        part = self.parts / manifest["parts"][1]["name"]
        content = bytearray(part.read_bytes())
        content[7] ^= 0x80
        part.write_bytes(content)
        with self.assertRaisesRegex(ValueError, "Partition SHA-256"):
            evidence.verify(self.parts)
        output = self.root / "reassembled.enc"
        with self.assertRaises(ValueError):
            evidence.reassemble(self.parts, output)
        self.assertFalse(output.exists())
        self.assertFalse(any(path.name.startswith("native-evidence-") for path in self.root.iterdir()))

    def test_complete_ciphertext_digest_is_checked_independently_of_part_digests(self):
        _, manifest = self.create()
        manifest["ciphertext"]["sha256"] = "0" * 64
        self.save_manifest(manifest)
        with self.assertRaisesRegex(ValueError, "Reassembled ciphertext SHA-256"):
            evidence.verify(self.parts)

    def test_missing_extra_and_truncated_parts_are_rejected(self):
        _, manifest = self.create()
        part = self.parts / manifest["parts"][-1]["name"]
        original = part.read_bytes()
        part.unlink()
        with self.assertRaises(ValueError):
            evidence.verify(self.parts)
        part.write_bytes(original[:-1])
        with self.assertRaises(ValueError):
            evidence.verify(self.parts)
        part.write_bytes(original)
        (self.parts / "extra.enc").write_bytes(b"unlisted")
        with self.assertRaises(ValueError):
            evidence.verify(self.parts)

    def test_manifest_cannot_reorder_duplicate_escape_or_omit_parts(self):
        _, manifest = self.create()
        changes = [
            lambda value: value["parts"].reverse(),
            lambda value: value["parts"][1].update(name=value["parts"][0]["name"]),
            lambda value: value["parts"][0].update(name="../outside"),
            lambda value: value["parts"][0].update(name="/tmp/outside"),
            lambda value: value["parts"][0].update(offset=1),
            lambda value: value["parts"][0].update(index=True),
            lambda value: value["parts"].pop(),
            lambda value: value.update(partCount=9),
            lambda value: value.update(schemaVersion=True),
        ]
        for change in changes:
            value = copy.deepcopy(manifest)
            change(value)
            self.save_manifest(value)
            with self.subTest(change=change), self.assertRaises(ValueError):
                evidence.verify(self.parts)

    def test_symlink_input_parent_part_and_manifest_are_rejected(self):
        self.source.write_bytes(self.payload())
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            evidence.partition(alias / evidence.CIPHERTEXT_NAME, self.parts, self.metadata, part_bytes=64)
        _, manifest = self.create()
        part = self.parts / manifest["parts"][0]["name"]
        saved = self.root / "saved-part"
        part.rename(saved)
        part.symlink_to(saved)
        with self.assertRaises(ValueError):
            evidence.verify(self.parts)
        part.unlink()
        saved.rename(part)
        path = self.parts / "manifest.json"
        saved_manifest = self.root / "saved-manifest"
        path.rename(saved_manifest)
        path.symlink_to(saved_manifest)
        with self.assertRaises(ValueError):
            evidence.verify(self.parts)

    def test_existing_output_and_unsafe_output_paths_are_never_overwritten(self):
        _, manifest = self.create()
        with self.assertRaises(ValueError):
            evidence.partition(self.source, self.parts, self.metadata, part_bytes=64)
        output = self.root / "keep.enc"
        output.write_bytes(b"keep existing bytes")
        with self.assertRaises(ValueError):
            evidence.reassemble(self.parts, output)
        self.assertEqual(output.read_bytes(), b"keep existing bytes")
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        for unsafe in [alias / "new.enc", self.root / ".." / "new.enc"]:
            with self.subTest(path=unsafe), self.assertRaises(ValueError):
                evidence.reassemble(self.parts, unsafe)
        self.assertEqual(evidence.verify(self.parts), manifest)

    def test_cli_partition_verify_and_reassemble_need_no_decryption_configuration(self):
        self.source.write_bytes(self.payload())
        metadata = self.root / "source.json"
        metadata.write_text(json.dumps(self.metadata), encoding="utf-8")
        script = str(Path(evidence.__file__).resolve())
        output = self.root / "reassembled.enc"
        commands = [
            ["partition", "--input", str(self.source), "--source-metadata", str(metadata), "--output", str(self.parts)],
            ["verify", "--directory", str(self.parts)],
            ["reassemble", "--directory", str(self.parts), "--output", str(output)],
        ]
        for command in commands:
            result = subprocess.run([sys.executable, script, *command], check=True, capture_output=True, text=True,
                                    env={"PATH": "/usr/bin:/bin"})
            self.assertEqual(json.loads(result.stdout)["sourceConclusion"], "failure")
        self.assertEqual(output.read_bytes(), self.source.read_bytes())


if __name__ == "__main__":
    unittest.main()
