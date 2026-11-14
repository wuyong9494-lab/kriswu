#!/usr/bin/env python3
"""Append three pinned shared root-victim motions to Liu's existing private rig.

Uses the already recovered 214 KB motion cache, never an archive scan or network
request. Original meshes, skinning, nodes and 56 animations remain unchanged.
FK, weapon landmarks, hurt capsules, pelvis and mass centres are evaluated on
Liu's own rig. This does not turn the reference hammers model into D19 equipment.
All original bytes and generated media remain outside the source repository.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
from pathlib import Path

import numpy as np

from stage_h17_floorfall_release import fresh_output, regular, real_directory, write_private
from sun_triad_assets import (RIGHT, Writer, accessor_read, capsule_point, decode,
    glb_read, matrix, pose_world, require, world_poses)
from sun_triad_source_bones import capsule_binding


PROFILE_SHA = "30b7af76550112c523d11d8b967553bccd7a65503d24bb21cb71f92b060c8723"
CHARACTER_SHA = "f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472"
BINDINGS_SHA = "fd16a6cb2eb863365b563aab9b162220335c6abdb0c700594499c08264151c57"
MASSES_SHA = "3bf3b9b92e118d4584019213c1d51f68b47d28dff11abb098ef42428a32dd1d2"
BUNDLE = "9893dca6e10355eb9c3c79d1613f08b1.bin"
MOTIONS = (
    dict(name="h17_root_spike_passive_start", frames=44, bytes=61522,
         path_id=-2831424740327325281,
         sha256="69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c"),
    dict(name="h17_root_spike_passive_loop", frames=61, bytes=85186,
         path_id=2284072289221197163,
         sha256="a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce"),
    dict(name="h17_root_spike_passive_end", frames=48, bytes=67090,
         path_id=-1870236551894418490,
         sha256="7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2"),
)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()


def pinned(path, sha, maximum):
    path = Path(path).absolute()
    require(path.resolve(strict=True) == path, "Input must not use symbolic links")
    raw = regular(path, maximum)
    require(digest(raw) == sha, "Reviewed input identity changed: " + path.name)
    return raw


def checked_rig(document, bindings, masses, character_sha):
    names = {row["name"]: row["targetNode"] for row in bindings}
    source_rows = [row for row in bindings if row.get("sourceID") is not None]
    bones = {row["sourceID"]: row["name"] for row in source_rows}
    require(len(names) == len(bindings) and len(bones) == len(source_rows), "Duplicate source bone binding")
    require(all(type(index) is int and 0 <= index < len(document["nodes"])
                and document["nodes"][index]["name"] == name for name, index in names.items()),
            "Original bone node binding changed")
    rows = masses["bones"]
    require(masses["characterSHA256"] == character_sha and rows
            and len({row["name"] for row in rows}) == len(rows), "Mass table identity changed")
    for row in rows:
        require(row["name"] in names and names[row["name"]] == row["targetNode"]
                and np.isfinite(row["mass"]) and row["mass"] >= 0, "Mass bone is unbound or invalid")
    require(sum(row["mass"] for row in rows) > 0, "Zero source mass")
    return names, bones


def weighted_center(world, masses):
    # Preserve recovered native Float arithmetic and original traversal order.
    accumulator, total = np.zeros(3, dtype=np.float32), np.float32(0)
    for row in masses:
        weight = np.float32(row["mass"])
        point = np.asarray((RIGHT @ world[row["targetNode"]][:, 3])[:3], dtype=np.float32)
        accumulator = np.asarray(accumulator + point * weight, dtype=np.float32)
        total = np.float32(total + weight)
    return accumulator / total


def append(args):
    output = fresh_output(args.output)
    motion_directory = real_directory(args.motions)
    original_raw = pinned(args.profile, PROFILE_SHA, 16_000_000)
    original = json.loads(original_raw)
    require(original["id"] == "liu_hammers" and original["hero"] == "liu"
            and original["resourceName"] == "Liu_Legion_Hammers"
            and original["sha256"] == CHARACTER_SHA and len(original["clips"]) == 56,
            "Expected the explicitly labelled reference character")
    source_glb = args.profile.parent / (original["resourceName"] + ".glb")
    raw_glb = pinned(source_glb, CHARACTER_SHA, 16_000_000)
    require(len(raw_glb) == original["bytes"], "Character byte count changed")
    definitions = json.loads(pinned(args.bindings, BINDINGS_SHA, 128_000))
    mass_document = json.loads(pinned(args.masses, MASSES_SHA, 128_000))
    inputs = []
    for info in MOTIONS:
        raw = pinned(motion_directory / (info["name"] + ".bytes"), info["sha256"], 128_000)
        require(len(raw) == info["bytes"], "Original motion byte count changed")
        inputs.append((info, raw))

    profile = copy.deepcopy(original)
    g, binary = glb_read(source_glb)
    old_g = copy.deepcopy(g)
    names, bone_names = checked_rig(g, profile["sourceBoneBindings"], mass_document, CHARACTER_SHA)
    rest_world, rest, parents = world_poses(g["nodes"])
    basis = RIGHT[:3, :3] @ rest_world[parents[names["pelvis"]]][:3, :3]
    writer = Writer(); writer.g = g; writer.b = bytearray(binary)
    require(len(g["animations"]) == 56, "Original animation set changed")
    markers = []
    for side in ("l", "r"):
        foot, toe = names["foot_" + side], names["toe_" + side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0]) - .055, max(a[0], b[0]) + .055):
            for z in (min(a[2], b[2]) - .055, max(a[2], b[2]) + .055):
                markers.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    attacks, hurts = definitions.get("collisionEdges", []), definitions["hurtCapsules"]
    require(not attacks and len(hurts) == 15, "Unexpected reference collision binding")
    for capsule in hurts:
        require(all(capsule[end]["bone"] in names for end in ("base", "tip")), "Unbound source hurt capsule")

    skin_points = {}
    for side in ("left", "right"):
        landmark = profile["weaponLandmarks"][side]
        meshes = [(index, mesh) for index, mesh in enumerate(g["meshes"]) if mesh.get("name") == landmark["mesh"]]
        require(len(meshes) == 1, "Ambiguous source weapon mesh")
        mesh_index, mesh = meshes[0]
        nodes = [node for node in g["nodes"] if node.get("mesh") == mesh_index]
        require(len(nodes) == 1 and "skin" in nodes[0], "Missing source weapon skin")
        skin = g["skins"][nodes[0]["skin"]]
        inv_bind = accessor_read(g, binary, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        attrs = mesh["primitives"][0]["attributes"]
        vertices = accessor_read(g, binary, attrs["POSITION"])
        joints, weights = (accessor_read(g, binary, attrs[key]) for key in ("JOINTS_0", "WEIGHTS_0"))
        for end in ("base", "tip"):
            vertex = landmark[end + "Vertex"]
            require(0 <= vertex < len(vertices), "Source weapon landmark is out of bounds")
            skin_points[side, end] = (np.append(vertices[vertex], 1), joints[vertex], weights[vertex], skin["joints"], inv_bind)

    def weapon_point(side, end, world):
        point, joints, weights, nodes, inverse = skin_points[side, end]
        value = sum((world[nodes[int(j)]] @ inverse[int(j)] @ point) * float(w)
                    for j, w in zip(joints, weights))
        return (RIGHT @ value)[:3]

    receipts = []
    for info, raw in inputs:
        name, frames = info["name"], info["frames"]
        require(name not in {clip["name"] for clip in profile["clips"]}, "Motion already exists")
        arrays = decode(raw)
        require(len(arrays) == 2 and arrays[0]["frame_count"] == frames, "Original source array/frame count changed")
        motion = arrays[0]
        ids = [int(value) for value in motion["bone_ids"]]
        require(len(ids) == len(set(ids)) == 58 and all(value in bone_names for value in ids),
                "Every source bone must bind uniquely to this character")
        columns = {bone_names[value]: column for column, value in enumerate(ids)}
        animation = dict(name=name, samplers=[], channels=[], extras=dict(sourceSHA256=info["sha256"],
            sourceFrames=frames, sourceFPS=30, simulationHz=60, defaultMidFrames=1, previewFPS=30,
            sourceBytesRetainedInProfile=True))
        times = writer.acc(np.arange(frames) / 30., "SCALAR")
        positions, rotations = {}, {}
        for bone, column in columns.items():
            p = motion["positions"][:, column].astype(float) * [.01, .01, -.01]
            if bone == "pelvis": p[:, [0, 2]] = 0
            q = motion["rotations"][:, column].astype(float) * [-1, -1, 1, 1]
            require((np.linalg.norm(q, axis=1) > 1e-12).all(), "Zero original quaternion")
            q /= np.linalg.norm(q, axis=1)[:, None]
            for k in range(1, len(q)):
                if q[k - 1] @ q[k] < 0: q[k] *= -1
            positions[bone] = p.astype(np.float32).astype(float)
            rotations[bone] = q.astype(np.float32).astype(float)
            for kind, values, width in (("translation", p, "VEC3"), ("rotation", q, "VEC4")):
                sampler = len(animation["samplers"])
                animation["samplers"].append(dict(input=times, output=writer.acc(values, width), interpolation="LINEAR"))
                animation["channels"].append(dict(sampler=sampler, target=dict(node=names[bone], path=kind)))
        g["animations"].append(animation)
        raw_roots = motion["positions"][:, columns["pelvis"]].astype(float) * [.01, .01, -.01]
        root_delta = (raw_roots - raw_roots[0]) @ basis.T
        tracks = {key: [] for key in ("root", "handL", "handR", "footL", "footR", "weaponBaseL", "weaponTipL",
            "weaponBaseR", "weaponTipR", "groundLift", "pelvis", "centerOfMass")}
        tracks["samplesPerSourceFrame"] = 2
        hurt_shapes = [dict(**capsule_binding(c, "hurt"), base=[], tip=[]) for c in hurts]
        for sample in range(2 * frames - 1):
            a, half = divmod(sample, 2); b, factor = min(frames - 1, a + 1), half / 2
            local = [value.copy() for value in rest]
            for bone in columns:
                p = positions[bone][a] * (1 - factor) + positions[bone][b] * factor
                q = rotations[bone][a] * (1 - factor) + rotations[bone][b] * factor
                local[names[bone]] = matrix(p, q, g["nodes"][names[bone]].get("scale", [1, 1, 1]))
            world = pose_world(local, parents)
            tracks["root"].append(root_delta[a] * (1 - factor) + root_delta[b] * factor)
            for key, bone in (("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"), ("footR", "foot_r"), ("pelvis", "pelvis")):
                tracks[key].append((RIGHT @ world[names[bone]][:, 3])[:3])
            tracks["centerOfMass"].append(weighted_center(world, mass_document["bones"]))
            for side, letter in (("left", "L"), ("right", "R")):
                for end, label in (("base", "Base"), ("tip", "Tip")):
                    tracks["weapon" + label + letter].append(weapon_point(side, end, world))
            for capsule, target in zip(hurts, hurt_shapes):
                for end in ("base", "tip"): target[end].append(capsule_point(capsule[end], world, names))
            low = min((world[foot] @ marker)[1] for foot, marker in markers)
            tracks["groundLift"].append(float(max(0., -.035 - low)))
        tracks = {key: np.round(value, 7).tolist() if isinstance(value, list) else value for key, value in tracks.items()}
        for capsule in hurt_shapes:
            for end in ("base", "tip"): capsule[end] = np.round(capsule[end], 7).tolist()
        tracks["hurtCapsules"] = hurt_shapes
        profile["clips"].append(dict(name=name, frames=frames, sha256=info["sha256"], bundle=BUNDLE,
            sourcePathID=str(info["path_id"]), sourceBytesBase64=base64.b64encode(raw).decode(),
            sourceArrayCount=2, sourceBoneIDs=ids, tracks=tracks))
        receipts.append(dict(**info, samples=2 * frames - 1, boundBones=len(ids), channels=len(animation["channels"]),
            tracksSHA256=digest(encoded(tracks)), pelvisSHA256=digest(encoded(tracks["pelvis"])),
            hurtCapsules=len(hurt_shapes)))

    require(bytes(writer.b[:len(binary)]) == binary, "Existing binary data changed")
    for key in ("nodes", "meshes", "materials", "skins", "textures", "images", "scenes", "scene", "extras"):
        require(g.get(key) == old_g.get(key), "Existing source container changed: " + key)
    for key in ("animations", "accessors", "bufferViews"):
        require(g[key][:len(old_g[key])] == old_g[key], "Existing source records changed: " + key)
    require(profile["clips"][:56] == original["clips"] and profile["roles"] == original["roles"],
            "Existing clips or controls changed")
    os.mkdir(output, 0o700)
    model = output / source_glb.name
    profile.update(writer.save(model)); model.chmod(0o600)
    write_private(output / args.profile.name, encoded(profile))
    receipt = dict(schema="liu-shared-root-victim-append-v1", inputProfileSHA256=PROFILE_SHA,
        inputCharacterSHA256=CHARACTER_SHA, outputCharacterSHA256=profile["sha256"],
        outputCharacterBytes=profile["bytes"], outputProfileSHA256=digest(encoded(profile)),
        inputBindingsSHA256=BINDINGS_SHA, inputMassesSHA256=MASSES_SHA,
        oldClipsPreserved=56, appended=receipts, privateMediaPublished=False,
        panguEquipmentActivated=False, resourceReclassified=False,
        unchanged=["old BIN prefix", "nodes", "meshes", "skins", "textures", "materials", "images",
                   "old animations", "old accessors", "old buffer views", "old clips", "control roles"],
        geometry="Liu rig FK; 60 Hz half-frame local nlerp; original skinned weapon landmarks; original 15 hurt capsules; own pelvis and 58-bone Float COM")
    write_private(output / "root-victim-append-receipt-private.json", encoded(receipt))
    return {key: receipt[key] for key in ("inputCharacterSHA256", "outputCharacterSHA256", "outputCharacterBytes",
        "oldClipsPreserved", "panguEquipmentActivated", "resourceReclassified")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("profile", "bindings", "masses", "motions", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(append(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
