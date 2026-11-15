#!/usr/bin/env python3
"""Append the reviewed Imperial Spear victim motion to Sun and Liu's own rigs.

Only existing pinned inputs are read. Two aliases share the original 120-frame
source and its EndFrame=71 crop. The mirrored alias applies the recovered
body-local mirror rules after source interpolation, at every 60 Hz sample.
Original geometry, skins, old animations, profiles and private media stay
unchanged; the output is a new candidate and never activates D19 equipment.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
import os
from pathlib import Path

import numpy as np

from append_cached_root_victim_motions import checked_rig, digest, encoded, pinned, weighted_center
from append_cached_stun_motions import PROFILES as PRE_STUN, weapon_sampler
from source_body_mirroring import body_rules, mirror_source_samples, sample_source_motion
from stage_h17_floorfall_release import fresh_output, regular, write_private
from stage_h17_shared_root_release import glb_chunks
from sun_triad_assets import RIGHT, Writer, capsule_point, decode, glb_read, matrix, pose_world, require, world_poses
from sun_triad_source_bones import capsule_binding


SOURCE_CLIP_SHA = "8fc82d094d1c0b832cb13998b786d10e54bb63e983de6856bf7b2839bf977e29"
SOURCE_RAW_SHA = "75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411"
NAMED_CONFIG_SHA = "e2dc838741a8d0f780796edd0cd30fcb66071e779d6f9a0e41c9fa1db59a78f7"
PROFILES = {
    "sun": dict(PRE_STUN["sun"], count=68,
        profileSHA="78a83dc1b51c0b21eac76fcae6efa8a54f2e722688a94bc9496faf9d66b61d02",
        characterSHA="9513c85028541fe514f552a5e0d11fd01df277b8cd9f8ddeb832508ff975c699"),
    "liu": dict(PRE_STUN["liu"], count=62,
        profileSHA="00731a040544cfd993a4744b1dc9d959da0d4f294d2067272dcb722f658d86a3",
        characterSHA="66f8a748efb431bb28bdcd5e4cd91bc2d5d374fd456eb00e843f5d6590a26bfe"),
}
VARIANTS = (
    ("imperial_spear_heavy_slash_passive", "imperialHeavyPassive", 9, False),
    ("imperial_spear_heavy_slash_passive_mirror", "imperialHeavyPassiveMirrored", 10, True),
)


def validate_append(original, appended, count):
    before, _, raw_before = glb_chunks(original)
    after, _, raw_after = glb_chunks(appended)
    require(set(before) == set(after) and raw_after[:len(raw_before)] == raw_before,
            "Original GLB structure or BIN prefix changed")
    for key in before:
        if key in {"animations", "accessors", "bufferViews"}:
            require(after[key][:len(before[key])] == before[key], "Original GLB records changed")
        elif key != "buffers":
            require(before[key] == after[key], "Original geometry, materials or skin changed")
    require(len(before["animations"]) == count and len(after["animations"]) == count + 2
            and [a["name"] for a in after["animations"][count:]] == [v[0] for v in VARIANTS],
            "Expected exactly the two reviewed Imperial victim aliases")


def inputs(source_clip, named_config, mirroring):
    clip = json.loads(pinned(source_clip, SOURCE_CLIP_SHA, 1_000_000))
    named = json.loads(pinned(named_config, NAMED_CONFIG_SHA, 1_000_000))
    mirror_raw = regular(Path(mirroring).absolute(), 128_000)
    rules = body_rules(mirror_raw)
    require(clip["name"] == VARIANTS[0][0] and clip["frames"] == 71
            and clip["sourceUncroppedFrames"] == 120 and clip["sourceFirstIndex"] == 0
            and clip["sourceLastIndex"] == 70 and clip["playbackTicks"] == 140
            and clip["sha256"] == SOURCE_RAW_SHA and not clip["targetAbsentSourceWeaponTrackIDs"],
            "Original Imperial victim source/crop differs")
    raw = base64.b64decode(clip["sourceBytesBase64"], validate=True)
    require(digest(raw) == SOURCE_RAW_SHA, "Original source bytes differ")
    arrays = decode(raw)
    require(len(arrays) == 2 and arrays[0]["frame_count"] == 120
            and [int(n) for n in arrays[0]["bone_ids"]] == clip["sourceBoneIDs"]
            and len(clip["sourceBoneIDs"]) == 58, "Original body motion schema differs")
    records = copy.deepcopy(named["records"])
    # The earlier named-config recovery retained compact Sounds tuples. The
    # actor builder subsequently named those same fields without changing them.
    for index in (9, 10):
        sounds = records[index]["configuration"]["Sounds"]
        for i, sound in enumerate(sounds):
            require(isinstance(sound, list) and len(sound) == 4 and sound[3] is None,
                    "Unexpected reviewed passive sound tuple")
            gender = sound[2]
            require(gender is None or len(gender) == 3, "Unexpected source gender tuple")
            sounds[i] = dict(Frame=sound[0], Common=sound[1],
                Gender=None if gender is None else dict(zip(("Male", "Female", "Monkey"), gender)), Floor=None)
    require(records[9] == clip["sourceConfiguration"], "Normal source configuration differs")
    normal, mirrored = records[9]["configuration"], records[10]["configuration"]
    require(normal["Mirrored"] is None and mirrored["Mirrored"] == -1
            and mirrored["Animation"] == "Imperial_Spear_Heavy_Slash_Passive_Mirror"
            and {k: v for k, v in normal.items() if k not in {"Animation", "Mirrored"}}
                == {k: v for k, v in mirrored.items() if k not in {"Animation", "Mirrored"}},
            "Mirror variant differs beyond its reviewed alias/toggle")
    samples = sample_source_motion(arrays[0], 0, 70)
    return clip, records, rules, samples, digest(mirror_raw)


def append_profile(key, profile_path, bindings_path, masses_path, source, output):
    pin = PROFILES[key]
    original = json.loads(pinned(profile_path, pin["profileSHA"], 32_000_000))
    require(original["id"] == pin["id"] and original["resourceName"] == pin["resource"]
            and original["sha256"] == pin["characterSHA"] and len(original["clips"]) == pin["count"],
            "Expected the reviewed post-Stun character")
    source_glb = Path(profile_path).parent / (pin["resource"] + ".glb")
    raw_glb = pinned(source_glb, pin["characterSHA"], 32_000_000)
    require(len(raw_glb) == original["bytes"], "Original character size differs")
    definitions = json.loads(pinned(bindings_path, pin["bindingsSHA"], 128_000))
    masses = json.loads(pinned(masses_path, pin["massesSHA"], 128_000))
    profile = copy.deepcopy(original)
    g, binary = glb_read(source_glb)
    names, bone_names = checked_rig(g, profile["sourceBoneBindings"], masses, pin["massCharacterSHA"])
    rest_world, rest, parents = world_poses(g["nodes"])
    basis = RIGHT[:3, :3] @ rest_world[parents[names["pelvis"]]][:3, :3]
    weapon_point = weapon_sampler(g, binary, profile, names)
    attacks, hurts = definitions.get("collisionEdges", []), definitions["hurtCapsules"]
    require(len(attacks) == (4 if key == "sun" else 0) and len(hurts) == 15,
            "Reviewed collision binding differs")
    for capsule in attacks + hurts:
        require(all(capsule[end]["bone"] in names for end in ("base", "tip")), "Unbound capsule")
    clip, records, rules, samples, mirror_sha = source
    require(all(n in bone_names for n in clip["sourceBoneIDs"]), "Unbound original victim bone")
    columns = {bone_names[n]: i for i, n in enumerate(clip["sourceBoneIDs"])}
    writer = Writer(); writer.g = g; writer.b = bytearray(binary)
    require(len(g["animations"]) == pin["count"], "Original animation count differs")
    ground = []
    for side in ("l", "r"):
        foot, toe = names["foot_" + side], names["toe_" + side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0]) - .055, max(a[0], b[0]) + .055):
            for z in (min(a[2], b[2]) - .055, max(a[2], b[2]) + .055):
                ground.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    receipts = []
    for name, role, record_index, mirrored in VARIANTS:
        require(role not in profile["roles"] and name not in {c["name"] for c in profile["clips"]},
                "Imperial victim alias already exists")
        source_p, source_q = samples
        if mirrored:
            source_p, source_q = mirror_source_samples(source_p, source_q, columns, g["nodes"], names, rules)
        p = source_p * [.01, .01, -.01]
        q = source_q * [-1, -1, 1, 1]
        roots = p[:, columns["pelvis"]].copy()
        p[:, columns["pelvis"], [0, 2]] = 0
        p, q = p.astype(np.float32).astype(float), q.astype(np.float32).astype(float)
        animation = dict(name=name, samplers=[], channels=[], extras=dict(
            sourceSHA256=SOURCE_RAW_SHA, sourceFrames=120, sourceFirstIndex=0, sourceLastIndex=70,
            sourceFPS=30, simulationHz=60, bakedSamples=141, sourceMirroringApplied=mirrored,
            sourceMirroringSchemaSHA256=mirror_sha if mirrored else None,
            sourceBytesRetainedInProfile=True))
        times = writer.acc(np.arange(141) / 60., "SCALAR")
        for bone, column in columns.items():
            for kind, values, width in (("translation", p[:, column], "VEC3"),
                                        ("rotation", q[:, column], "VEC4")):
                i = len(animation["samplers"])
                animation["samplers"].append(dict(input=times, output=writer.acc(values, width), interpolation="LINEAR"))
                animation["channels"].append(dict(sampler=i, target=dict(node=names[bone], path=kind)))
        g["animations"].append(animation)
        root_delta = (roots - roots[0]) @ basis.T
        tracks = {k: [] for k in ("root", "handL", "handR", "footL", "footR", "toeL", "toeR",
            "weaponBaseL", "weaponTipL", "weaponBaseR", "weaponTipR", "groundLift", "pelvis", "centerOfMass")}
        tracks["samplesPerSourceFrame"] = 2
        edges = [dict(**capsule_binding(c, "attack"), base=[], tip=[]) for c in attacks]
        shapes = [dict(**capsule_binding(c, "hurt"), base=[], tip=[]) for c in hurts]
        for sample in range(141):
            local = [value.copy() for value in rest]
            for bone, column in columns.items():
                local[names[bone]] = matrix(p[sample, column], q[sample, column],
                                            g["nodes"][names[bone]].get("scale", [1, 1, 1]))
            world = pose_world(local, parents)
            tracks["root"].append(root_delta[sample])
            for field, bone in (("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"),
                    ("footR", "foot_r"), ("toeL", "toe_l"), ("toeR", "toe_r"), ("pelvis", "pelvis")):
                tracks[field].append((RIGHT @ world[names[bone]][:, 3])[:3])
            tracks["centerOfMass"].append(weighted_center(world, masses["bones"]))
            for side, letter in (("left", "L"), ("right", "R")):
                for end, label in (("base", "Base"), ("tip", "Tip")):
                    tracks["weapon" + label + letter].append(weapon_point(side, end, world))
            for capsule, shape in zip(attacks + hurts, edges + shapes):
                for end in ("base", "tip"): shape[end].append(capsule_point(capsule[end], world, names))
            low = min((world[foot] @ marker)[1] for foot, marker in ground)
            tracks["groundLift"].append(float(max(0., -.035 - low)))
        tracks = {k: np.round(v, 7).tolist() if isinstance(v, list) else v for k, v in tracks.items()}
        for shape in edges + shapes:
            for end in ("base", "tip"): shape[end] = np.round(shape[end], 7).tolist()
        if edges: tracks["collisionEdges"] = edges
        tracks["hurtCapsules"] = shapes
        new_clip = {k: copy.deepcopy(v) for k, v in clip.items() if k not in {"tracks", "sourceConfiguration", "name"}}
        new_clip.update(name=name, tracks=tracks, sourceConfiguration=records[record_index],
                        sourceEndEventTick=132, sourceMirroringApplied=mirrored)
        profile["clips"].append(new_clip); profile["roles"][role] = name
        receipts.append(dict(name=name, role=role, sourceRecordIndex=record_index, sourceMirroringApplied=mirrored,
            frames=71, samples=141, playbackTicks=140, sourceEndEventTick=132, boundBones=58,
            channels=len(animation["channels"]), tracksSHA256=digest(encoded(tracks))))
    require(profile["clips"][:pin["count"]] == original["clips"]
            and {k: v for k, v in profile["roles"].items() if k not in {x[1] for x in VARIANTS}} == original["roles"],
            "Existing motion profile changed")
    os.mkdir(output, 0o700)
    model = output / source_glb.name
    profile.update(writer.save(model)); model.chmod(0o600)
    validate_append(raw_glb, model.read_bytes(), pin["count"])
    write_private(output / Path(profile_path).name, encoded(profile))
    receipt = dict(schema="imperial-spear-passive-own-rig-v1", profileID=profile["id"], input=pin,
        outputCharacterSHA256=profile["sha256"], outputCharacterBytes=profile["bytes"],
        outputProfileSHA256=digest(encoded(profile)), oldClipsPreserved=pin["count"], appended=receipts,
        sourceMirroringSchemaSHA256=mirror_sha, originalMediaPublished=False, nativeRendered=False,
        panguEquipmentActivated=False, geometry="Own rig, original source capsules, Float mass centre; 60 Hz baked source poses",
        precision="Portable ZXY non-singular Euler bake; not a bit-exact Unity native floating point claim")
    write_private(output / "imperial-passive-append-receipt-private.json", encoded(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source-clip", "named-config", "mirroring", "sun-profile", "liu-profile", "sun-bindings",
                 "liu-bindings", "sun-masses", "liu-masses", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args(); output = fresh_output(args.output)
    source = inputs(args.source_clip, args.named_config, args.mirroring)
    os.mkdir(output, 0o700)
    result = {key: append_profile(key, getattr(args, key + "_profile"), getattr(args, key + "_bindings"),
                  getattr(args, key + "_masses"), source, output / key) for key in PROFILES}
    write_private(output / "imperial-passive-candidate-receipt-private.json", encoded(result))
    print(json.dumps({k: {f: v[f] for f in ("outputCharacterSHA256", "outputProfileSHA256", "outputCharacterBytes")}
                      for k, v in result.items()}, sort_keys=True))


if __name__ == "__main__":
    main()
