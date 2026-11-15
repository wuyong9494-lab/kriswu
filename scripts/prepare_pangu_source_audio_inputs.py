#!/usr/bin/env python3
"""Verify original D19 sound-marker inputs without creating a runtime release.

Offline only. Existing reviewed PCM is reused after bundle, container, AudioClip,
encoded-resource and WAV checks. Optional decoding is limited to indexed clips
that have no reviewed PCM receipt. Original Sounds.Frame is clamped at zero;
clip cropping, cast-phase timing and runtime binding remain unresolved here.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import redirect_stderr, redirect_stdout
import copy
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import wave
import zipfile

MOTION_SHA256 = "baa0a83c58348c3842b4a442ea534f875168a93a411646ed6c7e07e5d2941d45"
MOTION_BYTES = 52747
CATALOG_MEMBER = "research/android_bundle_catalog.jsonl"
CATALOG_SHA256 = "2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055"
CATALOG_BYTES = 9100700
SETTINGS_VALUES_SHA256 = "a4b3023f669becc039c2b546e1c6f171fc89e84e1ecb82688b5db2dc66aea64b"
SETTINGS_VALUES_BYTES = 1111299
SETTINGS_STORAGE_SHA256 = "44664e48acf70462c8285029bbf861a19cbc6df26804c28c7efc4d0d2c77b9b2"
SETTINGS_STORAGE_BYTES = 790977
SETTINGS_SOURCE_SHA256 = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
PRIOR_PLAN_SHA256 = "7f4492df25afc1ce3825d1a6872f20cd268436dbd6c68c45669966c20fcf5729"
PRIOR_LOCATIONS_SHA256 = "e252b98fb4cb63bdb035e544e2b6b40c4ec248399af781a7c5e7839cb6653418"
# Native animation schema method 16684 / generated readers 16478..16506.
ANIMATION_FIELDS = (
    "Animation", "FileName", "MidFrames", "Style", "TacticsGroups", "FirstFrame", "EndFrame",
    "Looped", "Mirrored", "BlendingFrames", "SelfEndFrame", "SelfNoMirroring", "IgnoreWeaponMirroring",
    "ShowAllSkeletons", "ForceDetachWeapon", "SaveMirroringOnNextAnimation", "ForceDisableSnapping",
    "WeaponSwitchFrames", "EndsStage", "Groups", "ComboAnimations", "SetDirection", "Velocity", "Align",
    "Transitions", "RepulsionScale", "Sounds", "Intervals", "AttackType",
)
REVIEWED_PCM = {
    "h17-context-audio-inventory-private.json": (
        "06a0b02587c55106b851f33aad1a7b10a480e5fad846d26c17a0510351974736", "files"),
    "h17-audio-binding-provenance-private.json": (
        "2eaf22eb311bbb9006a214199f52dc5e81179d01d97931a18d465a6b47a3b35e", "decodedSourceFiles"),
    "h17-common-context-audio-inventory-private.json": (
        "b1557aafc28213d6e2ed9aa975473c2649b94e48a10ced20da07bce6eab43bef", "files"),
}
PREFIX = "assets/gamedata/resources/audio/sounds/"
MAX_WAV = 4_000_000


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON field")
        result[key] = value
    return result


def json_value(data):
    return json.loads(data, object_pairs_hook=unique_object,
                      parse_constant=lambda value: require(False, "Non-finite JSON number"))


def regular(path, maximum):
    path = Path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum,
                "Input must be a bounded regular file")
        data = stream.read(maximum + 1)
    require(len(data) == info.st_size, "Input changed while being read")
    return data


def basename(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", value)
            and value not in (".", ".."), "Unsafe input filename")
    return value


def source_path(value):
    require(isinstance(value, str), "Sound identifier must be text")
    parts = value.split("@")
    require(len(parts) == 3 and parts[1] == "Battle" and parts[2] in ("Movement", "Voice", "WeaponAndArmor"),
            "Unexpected original sound routing")
    relative = PurePosixPath(parts[0])
    require(re.fullmatch(r"[A-Za-z0-9_./-]+", parts[0]) and not relative.is_absolute()
            and all(part not in (".", "..") for part in parts[0].split("/"))
            and "" not in parts[0].split("/"), "Unsafe original sound path")
    return PREFIX + parts[0].lower() + ".wav"


def named_sound(value):
    require(isinstance(value, list) and len(value) == 4, "Original sound schema differs")
    sound = dict(zip(("Frame", "Common", "Gender", "Floor"), copy.deepcopy(value)))
    for key, fields in (("Gender", ("Male", "Female", "Monkey")),
                        ("Floor", ("Stone", "Wood", "Metal", "Ground"))):
        if sound[key] is not None:
            require(isinstance(sound[key], list) and len(sound[key]) == len(fields),
                    "Original sound-context schema differs")
            sound[key] = dict(zip(fields, sound[key]))
    return sound


def extend_motion_inventory(inventory, values):
    """Missing motion bytes do not erase the source configuration's sound rows."""
    selected = {}
    for index, value in enumerate(values):
        require(isinstance(value, list) and len(value) == len(ANIMATION_FIELDS), "Original animation schema differs")
        if not value[0].startswith("D19_"):
            continue
        require(value[0] not in selected, "Duplicate source D19 alias")
        config = dict(zip(ANIMATION_FIELDS, value))
        config["Sounds"] = None if config["Sounds"] is None else [named_sound(sound) for sound in config["Sounds"]]
        selected[value[0]] = (index, config)
    expected = {record["animation"] for record in inventory["records"] + inventory["unrecovered"]}
    require(set(selected) == expected, "Source settings and recovered/missing alias inventories differ")
    extended = copy.deepcopy(inventory)
    for record in extended["records"]:
        index, config = selected[record["animation"]]
        require(index == record["configurationSource"]["recordIndex"]
                and config["FileName"] == record["motion"]["sourceFile"]
                and config["Sounds"] == record["soundMarkers"]
                and all(config[key] == value for key, value in record["rawMarkers"].items()),
                "Previously recovered alias differs from the original settings")
        record["motionBytesRecovered"] = True
    marker_fields = tuple(inventory["records"][0]["rawMarkers"])
    for missing in inventory["unrecovered"]:
        index, config = selected[missing["animation"]]
        require(config["FileName"] == missing["sourceFile"], "Missing motion alias points to a different source file")
        extended["records"].append({"animation": missing["animation"], "motionBytesRecovered": False,
            "configurationSource": {"entry": "settings_sets_dynasty.bytes", "sha256": SETTINGS_SOURCE_SHA256, "recordIndex": index},
            "motion": {"sourceFile": missing["sourceFile"], "sourceBundle": None,
                       "sourceObjectPath": "assets/gamedata/resources/content/animations/binaries/" + str(PurePosixPath(missing["sourceFile"]).with_suffix(".bytes")),
                       "pathID": None, "bytes": None, "sha256": None},
            "rawMarkers": {key: copy.deepcopy(config[key]) for key in marker_fields},
            "soundMarkers": config["Sounds"]})
    return extended


