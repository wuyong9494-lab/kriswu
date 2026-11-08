#!/usr/bin/env python3
"""Authenticate both equipped fighters and original feedback before staging.

Only encrypted chunks and integrity metadata live in the public repository.
The already-authorized FIGHTER_LIU_MODEL_KEY is consumed by the envelope helper.
"""
import hashlib
import io
import json
import re
import stat
import zipfile
from pathlib import Path

import fighter_private_model as envelope

SIZE = 16_499_513
SHA256 = "1b228965b08c5d1b6cc659426722705a1ea734a906e183082d6556bde3fc18a8"
FILE_COUNT = 61
PURPOSE = "asset:SF3_DistinctFighters.zip"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verified_assets(source, expected_size=SIZE, expected_sha=SHA256, expected_count=FILE_COUNT):
    source = Path(source)
    manifest = json.loads((source / "manifest.json").read_text())
    if (manifest.get("version"), manifest.get("purpose"), manifest.get("bytes"), manifest.get("sha256")) != (
            1, PURPOSE, expected_size, expected_sha):
        raise ValueError("Distinct fighter archive identity mismatch")
    parts = manifest.get("parts", [])
    if not 1 <= len(parts) <= 128:
        raise ValueError("Invalid distinct fighter part count")
    blocks = []
    for index, part in enumerate(parts):
        name = f"distinct.pack.enc.{index:03}"
        if part.get("file") != name or not 1 <= part.get("bytes", 0) <= 512 * 1024:
            raise ValueError("Invalid distinct fighter part identity")
        path = source / name
        if path.is_symlink():
            raise ValueError("Encrypted parts cannot be symbolic links")
        data = path.read_bytes()
        if len(data) != part["bytes"] or digest(data) != part.get("sha256"):
            raise ValueError("Distinct fighter part verification failed")
        blocks.append(data)
    ciphertext = b"".join(blocks)
    if digest(ciphertext) != manifest.get("cipher_sha256"):
        raise ValueError("Distinct fighter ciphertext verification failed")
    clear = envelope.unseal(ciphertext, PURPOSE)
    if len(clear) != expected_size or digest(clear) != expected_sha:
        raise ValueError("Distinct fighter clear archive verification failed")
    files = manifest.get("files", [])
    if len(files) != expected_count or len({row["file"] for row in files}) != expected_count:
        raise ValueError("Unexpected distinct fighter file set")
    expected = {row["file"]: row for row in files}
    result = {}
    pattern = r"(?:Sun_Herald_Katana\.glb|Liu_Legion_Hammers\.glb|SF3_DistinctFighters\.json|SF3(?:UI|FX|WE)_[A-Za-z0-9_]+\.(?:json|png|wav))"
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        entries = archive.infolist()
        if len(entries) != expected_count or {entry.filename for entry in entries} != set(expected):
            raise ValueError("Missing, extra or duplicate distinct fighter ZIP entry")
        if sum(entry.file_size for entry in entries) > 64_000_000:
            raise ValueError("Distinct fighter archive exceeds clear byte budget")
        for entry in entries:
            name = entry.filename
            if not re.fullmatch(pattern, name):
                raise ValueError("Unsafe distinct fighter file name")
            if stat.S_ISLNK(entry.external_attr >> 16) or entry.is_dir():
                raise ValueError("Distinct fighter entry must be a regular file")
            data = archive.read(entry)
            row = expected[name]
            if len(data) != row["bytes"] or digest(data) != row["sha256"]:
                raise ValueError("Distinct fighter resource verification failed")
            result[name] = data
    return result


def stage(source, destination):
    assets = verified_assets(source)
    destination = Path(destination)
    for name in assets:
        if (destination / name).is_symlink():
            raise ValueError("Distinct fighter destination cannot be a symbolic link")
    for name, data in assets.items():
        envelope.write_atomic(destination / name, data)
    print(f"Authenticated and staged {len(assets)} distinct fighter and source feedback files")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    stage(root / ".github/private/sf3-distinct", root / "App/Resources/FighterPrivate")
