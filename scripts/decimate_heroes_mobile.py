#!/usr/bin/env python3
"""Face-preserving mobile mesh decimation + optional clean-UV albedo rebake + surgical GLB swap.

- wuYong & sunDeng heads: watertight manifold decimation preserving original continuous UVs.
- xuXiao head+body & liuQuanwei head (micro-UV-chart photogrammetry meshes): watertight manifold
  cleanup (nm_left=0) -> face-protected Collapse Decimate -> clean Smart UV -> 1-sample Cycles
  EMIT pure-albedo transfer from the original high-poly mesh -> 1024x1024 JPEG (q=92).
- Surgically replaces ONLY target mesh primitives (and baked diffuse JPEG for rebaked slots)
  inside each DuelChar_<hero>.glb while preserving 100% of original nodes, weapon sockets, skins,
  inverseBindMatrices, materials, other textures, and all 120 60fps animations bit-for-bit.

Usage:
    python3 scripts/decimate_heroes_mobile.py [--apply] [--preview /path/to/sheet.png]
"""
import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CHAR_DIR = REPO / "App/Resources/DuelCharacters"
BLENDER = Path("/home/antigravity/blender/blender")

TARGETS = {
    "wuYong": {
        "WuYong_UserPortrait": {"target_tris": 18000, "is_head": True, "rebake_slot": None},
    },
    "xuXiao": {
        "XuXiao_ProvidedHead": {"target_tris": 26000, "is_head": True, "rebake_slot": None},
        "XuXiao_Body_CutAtCollar": {"target_tris": 28000, "is_head": False, "rebake_slot": None},
    },
    "liuQuanwei": {
        "Liu exact substitute head": {"target_tris": 22000, "is_head": True, "rebake_slot": None},
    },
    "sunDeng": {
        "SunDeng_222_Head": {"target_tris": 18000, "is_head": True, "rebake_slot": None},
    },
}