def marker_groups(inventory):
    """Retain original ordering and alternative groups; never infer clip/ticks."""
    aliases, groups, identifiers = [], [], {}
    for record in inventory["records"]:
        sounds = record["soundMarkers"]
        if not sounds:
            continue
        aliases.append({"animation": record["animation"],
                        "motionBytesRecovered": record.get("motionBytesRecovered", True),
                        "configurationSource": copy.deepcopy(record["configurationSource"]),
                        "motion": {key: copy.deepcopy(record["motion"][key]) for key in
                                   ("sourceFile", "sourceBundle", "sourceObjectPath", "pathID", "bytes", "sha256")},
                        "rawTiming": copy.deepcopy(record["rawMarkers"]),
                        "rawSoundMarkers": copy.deepcopy(sounds)})
        for index, sound in enumerate(sounds):
            frame = sound["Frame"]
            require(type(frame) is int, "Sound Frame must be explicit; absent values need source evidence")
            gender = sound.get("Gender") or {}
            for route, values in (("Sounds.Common", sound.get("Common")),
                                  ("Sounds.Gender.Male", gender.get("Male"))):
                if not values:
                    continue
                require(isinstance(values, list) and len(values) <= 32, "Unbounded sound alternatives")
                paths = [source_path(value) for value in values]
                for value, path in zip(values, paths):
                    if path in identifiers:
                        require(identifiers[path] == value, "Conflicting original sound identifiers")
                    identifiers[path] = value
                groups.append({"animation": record["animation"], "soundIndex": index,
                               "route": route, "rawFrame": frame, "sourceFrame": max(0, frame),
                               "sourceIdentifiers": list(values), "sourcePaths": paths,
                               "runtimeClip": None, "runtimeTick": None,
                               "bindingStatus": "source-inputs-only"})
    return aliases, groups, identifiers


