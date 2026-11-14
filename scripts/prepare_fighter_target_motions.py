#!/usr/bin/env python3
"""Prepare verified Ninjato/H17 source motion privately; export provenance only.

Input is the previously saved Android 1.45.3 source archive, pinned below.
This is not a gameplay interpreter: frame rate, contacts, damage, transitions,
input bindings and Pangu identity remain unverified. No credentials or network
are used. Raw bytes and decoded transforms may only be staged outside this repo.
UnityPy==1.25.4 is needed for real bundles; the motion decoder uses stdlib only.

Compressed rotation decoding is adapted from ShadowFightAnimationTool and the
archive's tools/sf3_motion.py. The following license applies to that adaptation:

MIT License
Copyright (c) 2025 Abdul Ghani
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
from zipfile import ZipFile


ARCHIVE_SHA256 = "f9a24c6f81c46b12facd670adff92d24f829a7811c298473ee51867262338959"
MOTION_CATALOG = "research/motion_catalog.json"
BUNDLE_CATALOG = "research/android_bundle_catalog.jsonl"
SOURCE_APK_SHA256 = "29eab6cb60ebec8aeb0a47c2efcfebc5e38320c2c659add3fa5670067ece13ab"
TARGETS = (
    {"target": "sun_ninjato", "bundle": "2ee15f236c4e114912c05a8561b8c9a3.bin",
     "sha256": "733d0127c26bda02300d0c2b7cdf4e11beea8b024ca7567161a194795247d1cc",
     "bytes": 1091123, "prefix": "", "count": 24},
    {"target": "sun_dead_forest_triad_h17", "bundle": "9893dca6e10355eb9c3c79d1613f08b1.bin",
     "sha256": "d6f2efe8ce772b953f610583ab5fb8963fb27abcccfec4b3aeccce8be973dd42",
     "bytes": 14681877, "prefix": "h17_", "count": 23},
)
MAGIC = 457_546_134_634_734
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_MEMBER_BYTES = 32 * 1024 * 1024
MAX_EXPANDED_BYTES = 300 * 1024 * 1024
MAX_CLIP_BYTES = 16 * 1024 * 1024
REPOSITORY = Path(__file__).resolve().parents[1]


class PreparationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PreparationError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def parse_json(data):
    return json.loads(data, object_pairs_hook=unique_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(
                          PreparationError("Non-finite JSON value: " + value)))


def checked_members(archive):
    members = {}
    total = 0
    require(len(archive.infolist()) <= 1000, "Too many ZIP members")
    for member in archive.infolist():
        path = PurePosixPath(member.filename)
        require(not path.is_absolute() and ".." not in path.parts
                and "\\" not in member.filename and path.parts,
                "Unsafe archive member path")
        require(member.filename not in members, "Duplicate ZIP member")
        require(not stat.S_ISLNK(member.external_attr >> 16), "ZIP symlink is forbidden")
        require(not member.flag_bits & 1, "Encrypted ZIP entry is unsupported")
        require(0 <= member.file_size <= MAX_MEMBER_BYTES, "ZIP member exceeds byte budget")
        total += member.file_size
        require(total <= MAX_EXPANDED_BYTES, "ZIP exceeds expanded byte budget")
        members[member.filename] = member
    return members


def decode_motion(data):
    """Decode source-frame transforms without assigning either array semantics."""
    require(26 <= len(data) <= MAX_CLIP_BYTES, "Invalid motion byte count")
    magic, count = struct.unpack_from("<QH", data)
    require(magic == MAGIC and count == 2, "Expected two source motion arrays")
    declared = struct.unpack_from("<QQ", data, 10)
    offset = 26
    arrays = []
    for array_index in range(count):
        require(offset + 8 <= len(data), "Truncated motion array header")
        frames, bones = struct.unpack_from("<II", data, offset)
        require(1 <= frames <= 2000 and 1 <= bones <= 256, "Invalid motion dimensions")
        packed = 8 + 2 * bones + 12 * frames * bones
        expanded = 8 + 2 * bones + 28 * frames * bones
        require(declared[array_index] in (packed, expanded), "Unrecognized array size")
        require(offset + packed <= len(data), "Truncated motion transforms")
        ids = list(struct.unpack_from("<" + "H" * bones, data, offset + 8))
        require(len(set(ids)) == bones, "Duplicate source bone IDs")
        cursor = offset + 8 + 2 * bones
        positions, rotations = [], []
        for _ in range(frames):
            frame_positions, frame_rotations = [], []
            for _ in range(bones):
                position = list(struct.unpack_from("<eee", data, cursor))
                x, y, z = struct.unpack_from("<HHH", data, cursor + 6)
                cursor += 12
                values = (((x & 0x1fff) * 4 + (y >> 14)),
                          ((y & 0x3fff) * 2 + (z >> 15)), z & 0x7fff)
                small = [value * (1.4142135 / 32767.0) - 0.70710677 for value in values]
                remaining = 1.0 - sum(value * value for value in small)
                require(remaining >= -0.001, "Invalid compressed quaternion")
                rotation = list(small)
                rotation.insert((x >> 13) & 3, math.sqrt(max(0.0, remaining)))
                require(all(math.isfinite(v) for v in position + rotation), "Non-finite motion transform")
                frame_positions.append(position)
                frame_rotations.append(rotation)
            positions.append(frame_positions)
            rotations.append(frame_rotations)
        arrays.append({"sourceArrayIndex": array_index, "frameCount": frames,
                       "boneIDs": ids, "positions": positions, "rotations": rotations})
        offset += packed
    require(offset == len(data), "Unexpected trailing motion bytes")
    return arrays


def read_text_assets(data, wanted_ids):
    try:
        import UnityPy
    except ImportError as error:
        raise PreparationError("Install UnityPy==1.25.4 in the task environment") from error
    require(UnityPy.__version__ == "1.25.4", "Expected reviewed UnityPy version 1.25.4")
    previous_version = UnityPy.config.FALLBACK_UNITY_VERSION
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
    try:
        environment = UnityPy.load(data)
        results = {}
        for obj in environment.objects:
            if obj.type.name != "TextAsset" or obj.path_id not in wanted_ids:
                continue
            require(obj.path_id not in results, "Duplicate Unity TextAsset path ID")
            asset = obj.read()
            raw = asset.m_Script.encode("utf-8", "surrogateescape") if isinstance(asset.m_Script, str) else bytes(asset.m_Script)
            results[obj.path_id] = (asset.m_Name, raw)
        require(set(results) == wanted_ids, "Source TextAsset missing from verified bundle")
        return results
    finally:
        UnityPy.config.FALLBACK_UNITY_VERSION = previous_version


def role_candidate(name):
    if name.startswith("h17_"):
        return "set." + name[4:].replace("_", ".")
    if name.startswith("s_ninjato_"):
        return "weapon.shadow." + name[len("s_ninjato_"):].replace("_", ".")
    return "weapon." + name.removeprefix("ninjato_").replace("_", ".")


def inspect_archive(path):
    require(path.is_file() and not path.is_symlink(), "Archive must be a regular non-symlink file")
    require(path.stat().st_size <= MAX_ARCHIVE_BYTES, "Archive exceeds byte budget")
    require(file_digest(path) == ARCHIVE_SHA256, "Source archive SHA-256 mismatch")
    exports, groups = [], []
    with ZipFile(path) as archive:
        members = checked_members(archive)
        require(MOTION_CATALOG in members and BUNDLE_CATALOG in members, "Source catalog missing")
        catalog = parse_json(archive.read(MOTION_CATALOG))
        require(catalog["error_count"] == 0, "Saved source catalog has decode errors")
        motions = catalog["motions"]
        bundle_rows = [parse_json(line) for line in archive.read(BUNDLE_CATALOG).splitlines() if line]
        for target in TARGETS:
            bundle_path = "bundles/" + target["bundle"]
            require(bundle_path in members, "Target bundle missing")
            bundle = archive.read(bundle_path)
            require(len(bundle) == target["bytes"] and digest(bundle) == target["sha256"], "Target bundle identity mismatch")
            selected = [row for row in motions if row["bundle"] == target["bundle"]
                        and row["name"].startswith(target["prefix"])]
            require(len(selected) == target["count"], "Target motion count mismatch")
            require(len({row["name"] for row in selected}) == len(selected), "Duplicate target motion name")
            ids = [row["path_id"] for row in selected]
            require(all(type(value) is int and -(2**63) <= value < 2**63 for value in ids)
                    and len(set(ids)) == len(ids), "Invalid target path IDs")
            assets = read_text_assets(bundle, set(ids))
            public_clips = []
            for row in sorted(selected, key=lambda item: item["name"]):
                name = row["name"]
                require(re.fullmatch(r"[a-z0-9_]+", name) is not None, "Unsafe motion name")
                require(row.get("playback_fps") is None, "Unreviewed source FPS cannot be imported")
                asset_name, raw = assets[row["path_id"]]
                require(asset_name == name and len(raw) == row["bytes"] and digest(raw) == row["sha256"], "Motion identity mismatch")
                arrays = decode_motion(raw)
                require(len(arrays) == row["arrays"] and all(
                    array["frameCount"] == row["frames"] and array["boneIDs"] == row["bone_ids"]
                    for array in arrays), "Decoded dimensions disagree with source catalog")
                summary = {"name": name, "candidateRole": role_candidate(name),
                           "roleBindingStatus": "name-derived candidate; not a verified control or event binding",
                           "sourcePathID": str(row["path_id"]), "sourceBundle": target["bundle"],
                           "sourceBytes": len(raw), "sourceSHA256": digest(raw),
                           "sourceFrameCount": row["frames"], "sourceFramesPerSecond": None,
                           "decodedArrayCount": len(arrays), "decodedBoneCounts": [len(a["boneIDs"]) for a in arrays],
                           "allTransformsFinite": True, "trailingBytes": 0}
                public_clips.append(summary)
                exports.append((name, raw, {"schemaVersion": 1, "sourceFramesPerSecond": None,
                                           "sourceSHA256": digest(raw), "arraySemantics": "unverified",
                                           "arrays": arrays}))
            groups.append({"target": target["target"], "sourceBundle": target["bundle"],
                           "bundleBytes": len(bundle), "bundleSHA256": digest(bundle), "motions": public_clips})
        leads = ("pangu", "primordial", "heavenly", "agl_48")
        pangu_matches = {lead: sum(lead in item["path"].lower()
                                  for row in bundle_rows for item in row.get("paths", [])) for lead in leads}
    report = {"schemaVersion": 1, "preparationKind": "verified-source-motion-decode",
              "sourceArchive": path.name, "sourceArchiveSHA256": ARCHIVE_SHA256,
              "sourcePackage": {"platform": "Android", "version": "1.45.3", "sha256": SOURCE_APK_SHA256},
              "decoder": {"containerReader": "UnityPy 1.25.4", "motionFormat": "two compressed transform arrays",
                          "fallbackUnityVersion": "6000.3.11f1", "bundleUnityVersionVerified": False,
                          "rotationAttribution": "ShadowFightAnimationTool (MIT), Abdul Ghani, 2025"},
              "verifiedBundleCount": len(groups), "verifiedMotionCount": len(exports),
              "decodedArrayCount": sum(len(item[2]["arrays"]) for item in exports),
              "sourceFramesPerSecond": None, "contactWindowsRecovered": False,
              "gameRulesRecovered": False, "damageAndHealthRecovered": False,
              "permitsGameplayEnablement": False,
              "pangu": {"status": "unmapped", "observedEquipmentLead": "ERR_HELM_AGL_48",
                        "leadStatus": "reference-video lead; not a verified asset mapping",
                        "sourcePathMatchCounts": pangu_matches},
              "limitations": ["Android 1.45.3 motion bytes do not establish iOS 1.46.1 behavior.",
                              "No contact windows, damage, health, source FPS, state transitions or input bindings are inferred.",
                              "Private decoded arrays retain source-frame indices; neither array is assigned undocumented semantics.",
                              "Target model, skeleton binding, effects and complete gameplay still require separate verification."],
              "targets": groups}
    return report, exports


def ensure_private_destination(path, repository=REPOSITORY):
    resolved = path.resolve()
    require(not resolved.is_relative_to(repository.resolve()), "Private staging must be outside the repository")
    require(not path.exists() and not path.is_symlink(), "Private staging already exists")
    require(path.parent.is_dir(), "Private staging parent must already exist")
    require(all(not parent.is_symlink() for parent in (path.parent, *path.parents)), "Private staging parent is a symlink")


def prepare(archive, private_staging, output):
    ensure_private_destination(private_staging)
    require(not output.exists() and not output.is_symlink(), "Report already exists")
    require(output.parent.is_dir(), "Report parent must already exist")
    report, exports = inspect_archive(archive)
    private_staging.mkdir(mode=0o700)
    try:
        (private_staging / "raw").mkdir(mode=0o700)
        (private_staging / "decoded").mkdir(mode=0o700)
        for name, raw, decoded in exports:
            for relative, data in (("raw/" + name + ".bytes", raw),
                                   ("decoded/" + name + ".json.gz", gzip.compress(
                                       json.dumps(decoded, separators=(",", ":"), allow_nan=False).encode(), mtime=0))):
                path = private_staging / relative
                descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(descriptor, "wb") as destination:
                    destination.write(data)
        with output.open("x", encoding="utf-8") as destination:
            json.dump(report, destination, indent=2, sort_keys=True, allow_nan=False)
            destination.write("\n")
    except Exception:
        shutil.rmtree(private_staging)
        raise
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--private-staging", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        report = prepare(args.archive, args.private_staging, args.output)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, "Target motion preparation failed: " + str(error) + "\n")
    print(json.dumps({"verifiedBundles": report["verifiedBundleCount"],
                      "decodedMotions": report["verifiedMotionCount"],
                      "decodedArrays": report["decodedArrayCount"],
                      "gameRulesRecovered": False, "pangu": report["pangu"]["status"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
