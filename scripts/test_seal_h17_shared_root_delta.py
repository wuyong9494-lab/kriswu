"""Synthetic sealed-delta reconstruction and hostile-input checks.

Fixtures use test-only keys and tiny data. No original media, network request,
real key, release activation, native test or repeated export is involved.
"""
import base64
from contextlib import ExitStack
from copy import deepcopy
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import seal_h17_shared_root_delta as subject
from test_stage_h17_shared_root_release import fixture_pins, synthetic_inputs


class SharedRootSealedDeltaTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.base, self.directory = self.root / "base", self.root / "delta"
        self.base.mkdir()
        self.directory.mkdir()
        self.key = self.root / "synthetic-test-only.key"
        self.key.write_bytes(base64.b64encode(bytes(range(32))))
        self.key.chmod(0o600)
        f = synthetic_inputs()
        fixture_pins(self.stack, f)
        s = subject.stage
        self.old_files = {f"Existing_{i:03d}.bin": bytes([i % 251 + 1]) * (i % 13 + 1) for i in range(289)}
        self.old_files.update({s.CHARACTER_NAME: f["old_model"], s.CATALOG_NAME: subject.encoded(f["catalog"]),
            subject.AUDIO_NAME: subject.encoded(f["audio"]), subject.RELEASE_NAME: subject.encoded(f["release"]),
            s.MORPH_NAME: subject.encoded(f["morph"]), s.TRAILS_NAME: subject.encoded(f["trails"])})
        for name, value in self.old_files.items():
            (self.base / name).write_bytes(value)
        self.inventory = {name: subject.record(name, raw) for name, raw in self.old_files.items()}
        base_release_sha = subject.digest(self.old_files[subject.RELEASE_NAME])
        self.base_manifest = self.root / "base-manifest.json"
        self.base_manifest.write_bytes(subject.encoded(dict(releaseSHA256=base_release_sha,
            files=[dict(file=name, bytes=len(value), sha256=subject.digest(value)) for name, value in sorted(self.old_files.items())])))
        base_pack_sha = subject.digest(self.base_manifest.read_bytes())
        self.stack.enter_context(patch.object(s, "BASE_RELEASE_SHA", base_release_sha))
        self.stack.enter_context(patch.object(subject, "BASE_RELEASE_SHA", base_release_sha))
        self.stack.enter_context(patch.object(subject, "BASE_PACK_SHA", base_pack_sha))
        model_patch, geometry = s.glb_patch(f["old_model"], f["new_model"])
        catalog_patch, new_catalog = s.catalog_patch(self.old_files[s.CATALOG_NAME], f["clips"])
        audio = subject.encoded(s.revised_audio(f["audio"]))
        morph = s.rebind_json_raw(self.old_files[s.MORPH_NAME], s.MORPH_SHA, s.revised_morph)
        trails = s.rebind_json_raw(self.old_files[s.TRAILS_NAME], s.TRAILS_SHA, s.revised_trails)
        release = subject.encoded(s.revised_release(f["release"], subject.record(s.CATALOG_NAME, new_catalog),
            subject.record(subject.AUDIO_NAME, audio), subject.record(s.MORPH_NAME, morph), subject.record(s.TRAILS_NAME, trails)))
        self.changed = {s.CHARACTER_NAME: f["new_model"], s.CATALOG_NAME: new_catalog, subject.AUDIO_NAME: audio,
                        subject.RELEASE_NAME: release, s.MORPH_NAME: morph, s.TRAILS_NAME: trails}
        self.changed.update({name: b"synthetic-wave-" + bytes([i]) for i, name in enumerate(s.FLOORFALL_NAMES)})
        self.payloads = {name: value for name, value in self.changed.items() if name not in (s.CHARACTER_NAME, s.CATALOG_NAME)}
        self.payloads.update({s.GLB_PATCH_NAME: model_patch, s.CATALOG_PATCH_NAME: catalog_patch})
        self.document = dict(schema="fighter-h17-shared-root-delta-v1", basePackManifestSHA256=base_pack_sha,
            baseReleaseSHA256=base_release_sha, sourceFloorfallReleaseSHA256=s.FLOORFALL_RELEASE_SHA,
            targetRelease=subject.record(subject.RELEASE_NAME, release), replacements=s.REPLACEMENTS,
            additions=sorted(s.FLOORFALL_NAMES), files=[subject.record(n, v) for n, v in sorted(self.changed.items())],
            payloads=[subject.record(n, v) for n, v in sorted(self.payloads.items())],
            transforms=[dict(kind="glb-bin-append-v1", target=s.CHARACTER_NAME, payload=s.GLB_PATCH_NAME,
                             base=self.inventory[s.CHARACTER_NAME], **geometry),
                        dict(kind="catalog-three-clip-append-v1", target=s.CATALOG_NAME, payload=s.CATALOG_PATCH_NAME,
                             base=self.inventory[s.CATALOG_NAME], priorClipCount=56, appendedClips=[c["name"] for c in s.CLIPS])],
            unchangedBaseFiles=289, requiresIndependentSignedBuildPin=True, encrypted=False, uploaded=False)
        self.delta_path = self.root / "delta-manifest-private.json"
        self.delta_path.write_bytes(subject.encoded(self.document))
        for name, value in self.payloads.items():
            (self.directory / name).write_bytes(value)
        self.stack.enter_context(patch.object(subject, "DELTA_SHA", subject.digest(self.delta_path.read_bytes())))
        self.stack.enter_context(patch.object(subject, "TARGET_RELEASE_SHA", subject.digest(release)))

    def seal(self):
        output = self.root / "sealed"
        return output, subject.seal(self.directory, self.delta_path, self.key, output)

    def apply(self, directory, receipt, output=None, key=None):
        return subject.apply(directory, directory / "manifest.json", receipt["manifestSHA256"], self.base,
                             self.base_manifest, key or self.key, output or self.root / "installed")

    def rewrite_envelope(self, directory, receipt, clear, aad=None):
        nonce = bytes(range(12))
        cipher = nonce + AESGCM(base64.b64decode(self.key.read_bytes())).encrypt(nonce, clear, aad or subject.AAD)
        (directory / subject.CIPHER_NAME).write_bytes(cipher)
        manifest = subject.parse_json((directory / "manifest.json").read_bytes())
        manifest.update(cipher=subject.record(subject.CIPHER_NAME, cipher), clearZIPBytes=len(clear), clearZIPSHA256=subject.digest(clear))
        raw = subject.encoded(manifest)
        (directory / "manifest.json").write_bytes(raw)
        return dict(receipt, manifestSHA256=subject.digest(raw))

    def test_round_trip_reconstructs_models_and_catalog_without_transferring_old_binary(self):
        before = {name: subject.digest(raw) for name, raw in self.old_files.items()}
        directory, receipt = self.seal()
        result = self.apply(directory, receipt)
        self.assertEqual((result["files"], result["unchangedFiles"], result["deltaFiles"], result["payloadFiles"]), (302, 289, 13, 13))
        self.assertFalse(result["uploaded"])
        self.assertFalse(result["secretDestinationChanged"])
        self.assertNotIn(subject.stage.CHARACTER_NAME, self.payloads)
        self.assertNotIn(subject.stage.CATALOG_NAME, self.payloads)
        self.assertEqual(before, {path.name: subject.digest(path.read_bytes()) for path in self.base.iterdir()})
        installed = self.root / "installed"
        self.assertEqual(stat.S_IMODE(installed.stat().st_mode), 0o700)
        for path in installed.iterdir():
            self.assertEqual(path.read_bytes(), self.changed.get(path.name, self.old_files.get(path.name)))
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        for path in directory.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_wrong_independent_manifest_pin_rejects_before_key_or_output(self):
        directory, receipt = self.seal()
        with patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
            self.apply(directory, dict(receipt, manifestSHA256="0" * 64))
        key.assert_not_called()
        self.assertFalse((self.root / "installed").exists())

    def test_changed_delta_cannot_authorize_itself_or_a_different_target(self):
        document = deepcopy(self.document)
        document["targetRelease"]["sha256"] = "a" * 64
        self.delta_path.write_bytes(subject.encoded(document))
        with patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
            self.seal()
        key.assert_not_called()
        self.assertFalse((self.root / "sealed").exists())

    def test_incorrect_original_base_resource_rejects_before_key_access(self):
        directory, receipt = self.seal()
        (self.base / "Existing_000.bin").write_bytes(b"changed")
        with patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
            self.apply(directory, receipt)
        key.assert_not_called()
        self.assertFalse((self.root / "installed").exists())

    def test_base_directory_extra_member_rejects_before_key_access(self):
        directory, receipt = self.seal()
        (self.base / "unreviewed.bin").write_bytes(b"extra")
        with patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
            self.apply(directory, receipt)
        key.assert_not_called()

    def test_cipher_authentication_failure_cannot_create_an_installation(self):
        directory, receipt = self.seal()
        cipher = bytearray((directory / subject.CIPHER_NAME).read_bytes())
        cipher[-1] ^= 1
        (directory / subject.CIPHER_NAME).write_bytes(cipher)
        manifest = subject.parse_json((directory / "manifest.json").read_bytes())
        manifest["cipher"] = subject.record(subject.CIPHER_NAME, bytes(cipher))
        raw = subject.encoded(manifest)
        (directory / "manifest.json").write_bytes(raw)
        with self.assertRaises(InvalidTag):
            self.apply(directory, dict(receipt, manifestSHA256=subject.digest(raw)))
        self.assertFalse((self.root / "installed").exists())

    def test_wrong_key_and_wrong_aad_fail_before_output(self):
        directory, receipt = self.seal()
        wrong = self.root / "wrong-test-only.key"
        wrong.write_bytes(base64.b64encode(b"X" * 32))
        wrong.chmod(0o600)
        with self.assertRaises(InvalidTag):
            self.apply(directory, receipt, key=wrong)
        clear = subject.zip_bytes(dict(self.payloads, **{subject.DELTA_NAME: self.delta_path.read_bytes()}))
        changed = self.rewrite_envelope(directory, receipt, clear, aad=b"wrong-purpose")
        with self.assertRaises(InvalidTag):
            self.apply(directory, changed)
        self.assertFalse((self.root / "installed").exists())

    def test_repeated_outputs_reject_before_key_read(self):
        directory, receipt = self.seal()
        self.apply(directory, receipt)
        with patch.object(subject, "read_key") as key:
            with self.assertRaises(ValueError):
                self.seal()
            with self.assertRaises(ValueError):
                self.apply(directory, receipt)
        key.assert_not_called()

    def test_symlink_payload_and_output_parent_reject_before_key_read(self):
        path = self.directory / subject.stage.FLOORFALL_NAMES[0]
        path.unlink()
        path.symlink_to(self.key)
        with patch.object(subject, "read_key") as key, self.assertRaises(OSError):
            self.seal()
        key.assert_not_called()
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
            subject.seal(self.directory, self.delta_path, self.key, alias / "never-create")
        key.assert_not_called()

    def test_output_under_input_or_repository_is_rejected_before_key_read(self):
        for output in (self.directory / "nested", subject.stage.ROOT / "never-create-sealed-test"):
            with self.subTest(output=output.name), patch.object(subject, "read_key") as key, self.assertRaises(ValueError):
                subject.seal(self.directory, self.delta_path, self.key, output)
            key.assert_not_called()

    def test_key_permissions_encoding_and_alias_are_enforced(self):
        self.key.chmod(0o644)
        with self.assertRaises(ValueError):
            subject.read_key(self.key)
        self.key.chmod(0o600)
        self.key.write_bytes(b"not-base64")
        with self.assertRaises(ValueError):
            subject.read_key(self.key)
        alias = self.root / "key-alias"
        alias.symlink_to(self.key)
        with self.assertRaises(ValueError):
            subject.read_key(alias)

    def test_zip_traversal_duplicates_and_symlink_members_are_rejected(self):
        normal = dict(self.payloads, **{subject.DELTA_NAME: self.delta_path.read_bytes()})
        victim = subject.stage.FLOORFALL_NAMES[0]
        for kind in ("traversal", "duplicate", "symlink"):
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, "w") as archive:
                for name, value in normal.items():
                    actual = "../outside.wav" if kind == "traversal" and name == victim else name
                    info = zipfile.ZipInfo(actual)
                    info.create_system = 3
                    info.external_attr = (0o120600 if kind == "symlink" and name == victim else 0o100600) << 16
                    archive.writestr(info, value)
                if kind == "duplicate":
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore")
                        archive.writestr(victim, b"extra")
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                subject.decoded_payloads(stream.getvalue())

    def test_oversized_expansion_is_rejected_before_reading_members(self):
        payloads = dict(self.payloads, **{subject.DELTA_NAME: self.delta_path.read_bytes()})
        payloads[subject.stage.FLOORFALL_NAMES[0]] = b"\0" * (subject.MAX_TRANSPORT_BYTES + 1)
        with patch.object(zipfile.ZipFile, "read") as read, self.assertRaises(ValueError):
            subject.decoded_payloads(subject.zip_bytes(payloads))
        read.assert_not_called()

    def test_target_reconstruction_rejects_wrong_model_base_or_catalog_output(self):
        for kind in ("base", "target"):
            document = deepcopy(self.document)
            if kind == "base":
                document["transforms"][0]["base"]["sha256"] = "a" * 64
            else:
                next(row for row in document["files"] if row["name"] == subject.stage.CATALOG_NAME)["sha256"] = "a" * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                subject.reconstruct(document, self.payloads, self.base, self.inventory)

    def test_catalog_patch_does_not_allow_replacing_existing_rules(self):
        payloads = dict(self.payloads)
        document = deepcopy(self.document)
        patch_raw = subject.parse_json(payloads[subject.stage.CATALOG_PATCH_NAME])
        patch_raw["roles"] = {"injected": "old_0"}
        payloads[subject.stage.CATALOG_PATCH_NAME] = subject.encoded(patch_raw)
        document["payloads"] = [subject.record(n, v) for n, v in sorted(payloads.items())]
        with self.assertRaises(ValueError):
            subject.reconstruct(document, payloads, self.base, self.inventory)

    def test_pinned_delta_still_rejects_bad_counts_bounds_and_morph_omission(self):
        for kind in ("count", "bool-size", "too-large", "missing-morph"):
            value = deepcopy(self.document)
            if kind == "count":
                value["unchangedBaseFiles"] = 291
            elif kind == "bool-size":
                value["payloads"][0]["bytes"] = True
            elif kind == "too-large":
                value["payloads"][0]["bytes"] = subject.MAX_TRANSPORT_BYTES
            else:
                value["replacements"] = [n for n in value["replacements"] if n != subject.stage.MORPH_NAME]
            raw = subject.encoded(value)
            with self.subTest(kind=kind), patch.object(subject, "DELTA_SHA", subject.digest(raw)), self.assertRaises(ValueError):
                subject.delta_document(raw)


if __name__ == "__main__":
    unittest.main()