def catalog_matches(rows, wanted):
    matches = {path: [] for path in wanted}
    for row in rows:
        for resource in row["paths"]:
            path = resource["path"].lower()
            if path not in matches:
                continue
            require(resource["file_id"] == 0 and type(resource["path_id"]) is int,
                    "Original AudioClip must be local to its catalog bundle")
            require(row.get("crc_ok") is True and row.get("types", {}).get("AudioClip", 0) > 0,
                    "Catalog entry is not an authenticated audio bundle")
            require(re.fullmatch(r"[0-9a-f]{64}", row["sha256"])
                    and type(row["bytes"]) is int and 0 < row["bytes"] <= 16_000_000,
                    "Invalid catalog bundle identity")
            matches[path].append({"bundle": basename(row["file"]), "bundleBytes": row["bytes"],
                                  "bundleSHA256": row["sha256"], "pathID": str(resource["path_id"]),
                                  "fileID": resource["file_id"]})
    require(all(len(items) <= 1 for items in matches.values()), "Ambiguous original audio container path")
    return {path: items[0] if items else None for path, items in matches.items()}


def load_reviewed_pcm(paths, wanted):
    available, receipts = {}, []
    for path in paths:
        require(path.name in REVIEWED_PCM, "Unreviewed PCM provenance snapshot")
        expected, field = REVIEWED_PCM[path.name]
        data = regular(path, 1_000_000)
        require(sha(data) == expected, "Reviewed PCM provenance snapshot differs")
        document = json_value(data)
        receipt = {"name": path.name, "bytes": len(data), "sha256": expected}
        receipts.append(receipt)
        for row in document[field]:
            original = row["sourcePath"]
            if original not in wanted:
                continue
            if original in available:
                require(available[original][0] == row, "Conflicting reviewed PCM provenance")
            else:
                available[original] = (row, path.parent, receipt)
    return available, receipts


def load_prepared_pcm(plan_path, locations_path, wanted):
    """Reuse the three already prepared originals through their fixed receipt."""
    plan_raw = regular(plan_path, 100_000)
    require(sha(plan_raw) == PRIOR_PLAN_SHA256, "Previously prepared input plan differs")
    locations_raw = regular(locations_path, 100_000)
    require(sha(locations_raw) == PRIOR_LOCATIONS_SHA256, "Previously prepared PCM locator receipt differs")
    plan, locations = json_value(plan_raw), json_value(locations_raw)
    require(plan["schema"] == "pangu-source-audio-input-plan-v1"
            and locations["schema"] == "pangu-source-audio-locations-private-v1", "Unexpected prepared PCM snapshot")
    by_source = {row["sourcePath"]: row for row in locations["files"]}
    require(len(by_source) == len(locations["files"]) == 24, "Ambiguous prepared PCM locations")
    receipt = {"name": plan_path.name, "bytes": len(plan_raw), "sha256": PRIOR_PLAN_SHA256,
               "kind": "previously-prepared-source-pcm"}
    available = {}
    for item in plan["inputs"]:
        source = item["sourcePath"]
        if source not in wanted or item.get("pcm", {}).get("reusedExistingPCM") is not False:
            continue
        pcm, verified, location = item["pcm"], item["verifiedSource"], by_source[source]
        require(item["status"] == "verified-local-pcm" and pcm["sha256"] == location["sha256"]
                and pcm["bytes"] == location["bytes"] and Path(location["path"]).name == pcm["name"],
                "Prepared PCM identity differs from its location")
        row = {key: pcm[key] for key in ("name", "bytes", "sha256", "sampleRate", "channels", "sampleFrames", "sampleWidth")}
        row.update(sourcePath=source, sourcePathID=verified["pathID"], sourceBundle=verified["bundle"],
                   sourceBundleSHA256=verified["bundleSHA256"], sourceObjectSHA256=verified["objectSHA256"],
                   encodedSHA256=verified["encodedSHA256"], encodedBytes=verified["encodedBytes"],
                   sourceName=verified["sourceName"])
        available[source] = (row, Path(location["path"]).parent, receipt)
    require(len(available) == 3, "Expected exactly the three previously prepared original sounds")
    return available, receipt


