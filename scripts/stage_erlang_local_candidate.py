#!/usr/bin/env python3
"""Assemble the pinned local character candidate without signing or uploading it.

The existing two-character release is preserved byte for byte. Additional Wu
files must match the application's independently reviewed identity table and
every referenced payload. Private extraction receipts are not installed as
application resources.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import zlib


ROOT = Path(__file__).resolve().parents[1]
BASE_RECEIPT = "imperial-passive-release-receipt-private.json"
BASE_RECEIPT_SHA256 = "449f039fa5fc6342565e6eafa098752089be5ff00cc292232a1abba762e3b582"
BASE_RELEASE_SHA256 = "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3"
GROUPS = (
    ("companions", "SF3_D15_Companions.json", "companionManifestSHA256"),
    ("hound_effects", "SF3_D15_Effects.json.gz", "houndEffectsSHA256"),
    ("stomp_effects", "SF3_D15_StompEffects.json.gz", "stompEffectsSHA256"),
    ("sword_effects", "SF3_D15_SwordEffects.json.gz", "swordEffectsSHA256"),
    ("skill_effects", "SF3_D15_SkillEffects.json.gz", "skillEffectsSHA256"),
    ("audio", "SF3_Erlang_Audio.json", "audioManifestSHA256"),
    ("victory_morph", "SF3_H17_WuMorph.json", "victoryMorphManifestSHA256"),
)


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def regular(path, maximum=128_000_000):
    path = path.absolute()
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum
            and path.resolve(strict=True) == path, "Expected a bounded regular input")
    return path


def checked(path, sha256, size=None):
    path = regular(path)
    require(re.fullmatch(r"[0-9a-f]{64}", sha256) is not None
            and (size is None or type(size) is int and path.stat().st_size == size)
            and digest(path) == sha256, "Input integrity mismatch: " + path.name)
    return path


def document(path, sha256):
    raw = checked(path, sha256).read_bytes()
    if path.name.endswith(".json.gz"):
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        raw = decoder.decompress(raw, 256_000_001)
        require(len(raw) <= 256_000_000 and decoder.eof and not decoder.unused_data
                and not decoder.unconsumed_tail, "Invalid bounded manifest stream")
    value = json.loads(raw)
    require(isinstance(value, dict), "Manifest must be an object")
    return value


def stage(args):
    identity_file = regular(ROOT / "App/Services/DuelErlangAssetIdentity.swift", 16_384)
    identity = dict(re.findall(r'static let ([A-Za-z0-9_]+) = "([A-Za-z0-9_.]+)"',
                              identity_file.read_text()))
    require(identity["profileName"] == "SF3_Erlang_Profile.json"
            and identity["audioManifestName"] == "SF3_Erlang_Audio.json"
            and identity["victoryMorphManifestName"] == "SF3_H17_WuMorph.json",
            "Application resource names differ")
    receipt = document(args.base / BASE_RECEIPT, BASE_RECEIPT_SHA256)
    require(receipt["release"]["sha256"] == BASE_RELEASE_SHA256
            and len(receipt["files"]) == 302 and not receipt["productionPanguActivated"],
            "Expected the reviewed shared-victim base release")
    plan = {}

    def select(directory, row, group):
        name, size, sha256 = row["name"], row["bytes"], row["sha256"]
        require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,191}", name)
                is not None and ".." not in name, "Invalid resource name")
        path = checked(directory / name, sha256, size)
        record = {"name": name, "bytes": size, "sha256": sha256}
        if name in plan:
            require(plan[name][1] == record, "Conflicting resource bytes: " + name)
            plan[name][2].add(group)
        else:
            plan[name] = (path, record, {group})

    base = args.base / "FighterPrivate"
    require({p.name for p in base.iterdir()} == {row["name"] for row in receipt["files"]},
            "Base release has unexpected or missing entries")
    for row in receipt["files"]:
        select(base, row, "base")
    profile_path = args.body / identity["profileName"]
    profile = document(profile_path, identity["profileSHA256"])
    require(profile["id"] == profile["hero"] == "wuyong_erlang"
            and profile["sha256"] == identity["characterSHA256"]
            and len(profile["clips"]) == 62 and len(profile["combatRules"]["attacks"]) == 20,
            "Wu actor profile or paired Active binding differs")
    select(args.body, {"name": profile_path.name, "bytes": profile_path.stat().st_size,
                      "sha256": identity["profileSHA256"]}, "body")
    select(args.body, {"name": profile["resourceName"] + ".glb", "bytes": profile["bytes"],
                      "sha256": profile["sha256"]}, "body")
    source_scopes = {}
    for group, name, pin in GROUPS:
        directory = getattr(args, group)
        path = directory / name
        value = document(path, identity[pin])
        if group == "victory_morph":
            require(value["ownerProfileID"] == "sun_triad"
                    and value["targetProfileID"] == profile["id"]
                    and value["targetCharacterSHA256"] == profile["sha256"],
                    "Victory morph belongs to a different pair")
            mask = value["mask"]
            files = [{"name": mask["file"], "bytes": mask["bytes"], "sha256": mask["sha256"]}]
        else:
            require(value["profileID"] == profile["id"] and value["characterSHA256"] == profile["sha256"],
                    "Manifest belongs to a different Wu actor")
            files = [m["file"] for m in value["models"]] if group == "companions" else value["files"]
        if group == "audio":
            require(value["profileSHA256"] == identity["profileSHA256"] and value["schemaVersion"] == 5
                    and len(files) == 82 and len(value["markers"]) == 119
                    and value["pendingModels"] == [] and len(value["triggerSounds"]) == 1,
                    "Original audio closure differs")
            context = value["context"]
            require(context["floor"] == "Stone" and context["gender"] == "Male"
                    and context["stageName"] == "SF3_Palace_Exterior.glb"
                    and context["stageSHA256"] == "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8",
                    "Floor sounds require their authenticated original stage")
            select(args.stage, {"name": context["stageName"], "bytes": 9_292_540,
                                "sha256": context["stageSHA256"]}, "stage")
        if group == "sword_effects":
            source_scopes[group] = value["erlangSwordScope"]
        if group == "skill_effects":
            source_scopes[group] = value["erlangSkillScopes"]
        select(directory, {"name": name, "bytes": path.stat().st_size, "sha256": identity[pin]}, group)
        require(len({f["name"] for f in files}) == len(files), "Duplicate manifest payload")
        for row in files:
            select(directory, row, group)
    total = sum(row[1]["bytes"] for row in plan.values())
    require(total <= 256_000_000, "Candidate exceeds the current in-app resource bound")
    output = args.output.absolute()
    require(not output.exists() and output.parent.resolve(strict=True) == output.parent,
            "Candidate output must be a new directory")
    os.mkdir(output, 0o700)
    target = output / "FighterPrivate"
    os.mkdir(target, 0o700)
    files = []
    for name, (source, row, groups) in sorted(plan.items()):
        destination = target / name
        with source.open("rb") as stream, destination.open("xb") as result:
            shutil.copyfileobj(stream, result)
        os.chmod(destination, 0o600)
        checked(destination, row["sha256"], row["bytes"])
        files.append(dict(row, groups=sorted(groups)))
    result = {
        "schema": "erlang-local-integrated-candidate-v1",
        "applicationIdentitySHA256": digest(identity_file),
        "baseReleaseSHA256": BASE_RELEASE_SHA256, "baseFilesPreserved": 302,
        "bodyProfileSHA256": identity["profileSHA256"], "characterSHA256": profile["sha256"],
        "files": files, "fileCount": len(files), "totalBytes": total,
        "sourceScopes": source_scopes,
        "baseNetworkCatalogUnchanged": True, "productionPanguActivated": False,
        "nativeRendered": False, "signed": False, "uploaded": False,
        "readyForTestFlight": False,
        "boundary": "Local integration candidate only. Separately authenticated D13 and D20 resources, remaining D15 effects and complete native acceptance are still required."
    }
    path = output / "erlang-local-candidate-receipt-private.json"
    with path.open("x") as stream:
        json.dump(result, stream, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        stream.write("\n")
    os.chmod(path, 0o600)
    return {k: result[k] for k in ("fileCount", "totalBytes", "baseFilesPreserved", "bodyProfileSHA256",
                                  "characterSHA256", "readyForTestFlight")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "body", "stage", *(row[0].replace("_", "-") for row in GROUPS), "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(stage(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