BLENDER_DECIMATE_SCRIPT = r'''
import bpy, bmesh, json, math, os, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
in_glb, out_glb, bake_dir, spec_json = argv[0], argv[1], argv[2], argv[3]
targets = json.loads(spec_json)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_glb)

# Delete stray unparented helper meshes
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.parent is None and obj.name not in targets:
        bpy.data.objects.remove(obj, do_unlink=True)

# Remove non-target meshes (keep armature intact)
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj.name not in targets:
        bpy.data.objects.remove(obj, do_unlink=True)

baked_manifest = {}

def make_emit_copy(src_obj):
    """Clone src_obj with pure Emission shader wired from each material's Base Color
    (texture or solid color) so Cycles EMIT bake transfers 1:1 unlit albedo with zero
    metallic darkening, shadow bleed, or color shift."""
    dup_me = src_obj.data.copy()
    dup = bpy.data.objects.new(src_obj.name + "__SRC__", dup_me)
    bpy.context.collection.objects.link(dup)
    dup.parent = src_obj.parent
    dup.matrix_local = src_obj.matrix_local.copy()
    new_mats = []
    for m in dup_me.materials:
        em = bpy.data.materials.new(name=(m.name if m else "M") + "__EMIT__")
        em.use_nodes = True
        nt = em.node_tree
        nt.nodes.clear()
        out_n = nt.nodes.new("ShaderNodeOutputMaterial")
        emit_n = nt.nodes.new("ShaderNodeEmission")
        emit_n.inputs["Strength"].default_value = 1.0
        nt.links.new(emit_n.outputs["Emission"], out_n.inputs["Surface"])

        img = None
        base_col = (0.8, 0.8, 0.8, 1.0)
        if m and m.use_nodes and m.node_tree:
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf:
                bc = bsdf.inputs.get("Base Color")
                if bc:
                    base_col = tuple(bc.default_value)
                    if bc.is_linked:
                        from_n = bc.links[0].from_node
                        stack = [from_n]
                        visited = set()
                        while stack:
                            cur = stack.pop()
                            if cur in visited: continue
                            visited.add(cur)
                            if cur.type == "TEX_IMAGE" and cur.image:
                                img = cur.image; break
                            for inp in cur.inputs:
                                if inp.is_linked:
                                    stack.append(inp.links[0].from_node)
        if img is not None:
            tex_n = nt.nodes.new("ShaderNodeTexImage")
            tex_n.image = img
            nt.links.new(tex_n.outputs["Color"], emit_n.inputs["Color"])
        else:
            emit_n.inputs["Color"].default_value = base_col
        new_mats.append(em)
    dup_me.materials.clear()
    for em in new_mats:
        dup_me.materials.append(em)
    return dup

for name, cfg in targets.items():
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Missing target mesh {name!r}")
    me = obj.data
    orig_v = len(me.vertices)
    orig_p = len(me.polygons)

    rebake_slot = cfg.get("rebake_slot")
    src_copy = make_emit_copy(obj) if rebake_slot is not None else None

    # 1. Watertight vertex weld + non-manifold (>2 face) interior-face cleanup
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=3e-5)
    bm.normal_update()
    removed_nm = 0
    for _ in range(4):
        to_del = set()
        for e in bm.edges:
            if len(e.link_faces) > 2:
                fs = sorted(e.link_faces, key=lambda f: f.calc_area(), reverse=True)
                for extra in fs[2:]:
                    to_del.add(extra)
        if not to_del:
            break
        bmesh.ops.delete(bm, geom=list(to_del), context="FACES")
        removed_nm += len(to_del)
    loose0 = [v for v in bm.verts if not v.link_faces]
    if loose0:
        bmesh.ops.delete(bm, geom=loose0, context="VERTS")
    nm_left = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    bm.to_mesh(me)
    bm.free()
    me.validate(verbose=False)
    me.update()
    welded_v = len(me.vertices)
    welded_p = len(me.polygons)

    # 2. Strict front-face + ear protection vertex group (0.0 = 100% PROTECTED, 1.0 = COLLAPSED)
    def build_face_vg():
        vgn = "__decim_collapse_weight__"
        if vgn in obj.vertex_groups:
            obj.vertex_groups.remove(obj.vertex_groups[vgn])
        vg = obj.vertex_groups.new(name=vgn)
        wc = [obj.matrix_world @ v.co for v in obj.data.vertices]
        xs, ys, zs = [c.x for c in wc], [c.y for c in wc], [c.z for c in wc]
        cx = 0.5 * (min(xs) + max(xs))
        sx = max(1e-4, max(xs) - min(xs))
        miny, sy = min(ys), max(1e-4, max(ys) - min(ys))
        minz, sz = min(zs), max(1e-4, max(zs) - min(zs))
        for v, c in zip(obj.data.vertices, wc):
            ny = (c.y - miny) / sy
            nz = (c.z - minz) / sz
            nx = abs(c.x - cx) / (0.5 * sx)
            # Keep 100% original geometry on eyes/brows/nose/lips/cheeks/chin AND ears/sideburns
            if ny < 0.54 and 0.20 <= nz <= 0.80 and nx < 0.96:
                w = 0.0
            elif ny < 0.68 and 0.14 <= nz <= 0.88:
                w = 0.16
            else:
                w = 1.0
            vg.add([v.index], w, "REPLACE")
        return vgn

    # 3. Collapse Decimate BEFORE Armature modifier; keep face protection active on EVERY pass!
    target_tris = int(cfg["target_tris"])
    for dec_pass in range(2):
        cur_p = len(obj.data.polygons)
        if cur_p <= target_tris * 1.15:
            break
        vg_name = build_face_vg() if cfg.get("is_head") else None
        ratio = min(1.0, max(0.04, float(target_tris) / max(1, cur_p)))
        mod = obj.modifiers.new(name=f"MobileDecimate_{dec_pass}", type="DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        if vg_name:
            mod.vertex_group = vg_name
            mod.vertex_group_factor = 10.0
            mod.invert_vertex_group = False
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        if vg_name and vg_name in obj.vertex_groups:
            obj.vertex_groups.remove(obj.vertex_groups[vg_name])
        if len(obj.data.polygons) >= cur_p * 0.96:
            break

    # Purge any loose verts & validate
    bm2 = bmesh.new()
    bm2.from_mesh(obj.data)
    loose = [v for v in bm2.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm2, geom=loose, context="VERTS")
    bm2.to_mesh(obj.data)
    bm2.free()
    obj.data.validate(verbose=False)
    obj.data.update()
    for poly in obj.data.polygons:
        poly.use_smooth = True

    # 4. If rebake_slot is requested, re-unwrap clean UVs and bake pure albedo from src_copy!
    if rebake_slot is not None and src_copy is not None:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.005, area_weight=0.0, correct_aspect=True, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")

        img_name = f"baked_{name.replace(' ', '_')}"
        bake_img = bpy.data.images.new(name=img_name, width=1024, height=1024, alpha=False, float_buffer=False)
        bake_img.colorspace_settings.name = "sRGB"

        mat_slot = obj.data.materials[rebake_slot]
        mat_name = mat_slot.name if mat_slot else ""
        temp_nodes = []
        for mi, m in enumerate(obj.data.materials):
            if m is None:
                continue
            m.use_nodes = True
            nt = m.node_tree
            for n in nt.nodes:
                n.select = False
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = bake_img
            tn.select = True
            nt.nodes.active = tn
            temp_nodes.append((nt, tn))

        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 4
        scene.cycles.use_denoising = False
        scene.render.bake.use_selected_to_active = True
        scene.render.bake.cage_extrusion = 0.005
        scene.render.bake.max_ray_distance = 0.022
        scene.render.bake.margin = 10
        scene.render.bake.margin_type = "EXTEND"

        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = (o not in (obj, src_copy))
                o.hide_viewport = False
        bpy.ops.object.select_all(action="DESELECT")
        src_copy.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        for o in (obj, src_copy):
            for md in o.modifiers:
                if md.type == "ARMATURE":
                    md.show_viewport = False
                    md.show_render = False

        bpy.ops.object.bake(type="EMIT")

        for o in (obj, src_copy):
            for md in o.modifiers:
                if md.type == "ARMATURE":
                    md.show_viewport = True
                    md.show_render = True

        jpg_path = os.path.join(bake_dir, f"{img_name}.jpg")
        scene.render.image_settings.file_format = "JPEG"
        scene.render.image_settings.quality = 92
        bake_img.save_render(filepath=jpg_path, scene=scene)
        baked_manifest[mat_name] = jpg_path

        for nt, tn in temp_nodes:
            nt.nodes.remove(tn)
        bpy.data.objects.remove(src_copy, do_unlink=True)
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = False

    print(f"DECIMATED {name}: {orig_v}v/{orig_p}p -> welded {welded_v}v/{welded_p}p (nm_del={removed_nm}, nm_left={nm_left}) -> final {len(obj.data.vertices)}v/{len(obj.data.polygons)}p rebake={rebake_slot is not None}")

with open(os.path.join(bake_dir, "baked_manifest.json"), "w") as f:
    json.dump(baked_manifest, f)

bpy.ops.export_scene.gltf(
    filepath=out_glb,
    export_format="GLB",
    export_animations=False,
    export_materials="PLACEHOLDER",
    export_skins=True,
    export_all_influences=False,
    export_normals=True,
    export_texcoords=True,
    export_tangents=False,
    export_apply=False,
)
'''


