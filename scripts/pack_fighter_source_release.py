#!/usr/bin/env python3
"""Seal an already verified private fighter overlay as bounded AES-GCM shards.

Only ciphertext and its byte receipts are published. The 32-byte decryption
key is supplied through a private local file and is never copied to the pack,
logged, generated implicitly, or sent to any remote service by this script.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import zipfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sun_triad_assets import private_output, require

AAD = b"fighter-h17-d19-v1"
SHARD_BYTES = 1024 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def regular(path, maximum):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, "Expected a bounded regular input")
    return path.read_bytes()


def seal(args):
    require(not args.output.exists() and not args.output.is_symlink(), "Use a fresh private output directory for each release")
    output = private_output(args.output)
    key_info = args.key_file.lstat()
    require(stat.S_ISREG(key_info.st_mode) and key_info.st_mode & 0o077 == 0,
            "Asset key must be an owner-only regular file")
    key = base64.b64decode(regular(args.key_file, 128).strip(), validate=True)
    require(len(key) == 32, "Expected an existing base64-encoded 32-byte asset key")
    receipt = json.loads(regular(args.receipt, 2_000_000))
    files = receipt["files"]
    require(1 <= len(files) <= 512 and len({f["name"] for f in files}) == len(files), "Invalid resource inventory")
    require(sum(f["bytes"] for f in files) <= 160 * 1024**2, "Private resource bound exceeded")
    require(receipt["replacements"] == ["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"],
            "Unexpected baseline resource replacements")
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        for row in sorted(files, key=lambda f: f["name"]):
            name = row["name"]
            require(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", name) is not None and ".." not in name,
                    "Unsafe resource basename")
            data = regular(args.directory / name, 128_000_000)
            require(len(data) == row["bytes"] and digest(data) == row["sha256"], "Resource bytes changed after assembly")
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3; info.external_attr = 0o100444 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, data, compresslevel=6)
    clear = archive.getvalue()
    require(len(clear) + 28 <= 128 * 1024**2, "Private archive bound exceeded")
    release = next(f for f in files if f["name"] == "SF3_FighterRelease.json")
    require(release == receipt["release"], "Release receipt differs from its inventory")
    nonce = os.urandom(12)
    encrypted = nonce + AESGCM(key).encrypt(nonce, clear, AAD)
    # Verify the exact combined representation before publishing any shard.
    require(AESGCM(key).decrypt(encrypted[:12], encrypted[12:], AAD) == clear, "Local authenticated round trip failed")
    shards = []
    for index, offset in enumerate(range(0, len(encrypted), SHARD_BYTES)):
        data = encrypted[offset:offset + SHARD_BYTES]
        name = f"assets.part{index:03d}.enc"
        (output / name).write_bytes(data)
        shards.append(dict(file=name, encoding="binary", bytes=len(data), sha256=digest(data)))
    manifest = dict(version=1, purpose="h17-d19", algorithm="AES-256-GCM", aad=AAD.decode(),
        keyEncoding="base64-32", cipherLayout="nonce12-ciphertext-tag16",
        cipherBytes=len(encrypted), cipherSHA256=digest(encrypted), clearZIPBytes=len(clear), clearZIPSHA256=digest(clear),
        shards=shards, files=[dict(file=f["name"], bytes=f["bytes"], sha256=f["sha256"])
            for f in sorted(files, key=lambda f: f["name"])],
        replacements=receipt["replacements"], releaseSHA256=release["sha256"])
    encoded = (json.dumps(manifest, separators=(",", ":")) + "\n").encode()
    (output / "manifest.json").write_bytes(encoded)
    return dict(manifestSHA256=digest(encoded), releaseSHA256=release["sha256"],
        files=len(files), shards=len(shards), cipherBytes=len(encrypted),
        authenticatedRoundTrip=True, output=str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("directory", "receipt", "key-file", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(seal(parser.parse_args())))


if __name__ == "__main__": main()
