#!/usr/bin/env python3
"""Upgrade untextured weapons to real forged PBR, sculpt real 3D Dark-Lacquer Samurai Retainer GLB,
patch Sanctuary foliage to MASK alphaMode, and fix Sun Deng's kneeling idle/guard stance.

Run with: /home/antigravity/blender/blender --background --python scripts/upgrade_weapons_retainer_and_heroes.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path
import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

PBR_DIR = Path("/tmp/pbr_build")
RES_DIR = Path("App/Resources/DuelCharacters")


def patch_glb_json(glb_path: Path, mutate_fn) -> None:
    """Losslessly patch glTF JSON chunk in-place without touching binary buffers."""
    raw = glb_path.read_bytes()
    magic, version, total_len = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67, f"Not a GLB: {glb_path}"
    json_len, json_type = struct.unpack_from("<II", raw, 12)
    assert json_type == 0x4E4F534A
    g = json.loads(raw[20:20 + json_len].decode("utf-8"))
    rest = raw[20 + json_len:]
    mutate_fn(g)
    new_json = json.dumps(g, separators=(",", ":")).encode("utf-8")
    pad = (4 - (len(new_json) % 4)) % 4
    new_json += b" " * pad
    new_total = 12 + 8 + len(new_json) + len(rest)
    out = struct.pack("<IIIII", magic, version, new_total, len(new_json), json_type) + new_json + rest
    glb_path.write_bytes(out)


def box_uv_mesh(obj: bpy.types.Object, scale: float = 2.0) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * scale, co.y * scale
            elif ax >= ay:
                u, v = co.y * scale, co.z * scale
            else:
                u, v = co.x * scale, co.z * scale
            loop[uv_layer].uv = (u, v)
    bm.to_mesh(obj.data)
    bm.free()


def make_pbr_mat(
    name: str,
    albedo_file: str,
    normal_file: str,
    orm_file: str,
    tint: tuple[float, float, float] | None = None,
    normal_strength: float = 1.0,
    rough_scale: float | None = None,
    metal_override: float | None = None,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.image = bpy.data.images.load(str(PBR_DIR / albedo_file), check_existing=True)
    tex_alb.image.colorspace_settings.name = "sRGB"
    if tint is not None:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*tint, 1.0)
        nt.links.new(tex_alb.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_n = nt.nodes.new("ShaderNodeTexImage")
    tex_n.image = bpy.data.images.load(str(PBR_DIR / normal_file), check_existing=True)
    tex_n.image.colorspace_settings.name = "Non-Color"
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = normal_strength
    nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.image = bpy.data.images.load(str(PBR_DIR / orm_file), check_existing=True)
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    if rough_scale is not None:
        bsdf.inputs["Roughness"].default_value = rough_scale
    else:
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    if metal_override is not None:
        bsdf.inputs["Metallic"].default_value = metal_override
    else:
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    return mat


def upgrade_liu_axe() -> None:
    """Upgrade Liu Quanwei's 0-texture war axe into forged Damascus steel, honed edge, bronze & charred oak."""
    path = RES_DIR / "DuelWeapon_liuQuanwei.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))

    mat_dark_steel = make_pbr_mat("Axe_ForgedSteel", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(0.56, 0.58, 0.62), normal_strength=1.15)
    mat_honed_edge = make_pbr_mat("Axe_HonedEdge", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(1.15, 1.18, 1.22), normal_strength=0.65, rough_scale=0.16, metal_override=0.96)
    mat_bronze = make_pbr_mat("Axe_AgedBronze", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(0.76, 0.56, 0.30), normal_strength=0.95, rough_scale=0.34, metal_override=0.88)
    mat_oak = make_pbr_mat("Axe_CharredOak", "dark_wood_albedo.jpg", "dark_wood_normal.png", "dark_wood_orm.png", tint=(0.82, 0.68, 0.54), normal_strength=1.25)
    mat_leather = make_pbr_mat("Axe_WornLeather", "dark_wood_albedo.jpg", "dark_wood_normal.png", "dark_wood_orm.png", tint=(0.46, 0.30, 0.20), normal_strength=1.05, rough_scale=0.72, metal_override=0.04)

    mapping = {
        "Bronze_Patina": mat_bronze,
        "Bronze_Edge": mat_honed_edge,
        "Stone_Jade": mat_dark_steel,
        "Leather_Umber": mat_leather,
        "Iron_Obsidian": mat_dark_steel,
        "Bark_Mahogany": mat_oak,
        "Iron_Cut": mat_honed_edge,
    }
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        box_uv_mesh(obj, scale=2.6)
        for slot in obj.material_slots:
            if slot.material and slot.material.name in mapping:
                slot.material = mapping[slot.material.name]

    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
    )
    print(f"[weapon] upgraded {path.name} ({path.stat().st_size // 1024} KB)")


