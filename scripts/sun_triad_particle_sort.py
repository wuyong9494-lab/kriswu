#!/usr/bin/env python3
"""Recover original H17 renderer ordering without resampling particle tracks.

Inputs are existing, private source bundles and their authenticated extraction
receipts. Only ordering fields are added to the private JSON document. The
separate release finalizer owns gzip and asset pins. No network is used and no
original game data is written into the source repository.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import random
import re
import warnings
from pathlib import Path


SHADER_BUNDLE = "b77cd85962dab26b5e542811e8599be3.bin"
SHADER_SHA256 = "c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972"
SORT_FIELDS = frozenset(("sourceSortMode", "sourceSortingLayer", "sourceRenderQueue", "sourceAgeOffset"))
QUEUE_VALUES = {"Background": 1000, "Geometry": 2000, "AlphaTest": 2450, "Transparent": 3000, "Overlay": 4000}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def source_queue(custom, tag):
    """Apply the original material override, otherwise its shader Queue tag."""
    require(type(custom) is int and -1 <= custom <= 5000, "Invalid source material render queue")
    if custom >= 0:
        return custom
    match = re.fullmatch(r"(Background|Geometry|AlphaTest|Transparent|Overlay)([+-][0-9]+)?", tag)
    require(match is not None, "Unsupported original shader queue tag")
    value = QUEUE_VALUES[match[1]] + int(match[2] or 0)
    require(0 <= value <= 5000, "Original shader render queue is out of bounds")
    return value


def occurrences(schedule, speed, start_delay, prewarm, duration_override):
    """Replay only the birth/clip clock; no curves, meshes or images are sampled.

    A prewarmed particle has already lived for -originalDelay seconds when the
    exported clip starts at zero. Its later recurring occurrence is a new birth
    with age zero. Duration clipping follows the existing exporter exactly.
    """
    require(all(math.isfinite(value) for value in (speed, start_delay, prewarm))
            and speed > 0 and start_delay >= 0 and prewarm >= 0, "Invalid source emitter clock")
    if duration_override is not None:
        require(math.isfinite(duration_override) and duration_override > 0, "Invalid source effect duration")
    result = collections.defaultdict(list)
    for particle, birth, period in schedule:
        life = round(particle.life / speed, 7)
        delay = start_delay + birth / speed - prewarm
        rows = []
        if delay < 0:
            if -delay < life:
                rows.append((0., None, round(life + delay, 7), -delay))
            if period is not None:
                rows.append((delay + period / speed, period / speed, life, 0.))
        else:
            rows.append((delay, None if period is None else period / speed, life, 0.))
        for delay, repeat, duration, age in rows:
            delay = round(delay, 7)
            require(delay >= 0, "Original prewarm exceeds its verified repeat period")
            if duration_override is not None:
                if delay >= duration_override - 1e-7:
                    continue
                duration = min(duration, round(duration_override - delay, 7))
            require(duration > 0 and math.isfinite(age) and 0 <= age <= 36000, "Invalid source particle age")
            key = (particle.index, delay, None if repeat is None else round(repeat, 7))
            result[key].append({"duration": duration, "age": round(age, 7)})
    return result


def take_occurrence(track, expected, prefix):
    require(track["name"].startswith(prefix + "_"), "Track name belongs to another original emitter")
    suffix = track["name"][len(prefix) + 1:].split("_")
    require(len(suffix) == 2 and all(part.isdecimal() for part in suffix), "Invalid original particle ordinal")
    key = (int(suffix[0]), track["delay"], track.get("loopPeriod"))
    rows = expected.get(key, [])
    require(len(rows) == 1, "Original particle birth is missing or ambiguous")
    row = rows.pop()
    require(abs(row["duration"] - track["duration"]) <= 1e-6, "Original particle lifetime differs from its exported clip")
    return row["age"]


def unchanged_digest(document):
    """Hash everything except the four ordering fields, sharing frame arrays."""
    stripped = dict(document)
    stripped["effects"] = {}
    for name, effect in document["effects"].items():
        replacement = dict(effect)
        for field in ("tracks", "historyTrails"):
            if field in effect:
                replacement[field] = [{key: value for key, value in track.items() if key not in SORT_FIELDS}
                                      for track in effect[field]]
        stripped["effects"][name] = replacement
    digest = hashlib.sha256()
    encoder = json.JSONEncoder(separators=(",", ":"), allow_nan=False)
    for piece in encoder.iterencode(stripped):
        digest.update(piece.encode())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("models", "effects", "candidate"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    warnings.filterwarnings("ignore", category=Warning, module="UnityPy")
    import UnityPy
    from UnityPy.helpers import TypeTreeHelper
    from UnityPy.streams import EndianBinaryReader
    from sun_triad_assets import private_output, write_private
    from sun_triad_particle_assets import SourceAssets
    from sun_triad_particle_curves import minmax
    from sun_triad_particles import emission_schedule, seed

    output = private_output(args.candidate)
    path = output / "SF3_H17_Effects.json"
    require(not path.is_symlink(), "Private source document cannot be a symlink")
    before = path.read_bytes()
    require(len(before) <= 256_000_000, "Private effect document exceeds its decoded byte limit")
    document = json.loads(before)
    old_digest = sha(before)
    del before
    protected_digest = unchanged_digest(document)
    inventory_bytes = (args.effects / "h17-effects-inventory.json").read_bytes()
    inventory = json.loads(inventory_bytes)
    source_gzip = (args.effects / inventory["particleSourceFile"]).read_bytes()
    require(len(source_gzip) == inventory["particleSourceBytes"]
            and sha(source_gzip) == inventory["particleSourceSHA256"], "Original particle extraction receipt differs")
    assets = SourceAssets(args.models, args.effects, output)
    require(sha((args.models / inventory["sourceBundle"]).read_bytes()) == inventory["sourceBundleSHA256"],
            "Original effect inventory refers to another bundle")
    shader_bytes = (args.models / SHADER_BUNDLE).read_bytes()
    require(sha(shader_bytes) == SHADER_SHA256, "Original shader bundle digest differs")
    shader_environment = UnityPy.load(shader_bytes)
    shaders = {str(obj.path_id): obj for obj in shader_environment.objects if obj.type.name == "Shader"}
    material_type = next(obj for obj in assets.environment.objects if obj.type.name == "Material")
    entries = {entry["rootName"]: entry for entry in inventory["entries"]}
    require(len(entries) == len(inventory["entries"]), "Original effect paths are ambiguous")
    material_proofs = {}
    emitter_proofs = []
    mode_counts = collections.Counter()
    queue_counts = collections.Counter()
    age_count = 0
    age_maximum = 0.
    track_count = 0
    history_count = 0

    def material_queue(pointer, key):
        cab, path_id = assets.key(pointer)
        require(key == "m_" + str(path_id) and key in document["materials"], "Source renderer material PPtr differs")
        descriptor = document["materials"][key]
        if key in material_proofs:
            proof = material_proofs[key]
            require(proof["sourceCAB"] == (cab or assets.source_cab.name), "Material path ID is not globally unique")
            return proof["sourceRenderQueue"]
        if cab is None:
            obj = assets.local[path_id]
            require(obj.type.name == "Material", "Source renderer PPtr is not a material")
            material = obj.read_typetree()
            material_sha = sha(obj.get_raw_data())
        else:
            receipt = assets.record("Material", cab, path_id)
            raw = Path(receipt["rawFile"]).read_bytes()
            # Reparse the original object bytes using the same client Material
            # type tree and require exact agreement with its prior extraction.
            material = TypeTreeHelper.read_typetree(material_type.serialized_type.node,
                EndianBinaryReader(raw, endian=material_type.reader.endian), byte_size=len(raw), as_dict=True)
            require(json.loads(json.dumps(material)) == json.loads(Path(receipt["metadataFile"]).read_text()),
                    "Original material raw bytes disagree with their extracted metadata")
            material_sha = sha(raw)
        require(descriptor["sourceMaterialSHA256"] == material_sha, "Accepted source material identity differs")
        bindings = [binding for binding in assets.shader_document["materials"]
                    if binding["sourcePathID"] == str(path_id) and binding["sourceObjectSHA256"] == material_sha]
        require(len(bindings) == 1 and bindings[0]["shaderPathID"] == descriptor["shaderPathID"],
                "Original material shader identity is missing or ambiguous")
        shader = shaders.get(descriptor["shaderPathID"])
        require(shader is not None and sha(shader.get_raw_data()) == descriptor["sourceShaderSHA256"],
                "Accepted source shader identity differs")
        forms = shader.read_typetree()["m_ParsedForm"]["m_SubShaders"]
        require(len(forms) == 1, "Multiple source subshaders require an explicit queue selection")
        tags = [value for name, value in forms[0]["m_Tags"]["tags"] if name.lower() == "queue"]
        require(len(tags) == 1, "Original shader Queue tag is missing or ambiguous")
        queue = source_queue(material["m_CustomRenderQueue"], tags[0])
        material_proofs[key] = dict(sourcePathID=str(path_id), sourceCAB=cab or assets.source_cab.name,
            sourceMaterialSHA256=material_sha, sourceShaderSHA256=descriptor["sourceShaderSHA256"],
            sourceShaderPathID=descriptor["shaderPathID"], sourceCustomRenderQueue=material["m_CustomRenderQueue"],
            sourceShaderQueue=tags[0], sourceRenderQueue=queue)
        return queue

    for name, effect in document["effects"].items():
        entry = entries.get(name)
        require(entry is not None and effect["sourceName"] == entry["sourcePath"], "Effect belongs to another source prefab")
        emitters = {}
        controllers = []
        for component in entry["transforms"][0]["components"]:
            if component["type"] == "MonoBehaviour":
                data = assets.local[int(component["pathID"])].read_typetree()
                if "overrideDuration" in data:
                    controllers.append(data)
        require(len(controllers) == 1, "Original effect controller is missing or ambiguous")
        override = float(controllers[0]["duration"]) if controllers[0]["overrideDuration"] else None
        require(effect["sourceDurationOverride"] == override, "Accepted source controller clock differs")
        for transform in entry["transforms"]:
            refs = {component["type"]: component["pathID"] for component in transform["components"]}
            if "ParticleSystem" not in refs:
                continue
            require("ParticleSystemRenderer" in refs, "Original particle renderer is missing")
            identity = refs["ParticleSystem"]
            require(identity not in emitters, "Original particle identity is ambiguous within its prefab")
            source_obj = assets.local[int(identity)]
            renderer_obj = assets.local[int(refs["ParticleSystemRenderer"])]
            source = source_obj.read_typetree()
            renderer = renderer_obj.read_typetree()
            emitters[identity] = (source, renderer, transform, source_obj, renderer_obj)
        grouped = collections.defaultdict(list)
        for kind in ("tracks", "historyTrails"):
            for track in effect.get(kind, []):
                grouped[track["sourceParticleSystem"]].append((kind, track))
        for identity, tracks in grouped.items():
            require(identity in emitters, "Particle track belongs to another original prefab")
            source, renderer, transform, source_obj, renderer_obj = emitters[identity]
            mode, layer = renderer["m_SortMode"], renderer["m_SortingLayer"]
            require(mode in (0, 2, 3, 4), "Unsupported source particle sorting mode")
            require(layer == renderer["m_SortingLayerID"] == 0 and renderer["m_SortingFudge"] == 0,
                    "Nondefault source layer or sorting fudge requires its project ordering adapter")
            expected = None
            if any(kind == "tracks" for kind, _ in tracks):
                require(renderer["m_RenderMode"] != 5, "History renderer cannot own a sampled mesh track")
                speed = source["simulationSpeed"]
                prewarm = source["lengthInSec"] / speed if source["prewarm"] and source["looping"] else 0.
                start_delay = minmax(source["startDelay"], 0, random.Random(seed(identity, "delay")).random()) / speed
                expected = occurrences(emission_schedule(source, identity), speed, start_delay, prewarm, override)
            ages = []
            material_keys = set()
            for kind, track in tracks:
                require(track["sortingOrder"] == renderer["m_SortingOrder"], "Accepted renderer sorting order differs")
                slot = 1 if kind == "historyTrails" else 0
                require(slot < len(renderer["m_Materials"]), "Original renderer material slot is missing")
                queue = material_queue(renderer["m_Materials"][slot], track["material"])
                material_keys.add(track["material"])
                if kind == "historyTrails":
                    require(not source["prewarm"] and not source["looping"] and renderer["m_RenderMode"] == 5,
                            "History particle has unadapted source prewarm or repetition")
                    age = 0.
                    history_count += 1
                else:
                    age = take_occurrence(track, expected, transform["name"] + "_" + identity)
                    track_count += 1
                track.update(sourceSortMode=mode, sourceSortingLayer=layer, sourceRenderQueue=queue, sourceAgeOffset=age)
                mode_counts[mode] += 1
                queue_counts[queue] += 1
                age_count += int(age > 0)
                age_maximum = max(age_maximum, age)
                ages.append(age)
            require(expected is None or all(not rows for rows in expected.values()), "Original emitter has an unbound particle occurrence")
            emitter_proofs.append(dict(effect=name, sourceParticleSystem=identity,
                sourceParticleSystemSHA256=sha(source_obj.get_raw_data()), sourceRendererPathID=str(renderer_obj.path_id),
                sourceRendererSHA256=sha(renderer_obj.get_raw_data()), sourceSortMode=mode,
                sourceSortingLayer=layer, sourceSortingLayerID=renderer["m_SortingLayerID"],
                sourceSortingOrder=renderer["m_SortingOrder"], sourceSortingFudge=renderer["m_SortingFudge"],
                materialKeys=sorted(material_keys), tracks=len(tracks), prewarmedTracks=sum(age > 0 for age in ages),
                maximumSourceAgeOffset=max(ages)))
    require(unchanged_digest(document) == protected_digest, "Ordering patch changed another source data field")
    result = json.dumps(document, separators=(",", ":"), allow_nan=False).encode()
    require(len(result) <= 256_000_000, "Patched source document exceeds its decoded byte limit")
    require(sha(path.read_bytes()) == old_digest, "Private source document changed while ordering was being recovered")
    receipt = dict(version=1, operation="original-source-ordering-only", sourceBundleSHA256=inventory["sourceBundleSHA256"],
        sourceInventorySHA256=sha(inventory_bytes), sourceParticleExtractionSHA256=inventory["particleSourceSHA256"],
        sourceShaderBundleSHA256=SHADER_SHA256, beforeSHA256=old_digest, afterSHA256=sha(result),
        unchangedNonSortSHA256=protected_digest, decodedBytes=len(result), tracks=track_count, historyTrails=history_count,
        emitters=len(emitter_proofs), sortModes=dict(sorted(mode_counts.items())), renderQueues=dict(sorted(queue_counts.items())),
        prewarmedTracks=age_count, maximumSourceAgeOffset=age_maximum, addedFields=sorted(SORT_FIELDS),
        orderingRules={"0": "Keep original particle ordinal within the emitter.",
                       "2": "OldestInFront: draw younger particles first, older particles last.",
                       "3": "YoungestInFront: draw older particles first, younger particles last.",
                       "4": "Depth: draw farther particles first, nearer particles last."},
        sourceReferences=["https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/particlesystemsortmode",
                          "https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/rendering/renderqueue/transparent"],
        ageRule="Playback seconds since original birth = active clip time + sourceAgeOffset; recurring new births use zero offset.",
        limitations=["Original automatic random seeds vary per run; the existing private realization is preserved.",
                     "Emitter grouping must also include the live effect instance identity.",
                     "No frames, geometry, bindings, source models, materials or resource bytes were resampled or changed.",
                     "The release finalizer must regenerate gzip and all dependent digest pins."],
        materials=material_proofs, emittersEvidence=emitter_proofs)
    temporary = output / "SF3_H17_Effects.sort-pending-private.json"
    write_private(temporary, result)
    temporary.replace(path)
    write_private(output / "h17-source-particle-sort-private.json", json.dumps(receipt, indent=2, allow_nan=False).encode())
    print(json.dumps({key: receipt[key] for key in ("afterSHA256", "decodedBytes", "tracks", "historyTrails", "emitters",
                                                   "sortModes", "renderQueues", "prewarmedTracks", "maximumSourceAgeOffset")}))


if __name__ == "__main__":
    main()
