#!/usr/bin/env python3
"""Seal/apply the reviewed 13-payload shared-root and floorfall delta.

The original 295-file encrypted release remains the independent prerequisite.
Only a new GLB JSON chunk/BIN suffix and three catalog clips are transported;
the verified original model BIN and catalog are reconstructed locally. This
tool cannot upload, select a build pin, create a key or alter remote secrets.
"""
from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path
import re
import stat
import sys
import zipfile

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

import stage_h17_shared_root_release as stage
from seal_h17_floorfall_delta import read_key
from stage_h17_floorfall_release import (
    BASE_PACK_SHA, BASE_RELEASE_SHA, MAX_TOTAL, RELEASE_NAME, AUDIO_NAME,
    checked_file, digest, encoded, fresh_output, parse_json, real_directory,
    record, regular, require, safe_name, write_private,
)


DELTA_SHA = "dd08d99764fcbba6f791e1db941b9eb607e715f40ade2faf8b8bdf0051365765"
TARGET_RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
AAD = b"fighter-h17-shared-root-delta-v1"
MAX_TRANSPORT_BYTES = 8 * 1024 * 1024
MAX_METADATA_BYTES = 32_768
DELTA_NAME = "delta-manifest.json"
CIPHER_NAME = "shared-root.delta.enc"
SEALED_SCHEMA = "fighter-h17-shared-root-sealed-delta-v1"


