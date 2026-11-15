#!/usr/bin/env python3
"""Stage the reviewed source-Stun append into a fresh private release.

The old signed release, every old resource, candidate receipts and both new
GLBs have independent pins. Only three clips/roles and dependent identity
bindings change. No workflow, signed build setting or production Pangu gate is
changed; adopting the resulting release remains a separate integration step.
"""
from __future__ import annotations

import argparse
import base64
from copy import deepcopy
import gzip
import json
import os
from pathlib import Path
import zlib

from append_cached_stun_motions import BUNDLE, MOTIONS, PROFILES, validate_stun_append
from append_cached_root_victim_motions import pinned
from stage_h17_floorfall_release import (checked_file, digest, encoded, fresh_output,
    parse_json, real_directory, record, require, safe_name, write_private)


BASE_RECEIPT_SHA = "b60964cf0c2ce0b234bf3f31522677d0e05972c9493efab77b0044ff8d6ba248"
BASE_RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
CANDIDATE_RECEIPT_SHA = "eb49bcef70e8923b3aaa5a24866cfb798aee8f70c8340d65f3d27bbc559244d1"
RELEASE_NAME = "SF3_FighterRelease.json"
CATALOG_NAME = "SF3_DistinctFighters.json"
TARGET_ID = "shared-original-stun-20261115-v1"
NEW = {
    "sun": dict(bytes=15_721_912, sha256="9513c85028541fe514f552a5e0d11fd01df277b8cd9f8ddeb832508ff975c699",
        profileSHA="78a83dc1b51c0b21eac76fcae6efa8a54f2e722688a94bc9496faf9d66b61d02"),
    "liu": dict(bytes=11_055_648, sha256="66f8a748efb431bb28bdcd5e4cd91bc2d5d374fd456eb00e843f5d6590a26bfe",
        profileSHA="00731a040544cfd993a4744b1dc9d959da0d4f294d2067272dcb722f658d86a3"),
}
MEDIA_BINDINGS = {
    "sourceTrails": ("SF3WE_Target_Trails.json", ("sun", "liu")),
    "triadAudio": ("SF3_H17_Audio.json", ("sun", "liu")),
    "triadSummons": ("SF3_H17_Summons.json", ("sun",)),
    "triadEffects": ("SF3_H17_Effects.json.gz", ("sun",)),
    "triadMorph": ("SF3_H17_Morph.json", ("sun", "liu")),
}


def append_catalog(base, candidates):
    result = deepcopy(base)
    require({p["id"] for p in result["profiles"]} == {p["id"] for p in PROFILES.values()}, "Production roster differs")
    for key, pin in PROFILES.items():
        old = next(p for p in base["profiles"] if p["id"] == pin["id"])
        row = next(p for p in result["profiles"] if p["id"] == pin["id"])
        candidate = candidates[key]
        require(old["sha256"] == pin["characterSHA"] and len(old["clips"]) == pin["count"]
                and candidate["sha256"] == NEW[key]["sha256"]
                and len(candidate["clips"]) == pin["count"] + 3, "Catalog append source identity differs")
        # The production catalog has later source COM/pelvis/combos/rules.
        # Never replace it with a standalone conversion profile's old tracks.
        row["bytes"] = NEW[key]["bytes"]; row["sha256"] = NEW[key]["sha256"]
        clips = candidate["clips"][-3:]
        for clip, motion in zip(clips, MOTIONS):
            raw = base64.b64decode(clip["sourceBytesBase64"], validate=True)
            require(clip["name"] == motion["name"] and clip["sha256"] == motion["sha256"]
                    and clip["frames"] == motion["frames"] and clip["bundle"] == BUNDLE
                    and len(raw) == motion["bytes"] and digest(raw) == motion["sha256"], "Stun source clip identity differs")
            require(motion["role"] not in row["roles"] and motion["name"] not in {c["name"] for c in old["clips"]},
                    "Stun binding already exists")
            row["roles"][motion["role"]] = motion["name"]
        row["clips"].extend(deepcopy(clips))
        for field in old:
            if field not in {"sha256", "bytes", "roles", "clips"}:
                require(row[field] == old[field], "Existing catalog rules/identity changed")
        require(row["clips"][:pin["count"]] == old["clips"], "Old production tracks changed")
    return result


def rebind_identity(raw, keys, compressed=False):
    if compressed:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        plain = decoder.decompress(raw, 200_000_001)
        require(len(plain) <= 200_000_000 and decoder.eof and not decoder.unused_data
                and not decoder.unconsumed_tail, "Source effect manifest exceeds exact gzip bound")
    else: plain = raw
    for key in keys:
        old, new = (PROFILES[key]["characterSHA"].encode(), NEW[key]["sha256"].encode())
        require(plain.count(old) == 1 and new not in plain, "Dependent character binding is missing or ambiguous")
        plain = plain.replace(old, new)
    # All non-identity source data, including PCM cues, FX samples and source
    # material bindings, remain byte-for-byte equal before gzip compression.
    return gzip.compress(plain, compresslevel=9, mtime=0) if compressed else plain