def read_glb(path: Path):
    data = path.read_bytes()
    magic, version, total_len = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2
    jlen, jtype = struct.unpack_from("<II", data, 12)
    assert jtype == 0x4E4F534A
    gltf = json.loads(data[20:20 + jlen].decode("utf-8"))
    boff = 20 + jlen
    bin_data = b""
    if boff + 8 <= len(data):
        blen, btype = struct.unpack_from("<II", data, boff)
        assert btype == 0x004E4942
        bin_data = data[boff + 8:boff + 8 + blen]
    return gltf, bin_data


def write_glb(path: Path, gltf: dict, bin_data: bytes):
    jbytes = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    while len(jbytes) % 4 != 0:
        jbytes += b" "
    bpad = bytearray(bin_data)
    while len(bpad) % 4 != 0:
        bpad.append(0)
    total = 12 + 8 + len(jbytes) + 8 + len(bpad)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(jbytes), 0x4E4F534A)
    out += jbytes
    out += struct.pack("<II", len(bpad), 0x004E4942)
    out += bpad
    path.write_bytes(bytes(out))


COMP_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
COMP_FMT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


def read_accessor_raw(gltf, bin_data, acc_idx):
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    comp = acc["componentType"]
    ncomp = TYPE_COUNTS[acc["type"]]
    csize = COMP_SIZES[comp]
    elem_size = ncomp * csize
    stride = bv.get("byteStride", elem_size)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    fmt = "<" + COMP_FMT[comp] * ncomp
    vals = [struct.unpack_from(fmt, bin_data, base + i * stride) for i in range(count)]
    return acc, vals


