#!/usr/bin/env python3
"""Authenticate the small optional presentation pack; never print its key.

No new recipient or protection bypass. The new key is a separate environment
secret. Existing model and scenery envelopes/keys remain unchanged.
"""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import zipfile

import fighter_private_model as envelope

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / ".github/private/fighter-presentation/manifest.json"
MANIFEST_NAME = "Fidelity_presentation.json"
MANIFEST_SHA = "0ca27c39b7d65086dfd391b4716186b819c25e0933165b6df6ba1a4e09d63feb"
ALLOWED = {f"Fidelity_mask_{i}.png" for i in range(4)} | {
    "Fidelity_matcap_palace.png", "Fidelity_matcap_autumn.png", "liu_shadow_callout.wav", MANIFEST_NAME}
CAP = 3_000_000


def authenticate(clear, rows):
    if not 0 < len(clear) <= CAP or len(rows) != 8 or {r["file"] for r in rows} != ALLOWED:
        raise ValueError("Unexpected presentation inventory")
    expected = {r["file"]: r for r in rows}
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        infos = archive.infolist()
        if len(infos) != 8 or {i.filename for i in infos} != ALLOWED:
            raise ValueError("Unexpected presentation archive entries")
        payload = {}
        for info in infos:
            row = expected[info.filename]
            mode = info.external_attr >> 16
            if (info.is_dir() or stat.S_ISLNK(mode) or info.flag_bits & 1 or
                    info.compress_type != zipfile.ZIP_STORED or
                    not 0 < info.file_size == row["bytes"] <= CAP):
                raise ValueError("Invalid presentation entry")
            data = archive.read(info)
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                raise ValueError("Presentation entry integrity mismatch")
            payload[info.filename] = data
    if hashlib.sha256(payload[MANIFEST_NAME]).hexdigest() != MANIFEST_SHA:
        raise ValueError("Unexpected presentation runtime manifest")
    runtime = json.loads(payload[MANIFEST_NAME])
    if {r["name"] for r in runtime["files"]} != ALLOWED - {MANIFEST_NAME}:
        raise ValueError("Runtime inventory mismatch")
    for row in runtime["files"]:
        data = payload[row["name"]]
        if len(data) != row["bytes"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
            raise ValueError("Runtime payload mismatch")
    return payload


def stage(destination=None):
    manifest = json.loads(MANIFEST.read_text())
    path = MANIFEST.parent / "presentation-v1.enc.b64"
    if path.is_symlink() or not 0 < path.stat().st_size <= CAP * 2:
        raise ValueError("Invalid presentation ciphertext file")
    cipher = base64.b64decode(path.read_bytes(), validate=True)
    if len(cipher) != manifest["cipherBytes"] or hashlib.sha256(cipher).hexdigest() != manifest["cipherSHA256"]:
        raise ValueError("Presentation ciphertext integrity mismatch")
    value = os.environ.get("FIGHTER_PRESENTATION_KEY", "")
    if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("Private presentation key is missing or malformed")
    original = os.environ.get("FIGHTER_LIU_MODEL_KEY")
    try:
        os.environ["FIGHTER_LIU_MODEL_KEY"] = value
        clear = envelope.unseal(cipher, "presentation-v1")
    finally:
        if original is None:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
        else:
            os.environ["FIGHTER_LIU_MODEL_KEY"] = original
    if len(clear) != manifest["archiveBytes"] or hashlib.sha256(clear).hexdigest() != manifest["archiveSHA256"]:
        raise ValueError("Presentation archive integrity mismatch")
    payload = authenticate(clear, manifest["files"])
    destination = destination or ROOT / "App/Resources/FighterPrivate"
    if destination.is_symlink():
        raise ValueError("Presentation destination cannot be a symlink")
    destination.mkdir(parents=True, exist_ok=True)
    # Validate everything before the first write. Publish the runtime manifest
    # last so an interrupted staging attempt cannot declare a complete new pack.
    for name in sorted(ALLOWED - {MANIFEST_NAME}) + [MANIFEST_NAME]:
        target = destination / name
        if target.is_symlink():
            raise ValueError("Presentation target cannot be a symlink")
    for name in sorted(ALLOWED - {MANIFEST_NAME}) + [MANIFEST_NAME]:
        envelope.write_atomic(destination / name, payload[name])
    print("Eight presentation files authenticated and staged; no plaintext upload.")


if __name__ == "__main__":
    if sys.argv[1:] != ["stage"]:
        raise SystemExit("Usage: fighter_presentation_assets.py stage")
    stage()
