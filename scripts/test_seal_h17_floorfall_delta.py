"""Small hostile-envelope checks; no original media, network, or real keys."""
import base64
import copy
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import seal_h17_floorfall_delta as subject


class FloorfallDeltaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = self.root / "base"
        self.delta = self.root / "delta"
        self.base.mkdir(); self.delta.mkdir()
        self.key = self.root / "test-only.key"
        self.key.write_bytes(base64.b64encode(bytes(range(32))))
        self.key.chmod(0o600)
        base_files = {f"Existing_{i:03d}.bin": bytes([i % 251 + 1]) * (i % 13 + 1) for i in range(293)}
        base_files.update({subject.RELEASE_NAME: b"old-reviewed-release", subject.AUDIO_NAME: b"old-reviewed-audio"})
        for name, raw in base_files.items(): (self.base / name).write_bytes(raw)
        base_rows = [{"file": name, "bytes": len(raw), "sha256": subject.digest(raw)} for name, raw in sorted(base_files.items())]
        self.base_release_sha = subject.digest(base_files[subject.RELEASE_NAME])
        self.base_manifest = self.root / "base-manifest.json"
        self.base_manifest.write_bytes(subject.encoded({"files": base_rows, "releaseSHA256": self.base_release_sha}))
        self.payloads = {f"New_Fall_{i}.wav": b"fixture-pcm-" + bytes([i + 1]) for i in range(7)}
        self.payloads.update({subject.RELEASE_NAME: b"new-reviewed-release", subject.AUDIO_NAME: b"new-reviewed-audio"})
        for name, raw in self.payloads.items(): (self.delta / name).write_bytes(raw)
        target = subject.record(subject.RELEASE_NAME, self.payloads[subject.RELEASE_NAME])
        document = {
            "schema": "fighter-h17-audio-delta-v1",
            "basePackManifestSHA256": subject.digest(self.base_manifest.read_bytes()),
            "baseReleaseSHA256": self.base_release_sha,
            "targetRelease": target,
            "replacements": [subject.RELEASE_NAME, subject.AUDIO_NAME],
            "additions": sorted(n for n in self.payloads if n.endswith('.wav')),
            "files": [subject.record(n, v) for n, v in sorted(self.payloads.items())],
            "unchangedBaseFiles": 293, "requiresIndependentSignedBuildPin": True,
            "encrypted": False, "uploaded": False,
        }
        self.delta_manifest = self.root / "delta-manifest-private.json"
        self.delta_manifest.write_bytes(subject.encoded(document))
        for name, value in {
            'BASE_PACK_SHA': subject.digest(self.base_manifest.read_bytes()),
            'BASE_RELEASE_SHA': self.base_release_sha,
            'TARGET_RELEASE_SHA': target['sha256'],
            'DELTA_SHA': subject.digest(self.delta_manifest.read_bytes()),
        }.items():
            test_pin = patch.object(subject, name, value); test_pin.start(); self.addCleanup(test_pin.stop)

    def seal(self):
        output = self.root / "sealed"
        receipt = subject.seal(self.delta, self.delta_manifest, self.key, output)
        return output, receipt

    def apply(self, sealed, receipt, output=None, key=None):
        return subject.apply(sealed, sealed / "manifest.json", receipt['manifestSHA256'],
                             self.base, self.base_manifest, key or self.key, output or self.root / "installed")

    def rewrite_envelope(self, sealed, receipt, clear):
        key = base64.b64decode(self.key.read_bytes())
        nonce = bytes(range(12))
        cipher = nonce + AESGCM(key).encrypt(nonce, clear, subject.AAD)
        (sealed / subject.CIPHER_NAME).write_bytes(cipher)
        manifest = json.loads((sealed / 'manifest.json').read_bytes())
        manifest.update(cipher=subject.record(subject.CIPHER_NAME, cipher), clearZIPBytes=len(clear), clearZIPSHA256=subject.digest(clear))
        raw = subject.encoded(manifest)
        (sealed / 'manifest.json').write_bytes(raw)
        return dict(receipt, manifestSHA256=subject.digest(raw))

    def test_round_trip_installs_exact_delta_and_preserves_all_base_bytes(self):
        before = {p.name: subject.digest(p.read_bytes()) for p in self.base.iterdir()}
        sealed, receipt = self.seal()
        result = self.apply(sealed, receipt)
        installed = self.root / 'installed'
        self.assertEqual(result['files'], 302)
        self.assertEqual(result['unchangedFiles'], 293)
        self.assertEqual(result['deltaFiles'], 9)
        self.assertFalse(result['uploaded']); self.assertFalse(result['secretDestinationChanged'])
        self.assertEqual(before, {p.name: subject.digest(p.read_bytes()) for p in self.base.iterdir()})
        for path in installed.iterdir():
            expected = self.payloads.get(path.name, (self.base / path.name).read_bytes() if (self.base / path.name).exists() else None)
            self.assertEqual(path.read_bytes(), expected)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(installed.stat().st_mode), 0o700)

    def test_wrong_manifest_pin_is_rejected_before_key_or_output(self):
        sealed, receipt = self.seal()
        with patch.object(subject, 'read_key') as key, self.assertRaises(ValueError):
            self.apply(sealed, dict(receipt, manifestSHA256='0' * 64))
        key.assert_not_called(); self.assertFalse((self.root / 'installed').exists())

    def test_changed_delta_cannot_self_authorize_a_target_release(self):
        document = json.loads(self.delta_manifest.read_bytes())
        document['targetRelease']['sha256'] = 'a' * 64
        self.delta_manifest.write_bytes(subject.encoded(document))
        with patch.object(subject, 'read_key') as key, self.assertRaises(ValueError): self.seal()
        key.assert_not_called(); self.assertFalse((self.root / 'sealed').exists())

    def test_modified_cipher_fails_authentication_even_if_outer_digest_is_replaced(self):
        sealed, receipt = self.seal()
        cipher = bytearray((sealed / subject.CIPHER_NAME).read_bytes()); cipher[-1] ^= 1
        (sealed / subject.CIPHER_NAME).write_bytes(cipher)
        manifest = json.loads((sealed / 'manifest.json').read_bytes())
        manifest['cipher'] = subject.record(subject.CIPHER_NAME, bytes(cipher))
        raw = subject.encoded(manifest); (sealed / 'manifest.json').write_bytes(raw)
        with self.assertRaises(InvalidTag): self.apply(sealed, dict(receipt, manifestSHA256=subject.digest(raw)))
        self.assertFalse((self.root / 'installed').exists())

    def test_wrong_key_does_not_create_a_partial_installation(self):
        sealed, receipt = self.seal()
        wrong = self.root / 'wrong.key'; wrong.write_bytes(base64.b64encode(b'X' * 32)); wrong.chmod(0o600)
        with self.assertRaises(InvalidTag): self.apply(sealed, receipt, key=wrong)
        self.assertFalse((self.root / 'installed').exists())

    def test_changed_base_resource_fails_before_key_read(self):
        sealed, receipt = self.seal()
        (self.base / 'Existing_000.bin').write_bytes(b'changed')
        with patch.object(subject, 'read_key') as key, self.assertRaises(ValueError): self.apply(sealed, receipt)
        key.assert_not_called(); self.assertFalse((self.root / 'installed').exists())

    def test_symlink_payload_and_key_are_rejected(self):
        path = self.delta / 'New_Fall_0.wav'; path.unlink(); path.symlink_to(self.key)
        with self.assertRaises(OSError): self.seal()
        self.assertFalse((self.root / 'sealed').exists())
        alias = self.root / 'key-alias'; alias.symlink_to(self.key)
        with self.assertRaises(ValueError): subject.read_key(alias)

    def test_public_or_noncanonical_key_is_rejected(self):
        self.key.chmod(0o644)
        with self.assertRaises(ValueError): subject.read_key(self.key)
        self.key.chmod(0o600); self.key.write_bytes(b'not-a-canonical-key')
        with self.assertRaises(ValueError): subject.read_key(self.key)

    def test_repeated_successful_output_is_rejected_without_key_access(self):
        sealed, receipt = self.seal(); self.apply(sealed, receipt)
        with patch.object(subject, 'read_key') as key:
            with self.assertRaises(ValueError): self.seal()
            with self.assertRaises(ValueError): self.apply(sealed, receipt)
        key.assert_not_called()

    def test_authenticated_zip_rejects_traversal_duplicates_and_symlink_members(self):
        sealed, receipt = self.seal()
        normal = dict(self.payloads, **{subject.DELTA_NAME: self.delta_manifest.read_bytes()})
        for mode in ['traversal', 'duplicate', 'symlink']:
            with self.subTest(mode=mode):
                stream = io.BytesIO()
                with zipfile.ZipFile(stream, 'w') as archive:
                    for name, raw in normal.items():
                        actual = '../outside.wav' if mode == 'traversal' and name == 'New_Fall_0.wav' else name
                        info = zipfile.ZipInfo(actual); info.create_system = 3; info.external_attr = 0o100600 << 16
                        if mode == 'symlink' and name == 'New_Fall_0.wav': info.external_attr = 0o120600 << 16
                        archive.writestr(info, raw)
                    if mode == 'duplicate':
                        import warnings
                        with warnings.catch_warnings():
                            warnings.simplefilter('ignore'); archive.writestr('New_Fall_0.wav', b'duplicate')
                changed_receipt = self.rewrite_envelope(sealed, receipt, stream.getvalue())
                with self.assertRaises(ValueError): self.apply(sealed, changed_receipt)
                self.assertFalse((self.root / 'installed').exists())

    def test_authenticated_oversized_expansion_is_rejected_before_extracting(self):
        sealed, receipt = self.seal()
        payloads = dict(self.payloads, **{subject.DELTA_NAME: self.delta_manifest.read_bytes()})
        payloads['New_Fall_0.wav'] = b'\0' * (subject.MAX_DELTA_BYTES + 1)
        changed_receipt = self.rewrite_envelope(sealed, receipt, subject.zip_bytes(payloads))
        with self.assertRaises(ValueError): self.apply(sealed, changed_receipt)
        self.assertFalse((self.root / 'installed').exists())


if __name__ == '__main__':
    unittest.main()
