#!/usr/bin/env python3
"""Bind recovered bone-mass centres to a verified private character profile.

This reads the character's own animation channels and node hierarchy. It never
rewrites its GLB, approximates COM with pelvis, or shares a second rig's nodes.
Mass records must be independently recovered and tied to this character hash.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from sun_triad_assets import RIGHT, accessor_read, glb_read, matrix, pose_world, private_output, require, world_poses


def bind(profile_path: Path, weights_path: Path) -> dict:
    private_output(profile_path.parent)
    profile = json.loads(profile_path.read_text())
    before = hashlib.sha256(profile_path.read_bytes()).hexdigest()
    model = profile_path.parent / (profile["resourceName"] + ".glb")
    require(hashlib.sha256(model.read_bytes()).hexdigest() == profile["sha256"], "Character identity mismatch")
    weights = json.loads(weights_path.read_text())
    require(weights["characterSHA256"] == profile["sha256"], "Mass table belongs to another character")
    g, binary = glb_read(model)
    bindings = {row["name"]: row["targetNode"] for row in profile["sourceBoneBindings"]}
    masses = weights["bones"]
    require(masses and len({row["name"] for row in masses}) == len(masses), "Empty or duplicate source mass binding")
    for row in masses:
        require(row["name"] in bindings and bindings[row["name"]] == row["targetNode"] and
                g["nodes"][row["targetNode"]]["name"] == row["name"], "Source mass bone identity mismatch")
        require(np.isfinite(row["mass"]) and row["mass"] >= 0, "Invalid source bone mass")
    total = sum(row["mass"] for row in masses)
    require(total > 0, "Source centre has no positive total mass")
    _, rest, parents = world_poses(g["nodes"])
    animations = {animation["name"]: animation for animation in g["animations"]}
    count = 0
    for clip in profile["clips"]:
        require(clip["name"] in animations, "Source clip missing from character")
        animation = animations[clip["name"]]
        require(animation.get("extras", {}).get("sourceSHA256") == clip["sha256"], "Animation identity mismatch")
        channels = {}
        for channel in animation["channels"]:
            node, kind = channel["target"]["node"], channel["target"]["path"]
            require(kind in ("translation", "rotation", "scale") and (node, kind) not in channels,
                    "Unexpected or duplicate original animation channel")
            sampler = animation["samplers"][channel["sampler"]]
            require(sampler.get("interpolation", "LINEAR") == "LINEAR", "Unbound source interpolation")
            times = accessor_read(g, binary, sampler["input"])
            values = accessor_read(g, binary, sampler["output"])
            require(len(times) == clip["frames"] and len(values) == len(times) and
                    np.max(np.abs(times - np.arange(clip["frames"]) / 30.)) < .0001,
                    "Source frame grid mismatch")
            channels[node, kind] = values.astype(float)
        centers = []
        for sample in range(2 * clip["frames"] - 1):
            a, half = divmod(sample, 2); b = min(clip["frames"] - 1, a + 1); w = half / 2
            local = [item.copy() for item in rest]
            for node in {key[0] for key in channels}:
                transform = {}
                for kind, default in (("translation", [0, 0, 0]), ("rotation", [0, 0, 0, 1]), ("scale", [1, 1, 1])):
                    values = channels.get((node, kind))
                    if values is None:
                        transform[kind] = g["nodes"][node].get(kind, default)
                    else:
                        first, second = values[a], values[b]
                        if kind == "rotation" and first @ second < 0: second = -second
                        transform[kind] = first * (1 - w) + second * w
                local[node] = matrix(transform["translation"], transform["rotation"], transform["scale"])
            world = pose_world(local, parents)
            # The recovered native updater accumulates scalar Float values in
            # skeleton traversal order. Preserve that order and arithmetic;
            # glTF/FK projection remains the separately declared arena basis.
            accumulator, mass_sum = np.zeros(3, dtype=np.float32), np.float32(0)
            for row in masses:
                weight = np.float32(row["mass"])
                point = np.asarray((RIGHT @ world[row["targetNode"]][:, 3])[:3], dtype=np.float32)
                accumulator = np.asarray(accumulator + point * weight, dtype=np.float32)
                mass_sum = np.float32(mass_sum + weight)
            center = accumulator / mass_sum
            centers.append(center)
        clip["tracks"]["centerOfMass"] = np.round(centers, 7).tolist()
        count += len(centers)
    profile_path.write_text(json.dumps(profile, ensure_ascii=False, separators=(",", ":")) + "\n")
    receipt = dict(characterSHA256=profile["sha256"], originalProfileSHA256=before,
        profileSHA256=hashlib.sha256(profile_path.read_bytes()).hexdigest(),
        massTableSHA256=hashlib.sha256(weights_path.read_bytes()).hexdigest(), clips=len(profile["clips"]),
        samples=count, totalSourceMass=total, weightedBones=len(masses),
        projection="sum(original bone world position * original mass) / sum(mass); half-frame local quaternion interpolation before FK; same RIGHT/metre basis as limb tracks",
        unchangedGLBSHA256=hashlib.sha256(model.read_bytes()).hexdigest())
    (profile_path.parent / (profile["resourceName"] + "_center_of_mass_receipt-private.json")).write_text(
        json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--weights", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(bind(args.profile, args.weights)))


if __name__ == "__main__": main()