def pcm_properties(data, clip):
    require(0 < len(data) <= MAX_WAV, "Decoded WAV exceeds its bound")
    with wave.open(io.BytesIO(data), "rb") as wav:
        rate, channels = wav.getframerate(), wav.getnchannels()
        frames, width = wav.getnframes(), wav.getsampwidth()
        require(wav.getcomptype() == "NONE" and width == 2 and channels in (1, 2)
                and 8_000 <= rate <= 192_000 and 0 < frames <= rate * 30,
                "Original WAV is not bounded PCM16")
        pcm = wav.readframes(frames + 1)
        require(len(pcm) == frames * channels * width and not wav.readframes(1), "Truncated PCM samples")
    require(rate == clip.m_Frequency and channels == clip.m_Channels,
            "Decoded format differs from the original AudioClip")
    require(math.isfinite(clip.m_Length) and abs(frames / rate - clip.m_Length) < 2 / rate,
            "Decoded duration differs from the original AudioClip")
    return {"bytes": len(data), "sha256": sha(data), "sampleRate": rate, "channels": channels,
            "sampleFrames": frames, "sampleWidth": width, "pcmSHA256": sha(pcm)}


def reuse_pcm(source, identity, clip, reviewed):
    row, parent, receipt = reviewed
    expected = {"sourcePath": source, "sourcePathID": identity["pathID"],
                "sourceBundle": identity["bundle"], "sourceBundleSHA256": identity["bundleSHA256"],
                "sourceObjectSHA256": identity["objectSHA256"], "encodedSHA256": identity["encodedSHA256"],
                "encodedBytes": identity["encodedBytes"], "sourceName": clip.m_Name}
    require(all(row.get(key) == value for key, value in expected.items()),
            "Reviewed PCM belongs to a different source object or encoded resource")
    path = parent / basename(row["name"])
    properties = pcm_properties(regular(path, MAX_WAV), clip)
    require(all(row.get(key) == properties[key] for key in
                ("bytes", "sha256", "sampleRate", "channels", "sampleFrames", "sampleWidth")),
            "Reviewed WAV bytes or PCM metadata differ")
    return {"name": path.name, **properties, "reusedExistingPCM": True,
            "provenance": receipt}, path


