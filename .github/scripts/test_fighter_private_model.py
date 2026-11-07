import os
import unittest
from unittest.mock import patch
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


if __name__ == "__main__":
    unittest.main()
