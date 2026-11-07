import os
import hashlib
from pathlib import Path
import tempfile
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


if __name__ == "__main__":
    unittest.main()
