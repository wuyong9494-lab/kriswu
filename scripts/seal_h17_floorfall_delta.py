#!/usr/bin/env python3
"""Seal/apply only the reviewed nine-file H17 floorfall resource delta.

The existing 295-file package is an independent prerequisite. This utility
does not download, upload, create keys, change a secret destination, or select
the application's build pin. Callers must obtain the encrypted manifest pin
from their reviewed build configuration, not from an untrusted package.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import zipfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from stage_h17_floorfall_release import (
    BASE_PACK_SHA, BASE_RELEASE_SHA, RELEASE_NAME, AUDIO_NAME,
    checked_file, encoded, parse_json, real_directory, record, regular,
    require, safe_name,
)


ROOT = Path(__file__).resolve().parents[1]
DELTA_SHA = "da980ab998acaa85fb828d320a9fc3aec4cff6457145644bd94287f0c84000fb"
TARGET_RELEASE_SHA = "fc85891d75aef9b236270e801d9d6d43661ff0f86fde812d4d1aa7996bc9ebbf"
AAD = b"fighter-h17-floorfall-delta-v1"
MAX_DELTA_BYTES = 2 * 1024 * 1024
DELTA_NAME = "delta-manifest.json"
CIPHER_NAME = "floorfall.delta.enc"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def fresh_private_output(path):
    path = Path(path).absolute()
    require(not path.exists() and not path.is_symlink(), "Output already exists; do not repeat a successful operation")
    require(path.parent.is_dir() and path.parent.resolve(strict=True) == path.parent,
            "Output parent must already exist without symbolic links")
    require(not path.is_relative_to(ROOT), "Plaintext and key-bearing work must remain outside the repository")
    return path


def write_private(path, raw):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(raw)


def read_key(path):
    path = Path(path).absolute()
    require(path.resolve(strict=True) == path, "Key path must not use symbolic links")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_mode & 0o077 == 0 and 0 < info.st_size <= 128,
                "Use an existing owner-only key file")
        value = handle.read(129).strip()
    try:
        key = base64.b64decode(value, validate=True)
    except ValueError:
        raise ValueError("Malformed asset key") from None
    require(len(key) == 32 and base64.b64encode(key) == value, "Expected a canonical 32-byte asset key")
    return key


def delta_document(raw):
    require(digest(raw) == DELTA_SHA, "Delta differs from the reviewed input")
    delta = parse_json(raw)
    require(delta["schema"] == "fighter-h17-audio-delta-v1"
            and delta["basePackManifestSHA256"] == BASE_PACK_SHA
            and delta["baseReleaseSHA256"] == BASE_RELEASE_SHA
            and delta["targetRelease"]["sha256"] == TARGET_RELEASE_SHA
            and delta["targetRelease"]["name"] == RELEASE_NAME
            and delta["replacements"] == [RELEASE_NAME, AUDIO_NAME]
            and delta["requiresIndependentSignedBuildPin"] is True,
            "Delta cannot authorize its own base, target or replacements")
    rows = delta["files"]
    names = [safe_name(row["name"]) for row in rows]
    require(len(rows) == 9 and len(set(names)) == 9 and names == sorted(names), "Expected exactly nine unique payloads")
    require(set(names) == set(delta["additions"]) | set(delta["replacements"])
            and len(delta["additions"]) == 7 and len(set(delta["additions"])) == 7
            and all(name.endswith(".wav") for name in delta["additions"]),
            "Unexpected resource additions")
    require(all(type(row["bytes"]) is int and 0 < row["bytes"] <= MAX_DELTA_BYTES for row in rows)
            and sum(row["bytes"] for row in rows) <= MAX_DELTA_BYTES,
            "Delta exceeds its bounded payload budget")
    require(next(row for row in rows if row["name"] == RELEASE_NAME) == delta["targetRelease"],
            "Target release inventory differs")
    return delta


def zip_bytes(payloads):
    target = io.BytesIO()
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, raw in sorted(payloads.items()):
            info = zipfile.ZipInfo(safe_name(name), date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100600 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, raw, compresslevel=6)
    return target.getvalue()


def seal(directory, delta_path, key_path, output):
    output = fresh_private_output(output)
    directory = real_directory(directory)
    raw = regular(delta_path, 32_768)
    delta = delta_document(raw)
    expected = {row["name"] for row in delta["files"]}
    require({p.name for p in directory.iterdir()} == expected, "Delta directory must contain only its nine reviewed files")
    payloads = {row["name"]: checked_file(directory, row) for row in delta["files"]}
    payloads[DELTA_NAME] = raw
    clear = zip_bytes(payloads)
    require(len(clear) <= MAX_DELTA_BYTES, "Delta ZIP exceeds its bound")
    key = read_key(key_path)
    nonce = os.urandom(12)
    cipher = nonce + AESGCM(key).encrypt(nonce, clear, AAD)
    require(AESGCM(key).decrypt(cipher[:12], cipher[12:], AAD) == clear,
            "Authenticated local round trip failed")
    key = b""
    manifest = {
        "schema": "fighter-h17-floorfall-sealed-delta-v1", "algorithm": "AES-256-GCM",
        "aad": AAD.decode(), "cipherLayout": "nonce12-ciphertext-tag16", "keyEncoding": "base64-32",
        "basePackManifestSHA256": BASE_PACK_SHA, "baseReleaseSHA256": BASE_RELEASE_SHA,
        "targetReleaseSHA256": TARGET_RELEASE_SHA, "deltaManifestSHA256": DELTA_SHA,
        "cipher": record(CIPHER_NAME, cipher), "clearZIPBytes": len(clear), "clearZIPSHA256": digest(clear),
        "payloadFiles": delta["files"], "unchangedBaseFiles": delta["unchangedBaseFiles"],
        "requiresIndependentSignedBuildPin": True,
    }
    manifest_bytes = encoded(manifest)
    os.mkdir(output, 0o700)
    write_private(output / CIPHER_NAME, cipher)
    write_private(output / "manifest.json", manifest_bytes)
    return {"manifestSHA256": digest(manifest_bytes), "targetReleaseSHA256": TARGET_RELEASE_SHA,
            "cipherBytes": len(cipher), "payloadFiles": 9, "authenticatedRoundTrip": True,
            "uploaded": False, "secretDestinationChanged": False}


def decoded_payloads(clear):
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        members = archive.infolist()
        names = [safe_name(member.filename) for member in members]
        require(len(names) == 10 and len(set(names)) == 10 and DELTA_NAME in names,
                "Expected nine payloads plus one authenticated delta manifest")
        require(sum(member.file_size for member in members) <= MAX_DELTA_BYTES,
                "Expanded delta exceeds its bound")
        for member in members:
            mode = member.external_attr >> 16
            require(stat.S_ISREG(mode) and member.compress_type in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]
                    and not member.flag_bits & 1 and 0 < member.file_size <= MAX_DELTA_BYTES,
                    "Unsupported ZIP member")
        raw = archive.read(DELTA_NAME)
        delta = delta_document(raw)
        require(set(names) == {DELTA_NAME} | {row["name"] for row in delta["files"]}, "Unexpected ZIP payload")
        payloads = {}
        for row in delta["files"]:
            member = archive.getinfo(row["name"])
            require(member.file_size == row["bytes"], "ZIP size differs from reviewed payload")
            value = archive.read(member)
            require(record(row["name"], value) == row, "ZIP payload differs from reviewed bytes")
            payloads[row["name"]] = value
    return delta, payloads


def apply(directory, manifest_path, manifest_sha, base_directory, base_manifest_path, key_path, output):
    output = fresh_private_output(output)
    directory = real_directory(directory)
    base_directory = real_directory(base_directory)
    raw = regular(manifest_path, 32_768)
    require(len(manifest_sha) == 64 and digest(raw) == manifest_sha,
            "Encrypted manifest differs from the independently supplied pin")
    manifest = parse_json(raw)
    require(manifest["schema"] == "fighter-h17-floorfall-sealed-delta-v1"
            and manifest["algorithm"] == "AES-256-GCM" and manifest["aad"] == AAD.decode()
            and manifest["cipherLayout"] == "nonce12-ciphertext-tag16"
            and manifest["keyEncoding"] == "base64-32"
            and manifest["basePackManifestSHA256"] == BASE_PACK_SHA
            and manifest["baseReleaseSHA256"] == BASE_RELEASE_SHA
            and manifest["targetReleaseSHA256"] == TARGET_RELEASE_SHA
            and manifest["deltaManifestSHA256"] == DELTA_SHA
            and manifest["requiresIndependentSignedBuildPin"] is True,
            "Encrypted manifest identity is not reviewed")
    require(manifest["cipher"]["name"] == CIPHER_NAME
            and type(manifest["cipher"]["bytes"]) is int
            and 28 < manifest["cipher"]["bytes"] <= MAX_DELTA_BYTES + 28,
            "Cipher bound is invalid")
    cipher = checked_file(directory, manifest["cipher"])
    base_raw = regular(base_manifest_path, 2_000_000)
    require(digest(base_raw) == BASE_PACK_SHA, "Base package manifest changed")
    base_manifest = parse_json(base_raw)
    require(base_manifest["releaseSHA256"] == BASE_RELEASE_SHA, "Wrong base release")
    base_rows = [{"name": row["file"], "bytes": row["bytes"], "sha256": row["sha256"]}
                 for row in base_manifest["files"]]
    require(len(base_rows) == 295 and len({row["name"] for row in base_rows}) == 295
            and sum(row["bytes"] for row in base_rows) <= 160 * 1024**2,
            "Unexpected base resource inventory")
    require({p.name for p in base_directory.iterdir()} == {row["name"] for row in base_rows},
            "Base directory is not the reviewed overlay")
    # Validate the complete immutable base before decrypting or writing output.
    for row in base_rows:
        checked_file(base_directory, row)
    key = read_key(key_path)
    clear = AESGCM(key).decrypt(cipher[:12], cipher[12:], AAD)
    key = b""
    require(type(manifest["clearZIPBytes"]) is int and 0 < len(clear) <= MAX_DELTA_BYTES
            and len(clear) == manifest["clearZIPBytes"] and digest(clear) == manifest["clearZIPSHA256"],
            "Authenticated ZIP differs from its reviewed receipt")
    delta, payloads = decoded_payloads(clear)
    require(delta["files"] == manifest["payloadFiles"] and delta["unchangedBaseFiles"] == 293
            and manifest["unchangedBaseFiles"] == 293, "Delta metadata differs across authenticated envelopes")
    base_names = {row["name"] for row in base_rows}
    require(set(delta["replacements"]) <= base_names and not set(delta["additions"]) & base_names,
            "Unexpected base collision")
    # Every destination is fresh, all members have safe flat names, and the
    # target release pin remains external to both archive and resource folder.
    os.mkdir(output, 0o700)
    target_rows = []
    for row in base_rows:
        if row["name"] in delta["replacements"]:
            continue
        value = checked_file(base_directory, row)
        write_private(output / row["name"], value)
        target_rows.append(row)
    for row in delta["files"]:
        write_private(output / row["name"], payloads[row["name"]])
        target_rows.append(row)
    require(len(target_rows) == 302, "Unexpected installed resource count")
    return {"baseReleaseSHA256": BASE_RELEASE_SHA, "targetReleaseSHA256": TARGET_RELEASE_SHA,
            "files": len(target_rows), "unchangedFiles": 293, "deltaFiles": 9,
            "totalBytes": sum(row["bytes"] for row in target_rows),
            "buildSetting": {"FIGHTER_ASSET_RELEASE_SHA256": TARGET_RELEASE_SHA},
            "uploaded": False, "secretDestinationChanged": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    sealing = modes.add_parser("seal")
    for name in ["directory", "delta-manifest", "key-file", "output"]:
        sealing.add_argument("--" + name, type=Path, required=True)
    applying = modes.add_parser("apply")
    for name in ["directory", "manifest", "base-directory", "base-manifest", "key-file", "output"]:
        applying.add_argument("--" + name, type=Path, required=True)
    applying.add_argument("--manifest-sha256", required=True)
    args = parser.parse_args()
    if args.mode == "seal":
        result = seal(args.directory, args.delta_manifest, args.key_file, args.output)
    else:
        result = apply(args.directory, args.manifest, args.manifest_sha256,
                       args.base_directory, args.base_manifest, args.key_file, args.output)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