def stage(args):
    output = fresh_output(args.output)
    base, candidate = real_directory(args.base), real_directory(args.candidate)
    output = fresh_output(output, (base, candidate))
    receipt = parse_json(pinned(args.base_receipt, BASE_RECEIPT_SHA, 128_000))
    new_receipt = parse_json(pinned(candidate / "stun-candidate-receipt-private.json", CANDIDATE_RECEIPT_SHA, 32_000))
    require(receipt["release"]["sha256"] == BASE_RELEASE_SHA
            and new_receipt["productionPanguActivated"] is False, "Source release receipt differs")
    inventory = {safe_name(row["name"]): row for row in receipt["files"]}
    require(len(inventory) == len(receipt["files"]) == 302
            and sum(row["bytes"] for row in inventory.values()) < 180_000_000,
            "Source private inventory differs")
    require({p.name for p in base.iterdir()} == set(inventory), "Source resource directory differs")
    original = {name: checked_file(base, row) for name, row in inventory.items()}
    release = parse_json(original[RELEASE_NAME])
    require(digest(original[RELEASE_NAME]) == BASE_RELEASE_SHA and release["schemaVersion"] == 2
            and release["panguAudio"] is None, "Expected the current legacy Liu production release")
    candidates, changes = {}, {}
    for key, pin in PROFILES.items():
        name = pin["resource"] + ".glb"
        raw = pinned(candidate / key / name, NEW[key]["sha256"], 32_000_000)
        require(len(raw) == NEW[key]["bytes"], "Candidate character size differs")
        validate_stun_append(original[name], raw, pin["count"])
        changes[name] = raw
        candidates[key] = parse_json(pinned(candidate / key / (pin["resource"] + "_profile.json"), NEW[key]["profileSHA"], 24_000_000))
    catalog = append_catalog(parse_json(original[CATALOG_NAME]), candidates)
    changes[CATALOG_NAME] = encoded(catalog)
    target = deepcopy(release); target["id"] = TARGET_ID
    target["catalog"] = record(CATALOG_NAME, changes[CATALOG_NAME])
    for field, (name, keys) in MEDIA_BINDINGS.items():
        require(release[field] == inventory[name], "Source dependent manifest pin differs")
        changes[name] = rebind_identity(original[name], keys, name.endswith(".gz"))
        target[field] = record(name, changes[name])
    for key, pin in PROFILES.items():
        row = next(p for p in target["profiles"] if p["id"] == pin["id"])
        require(row["characterSHA256"] == pin["characterSHA"] and len(row["motions"]) == pin["count"], "Source release profile differs")
        row["characterSHA256"] = NEW[key]["sha256"]
        row["motions"].extend(dict(clip=m["name"], sourceSHA256=m["sha256"], sourceBundle=BUNDLE,
            frames=m["frames"], exportFramesPerSecond=30, sourceFramesPerSecond=30) for m in MOTIONS)
    changes[RELEASE_NAME] = encoded(target)
    os.mkdir(output, 0o700)
    media = output / "FighterPrivate"; os.mkdir(media, 0o700)
    rows = []
    for name in sorted(inventory):
        raw = changes.get(name, original[name]); write_private(media / name, raw)
        rows.append(record(name, raw))
    result = dict(schema="common-source-stun-private-release-v1", baseReleaseSHA256=BASE_RELEASE_SHA,
        candidateReceiptSHA256=CANDIDATE_RECEIPT_SHA, release=record(RELEASE_NAME, changes[RELEASE_NAME]),
        files=rows, changedFiles=sorted(changes), unchangedFiles=len(inventory) - len(changes),
        sourceClipsAddedPerProfile=3, oldCatalogTracksRulesAndCombosPreserved=True,
        oldGLBGeometryAndAnimationsPreserved=True, dependentManifestChanges="character digest only",
        productionLiuID="liu_hammers", productionPanguActivated=False,
        signedBuildPinChanged=False, uploaded=False, nativeRendered=False,
        buildSetting={"FIGHTER_ASSET_RELEASE_SHA256": digest(changes[RELEASE_NAME])})
    write_private(output / "stun-release-receipt-private.json", encoded(result))
    return {key: result[key] for key in ("release", "changedFiles", "unchangedFiles", "productionPanguActivated", "nativeRendered")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "base-receipt", "candidate", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(stage(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
