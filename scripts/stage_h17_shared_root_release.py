#!/usr/bin/env python3
"""Stage existing floorfall media plus three source root-victim clips.

Only an independently pinned local candidate is consumed. No conversion, key
access, network, upload or activation occurs. Old catalog tracks are preserved;
the standalone append profile is used only for its three final new clips.
The 13 payloads omit the old GLB BIN and the old 28 MB catalog.
"""
from __future__ import annotations

import argparse
import base64
from copy import deepcopy
import json
from pathlib import Path
import struct
import sys

from stage_h17_floorfall_release import (
    BASE_PACK_SHA, BASE_RELEASE_SHA, MAX_TOTAL, RELEASE_NAME, AUDIO_NAME,
    checked_file, digest, encoded, fresh_output, parse_json, pinned_json,
    real_directory, record, regular, require, safe_name, write_private,
)

ROOT = Path(__file__).resolve().parents[1]
FLOORFALL_RECEIPT_SHA = "449f0545c7b9d880dfae2736264efa00a2f01639948a362910f6a57d4b47b285"
FLOORFALL_RELEASE_SHA = "fc85891d75aef9b236270e801d9d6d43661ff0f86fde812d4d1aa7996bc9ebbf"
FLOORFALL_AUDIO_SHA = "7451625a85eab8da8f296f4d412c94981e7d411706de7ea6e5b620c2f7d4d809"
CATALOG_SHA = "2fad3a3e958238b5a294ec7ecdc94d004eae515c252184c8385d7b8460ef4801"
OLD_CHARACTER_SHA = "f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472"
CHARACTER_SHA = "a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517"
PROFILE_SHA = "2dbe085bd288a4aff2bf9694d5e55699500879feb203985a342b76c1036b81ca"
APPEND_RECEIPT_SHA = "c9a1e608dfa56d0311bf459ad4dd5340a84e2e43f456161604bb47e8df8b66f3"
CHARACTER_NAME = "Liu_Legion_Hammers.glb"
CATALOG_NAME = "SF3_DistinctFighters.json"
GLB_PATCH_NAME = "Liu_Legion_Hammers.shared-root.glbdelta"
CATALOG_PATCH_NAME = "SF3_DistinctFighters.shared-root.jsonpatch"
MORPH_NAME = "SF3_H17_Morph.json"
TRAILS_NAME = "SF3WE_Target_Trails.json"
MORPH_SHA = "364003f89aed01b0db41c68726c71ecd92c714ed6ee443984ba430d3b52c16ff"
TRAILS_SHA = "1069fbdfee2b9198428c365f914d1eed4c9dab0bd88d4ecefe92042d6f9b511b"
TARGET_ID = "h17-shared-root-floorfall-20261115-v2"
PATCH_MAGIC = b"H17ROOT1"
MAX_PATCH = 4 * 1024 * 1024
NEW_CHARACTER_BYTES = 10_792_864
SOURCE_BUNDLE = "9893dca6e10355eb9c3c79d1613f08b1.bin"
CLIPS = [
    dict(name="h17_root_spike_passive_start", frames=44, bytes=61522,
         sha256="69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c",
         tracksSHA256="3275368e4cc8e7ee96e8f28a7040e43b780d902335c5cf178fb668e819748fcc"),
    dict(name="h17_root_spike_passive_loop", frames=61, bytes=85186,
         sha256="a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce",
         tracksSHA256="8dfbafe54551696c3b937455e46d3218bffbfd9bccfced3e5c877c3657d18170"),
    dict(name="h17_root_spike_passive_end", frames=48, bytes=67090,
         sha256="7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2",
         tracksSHA256="0e63eb602c7b3e3f5321a3d6399c08bb0b6100605bc23cb0edc403d2214092a8"),
]
FLOORFALL_NAMES = [
    "SF3H17_6_Body_Fall_V1_bip_63802beafb.wav", "SF3H17_6_Body_Fall_V3_bip_0d7e939477.wav",
    "SF3H17_6_Body_Fall_V5_bip_ff94cf9c13.wav", "SF3H17_6_Body_Fall_V8_bip_a19aa28789.wav",
    "SF3H17_6_Body_Fall_V13_bip_26d86c4046.wav", "SF3H17_6_Body_Fall_V15_bip_bca7f5cc5e.wav",
    "SF3H17_6_Body_Fall_V16_bip_83cefa768d.wav",
]
REPLACEMENTS = [RELEASE_NAME, AUDIO_NAME, CHARACTER_NAME, CATALOG_NAME, MORPH_NAME, TRAILS_NAME]


