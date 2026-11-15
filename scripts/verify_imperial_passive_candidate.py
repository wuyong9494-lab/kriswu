#!/usr/bin/env python3
"""Read exported Imperial victim GLBs back and compare every FK sample.

This checks the rendered channels against collision/landmark/COM profiles. It
is an offline asset consistency check, not a native SceneKit acceptance result.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from append_cached_imperial_passives import PROFILES, VARIANTS
from append_cached_root_victim_motions import checked_rig, encoded, pinned, weighted_center
from append_cached_stun_motions import weapon_sampler
from sun_triad_assets import RIGHT, accessor_read, capsule_point, glb_read, matrix, pose_world, require, world_poses


def check(key, directory, bindings, masses_path):
    receipt = json.loads((directory / "imperial-passive-append-receipt-private.json").read_text())
    pin = PROFILES[key]
    profile = json.loads(pinned(directory / (pin["resource"] + "_profile.json"),
                               receipt["outputProfileSHA256"], 32_000_000))
    model = directory / (pin["resource"] + ".glb")
    pinned(model, receipt["outputCharacterSHA256"], 32_000_000)
    definitions = json.loads(pinned(bindings, pin["bindingsSHA"], 128_000))
    masses = json.loads(pinned(masses_path, pin["massesSHA"], 128_000))
    g, binary = glb_read(model)
    names, _ = checked_rig(g, profile["sourceBoneBindings"], masses, pin["massCharacterSHA"])
    _, rest, parents = world_poses(g["nodes"])
    weapon_point = weapon_sampler(g, binary, profile, names)
    total, maximum = 0, 0.

    def compare(expected, actual):
        nonlocal total, maximum
        error = float(np.max(np.abs(np.asarray(expected) - np.asarray(actual))))
        require(np.isfinite(error) and error < 2e-6, "GLB/profile FK mismatch")
        maximum = max(maximum, error); total += 1

    for name, role, _, mirrored in VARIANTS:
        animation = next(a for a in g["animations"] if a["name"] == name)
        clip = next(c for c in profile["clips"] if c["name"] == name)
        require(profile["roles"][role] == name and clip["frames"] == 71
                and clip["playbackTicks"] == 140 and clip["sourceEndEventTick"] == 132
                and clip["sourceMirroringApplied"] == mirrored, "Source timing/role differs")
        curves = {}
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            times = accessor_read(g, binary, sampler["input"]).reshape(-1)
            require(len(times) == 141 and np.max(np.abs(times - np.arange(141) / 60)) < 2e-7,
                    "Expected 141 source-sampled keys")
            key_path = channel["target"]["node"], channel["target"]["path"]
            require(key_path not in curves, "Duplicate GLB animation channel")
            curves[key_path] = accessor_read(g, binary, sampler["output"])
        require(len(curves) == 116, "Expected all 58 original body bones")
        track = clip["tracks"]
        shapes = (track.get("collisionEdges", []) + track["hurtCapsules"])
        capsules = definitions.get("collisionEdges", []) + definitions["hurtCapsules"]
        require(len(shapes) == len(capsules), "Source capsule count differs")
        for tick in range(141):
            local = [m.copy() for m in rest]
            for node, path in curves:
                if path != "translation": continue
                local[node] = matrix(curves[node, "translation"][tick], curves[node, "rotation"][tick],
                                     g["nodes"][node].get("scale", [1, 1, 1]))
            world = pose_world(local, parents)
            for field, bone in (("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"),
                               ("footR", "foot_r"), ("toeL", "toe_l"), ("toeR", "toe_r"), ("pelvis", "pelvis")):
                compare(track[field][tick], (RIGHT @ world[names[bone]][:, 3])[:3])
            compare(track["centerOfMass"][tick], weighted_center(world, masses["bones"]))
            for side, letter in (("left", "L"), ("right", "R")):
                for end, label in (("base", "Base"), ("tip", "Tip")):
                    compare(track["weapon" + label + letter][tick], weapon_point(side, end, world))
            for shape, capsule in zip(shapes, capsules):
                require(shape["id"] == capsule["id"], "Source capsule identity differs")
                for end in ("base", "tip"):
                    compare(shape[end][tick], capsule_point(capsule[end], world, names))
    return dict(clips=2, samples=282, comparedPoints=total, maximumErrorMeters=maximum,
                characterSHA256=receipt["outputCharacterSHA256"], nativeRendered=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "sun-bindings", "liu-bindings", "sun-masses", "liu-masses"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    result = {key: check(key, args.candidate / key, getattr(args, key + "_bindings"),
                        getattr(args, key + "_masses")) for key in PROFILES}
    print(encoded(result).decode().strip())


if __name__ == "__main__":
    main()
