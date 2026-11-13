#!/usr/bin/env python3
"""Export the four verified source skins; no generated mesh, animation or texture.

Run only against the already recovered private bundles and byte-verified equipped
fighters. Clear output is private input to fighter_source_trails.py's envelope.
No source shader/controller equivalence is claimed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import warnings
import zlib


def digest(data):
    return hashlib.sha256(data).hexdigest()


BUNDLES = {
    "b0a04b3fa5028da909862b6332e2e0b8.bin": "e9b3a8d70a738db1a91a728812f6e5f4bfaad4dda896913cb9721a9e8dddb9e4",
    "45d6c13eaf9b6359e0d11caac0ee92e9.bin": "d6f278f0f19fb5c26006b1b0e70de3da0836f1e5ea84d27b0ae8d5440a04a540",
    "6c577d30c62b64c3176e1ba9341f8fb7.bin": "cdc7bc96e6075fe27c348ae5bd6fbd28da2c096078a942e3f129c04f3d19f96e",
}
CHARACTERS = {
    "Sun_Herald_Katana": "5a1a64c9986b0d5284a7986efc1589dbfc1f00f91ac9477cdae45930612ac553",
    "Liu_Legion_Hammers": "9ff998118a69b1d089694e97b2623cf6d6fb81e64451a8462dddaff756b6a09f",
}


def export(source, fighters, output):
    import numpy as np
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    warnings.simplefilter("ignore")
    UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
    for name, sha in BUNDLES.items():
        assert digest((source / name).read_bytes()) == sha, name
    catalog_data = (fighters / "SF3_DistinctFighters.json").read_bytes()
    assert digest(catalog_data) == "c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f"
    catalog = json.loads(catalog_data)
    env = UnityPy.load(*(str(source / name) for name in BUNDLES))
    meshes = {}
    bindings = {}
    for obj in env.objects:
        if obj.type.name == "Mesh":
            mesh = obj.read()
            if "__trail_" in mesh.m_Name:
                assert mesh.m_Name not in meshes
                meshes[mesh.m_Name] = mesh
        elif obj.type.name == "MonoBehaviour":
            tree = obj.read_typetree()
            names = tree.get("_bindBonesName", [])
            if len(names) == 4 and all("_trail" in name for name in names):
                bindings[names[0]] = names
    assert len(meshes) == 4 and len(bindings) == 4
    conversion = np.diag([.01, .01, -.01, 1.])
    inverse = np.linalg.inv(conversion)
    profiles = []
    audit = []
    for resource, sha in CHARACTERS.items():
        raw = (fighters / (resource + ".glb")).read_bytes()
        assert digest(raw) == sha
        length = struct.unpack_from("<I", raw, 12)[0]
        gltf = json.loads(raw[20:20 + length])
        profile = next(p for p in catalog["profiles"] if p["resourceName"] == resource)
        hashes = {zlib.crc32(row["path"].encode()): row for row in profile["sourceBoneBindings"]}
        rows = []
        for name, mesh in sorted(meshes.items()):
            if ("katana" in name) != (profile["hero"] == "ember"):
                continue
            bone_rows = [hashes[value] for value in mesh.m_BoneNameHashes]
            bones = [row["name"] for row in bone_rows]
            assert bones == bindings[bones[0]]
            assert len(mesh.m_BindPose) == 4
            assert all(gltf["nodes"][row["targetNode"]]["name"] == row["name"] for row in bone_rows)
            handler = MeshHandler(mesh)
            handler.process()
            vertices = np.asarray(handler.m_Vertices)[:, :3] * [.01, .01, -.01]
            normals = np.asarray(handler.m_Normals)[:, :3] * [1, 1, -1]
            uv = np.asarray(handler.m_UV0)[:, :2].copy()
            uv[:, 1] = 1 - uv[:, 1]
            weights = np.asarray(handler.m_BoneWeights)
            joints = np.asarray(handler.m_BoneIndices)
            assert np.max(abs(weights.sum(axis=1) - 1)) < 1e-6
            assert (joints >= 0).all() and (joints < 4).all()
            assert not handler.m_UV1  # source shader's equipment UV channel is absent
            triangles = np.asarray(handler.get_triangles()[0])[:, [0, 2, 1]]
            matrices = [conversion @ np.array([[getattr(m, f"e{r}{c}") for c in range(4)] for r in range(4)]) @ inverse
                        for m in mesh.m_BindPose]
            def floats(values):
                value = np.asarray(values, dtype=np.float32)
                assert np.isfinite(value).all()
                return value.reshape(-1).tolist()
            rows.append(dict(name=name, side="left" if name.endswith("_l") else "right", bones=bones,
                             sourceBoneIDs=[row["sourceID"] for row in bone_rows],
                             positions=floats(vertices), normals=floats(normals), uv=floats(uv),
                             weights=floats(weights), joints=joints.reshape(-1).tolist(),
                             indices=triangles.reshape(-1).tolist(),
                             inverseBinds=[floats(m.T) for m in matrices]))
            audit.append(dict(name=name, vertices=len(vertices), triangles=len(triangles), bones=bones,
                              boneHashes=list(mesh.m_BoneNameHashes), sourceBoneIDs=rows[-1]["sourceBoneIDs"],
                              bindOrderMatchesPrefab=True, equipmentUVPresent=False))
        clips = []
        trail_nodes = {row["targetNode"] for row in profile["sourceBoneBindings"] if "_trail" in row["name"]}
        for clip in gltf["animations"]:
            if any(channel["target"]["node"] in trail_nodes for channel in clip["channels"]):
                clips.append(clip["name"])
        profiles.append(dict(id=profile["id"], characterSHA256=sha, meshes=rows, clips=sorted(clips)))
    payload = dict(version=1, profiles=profiles, alphaTexture="SF3WE_1394430195881985131.png",
                   alphaSHA256="c8a01bc4e4574aff6e7dbf3615fbc673301364f776c1bd8483f509025f8fc386",
                   limitations=["Ordinary source mesh/UV0/bind order/weights and existing source motion are retained.",
                                "Visibility uses the existing application attack window; original controller events remain unverified.",
                                "The source secondary equipment UV is absent. This adapter uses the verified alpha texture and neutral tint; source lighting and dynamic equipment UV are not reconstructed."])
    clear = (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(clear)
    return dict(file=output.name, bytes=len(clear), sha256=digest(clear), meshes=audit,
                profiles=[dict(id=p["id"], sourceAnimatedClipCount=len(p["clips"])) for p in profiles])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--fighters", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    result = export(args.source, args.fighters, args.output)
    args.audit.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Verified four original trail meshes; private payload {result['bytes']} bytes, {result['sha256']}")