def inventory_from_pack(pack):
    require(pack["releaseSHA256"] == BASE_RELEASE_SHA, "Original base release differs")
    rows = [dict(name=r["file"], bytes=r["bytes"], sha256=r["sha256"]) for r in pack["files"]]
    require(len(rows) == 295 and len({safe_name(r["name"]) for r in rows}) == 295,
            "Expected the original 295-file base")
    require(all(type(r["bytes"]) is int and 0 < r["bytes"] <= 128_000_000 for r in rows)
            and sum(r["bytes"] for r in rows) <= MAX_TOTAL, "Base inventory exceeds bounds")
    return {r["name"]: r for r in rows}


def glb_chunks(raw):
    require(len(raw) >= 28 and len(raw) <= 32_000_000, "GLB byte bound differs")
    magic, version, total = struct.unpack_from("<III", raw)
    require(magic == 0x46546C67 and version == 2 and total == len(raw), "Malformed GLB header")
    size, kind = struct.unpack_from("<II", raw, 12)
    require(kind == 0x4E4F534A and size % 4 == 0 and 20 + size + 8 <= total, "Malformed GLB JSON chunk")
    json_raw = raw[20:20 + size]
    binary_size, binary_kind = struct.unpack_from("<II", raw, 20 + size)
    require(binary_kind == 0x004E4942 and binary_size % 4 == 0 and 28 + size + binary_size == total,
            "Expected exactly one GLB JSON chunk and one BIN chunk")
    document = parse_json(json_raw)
    require(len(document["buffers"]) == 1 and set(document["buffers"][0]) == {"byteLength"}
            and type(document["buffers"][0]["byteLength"]) is int
            and binary_size - 3 <= document["buffers"][0]["byteLength"] <= binary_size,
            "Unsupported GLB buffer layout")
    return document, json_raw, raw[28 + size:]


def validate_glb_append(old, new):
    old_g, old_json, old_bin = glb_chunks(old)
    new_g, new_json, new_bin = glb_chunks(new)
    require(new_bin[:len(old_bin)] == old_bin and len(new_bin) > len(old_bin), "Old GLB BIN prefix changed")
    require(set(old_g) == set(new_g), "GLB top-level structure changed")
    appended = {"animations", "accessors", "bufferViews"}
    for key in old_g:
        if key in appended:
            require(isinstance(old_g[key], list) and isinstance(new_g[key], list)
                    and new_g[key][:len(old_g[key])] == old_g[key], "Old GLB array records changed")
        elif key != "buffers":
            require(new_g[key] == old_g[key], "Existing GLB model, skin or material changed")
    require(len(old_g["animations"]) == 56 and len(new_g["animations"]) == 59
            and [a["name"] for a in new_g["animations"][56:]] == [c["name"] for c in CLIPS],
            "Shared-root animation append differs")
    return old_bin, new_json, new_bin[len(old_bin):]


def glb_patch(old, new):
    prefix, new_json, suffix = validate_glb_append(old, new)
    payload = struct.pack("<8sIIII", PATCH_MAGIC, len(prefix), len(new_json), len(suffix), len(new)) + new_json + suffix
    require(len(payload) <= MAX_PATCH, "GLB append payload exceeds bound")
    return payload, dict(retainedBINBytes=len(prefix), retainedBINSHA256=digest(prefix),
                         jsonChunkBytes=len(new_json), jsonChunkSHA256=digest(new_json),
                         appendedBINBytes=len(suffix), appendedBINSHA256=digest(suffix))


def rebuild_glb(old, patch):
    require(24 <= len(patch) <= MAX_PATCH, "GLB patch size differs")
    magic, retained, json_size, suffix_size, total = struct.unpack_from("<8sIIII", patch)
    require(magic == PATCH_MAGIC and json_size > 0 and suffix_size > 0 and
            json_size % 4 == suffix_size % 4 == 0 and len(patch) == 24 + json_size + suffix_size,
            "Malformed append patch")
    _, _, old_bin = glb_chunks(old)
    require(retained == len(old_bin) and total == 28 + json_size + retained + suffix_size,
            "Append patch cannot trim or replace the old BIN")
    new_json, suffix = patch[24:24 + json_size], patch[24 + json_size:]
    result = (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", json_size, 0x4E4F534A) +
              new_json + struct.pack("<II", retained + suffix_size, 0x004E4942) + old_bin + suffix)
    validate_glb_append(old, result)
    return result


