#!/usr/bin/env python3
"""Stage two original Imperial victim aliases without replacing old rules.

The existing 302-file private release is authenticated before copying. This
only adds the reviewed victim clips and updates dependent character digests;
it does not activate Pangu, publish media or change a signed build setting.
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

from append_cached_imperial_passives import PROFILES, SOURCE_RAW_SHA, VARIANTS, validate_append
from append_cached_root_victim_motions import pinned
from stage_cached_stun_release import CATALOG_NAME, MEDIA_BINDINGS, RELEASE_NAME
from stage_h17_floorfall_release import (checked_file, digest, encoded, fresh_output,
    parse_json, real_directory, record, require, safe_name, write_private)


BASE_RECEIPT_SHA = "7c82dadc14b9e12ee84ecae08bb05154fb1f265c4fe81e0caea96e3d3fcf7cfe"
BASE_RELEASE_SHA = "53382445ba6867890a67b255e3dd671b6906a9a2ab044e765dd46d5ae3e35c19"
CANDIDATE_RECEIPT_SHA = "aaeacb4288e93e7d45b574fa83595c56463ee3361dff3682ccf3e4f3be824746"
NEW = {
    "sun": dict(bytes=16_252_036, sha256="7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a",
        profileSHA="f46dd3c1e5df637fadc6f5a5f5a08468af2c6db50002a0ae8282b78f4daf6e6a"),
    "liu": dict(bytes=11_585_516, sha256="d873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80",
        profileSHA="a98e19b573509d6a08c998093b3937fefe8c9c4742d683e76621a8a10a22f266"),
}


def rebind(raw, keys, compressed=False):
    if compressed:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        plain = decoder.decompress(raw, 200_000_001)
        require(len(plain) <= 200_000_000 and decoder.eof and not decoder.unused_data
                and not decoder.unconsumed_tail, "Source effect manifest exceeds exact gzip bound")
    else: plain = raw
    for key in keys:
        old, new = PROFILES[key]["characterSHA"].encode(), NEW[key]["sha256"].encode()
        require(plain.count(old) == 1 and new not in plain, "Dependent identity missing or ambiguous")
        plain = plain.replace(old, new)
    return gzip.compress(plain, compresslevel=9, mtime=0) if compressed else plain


def stage(args):
    base, candidate = real_directory(args.base), real_directory(args.candidate)
    output = fresh_output(args.output, (base, candidate))
    receipt = parse_json(pinned(args.base_receipt, BASE_RECEIPT_SHA, 128_000))
    candidate_receipt = parse_json(pinned(candidate / "imperial-passive-candidate-receipt-private.json",
                                          CANDIDATE_RECEIPT_SHA, 32_000))
    require(receipt["release"]["sha256"] == BASE_RELEASE_SHA and receipt["productionPanguActivated"] is False,
            "Expected the reviewed post-Stun release")
    inventory = {safe_name(row["name"]): row for row in receipt["files"]}
    require(len(inventory) == len(receipt["files"]) == 302
            and sum(row["bytes"] for row in inventory.values()) < 180_000_000,
            "Original private inventory differs")
    require({p.name for p in base.iterdir()} == set(inventory), "Original resource directory differs")
    original = {name: checked_file(base, row) for name, row in inventory.items()}
    release = parse_json(original[RELEASE_NAME])
    require(digest(original[RELEASE_NAME]) == BASE_RELEASE_SHA and release["schemaVersion"] == 2
            and release["panguAudio"] is None, "Expected the existing Liu reference release")
    catalog = parse_json(original[CATALOG_NAME]); previous_catalog = deepcopy(catalog)
    require({p["id"] for p in catalog["profiles"]} == {p["id"] for p in PROFILES.values()},
            "Original production roster differs")
    changes = {}
    target = deepcopy(release); target["id"] = "shared-imperial-victim-20261115-v1"
    for key, pin in PROFILES.items():
        name = pin["resource"] + ".glb"
        raw = pinned(candidate / key / name, NEW[key]["sha256"], 32_000_000)
        require(len(raw) == NEW[key]["bytes"] and candidate_receipt[key]["outputCharacterSHA256"] == NEW[key]["sha256"],
                "Candidate identity differs")
        validate_append(original[name], raw, pin["count"]); changes[name] = raw
        profile = parse_json(pinned(candidate / key / (pin["resource"] + "_profile.json"), NEW[key]["profileSHA"], 32_000_000))
        row = next(p for p in catalog["profiles"] if p["id"] == pin["id"])
        old = deepcopy(row)
        require(row["sha256"] == pin["characterSHA"] and len(row["clips"]) == pin["count"]
                and len(profile["clips"]) == pin["count"] + 2, "Original/candidate clip set differs")
        clips = profile["clips"][-2:]
        for clip, (clip_name, role, index, mirrored) in zip(clips, VARIANTS):
            source = base64.b64decode(clip["sourceBytesBase64"], validate=True)
            require(clip["name"] == clip_name and clip["sha256"] == SOURCE_RAW_SHA
                    and digest(source) == SOURCE_RAW_SHA and clip["frames"] == 71
                    and clip["sourceFirstIndex"] == 0 and clip["sourceLastIndex"] == 70
                    and clip["playbackTicks"] == 140 and clip["sourceEndEventTick"] == 132
                    and clip["sourceConfiguration"]["sourceRecordIndex"] == index
                    and clip["sourceMirroringApplied"] == mirrored
                    and role not in row["roles"] and all(c["name"] != clip_name for c in row["clips"]),
                    "Reviewed Imperial alias differs")
            row["roles"][role] = clip_name
        row["clips"].extend(deepcopy(clips)); row["bytes"] = NEW[key]["bytes"]; row["sha256"] = NEW[key]["sha256"]
        require(row["clips"][:pin["count"]] == old["clips"] and all(row[f] == old[f]
            for f in old if f not in {"bytes", "sha256", "clips", "roles"}), "Existing production rules/tracks changed")
        binding = next(p for p in target["profiles"] if p["id"] == pin["id"])
        require(binding["characterSHA256"] == pin["characterSHA"] and len(binding["motions"]) == pin["count"],
                "Original release binding differs")
        binding["characterSHA256"] = NEW[key]["sha256"]
        # Release frame/FPS describes the source crop's duration. These clips
        # also contain intermediate 60 Hz keys, as recorded in their GLB extras.
        binding["motions"].extend(dict(clip=name, sourceSHA256=SOURCE_RAW_SHA,
            sourceBundle="baccadc1bc62c24fcf83246b63fd6c17.bin", frames=71,
            exportFramesPerSecond=30, sourceFramesPerSecond=30) for name, _, _, _ in VARIANTS)
    require(all(catalog[k] == previous_catalog[k] for k in catalog if k != "profiles"), "Catalog metadata changed")
    changes[CATALOG_NAME] = encoded(catalog); target["catalog"] = record(CATALOG_NAME, changes[CATALOG_NAME])
    for field, (name, keys) in MEDIA_BINDINGS.items():
        require(release[field] == inventory[name], "Dependent manifest identity differs")
        changes[name] = rebind(original[name], keys, name.endswith(".gz")); target[field] = record(name, changes[name])
    changes[RELEASE_NAME] = encoded(target)
    os.mkdir(output, 0o700); media = output / "FighterPrivate"; os.mkdir(media, 0o700)
    rows = []
    for name in sorted(inventory):
        raw = changes.get(name, original[name]); write_private(media / name, raw); rows.append(record(name, raw))
    result = dict(schema="imperial-victim-private-release-v1", baseReleaseSHA256=BASE_RELEASE_SHA,
        candidateReceiptSHA256=CANDIDATE_RECEIPT_SHA, release=record(RELEASE_NAME, changes[RELEASE_NAME]),
        files=rows, changedFiles=sorted(changes), unchangedFiles=len(inventory) - len(changes),
        sourceClipsAddedPerProfile=2, oldCatalogTracksRulesAndCombosPreserved=True,
        oldGLBGeometryAndAnimationsPreserved=True, dependentManifestChanges="character digest only",
        productionLiuID="liu_hammers", productionPanguActivated=False, signedBuildPinChanged=False,
        uploaded=False, nativeRendered=False,
        buildSetting={"FIGHTER_ASSET_RELEASE_SHA256": digest(changes[RELEASE_NAME])})
    write_private(output / "imperial-passive-release-receipt-private.json", encoded(result))
    return {key: result[key] for key in ("release", "changedFiles", "unchangedFiles", "productionPanguActivated", "nativeRendered")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "base-receipt", "candidate", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(stage(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
