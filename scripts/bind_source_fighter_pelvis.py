#!/usr/bin/env python3
"""Add verified pelvis FK samples to a private runtime fighter profile.

The input character and source profile are read-only. Only tracks.pelvis is
added to the runtime JSON; source bytes, COM, other tracks and rules survive
unchanged. Coordinates match the existing RIGHT/metre FK tracks, including
the character's own ancestor transforms. Arena position, facing and ground
lift are deliberately left to the authoritative simulation.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
import tempfile
from pathlib import Path

import numpy as np

from sun_triad_assets import RIGHT, accessor_read, glb_read, matrix, private_output, require


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def semantic_digest(value) -> str:
    return digest(json.dumps(value, sort_keys=True, ensure_ascii=False,
                             separators=(",", ":"), allow_nan=False).encode())


def without_pelvis(profile: dict) -> dict:
    result = copy.deepcopy(profile)
    for clip in result["clips"]:
        clip["tracks"].pop("pelvis", None)
    return result


def pelvis_samples(document: dict, binary: bytes, animation: dict,
                   frames: int, target: int) -> list:
    """Use the same local nlerp and FK as the existing limb/COM exporter."""
    nodes = document["nodes"]
    require(0 <= target < len(nodes), "Pelvis node outside character")
    parents = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            require(0 <= child < len(nodes) and child not in parents,
                    "Invalid or multiply parented source node")
            parents[child] = index
    chain, current = [], target
    while current is not None:
        require(current not in chain, "Source pelvis ancestor cycle")
        require("matrix" not in nodes[current], "Unbound matrix/TRS animation convention")
        chain.append(current)
        current = parents.get(current)
    chain.reverse()
    channels = {}
    for channel in animation["channels"]:
        node, kind = channel["target"]["node"], channel["target"]["path"]
        require(0 <= node < len(nodes) and kind in ("translation", "rotation", "scale")
                and (node, kind) not in channels, "Unexpected or duplicate source channel")
        sampler = animation["samplers"][channel["sampler"]]
        require(sampler.get("interpolation", "LINEAR") == "LINEAR", "Unbound source interpolation")
        times = accessor_read(document, binary, sampler["input"])
        values = accessor_read(document, binary, sampler["output"]).astype(float)
        width = 4 if kind == "rotation" else 3
        require(times.shape == (frames,) and values.shape == (frames, width)
                and np.isfinite(times).all() and np.isfinite(values).all()
                and np.max(np.abs(times - np.arange(frames) / 30.)) < .0001,
                "Source frame grid or channel shape mismatch")
        if kind == "rotation":
            require((np.linalg.norm(values, axis=1) > 1e-12).all(), "Zero source quaternion")
        channels[node, kind] = values
    require((target, "translation") in channels, "Source animation has no pelvis translation")
    result = []
    for sample in range(2 * frames - 1):
        first, half = divmod(sample, 2)
        second, weight = min(frames - 1, first + 1), half / 2
        world = np.eye(4)
        for node in chain:
            transform = {}
            for kind, default in (("translation", [0, 0, 0]), ("rotation", [0, 0, 0, 1]),
                                  ("scale", [1, 1, 1])):
                values = channels.get((node, kind))
                if values is None:
                    transform[kind] = nodes[node].get(kind, default)
                else:
                    a, b = values[first], values[second]
                    if kind == "rotation" and a @ b < 0:
                        b = -b
                    transform[kind] = a * (1 - weight) + b * weight
            world = world @ matrix(transform["translation"], transform["rotation"], transform["scale"])
        point = (RIGHT @ world[:, 3])[:3]
        require(np.isfinite(point).all(), "Non-finite source pelvis")
        result.append(point)
    return np.round(result, 7).tolist()


def bind(source_path: Path, runtime_path: Path, receipt_path: Path) -> dict:
    private_output(runtime_path.parent)
    private_output(receipt_path.parent)
    require(not runtime_path.is_symlink() and not receipt_path.is_symlink(), "Output cannot be a symlink")
    require(len({source_path.resolve(), runtime_path.resolve(), receipt_path.resolve()}) == 3,
            "Source, runtime and receipt paths must differ")
    source_bytes, runtime_bytes = source_path.read_bytes(), runtime_path.read_bytes()
    source, runtime = json.loads(source_bytes), json.loads(runtime_bytes)
    require(source["id"] == runtime["id"] and source["resourceName"] == runtime["resourceName"]
            and source["sha256"] == runtime["sha256"] and source["bytes"] == runtime["bytes"],
            "Source and runtime character identities differ")
    model = source_path.parent / (source["resourceName"] + ".glb")
    model_bytes = model.read_bytes()
    require(digest(model_bytes) == source["sha256"] and len(model_bytes) == source["bytes"],
            "Character bytes or SHA256 mismatch")
    document, binary = glb_read(model)
    bindings = [row for row in source["sourceBoneBindings"] if row["name"] == "pelvis"]
    require(len(bindings) == 1, "Expected one exact source pelvis binding")
    binding = bindings[0]
    target = binding["targetNode"]
    require(binding["sourceID"] == 0 and document["nodes"][target].get("name") == "pelvis",
            "Source pelvis identity mismatch")
    animations = {item["name"]: item for item in document["animations"]}
    source_clips = {clip["name"]: clip for clip in source["clips"]}
    require(len(animations) == len(document["animations"])
            and len(source_clips) == len(source["clips"])
            and len({clip["name"] for clip in runtime["clips"]}) == len(runtime["clips"])
            and set(source_clips) == {clip["name"] for clip in runtime["clips"]},
            "Duplicate or mismatched source/runtime clip set")
    original_semantics = semantic_digest(without_pelvis(runtime))
    records = []
    for clip in runtime["clips"]:
        source_clip = source_clips[clip["name"]]
        frames = clip["frames"]
        require(isinstance(frames, int) and 1 <= frames <= 2000
                and frames == source_clip["frames"] and clip["sha256"] == source_clip["sha256"]
                and clip["bundle"] == source_clip["bundle"], "Source motion identity mismatch")
        source_raw = base64.b64decode(source_clip["sourceBytesBase64"], validate=True)
        require(digest(source_raw) == clip["sha256"], "Original motion SHA256 mismatch")
        animation = animations[clip["name"]]
        require(animation.get("extras", {}).get("sourceSHA256") == clip["sha256"]
                and animation.get("extras", {}).get("sourceFrames") == frames,
                "Character animation source binding mismatch")
        old_tracks = {key: value for key, value in clip["tracks"].items() if key != "pelvis"}
        source_tracks = {key: value for key, value in source_clip["tracks"].items() if key != "pelvis"}
        require(old_tracks == source_tracks and old_tracks["samplesPerSourceFrame"] == 2,
                "Runtime tracks differ from the verified source profile")
        points = pelvis_samples(document, binary, animation, frames, target)
        require(len(points) == len(old_tracks["root"]) == 2 * frames - 1,
                "Pelvis sample count differs from source tracks")
        if "pelvis" in clip["tracks"]:
            require(clip["tracks"]["pelvis"] == points, "Existing pelvis track differs from source FK")
        clip["tracks"]["pelvis"] = points
        records.append(dict(name=clip["name"], sourceSHA256=clip["sha256"], frames=frames,
                            samples=len(points), pelvisSHA256=semantic_digest(points),
                            unchangedOtherTracksSHA256=semantic_digest(old_tracks),
                            unchangedCenterOfMassSHA256=semantic_digest(old_tracks.get("centerOfMass"))))
    require(semantic_digest(without_pelvis(runtime)) == original_semantics,
            "Export changed fields outside tracks.pelvis")
    output = (json.dumps(runtime, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()
    require(source_path.read_bytes() == source_bytes and model.read_bytes() == model_bytes
            and runtime_path.read_bytes() == runtime_bytes, "An input changed during pelvis export")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=runtime_path.parent, prefix="pelvis-", suffix=".tmp", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(output)
        os.replace(temporary, runtime_path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    require(runtime_path.read_bytes() == output, "Runtime profile write verification failed")
    receipt = dict(version=1, profileID=runtime["id"], characterSHA256=digest(model_bytes),
        sourceProfileSHA256=digest(source_bytes), originalRuntimeProfileSHA256=digest(runtime_bytes),
        runtimeProfileSHA256=digest(output), runtimeProfileBytes=len(output),
        unchangedFieldsExcludingPelvisSHA256=original_semantics,
        unchangedGLBSections={key: semantic_digest(document.get(key)) for key in
            ("nodes", "meshes", "skins", "materials", "textures", "images", "animations", "scenes", "accessors", "bufferViews")},
        sourceBoneBinding=binding, samplesPerSourceFrame=2, clips=len(records),
        samples=sum(record["samples"] for record in records),
        projection="RIGHT @ original GLB pelvis world FK; original ancestor scale retained exactly once; metres; no arena/facing/groundLift; local half-frame quaternion nlerp before FK",
        records=records)
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    receipt_path.chmod(0o600)
    return {key: receipt[key] for key in ("profileID", "characterSHA256", "runtimeProfileSHA256", "runtimeProfileBytes", "clips", "samples")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-profile", type=Path, required=True)
    parser.add_argument("--runtime-profile", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(bind(args.source_profile, args.runtime_profile, args.receipt)))


if __name__ == "__main__":
    main()