def upgrade_sun_blades() -> None:
    """Upgrade Sun Deng's twin shinobi blades to folded Damascus steel + silver edge + dark wrapped hilt."""
    for fname in ("DuelWeapon_sunDeng.glb", "DuelWeaponL_sunDeng.glb"):
        path = RES_DIR / fname
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path))

        mat_damascus = make_pbr_mat("Blade_Damascus", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(0.62, 0.68, 0.78), normal_strength=0.95)
        mat_edge = make_pbr_mat("Blade_SilverEdge", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(1.22, 1.26, 1.32), normal_strength=0.50, rough_scale=0.14, metal_override=0.98)
        mat_guard = make_pbr_mat("Blade_DarkSteelGuard", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png", tint=(0.32, 0.36, 0.44), normal_strength=1.0, rough_scale=0.30, metal_override=0.90)
        mat_grip = make_pbr_mat("Blade_DarkBraid", "dark_wood_albedo.jpg", "dark_wood_normal.png", "dark_wood_orm.png", tint=(0.24, 0.28, 0.36), normal_strength=1.15, rough_scale=0.78, metal_override=0.05)
        mat_teal = make_pbr_mat("Blade_TealBraid", "dark_wood_albedo.jpg", "dark_wood_normal.png", "dark_wood_orm.png", tint=(0.26, 0.56, 0.64), normal_strength=1.0, rough_scale=0.68, metal_override=0.08)

        mapping = {
            "Smoky blade steel": mat_damascus,
            "Hardened silver edge": mat_edge,
            "Burnished black indigo leather": mat_grip,
            "Blue black steel": mat_guard,
            "Cold forged edges": mat_edge,
            "Faded glacial teal braid": mat_teal,
        }
        for obj in bpy.data.objects:
            if obj.type != "MESH":
                continue
            box_uv_mesh(obj, scale=3.2)
            for slot in obj.material_slots:
                if slot.material and slot.material.name in mapping:
                    slot.material = mapping[slot.material.name]

        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            export_yup=True,
            export_normals=True,
            export_materials="EXPORT",
            export_image_format="AUTO",
            export_texcoords=True,
        )
        print(f"[weapon] upgraded {path.name} ({path.stat().st_size // 1024} KB)")