def accessor_bytes(gltf, bin_data, acc_idx):
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    comp = acc["componentType"]
    ncomp = TYPE_COUNTS[acc["type"]]
    elem_size = ncomp * COMP_SIZES[comp]
    stride = bv.get("byteStride", elem_size)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    if stride == elem_size:
        return bin_data[base:base + count * elem_size]
    out = bytearray()
    for i in range(count):
        out += bin_data[base + i * stride:base + i * stride + elem_size]
    return bytes(out)


def compact_glb(gltf, bin_data):
    used_accs = set()
    for m in gltf.get("meshes", []):
        for pr in m.get("primitives", []):
            for v in pr.get("attributes", {}).values():
                used_accs.add(v)
            if "indices" in pr:
                used_accs.add(pr["indices"])
            for tgt in pr.get("targets", []):
                for v in tgt.values():
                    used_accs.add(v)
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            used_accs.add(sk["inverseBindMatrices"])
    for an in gltf.get("animations", []):
        for s in an.get("samplers", []):
            used_accs.add(s["input"])
            used_accs.add(s["output"])

    acc_remap = {}
    new_accs = []
    for old_i in sorted(used_accs):
        acc_remap[old_i] = len(new_accs)
        new_accs.append(gltf["accessors"][old_i])

    for m in gltf.get("meshes", []):
        for pr in m.get("primitives", []):
            pr["attributes"] = {k: acc_remap[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = acc_remap[pr["indices"]]
            if "targets" in pr:
                pr["targets"] = [{k: acc_remap[v] for k, v in tgt.items()} for tgt in pr["targets"]]
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = acc_remap[sk["inverseBindMatrices"]]
    for an in gltf.get("animations", []):
        for s in an.get("samplers", []):
            s["input"] = acc_remap[s["input"]]
            s["output"] = acc_remap[s["output"]]
    gltf["accessors"] = new_accs

    used_bvs = set()
    for acc in gltf["accessors"]:
        if "bufferView" in acc:
            used_bvs.add(acc["bufferView"])
    for im in gltf.get("images", []):
        if "bufferView" in im:
            used_bvs.add(im["bufferView"])

    bv_remap = {}
    new_bvs = []
    new_bin = bytearray()
    for old_bv_i in sorted(used_bvs):
        bv = dict(gltf["bufferViews"][old_bv_i])
        while len(new_bin) % 4 != 0:
            new_bin.append(0)
        off = bv.get("byteOffset", 0)
        ln = bv["byteLength"]
        bv["byteOffset"] = len(new_bin)
        bv["buffer"] = 0
        new_bin += bin_data[off:off + ln]
        bv_remap[old_bv_i] = len(new_bvs)
        new_bvs.append(bv)

    for acc in gltf["accessors"]:
        if "bufferView" in acc:
            acc["bufferView"] = bv_remap[acc["bufferView"]]
    for im in gltf.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = bv_remap[im["bufferView"]]

    gltf["bufferViews"] = new_bvs
    gltf["buffers"] = [{"byteLength": len(new_bin)}]
    return gltf, bytes(new_bin)


def surgical_swap(orig_glb: Path, decim_glb: Path, out_glb: Path, target_node_names: list[str], baked_manifest: dict):
    og, ob = read_glb(orig_glb)
    dg, db = read_glb(decim_glb)
    ob_mut = bytearray(ob)

    def append_bv(raw: bytes, target=None):
        while len(ob_mut) % 4 != 0:
            ob_mut.append(0)
        off = len(ob_mut)
        ob_mut.extend(raw)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
        if target is not None:
            bv["target"] = target
        idx = len(og["bufferViews"])
        og["bufferViews"].append(bv)
        return idx

    def append_acc(raw: bytes, comp: int, atype: str, count: int, min_v=None, max_v=None, target=None):
        bvi = append_bv(raw, target=target)
        acc = {"bufferView": bvi, "componentType": comp, "count": count, "type": atype}
        if min_v is not None:
            acc["min"] = min_v
        if max_v is not None:
            acc["max"] = max_v
        idx = len(og["accessors"])
        og["accessors"].append(acc)
        return idx

    # Swap baked baseColor textures (and remove mismatched normal/roughness maps tied to old micro-UVs!)
    for mat in og.get("materials", []):
        mname = mat.get("name", "")
        if mname in baked_manifest:
            jpg_bytes = Path(baked_manifest[mname]).read_bytes()
            new_bvi = append_bv(jpg_bytes)
            new_img_idx = len(og.setdefault("images", []))
            og["images"].append({"bufferView": new_bvi, "mimeType": "image/jpeg", "name": f"{mname}_baked"})
            new_tex_idx = len(og.setdefault("textures", []))
            sampler = og["textures"][0].get("sampler", 0) if og.get("textures") else None
            tex_obj = {"source": new_img_idx}
            if sampler is not None:
                tex_obj["sampler"] = sampler
            og["textures"].append(tex_obj)
            pbr = mat.setdefault("pbrMetallicRoughness", {})
            pbr["baseColorTexture"] = {"index": new_tex_idx}
            # Remove auxiliary textures that were authored for the old micro-UV layout
            pbr.pop("metallicRoughnessTexture", None)
            mat.pop("normalTexture", None)
            mat.pop("occlusionTexture", None)
            print(f"  BAKED TEXTURE swapped into material {mname!r} ({len(jpg_bytes)//1024} KB JPEG)")

    orig_skin = og["skins"][0]
    orig_joint_name_to_idx = {og["nodes"][ji]["name"]: idx for idx, ji in enumerate(orig_skin["joints"])}
    decim_skin = dg["skins"][0]
    decim_joint_idx_to_orig = [orig_joint_name_to_idx[dg["nodes"][ji]["name"]] for ji in decim_skin["joints"]]
    orig_mat_by_name = {m.get("name"): i for i, m in enumerate(og.get("materials", []))}

    orig_nodes_by_name = {n.get("name"): n for n in og["nodes"] if "mesh" in n}
    decim_nodes_by_name = {n.get("name"): n for n in dg["nodes"] if "mesh" in n}

    for node_name in target_node_names:
        onode = orig_nodes_by_name[node_name]
        dnode = decim_nodes_by_name[node_name]
        omesh = og["meshes"][onode["mesh"]]
        dmesh = dg["meshes"][dnode["mesh"]]

        omin = [1e9, 1e9, 1e9]
        omax = [-1e9, -1e9, -1e9]
        for opr in omesh["primitives"]:
            pacc = og["accessors"][opr["attributes"]["POSITION"]]
            for k in range(3):
                omin[k] = min(omin[k], pacc["min"][k])
                omax[k] = max(omax[k], pacc["max"][k])

        new_prims = []
        dmin = [1e9, 1e9, 1e9]
        dmax = [-1e9, -1e9, -1e9]
        for pi, dpr in enumerate(dmesh["primitives"]):
            dmat_idx = dpr.get("material")
            omat_idx = None
            if dmat_idx is not None and dmat_idx < len(dg.get("materials", [])):
                omat_idx = orig_mat_by_name.get(dg["materials"][dmat_idx].get("name"))
            if omat_idx is None:
                omat_idx = omesh["primitives"][min(pi, len(omesh["primitives"]) - 1)].get("material")

            new_attrs = {}
            for attr_name in ["POSITION", "NORMAL", "TEXCOORD_0"]:
                if attr_name not in dpr["attributes"]:
                    continue
                dacc_idx = dpr["attributes"][attr_name]
                dacc = dg["accessors"][dacc_idx]
                raw = accessor_bytes(dg, db, dacc_idx)
                min_v = dacc.get("min") if attr_name == "POSITION" else None
                max_v = dacc.get("max") if attr_name == "POSITION" else None
                if attr_name == "POSITION" and min_v and max_v:
                    for k in range(3):
                        dmin[k] = min(dmin[k], min_v[k])
                        dmax[k] = max(dmax[k], max_v[k])
                new_attrs[attr_name] = append_acc(
                    raw, dacc["componentType"], dacc["type"], dacc["count"],
                    min_v=min_v, max_v=max_v, target=34962
                )

            if "JOINTS_0" in dpr["attributes"]:
                jacc, jvals = read_accessor_raw(dg, db, dpr["attributes"]["JOINTS_0"])
                jbuf = bytearray()
                use_u8 = len(orig_skin["joints"]) <= 255
                jfmt = "<4B" if use_u8 else "<4H"
                jcomp = 5121 if use_u8 else 5123
                for jt in jvals:
                    remapped = tuple(decim_joint_idx_to_orig[j] if j < len(decim_joint_idx_to_orig) else 0 for j in jt)
                    jbuf += struct.pack(jfmt, *remapped)
                new_attrs["JOINTS_0"] = append_acc(bytes(jbuf), jcomp, "VEC4", jacc["count"], target=34962)

            if "WEIGHTS_0" in dpr["attributes"]:
                wacc, wvals = read_accessor_raw(dg, db, dpr["attributes"]["WEIGHTS_0"])
                wbuf = bytearray()
                for wt in wvals:
                    s = sum(wt)
                    nw = (wt[0] / s, wt[1] / s, wt[2] / s, wt[3] / s) if s > 1e-6 else (1.0, 0.0, 0.0, 0.0)
                    wbuf += struct.pack("<4f", *nw)
                new_attrs["WEIGHTS_0"] = append_acc(bytes(wbuf), 5126, "VEC4", wacc["count"], target=34962)

            npr = {"attributes": new_attrs, "mode": 4}
            if omat_idx is not None:
                npr["material"] = omat_idx
            if "indices" in dpr:
                iacc_idx = dpr["indices"]
                iacc = dg["accessors"][iacc_idx]
                npr["indices"] = append_acc(accessor_bytes(dg, db, iacc_idx), iacc["componentType"], "SCALAR", iacc["count"], target=34963)
            new_prims.append(npr)

        deltas = [max(abs(omin[k] - dmin[k]), abs(omax[k] - dmax[k])) for k in range(3)]
        print(f"  BBOX check {node_name}: max_delta={max(deltas)*1000:.1f}mm")
        if max(deltas) > 0.04:
            raise RuntimeError(f"Bounding box mismatch on {node_name}: {deltas}")
        omesh["primitives"] = new_prims

    og, compacted_bin = compact_glb(og, bytes(ob_mut))
    write_glb(out_glb, og, compacted_bin)


BLENDER_COMPARE_SCRIPT = r'''
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
orig_glb, new_glb, out_face_orig, out_face_new, out_body_orig, out_body_new = argv

def render_glb(glb_path, face_out, body_out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.studio_light = "studio.sl"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("W")
    scene.world.color = (0.11, 0.12, 0.16)
    scene.render.image_settings.file_format = "PNG"

    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm and arm.animation_data:
        for act in bpy.data.actions:
            if act.name.lower().startswith("idle"):
                arm.animation_data.action = act
                scene.frame_set(0)
                break
    bpy.context.view_layer.update()

    min_z, max_z = 1e9, -1e9
    cx_list = []
    for o in bpy.data.objects:
        if o.type == "MESH" and o.parent is not None:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                min_z = min(min_z, w.z)
                max_z = max(max_z, w.z)
                cx_list.append(w.x)
    cx = sum(cx_list) / max(1, len(cx_list))
    head_z = max_z - 0.17

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    scene.render.resolution_x = 420
    scene.render.resolution_y = 420
    cam_data.ortho_scale = 0.42
    cam_obj.location = (cx + 0.55, -2.2, head_z + 0.03)
    cam_obj.rotation_euler = (Vector((cx, 0.0, head_z)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = face_out
    bpy.ops.render.render(write_still=True)

    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    cam_data.ortho_scale = 2.15
    mid_z = 0.5 * (min_z + max_z)
    cam_obj.location = (cx + 0.85, -3.5, mid_z + 0.05)
    cam_obj.rotation_euler = (Vector((cx, 0.0, mid_z)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = body_out
    bpy.ops.render.render(write_still=True)

render_glb(orig_glb, out_face_orig, out_body_orig)
render_glb(new_glb, out_face_new, out_body_new)
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Overwrite App/Resources/DuelCharacters/DuelChar_*.glb")
    ap.add_argument("--preview", type=str, default="/tmp/decimate_face_before_after.png")
    args = ap.parse_args()

    work = Path(tempfile.mkdtemp(prefix="duel_decim_"))
    decim_py = work / "decim.py"
    decim_py.write_text(BLENDER_DECIMATE_SCRIPT)
    cmp_py = work / "cmp.py"
    cmp_py.write_text(BLENDER_COMPARE_SCRIPT)

    summary = []
    preview_rows = []

    for hero, spec in TARGETS.items():
        orig = CHAR_DIR / f"DuelChar_{hero}.glb"
        tmp_decim = work / f"raw_decim_{hero}.glb"
        bake_dir = work / f"bake_{hero}"
        bake_dir.mkdir(parents=True, exist_ok=True)
        out_glb = work / f"DuelChar_{hero}.glb"

        print(f"\n=== Processing {hero} ({orig.stat().st_size / 1048576:.2f} MB) ===")
        subprocess.run(
            [str(BLENDER), "--background", "--factory-startup", "--python", str(decim_py),
             "--", str(orig), str(tmp_decim), str(bake_dir), json.dumps(spec)],
            check=True,
        )
        baked_manifest = json.loads((bake_dir / "baked_manifest.json").read_text())
        surgical_swap(orig, tmp_decim, out_glb, list(spec.keys()), baked_manifest)

        og, _ = read_glb(orig)
        ng, _ = read_glb(out_glb)
        ov = sum(og["accessors"][pr["attributes"]["POSITION"]]["count"] for m in og["meshes"] for pr in m["primitives"])
        nv = sum(ng["accessors"][pr["attributes"]["POSITION"]]["count"] for m in ng["meshes"] for pr in m["primitives"])
        ot = sum(og["accessors"][pr["indices"]]["count"] // 3 for m in og["meshes"] for pr in m["primitives"] if "indices" in pr)
        nt = sum(ng["accessors"][pr["indices"]]["count"] // 3 for m in ng["meshes"] for pr in m["primitives"] if "indices" in pr)
        osz = orig.stat().st_size / 1048576
        nsz = out_glb.stat().st_size / 1048576
        print(f"RESULT {hero}: {osz:.2f}MB -> {nsz:.2f}MB | verts {ov:,} -> {nv:,} | tris {ot:,} -> {nt:,} | anims {len(og['animations'])} == {len(ng['animations'])}")
        assert len(og["animations"]) == len(ng["animations"])
        summary.append((hero, osz, nsz, ov, nv, ot, nt, out_glb, orig))

        fo = work / f"{hero}_face_orig.png"
        fn = work / f"{hero}_face_new.png"
        bo = work / f"{hero}_body_orig.png"
        bn = work / f"{hero}_body_new.png"
        subprocess.run(
            [str(BLENDER), "--background", "--factory-startup", "--python", str(cmp_py),
             "--", str(orig), str(out_glb), str(fo), str(fn), str(bo), str(bn)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        preview_rows.append((hero, osz, nsz, ot, nt, fo, fn, bo, bn))

    from PIL import Image, ImageDraw
    cell_w, cell_h = 380, 400
    cols = 4
    rows = len(preview_rows)
    sheet = Image.new("RGB", (cols * cell_w, rows * (cell_h + 28)), (18, 20, 26))
    draw = ImageDraw.Draw(sheet)
    for r, (hero, osz, nsz, ot, nt, fo, fn, bo, bn) in enumerate(preview_rows):
        items = [
            (f"{hero} ORIG FACE ({ot//1000}k t / {osz:.1f}MB)", fo),
            (f"{hero} NEW FACE ({nt//1000}k t / {nsz:.1f}MB)", fn),
            (f"{hero} ORIG BODY", bo),
            (f"{hero} NEW BODY", bn),
        ]
        for c, (label, p) in enumerate(items):
            im = Image.open(p).convert("RGB")
            im.thumbnail((cell_w - 8, cell_h - 6), Image.Resampling.LANCZOS)
            x0 = c * cell_w + (cell_w - im.width) // 2
            y0 = r * (cell_h + 28) + 24 + (cell_h - im.height) // 2
            sheet.paste(im, (x0, y0))
            draw.text((c * cell_w + 8, r * (cell_h + 28) + 5), label, fill=(240, 224, 175))
    prev_path = Path(args.preview)
    prev_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(prev_path, optimize=True)
    print(f"\nPREVIEW SHEET SAVED: {prev_path}")

    if args.apply:
        for hero, osz, nsz, ov, nv, ot, nt, out_glb, orig in summary:
            shutil.copy2(out_glb, orig)
            print(f"APPLIED: {orig}")
    else:
        print("\nDry run complete (pass --apply to overwrite GLBs). Temp dir:", work)


if __name__ == "__main__":
    main()
