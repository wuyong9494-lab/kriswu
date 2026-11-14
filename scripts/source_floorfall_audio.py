#!/usr/bin/env python3
"""Compile the recovered lock923 body-fall sound into a new private candidate.

Only existing local, already decoded source inputs are accepted. This command
does not fetch, decrypt, repack, publish, or modify an existing release. It
recovers the original trigger from typed source bytes, checks native registry
names/defaults, decodes only its seven previously absent AudioClips, and binds
the two verified H17 IntervalStart markers. Physics FloorHit and the native
meaning of PlaySound.Position=null remain explicitly unimplemented.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import struct
import warnings
import wave
from zipfile import ZipFile


REPOSITORY = Path(__file__).resolve().parents[1]
CHARACTER_SHA = "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"
SOURCE_CONFIGURATION_SHA = "71b164acc4f03d93e4af4aba864eb2e192531c07d1b4751f05b2520b94e7656e"
CATALOG_MEMBER = "research/android_bundle_catalog.jsonl"
CATALOG_SHA = "2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055"
BUNDLE_NAME = "4d7f8b35e599fce4165da3b317824dc0.bin"
BUNDLE_SHA = "a66918864b0974a585e24b11799ce701f70d3848d27baa343cf8199e68f35f32"
SOURCE_PINS = {
    "lock_923.bytes": (276605, "c2fe1f2fa5b4a0a8b457de20608334d9202b959b832b72317860adf0d8c9cba2"),
    "settings_hits.bytes": (64690, "d6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a"),
    "settings_sets_heralds.bytes": (399607, "64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a"),
    "settings_style_ninjato.bytes": (25607, "84fc1a78b7de5a3ad3bbdabf32f6526daf89bf7bd1fdbb9fd4d7a18cb12948bb"),
}
REGISTRY_PINS = {
    "actions": "5583e1ff7b3bc925cf62af52f7e4c25884992a4128fc5bd1d9de25c27782757d",
    "events": "8170e85ca0a857c08bc2a8b323904abd086ee2cd9c31a46ae9da4f687e519b92",
}
SOUND_NUMBERS = (1, 3, 5, 8, 13, 15, 16)
SOUND_VALUES = [f"fall/body_layer/6_Body_Fall_V{n}_bip@Battle@Movement" for n in SOUND_NUMBERS]
PREFIX = "assets/gamedata/resources/audio/sounds/"
SOURCE_SELECTIONS = (
    ("settings_hits.bytes", 48, "H_Head_Middle_Average_Critical_Fall", True),
    ("settings_sets_heralds.bytes", 104, "H17_Root_Spike_Passive_End", True),
    ("settings_style_ninjato.bytes", 11, "Ninjato_Stance_Start_Round", False),
    ("settings_style_ninjato.bytes", 20, "Shadow_Ninjato_Slash_Passive", False),
)
MOTION_PINS = {
    "h_hit_head_fall": (59, "9fda1b85f59b5ff7a6b6406ad3720347ab0b43f9330108d249892ec2ce08fef2"),
    "h17_root_spike_passive_end": (48, "7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2"),
}
ANIMATION_FIELDS = (
    "Animation", "FileName", "MidFrames", "Style", "TacticsGroups", "FirstFrame", "EndFrame",
    "Looped", "Mirrored", "BlendingFrames", "SelfEndFrame", "SelfNoMirroring", "IgnoreWeaponMirroring",
    "ShowAllSkeletons", "ForceDetachWeapon", "SaveMirroringOnNextAnimation", "ForceDisableSnapping",
    "WeaponSwitchFrames", "EndsStage", "Groups", "ComboAnimations", "SetDirection", "Velocity", "Align",
    "Transitions", "RepulsionScale", "Sounds", "Intervals", "AttackType",
)
POOL_LAYOUT = ((3, "q"), (4, "f"), (5, "d"), (6, "str"), (8, "2I"), (13, "2I"), (11, "3I"),
               (10, "6I"), (16, "2I"), (14, "2f"), (15, "3f"), (17, "4f"), (18, "2I"), (20, "3I"))
KIND = ("Null", "Bool", "Int", "Long", "Float", "Double", "String", "RpnOperator", "RpnFunction",
        "HandleList", "TriggerData", "ConditionData", "ConditionDataEntry", "NamedData", "Vector2",
        "Vector3", "TriggerSetData", "Color", "StringMap", "Object", "SplitData", "Enum")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_file(path, maximum=40_000_000):
    path = Path(path)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), "Input is not a regular non-symlink file")
    require(0 < info.st_size <= maximum, "Input size is outside the bounded range")
    return path.read_bytes()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()


def verified_json(path, expected=None, maximum=40_000_000):
    raw = read_file(path, maximum)
    require(expected is None or digest(raw) == expected, "Input JSON pin differs")
    return json.loads(raw), dict(name=Path(path).name, bytes=len(raw), sha256=digest(raw))


class Storage:
    """Bounded source typed-storage reader, recovered from native methods 168484/168607.

    It never executes source scripts. Every byte and reference is checked; the
    fixed reviewed source pins are checked before invoking this reader.
    """
    def __init__(self, data):
        require(0 < len(data) <= 1_000_000, "Typed source exceeds its bound")
        self.data, self.pos, self.tables = data, 0, {}
        self.string()
        self.root = self.read("I")
        for kind, fmt in POOL_LAYOUT:
            count = self.read("I")
            require(count <= len(data), "Typed source pool is out of bounds")
            self.tables[kind] = [self.string() if fmt == "str" else self.read(fmt) for _ in range(count)]
        self.headers, self.flat = self.array(), self.array()
        require(self.read("I") == 7, "Typed source group count differs")
        self.groups = [self.array() for _ in range(7)]
        require(self.headers == sorted(self.headers) and all(x <= len(self.flat) for x in self.headers),
                "Typed source handle offsets are invalid")
        require(all(len(group) % size == 0 for size, group in enumerate(self.groups, 1)),
                "Typed source handle group is misaligned")
        require(self.pos == len(data), "Typed source has trailing bytes")
        self.nodes = 0

    def read(self, fmt):
        size = struct.calcsize("<" + fmt)
        require(self.pos + size <= len(self.data), "Typed source is truncated")
        result = struct.unpack_from("<" + fmt, self.data, self.pos)
        self.pos += size
        return result[0] if len(result) == 1 else list(result)

    def string(self):
        count, shift = 0, 0
        while True:
            byte = self.read("B")
            count |= (byte & 127) << shift
            if byte < 128:
                break
            shift += 7
            require(shift <= 28, "Typed source string length is invalid")
        require(self.pos + count <= len(self.data), "Typed source string is truncated")
        result = self.data[self.pos:self.pos + count].decode("utf-8")
        self.pos += count
        return result

    def array(self):
        count = self.read("I")
        require(count * 4 <= len(self.data) - self.pos, "Typed source array is truncated")
        return [self.read("I") for _ in range(count)]

    def handles(self, raw):
        bank, index = (raw >> 24) & 7, raw & 0xFFFFFF
        if bank:
            group = self.groups[bank - 1]
            require(index % bank == 0 and index + bank <= len(group), "Typed source group reference is invalid")
            return group[index:index + bank]
        require(index < len(self.headers), "Typed source handle reference is invalid")
        end = self.headers[index + 1] if index + 1 < len(self.headers) else len(self.flat)
        return self.flat[self.headers[index]:end]

    def value(self, raw, depth=0):
        self.nodes += 1
        require(depth <= 200 and self.nodes <= 500_000, "Typed source nesting exceeds its bound")
        kind, payload = raw >> 27, raw & 0x7FFFFFF
        require(kind < len(KIND), "Typed source kind is unknown")
        if kind == 0:
            require(raw == 0, "Typed source null is invalid")
            return None
        if kind == 1:
            require(payload in (0, 1), "Typed source bool is invalid")
            return bool(payload)
        if kind == 2:
            return payload if payload < 0x4000000 else payload - 0x8000000
        if kind == 9:
            return [self.value(x, depth + 1) for x in self.handles(raw)]
        if kind in (7, 21):
            return {"kind": KIND[kind], "value": payload}
        require(kind in self.tables and payload < len(self.tables[kind]), "Typed source pool reference is invalid")
        value = self.tables[kind][payload]
        if kind in (3, 4, 5, 6, 14, 15, 17):
            return value
        if kind in (8, 13):
            return {"kind": KIND[kind], "id": value[0], "value": self.value(value[1], depth + 1)}
        return {"kind": KIND[kind], "fields": [self.value(x, depth + 1) for x in value]}


def compact(value):
    if isinstance(value, list):
        return [compact(x) for x in value]
    if not isinstance(value, dict):
        return value
    kind = value["kind"]
    if kind in ("RpnFunction", "NamedData"):
        return {("f" if kind == "RpnFunction" else "a") + str(value["id"]): compact(value["value"])}
    if kind in ("RpnOperator", "Enum"):
        return ("op" if kind == "RpnOperator" else "enum") + str(value["value"])
    if kind == "ConditionData":
        fields = value["fields"]
        return {fields[0] or "expr": compact(fields[1] if fields[1] is not None else fields[2])}
    return {kind: compact(value["fields"])}


def source_inputs(splits):
    receipts, sources = [], {}
    raw = read_file(splits, 20_000_000)
    with ZipFile(io.BytesIO(raw)) as outer:
        for split, names in (("battle_triggers", ["lock_923.bytes"]),
                             ("animation_settings", list(SOURCE_PINS)[1:])):
            member = "splits/split_" + split + ".bytes"
            info = outer.getinfo(member)
            require(info.file_size <= 17_000_000 and not info.flag_bits & 1, "Source split is encrypted or oversized")
            with ZipFile(io.BytesIO(outer.read(member))) as inner:
                for name in names:
                    expected_size, expected_sha = SOURCE_PINS[name]
                    require(inner.getinfo(name).file_size == expected_size, "Raw source member size differs")
                    payload = inner.read(name)
                    require(digest(payload) == expected_sha, "Raw source member pin differs")
                    storage = Storage(payload)
                    sources[name] = storage.value(storage.root)
                    receipts.append(dict(name=name, bytes=len(payload), sha256=expected_sha, allBytesConsumed=True))
    return sources, receipts


def registry_row(registry, ordinal, name, parameters):
    choices = [x for x in registry if x["ordinal"] == ordinal]
    require(len(choices) == 1 and choices[0]["text"] == name, "Original registry name differs")
    actual = [(x["name"]["text"], x["default"]["text"]) for x in choices[0]["parameters"]]
    require(actual == parameters, "Original registry parameters/defaults differ")


def validate_registries(actions, events):
    registry_row(actions, 111, "PlaySound", [("Sounds[]", "null"), ("Loop", "false"), ("Position", "null")])
    both = "Banzai.SFGF.Primitives.RelativeTarget.Both"
    registry_row(events, 13, "FloorHit", [("Player", both), ("Type", "Common.Moves.FloorHitType.Physics")])
    registry_row(events, 18, "IntervalStart", [("Player", both), ("Name", '\"\"')])


def rule_from_sources(sets):
    require(len(sets) > 98, "Original common trigger sets are incomplete")
    selected = sets[97]
    require(selected["kind"] == "TriggerSetData" and selected["fields"][0] == "EFFECT__Dust_Down",
            "Original body-fall set identity differs")
    triggers = selected["fields"][1]
    require(len(triggers) == 1, "Original body-fall trigger is ambiguous")
    fields = triggers[0]["fields"]
    events, conditions, actions = (compact(fields[i]) for i in (3, 4, 5))
    require(events == [{"a13": ["enum65537", None]}, {"a18": ["enum65537", "Floorfall"]}],
            "Original body-fall event alternatives differ")
    def group(name):
        return {"expr": [{"f26": [{"f74": ["enum65537"]}]}, name, "op22"]}
    expected_conditions = [{"Not": [group("THROW_FALL"), group("PHYSICS_NO_SFX")]},
                           {"Or": [group("PHYSICS"), group("FALL")]}]
    require(conditions == expected_conditions, "Original body-fall group guards differ")
    sound_actions = [x["a111"] for x in actions if "a111" in x]
    require(sound_actions == [[SOUND_VALUES, None, None]], "Original body-fall sounds or playback flags differ")
    throw_set = sets[98]["fields"]
    require(throw_set[0] == "EFFECT__Dust_Down_From_Throw", "Original throw-fall exclusion proof differs")
    require(all("a111" not in x for t in throw_set[1] for x in compact(t["fields"][5])),
            "Throw-fall acquired a sound action; review its separate semantics")
    return dict(sourceLock=923, sourceSet=97, sourceTrigger=0, name=selected["fields"][0],
                events=events, conditions=conditions, sounds=copy.deepcopy(SOUND_VALUES),
                loop=False, position=None, positionResolution="pending_native_default",
                physicsFloorHit="not_integrated", intervalStart="compiled_candidate_only")


def animation_records(sources):
    records = []
    for entry, index, alias, accepted in SOURCE_SELECTIONS:
        values = sources[entry][index]
        require(len(values) == len(ANIMATION_FIELDS), "Original animation schema differs")
        row = dict(zip(ANIMATION_FIELDS, values))
        require(row["Animation"] == alias, "Original animation record identity differs")
        records.append(dict(sourceEntry=entry, sourceRecordIndex=index, configuration=row,
                            expectedAccepted=accepted, sourceSHA256=SOURCE_PINS[entry][1]))
    return records


def compile_markers(records, profile, filenames):
    require(profile["id"] == "sun_triad" and profile["sha256"] == CHARACTER_SHA, "H17 source character pin differs")
    clips = {x["name"]: x for x in profile["clips"]}
    require(len(clips) == len(profile["clips"]), "Duplicate source motion names")
    markers, accepted, excluded = [], [], []
    for record in records:
        row = record["configuration"]
        groups = set(row["Groups"] or []) | {row["Animation"]}
        allowed = bool(groups & {"PHYSICS", "FALL"}) and not groups & {"THROW_FALL", "PHYSICS_NO_SFX"}
        require(allowed == record["expectedAccepted"], "Original group acceptance changed")
        proof = dict(sourceEntry=record["sourceEntry"], sourceSHA256=record["sourceSHA256"],
                     sourceRecordIndex=record["sourceRecordIndex"], sourceAnimation=row["Animation"],
                     groups=row["Groups"], sourceInterval="Floorfall")
        if not allowed:
            proof["reason"] = "THROW_FALL excluded" if "THROW_FALL" in groups else "No PHYSICS/FALL group"
            excluded.append(proof)
            continue
        require(row["FirstFrame"] in (None, 0) and row["MidFrames"] in (None, 1) and row["Looped"] in (None, False),
                "Cropped, looping or differently stepped source motion needs review")
        clip_name = Path(row["FileName"]).stem
        require(clip_name in MOTION_PINS and clip_name in clips, "Verified floor-fall motion is absent")
        clip = clips[clip_name]
        frames, sha = MOTION_PINS[clip_name]
        require(clip["frames"] == frames and clip["sha256"] == sha, "Floor-fall motion identity differs")
        configured_ticks = clip.get("playbackTicks")
        ticks = 2 * (frames - 1) if configured_ticks is None else configured_ticks
        require(type(ticks) is int and ticks > 0 and ticks == 2 * (frames - 1),
                "Floor-fall motion duration changed; do not infer a new marker tick")
        intervals = [x for x in row["Intervals"] or [] if x[0] == "Floorfall"]
        require(len(intervals) == 1 and len(intervals[0]) == 28 and intervals[0][2:4] == [20, 20],
                "Original Floorfall interval no longer matches frame 20")
        marker = dict(id="source_floorfall_923_97_" + clip_name, clip=clip_name,
                      sourceFrame=20, clock="intervalStart", context="Common", files=list(filenames))
        proof.update(clip=clip_name, sourceFrames=frames, sourceMotionSHA256=sha,
                     sourceStart=20, sourceEnd=20, playbackFrame=19,
                     playbackTick=19 * ticks // (frames - 1), duration=ticks,
                     position=None, positionResolution="pending_native_default")
        require(proof["playbackTick"] == 38, "Floor-fall marker must cross at tick 38")
        markers.append(marker)
        accepted.append(proof)
    require(len(markers) == 2 and len(excluded) == 2, "Reviewed interval/exclusion coverage differs")
    return markers, accepted, excluded


def source_audio_paths():
    return [PREFIX + value.split("@")[0].lower() + ".wav" for value in SOUND_VALUES]


def catalog_bundle(archive):
    # Only the existing 9 MB catalog member is read, never the whole source archive.
    path = Path(archive)
    require(stat.S_ISREG(path.lstat().st_mode), "Catalog archive must be a regular file")
    with ZipFile(path) as source:
        require(source.getinfo(CATALOG_MEMBER).file_size == 9_100_700, "Original catalog size differs")
        raw = source.read(CATALOG_MEMBER)
    require(digest(raw) == CATALOG_SHA, "Original source catalog pin differs")
    candidates = [json.loads(line) for line in raw.splitlines() if BUNDLE_NAME.encode() in line]
    require(len(candidates) == 1 and candidates[0]["file"] == BUNDLE_NAME, "Original audio bundle catalog is ambiguous")
    row = candidates[0]
    require(row["bytes"] == 1_014_386 and row["sha256"] == BUNDLE_SHA and row["crc_ok"],
            "Original audio bundle identity differs")
    wanted = source_audio_paths()
    selected = [x for x in row["paths"] if x["path"].lower() in wanted]
    require(len(selected) == 7 and {x["path"].lower() for x in selected} == set(wanted),
            "The seven exact body-fall AudioClips are not all in the existing catalog")
    return dict(row, paths=selected)


def decode_sounds(models, row):
    """Decode only the seven reviewed clips; no resampling, normalizing or gain change."""
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
    raw = read_file(Path(models) / row["file"], 2_000_000)
    require(len(raw) == row["bytes"] and digest(raw) == row["sha256"], "Cached original audio bundle pin differs")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", Warning)
        environment = UnityPy.load(raw)
        container = {key.lower(): value for key, value in environment.container.items()}
        records, media = {}, {}
        for entry in row["paths"]:
            path = entry["path"].lower()
            require(path in container, "Original AudioClip container entry is missing")
            pointer = container[path]
            obj = pointer.deref()
            require(obj.type.name == "AudioClip" and obj.path_id == entry["path_id"],
                    "Original AudioClip type or pathID differs")
            clip = pointer.read()
            samples = clip.samples
            require(len(samples) == 1, "Original AudioClip decoder returned ambiguous samples")
            name, data = next(iter(samples.items()))
            require(name.endswith(".wav"), "Original AudioClip decoder did not produce WAV")
            with wave.open(io.BytesIO(data), "rb") as decoded:
                channels, frequency, frames, width = (decoded.getnchannels(), decoded.getframerate(),
                                                       decoded.getnframes(), decoded.getsampwidth())
                require(decoded.getcomptype() == "NONE" and width == 2, "Original sound is not PCM16")
            require(channels == clip.m_Channels and frequency == clip.m_Frequency and
                    abs(frames / frequency - clip.m_Length) < 2 / frequency,
                    "Original AudioClip channel/rate/duration changed during decoding")
            sound_sha = digest(data)
            filename = "SF3H17_" + re.sub(r"[^A-Za-z0-9_]+", "_", Path(name).stem) + "_" + sound_sha[:10] + ".wav"
            require(0 < len(data) <= 4_000_000 and len(filename) <= 160, "Decoded sound exceeds loader bounds")
            resource = clip.m_Resource
            encoded = get_resource_data(resource.m_Source, clip.object_reader.assets_file, resource.m_Offset, resource.m_Size)
            require(filename not in media, "Unexpected duplicate body-fall decoded identity")
            media[filename] = data
            records[path] = dict(name=filename, bytes=len(data), sha256=sound_sha, sourceName=clip.m_Name,
                                 sourcePath=path, sourcePathID=str(obj.path_id), sourceBundle=row["file"],
                                 sourceBundleSHA256=row["sha256"], sourceObjectSHA256=digest(obj.get_raw_data()),
                                 encodedSHA256=digest(encoded), encodedBytes=len(encoded), sampleRate=frequency,
                                 channels=channels, sampleFrames=frames, sampleWidth=width)
    require(set(records) == set(source_audio_paths()), "Decoded body-fall source path set differs")
    return records, media


def validate_base_binding(base):
    """Reject invalid identities and unbounded/reference-invalid JSON before WAV IO."""
    require(isinstance(base, dict) and base.get("version") == 2 and base.get("profileID") == "sun_triad"
            and base.get("characterSHA256") == CHARACTER_SHA,
            "Base audio binding is not the verified H17 v2 identity")
    require(base.get("sourceConfigurationSHA256") == SOURCE_CONFIGURATION_SHA,
            "Base source configuration pin differs")
    require(base.get("context") == dict(gender="Male", floor="Stone"), "Base source audio context differs")
    files, markers, cues, audio = (base.get(k) for k in ("files", "markers", "cues", "audio"))
    require(isinstance(files, list) and 1 <= len(files) <= 96, "Base audio file count exceeds loader bounds")
    require(isinstance(markers, list) and len(markers) <= 1024 and isinstance(cues, list) and len(cues) <= 128,
            "Base audio marker/cue count exceeds loader bounds")
    names, total = set(), 0
    for record in files:
        require(isinstance(record, dict), "Base audio file record is invalid")
        name, count, sha = (record.get(k) for k in ("name", "bytes", "sha256"))
        require(isinstance(name, str) and len(name) <= 160 and
                re.fullmatch(r"[A-Za-z0-9_.-]+\.wav", name) and ".." not in name,
                "Base audio filename is invalid")
        require(name not in names, "Base audio file names are duplicated")
        names.add(name)
        require(type(count) is int and 0 < count <= 4_000_000, "Base audio file byte bound is invalid")
        require(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{64}", sha), "Base audio digest is invalid")
        total += count
    require(total <= 32_000_000, "Base audio total bytes exceed loader bounds")
    require(isinstance(audio, dict) and set(audio) <= {"ninjatoHit", "ninjatoBlock", "ninjatoWhoosh"},
            "Base audio categories are invalid")
    references = set()
    groups = list(audio.values())
    for entries in (markers, cues):
        identities = set()
        for entry in entries:
            require(isinstance(entry, dict) and isinstance(entry.get("id"), str) and
                    re.fullmatch(r"[A-Za-z0-9_-]{1,96}", entry["id"]), "Base marker/cue identity is invalid")
            require(entry["id"] not in identities, "Base marker/cue identities are duplicated")
            identities.add(entry["id"])
            groups.append(entry.get("files"))
    for group in groups:
        require(isinstance(group, list) and 1 <= len(group) <= 32 and
                all(isinstance(name, str) for name in group), "Base audio choice group is invalid")
        references.update(group)
    require(references == names, "Base audio reference closure differs")


def candidate_manifest(base, markers, sound_records):
    validate_base_binding(base)
    original = copy.deepcopy(base)
    candidate = copy.deepcopy(base)
    old_ids = {x["id"] for x in base["markers"]}
    require(len(old_ids) == len(base["markers"]) and not old_ids & {x["id"] for x in markers},
            "Floor-fall marker already exists or base marker identity is duplicated")
    files = {x["name"]: x for x in base["files"]}
    require(len(files) == len(base["files"]), "Base audio file names are duplicated")
    for record in sound_records:
        value = {k: record[k] for k in ("name", "bytes", "sha256")}
        require(value["name"] not in files, "Floor-fall PCM already exists; review reuse instead of decoding again")
        files[value["name"]] = value
    candidate["files"] = base["files"] + [files[x["name"]] for x in sound_records]
    candidate["markers"] = base["markers"] + copy.deepcopy(markers)
    require(len(candidate["files"]) <= 96 and sum(x["bytes"] for x in candidate["files"]) <= 32_000_000,
            "Candidate exceeds existing audio loader bounds")
    require(len(candidate["markers"]) <= 1024, "Candidate exceeds existing marker bounds")
    refs = {name for x in candidate["markers"] + candidate["cues"] for name in x["files"]}
    refs |= {name for group in candidate["audio"].values() for name in group}
    require(refs == set(files), "Candidate has missing or unreferenced audio files")
    require(base == original, "Compiler modified its base binding")
    return candidate


def existing_media(base, directory):
    contents = {}
    for record in base["files"]:
        name = record["name"]
        require(re.fullmatch(r"[A-Za-z0-9_.-]{1,160}\.wav", name) and ".." not in name,
                "Base audio filename is invalid")
        data = read_file(Path(directory) / name, 4_000_000)
        require(len(data) == record["bytes"] and digest(data) == record["sha256"], "Existing PCM identity differs")
        contents[name] = data
    return contents


def candidate_location(output):
    output = Path(output).absolute()
    require(output.parent.resolve(strict=True) == output.parent, "Candidate parent uses a symlink")
    require(REPOSITORY not in output.parents and not output.exists() and not output.is_symlink(),
            "Candidate must be new and outside the repository")
    return output


def write_candidate(output, manifest, media, receipt):
    output = candidate_location(output)
    # This command creates an independent candidate; it never overwrites one.
    output.mkdir(mode=0o700)
    for name, data in {**media, "SF3_H17_Audio.json": json_bytes(manifest),
                       "floorfall-audio-provenance-private.json": json_bytes(receipt)}.items():
        require(Path(name).name == name and name not in (".", ".."), "Unsafe candidate filename")
        fd = os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
    require(stat.S_IMODE(output.stat().st_mode) == 0o700 and
            all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in output.iterdir()), "Candidate privacy modes differ")


def compile_candidate(args):
    # Check this before source parsing or decoding so an accidental repeat of
    # the successful command never re-decodes audio or rewrites its candidate.
    candidate_location(args.output)
    base, base_receipt = verified_json(args.audio_manifest, maximum=512_000)
    validate_base_binding(base)
    require(len(base["files"]) + 7 <= 96 and len(base["markers"]) + 2 <= 1024,
            "Projected floor-fall candidate exceeds existing loader count bounds")
    require(not any(x["id"].startswith("source_floorfall_923_97_") for x in base["markers"]),
            "Floor-fall bindings already exist; no repeated decode")
    actions, action_receipt = verified_json(args.actions, REGISTRY_PINS["actions"], 500_000)
    events, event_receipt = verified_json(args.events, REGISTRY_PINS["events"], 100_000)
    validate_registries(actions, events)
    sources, source_receipts = source_inputs(args.splits)
    rule = rule_from_sources(sources["lock_923.bytes"])
    profiles, profile_receipt = verified_json(args.profiles)
    choices = [x for x in profiles["profiles"] if x["id"] == "sun_triad"]
    require(len(choices) == 1, "H17 profile is missing or ambiguous")
    records = animation_records(sources)
    # Fail on source/identity/marker errors before invoking any AudioClip decoder.
    compile_markers(records, choices[0], ["provisional.wav"])
    old_media = existing_media(base, args.audio_directory)
    row = catalog_bundle(args.catalog_archive)
    sounds, new_media = decode_sounds(args.models, row)
    ordered = [sounds[path] for path in source_audio_paths()]
    markers, accepted, excluded = compile_markers(records, choices[0], [x["name"] for x in ordered])
    candidate = candidate_manifest(base, markers, ordered)
    media = {**old_media, **new_media}
    require(set(media) == {x["name"] for x in candidate["files"]}, "Candidate PCM set differs from manifest")
    receipt = dict(schema="private-source-floorfall-audio-candidate-v1", originalRule=rule,
                   rawSourceInputs=source_receipts, registryInputs=[action_receipt, event_receipt],
                   profileInput=profile_receipt, baseAudioInput=base_receipt, catalogSHA256=CATALOG_SHA,
                   verifiedAudio=ordered, acceptedIntervals=accepted, excludedIntervals=excluded,
                   originalBindingCounts=dict(files=len(base["files"]), markers=len(base["markers"])),
                   candidateBindingCounts=dict(files=len(candidate["files"]), markers=len(candidate["markers"])),
                   oldBindingObjectsUnchanged=True, oldMediaCopiedWithoutReencoding=len(old_media),
                   networkBytes=0, resourcePackModified=False, uploaded=False,
                   runtimeIntegration=False, nativePlaybackValidation=False, simulatorValidation=False,
                   deviceValidation=False, pending=["Native FloorHit event branch has not been integrated.",
                       "PlaySound.Position=null native default resolution has not been recovered; the effect centerOfMass is not used as audio position.",
                       "The private v2 candidate is not installed or merged into any release.",
                       "Apple playback, simulator screenshots/logs and iPhone 17 Pro Max audiovisual acceptance remain pending."])
    before = {str(path): digest(read_file(path)) for path in (args.profiles, args.audio_manifest)}
    write_candidate(args.output, candidate, media, receipt)
    require(all(digest(read_file(Path(path))) == sha for path, sha in before.items()), "Original binding input changed")
    return dict(output=str(Path(args.output).absolute()), files=len(candidate["files"]),
                addedAudioFiles=len(new_media), addedMarkers=len(markers), playbackTicks=[x["playbackTick"] for x in accepted],
                candidateSHA256=digest(json_bytes(candidate)), originalManifestSHA256=base_receipt["sha256"],
                originalMediaPreserved=len(old_media), physicsFloorHitIntegrated=False, spatialDefaultVerified=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("splits", "actions", "events", "catalog-archive", "models", "profiles", "audio-manifest", "audio-directory", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(compile_candidate(args), ensure_ascii=False))


if __name__ == "__main__":
    main()