def validate_new_clips(clips):
    require(isinstance(clips, list) and len(clips) == 3, "Expected exactly three new clips")
    for clip, pin in zip(clips, CLIPS):
        require(clip["name"] == pin["name"] and clip["frames"] == pin["frames"]
                and clip["sha256"] == pin["sha256"] and clip["bundle"] == SOURCE_BUNDLE,
                "Shared source motion identity differs")
        source = base64.b64decode(clip["sourceBytesBase64"], validate=True)
        require(len(source) == pin["bytes"] and digest(source) == pin["sha256"], "Source motion bytes differ")
        require(digest(encoded(clip["tracks"])) == pin["tracksSHA256"], "Verified Liu rig tracks differ")
        require(clip["sourceArrayCount"] == 2 and len(clip["sourceBoneIDs"]) == 58
                and clip["tracks"]["samplesPerSourceFrame"] == 2
                and len(clip["tracks"]["hurtCapsules"]) == 15,
                "Verified source rig/timing coverage differs")


def append_catalog(base, clips):
    validate_new_clips(clips)
    require(base["schemaVersion"] == 1 and len(base["profiles"]) == 2
            and {p["id"] for p in base["profiles"]} == {"sun_triad", "liu_hammers"}, "Catalog identity differs")
    old = next(p for p in base["profiles"] if p["id"] == "liu_hammers")
    require(len(old["clips"]) == 56 and old["sha256"] == OLD_CHARACTER_SHA
            and old["bytes"] == 10_438_952 and old["bodyID"] == "arm__str_03"
            and old["weaponID"] == "wpn__hammers_01_01", "Original Liu profile identity differs")
    require(not {c["name"] for c in old["clips"]} & {c["name"] for c in clips}, "Appended clip collides")
    new = dict(old, bytes=NEW_CHARACTER_BYTES, sha256=CHARACTER_SHA, clips=[*old["clips"], *clips])
    return dict(base, profiles=[new if p["id"] == "liu_hammers" else p for p in base["profiles"]])


def catalog_patch(old_raw, clips):
    require(digest(old_raw) == CATALOG_SHA, "Base catalog pin differs")
    base = parse_json(old_raw)
    require(encoded(base) == old_raw, "Base catalog canonical encoding differs")
    target = encoded(append_catalog(base, clips))
    patch = dict(schema="liu-h17-shared-root-catalog-append-v1", profileID="liu_hammers", priorClipCount=56,
                 base=record(CATALOG_NAME, old_raw), target=record(CATALOG_NAME, target),
                 oldCharacterSHA256=OLD_CHARACTER_SHA, characterSHA256=CHARACTER_SHA,
                 characterBytes=NEW_CHARACTER_BYTES, appendedClips=clips)
    raw = encoded(patch)
    require(len(raw) <= MAX_PATCH, "Catalog append payload exceeds bound")
    return raw, target


def rebuild_catalog(old_raw, raw):
    require(0 < len(raw) <= MAX_PATCH and digest(old_raw) == CATALOG_SHA, "Catalog patch/base bound differs")
    patch = parse_json(raw)
    require(set(patch) == {"schema", "profileID", "priorClipCount", "base", "target",
            "oldCharacterSHA256", "characterSHA256", "characterBytes", "appendedClips"}
            and patch["schema"] == "liu-h17-shared-root-catalog-append-v1"
            and patch["profileID"] == "liu_hammers" and patch["priorClipCount"] == 56
            and patch["base"] == record(CATALOG_NAME, old_raw)
            and patch["oldCharacterSHA256"] == OLD_CHARACTER_SHA and patch["characterSHA256"] == CHARACTER_SHA
            and patch["characterBytes"] == NEW_CHARACTER_BYTES, "Catalog patch contract differs")
    target = encoded(append_catalog(parse_json(old_raw), patch["appendedClips"]))
    require(record(CATALOG_NAME, target) == patch["target"], "Reconstructed catalog digest differs")
    return target