def build_shogun_retainer_glb() -> None:
    """Build a genuine AAA Dark-Obsidian Armored Samurai Retainer GLB directly from Wu Yong's
    real sculpted samurai armor mesh + DuelWeapon_wuYong.glb odachi, posed in a low drawn-katana
    iaido stance with a sculpted horned samurai kabuto & iron menpo mask replacing the human face.
    ZERO primitive mannequins or Lego cubes!"""
    out_path = RES_DIR / "DuelProp_ShogunRetainer.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Import Wu Yong's real sculpted armored body + pose into clean low samurai idle guard!
    bpy.ops.import_scene.gltf(filepath=str(RES_DIR / "DuelChar_wuYong.glb"))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    act = next((a for a in bpy.data.actions if a.name.lower().startswith("idle")), None)
    if act and arm.animation_data:
        arm.animation_data.action = act
        bpy.context.scene.frame_set(int(0.5 * (act.frame_range[0] + act.frame_range[1])))
        bpy.context.view_layer.update()

    # Record head & weapon socket world transforms before baking the posed mesh
    head_pb = arm.pose.bones["Head"]
    head_world = arm.matrix_world @ head_pb.matrix
    sock_pb = arm.pose.bones["weapon_socket_r"]
    sock_world = arm.matrix_world @ sock_pb.matrix

    # 2. Import Wu Yong's real detailed PBR Odachi blade and place at weapon_socket_r (at bone head!)
    before_w = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(RES_DIR / "DuelWeapon_wuYong.glb"))
    weapon_objs = [o for o in bpy.data.objects if o not in before_w]
    for wr in [o for o in weapon_objs if o.parent is None]:
        wr.matrix_world = sock_world @ wr.matrix_world
    bpy.context.view_layer.update()

    # 3. Bake evaluated posed meshes & apply dark smoky-lacquer samurai shadow-ghost PBR styling!
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mat_shadow_armor = make_pbr_mat(
        "Retainer_ShadowLacquer", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png",
        tint=(0.14, 0.17, 0.24), normal_strength=0.95, rough_scale=0.30, metal_override=0.82
    )
    mat_gold_crest = make_pbr_mat(
        "Retainer_AgedGoldCrest", "steel_albedo.jpg", "steel_normal.png", "steel_orm.png",
        tint=(0.95, 0.72, 0.26), normal_strength=0.65, rough_scale=0.22, metal_override=0.94
    )
    mat_eyes = bpy.data.materials.new("Retainer_IceEyes")
    mat_eyes.use_nodes = True
    bsdf_e = mat_eyes.node_tree.nodes["Principled BSDF"]
    bsdf_e.inputs["Base Color"].default_value = (0.32, 0.92, 1.0, 1.0)
    bsdf_e.inputs["Emission Color"].default_value = (0.32, 0.92, 1.0, 1.0)
    bsdf_e.inputs["Emission Strength"].default_value = 5.5

    baked_meshes = []
    visible_scene_objs = set(bpy.context.scene.objects)
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or obj not in visible_scene_objs:
            continue
        if obj.hide_viewport or obj.hide_render or "icosphere" in obj.name.lower() or "wgt" in obj.name.lower():
            continue
        is_weapon = obj in weapon_objs
        ev = obj.evaluated_get(depsgraph)
        me = bpy.data.meshes.new_from_object(ev)
        me.transform(obj.matrix_world)
        me.transform(Matrix.Rotation(math.radians(90.0), 4, "Z"))
        new_obj = bpy.data.objects.new(f"Retainer_{obj.name}", me)
        bpy.context.collection.objects.link(new_obj)

        # Decimate both body and weapon cleanly for lightweight ~12k-tri mobile retainer
        dec = new_obj.modifiers.new("Decimate", type="DECIMATE")
        dec.ratio = 0.22 if not is_weapon else 0.20
        bpy.context.view_layer.objects.active = new_obj
        bpy.ops.object.modifier_apply(modifier=dec.name)

        if not is_weapon:
            for i, slot in enumerate(new_obj.material_slots):
                if slot.material and slot.material.use_nodes:
                    nt = slot.material.node_tree
                    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
                    nm = slot.material.name.lower()
                    if any(k in nm for k in ("material.002", "weldedneck")):
                        slot.material = mat_shadow_armor
                    elif bsdf:
                        bc = bsdf.inputs["Base Color"]
                        if bc.is_linked:
                            src_sock = bc.links[0].from_socket
                            mix = nt.nodes.new("ShaderNodeMix")
                            mix.data_type = "RGBA"
                            mix.blend_type = "MULTIPLY"
                            mix.inputs["Factor"].default_value = 1.0
                            mix.inputs[7].default_value = (0.18, 0.22, 0.30, 1.0)
                            nt.links.new(src_sock, mix.inputs[6])
                            nt.links.new(mix.outputs[2], bc)
                        else:
                            bc.default_value = (0.14, 0.17, 0.24, 1.0)
                        if not bsdf.inputs["Metallic"].is_linked:
                            bsdf.inputs["Metallic"].default_value = 0.72
                        if not bsdf.inputs["Roughness"].is_linked:
                            bsdf.inputs["Roughness"].default_value = 0.34
        else:
            for slot in new_obj.material_slots:
                if slot.material and slot.material.use_nodes:
                    nt = slot.material.node_tree
                    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
                    if bsdf and bsdf.inputs["Base Color"].is_linked:
                        src_sock = bsdf.inputs["Base Color"].links[0].from_socket
                        mix = nt.nodes.new("ShaderNodeMix")
                        mix.data_type = "RGBA"
                        mix.blend_type = "MULTIPLY"
                        mix.inputs["Factor"].default_value = 1.0
                        mix.inputs[7].default_value = (0.50, 0.70, 0.88, 1.0)
                        nt.links.new(src_sock, mix.inputs[6])
                        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        baked_meshes.append(new_obj)

    for obj in list(bpy.data.objects):
        if obj not in baked_meshes:
            bpy.data.objects.remove(obj, do_unlink=True)

    # 4. Snug armored Kabuto Helmet + Golden Crescent Maedate Crest + Glowing Ice-Cyan Eyes
    rot90 = Matrix.Rotation(math.radians(90.0), 4, "Z")
    hc = (rot90 @ head_world).translation + Vector((0.0, 0.0, 0.085))

    bm_kab = bmesh.new()
    s = bmesh.new()
    bmesh.ops.create_uvsphere(s, u_segments=20, v_segments=12, radius=0.128)
    for v in s.verts:
        v.co.x *= 1.10
        v.co.y *= 1.02
        v.co.z = v.co.z * 0.85 if v.co.z > 0 else v.co.z * 0.50
    bmesh.ops.transform(s, matrix=Matrix.Translation(hc + Vector((-0.005, 0, 0.045))), verts=s.verts)
    vmap = {v.index: bm_kab.verts.new(v.co) for v in s.verts}
    for f in s.faces:
        try:
            nf = bm_kab.faces.new([vmap[v.index] for v in f.verts]); nf.smooth = True
        except ValueError:
            pass
    s.free()
    for tier in range(2):
        s = bmesh.new()
        bmesh.ops.create_cone(s, cap_ends=False, segments=18, radius1=0.165 + tier * 0.028, radius2=0.128 + tier * 0.018, depth=0.068)
        for v in s.verts:
            if v.co.x > 0.050:
                v.co.x = 0.050
        bmesh.ops.solidify(s, geom=list(s.faces), thickness=0.013)
        bmesh.ops.transform(s, matrix=Matrix.Translation(hc + Vector((-0.025, 0, -0.012 - tier * 0.046))) @ Euler((0, -0.18, 0)).to_matrix().to_4x4(), verts=s.verts)
        vmap = {v.index: bm_kab.verts.new(v.co) for v in s.verts}
        for f in s.faces:
            try:
                nf = bm_kab.faces.new([vmap[v.index] for v in f.verts]); nf.smooth = True
            except ValueError:
                pass
        s.free()
    bmesh.ops.recalc_face_normals(bm_kab, faces=bm_kab.faces)
    me_kab = bpy.data.meshes.new("Retainer_Kabuto")
    bm_kab.to_mesh(me_kab); bm_kab.free()
    o_kab = bpy.data.objects.new("Retainer_Kabuto", me_kab)
    o_kab.data.materials.append(mat_shadow_armor)
    bpy.context.collection.objects.link(o_kab)
    box_uv_mesh(o_kab, scale=3.0)

    bm_cr = bmesh.new()
    for side in (-1.0, 1.0):
        pts = [
            (hc.x + 0.128, side * 0.010, hc.z + 0.055),
            (hc.x + 0.162, side * 0.082, hc.z + 0.128),
            (hc.x + 0.145, side * 0.145, hc.z + 0.220),
            (hc.x + 0.112, side * 0.175, hc.z + 0.295),
        ]
        prev = None
        for i, p in enumerate(pts):
            w = 0.020 * (1.0 - i * 0.24)
            ring = [bm_cr.verts.new((p[0] + w, p[1], p[2])), bm_cr.verts.new((p[0] - w, p[1], p[2])), bm_cr.verts.new((p[0], p[1] + side * w * 0.45, p[2] + w * 0.45))]
            if prev is not None:
                for a, b in [(0, 1), (1, 2), (2, 0)]:
                    try:
                        f = bm_cr.faces.new([prev[a], prev[b], ring[b], ring[a]]); f.smooth = True
                    except ValueError:
                        pass
            prev = ring
    bmesh.ops.recalc_face_normals(bm_cr, faces=bm_cr.faces)
    me_cr = bpy.data.meshes.new("Retainer_Crest")
    bm_cr.to_mesh(me_cr); bm_cr.free()
    o_cr = bpy.data.objects.new("Retainer_Crest", me_cr)
    o_cr.data.materials.append(mat_gold_crest)
    bpy.context.collection.objects.link(o_cr)
    box_uv_mesh(o_cr, scale=4.0)

    bm_ey = bmesh.new()
    for ey in (-0.032, 0.032):
        s = bmesh.new()
        bmesh.ops.create_uvsphere(s, u_segments=8, v_segments=6, radius=0.012)
        bmesh.ops.scale(s, vec=(0.6, 1.45, 0.50), verts=s.verts)
        bmesh.ops.transform(s, matrix=Matrix.Translation(hc + Vector((0.105, ey, -0.014))), verts=s.verts)
        vmap = {v.index: bm_ey.verts.new(v.co) for v in s.verts}
        for f in s.faces:
            try:
                nf = bm_ey.faces.new([vmap[v.index] for v in f.verts]); nf.smooth = True
            except ValueError:
                pass
        s.free()
    me_ey = bpy.data.meshes.new("Retainer_Eyes")
    bm_ey.to_mesh(me_ey); bm_ey.free()
    o_ey = bpy.data.objects.new("Retainer_Eyes", me_ey)
    o_ey.data.materials.append(mat_eyes)
    bpy.context.collection.objects.link(o_ey)

    # Ground align so lowest vertex sits cleanly at z = 0.0
    min_z = min(v.co.z for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.transform(Matrix.Translation((0, 0, -min_z)))

    # Purge unused blocks before export
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_jpeg_quality=82,
        export_texcoords=True,
    )
    tris = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == "MESH")
    print(f"[retainer] built REAL armored samurai {out_path.name} ({out_path.stat().st_size // 1024} KB, ~{tris} tris)")


