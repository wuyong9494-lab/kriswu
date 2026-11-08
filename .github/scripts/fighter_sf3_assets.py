#!/usr/bin/env python3
"""Authenticate all personal-fighter/scenery chunks before staging any asset.

Uses the existing private fighter key. No network access or key output.
"""
import hashlib
import json
from pathlib import Path

import fighter_private_model as envelope

EXPECTED = {
    "Sun_FullBody_Prototype.glb": (
        7_953_392, "87b7b420206e1962e121eb49ac459b19144f66fef9590770b37849adc9576241"),
    "SF3_Palace_Exterior.glb": (
        9_292_540, "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"),
    "SF3_Autumn_Lobby.glb": (
        11_164_484, "616d5cb125f49c6b378cf280c90cf10e927b5b71aa461ecb34d7cdaad08c62c1"),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verified_assets(source):
    source = Path(source)
    manifest = json.loads((source / "manifest.json").read_text())
    if manifest.get("version") != 1:
        raise ValueError("Unsupported private asset manifest version")
    rows = manifest.get("assets", [])
    if len(rows) != len(EXPECTED) or {row["file"] for row in rows} != set(EXPECTED):
        raise ValueError("Missing or unexpected private asset")
    clear = {}
    for row in rows:
        name = row["file"]
        size, expected_digest = EXPECTED[name]
        purpose = "asset:" + name
        if (row["bytes"], row["sha256"], row["purpose"]) != (size, expected_digest, purpose):
            raise ValueError("Private asset identity mismatch")
        parts = row["parts"]
        if not 1 <= len(parts) <= 128:
            raise ValueError("Invalid private asset part count")
        blocks = []
        for index, part in enumerate(parts):
            expected_name = f"{name}.enc.{index:03}"
            if part["file"] != expected_name or not 1 <= part["bytes"] <= 512 * 1024:
                raise ValueError("Invalid private asset part identity")
            data = (source / expected_name).read_bytes()
            if len(data) != part["bytes"] or digest(data) != part["sha256"]:
                raise ValueError("Private asset part failed verification")
            blocks.append(data)
        ciphertext = b"".join(blocks)
        if digest(ciphertext) != row["cipher_sha256"]:
            raise ValueError("Private asset cipher digest mismatch")
        data = envelope.unseal(ciphertext, purpose)
        if len(data) != size or digest(data) != expected_digest:
            raise ValueError("Private asset clear digest mismatch")
        clear[name] = data
    return clear


def stage(source, destination):
    # A corrupt last asset must not leave earlier assets partially installed.
    assets = verified_assets(source)
    for name, data in assets.items():
        envelope.write_atomic(Path(destination) / name, data)
    print(f"Authenticated and staged {len(assets)} personal fighter/scenery assets")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    stage(root / ".github/private/sf3", root / "App/Resources/FighterPrivate")