def revised_audio(base):
    require(base["version"] == 2 and base["profileID"] == "sun_triad"
            and base["motionProfiles"] == {"liu_hammers": OLD_CHARACTER_SHA}
            and len(base["files"]) == 95 and len(base["markers"]) == 114,
            "Floorfall audio base differs")
    require(base["markers"][-1] == dict(id="source_floorfall_923_97_h17_root_spike_passive_end",
            clip=CLIPS[-1]["name"], sourceFrame=20, clock="intervalStart", context="Common", files=FLOORFALL_NAMES),
            "Source floorfall array/order differs")
    result = deepcopy(base)
    result["motionProfiles"]["liu_hammers"] = CHARACTER_SHA
    marker = dict(id="source_floorfall_923_97_liu_hammers_h17_root_spike_passive_end",
                  profileID="liu_hammers", clip=CLIPS[-1]["name"], sourceFrame=20,
                  clock="intervalStart", context="Common", files=list(FLOORFALL_NAMES))
    require(marker["id"] not in {m["id"] for m in result["markers"]}, "New audio marker ID collides")
    result["markers"].append(marker)
    return result


def revised_morph(base):
    require(base["version"] == 2 and base["ownerProfileID"] == "sun_triad"
            and base["targetProfileID"] == "liu_hammers" and base["targetCharacterSHA256"] == OLD_CHARACTER_SHA,
            "Source morph target identity differs")
    result = deepcopy(base)
    result["targetCharacterSHA256"] = CHARACTER_SHA
    return result


def revised_trails(base):
    require(base["version"] == 3 and base["legacy"]["profileIDs"] == ["liu_hammers"]
            and len(base["legacy"]["rebindings"]) == 1, "Source trails legacy identity differs")
    binding = base["legacy"]["rebindings"][0]
    require(binding["id"] == "liu_hammers" and binding["mode"] == "appendSourceAnimations"
            and binding["toSHA256"] == OLD_CHARACTER_SHA, "Source trails rebound target differs")
    result = deepcopy(base)
    result["legacy"]["rebindings"][0]["toSHA256"] = CHARACTER_SHA
    return result


def rebind_json_raw(raw, pin, transform):
    require(digest(raw) == pin and raw.count(OLD_CHARACTER_SHA.encode()) == 1,
            "Bound resource pin or target occurrence differs")
    result = raw.replace(OLD_CHARACTER_SHA.encode(), CHARACTER_SHA.encode(), 1)
    require(parse_json(result) == transform(parse_json(raw)), "Binding update changed unrelated JSON fields")
    return result


def revised_release(base, catalog_row, audio_row, morph_row, trails_row):
    require(base["schemaVersion"] == 2 and base["id"] == "h17-source-floorfall-20261114"
            and base["panguAudio"] is None and len(base["profiles"]) == 2
            and {p["id"] for p in base["profiles"]} == {"sun_triad", "liu_hammers"},
            "Floorfall release identity differs")
    result = deepcopy(base)
    require(base["triadMorph"]["name"] == MORPH_NAME and base["triadMorph"]["sha256"] == MORPH_SHA
            and base["sourceTrails"]["name"] == TRAILS_NAME and base["sourceTrails"]["sha256"] == TRAILS_SHA,
            "Release morph/trails references differ")
    result.update(id=TARGET_ID, catalog=catalog_row, triadAudio=audio_row,
                  triadMorph=morph_row, sourceTrails=trails_row)
    liu = next(p for p in result["profiles"] if p["id"] == "liu_hammers")
    require(liu["characterSHA256"] == OLD_CHARACTER_SHA and len(liu["motions"]) == 56
            and liu["bodyID"] == "arm__str_03" and liu["weaponID"] == "wpn__hammers_01_01",
            "Liu release identity differs")
    liu["characterSHA256"] = CHARACTER_SHA
    liu["motions"].extend(dict(clip=c["name"], sourceSHA256=c["sha256"], sourceBundle=SOURCE_BUNDLE,
                               frames=c["frames"], exportFramesPerSecond=30, sourceFramesPerSecond=30) for c in CLIPS)
    return result