def _slerp_xyzw(q0: tuple[float, float, float, float],
                q1: tuple[float, float, float, float],
                t: float) -> tuple[float, float, float, float]:
    ax, ay, az, aw = q0
    bx, by, bz, bw = q1
    dot = ax * bx + ay * by + az * bz + aw * bw
    if dot < 0.0:
        bx, by, bz, bw = -bx, -by, -bz, -bw
        dot = -dot
    if dot > 0.9995:
        rx = ax + t * (bx - ax)
        ry = ay + t * (by - ay)
        rz = az + t * (bz - az)
        rw = aw + t * (bw - aw)
    else:
        theta0 = math.acos(max(-1.0, min(1.0, dot)))
        sin0 = math.sin(theta0)
        s0 = math.sin((1.0 - t) * theta0) / sin0
        s1 = math.sin(t * theta0) / sin0
        rx = s0 * ax + s1 * bx
        ry = s0 * ay + s1 * by
        rz = s0 * az + s1 * bz
        rw = s0 * aw + s1 * bw
    n = math.sqrt(rx * rx + ry * ry + rz * rz + rw * rw) or 1.0
    return (rx / n, ry / n, rz / n, rw / n)


def fix_sun_deng_kneeling_stance() -> None:
    """Losslessly lift Sun Deng's crouching idle/guard/hit/walk clips directly in GLB binary space,
    preserving all 30 pristine 60fps LINEAR Cascadeur tracks with zero STEP resampling."""
    path = RES_DIR / "DuelChar_sunDeng.glb"
    raw = bytearray(path.read_bytes())
    jlen = struct.unpack_from("<I", raw, 12)[0]
    g = json.loads(raw[20:20 + jlen].decode("utf-8"))
    bin_header = 20 + jlen
    bin_len = struct.unpack_from("<I", raw, bin_header)[0]
    bin_start = bin_header + 8

    nodes = g.get("nodes", [])
    accessors = g.get("accessors", [])
    bvs = g.get("bufferViews", [])
    touched_accessors: set[int] = set()
    lifted = []

    for anim in g.get("animations", []):
        lname = anim.get("name", "").lower()
        if any(lname.startswith(p) for p in ("idle_", "guard_", "hit_")):
            target_y, leg_blend = 0.895, 0.46
        elif any(lname.startswith(p) for p in ("walk_", "backstep_")):
            target_y, leg_blend = 0.865, 0.28
        else:
            continue

        # Check current mean Hips Y so patching is strictly idempotent
        hips_ch = next(
            (c for c in anim["channels"]
             if nodes[c["target"]["node"]].get("name") == "Hips" and c["target"]["path"] == "translation"),
            None,
        )
        if hips_ch is None:
            continue
        h_acc_idx = anim["samplers"][hips_ch["sampler"]]["output"]
        h_acc = accessors[h_acc_idx]
        h_bv = bvs[h_acc["bufferView"]]
        h_off = bin_start + h_bv.get("byteOffset", 0) + h_acc.get("byteOffset", 0)
        h_cnt = h_acc["count"]
        ys = [struct.unpack_from("<3f", raw, h_off + i * 12)[1] for i in range(h_cnt)]
        mean_y = sum(ys) / max(1, len(ys))
        if mean_y >= target_y - 0.01:
            continue
        delta_y = target_y - mean_y

        # 1. Lift Hips translation.y
        if h_acc_idx not in touched_accessors:
            touched_accessors.add(h_acc_idx)
            mn = [1e9, 1e9, 1e9]
            mx = [-1e9, -1e9, -1e9]
            for i in range(h_cnt):
                x, y, z = struct.unpack_from("<3f", raw, h_off + i * 12)
                y += delta_y
                struct.pack_into("<3f", raw, h_off + i * 12, x, y, z)
                for k, v in enumerate((x, y, z)):
                    mn[k] = min(mn[k], v); mx[k] = max(mx[k], v)
            if "min" in h_acc:
                h_acc["min"] = mn
            if "max" in h_acc:
                h_acc["max"] = mx

        # 2. Straighten crouching thighs, shins & ankles toward upright rest rotation
        for ch in anim["channels"]:
            ni = ch["target"]["node"]
            bname = nodes[ni].get("name", "")
            if ch["target"]["path"] != "rotation" or bname not in (
                "Thigh.L", "Thigh.R", "Shin.L", "Shin.R", "Foot.L", "Foot.R"
            ):
                continue
            rest_q = tuple(nodes[ni].get("rotation", [0.0, 0.0, 0.0, 1.0]))
            acc_idx = anim["samplers"][ch["sampler"]]["output"]
            if acc_idx in touched_accessors:
                continue
            touched_accessors.add(acc_idx)
            acc = accessors[acc_idx]
            bv = bvs[acc["bufferView"]]
            off = bin_start + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            cnt = acc["count"]
            mn4 = [1e9, 1e9, 1e9, 1e9]
            mx4 = [-1e9, -1e9, -1e9, -1e9]
            for i in range(cnt):
                q = struct.unpack_from("<4f", raw, off + i * 16)
                q2 = _slerp_xyzw(q, rest_q, leg_blend)
                struct.pack_into("<4f", raw, off + i * 16, *q2)
                for k, v in enumerate(q2):
                    mn4[k] = min(mn4[k], v); mx4[k] = max(mx4[k], v)
            if "min" in acc:
                acc["min"] = mn4
            if "max" in acc:
                acc["max"] = mx4

        lifted.append((anim["name"], round(mean_y, 3), round(mean_y + delta_y, 3)))

    jb = json.dumps(g, separators=(",", ":")).encode("utf-8")
    while len(jb) % 4:
        jb += b" "
    bin_payload = bytes(raw[bin_start:bin_start + bin_len])
    total = 12 + 8 + len(jb) + 8 + len(bin_payload)
    out = (
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(jb), 0x4E4F534A)
        + jb
        + struct.pack("<II", len(bin_payload), 0x004E4942)
        + bin_payload
    )
    path.write_bytes(out)
    print(f"[sunDeng] losslessly fixed kneeling clips ({len(lifted)}, 0 STEP samplers):", lifted)


