#!/usr/bin/env python3
"""Offline provenance/geometry audit, never a source combat-event interpreter.

Reads one explicitly supplied, hash-pinned plaintext catalog. Does not decrypt,
open related files, access credentials/network, or change gameplay/resources.
The binary framing follows DuelWeaponAssetTests.verifySource, not a new claim
about the meaning of the two preserved arrays. Reports contain no raw clip data.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import math
from pathlib import Path
import re
import struct


MAGIC = 457_546_134_634_734
MAX_CATALOG_BYTES = 32 * 1024 * 1024
MAX_CLIP_BYTES = 16 * 1024 * 1024
TRACK_NAMES = ("root", "handL", "handR", "footL", "footR",
               "weaponBaseL", "weaponTipL", "weaponBaseR", "weaponTipR")


class AuditError(ValueError):
    """Reject incomplete or inconsistent evidence without guessing a repair."""


def require(condition, message):
    if not condition:
        raise AuditError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def integer(value, low, high, label):
    require(type(value) is int and low <= value <= high, "Invalid " + label)
    return value


def label(value, field):
    require(isinstance(value, str) and 0 < len(value) <= 256
            and all(ord(c) >= 32 for c in value), "Invalid " + field)
    return value


def sha256(value, field):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
            "Invalid " + field)
    return value


def source_path_id(value):
    """Keep decimal-string IDs exact; JSON number consumers can lose 64-bit bits."""
    if isinstance(value, str):
        require(len(value) <= 20 and re.fullmatch(r"(?:0|-?[1-9][0-9]*)", value) is not None,
                "Invalid canonical source path ID")
        integer(int(value), -(2**63), 2**63 - 1, "source path ID")
        return value
    return integer(value, -(2**63), 2**63 - 1, "source path ID")


def finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON object key")
        result[key] = value
    return result


def raw_layout(clip):
    """Bounded verification of existing framing; array payload stays opaque."""
    frames = integer(clip.get("frames"), 2, 2000, "frame count")
    require(clip.get("sourceArrayCount") == 2
            and type(clip.get("sourceArrayCount")) is int, "Expected two source arrays")
    ids = clip.get("sourceBoneIDs")
    require(isinstance(ids, list) and 1 <= len(ids) <= 256, "Invalid source bone IDs")
    for value in ids:
        integer(value, 0, 65535, "source bone ID")
    require(len(set(ids)) == len(ids), "Duplicate source bone ID")
    encoded = clip.get("sourceBytesBase64")
    require(isinstance(encoded, str) and len(encoded) <= 4 * ((MAX_CLIP_BYTES + 2) // 3),
            "Missing or oversized source bytes")
    try:
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise AuditError("Invalid source byte encoding") from error
    require(26 <= len(data) <= MAX_CLIP_BYTES, "Invalid source byte count")
    require(digest(data) == sha256(clip.get("sha256"), "clip SHA-256"),
            "Source clip hash mismatch")
    magic, array_count = struct.unpack_from("<QH", data)
    require(magic == MAGIC and array_count == 2, "Unrecognized source framing")
    offset = 26
    arrays = []
    for index in range(2):
        require(offset + 8 <= len(data), "Truncated array header")
        actual_frames, bones = struct.unpack_from("<II", data, offset)
        require(actual_frames == frames and bones == len(ids), "Source array dimensions mismatch")
        packed = 8 + 2 * bones + 12 * frames * bones
        expanded = 8 + 2 * bones + 28 * frames * bones
        declared = struct.unpack_from("<Q", data, 10 + index * 8)[0]
        require(declared in (packed, expanded), "Unrecognized declared array size")
        require(offset + packed <= len(data), "Truncated source array")
        actual_ids = list(struct.unpack_from("<" + "H" * bones, data, offset + 8))
        require(actual_ids == ids, "Source bone ordering mismatch")
        arrays.append({"index": index, "byteOffset": offset, "packedBytes": packed,
                       "declaredBytes": declared,
                       "declaredSizeForm": "packed" if declared == packed else "expanded",
                       "sha256": digest(data[offset:offset + packed])})
        offset += packed
    require(offset == len(data), "Unaccounted source bytes after the two arrays")
    return {"bytes": len(data), "sha256": digest(data), "arrayCount": 2,
            "boneCount": len(ids), "arrays": arrays, "trailingByteCount": 0,
            "payloadInterpretation": "opaque; no event or tangent semantics inferred"}


def track_audit(clip, sides, threshold):
    tracks = clip.get("tracks")
    require(isinstance(tracks, dict), "Missing motion tracks")
    require(type(tracks.get("samplesPerSourceFrame")) is int
            and tracks["samplesPerSourceFrame"] == 2, "Expected half-source-frame tracks")
    count = 2 * clip["frames"] - 1
    report = {}
    for name in TRACK_NAMES:
        points = tracks.get(name)
        expected = count
        if name.startswith("weapon"):
            side = "left" if name.endswith("L") else "right"
            expected = count if side in sides else 0
        require(isinstance(points, list) and len(points) == expected, "Invalid track length: " + name)
        require(all(isinstance(point, list) and len(point) == 3
                    and all(finite(value) for value in point) for point in points),
                "Invalid track coordinates: " + name)
        steps = []
        for index in range(1, len(points)):
            delta = [b - a for a, b in zip(points[index - 1], points[index])]
            distance = math.hypot(*delta)
            require(all(finite(value) for value in delta) and finite(distance),
                    "Overflow in track interval: " + name)
            steps.append({"sampleFrom": index - 1, "sampleTo": index,
                          "sourceFrameFrom": (index - 1) / 2, "sourceFrameTo": index / 2,
                          "deltaMetres": delta, "distanceMetres": distance})
        steps.sort(key=lambda item: (-item["distanceMetres"], item["sampleFrom"]))
        report[name] = {"samples": len(points), "reviewThresholdExceedances": sum(
            item["distanceMetres"] > threshold for item in steps), "largestIntervals": steps[:5]}
    lifts = tracks.get("groundLift")
    require(isinstance(lifts, list) and len(lifts) == count
            and all(finite(value) and 0 <= value <= 2 for value in lifts), "Invalid ground lift")
    report["groundLift"] = {"samples": len(lifts), "minimumMetres": min(lifts),
                            "maximumMetres": max(lifts)}
    return report


def audit_catalog(data, expected_sha256, threshold=1.0):
    require(type(data) is bytes and len(data) <= MAX_CATALOG_BYTES, "Catalog exceeds byte budget")
    require(digest(data) == sha256(expected_sha256, "expected catalog SHA-256"), "Catalog hash mismatch")
    require(finite(threshold) and threshold > 0, "Invalid review threshold")
    try:
        catalog = json.loads(data, object_pairs_hook=reject_duplicate_keys,
                             parse_constant=lambda _: (_ for _ in ()).throw(AuditError("Non-finite JSON number")))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise AuditError("Invalid catalog JSON") from error
    require(isinstance(catalog, dict), "Expected catalog object")
    require(type(catalog.get("schemaVersion")) is int and catalog["schemaVersion"] == 1,
            "Unsupported catalog schema")
    require(type(catalog.get("previewFramesPerSecond")) is int
            and catalog["previewFramesPerSecond"] == 30, "Unsupported preview timebase")
    require(catalog.get("coordinateSpace") == "actor_facing_right_metres", "Unsupported coordinate space")
    provenance = catalog.get("provenance")
    require(isinstance(provenance, dict), "Missing source recovery provenance")
    recovery_flags = ("contactWindowsRecovered", "gameRulesRecovered")
    require(all(provenance.get(field) is False for field in recovery_flags),
            "This baseline audit requires explicit false source recovery flags")
    source_fps = catalog.get("sourceFramesPerSecond")
    require(source_fps is None or (finite(source_fps) and source_fps > 0), "Invalid source FPS field")
    profiles = catalog.get("profiles")
    require(isinstance(profiles, list) and len(profiles) == 2
            and all(isinstance(profile, dict) for profile in profiles), "Expected two profiles")
    require(all(isinstance(profile.get("id"), str) for profile in profiles)
            and {profile["id"] for profile in profiles} == {"sun_katana", "liu_hammers"},
            "Unexpected profile identities")
    results = []
    for profile in profiles:
        roles = profile.get("roles")
        require(isinstance(roles, dict) and isinstance(roles.get("shadow"), str), "Missing shadow role")
        clips = profile.get("clips")
        require(isinstance(clips, list) and 1 <= len(clips) <= 256
                and all(isinstance(clip, dict) for clip in clips), "Invalid clip list")
        names = [label(clip.get("name"), "clip name") for clip in clips]
        require(len(set(names)) == len(names), "Duplicate clip name")
        matches = [clip for clip in clips if clip["name"] == roles["shadow"]]
        require(len(matches) == 1, "Shadow role does not resolve uniquely")
        clip = matches[0]
        sides = profile.get("activeWeaponSides")
        require(isinstance(sides, list) and 1 <= len(sides) <= 2
                and all(side in ("left", "right") for side in sides)
                and len(set(sides)) == len(sides), "Invalid active weapon sides")
        layout = raw_layout(clip)
        result = {"profileID": profile["id"], "role": "shadow", "clipName": clip["name"],
                  "bundle": label(clip.get("bundle"), "source bundle"),
                  "sourcePathID": source_path_id(clip.get("sourcePathID")),
                  "frames": clip["frames"], "activeWeaponSides": sides,
                  "clipFieldsPresent": sorted(clip), "rawLayout": layout,
                  "tracks": track_audit(clip, sides, threshold)}
        results.append(result)
    return {"schemaVersion": 1, "auditKind": "source-layout-and-displacement-only",
            "catalogSHA256": digest(data), "catalogBytes": len(data),
            "previewFramesPerSecond": catalog["previewFramesPerSecond"],
            "catalogSourceFramesPerSecond": source_fps,
            "sourceTimingVerifiedByThisAudit": False,
            "authoritativeEventSemanticsRecoveredByThisAudit": False,
            "permitsGameplayEnablement": False,
            "catalogRecoveryProvenance": {field: provenance[field] for field in recovery_flags},
            "reviewThresholdMetres": threshold,
            "thresholdMeaning": "review aid only; not a teleport, contact, or visibility classifier",
            "trackSpace": "stored actor-facing-right metres; not gameplay world sweeps",
            "catalogFieldsPresent": sorted(catalog), "profiles": results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path,
                        help="New local report file; existing files are never overwritten")
    parser.add_argument("--review-threshold-metres", default=1.0, type=float)
    args = parser.parse_args(argv)
    try:
        require(not args.catalog.is_symlink() and args.catalog.is_file(), "Catalog must be a regular non-symlink file")
        with args.catalog.open("rb") as source:
            data = source.read(MAX_CATALOG_BYTES + 1)
        report = audit_catalog(data, args.expected_sha256, args.review_threshold_metres)
        # Exclusive creation also refuses a symlink, an input alias, or old report.
        with args.output.open("x", encoding="utf-8") as destination:
            json.dump(report, destination, indent=2, sort_keys=True, allow_nan=False)
            destination.write("\n")
    except (AuditError, OSError) as error:
        parser.exit(1, "Shadow source audit failed: " + str(error) + "\n")
    print("Wrote two shadow layout audits. Gameplay and event semantics remain unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
