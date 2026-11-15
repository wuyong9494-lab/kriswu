#!/usr/bin/env python3
"""Append the three cached, original common Stun motions to the reviewed rigs.

Only the pinned 2.7 MB bundle and two inventory members are read from the
existing source archive. Original geometry, skins and old animation channels
are preserved. This creates private candidates, never activates Pangu, fetches
resources, executes a client, or publishes original media.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
import os
from pathlib import Path
from zipfile import ZipFile

import numpy as np

from append_cached_root_victim_motions import checked_rig, digest, encoded, pinned, weighted_center
from prepare_fighter_target_motions import read_text_assets
from stage_h17_floorfall_release import fresh_output, write_private
from stage_h17_shared_root_release import glb_chunks
from sun_triad_assets import (RIGHT, Writer, accessor_read, capsule_point, decode,
    glb_read, matrix, pose_world, require, world_poses)
from sun_triad_source_bones import capsule_binding


BUNDLE = "1b0a132a449bc2947a2a326ff30ff33d.bin"
BUNDLE_SHA = "0f94e38b3270548b43d601e00e65dfdcf430d7a06c38e4d6c1eb407102fe5b20"
MEMBERS = {
    "research/motion_catalog.json": (3_008_671, "09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8"),
    "research/android_bundle_catalog.jsonl": (9_100_700, "2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055"),
    "bundles/" + BUNDLE: (2_746_808, BUNDLE_SHA),
}
MOTIONS = (
    dict(name="h_stun_start", role="sourceStunIn", frames=31, bytes=43426,
         path_id=1063423564692364207,
         sha256="ea3b5942fd8c7d8721f9b90bfab4c7c03c55a3dd570c4aa9cff12eefd4d9965b"),
    dict(name="h_stun_loop", role="sourceStunLoop", frames=35, bytes=48994,
         path_id=4075479027709813272,
         sha256="bd1e3f455499a3caf6df7b67d5c5e40c0aff418fa88dd96aab6fd014de879eb3"),
    dict(name="h_stun_end", role="sourceStunOut", frames=31, bytes=43426,
         path_id=3764084586578974847,
         sha256="5d23977e9369fa15724fe5f0b9e3abdf7393d944182425f734258f14369c1eac"),
)
BONES = [41,31,40,39,38,37,36,35,34,33,32,30,29,28,58,27,26,42,25,5,4,3,24,23,13,
         22,21,20,19,18,17,16,15,14,12,11,10,57,9,8,7,2,1,60,55,54,53,52,56,51,59,
         47,46,45,44,48,43,0]
PROFILES = {
    "sun": dict(id="sun_triad", resource="Sun_DeadForestTriad_Ninjato", count=65,
        profileSHA="303b0c010def983688b0fa38ee201bcbdb26a031f20ce03add47c091158b5cfe",
        characterSHA="ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6",
        bindingsSHA="3e292f26f59830d397cf1471ff4e5c3e62652c0c7f1752694213a48187da893a",
        massesSHA="89f89bdb912eb2b98cd1e8b5506fe308a38ad2ffb2114d569409d8b8e4c0ff6b",
        massCharacterSHA="ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"),
    "liu": dict(id="liu_hammers", resource="Liu_Legion_Hammers", count=59,
        profileSHA="2dbe085bd288a4aff2bf9694d5e55699500879feb203985a342b76c1036b81ca",
        characterSHA="a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517",
        bindingsSHA="fd16a6cb2eb863365b563aab9b162220335c6abdb0c700594499c08264151c57",
        massesSHA="3bf3b9b92e118d4584019213c1d51f68b47d28dff11abb098ef42428a32dd1d2",
        massCharacterSHA="f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472"),
}


def validate_stun_append(old, new, count):
    original, _, old_binary = glb_chunks(old)
    appended, _, new_binary = glb_chunks(new)
    require(set(original) == set(appended) and len(new_binary) > len(old_binary)
            and new_binary[:len(old_binary)] == old_binary,
            "Original GLB structure/BIN prefix changed")
    for key in original:
        if key in {"animations", "accessors", "bufferViews"}:
            require(appended[key][:len(original[key])] == original[key], "Original GLB records changed")
        elif key != "buffers":
            require(appended[key] == original[key], "Original geometry, material or skin changed")
    require(len(original["animations"]) == count and len(appended["animations"]) == count + 3
            and [a["name"] for a in appended["animations"][count:]] == [m["name"] for m in MOTIONS],
            "Expected exactly the three reviewed Stun motions")


def cached_motions(archive):
    archive = Path(archive).absolute()
    require(archive.resolve(strict=True) == archive and archive.is_file(), "Expected the existing regular archive")
    with ZipFile(archive) as container:
        selected = {}
        for name, (size, sha) in MEMBERS.items():
            entries = [info for info in container.infolist() if info.filename == name]
            require(len(entries) == 1 and entries[0].file_size == size, "Source archive member identity differs")
            raw = container.read(entries[0])
            require(len(raw) == size and digest(raw) == sha, "Source archive member hash differs")
            selected[name] = raw
    catalog = json.loads(selected["research/motion_catalog.json"])["motions"]
    bundles = [json.loads(line) for line in selected["research/android_bundle_catalog.jsonl"].splitlines()]
    matches = [row for row in bundles if row["file"] == BUNDLE]
    require(len(matches) == 1, "Source bundle inventory is ambiguous")
    bundle = matches[0]
    require(bundle["cached"] is True and bundle["crc_ok"] is True
            and bundle["sha256"] == BUNDLE_SHA and bundle["bytes"] == MEMBERS["bundles/" + BUNDLE][0],
            "Expected the fully cached, reviewed source bundle")
    objects = read_text_assets(selected["bundles/" + BUNDLE], {m["path_id"] for m in MOTIONS})
    result = []
    for motion in MOTIONS:
        rows = [row for row in catalog if row["name"] == motion["name"] and row["bundle"] == BUNDLE]
        require(len(rows) == 1 and all(rows[0][key] == motion[key]
                for key in ("name", "frames", "bytes", "path_id", "sha256"))
                and rows[0]["arrays"] == 2 and rows[0]["bone_ids"] == BONES,
                "Source motion inventory differs")
        path = "assets/gamedata/resources/content/animations/binaries/hits/" + motion["name"] + ".bytes"
        require([row for row in bundle["paths"] if row["path"] == path] ==
                [dict(path=path, file_id=0, path_id=motion["path_id"])], "Source motion object path differs")
        name, raw = objects[motion["path_id"]]
        require(name == motion["name"] and len(raw) == motion["bytes"] and digest(raw) == motion["sha256"],
                "Original Stun TextAsset differs")
        result.append((motion, raw))
    return result


def weapon_sampler(g, binary, profile, names):
    """Each rig keeps its reviewed original landmark method."""
    if profile["id"] == "sun_triad":
        landmarks = profile["weaponLandmarks"]
        require(set(landmarks) == {"l", "r"}, "Source bilateral blade landmarks changed")
        for value in landmarks.values():
            require(all(value[end]["bone"] in names for end in ("base", "tip")), "Unbound source blade")
        return lambda side, end, world: capsule_point(landmarks[side[0]][end], world, names)
    require(profile["id"] == "liu_hammers", "Unsupported source rig")
    points = {}
    for side in ("left", "right"):
        landmark = profile["weaponLandmarks"][side]
        meshes = [(i, mesh) for i, mesh in enumerate(g["meshes"]) if mesh.get("name") == landmark["mesh"]]
        require(len(meshes) == 1, "Ambiguous original weapon mesh")
        mesh_index, mesh = meshes[0]
        nodes = [node for node in g["nodes"] if node.get("mesh") == mesh_index]
        require(len(nodes) == 1 and "skin" in nodes[0], "Missing original weapon skin")
        skin = g["skins"][nodes[0]["skin"]]
        inverse = accessor_read(g, binary, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        attrs = mesh["primitives"][0]["attributes"]
        vertices = accessor_read(g, binary, attrs["POSITION"])
        joints, weights = (accessor_read(g, binary, attrs[key]) for key in ("JOINTS_0", "WEIGHTS_0"))
        for end in ("base", "tip"):
            vertex = landmark[end + "Vertex"]
            require(type(vertex) is int and 0 <= vertex < len(vertices), "Original landmark index differs")
            points[side, end] = (np.append(vertices[vertex], 1), joints[vertex], weights[vertex], skin["joints"], inverse)
    def sample(side, end, world):
        point, joints, weights, nodes, inverse = points[side, end]
        value = sum((world[nodes[int(j)]] @ inverse[int(j)] @ point) * float(w) for j, w in zip(joints, weights))
        return (RIGHT @ value)[:3]
    return sample


def append_profile(key, profile_path, bindings_path, masses_path, inputs, output):
    pin = PROFILES[key]
    original = json.loads(pinned(profile_path, pin["profileSHA"], 24_000_000))
    require(original["id"] == pin["id"] and original["resourceName"] == pin["resource"]
            and original["sha256"] == pin["characterSHA"] and len(original["clips"]) == pin["count"],
            "Expected the reviewed current character profile")
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
    require(len(attacks) == (4 if key == "sun" else 0) and len(hurts) == 15, "Source capsule count differs")
    for capsule in attacks + hurts:
        require(all(capsule[end]["bone"] in names for end in ("base", "tip")), "Unbound original capsule")
    writer = Writer(); writer.g = g; writer.b = bytearray(binary)
    require(len(g["animations"]) == pin["count"], "Original animation set differs")
    markers = []
    for side in ("l", "r"):
        foot, toe = names["foot_" + side], names["toe_" + side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0]) - .055, max(a[0], b[0]) + .055):
            for z in (min(a[2], b[2]) - .055, max(a[2], b[2]) + .055):
                markers.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    receipts = []
    for info, raw in inputs:
        name, frames = info["name"], info["frames"]
        require(name not in {clip["name"] for clip in profile["clips"]} and info["role"] not in profile["roles"],
                "Stun binding already exists")
        arrays = decode(raw)
        require(len(arrays) == 2 and arrays[0]["frame_count"] == frames
                and [int(x) for x in arrays[0]["bone_ids"]] == BONES, "Source Stun frames/bones differ")
        require(all(value in bone_names for value in BONES), "Unbound original Stun bone")
        motion = arrays[0]; columns = {bone_names[value]: i for i, value in enumerate(BONES)}
        animation = dict(name=name, samplers=[], channels=[], extras=dict(sourceSHA256=info["sha256"],
            sourceFrames=frames, sourceFPS=30, simulationHz=60, defaultMidFrames=1,
            previewFPS=30, sourceBytesRetainedInProfile=True))
        times = writer.acc(np.arange(frames) / 30., "SCALAR")
        positions, rotations = {}, {}
        for bone, column in columns.items():
            p = motion["positions"][:, column].astype(float) * [.01, .01, -.01]
            if bone == "pelvis": p[:, [0, 2]] = 0
            q = motion["rotations"][:, column].astype(float) * [-1, -1, 1, 1]
            require((np.linalg.norm(q, axis=1) > 1e-12).all(), "Zero source quaternion")
            q /= np.linalg.norm(q, axis=1)[:, None]
            for i in range(1, len(q)):
                if q[i - 1] @ q[i] < 0: q[i] *= -1
            positions[bone] = p.astype(np.float32).astype(float)
            rotations[bone] = q.astype(np.float32).astype(float)
            for kind, values, width in (("translation", p, "VEC3"), ("rotation", q, "VEC4")):
                index = len(animation["samplers"])
                animation["samplers"].append(dict(input=times, output=writer.acc(values, width), interpolation="LINEAR"))
                animation["channels"].append(dict(sampler=index, target=dict(node=names[bone], path=kind)))
        g["animations"].append(animation)
        roots = motion["positions"][:, columns["pelvis"]].astype(float) * [.01, .01, -.01]
        root_delta = (roots - roots[0]) @ basis.T
        tracks = {key: [] for key in ("root", "handL", "handR", "footL", "footR", "weaponBaseL", "weaponTipL",
            "weaponBaseR", "weaponTipR", "groundLift", "pelvis", "centerOfMass")}
        tracks["samplesPerSourceFrame"] = 2
        edges = [dict(**capsule_binding(c, "attack"), base=[], tip=[]) for c in attacks]
        shapes = [dict(**capsule_binding(c, "hurt"), base=[], tip=[]) for c in hurts]
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
            tracks["centerOfMass"].append(weighted_center(world, masses["bones"]))
            for side, letter in (("left", "L"), ("right", "R")):
                for end, label in (("base", "Base"), ("tip", "Tip")):
                    tracks["weapon" + label + letter].append(weapon_point(side, end, world))
            for capsule, shape in zip(attacks + hurts, edges + shapes):
                for end in ("base", "tip"): shape[end].append(capsule_point(capsule[end], world, names))
            low = min((world[foot] @ marker)[1] for foot, marker in markers)
            tracks["groundLift"].append(float(max(0., -.035 - low)))
        tracks = {key: np.round(value, 7).tolist() if isinstance(value, list) else value for key, value in tracks.items()}
        for shape in edges + shapes:
            for end in ("base", "tip"): shape[end] = np.round(shape[end], 7).tolist()
        if edges: tracks["collisionEdges"] = edges
        tracks["hurtCapsules"] = shapes
        profile["clips"].append(dict(name=name, frames=frames, sha256=info["sha256"], bundle=BUNDLE,
            sourcePathID=str(info["path_id"]), sourceBytesBase64=base64.b64encode(raw).decode(),
            sourceArrayCount=2, sourceBoneIDs=BONES, tracks=tracks))
        profile["roles"][info["role"]] = name
        receipts.append(dict(**info, sourceFile="hits/" + name + ".bin", samples=2 * frames - 1,
            boundBones=len(BONES), channels=len(animation["channels"]), tracksSHA256=digest(encoded(tracks)),
            collisionEdges=len(edges), hurtCapsules=len(shapes)))
    require(profile["clips"][:pin["count"]] == original["clips"]
            and {k: v for k, v in profile["roles"].items() if not k.startswith("sourceStun")} == original["roles"],
            "Existing clips/roles changed")
    os.mkdir(output, 0o700)
    model = output / source_glb.name
    profile.update(writer.save(model)); model.chmod(0o600)
    validate_stun_append(raw_glb, model.read_bytes(), pin["count"])
    write_private(output / Path(profile_path).name, encoded(profile))
    receipt = dict(schema="common-source-stun-append-v1", profileID=profile["id"], input=pin,
        outputCharacterSHA256=profile["sha256"], outputCharacterBytes=profile["bytes"],
        outputProfileSHA256=digest(encoded(profile)), oldClipsPreserved=pin["count"], appended=receipts,
        originalMediaPublished=False, panguEquipmentActivated=False, resourceReclassified=False,
        unchanged=["old BIN prefix", "nodes", "meshes", "skins", "textures", "materials", "images",
                   "old animations", "old accessors", "old buffer views", "old clips", "old control roles"],
        timing="MidFrames=1 at60Hz; source31/35/31frames. Native active-stun re-entry event order remains unproven.",
        geometry="Own rig FK/weapon landmarks/15hurt capsules/pelvis/FloatCOM; half-frame local nlerp")
    write_private(output / "stun-append-receipt-private.json", encoded(receipt))
    return receipt


def append(args):
    output = fresh_output(args.output)
    inputs = cached_motions(args.archive)
    os.mkdir(output, 0o700)
    raw_dir = output / "original-motions"; os.mkdir(raw_dir, 0o700)
    for info, raw in inputs: write_private(raw_dir / (info["name"] + ".bytes"), raw)
    receipts = {}
    for key in PROFILES:
        receipts[key] = append_profile(key, getattr(args, key + "_profile"), getattr(args, key + "_bindings"),
            getattr(args, key + "_masses"), inputs, output / key)
    receipt = dict(schema="common-source-stun-private-candidate-v1", bundle=BUNDLE, bundleSHA256=BUNDLE_SHA,
        inventoryMembers={name: dict(bytes=pin[0], sha256=pin[1]) for name, pin in MEMBERS.items()},
        profiles=receipts, productionPanguActivated=False, nativeRendered=False)
    write_private(output / "stun-candidate-receipt-private.json", encoded(receipt))
    return {key: {field: row[field] for field in ("outputCharacterSHA256", "outputCharacterBytes", "oldClipsPreserved")}
            for key, row in receipts.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("archive", "sun-profile", "liu-profile", "sun-bindings", "liu-bindings", "sun-masses", "liu-masses", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    print(json.dumps(append(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