def stage(args):
    output = fresh_output(args.output)
    base, floorfall, candidate = map(real_directory, (args.base, args.floorfall, args.candidate))
    output = fresh_output(output, (base, floorfall, candidate))
    pack = pinned_json(args.pack_manifest, BASE_PACK_SHA, 2_000_000)
    inventory = inventory_from_pack(pack)
    floor_receipt = pinned_json(args.floorfall_receipt, FLOORFALL_RECEIPT_SHA, 2_000_000)
    require(floor_receipt["basePackManifestSHA256"] == BASE_PACK_SHA
            and floor_receipt["release"]["sha256"] == FLOORFALL_RELEASE_SHA,
            "Floorfall assembly prerequisites differ")
    floor_rows = {safe_name(r["name"]): r for r in floor_receipt["files"]}
    require(len(floor_receipt["files"]) == len(floor_rows) == 302
            and set(floor_rows) == set(inventory) | set(FLOORFALL_NAMES), "Floorfall inventory differs")
    require(all(floor_rows[n] == row for n, row in inventory.items() if n not in (RELEASE_NAME, AUDIO_NAME)),
            "Floorfall overlay changed unrelated resources")
    require({p.name for p in base.iterdir()} == set(inventory)
            and {p.name for p in floorfall.iterdir()} == set(floor_rows), "Input directory closure differs")
    append_receipt = pinned_json(candidate / "root-victim-append-receipt-private.json", APPEND_RECEIPT_SHA, 32_768)
    require(append_receipt["inputCharacterSHA256"] == OLD_CHARACTER_SHA
            and append_receipt["outputCharacterSHA256"] == CHARACTER_SHA
            and append_receipt["outputProfileSHA256"] == PROFILE_SHA
            and append_receipt["oldClipsPreserved"] == 56
            and append_receipt["panguEquipmentActivated"] is False
            and append_receipt["resourceReclassified"] is False, "Append receipt identity differs")
    profile = pinned_json(candidate / "Liu_Legion_Hammers_profile.json", PROFILE_SHA, 16_000_000)
    require(profile["id"] == "liu_hammers" and profile["sha256"] == CHARACTER_SHA
            and profile["bytes"] == NEW_CHARACTER_BYTES and len(profile["clips"]) == 59,
            "Candidate standalone profile differs")
    new_model = regular(candidate / CHARACTER_NAME, NEW_CHARACTER_BYTES)
    require(record(CHARACTER_NAME, new_model) == dict(name=CHARACTER_NAME, bytes=NEW_CHARACTER_BYTES,
            sha256=CHARACTER_SHA), "Candidate model differs")
    old_model = checked_file(base, inventory[CHARACTER_NAME])
    require(digest(old_model) == OLD_CHARACTER_SHA, "Base model differs")
    model_patch, geometry = glb_patch(old_model, new_model)
    require(rebuild_glb(old_model, model_patch) == new_model, "GLB reconstruction differs")
    old_catalog = checked_file(base, inventory[CATALOG_NAME])
    patch_catalog, new_catalog = catalog_patch(old_catalog, profile["clips"][56:])
    require(rebuild_catalog(old_catalog, patch_catalog) == new_catalog, "Catalog reconstruction differs")
    old_audio = checked_file(floorfall, floor_rows[AUDIO_NAME])
    require(digest(old_audio) == FLOORFALL_AUDIO_SHA, "Floorfall audio differs")
    new_audio = encoded(revised_audio(parse_json(old_audio)))
    new_morph = rebind_json_raw(checked_file(base, inventory[MORPH_NAME]), MORPH_SHA, revised_morph)
    new_trails = rebind_json_raw(checked_file(base, inventory[TRAILS_NAME]), TRAILS_SHA, revised_trails)
    old_release = checked_file(floorfall, floor_rows[RELEASE_NAME])
    require(digest(old_release) == FLOORFALL_RELEASE_SHA, "Floorfall release differs")
    new_release = encoded(revised_release(parse_json(old_release), record(CATALOG_NAME, new_catalog),
                                         record(AUDIO_NAME, new_audio), record(MORPH_NAME, new_morph),
                                         record(TRAILS_NAME, new_trails)))
    changed = {CHARACTER_NAME: new_model, CATALOG_NAME: new_catalog, AUDIO_NAME: new_audio,
               MORPH_NAME: new_morph, TRAILS_NAME: new_trails, RELEASE_NAME: new_release}
    for name in FLOORFALL_NAMES:
        require(name not in inventory, "New audio collides with base")
        changed[name] = checked_file(floorfall, floor_rows[name])
    target = dict(inventory)
    target.update({name: record(name, value) for name, value in changed.items()})
    require(len(target) == 302 and len(changed) == 13 and sum(r["bytes"] for r in target.values()) <= MAX_TOTAL,
            "Target resource bounds differ")
    payloads = {n: v for n, v in changed.items() if n not in (CHARACTER_NAME, CATALOG_NAME)}
    payloads.update({GLB_PATCH_NAME: model_patch, CATALOG_PATCH_NAME: patch_catalog})
    require(len(payloads) == 13 and sum(len(v) for v in payloads.values()) <= 8 * 1024 * 1024,
            "Transport exceeds thirteen compact payloads")
    delta = dict(schema="fighter-h17-shared-root-delta-v1", basePackManifestSHA256=BASE_PACK_SHA,
        baseReleaseSHA256=BASE_RELEASE_SHA, sourceFloorfallReleaseSHA256=FLOORFALL_RELEASE_SHA,
        targetRelease=target[RELEASE_NAME], replacements=REPLACEMENTS, additions=sorted(FLOORFALL_NAMES),
        files=[target[n] for n in sorted(changed)], payloads=[record(n, payloads[n]) for n in sorted(payloads)],
        transforms=[dict(kind="glb-bin-append-v1", target=CHARACTER_NAME, payload=GLB_PATCH_NAME,
                         base=inventory[CHARACTER_NAME], **geometry),
                    dict(kind="catalog-three-clip-append-v1", target=CATALOG_NAME, payload=CATALOG_PATCH_NAME,
                         base=inventory[CATALOG_NAME], priorClipCount=56, appendedClips=[c["name"] for c in CLIPS])],
        unchangedBaseFiles=289, requiresIndependentSignedBuildPin=True, encrypted=False, uploaded=False)
    raw_delta = encoded(delta)
    for row in inventory.values():
        current = checked_file(base, row)
        if row["name"].endswith(".json"):
            require(OLD_CHARACTER_SHA.encode() not in changed.get(row["name"], current),
                    "An active JSON resource still references the old Liu character")
    result = dict(schema="private-h17-shared-root-staged-release-v1", basePackManifestSHA256=BASE_PACK_SHA,
        baseReleaseSHA256=BASE_RELEASE_SHA, floorfallReleaseSHA256=FLOORFALL_RELEASE_SHA,
        appendReceiptSHA256=APPEND_RECEIPT_SHA, release=target[RELEASE_NAME],
        files=[target[n] for n in sorted(target)], deltaManifestSHA256=digest(raw_delta), delta=delta,
        transportBytes=sum(len(v) for v in payloads.values()), payloadFiles=13, resourceChanges=13,
        unchangedBaseFiles=289, addedPCMFiles=7, PCMFiles=95, audioMarkers=115, oldAudioMarkersPreserved=114,
        oldLiuCatalogClipsPreserved=56, appendedLiuClips=3, oldGLBBINPreserved=True,
        catalogRulesPreserved=True, H17ProfilePreserved=True, morphTargetRebound=True,
        trailsTargetRebound=True, oldLiuHashReferencesInJSON=0, panguEquipmentActivated=False,
        sourceAssetsReencoded=False, existingInputsModified=False, uploaded=False,
        iosLoadingVerified=False, iosPlaybackVerified=False, physicalDeviceVerified=False,
        buildSetting={"FIGHTER_ASSET_RELEASE_SHA256": target[RELEASE_NAME]["sha256"]})
    output.mkdir(mode=0o700)
    full, incremental = output / "FighterPrivate", output / "delta"
    full.mkdir(mode=0o700); incremental.mkdir(mode=0o700)
    for name in sorted(target):
        write_private(full / name, changed[name] if name in changed else checked_file(base, inventory[name]))
    for name in sorted(payloads):
        write_private(incremental / name, payloads[name])
    write_private(output / "delta-manifest-private.json", raw_delta)
    write_private(output / "assembly-receipt-private.json", encoded(result))
    return dict(staged=True, output=str(output), releaseSHA256=target[RELEASE_NAME]["sha256"],
                deltaManifestSHA256=digest(raw_delta), audioSHA256=target[AUDIO_NAME]["sha256"],
                catalogSHA256=target[CATALOG_NAME]["sha256"], morphSHA256=target[MORPH_NAME]["sha256"],
                trailsSHA256=target[TRAILS_NAME]["sha256"], files=302, resourceChanges=13, payloadFiles=13,
                transportBytes=result["transportBytes"], retainedBINBytes=geometry["retainedBINBytes"],
                oldCatalogClipsPreserved=56, audioMarkers=115, uploaded=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("base", "floorfall", "floorfall-receipt", "candidate", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--pack-manifest", type=Path, default=ROOT / ".github/private/fighter-h17-d19/manifest.json")
    try:
        result = stage(parser.parse_args())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(json.dumps(dict(staged=False, errorType=type(error).__name__)), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
