#!/usr/bin/env python3
"""Bind the existing private floor-fall candidate to a fresh playable release.

This is local assembly, not decoding, encryption, upload or activation. The
reviewed base package, assembly receipt and candidate have independent pins.
All source files stay untouched. The result includes a complete private asset
directory and a nine-file delta, so existing assets need not be re-uploaded.
The signed application must independently adopt the returned release digest.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

from source_floorfall_audio import CHARACTER_SHA, MOTION_PINS, validate_base_binding


REPOSITORY = Path(__file__).resolve().parents[1]
BASE_PACK_SHA = "697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff"
BASE_RECEIPT_SHA = "5f765002e32fa10482a892adbd379a6b0ef15837de47a5273cd9181c45cfbb79"
BASE_RELEASE_SHA = "7bf9aa17a1e15273dbe7ae04eecd1ef092c2ad9a72360b99cd4f7ac08695704b"
CANDIDATE_SHA = "7451625a85eab8da8f296f4d412c94981e7d411706de7ea6e5b620c2f7d4d809"
RELEASE_NAME = "SF3_FighterRelease.json"
AUDIO_NAME = "SF3_H17_Audio.json"
TARGET_ID = "h17-source-floorfall-20261114"
REPLACEMENTS = [RELEASE_NAME, AUDIO_NAME]
MAX_TOTAL = 160 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()


def parse_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON key")
            result[key] = value
        return result
    def invalid(_):
        raise ValueError("Non-finite JSON value")
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)


def safe_name(name):
    require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", name)
            and ".." not in name, "Unsafe resource basename")
    return name


def record(name, raw):
    return dict(name=safe_name(name), bytes=len(raw), sha256=digest(raw))


def regular(path, maximum):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum,
                "Expected a bounded regular input")
        raw = handle.read(maximum + 1)
        require(len(raw) == info.st_size, "Input changed while reading")
        return raw


def checked_file(directory, row):
    require(type(row["bytes"]) is int and 0 < row["bytes"] <= 128_000_000,
            "Resource byte bound is invalid")
    raw = regular(directory / safe_name(row["name"]), row["bytes"])
    require(record(row["name"], raw) == row, "Resource differs from the independently reviewed inventory")
    return raw


def pinned_json(path, pin, maximum):
    raw = regular(path, maximum)
    require(digest(raw) == pin, "Reviewed input pin differs")
    return parse_json(raw)


def real_directory(path):
    path = Path(path).absolute()
    require(path.is_dir() and not path.is_symlink() and path.resolve(strict=True) == path,
            "Input directory must not use symbolic links")
    return path


def fresh_output(path, inputs=()):
    path = Path(path).absolute()
    require(path.parent.resolve(strict=True) == path.parent, "Output parent must not use symbolic links")
    require(not path.exists() and not path.is_symlink(), "Output must be new")
    require(path != REPOSITORY and REPOSITORY not in path.parents and
            all(path != root and root not in path.parents for root in inputs),
            "Output must be outside the repository and source directories")
    return path


def base_inventory(pack, receipt):
    require(pack["releaseSHA256"] == BASE_RELEASE_SHA and
            receipt["release"]["sha256"] == BASE_RELEASE_SHA, "Base release pin differs")
    rows = [dict(name=r["file"], bytes=r["bytes"], sha256=r["sha256"]) for r in pack["files"]]
    require(len(rows) == 295 and len({r["name"] for r in rows}) == len(rows), "Base inventory set differs")
    require(sum(r["bytes"] for r in rows) <= MAX_TOTAL, "Base inventory exceeds the private resource bound")
    require(sorted(rows, key=lambda r: r["name"]) == sorted(receipt["files"], key=lambda r: r["name"]),
            "Assembly receipt does not match the reviewed package inventory")
    require(pack["replacements"] == receipt["replacements"] ==
            ["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"], "Base replacement contract differs")
    return {safe_name(r["name"]): r for r in rows}


def audio_delta(base, candidate, release):
    """Only the two exact interval markers and their seven WAVs may be appended."""
    validate_base_binding(base)
    validate_base_binding(candidate)
    require(set(base) == set(candidate) and all(base[k] == candidate[k] for k in base if k not in ("files", "markers")),
            "Candidate changed an existing audio binding object")
    require(len(base["files"]) == 88 and len(candidate["files"]) == 95 and
            candidate["files"][:88] == base["files"], "Candidate changed or reordered existing PCM bindings")
    require(len(base["markers"]) == 112 and len(candidate["markers"]) == 114 and
            candidate["markers"][:112] == base["markers"], "Candidate changed existing source markers")
    added = candidate["files"][88:]
    require(len({r["name"] for r in added}) == 7, "Expected exactly seven new source PCM files")
    markers = candidate["markers"][112:]
    require({m["clip"] for m in markers} == set(MOTION_PINS), "Unexpected floor-fall source motions")
    profile = next((p for p in release["profiles"] if p["id"] == "sun_triad"), None)
    require(profile is not None and profile["characterSHA256"] == CHARACTER_SHA,
            "Source release does not bind the reviewed H17 character")
    motions = {m["clip"]: m for m in profile["motions"]}
    for marker in markers:
        clip = marker["clip"]
        require(marker == dict(id="source_floorfall_923_97_" + clip, clip=clip,
                sourceFrame=20, clock="intervalStart", context="Common", files=[r["name"] for r in added]),
                "Floor-fall marker identity, clock or variant order changed")
        frames, sha = MOTION_PINS[clip]
        motion = motions.get(clip)
        require(motion is not None and motion["frames"] == frames and motion["sourceSHA256"] == sha and
                motion["sourceFramesPerSecond"] == 30 and motion["exportFramesPerSecond"] == 30,
                "Release source motion binding does not support the reviewed clock")
    return added


def revised_release(base, audio_row):
    require(base["schemaVersion"] == 2 and base["id"] == "h17-source-recovery-20261114" and
            base["panguAudio"] is None and {p["id"] for p in base["profiles"]} == {"sun_triad", "liu_hammers"},
            "Unsupported base release identity")
    require(audio_row["name"] == AUDIO_NAME, "Wrong audio manifest name")
    result = deepcopy(base)
    result["id"] = TARGET_ID
    result["triadAudio"] = deepcopy(audio_row)
    return result


def write_private(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(raw)


def stage(args):
    # Refuse repeat commands before reading 130 MB of existing source resources.
    output = fresh_output(args.output)
    base = real_directory(args.base)
    candidate_root = real_directory(args.candidate)
    output = fresh_output(output, (base, candidate_root))
    pack = pinned_json(args.pack_manifest, BASE_PACK_SHA, 2_000_000)
    receipt = pinned_json(args.receipt, BASE_RECEIPT_SHA, 2_000_000)
    inventory = base_inventory(pack, receipt)
    require({p.name for p in base.iterdir()} == set(inventory), "Base directory differs from its reviewed complete inventory")
    release = parse_json(checked_file(base, inventory[RELEASE_NAME]))
    old_audio = parse_json(checked_file(base, inventory[AUDIO_NAME]))
    require(release["triadAudio"] == inventory[AUDIO_NAME], "Base release audio reference differs")
    raw_audio = regular(candidate_root / AUDIO_NAME, 512_000)
    require(digest(raw_audio) == CANDIDATE_SHA, "Private candidate pin differs")
    audio = parse_json(raw_audio)
    added = audio_delta(old_audio, audio, release)
    require(not set(inventory) & {r["name"] for r in added}, "New audio collides with an existing resource")
    require({p.name for p in candidate_root.iterdir()} ==
            {r["name"] for r in audio["files"]} | {AUDIO_NAME, "floorfall-audio-provenance-private.json"},
            "Unexpected candidate directory contents")
    for row in old_audio["files"]:
        require(inventory.get(row["name"]) == row, "Existing PCM does not match the base release inventory")
    # All pins and actual bytes are checked before creating any output.
    for row in inventory.values():
        checked_file(base, row)
    for row in audio["files"]:
        checked_file(candidate_root, row)
    target_release = revised_release(release, record(AUDIO_NAME, raw_audio))
    raw_release = encoded(target_release)
    changed = {RELEASE_NAME: raw_release, AUDIO_NAME: raw_audio}
    for row in added:
        changed[row["name"]] = checked_file(candidate_root, row)
    target = dict(inventory)
    target.update({name: record(name, raw) for name, raw in changed.items()})
    require(len(target) == 302 and len(changed) == 9 and sum(r["bytes"] for r in target.values()) <= MAX_TOTAL,
            "Target resource set exceeds the reviewed delta")
    delta = dict(schema="fighter-h17-audio-delta-v1", basePackManifestSHA256=BASE_PACK_SHA,
                 baseReleaseSHA256=BASE_RELEASE_SHA, targetRelease=target[RELEASE_NAME],
                 replacements=REPLACEMENTS, additions=sorted(r["name"] for r in added),
                 files=[target[name] for name in sorted(changed)],
                 unchangedBaseFiles=len(inventory) - len(REPLACEMENTS),
                 requiresIndependentSignedBuildPin=True, encrypted=False, uploaded=False)
    result = dict(schema="private-h17-floorfall-staged-release-v1", baseReleaseSHA256=BASE_RELEASE_SHA,
                  basePackManifestSHA256=BASE_PACK_SHA, candidateAudioSHA256=CANDIDATE_SHA,
                  release=target[RELEASE_NAME], files=[target[name] for name in sorted(target)],
                  delta=delta, buildSetting={"FIGHTER_ASSET_RELEASE_SHA256": target[RELEASE_NAME]["sha256"]},
                  reusedOriginalFiles=293, reusedPCMFiles=88, addedPCMFiles=7, addedMarkers=2,
                  sourceAssetsReencoded=False, existingInputsModified=False, uploaded=False,
                  iosLoadingVerified=False, iosPlaybackVerified=False, physicalDeviceVerified=False,
                  description="Local complete source release and nine-file delta; the signed build must adopt the new pin")
    output.mkdir(mode=0o700)
    full = output / "FighterPrivate"
    incremental = output / "delta"
    full.mkdir(mode=0o700)
    incremental.mkdir(mode=0o700)
    for name in sorted(target):
        raw = changed[name] if name in changed else checked_file(base, inventory[name])
        write_private(full / name, raw)
    for name, raw in changed.items():
        write_private(incremental / name, raw)
    write_private(output / "delta-manifest-private.json", encoded(delta))
    write_private(output / "assembly-receipt-private.json", encoded(result))
    return dict(staged=True, releaseSHA256=target[RELEASE_NAME]["sha256"], files=len(target),
                deltaFiles=len(changed), deltaBytes=sum(len(raw) for raw in changed.values()),
                addedPCMFiles=7, addedMarkers=2, reusedPCMFiles=88,
                sourceAssetsReencoded=False, uploaded=False, signedBuildPinRequired=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "candidate", "receipt", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--pack-manifest", type=Path,
                        default=REPOSITORY / ".github/private/fighter-h17-d19/manifest.json")
    try:
        result = stage(parser.parse_args())
    except (ValueError, OSError, KeyError, TypeError) as error:
        # Paths and original byte payloads are private, even on rejection.
        print(json.dumps(dict(staged=False, errorType=type(error).__name__)), file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