def write_new(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def decode_new_pcm(identity, clip, output):
    stem = re.sub(r"[^A-Za-z0-9_]+", "_", clip.m_Name)[:70]
    filename = "SF3PanguSource_" + stem + "_" + identity["encodedSHA256"][:12] + ".wav"
    path = output / filename
    require(not path.exists(), "A prepared PCM already exists; preserve its receipt instead of decoding again")
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        samples = clip.samples
    require(len(samples) == 1, "Original decoder returned ambiguous samples")
    original_name, data = next(iter(samples.items()))
    require(original_name.endswith(".wav"), "Original decoder did not return WAV")
    properties = pcm_properties(data, clip)
    write_new(path, data)
    return {"name": filename, **properties, "reusedExistingPCM": False,
            "decoder": "UnityPy AudioClip.samples; original frequency/channels; no gain or resampling"}, path


def verify_audio_inputs(identifiers, matches, bundle_directories, reviewed, output, decode_missing):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
    environments, inputs, locations = {}, [], []
    for source in sorted(identifiers):
        catalog = matches[source]
        record = {"identifier": identifiers[source], "sourcePath": source,
                  "status": "not-in-reviewed-catalog", "catalog": catalog,
                  "sharedOriginalAudio": not source.startswith(PREFIX + "set_d19/")}
        inputs.append(record)
        if catalog is None:
            continue
        bundle = catalog["bundle"]
        if bundle not in environments:
            candidates = [directory / bundle for directory in bundle_directories if (directory / bundle).exists()]
            if not candidates:
                environments[bundle] = None
            else:
                for candidate in candidates:
                    data = regular(candidate, 16_000_000)
                    require(len(data) == catalog["bundleBytes"] and sha(data) == catalog["bundleSHA256"],
                            "Original audio bundle bytes differ from the reviewed catalog")
                with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    environment = UnityPy.load(data)
                container = {}
                for path, pointer in environment.container.items():
                    normalized = path.lower()
                    require(normalized not in container, "Duplicate original bundle container path")
                    container[normalized] = pointer
                environments[bundle] = (environment, container)
        if environments[bundle] is None:
            record["status"] = "indexed-bundle-not-local"
            continue
        _, container = environments[bundle]
        require(source in container, "Indexed source path is missing from its actual bundle")
        pointer = container[source]
        obj = pointer.deref()
        require(obj.type.name == "AudioClip" and str(obj.path_id) == catalog["pathID"],
                "Actual AudioClip type or pathID differs from the catalog")
        clip = pointer.read()
        resource = clip.m_Resource
        encoded = get_resource_data(resource.m_Source, clip.object_reader.assets_file,
                                    resource.m_Offset, resource.m_Size)
        require(0 < len(encoded) <= MAX_WAV, "Original encoded sound exceeds its bound")
        identity = {**catalog, "objectSHA256": sha(obj.get_raw_data()),
                    "encodedSHA256": sha(encoded), "encodedBytes": len(encoded)}
        record["verifiedSource"] = {**identity, "type": "AudioClip", "sourceName": clip.m_Name}
        if source in reviewed:
            pcm, location = reuse_pcm(source, identity, clip, reviewed[source])
        elif decode_missing:
            pcm, location = decode_new_pcm(identity, clip, output)
        else:
            record["status"] = "source-object-verified-pcm-not-prepared"
            continue
        record.update(status="verified-local-pcm", pcm=pcm)
        locations.append({"sourcePath": source, "path": str(location.resolve()),
                          "bytes": pcm["bytes"], "sha256": pcm["sha256"]})
    return inputs, locations


def summarize(aliases, groups, inputs):
    counts = Counter(row["status"] for row in inputs)
    verified = [row for row in inputs if row["status"] == "verified-local-pcm"]
    return {"aliasesWithSoundMarkers": len(aliases), "plannedCommonMaleGroups": len(groups),
            "uniqueSoundIdentifiers": len(inputs), "indexedSoundIdentifiers": sum(row["catalog"] is not None for row in inputs),
            "verifiedLocalPCM": len(verified), "reusedPCM": sum(row["pcm"]["reusedExistingPCM"] for row in verified),
            "newlyDecodedPCM": sum(not row["pcm"]["reusedExistingPCM"] for row in verified),
            "previouslyPreparedPCMReused": sum(row["pcm"].get("provenance", {}).get("kind") == "previously-prepared-source-pcm" for row in verified),
            "inputStatusCounts": dict(sorted(counts.items())),
            "allPlannedInputsAvailable": bool(inputs) and len(verified) == len(inputs),
            "sourceTimelineProjected": False, "runtimeAudioBindingCreated": False,
            "panguModelCompleted": False, "productionPanguActivated": False}


def prepare(args):
    require(not args.output.exists() and not args.output.is_symlink(), "Input plan output already exists")
    motion_bytes = regular(args.motion_inventory, MOTION_BYTES)
    require(len(motion_bytes) == MOTION_BYTES and sha(motion_bytes) == MOTION_SHA256,
            "Original D19 motion inventory identity differs")
    inventory = json_value(motion_bytes)
    require(inventory["schema"] == "pangu-original-motion-semantic-inventory-v1", "Unexpected motion inventory")
    settings_raw = regular(args.source_settings_values, SETTINGS_VALUES_BYTES)
    storage_raw = regular(args.source_settings_storage, SETTINGS_STORAGE_BYTES)
    require(len(settings_raw) == SETTINGS_VALUES_BYTES and sha(settings_raw) == SETTINGS_VALUES_SHA256,
            "Original source settings values differ")
    require(len(storage_raw) == SETTINGS_STORAGE_BYTES and sha(storage_raw) == SETTINGS_STORAGE_SHA256,
            "Original settings storage receipt differs")
    storage = json_value(storage_raw)
    require(storage["sourceSHA256"] == SETTINGS_SOURCE_SHA256 and storage["sourceBytes"] == 334225
            and storage["allBytesConsumed"] is True, "Source storage is not the reviewed complete original")
    extended = extend_motion_inventory(inventory, json_value(settings_raw))
    require(not args.catalog_archive.is_symlink() and args.catalog_archive.is_file(), "Unsafe catalog archive")
    with zipfile.ZipFile(args.catalog_archive) as archive:
        members = [member for member in archive.infolist() if member.filename == CATALOG_MEMBER]
        require(len(members) == 1 and members[0].file_size == CATALOG_BYTES and members[0].flag_bits & 1 == 0,
                "Missing or ambiguous bounded Android catalog")
        catalog_bytes = archive.read(members[0])
    require(sha(catalog_bytes) == CATALOG_SHA256, "Reviewed Android catalog identity differs")
    catalog = [json_value(line) for line in catalog_bytes.splitlines()]
    aliases, groups, identifiers = marker_groups(extended)
    require((len(extended["records"]), len(aliases), len(groups), len(identifiers)) == (29, 14, 17, 38),
            "Pinned complete animation-setting sound-marker inventory differs")
    matches = catalog_matches(catalog, identifiers)
    reviewed, receipts = load_reviewed_pcm(args.reviewed_pcm, identifiers)
    prior, prior_receipt = load_prepared_pcm(args.prepared_plan, args.prepared_locations, identifiers)
    require(not set(prior) & set(reviewed), "Ambiguous previously prepared PCM")
    reviewed.update(prior)
    receipts.append(prior_receipt)
    output = args.private_output.resolve()
    repository = Path(__file__).resolve().parents[1]
    require(not output.is_relative_to(repository), "Private audio output must stay outside the repository")
    require(not args.private_output.is_symlink(), "Unsafe private audio output")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    require(stat.S_IMODE(output.stat().st_mode) & 0o077 == 0, "Private audio output must not be shared")
    inputs, locations = verify_audio_inputs(identifiers, matches, args.bundle_directory, reviewed,
                                            output, args.decode_missing)
    document = {"schema": "pangu-source-audio-input-plan-v2",
                "motionInventory": {"file": args.motion_inventory.name, "bytes": len(motion_bytes), "sha256": MOTION_SHA256},
                "androidCatalog": {"member": CATALOG_MEMBER, "bytes": len(catalog_bytes), "sha256": CATALOG_SHA256,
                                   "bundleRecords": len(catalog)},
                "sourceConfigurationVersion": inventory["packagedConfigurationVersion"],
                "sourceSettings": {"entry": "settings_sets_dynasty.bytes", "bytes": 334225,
                    "sha256": SETTINGS_SOURCE_SHA256, "valuesSnapshotBytes": len(settings_raw),
                    "valuesSnapshotSHA256": SETTINGS_VALUES_SHA256,
                    "storageReceiptBytes": len(storage_raw), "storageReceiptSHA256": SETTINGS_STORAGE_SHA256,
                    "priorRecoveredAliasesCrossChecked": 17},
                "motionCoverage": {"configuredAliases": 29, "recoveredMotionAliases": 17,
                    "unrecoveredMotionAliases": 12, "unrecoveredSourceFiles": 11,
                    "soundAliasesWithRecoveredMotion": 5, "soundAliasesWithoutRecoveredMotion": 9,
                    "unrecovered": copy.deepcopy(inventory["unrecovered"])},
                "reviewedPCMProvenance": receipts,
                "frameRule": "Sounds.Frame = max(0, source value). Do not subtract one; absent values require separate source evidence.",
                "nativeSoundMarkerMethod": inventory["nativeEvidence"]["soundMarkers"],
                "scope": ["Common and Male Sounds markers for all 29 D19 animation aliases in the pinned settings entry; 14 aliases contain sounds.",
                          "Seventeen aliases have recovered motion bytes; twelve do not. Configuration sounds remain inspectable without their motion BIN.",
                          "Trigger-based sounds, music and other source settings are outside this animation-marker input inventory.",
                          "Female/Monkey/Floor data remains in rawSoundMarkers; it is not selected or resolved here.",
                          "Shared original sounds are reused by exact original identifier, not labelled D19-exclusive.",
                          "Original FirstFrame/EndFrame/MidFrames and group order remain unchanged; no castPhase or runtime tick is inferred.",
                          "This is an input plan, not a complete Pangu model, playable character, runtime audio release or native acceptance."],
                "summary": summarize(aliases, groups, inputs), "animations": aliases, "groups": groups, "inputs": inputs}
    private = {"schema": "pangu-source-audio-locations-private-v1", "files": locations,
               "newlyDecoded": [row for row in inputs if row.get("pcm", {}).get("reusedExistingPCM") is False]}
    write_new(output / "pangu-source-audio-locations-private.json",
              (json.dumps(private, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode())
    data = (json.dumps(document, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    write_new(args.output, data)
    return {"summary": document["summary"], "planBytes": len(data), "planSHA256": sha(data)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motion-inventory", required=True, type=Path)
    parser.add_argument("--source-settings-values", required=True, type=Path)
    parser.add_argument("--source-settings-storage", required=True, type=Path)
    parser.add_argument("--catalog-archive", required=True, type=Path)
    parser.add_argument("--bundle-directory", required=True, action="append", type=Path)
    parser.add_argument("--reviewed-pcm", required=True, action="append", type=Path)
    parser.add_argument("--prepared-plan", required=True, type=Path)
    parser.add_argument("--prepared-locations", required=True, type=Path)
    parser.add_argument("--private-output", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="Public metadata JSON; never contains PCM or private paths")
    parser.add_argument("--decode-missing", action="store_true", help="Decode only indexed local AudioClips without reviewed PCM")
    print(json.dumps(prepare(parser.parse_args()), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
