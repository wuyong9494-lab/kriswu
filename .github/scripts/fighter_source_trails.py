#!/usr/bin/env python3
"""Stage one new authenticated source-skin file with the existing presentation key.

The envelope purpose is distinct; no model archive or existing key is replaced.
Only ciphertext, hashes and byte counts may enter the public repository.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import fighter_private_model as envelope

ROOT = Path(__file__).resolve().parents[2]
NAME = "SF3_SourceTrails.json"
SHA = "6efadacf6a9e18a270a609132f622fb3ef569a505e46c81ff17c4b7ee386d0cc"
SIZE = 20_724
PURPOSE = "source-trails-v1"


def stage(destination=None):
    folder = ROOT / ".github/private/fighter-source-trails"
    manifest = json.loads((folder / "manifest.json").read_text())
    if (manifest.get("version"), manifest.get("purpose"), manifest.get("files")) != (
            1, PURPOSE, [dict(file=NAME, bytes=SIZE, sha256=SHA)]):
        raise ValueError("Unexpected source trail identity")
    path = folder / "source-trails-v1.enc.b64"
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 100_000:
        raise ValueError("Invalid source trail envelope")
    cipher = base64.b64decode(path.read_bytes(), validate=True)
    if len(cipher) != manifest["cipherBytes"] or hashlib.sha256(cipher).hexdigest() != manifest["cipherSHA256"]:
        raise ValueError("Source trail ciphertext mismatch")
    value = os.environ.get("FIGHTER_PRESENTATION_KEY", "")
    if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Missing presentation key for source trails")
    original = os.environ.get("FIGHTER_LIU_MODEL_KEY")
    try:
        os.environ["FIGHTER_LIU_MODEL_KEY"] = value
        clear = envelope.unseal(cipher, PURPOSE)
    finally:
        if original is None:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
        else:
            os.environ["FIGHTER_LIU_MODEL_KEY"] = original
    if len(clear) != SIZE or hashlib.sha256(clear).hexdigest() != SHA:
        raise ValueError("Source trail clear identity mismatch")
    destination = Path(destination or ROOT / "App/Resources/FighterPrivate")
    if destination.is_symlink() or (destination / NAME).is_symlink():
        raise ValueError("Invalid source trail destination")
    envelope.write_atomic(destination / NAME, clear)
    print("One source trail file authenticated and staged; no plaintext upload.")


if __name__ == "__main__":
    if sys.argv[1:] != ["stage"]:
        raise SystemExit("Usage: fighter_source_trails.py stage")
    stage()
