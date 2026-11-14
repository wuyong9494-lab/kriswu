#!/usr/bin/env python3
"""Append verified local source motions without rebuilding existing geometry.

The existing GLB's meshes, skins, textures, materials, hierarchy and animation
channels stay byte-for-byte equivalent as JSON/BIN objects. New buffers and
channels are appended only. Original media and the resulting profiles remain
outside the repository. No network access or source executable is involved.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

import numpy as np

from prepare_fighter_target_motions import ARCHIVE_SHA256
from sun_triad_assets import (RIGHT, Writer, accessor_read, capsule_point, decode,
    glb_read, matrix, pose_world, private_output, require, world_poses)
from sun_triad_source_bones import capsule_binding


def digest(data):
    return hashlib.sha256(data).hexdigest()


def append(args):
    import UnityPy
    require(UnityPy.__version__ == "1.25.4", "Use the reviewed UnityPy version")
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
    output = private_output(args.output)
    original = json.loads(args.profile.read_text())
    profile = copy.deepcopy(original)
    source_glb = args.profile.parent / (profile["resourceName"] + ".glb")
    raw_glb = source_glb.read_bytes()
    require(digest(raw_glb) == profile["sha256"] and len(raw_glb) == profile["bytes"], "Character identity mismatch")
    g, binary = glb_read(source_glb)
    old_g = copy.deepcopy(g)
    writer = Writer(); writer.g = g; writer.b = bytearray(binary)
    bindings = profile["sourceBoneBindings"]
    names = {row["name"]: row["targetNode"] for row in bindings}
    bone_names = {row["sourceID"]: row["name"] for row in bindings if row.get("sourceID") is not None}
    require(len(names) == len(bindings), "Duplicate original node name")
    require(all(g["nodes"][index]["name"] == name for name, index in names.items()), "Original bone binding mismatch")
    rest_world, rest, parents = world_poses(g["nodes"])
    basis = RIGHT[:3, :3] @ rest_world[parents[names["pelvis"]]][:3, :3]
    markers = []
    for side in ("l", "r"):
        foot, toe = names["foot_" + side], names["toe_" + side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0]) - .055, max(a[0], b[0]) + .055):
            for z in (min(a[2], b[2]) - .055, max(a[2], b[2]) + .055):
                markers.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    definitions = json.loads(args.bindings.read_text())
    attacks = definitions.get("collisionEdges", [])
    hurts = definitions.get("hurtCapsules", [])
    for capsule in attacks + hurts:
        require(all(capsule[e]["bone"] in names for e in ("base", "tip")), "Unbound original capsule")

    # Older original hammers used explicit source mesh vertices. Retain those
    # exact vertices and skin weights instead of guessing a weapon bone tip.
    skin_points = {}
    for side in ("left", "right"):
        landmark = profile.get("weaponLandmarks", {}).get(side)
        if not landmark or "mesh" not in landmark:
            continue
        meshes = [(index, mesh) for index, mesh in enumerate(g["meshes"]) if mesh.get("name") == landmark["mesh"]]
        require(len(meshes) == 1, "Ambiguous original weapon mesh")
        mesh_index, mesh = meshes[0]
        nodes = [node for node in g["nodes"] if node.get("mesh") == mesh_index]
        require(len(nodes) == 1 and "skin" in nodes[0], "Missing original weapon skin")
        skin = g["skins"][nodes[0]["skin"]]
        inv_bind = accessor_read(g, binary, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        attrs = mesh["primitives"][0]["attributes"]
        positions = accessor_read(g, binary, attrs["POSITION"])
        joints = accessor_read(g, binary, attrs["JOINTS_0"])
        weights = accessor_read(g, binary, attrs["WEIGHTS_0"])
        for end in ("base", "tip"):
            vertex = landmark[end + "Vertex"]
            require(0 <= vertex < len(positions), "Original weapon landmark index is out of bounds")
            skin_points[side, end] = (np.append(positions[vertex], 1), joints[vertex], weights[vertex], skin["joints"], inv_bind)

    def weapon_point(side, end, world):
        capsule = next((c for c in attacks if c["id"] == "Ninjato_Attacking_Edge_" + side[0]), None)
        if capsule is not None:
            return capsule_point(capsule[end], world, names)
        require((side, end) in skin_points, "Original weapon landmark unavailable")
        point, joints, weights, nodes, inv_bind = skin_points[side, end]
        result = sum((world[nodes[int(j)]] @ inv_bind[int(j)] @ point) * float(w)
                     for j, w in zip(joints, weights))
        return (RIGHT @ result)[:3]

    archive_raw = args.motion_archive.read_bytes()
    require(digest(archive_raw) == ARCHIVE_SHA256, "Original motion archive identity mismatch")
    import io
    source_receipts, geometries = [], []
    with ZipFile(io.BytesIO(archive_raw)) as archive:
        catalog = json.loads(archive.read("research/motion_catalog.json"))["motions"]
        bundle_catalog = {r["file"]: r for r in map(json.loads, archive.read("research/android_bundle_catalog.jsonl").splitlines())}
        environments = {}
        for request in definitions["motions"]:
            name = request["name"]
            require(name not in {x["name"] for x in profile["clips"]}, "Motion already exists: " + name)
            candidates = [row for row in catalog if row["name"] == name and row["sha256"] == request["sha256"]]
            require(len(candidates) == 1, "Missing or ambiguous source motion")
            info = candidates[0]
            bundle = info["bundle"]
            if bundle not in environments:
                blob = archive.read("bundles/" + bundle)
                require(digest(blob) == bundle_catalog[bundle]["sha256"], "Original motion bundle identity mismatch")
                environments[bundle] = UnityPy.load(blob)
            objects = [o for o in environments[bundle].objects if o.path_id == info["path_id"]]
            require(len(objects) == 1, "Original motion object missing")
            source = objects[0].read().m_Script
            raw = source.encode("utf8", "surrogateescape") if isinstance(source, str) else bytes(source)
            require(digest(raw) == request["sha256"], "Original motion checksum mismatch")
            arrays = decode(raw); require(len(arrays) == 2, "Original motion array count changed")
            motion = arrays[0]; frames = motion["frame_count"]
            require(frames == info["frames"] and all(int(i) in bone_names for i in motion["bone_ids"]), "Original motion bone/frame mismatch")
            columns = {bone_names[int(i)]: j for j, i in enumerate(motion["bone_ids"])}
            animation = dict(name=name, samplers=[], channels=[], extras=dict(sourceSHA256=info["sha256"],
                sourceFrames=frames, sourceFPS=30, simulationHz=60, defaultMidFrames=1, previewFPS=30))
            times = writer.acc(np.arange(frames) / 30., "SCALAR")
            positions, rotations = {}, {}
            for name_of_bone, column in columns.items():
                p = motion["positions"][:, column].astype(float) * [.01, .01, -.01]
                if name_of_bone == "pelvis": p[:, [0, 2]] = 0
                q = motion["rotations"][:, column].astype(float) * [-1, -1, 1, 1]
                q /= np.linalg.norm(q, axis=1)[:, None]
                for k in range(1, len(q)):
                    if q[k - 1] @ q[k] < 0: q[k] *= -1
                positions[name_of_bone] = p.astype(np.float32).astype(float)
                rotations[name_of_bone] = q.astype(np.float32).astype(float)
                for kind, values, width in (("translation", p, "VEC3"), ("rotation", q, "VEC4")):
                    sampler = len(animation["samplers"])
                    animation["samplers"].append(dict(input=times, output=writer.acc(values, width), interpolation="LINEAR"))
                    animation["channels"].append(dict(sampler=sampler, target=dict(node=names[name_of_bone], path=kind)))
            g["animations"].append(animation)
            raw_roots = motion["positions"][:, columns["pelvis"]].astype(float) * [.01, .01, -.01]
            root_delta = (raw_roots - raw_roots[0]) @ basis.T
            tracks = {key: [] for key in ("root", "handL", "handR", "footL", "footR", "weaponBaseL", "weaponTipL", "weaponBaseR", "weaponTipR")}
            tracks.update(samplesPerSourceFrame=2, groundLift=[])
            edges = [dict(**capsule_binding(c, "attack"), base=[], tip=[]) for c in attacks]
            hurt_shapes = [dict(**capsule_binding(c, "hurt"), base=[], tip=[]) for c in hurts]
            bone_tracks = {bone: [] for bone in ("pelvis", "foot_l", "foot_r")}
            for sample in range(2 * frames - 1):
                a = sample // 2; b = min(frames - 1, a + 1); factor = (sample % 2) / 2
                local = [m.copy() for m in rest]
                for bone in columns:
                    p = positions[bone][a] * (1 - factor) + positions[bone][b] * factor
                    q = rotations[bone][a] * (1 - factor) + rotations[bone][b] * factor
                    local[names[bone]] = matrix(p, q, g["nodes"][names[bone]].get("scale", [1, 1, 1]))
                world = pose_world(local, parents)
                tracks["root"].append(root_delta[a] * (1 - factor) + root_delta[b] * factor)
                for key, bone in (("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"), ("footR", "foot_r")):
                    tracks[key].append((RIGHT @ world[names[bone]][:, 3])[:3])
                for bone in bone_tracks: bone_tracks[bone].append((RIGHT @ world[names[bone]][:, 3])[:3])
                for side, letter in (("left", "L"), ("right", "R")):
                    for end, label in (("base", "Base"), ("tip", "Tip")):
                        tracks["weapon" + label + letter].append(weapon_point(side, end, world))
                for capsule, destination in zip(attacks + hurts, edges + hurt_shapes):
                    for end in ("base", "tip"): destination[end].append(capsule_point(capsule[end], world, names))
                low = min((world[foot] @ marker)[1] for foot, marker in markers)
                tracks["groundLift"].append(float(max(0., -.035 - low)))
            tracks = {k: np.round(v, 7).tolist() if isinstance(v, list) else v for k, v in tracks.items()}
            for capsule in edges + hurt_shapes:
                for end in ("base", "tip"): capsule[end] = np.round(capsule[end], 7).tolist()
            if edges: tracks["collisionEdges"] = edges
            if hurt_shapes: tracks["hurtCapsules"] = hurt_shapes
            clip = dict(name=name, frames=frames, sha256=info["sha256"], bundle=bundle, sourcePathID=str(info["path_id"]),
                sourceBytesBase64=base64.b64encode(raw).decode(), sourceArrayCount=2,
                sourceBoneIDs=[int(x) for x in motion["bone_ids"]], tracks=tracks)
            profile["clips"].append(clip)
            for role in request["roles"]: profile["roles"][role] = name
            geometries.append(dict(name=name, sourceSHA256=info["sha256"],
                bonePoints={key: np.round(value, 7).tolist() for key, value in bone_tracks.items()}))
            source_receipts.append({key: info[key] for key in ("name", "bundle", "path_id", "sha256", "frames", "bytes")})
    # Existing binary bytes include texture/mesh/skin accessors. Ensure the
    # append never rewrote them or any existing semantic container object.
    require(bytes(writer.b[:len(binary)]) == binary, "Existing binary bytes changed")
    for key in ("nodes", "meshes", "materials", "skins", "textures", "images", "scenes", "scene", "extras"):
        require(g.get(key) == old_g.get(key), "Existing geometry/material container changed: " + key)
    require(g["animations"][:len(old_g["animations"])] == old_g["animations"], "Existing animation changed")
    model = output / source_glb.name
    profile.update(writer.save(model))
    destination = output / args.profile.name
    destination.write_text(json.dumps(profile, ensure_ascii=False, separators=(",", ":")) + "\n")
    receipt = dict(inputCharacterSHA256=original["sha256"], outputCharacterSHA256=profile["sha256"],
        originalAnimations=len(old_g["animations"]), appendedAnimations=source_receipts,
        unchanged=["existing BIN prefix", "existing animations", "nodes", "meshes", "skins", "textures", "materials", "images"],
        inputs=[dict(name=p.name, sha256=digest(p.read_bytes())) for p in (args.profile, args.bindings)],
        geometry=geometries)
    (output / (profile["resourceName"] + "_motion_append_receipt-private.json")).write_text(json.dumps(receipt, separators=(",", ":")) + "\n")
    return dict(id=profile["id"], clips=len(profile["clips"]), bytes=profile["bytes"], sha256=profile["sha256"], output=str(destination))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("profile", "bindings", "motion-archive", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(append(parser.parse_args())))


if __name__ == "__main__": main()
