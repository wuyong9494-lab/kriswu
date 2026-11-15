#!/usr/bin/env python3
"""Read back the six new GLB animations and independently check their samples.

No conversion, network or activation occurs. The established hierarchy-only
pelvis sampler is reused for all five body landmarks. Channel data is compared
directly against the retained original TextAsset arrays, not importer buffers.
"""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

import numpy as np

from append_cached_root_victim_motions import digest, encoded, pinned
from append_cached_stun_motions import BONES, MOTIONS, PROFILES, validate_stun_append
from bind_source_fighter_pelvis import pelvis_samples
from stage_cached_stun_release import NEW
from stage_h17_floorfall_release import fresh_output, real_directory, write_private
from sun_triad_assets import RIGHT, accessor_read, decode, glb_read, require, world_poses


def verify(args):
    report_path = fresh_output(args.report)
    candidate, base = real_directory(args.candidate), real_directory(args.base)
    rows = []
    for key, pin in PROFILES.items():
        name = pin["resource"]
        profile = json.loads(pinned(candidate / key / (name + "_profile.json"), NEW[key]["profileSHA"], 24_000_000))
        raw_model = pinned(candidate / key / (name + ".glb"), NEW[key]["sha256"], 32_000_000)
        original = pinned(base / (name + ".glb"), pin["characterSHA"], 32_000_000)
        validate_stun_append(original, raw_model, pin["count"])
        g, binary = glb_read(candidate / key / (name + ".glb"))
        names = {r["name"]: r["targetNode"] for r in profile["sourceBoneBindings"]}
        source = {r["sourceID"]: r["targetNode"] for r in profile["sourceBoneBindings"] if r.get("sourceID") is not None}
        rest_world, _, parents = world_poses(g["nodes"])
        basis = RIGHT[:3, :3] @ rest_world[parents[names["pelvis"]]][:3, :3]
        for motion, clip, animation in zip(MOTIONS, profile["clips"][-3:], g["animations"][-3:]):
            require(clip["name"] == animation["name"] == motion["name"], "Appended motion order differs")
            raw = base64.b64decode(clip["sourceBytesBase64"], validate=True)
            require(len(raw) == motion["bytes"] and digest(raw) == motion["sha256"], "Retained original bytes differ")
            original_arrays = decode(raw)
            require(len(original_arrays) == 2 and list(original_arrays[0]["bone_ids"]) == BONES, "Original arrays differ")
            original_array = original_arrays[0]
            channels = {}
            for channel in animation["channels"]:
                target = channel["target"]; sampler = animation["samplers"][channel["sampler"]]
                pair = (target["node"], target["path"])
                require(pair not in channels and sampler["interpolation"] == "LINEAR", "Unexpected GLB channel")
                times = accessor_read(g, binary, sampler["input"])
                require(np.array_equal(times, (np.arange(motion["frames"]) / 30.).astype(np.float32)), "Export time grid differs")
                channels[pair] = accessor_read(g, binary, sampler["output"])
            require(set(channels) == {(source[bone], kind) for bone in BONES for kind in ("translation", "rotation")},
                    "The 116 channels do not bind this rig's exact original58 bones")
            for index, bone in enumerate(BONES):
                positions = original_array["positions"][:, index].astype(float) * [.01, .01, -.01]
                if bone == 0: positions[:, [0, 2]] = 0
                quaternions = original_array["rotations"][:, index].astype(float) * [-1, -1, 1, 1]
                quaternions /= np.linalg.norm(quaternions, axis=1)[:, None]
                for sample in range(1, len(quaternions)):
                    if quaternions[sample - 1] @ quaternions[sample] < 0: quaternions[sample] *= -1
                require(np.array_equal(channels[source[bone], "translation"], positions.astype(np.float32))
                        and np.array_equal(channels[source[bone], "rotation"], quaternions.astype(np.float32)),
                        "Written animation differs from original source transformations")
            for track, bone in (("pelvis", "pelvis"), ("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"), ("footR", "foot_r")):
                independently_sampled = pelvis_samples(g, binary, animation, motion["frames"], names[bone])
                require(independently_sampled == clip["tracks"][track], "Read-back FK differs: " + track)
            roots = original_array["positions"][:, BONES.index(0)].astype(float) * [.01, .01, -.01]
            roots = (roots - roots[0]) @ basis.T
            expected = []
            for sample in range(2 * motion["frames"] - 1):
                first, half = divmod(sample, 2); second = min(first + 1, motion["frames"] - 1)
                expected.append(roots[first] * (1 - half / 2) + roots[second] * half / 2)
            require(np.round(expected, 7).tolist() == clip["tracks"]["root"], "Original root displacement differs")
            rows.append(dict(profile=pin["id"], clip=motion["name"], frames=motion["frames"],
                samples=2 * motion["frames"] - 1, sourceSHA256=motion["sha256"], channels=116,
                ownRigBones=58, sourceChannelValuesExact=True, ownRigFiveLandmarkFKExact=True,
                sourceRootDisplacementExact=True))
    report = dict(schema="source-stun-written-glb-readback-v1", clips=rows,
        oldGLBBINAndModelUnchanged=True, glbRegenerated=False, sourceArraysDecodedForComparison=True,
        glbChannelsAndFKReadOnly=True, sourceInputsModified=False, nativeRendered=False,
        productionPanguActivated=False)
    write_private(report_path, encoded(report))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "base", "report"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(verify(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
