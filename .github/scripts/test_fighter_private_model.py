import os
import hashlib
import hmac
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import tracemalloc
import unittest
from unittest.mock import patch
import zipfile
import fighter_evidence_archive as evidence_archive
import fighter_private_model as envelope


class EnvelopeTests(unittest.TestCase):
    def test_roundtrip_rejects_tamper_wrong_key_and_wrong_purpose(self):
        with patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY="a5" * 32):
            encrypted = envelope.seal(b"private test bytes" * 100, "model")
            self.assertEqual(envelope.unseal(encrypted, "model"), b"private test bytes" * 100)
            for offset in (0, len(encrypted) // 2, len(encrypted) - 1):
                damaged = bytearray(encrypted); damaged[offset] ^= 1
                with patch.object(envelope, "openssl", side_effect=AssertionError("Never decrypt unauthenticated data")):
                    with self.assertRaises(ValueError):
                        envelope.unseal(bytes(damaged), "model")
            with self.assertRaises(ValueError):
                envelope.unseal(encrypted, "evidence")
        with patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY="b6" * 32):
            with self.assertRaises(ValueError):
                envelope.unseal(encrypted, "model")

    def test_app_gate_requires_exact_model_and_rejects_staging_material(self):
        model = b"synthetic model for bundle validation"
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(envelope, "SIZE", len(model)), \
             patch.object(envelope, "SHA", hashlib.sha256(model).hexdigest()):
            app = Path(directory) / "Test.app"
            app.mkdir()
            with self.assertRaises(ValueError):
                envelope.verify_app(app)
            flat = app / "Liu_FullBody_Mobile.glb"
            flat.write_bytes(model)
            envelope.verify_app(app)
            flat.write_bytes(b"x" * len(model))
            with self.assertRaises(ValueError):
                envelope.verify_app(app)
            flat.write_bytes(model)
            nested = app / "FighterPrivate/Liu_FullBody_Mobile.glb"
            nested.parent.mkdir()
            nested.write_bytes(model)
            with self.assertRaises(ValueError):
                envelope.verify_app(app)
            flat.unlink()
            envelope.verify_app(app)
            staging = app / "FighterPrivate/Fighter_Liu_Model_Key.txt"
            staging.write_text("synthetic placeholder, not a key")
            with self.assertRaises(ValueError):
                envelope.verify_app(app)
            staging.unlink()
            (app / "liu-fullbody-v1.glb.enc").write_bytes(b"synthetic ciphertext")
            with self.assertRaises(ValueError):
                envelope.verify_app(app)


class StreamingEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.source = self.root / "synthetic.zip"
        self.output = self.root / "synthetic.enc"
        self.environment = patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY="a5" * 32,
                                      FIGHTER_OPENSSL=shutil.which("openssl") or "")
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def assert_no_output_or_temporaries(self):
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob(".fighter-seal-*")), [])

    def test_streaming_envelopes_use_exact_existing_crypto_and_legacy_reader(self):
        command = envelope.openssl_command()
        self.assertEqual(command[1:], ["enc", "-aes-256-cbc", "-pbkdf2", "-iter", "200000",
                                       "-md", "sha256", "-pass", "env:FIGHTER_LIU_MODEL_KEY"])
        for size in (0, 15, 16, 17, envelope.EVIDENCE_BUFFER_BYTES + 31):
            with self.subTest(size=size):
                clear = (b"synthetic evidence" * (size // 18 + 1))[:size]
                self.source.write_bytes(clear)
                with patch.object(Path, "read_bytes", side_effect=AssertionError("No whole-file reads")):
                    envelope.seal_evidence_file(self.source, self.output)
                encrypted = self.output.read_bytes()
                prefix = envelope.HEADER + b"evidence\0"
                self.assertTrue(encrypted.startswith(prefix + b"Salted__"))
                self.assertEqual(envelope.unseal(encrypted, "evidence"), clear)
                self.assertEqual(len(encrypted), len(prefix) + 16 + (size // 16 + 1) * 16 + 32)
                self.assertEqual(encrypted[-32:], hmac.digest(envelope.mac_key("evidence"), encrypted[:-32], "sha256"))
                # Fixed ciphertext establishes byte-for-byte compatibility with
                # the old seal implementation despite fresh randomized salts.
                with patch.object(envelope, "openssl", return_value=encrypted[len(prefix):-32]):
                    self.assertEqual(encrypted, envelope.seal(clear, "evidence"))
                self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
                self.output.unlink()

    def test_authentication_failure_never_decrypts_or_publishes_cli_output(self):
        self.source.write_bytes(b"synthetic evidence")
        envelope.seal_evidence_file(self.source, self.output)
        encrypted = self.output.read_bytes()
        for offset in (0, len(encrypted) // 2, len(encrypted) - 1):
            damaged = bytearray(encrypted)
            damaged[offset] ^= 1
            self.output.write_bytes(damaged)
            clear = self.root / "clear.zip"
            with patch.object(sys, "argv", ["envelope", "unseal", "evidence", str(self.output), str(clear)]), \
                 patch.object(envelope, "openssl", side_effect=AssertionError("Must authenticate first")):
                with self.assertRaises(ValueError):
                    envelope.main()
            self.assertFalse(clear.exists())
        self.output.write_bytes(encrypted)
        for purpose, key in (("model", "a5" * 32), ("evidence", "b6" * 32)):
            with patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY=key), \
                 patch.object(envelope, "openssl", side_effect=AssertionError("Must authenticate first")):
                with self.assertRaises(ValueError):
                    envelope.unseal(encrypted, purpose)

    def test_cli_uses_streaming_only_for_evidence_sealing(self):
        self.source.write_bytes(b"synthetic")
        with patch.object(sys, "argv", ["envelope", "seal", "evidence", str(self.source), str(self.output)]), \
             patch.object(envelope, "seal", side_effect=AssertionError("Must stream")):
            envelope.main()
        self.assertEqual(envelope.unseal(self.output.read_bytes(), "evidence"), b"synthetic")
        self.output.unlink()
        with patch.object(sys, "argv", ["envelope", "seal", "model", str(self.source), str(self.output)]), \
             patch.object(envelope, "seal_evidence_file", side_effect=AssertionError("Model API unchanged")):
            envelope.main()
        self.assertEqual(envelope.unseal(self.output.read_bytes(), "model"), b"synthetic")

    def test_large_synthetic_input_keeps_python_memory_bounded(self):
        with self.source.open("wb") as stream:
            stream.truncate(64 * 1024 * 1024)
        tracemalloc.start()
        try:
            envelope.seal_evidence_file(self.source, self.output)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, 8 * 1024 * 1024)

    def test_partial_cipher_failure_and_wrong_header_never_publish(self):
        self.source.write_bytes(b"abc")
        for output, exit_code in ((b"Salted__" + b"0" * 24, 1), (b"X" * 32, 0),
                                  (b"Salted__", 0), (b"Salted__" + b"0" * 32, 0),
                                  (b"Salted__" + b"0" * 40, 0)):
            script = f"import sys; sys.stdout.buffer.write({output!r}); sys.exit({exit_code})"
            with patch.object(envelope, "openssl_command", return_value=[sys.executable, "-c", script]):
                with self.assertRaises(ValueError):
                    envelope.seal_evidence_file(self.source, self.output)
            self.assert_no_output_or_temporaries()

    def test_source_mutation_missing_key_symlink_and_size_bound_fail_closed(self):
        self.source.write_bytes(b"abc")
        script = ("import os,sys; p=sys.argv[1]; s=os.stat(p); "
                  "os.utime(p, ns=(s.st_atime_ns,s.st_mtime_ns+1)); "
                  "sys.stdout.buffer.write(b'Salted__'+b'0'*24)")
        with patch.object(envelope, "openssl_command", return_value=[sys.executable, "-c", script, str(self.source)]):
            with self.assertRaisesRegex(ValueError, "changed"):
                envelope.seal_evidence_file(self.source, self.output)
        with patch.dict(os.environ, FIGHTER_LIU_MODEL_KEY=""):
            with self.assertRaises(ValueError):
                envelope.seal_evidence_file(self.source, self.output)
        with patch.object(envelope, "MAX_EVIDENCE_BYTES", 2):
            with self.assertRaises(ValueError):
                envelope.seal_evidence_file(self.source, self.output)
        link = self.root / "symlink.zip"
        link.symlink_to(self.source)
        with self.assertRaises(ValueError):
            envelope.seal_evidence_file(link, self.output)
        fifo = self.root / "fifo.zip"
        os.mkfifo(fifo)
        with self.assertRaises(ValueError):
            envelope.seal_evidence_file(fifo, self.output)
        self.assert_no_output_or_temporaries()

    def test_existing_or_late_output_is_never_overwritten(self):
        self.source.write_bytes(b"abc")
        self.output.write_bytes(b"existing")
        with self.assertRaises(ValueError):
            envelope.seal_evidence_file(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing")
        self.output.unlink()
        link = os.link
        def race(source, destination):
            Path(destination).write_bytes(b"late existing")
            link(source, destination)
        with patch.object(envelope.os, "link", side_effect=race):
            with self.assertRaises(FileExistsError):
                envelope.seal_evidence_file(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"late existing")
        self.assertEqual(list(self.root.glob(".fighter-seal-*")), [])


class EvidenceArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.source = self.root / "evidence"
        self.source.mkdir()
        self.output = self.root / "private.zip"

    def assert_no_output_or_temporaries(self):
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.root.glob(".fighter-archive-*")), [])

    def test_stored_archive_preserves_bytes_paths_and_empty_directories(self):
        (self.source / "native-motion").mkdir()
        (self.source / "empty").mkdir()
        expected = {"native-motion/synthetic.mp4": b"synthetic video" * 100,
                    "attachment.png": b"synthetic screenshot", "metadata.json": b"{}"}
        for name, data in expected.items():
            (self.source / name).write_bytes(data)
        with patch.object(Path, "read_bytes", side_effect=AssertionError("No whole-file reads")):
            counts = evidence_archive.archive_evidence(self.source, self.output)
        self.assertEqual(counts, {"entries": 5, "bytes": sum(map(len, expected.values()))})
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), set(expected) | {"native-motion/", "empty/"})
            self.assertTrue(all(info.compress_type == zipfile.ZIP_STORED for info in archive.infolist()))
            self.assertIsNone(archive.testzip())
            for name, data in expected.items():
                self.assertEqual(archive.read(name), data)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)

    def test_symlink_root_file_directory_and_fifo_are_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "synthetic").write_bytes(b"must not read")
        root_link = self.root / "root-link"
        root_link.symlink_to(self.source)
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(root_link, self.output)
        for target in (outside, outside / "synthetic"):
            link = self.source / "link"
            link.symlink_to(target)
            with self.assertRaises(ValueError):
                evidence_archive.archive_evidence(self.source, self.output)
            link.unlink()
            self.assert_no_output_or_temporaries()
        os.mkfifo(self.source / "fifo")
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(self.source, self.output)
        self.assert_no_output_or_temporaries()

    def test_root_swapped_to_symlink_after_check_is_never_followed(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "synthetic").write_bytes(b"must not read")
        is_symlink = Path.is_symlink
        def swap_after_check(path):
            result = is_symlink(path)
            if path == self.source:
                path.rmdir()
                path.symlink_to(outside)
            return result
        with patch.object(Path, "is_symlink", autospec=True, side_effect=swap_after_check):
            with self.assertRaises(OSError):
                evidence_archive.archive_evidence(self.source, self.output)
        self.assert_no_output_or_temporaries()

    def test_entry_byte_path_and_depth_limits(self):
        (self.source / "a").mkdir()
        (self.source / "a/file").write_bytes(b"abc")
        for name, limit in (("MAX_ENTRIES", 1), ("MAX_TOTAL_BYTES", 2),
                            ("MAX_PATH_BYTES", 2), ("MAX_DEPTH", 1)):
            with self.subTest(bound=name), patch.object(evidence_archive, name, limit):
                with self.assertRaises(ValueError):
                    evidence_archive.archive_evidence(self.source, self.output)
                self.assert_no_output_or_temporaries()

    def test_unsafe_names_and_output_locations_are_rejected(self):
        (self.source / "windows\\path").write_bytes(b"abc")
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(self.source, self.output)
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(self.source, self.source / "recursive.zip")
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(self.source / ".." / "evidence", self.output)
        self.output.write_bytes(b"existing")
        with self.assertRaises(ValueError):
            evidence_archive.archive_evidence(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing")

    def test_failed_read_and_changed_source_leave_no_archive(self):
        source = self.source / "synthetic"
        source.write_bytes(b"abc")
        read = os.read
        def mutate(descriptor, size):
            result = read(descriptor, size)
            source.write_bytes(b"changed")
            return result
        with patch.object(evidence_archive.os, "read", side_effect=mutate):
            with self.assertRaises(ValueError):
                evidence_archive.archive_evidence(self.source, self.output)
        self.assert_no_output_or_temporaries()
        with patch.object(evidence_archive.os, "read", side_effect=OSError("synthetic disk failure")):
            with self.assertRaises(OSError):
                evidence_archive.archive_evidence(self.source, self.output)
        self.assert_no_output_or_temporaries()

    def test_large_synthetic_archive_has_bounded_memory(self):
        with (self.source / "synthetic.mp4").open("wb") as stream:
            stream.truncate(64 * 1024 * 1024)
        tracemalloc.start()
        try:
            evidence_archive.archive_evidence(self.source, self.output)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, 8 * 1024 * 1024)

    def test_private_workflow_only_uploads_successfully_sealed_evidence(self):
        workflow = (Path(__file__).parents[1] / "workflows/fighter-lab.yml").read_text()
        protected = workflow.split("      - name: Protect portrait evidence before upload\n")[1]
        self.assertIn("timeout-minutes: 8", protected)
        self.assertIn("trap 'rm -rf \"$PRIVATE_ARCHIVE\"' EXIT", protected)
        self.assertIn("fighter_evidence_archive.py fighter-evidence", protected)
        self.assertIn("seal evidence \"$PRIVATE_ARCHIVE/evidence.zip\" fighter-evidence.enc", protected)
        upload = protected.split("      - uses: actions/upload-artifact@v4\n")[1]
        self.assertIn("${{ steps.protect_evidence.outcome == 'success' && 'fighter-evidence.enc' || '' }}", upload)
        self.assertIn("compression-level: 0", upload)
        self.assertNotIn(".zip", upload)
        self.assertNotIn("            fighter-evidence\n", upload)


if __name__ == "__main__":
    unittest.main()
