"""Mock-only adapter tests, prepared but NOT RUN. No real encryption or keys."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import music_envelope as adapter


class EnvelopeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.clear = b'synthetic clear'
        self.cipher = adapter.PREFIX + b'Salted__' + b'synthetic ciphertext and tag'
        self.approved = adapter.pack.digest(self.cipher)
        self.source = self.root / 'clear'
        self.source.write_bytes(self.clear)
        self.encrypted = self.root / 'cipher'
        self.encrypted.write_bytes(self.cipher)
        self.envelope = Mock()
        self.envelope.seal.return_value = self.cipher
        self.envelope.unseal.return_value = self.clear
        for patcher in (
            patch.object(adapter, 'CIPHER_BYTES', len(self.cipher)),
            patch.object(adapter.pack, 'ARCHIVE_BYTES', len(self.clear)),
            patch.object(adapter.pack, 'verify_bytes', side_effect=self.verify_clear),
            patch.object(adapter, 'load_envelope', return_value=self.envelope),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def verify_clear(self, data):
        if data != self.clear:
            raise ValueError('synthetic clear mismatch')
        return {}

    def test_seal_roundtrip_then_new_output(self):
        output = self.root / 'new.enc'
        result = adapter.seal(self.source, output, 'unused-mock-source')
        self.assertEqual(output.read_bytes(), self.cipher)
        self.assertEqual(result['sha256'], self.approved)
        self.envelope.seal.assert_called_once_with(self.clear, adapter.pack.PURPOSE)
        self.envelope.unseal.assert_called_once_with(self.cipher, adapter.pack.PURPOSE)

    def test_digest_rejection_precedes_helper_or_key_use(self):
        with self.assertRaises(ValueError):
            adapter.authenticate(self.encrypted, '0' * 64, 'unused-mock-source')
        adapter.load_envelope.assert_not_called()
        self.envelope.unseal.assert_not_called()

    def test_oversized_input_rejected_before_helper(self):
        self.encrypted.write_bytes(self.cipher + b'x')
        with self.assertRaises(ValueError):
            adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source')
        adapter.load_envelope.assert_not_called()

    def test_authentication_failure_writes_nothing(self):
        self.envelope.unseal.side_effect = ValueError('mock authentication failed')
        output = self.root / 'new.clear'
        with self.assertRaises(ValueError):
            adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source', output)
        self.assertFalse(output.exists())

    def test_wrong_clear_digest_writes_nothing(self):
        self.envelope.unseal.return_value = b'wrong'
        output = self.root / 'new.clear'
        with self.assertRaises(ValueError):
            adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source', output)
        self.assertFalse(output.exists())

    def test_authenticate_does_not_write_and_unseal_never_overwrites(self):
        before = set(self.root.iterdir())
        adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source')
        self.assertEqual(set(self.root.iterdir()), before)
        output = self.root / 'new.clear'
        adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source', output)
        self.assertEqual(output.read_bytes(), self.clear)
        with self.assertRaises(FileExistsError):
            adapter.authenticate(self.encrypted, self.approved, 'unused-mock-source', output)
        self.assertEqual(output.read_bytes(), self.clear)


class SourcePinTests(unittest.TestCase):
    def test_source_rejected_without_executing_it(self):
        with patch.object(adapter, 'read_file', return_value=b'raise RuntimeError()'):
            with self.assertRaises(ValueError):
                adapter.load_envelope('synthetic-source')


if __name__ == '__main__':
    unittest.main()