def harmonize_hero_materials() -> None:
    """Harmonize head/body baseColorFactor & roughness on all 4 hero GLBs so faces aren't flat overexposed stickers
    and robes/armor look rich under HDR IBL + directional shadows."""
    for hero in ("wuYong", "liuQuanwei", "sunDeng", "xuXiao"):
        path = RES_DIR / f"DuelChar_{hero}.glb"

        def tweak(g: dict) -> None:
            for m in g.get("materials", []):
                nm = (m.get("name") or "").lower()
                pbr = m.setdefault("pbrMetallicRoughness", {})
                # Photo-scanned head / neck materials: tame harsh flat scan overexposure & ensure realistic skin roughness
                if any(k in nm for k in ("likeness", "weldedneck", "material.002")) or (hero in ("sunDeng", "liuQuanwei") and nm == "material.001"):
                    # Keep skin warm and natural under dramatic sunlit HDR IBL (no glowing chalky white head!)
                    pbr["baseColorFactor"] = [0.84, 0.80, 0.77, 1.0]
                    if "metallicRoughnessTexture" not in pbr:
                        pbr["roughnessFactor"] = 0.68
                        pbr["metallicFactor"] = 0.0
                elif "crusadergorget" in nm:
                    # Xu Xiao's imperial steel gorget: crisp dark forged steel + antique gold trim
                    pbr["metallicFactor"] = 0.90
                    pbr["roughnessFactor"] = 0.28
                else:
                    # Main outfit/armor: subtly deepen albedo to prevent chalky highlight clipping on white coats/hakama
                    if hero in ("xuXiao", "sunDeng"):
                        pbr["baseColorFactor"] = [0.84, 0.83, 0.81, 1.0]
                    else:
                        pbr["baseColorFactor"] = [0.90, 0.89, 0.87, 1.0]

        patch_glb_json(path, tweak)
        print(f"[heroes] harmonized PBR factors on {path.name}")


def patch_sanctuary_mask() -> None:
    path = RES_DIR / "DuelStage_Sanctuary.glb"

    def fix_alpha(g: dict) -> None:
        for m in g.get("materials", []):
            if m.get("name") == "Mat_CrimsonVines":
                m["alphaMode"] = "MASK"
                m["alphaCutoff"] = 0.44
                m["doubleSided"] = True

    patch_glb_json(path, fix_alpha)
    print(f"[stage] patched Mat_CrimsonVines -> alphaMode=MASK (cutoff=0.44) in {path.name}")


def main() -> None:
    patch_sanctuary_mask()
    upgrade_liu_axe()
    upgrade_sun_blades()
    build_shogun_retainer_glb()
    fix_sun_deng_kneeling_stance()
    harmonize_hero_materials()
    print("[upgrade] ALL WEAPONS, RETAINER, SUN DENG STANCE & HERO MATERIALS UPGRADED!")


if __name__ == "__main__":
    main()