def hex_digest(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def validate_row(row, maximum):
    require(isinstance(row, dict) and set(row) == {"name", "bytes", "sha256"}, "Unexpected inventory fields")
    safe_name(row["name"])
    require(type(row["bytes"]) is int and 0 < row["bytes"] <= maximum and hex_digest(row["sha256"]),
            "Inventory byte/hash bound differs")
    return row


def validate_rows(rows, names, per_file, total):
    require(isinstance(rows, list) and len(rows) == len(names), "Inventory count differs")
    found = [validate_row(row, per_file)["name"] for row in rows]
    require(found == sorted(names) and len(set(found)) == len(found), "Inventory names/order differ")
    require(sum(row["bytes"] for row in rows) <= total, "Inventory exceeds its total byte bound")


def delta_document(raw):
    require(0 < len(raw) <= MAX_METADATA_BYTES and digest(raw) == DELTA_SHA,
            "Delta differs from the independently reviewed input")
    delta = parse_json(raw)
    require(set(delta) == {"schema", "basePackManifestSHA256", "baseReleaseSHA256", "sourceFloorfallReleaseSHA256",
            "targetRelease", "replacements", "additions", "files", "payloads", "transforms",
            "unchangedBaseFiles", "requiresIndependentSignedBuildPin", "encrypted", "uploaded"}
            and delta["schema"] == "fighter-h17-shared-root-delta-v1"
            and delta["basePackManifestSHA256"] == BASE_PACK_SHA
            and delta["baseReleaseSHA256"] == BASE_RELEASE_SHA
            and delta["sourceFloorfallReleaseSHA256"] == stage.FLOORFALL_RELEASE_SHA
            and delta["targetRelease"]["sha256"] == TARGET_RELEASE_SHA
            and delta["targetRelease"]["name"] == RELEASE_NAME
            and delta["replacements"] == stage.REPLACEMENTS
            and delta["additions"] == sorted(stage.FLOORFALL_NAMES)
            and delta["unchangedBaseFiles"] == 289
            and delta["requiresIndependentSignedBuildPin"] is True
            and delta["encrypted"] is False and delta["uploaded"] is False,
            "Delta cannot authorize its own identities or replacement scope")
    target_names = set(stage.REPLACEMENTS) | set(stage.FLOORFALL_NAMES)
    payload_names = (target_names - {stage.CHARACTER_NAME, stage.CATALOG_NAME}
                     | {stage.GLB_PATCH_NAME, stage.CATALOG_PATCH_NAME})
    require(len(target_names) == len(payload_names) == 13, "Expected exactly thirteen changes and payloads")
    validate_rows(delta["files"], target_names, 32_000_000, MAX_TOTAL)
    validate_rows(delta["payloads"], payload_names, stage.MAX_PATCH, MAX_TRANSPORT_BYTES)
    target = {row["name"]: row for row in delta["files"]}
    payloads = {row["name"]: row for row in delta["payloads"]}
    require(target[RELEASE_NAME] == delta["targetRelease"]
            and all(target[name] == payloads[name] for name in target_names & payload_names),
            "Raw payload/target inventory differs")
    transforms = delta["transforms"]
    require(isinstance(transforms, list) and len(transforms) == 2, "Expected exactly two local reconstructions")
    glb, catalog = transforms
    require(set(glb) == {"kind", "target", "payload", "base", "retainedBINBytes", "retainedBINSHA256",
            "jsonChunkBytes", "jsonChunkSHA256", "appendedBINBytes", "appendedBINSHA256"}
            and glb["kind"] == "glb-bin-append-v1" and glb["target"] == stage.CHARACTER_NAME
            and glb["payload"] == stage.GLB_PATCH_NAME
            and validate_row(glb["base"], 32_000_000)["name"] == stage.CHARACTER_NAME
            and glb["base"]["sha256"] == stage.OLD_CHARACTER_SHA,
            "GLB transform contract differs")
    for name in ("retainedBIN", "jsonChunk", "appendedBIN"):
        require(type(glb[name + "Bytes"]) is int and 0 < glb[name + "Bytes"] <= 32_000_000
                and hex_digest(glb[name + "SHA256"]), "GLB chunk bounds differ")
    require(24 + glb["jsonChunkBytes"] + glb["appendedBINBytes"] == payloads[stage.GLB_PATCH_NAME]["bytes"]
            and 28 + glb["retainedBINBytes"] + glb["jsonChunkBytes"] + glb["appendedBINBytes"]
                == target[stage.CHARACTER_NAME]["bytes"], "GLB reconstruction byte count differs")
    require(set(catalog) == {"kind", "target", "payload", "base", "priorClipCount", "appendedClips"}
            and catalog["kind"] == "catalog-three-clip-append-v1" and catalog["target"] == stage.CATALOG_NAME
            and catalog["payload"] == stage.CATALOG_PATCH_NAME
            and validate_row(catalog["base"], 32_000_000)["name"] == stage.CATALOG_NAME
            and catalog["base"]["sha256"] == stage.CATALOG_SHA and catalog["priorClipCount"] == 56
            and catalog["appendedClips"] == [clip["name"] for clip in stage.CLIPS],
            "Catalog transform contract differs")
    return delta


def zip_bytes(payloads):
    result = io.BytesIO()
    with zipfile.ZipFile(result, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, raw in sorted(payloads.items()):
            info = zipfile.ZipInfo(safe_name(name), date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100600 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, raw, compresslevel=6)
    return result.getvalue()


def seal(directory, delta_path, key_path, output):
    output = fresh_output(output)
    directory = real_directory(directory)
    output = fresh_output(output, (directory,))
    raw = regular(delta_path, MAX_METADATA_BYTES)
    delta = delta_document(raw)
    require({path.name for path in directory.iterdir()} == {row["name"] for row in delta["payloads"]},
            "Delta directory must contain only its thirteen reviewed payloads")
    payloads = {row["name"]: checked_file(directory, row) for row in delta["payloads"]}
    payloads[DELTA_NAME] = raw
    require(sum(len(value) for value in payloads.values()) <= MAX_TRANSPORT_BYTES,
            "Expanded ZIP exceeds its byte bound")
    clear = zip_bytes(payloads)
    require(len(clear) <= MAX_TRANSPORT_BYTES, "Compressed ZIP exceeds its byte bound")
    # All pins, member bounds, directory closure and output safety precede key access.
    key = read_key(key_path)
    nonce = os.urandom(12)
    cipher = nonce + AESGCM(key).encrypt(nonce, clear, AAD)
    require(AESGCM(key).decrypt(cipher[:12], cipher[12:], AAD) == clear,
            "Authenticated local round trip failed")
    key = b""
    manifest = dict(schema=SEALED_SCHEMA, algorithm="AES-256-GCM", aad=AAD.decode(),
        cipherLayout="nonce12-ciphertext-tag16", keyEncoding="base64-32",
        basePackManifestSHA256=BASE_PACK_SHA, baseReleaseSHA256=BASE_RELEASE_SHA,
        targetReleaseSHA256=TARGET_RELEASE_SHA, deltaManifestSHA256=DELTA_SHA,
        cipher=record(CIPHER_NAME, cipher), clearZIPBytes=len(clear), clearZIPSHA256=digest(clear),
        payloadFiles=delta["payloads"], targetFiles=delta["files"], unchangedBaseFiles=289,
        requiresIndependentSignedBuildPin=True)
    manifest_raw = encoded(manifest)
    output.mkdir(mode=0o700)
    write_private(output / CIPHER_NAME, cipher)
    write_private(output / "manifest.json", manifest_raw)
    return dict(manifestSHA256=digest(manifest_raw), targetReleaseSHA256=TARGET_RELEASE_SHA,
                deltaManifestSHA256=DELTA_SHA, cipherBytes=len(cipher), payloadFiles=13,
                targetResourceChanges=13, authenticatedRoundTrip=True,
                uploaded=False, secretDestinationChanged=False)


def decoded_payloads(clear):
    require(0 < len(clear) <= MAX_TRANSPORT_BYTES, "Compressed ZIP exceeds its byte bound")
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        members = archive.infolist()
        names = [safe_name(member.filename) for member in members]
        require(len(names) == len(set(names)) == 14 and DELTA_NAME in names,
                "Expected thirteen unique payloads plus one authenticated delta manifest")
        require(sum(member.file_size for member in members) <= MAX_TRANSPORT_BYTES,
                "Expanded ZIP exceeds its byte bound")
        for member in members:
            require(stat.S_ISREG(member.external_attr >> 16) and not member.flag_bits & 1
                    and member.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    and 0 < member.file_size <= stage.MAX_PATCH,
                    "Unsupported or oversized ZIP member")
        require(archive.getinfo(DELTA_NAME).file_size <= MAX_METADATA_BYTES,
                "Delta manifest exceeds its byte bound")
        delta = delta_document(archive.read(DELTA_NAME))
        require(set(names) == {DELTA_NAME} | {row["name"] for row in delta["payloads"]},
                "Unexpected ZIP member set")
        payloads = {}
        for row in delta["payloads"]:
            member = archive.getinfo(row["name"])
            require(member.file_size == row["bytes"], "ZIP member size differs from reviewed inventory")
            value = archive.read(member)
            require(record(row["name"], value) == row, "ZIP member differs from reviewed bytes")
            payloads[row["name"]] = value
    return delta, payloads


def reconstruct(delta, payloads, base_directory, inventory):
    require(set(delta["replacements"]) <= set(inventory)
            and not set(delta["additions"]) & set(inventory), "Resource additions collide with the base")
    expected_payloads = {row["name"]: row for row in delta["payloads"]}
    require(set(payloads) == set(expected_payloads)
            and all(record(name, raw) == expected_payloads[name] for name, raw in payloads.items()),
            "Reconstruction payload closure differs")
    changed = {name: raw for name, raw in payloads.items()
               if name not in (stage.GLB_PATCH_NAME, stage.CATALOG_PATCH_NAME)}
    for transform in delta["transforms"]:
        name = transform["target"]
        require(transform["base"] == inventory[name], "Reconstruction base pin differs")
        old = checked_file(base_directory, inventory[name])
        if name == stage.CHARACTER_NAME:
            value = stage.rebuild_glb(old, payloads[transform["payload"]])
            old_bin, new_json, suffix = stage.validate_glb_append(old, value)
            for prefix, raw in (("retainedBIN", old_bin), ("jsonChunk", new_json), ("appendedBIN", suffix)):
                require(len(raw) == transform[prefix + "Bytes"] and digest(raw) == transform[prefix + "SHA256"],
                        "Reconstructed GLB chunk receipt differs")
        elif name == stage.CATALOG_NAME:
            value = stage.rebuild_catalog(old, payloads[transform["payload"]])
        else:
            raise ValueError("Unknown reconstruction transform")
        changed[name] = value
    target = {row["name"]: row for row in delta["files"]}
    require(set(changed) == set(target)
            and all(record(name, raw) == target[name] for name, raw in changed.items()),
            "Reconstructed resource differs from the reviewed target")
    final = dict(inventory, **target)
    require(len(final) == 302 and sum(row["bytes"] for row in final.values()) <= MAX_TOTAL,
            "Final resource inventory exceeds its bound")
    return changed, final


def envelope(raw, manifest_sha):
    require(hex_digest(manifest_sha) and digest(raw) == manifest_sha,
            "Encrypted manifest differs from the independently supplied build pin")
    value = parse_json(raw)
    require(set(value) == {"schema", "algorithm", "aad", "cipherLayout", "keyEncoding",
            "basePackManifestSHA256", "baseReleaseSHA256", "targetReleaseSHA256", "deltaManifestSHA256",
            "cipher", "clearZIPBytes", "clearZIPSHA256", "payloadFiles", "targetFiles",
            "unchangedBaseFiles", "requiresIndependentSignedBuildPin"}
            and value["schema"] == SEALED_SCHEMA and value["algorithm"] == "AES-256-GCM"
            and value["aad"] == AAD.decode() and value["cipherLayout"] == "nonce12-ciphertext-tag16"
            and value["keyEncoding"] == "base64-32" and value["basePackManifestSHA256"] == BASE_PACK_SHA
            and value["baseReleaseSHA256"] == BASE_RELEASE_SHA and value["targetReleaseSHA256"] == TARGET_RELEASE_SHA
            and value["deltaManifestSHA256"] == DELTA_SHA and value["unchangedBaseFiles"] == 289
            and value["requiresIndependentSignedBuildPin"] is True,
            "Encrypted manifest identities or contract differ")
    require(validate_row(value["cipher"], MAX_TRANSPORT_BYTES + 28)["name"] == CIPHER_NAME
            and value["cipher"]["bytes"] > 28 and type(value["clearZIPBytes"]) is int
            and 0 < value["clearZIPBytes"] <= MAX_TRANSPORT_BYTES
            and value["clearZIPBytes"] + 28 == value["cipher"]["bytes"]
            and hex_digest(value["clearZIPSHA256"]), "Encrypted/clear ZIP bounds differ")
    targets = set(stage.REPLACEMENTS) | set(stage.FLOORFALL_NAMES)
    payloads = targets - {stage.CHARACTER_NAME, stage.CATALOG_NAME} | {stage.GLB_PATCH_NAME, stage.CATALOG_PATCH_NAME}
    validate_rows(value["targetFiles"], targets, 32_000_000, MAX_TOTAL)
    validate_rows(value["payloadFiles"], payloads, stage.MAX_PATCH, MAX_TRANSPORT_BYTES)
    return value


def apply(directory, manifest_path, manifest_sha, base_directory, base_manifest_path, key_path, output):
    output = fresh_output(output)
    directory, base_directory = map(real_directory, (directory, base_directory))
    output = fresh_output(output, (directory, base_directory))
    manifest = envelope(regular(manifest_path, MAX_METADATA_BYTES), manifest_sha)
    cipher = checked_file(directory, manifest["cipher"])
    base_raw = regular(base_manifest_path, 2_000_000)
    require(digest(base_raw) == BASE_PACK_SHA, "Base package manifest differs from its independent pin")
    inventory = stage.inventory_from_pack(parse_json(base_raw))
    require({path.name for path in base_directory.iterdir()} == set(inventory), "Base directory closure differs")
    # Verify every original resource before reading a key or producing output.
    for row in inventory.values():
        checked_file(base_directory, row)
    key = read_key(key_path)
    clear = AESGCM(key).decrypt(cipher[:12], cipher[12:], AAD)
    key = b""
    require(len(clear) == manifest["clearZIPBytes"] and digest(clear) == manifest["clearZIPSHA256"],
            "Authenticated ZIP differs from its encrypted receipt")
    delta, payloads = decoded_payloads(clear)
    require(delta["payloads"] == manifest["payloadFiles"] and delta["files"] == manifest["targetFiles"],
            "Encrypted and authenticated resource inventories differ")
    changed, target = reconstruct(delta, payloads, base_directory, inventory)
    output.mkdir(mode=0o700)
    for name in sorted(target):
        write_private(output / name, changed[name] if name in changed else checked_file(base_directory, inventory[name]))
    return dict(baseReleaseSHA256=BASE_RELEASE_SHA, targetReleaseSHA256=TARGET_RELEASE_SHA,
                files=len(target), unchangedFiles=289, deltaFiles=13, payloadFiles=13,
                totalBytes=sum(row["bytes"] for row in target.values()),
                buildSetting={"FIGHTER_ASSET_RELEASE_SHA256": TARGET_RELEASE_SHA},
                uploaded=False, secretDestinationChanged=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    sealing = modes.add_parser("seal")
    for name in ("directory", "delta-manifest", "key-file", "output"):
        sealing.add_argument("--" + name, type=Path, required=True)
    applying = modes.add_parser("apply")
    for name in ("directory", "manifest", "base-directory", "base-manifest", "key-file", "output"):
        applying.add_argument("--" + name, type=Path, required=True)
    applying.add_argument("--manifest-sha256", required=True)
    args = parser.parse_args()
    try:
        if args.mode == "seal":
            result = seal(args.directory, args.delta_manifest, args.key_file, args.output)
        else:
            result = apply(args.directory, args.manifest, args.manifest_sha256, args.base_directory,
                           args.base_manifest, args.key_file, args.output)
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, InvalidTag) as error:
        print(json.dumps(dict(completed=False, errorType=type(error).__name__)), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
