#!/usr/bin/env python3
"""AAA 3D Hero Rescue:
1. Eliminate exploding back-cape / floral cloak spikes (re-weight back-cloak verts strictly to Chest/Spine/Cape/CapeTip).
2. Refit UpperArm / Forearm / Hand / weapon_socket bones cleanly INTO each hero's real rest-pose arms (fixing Wu Yong,
   Liu Quanwei's 52cm floating arm bug, and Sun Deng's hollow right sleeve).
3. Sculpt & attach anatomical 3D gripping hands / armored gauntlets (forearm bracer + contoured palm + 4 curled wrapping
   fingers + opposable thumb) locked 100% to Hand.R / Hand.L so EVERY hero visibly grips their weapon hilt at 0.0 cm gap!
4. Eliminate "paper cutout" flatness: wire Sobel Normal + Roughness/Metallic/AO maps onto Liu Quanwei's body, restore
   accidentally whitened dark linings/gloves on Wu Yong & Sun Deng, and raise sculptural normal relief on all 4 heroes.
5. Align all 4 DuelChar_*.json weapon manifests to [0,0,0] palm-centered grip + forward-cutting blade edge.
6. Sculpt real 3D PBR Flame-Spirit Wolf (DuelProp_SpiritWolf.glb) & Flame-Spirit Owl (DuelProp_SpiritOwl.glb) for Nonna.

Run with:
    python3 scripts/prep_hero_pbr_maps.py && /home/antigravity/blender/blender -b --factory-startup --python scripts/fix_hero_hands_grips_and_pbr.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

REPO = Path(__file__).resolve().parents[1]
RES_DIR = REPO / "App/Resources/DuelCharacters"
PBR_DIR = Path("/tmp/hero_pbr")

ARM_BONES_ALL = {
    "UpperArm.L", "Forearm.L", "Hand.L",
    "UpperArm.R", "Forearm.R", "Hand.R",
}
ARM_BONES_R = {"UpperArm.R", "Forearm.R", "Hand.R"}
ARM_BONES_L = {"UpperArm.L", "Forearm.L", "Hand.L"}


# ------------------------------------------------------------------ Helpers
def make_pbr_mat(
    name: str,
    prefix: str | None = None,
    tint: tuple[float, float, float] = (0.5, 0.5, 0.5),
    roughness: float = 0.45,
    metallic: float = 0.0,
    normal_strength: float = 1.0,
    emission: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    alb_path = (PBR_DIR / f"{prefix}_albedo.jpg") if prefix else None
    if prefix and alb_path and alb_path.exists():
        tex_a = nt.nodes.new("ShaderNodeTexImage")
        tex_a.image = bpy.data.images.load(str(alb_path), check_existing=True)
        tex_a.image.colorspace_settings.name = "sRGB"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*tint, 1.0)
        nt.links.new(tex_a.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])

        norm_path = PBR_DIR / f"{prefix}_normal.png"
        if norm_path.exists():
            tex_n = nt.nodes.new("ShaderNodeTexImage")
            tex_n.image = bpy.data.images.load(str(norm_path), check_existing=True)
            tex_n.image.colorspace_settings.name = "Non-Color"
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.inputs["Strength"].default_value = normal_strength
            nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    else:
        bsdf.inputs["Base Color"].default_value = (*tint, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    return mat


def box_uv(obj: bpy.types.Object, scale: float = 4.0) -> None:
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


def ensure_vg(obj: bpy.types.Object, name: str):
    vg = obj.vertex_groups.get(name)
    return vg if vg is not None else obj.vertex_groups.new(name=name)


def clear_all_pose_transforms(arm: bpy.types.Object) -> None:
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def set_vert_weights(obj: bpy.types.Object, v_idx: int, weights: dict[str, float]) -> None:
    """Replace all vertex group memberships for vertex `v_idx` with normalized `weights`."""
    total = sum(w for w in weights.values() if w > 1e-5)
    if total <= 1e-6:
        return
    for vg in obj.vertex_groups:
        vg.remove([v_idx])
    for name, w in weights.items():
        if w > 1e-5:
            ensure_vg(obj, name).add([v_idx], w / total, "REPLACE")


def project_seg(p: Vector, a: Vector, b: Vector) -> tuple[float, float]:
    """Return (t_clamped_0_1, distance_to_segment) for point p to segment a->b."""
    ab = b - a
    l2 = ab.length_squared
    if l2 < 1e-8:
        return 0.0, (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / l2))
    closest = a + ab * t
    return t, (p - closest).length


# ------------------------------------------------------------------ Sculpted Anatomical Gripping Hand / Gauntlet
def build_sculpted_gripping_hand(
    name: str,
    arm: bpy.types.Object,
    hand_bone_name: str,
    forearm_bone_name: str,
    socket_head_w: Vector,
    socket_dir_w: Vector,
    forearm_dir_w: Vector,
    side_sign: float,  # -1.0 for Right (-X), +1.0 for Left (+X)
    mat_bracer: bpy.types.Material,
    mat_palm: bpy.types.Material,
    mat_fingers: bpy.types.Material,
    mat_trim: bpy.types.Material,
    bracer_len: float = 0.16,
    bracer_rad_wrist: float = 0.044,
    bracer_rad_elbow: float = 0.056,
    scale: float = 1.0,
) -> bpy.types.Object:
    """Build a crisp, anatomically sculpted 3D gripping hand & armored forearm bracer centered
    EXACTLY around the weapon grip at `socket_head_w` with blade axis `socket_dir_w`!

    Coordinate frame of the hand (grip frame):
      +Z_g = socket_dir_w (weapon blade pointing out thumb/index side of fist)
      +Y_g = outward back-of-hand / forearm extension direction (perpendicular to Z_g)
      +X_g = cross(Y_g, Z_g) = palm-inward vs knuckle-outward axis
    The weapon hilt sits at origin (0, 0, 0) running along Z_g with radius ~0.022m.
    4 articulated curved fingers + opposing thumb wrap tightly around the cylinder r=0.022..0.036m!
    """
    z_g = socket_dir_w.normalized()
    # Forearm approaches wrist from -forearm_dir_w (from elbow toward wrist)
    back_wrist = (-forearm_dir_w).normalized()
    # Make y_g (back-of-hand -> wrist direction) perpendicular to z_g
    y_g = back_wrist - z_g * back_wrist.dot(z_g)
    if y_g.length < 1e-4:
        y_g = Vector((0.0, 1.0, 0.0))
        y_g = y_g - z_g * y_g.dot(z_g)
    y_g.normalize()
    x_g = y_g.cross(z_g).normalized()
    # Ensure consistent handedness: palm faces inward toward body (-side_sign * X roughly),
    # knuckles face outward (+side_sign). Flip x_g if needed so thumb always sits on +Z_g inner side!
    if x_g.x * side_sign < 0:
        x_g = -x_g
        y_g = z_g.cross(x_g).normalized()

    # Local-to-world matrix of grip frame
    rot_m = Matrix((
        (x_g.x, y_g.x, z_g.x, 0.0),
        (x_g.y, y_g.y, z_g.y, 0.0),
        (x_g.z, y_g.z, z_g.z, 0.0),
        (0.0,   0.0,   0.0,   1.0),
    ))
    frame_m = Matrix.Translation(socket_head_w) @ rot_m

    bm = bmesh.new()
    # Material slots: 0=bracer, 1=palm, 2=fingers, 3=trim
    # Also store per-vertex bone blend factor (0=100% Hand, 1=Forearm) via temporary custom float layer
    fa_layer = bm.verts.layers.float.new("forearm_w")

    def add_box(center: Vector, half_ext: Vector, mat_idx: int, rot_eul=(0.0, 0.0, 0.0), bevel_w=0.004, fw=0.0):
        m = Matrix.Translation(center * scale) @ Euler(rot_eul, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((*((half_ext * 2.0) * scale), 1.0))
        ret = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
        verts = ret["verts"]
        if bevel_w > 0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(bm, geom=edges, offset=bevel_w * scale, segments=2, affect="EDGES", clamp_overlap=True)
        # Assign material & forearm weight to all faces touching created area
        vset = set(verts)
        # Re-gather connected component via small BFS from first surviving vert
        seed = next((v for v in bm.verts if v in vset), None)
        if seed:
            comp = set()
            stack = [seed]
            while stack:
                cv = stack.pop()
                if cv in comp:
                    continue
                comp.add(cv)
                for e in cv.link_edges:
                    ov = e.other_vert(cv)
                    if ov not in comp:
                        stack.append(ov)
            for v in comp:
                v[fa_layer] = fw
                for f in v.link_faces:
                    f.material_index = mat_idx

    def add_tapered_tube(p0: Vector, p1: Vector, r0: float, r1: float, segs: int, mat_idx: int, fw0: float, fw1: float, rings: int = 5):
        axis = p1 - p0
        l = axis.length
        if l < 1e-5:
            return
        az = axis.normalized()
        up = Vector((0, 0, 1)) if abs(az.z) < 0.9 else Vector((1, 0, 0))
        ax = up.cross(az).normalized()
        ay = az.cross(ax).normalized()
        ring_verts = []
        for ri in range(rings):
            t = ri / float(rings - 1)
            c = (p0.lerp(p1, t)) * scale
            r = (r0 + (r1 - r0) * t) * scale
            # Slightly oval forearm/wrist cross-section
            rv = []
            for si in range(segs):
                ang = 2.0 * math.pi * si / segs
                pt = c + ax * (math.cos(ang) * r * 0.92) + ay * (math.sin(ang) * r * 1.08)
                v = bm.verts.new(pt)
                v[fa_layer] = fw0 + (fw1 - fw0) * t
                rv.append(v)
            ring_verts.append(rv)
        for ri in range(rings - 1):
            r_a, r_b = ring_verts[ri], ring_verts[ri + 1]
            for si in range(segs):
                sn = (si + 1) % segs
                f = bm.faces.new((r_a[si], r_a[sn], r_b[sn], r_b[si]))
                f.material_index = mat_idx
        # Cap ends
        f0 = bm.faces.new(list(reversed(ring_verts[0])))
        f0.material_index = mat_idx
        f1 = bm.faces.new(ring_verts[-1])
        f1.material_index = mat_idx

    # 1. Sculpted Palm & Metacarpal Back (sits on +Y_g side of the hilt, curving around hilt r=0.022m)
    # Palm heel sits around y=+0.036..+0.088, wrapping around grip axis Z_g in [-0.048, +0.048]
    add_box(Vector((0.004, 0.048, 0.000)), Vector((0.022, 0.032, 0.046)), mat_idx=1, bevel_w=0.009, fw=0.0)
    # Armored / sculpted knuckle guard ridge on back of hand (+X_g, +Y_g)
    add_box(Vector((0.022, 0.032, 0.002)), Vector((0.014, 0.024, 0.044)), mat_idx=3, bevel_w=0.006, fw=0.0)

    # 2. Four Articulated Curled Fingers wrapping tightly around the hilt (r = 0.022m at origin!)
    # Finger Z offsets along hilt from index (+0.033) to pinky (-0.033)
    finger_specs = [
        (0.033, 0.0105, 1.02),  # Index
        (0.011, 0.0110, 1.06),  # Middle
        (-0.011, 0.0102, 1.00), # Ring
        (-0.032, 0.0090, 0.90), # Pinky
    ]
    for fz, fr, flen in finger_specs:
        # 3-segment curled finger curving from knuckle (x=+0.024, y=+0.022) around front (-y) to palm (-x)
        pts = [
            Vector((0.022,  0.024, fz)),
            Vector((0.030 * flen,  0.002, fz)),
            Vector((0.020 * flen, -0.026 * flen, fz)),
            Vector((-0.012 * flen, -0.028 * flen, fz)),
            Vector((-0.024 * flen, -0.006, fz)),
        ]
        for k in range(len(pts) - 1):
            r_a = fr * (1.0 - k * 0.08)
            r_b = fr * (1.0 - (k + 1) * 0.08)
            add_tapered_tube(pts[k], pts[k + 1], r_a, r_b, 8, mat_idx=2, fw0=0.0, fw1=0.0, rings=2)

    # 3. Opposable Sculpted Thumb locking over the top (+Z_g) of the index & middle fingers!
    thumb_pts = [
        Vector((-0.014, 0.036,  0.032)),
        Vector((-0.028, 0.014,  0.042)),
        Vector((-0.018, -0.016, 0.044)),
        Vector((0.010, -0.026,  0.034)),
    ]
    for k in range(len(thumb_pts) - 1):
        add_tapered_tube(thumb_pts[k], thumb_pts[k + 1], 0.0125 - k * 0.001, 0.0115 - k * 0.001, 8, mat_idx=2, fw0=0.0, fw1=0.0, rings=2)

    # 4. Wrist Cuff + Armored Forearm Bracer extending seamlessly back along the forearm toward elbow!
    # Direction from wrist toward elbow in grip local frame:
    to_elbow_local = (rot_m.inverted() @ (-forearm_dir_w).normalized()).normalized()
    wrist_start = Vector((0.002, 0.068, -0.008))
    bracer_end = wrist_start + to_elbow_local * bracer_len
    # Decorative wrist cuff ring (trim)
    add_tapered_tube(wrist_start - to_elbow_local * 0.008, wrist_start + to_elbow_local * 0.024,
                     bracer_rad_wrist * 1.06, bracer_rad_wrist * 1.10, 12, mat_idx=3, fw0=0.10, fw1=0.35, rings=3)
    # Main tapered forearm bracer/sleeve connector
    add_tapered_tube(wrist_start + to_elbow_local * 0.015, bracer_end,
                     bracer_rad_wrist, bracer_rad_elbow, 12, mat_idx=0, fw0=0.25, fw1=1.0, rings=5)

    # Transform entire hand+bracer into rest-pose world space!
    bmesh.ops.transform(bm, matrix=frame_m, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(name)
    # Record per-vertex forearm weights before bm.free()
    vert_fw = [v[fa_layer] for v in bm.verts]
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in (mat_bracer, mat_palm, mat_fingers, mat_trim):
        obj.data.materials.append(m)
    box_uv(obj, scale=6.0)

    # Smooth shading
    for p in obj.data.polygons:
        p.use_smooth = True

    # Parent to armature with Armature modifier + exact vertex groups (Hand + Forearm blend)
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    vg_hand = obj.vertex_groups.new(name=hand_bone_name)
    vg_fa = obj.vertex_groups.new(name=forearm_bone_name)
    for idx, fw in enumerate(vert_fw):
        hw = max(0.0, min(1.0, 1.0 - fw))
        if hw > 1e-4:
            vg_hand.add([idx], hw, "REPLACE")
        if fw > 1e-4:
            vg_fa.add([idx], fw, "REPLACE")

    return obj


# ------------------------------------------------------------------ Cape De-Spiking + Clean Arm Re-Weighting
def despike_cape_and_clean_arms(
    body_obj: bpy.types.Object,
    arm: bpy.types.Object,
    arm_r_cyl: dict | None = None,
    arm_l_cyl: dict | None = None,
    hip_pin_predicate=None,
) -> tuple[int, int]:
    """Nuclear-clean skin weight rescue for fused AI-scanned capes, skirts, and wide kimono robes:
    - EVERY vertex OUTSIDE the tight anatomical arm cylinders (`arm_r_cyl`, `arm_l_cyl`) has ALL
      UpperArm / Forearm / Hand weights STRIPPED and reassigned smoothly to Chest / Spine / Hips / Cape!
      This guarantees ZERO horizontal stretching across the chest or exploding paper-spike capes!
    - Vertices strictly INSIDE the tight arm cylinders get smooth, clean UpperArm / Forearm weights
      (with optional Hand weight only when `allow_hand=True` — for wide-sleeve heroes, our sculpted
      anatomical bracers + gripping hands own Hand.L/R cleanly!).
    """
    mw = body_obj.matrix_world
    despiked = 0
    arm_reweighted = 0

    def bone_pts(bname: str) -> tuple[Vector, Vector]:
        b = arm.data.bones[bname]
        return arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local

    ua_r0, ua_r1 = bone_pts("UpperArm.R")
    fa_r0, fa_r1 = bone_pts("Forearm.R")
    hd_r0, hd_r1 = bone_pts("Hand.R")
    ua_l0, ua_l1 = bone_pts("UpperArm.L")
    fa_l0, fa_l1 = bone_pts("Forearm.L")
    hd_l0, hd_l1 = bone_pts("Hand.L")

    has_cape = "Cape" in arm.data.bones
    has_capetip = "CapeTip" in arm.data.bones
    arm_vg_idxs = {vg.index: vg.name for vg in body_obj.vertex_groups if vg.name in ARM_BONES_ALL}

    def torso_cape_weights(co: Vector, cape_y: float) -> dict[str, float]:
        is_back = co.y > cape_y
        if is_back:
            if co.z > 1.38:
                return {"Chest": 0.78, "Cape": 0.22} if has_cape else {"Chest": 1.0}
            elif co.z > 1.15:
                return {"Chest": 0.45, "Cape": 0.45, "Spine": 0.10} if has_cape else {"Chest": 0.65, "Spine": 0.35}
            elif co.z > 0.86:
                return {"Cape": 0.55, "CapeTip": 0.25, "Spine": 0.20} if (has_cape and has_capetip) else {"Spine": 0.5, "Hips": 0.5}
            else:
                return {"CapeTip": 0.65, "Cape": 0.20, "Hips": 0.15} if (has_cape and has_capetip) else {"Hips": 1.0}
        else:
            if co.z > 1.34:
                return {"Chest": 0.85, "Spine": 0.15}
            elif co.z > 1.12:
                return {"Chest": 0.45, "Spine": 0.55}
            elif co.z > 0.90:
                return {"Spine": 0.35, "Hips": 0.65}
            else:
                return {"Hips": 1.0}

    cape_y_ref = 0.08
    if arm_r_cyl and "cape_y" in arm_r_cyl:
        cape_y_ref = arm_r_cyl["cape_y"]

    for v in body_obj.data.vertices:
        co = mw @ v.co

        if hip_pin_predicate is not None and hip_pin_predicate(co):
            set_vert_weights(body_obj, v.index, {"Hips": 0.78, "Spine": 0.22})
            despiked += 1
            continue

        # Check strict Right Arm cylinder
        in_r = False
        if arm_r_cyl is not None and arm_r_cyl["pred"](co):
            _, d_ua = project_seg(co, ua_r0, ua_r1)
            _, d_fa = project_seg(co, fa_r0, fa_r1)
            _, d_hd = project_seg(co, hd_r0, hd_r1)
            max_r = arm_r_cyl["max_r"]
            if min(d_ua, d_fa, d_hd if arm_r_cyl.get("allow_hand", False) else 9.9) < max_r:
                in_r = True
                if arm_r_cyl.get("reweight", True):
                    w_ua = math.exp(-(d_ua / 0.065) ** 2)
                    w_fa = math.exp(-(d_fa / 0.060) ** 2) * (1.0 if co.z >= arm_r_cyl.get("min_fa_z", 0.92) else 0.1)
                    w_hd = (math.exp(-(d_hd / 0.055) ** 2) if arm_r_cyl.get("allow_hand", False) else 0.0)
                    inner_x = arm_r_cyl["inner_x"]
                    blend_sh = max(0.0, min(1.0, (co.x - (inner_x - 0.05)) / 0.06))
                    weights = {
                        "UpperArm.R": w_ua * (1.0 - 0.65 * blend_sh),
                        "Forearm.R": w_fa * (1.0 - 0.90 * blend_sh),
                        "Hand.R": w_hd * (1.0 - blend_sh),
                        "Shoulder.R": blend_sh * 0.75 if co.z > 1.30 else 0.0,
                        "Chest": blend_sh * 0.40 if co.z > 1.24 else (blend_sh * 0.50 if co.z > 1.05 else 0.0),
                    }
                    set_vert_weights(body_obj, v.index, weights)
                    arm_reweighted += 1
        if in_r:
            continue

        # Check strict Left Arm cylinder
        in_l = False
        if arm_l_cyl is not None and arm_l_cyl["pred"](co):
            _, d_ua = project_seg(co, ua_l0, ua_l1)
            _, d_fa = project_seg(co, fa_l0, fa_l1)
            _, d_hd = project_seg(co, hd_l0, hd_l1)
            max_r = arm_l_cyl["max_r"]
            if min(d_ua, d_fa, d_hd if arm_l_cyl.get("allow_hand", False) else 9.9) < max_r:
                in_l = True
                if arm_l_cyl.get("reweight", True):
                    w_ua = math.exp(-(d_ua / 0.065) ** 2)
                    w_fa = math.exp(-(d_fa / 0.060) ** 2) * (1.0 if co.z >= arm_l_cyl.get("min_fa_z", 0.92) else 0.1)
                    w_hd = (math.exp(-(d_hd / 0.055) ** 2) if arm_l_cyl.get("allow_hand", False) else 0.0)
                    inner_x = arm_l_cyl["inner_x"]
                    blend_sh = max(0.0, min(1.0, ((inner_x + 0.05) - co.x) / 0.06))
                    weights = {
                        "UpperArm.L": w_ua * (1.0 - 0.65 * blend_sh),
                        "Forearm.L": w_fa * (1.0 - 0.90 * blend_sh),
                        "Hand.L": w_hd * (1.0 - blend_sh),
                        "Shoulder.L": blend_sh * 0.75 if co.z > 1.30 else 0.0,
                        "Chest": blend_sh * 0.40 if co.z > 1.24 else (blend_sh * 0.50 if co.z > 1.05 else 0.0),
                    }
                    set_vert_weights(body_obj, v.index, weights)
                    arm_reweighted += 1
        if in_l:
            continue

        # ANY vertex outside both strict arm cylinders that still carries arm/hand weight -> STRIP IT!
        has_arm_w = any(g.group in arm_vg_idxs and g.weight > 0.01 for g in v.groups)
        if has_arm_w:
            set_vert_weights(body_obj, v.index, torso_cape_weights(co, cape_y_ref))
            despiked += 1

    return despiked, arm_reweighted


# ------------------------------------------------------------------ Armature Bone Refit
def refit_arm_bones(arm: bpy.types.Object, edits: dict[str, tuple[tuple[float, float, float], tuple[float, float, float], str | None]]) -> None:
    """In Edit Mode, reposition bone heads/tails & optional parent cleanly while preserving hierarchy."""
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for bname, (head_co, tail_co, parent_name) in edits.items():
        if bname not in eb:
            b = eb.new(bname)
        else:
            b = eb[bname]
        b.use_connect = False
        b.head = Vector(head_co)
        b.tail = Vector(tail_co)
        b.roll = 0.0
        if parent_name is not None and parent_name in eb:
            b.parent = eb[parent_name]
    if "Shoulder.R" in eb and "UpperArm.R" in eb:
        eb["Shoulder.R"].tail = eb["UpperArm.R"].head.copy()
    if "Shoulder.L" in eb and "UpperArm.L" in eb:
        eb["Shoulder.L"].tail = eb["UpperArm.L"].head.copy()
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ Material Depth & Repair
def wire_liu_body_pbr(body_obj: bpy.types.Object) -> None:
    """Wire freshly generated Sobel Normal + ORM maps onto Liu Quanwei's 0-normal-map tripo_mat_2d054047."""
    for slot in body_obj.material_slots:
        mat = slot.material
        if not mat or "tripo_mat" not in mat.name.lower():
            continue
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf:
            continue
        n_path = PBR_DIR / "liu_body_normal.png"
        if n_path.exists():
            tex_n = nt.nodes.new("ShaderNodeTexImage")
            tex_n.image = bpy.data.images.load(str(n_path), check_existing=True)
            tex_n.image.colorspace_settings.name = "Non-Color"
            nmap = nt.nodes.new("ShaderNodeNormalMap")
            nmap.inputs["Strength"].default_value = 1.45
            nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
            nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        orm_path = PBR_DIR / "liu_body_orm.png"
        if orm_path.exists():
            tex_orm = nt.nodes.new("ShaderNodeTexImage")
            tex_orm.image = bpy.data.images.load(str(orm_path), check_existing=True)
            tex_orm.image.colorspace_settings.name = "Non-Color"
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
            bc_in = bsdf.inputs["Base Color"]
            if bc_in.is_linked:
                src_sock = bc_in.links[0].from_socket
                nt.links.remove(bc_in.links[0])
                mix_ao = nt.nodes.new("ShaderNodeMix")
                mix_ao.data_type = "RGBA"
                mix_ao.blend_type = "MULTIPLY"
                mix_ao.inputs["Factor"].default_value = 0.55
                nt.links.new(src_sock, mix_ao.inputs[6])
                nt.links.new(sep.outputs["Red"], mix_ao.inputs[7])
                nt.links.new(mix_ao.outputs[2], bc_in)
        print(f"  [pbr] wired Normal(1.45) + ORM + AO onto {mat.name}")


def repair_hero_materials_in_blender(hero: str) -> None:
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nm = mat.name.lower()
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf:
            continue

        if hero == "wuYong" and "dark glove" in nm:
            bsdf.inputs["Base Color"].default_value = (0.075, 0.085, 0.100, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.58
            bsdf.inputs["Metallic"].default_value = 0.18
            print(f"  [mat] restored {mat.name} -> obsidian leather")
        elif hero == "wuYong" and "scarfinnerbacking" in nm:
            bsdf.inputs["Base Color"].default_value = (0.42, 0.39, 0.34, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.90
            bsdf.inputs["Metallic"].default_value = 0.0
            print(f"  [mat] restored {mat.name} -> shaded warm linen")
        elif hero == "sunDeng" and "seam local bake" in nm:
            bsdf.inputs["Base Color"].default_value = (0.09, 0.11, 0.12, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.86
            bsdf.inputs["Metallic"].default_value = 0.0
            print(f"  [mat] restored {mat.name} -> deep charcoal robe")

        is_head = any(k in nm for k in ("likeness", "weldedneck", "material.002")) or (hero in ("sunDeng", "liuQuanwei") and nm == "material.001")
        if not is_head:
            for node in nt.nodes:
                if node.type == "NORMAL_MAP":
                    node.inputs["Strength"].default_value = 1.40 if hero in ("liuQuanwei", "sunDeng") else 1.32


def patch_glb_pbr_factors(glb_path: Path, hero: str) -> None:
    raw = glb_path.read_bytes()
    magic, version, total_len = struct.unpack_from("<III", raw, 0)
    json_len, json_type = struct.unpack_from("<II", raw, 12)
    g = json.loads(raw[20:20 + json_len].decode("utf-8"))
    rest = raw[20 + json_len:]

    for m in g.get("materials", []):
        nm = (m.get("name") or "").lower()
        pbr = m.setdefault("pbrMetallicRoughness", {})
        has_tex = "baseColorTexture" in pbr
        if any(k in nm for k in ("likeness", "weldedneck", "material.002")) or (hero in ("sunDeng", "liuQuanwei") and nm == "material.001"):
            pbr["baseColorFactor"] = [0.85, 0.81, 0.78, 1.0]
            if "metallicRoughnessTexture" not in pbr:
                pbr["roughnessFactor"] = 0.66
                pbr["metallicFactor"] = 0.0
        elif has_tex and not any(k in nm for k in ("gauntlet", "hand", "bracer", "trim", "skin")):
            if hero == "xuXiao":
                pbr["baseColorFactor"] = [0.82, 0.81, 0.79, 1.0]
            elif hero == "wuYong":
                pbr["baseColorFactor"] = [0.88, 0.87, 0.85, 1.0]
            elif hero == "sunDeng":
                pbr["baseColorFactor"] = [0.86, 0.86, 0.86, 1.0]
            else:
                pbr["baseColorFactor"] = [0.92, 0.91, 0.89, 1.0]
            if "normalTexture" in m:
                m["normalTexture"]["scale"] = 1.40 if hero in ("liuQuanwei", "sunDeng") else 1.32

    new_json = json.dumps(g, separators=(",", ":")).encode("utf-8")
    new_json += b" " * ((4 - (len(new_json) % 4)) % 4)
    new_total = 12 + 8 + len(new_json) + len(rest)
    glb_path.write_bytes(struct.pack("<IIIII", magic, version, new_total, len(new_json), json_type) + new_json + rest)


def export_hero_glb(glb_path: Path, hero: str) -> None:
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        export_yup=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_skins=True,
        export_animations=True,
        export_nla_strips=False,
    )
    patch_glb_pbr_factors(glb_path, hero)
    print(f"[saved] {glb_path.name} ({glb_path.stat().st_size / 1e6:.2f} MB)")


# ------------------------------------------------------------------ Per-Hero Rescue Pipelines
def rescue_wu_yong() -> None:
    print("\n=== RESCUING WU YONG (Shogun) ===")
    path = RES_DIR / "DuelChar_wuYong.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    clear_all_pose_transforms(arm)

    # Measured directly from WuYong_222_Armor rest-pose slices:
    # - Body/arms sit at y ≈ +0.03..+0.15 (cape starts cleanly behind at y > 0.18).
    # - Zero-vertex hip/arm gap on Right at x = -0.295; hip-pouch valley on Left at x = +0.332.
    refit_arm_bones(arm, {
        "UpperArm.R":      ((-0.255,  0.105, 1.460), (-0.365,  0.095, 1.210), "Shoulder.R"),
        "Forearm.R":       ((-0.365,  0.095, 1.210), (-0.395,  0.032, 0.985), "UpperArm.R"),
        "Hand.R":          ((-0.395,  0.032, 0.985), (-0.382,  0.032, 0.895), "Forearm.R"),
        "weapon_socket_r": ((-0.382,  0.012, 0.925), (-0.382, -0.210, 1.000), "Hand.R"),
        "UpperArm.L":      (( 0.260,  0.120, 1.460), ( 0.338,  0.120, 1.210), "Shoulder.L"),
        "Forearm.L":       (( 0.338,  0.120, 1.210), ( 0.365,  0.092, 0.985), "UpperArm.L"),
        "Hand.L":          (( 0.365,  0.092, 0.985), ( 0.390,  0.080, 0.885), "Forearm.L"),
    })

    # Strict tight arm cylinders calibrated to WuYong_222_Armor's exact rest-pose geometry:
    # - Includes the full y-depth of both armored arms (y < 0.175/0.180) while stripping back cape (y >= 0.18)
    # - Below shoulder, strictly outside hip tasset (-0.295) and left waist leather pouch (+0.332)
    # - Wide enough (|x| < 0.50, max_r = 0.130) that EVERY outer vambrace plate moves as ONE unbroken arm!
    body = bpy.data.objects["WuYong_222_Armor"]
    despiked, arm_n = despike_cape_and_clean_arms(
        body, arm,
        arm_r_cyl={
            "pred": lambda co: (co.x < (-0.240 if co.z > 1.22 else -0.295)) and co.x > -0.50 and co.y < (0.190 if co.z > 1.26 else 0.235) and 0.80 < co.z < 1.50,
            "inner_x": -0.255, "max_r": 0.140, "allow_hand": True, "cape_y": 0.215, "min_fa_z": 0.80,
        },
        arm_l_cyl={
            "pred": lambda co: (co.x > (0.250 if co.z > 1.15 else 0.332)) and co.x < 0.50 and co.y < (0.205 if co.z > 1.26 else 0.255) and 0.80 < co.z < 1.50,
            "inner_x": 0.260, "max_r": 0.150, "allow_hand": True, "min_fa_z": 0.80,
        },
    )
    print(f"  [weights] despiked={despiked}, arm_reweighted={arm_n}")

    mat_bracer = make_pbr_mat("WuYong_GauntletSteel", "steel", tint=(0.14, 0.26, 0.24), roughness=0.30, metallic=0.84, normal_strength=1.1)
    mat_palm = make_pbr_mat("WuYong_GauntletLeather", "leather", tint=(0.09, 0.10, 0.12), roughness=0.64, metallic=0.10, normal_strength=1.0)
    mat_fingers = make_pbr_mat("WuYong_GauntletFingers", "steel", tint=(0.18, 0.20, 0.23), roughness=0.36, metallic=0.78, normal_strength=0.9)
    mat_gold = make_pbr_mat("WuYong_GauntletGold", "steel", tint=(0.86, 0.68, 0.28), roughness=0.24, metallic=0.92, normal_strength=0.7)

    sock_r = arm.data.bones["weapon_socket_r"]
    fa_r = arm.data.bones["Forearm.R"]
    build_sculpted_gripping_hand(
        "WuYong_GrippingGauntlet_R", arm, "Hand.R", "Forearm.R",
        socket_head_w=arm.matrix_world @ sock_r.head_local,
        socket_dir_w=(arm.matrix_world @ sock_r.tail_local) - (arm.matrix_world @ sock_r.head_local),
        forearm_dir_w=(arm.matrix_world @ fa_r.tail_local) - (arm.matrix_world @ fa_r.head_local),
        side_sign=-1.0,
        mat_bracer=mat_bracer, mat_palm=mat_palm, mat_fingers=mat_fingers, mat_trim=mat_gold,
        bracer_len=0.065, bracer_rad_wrist=0.042, bracer_rad_elbow=0.046, scale=1.00,
    )
    hd_l = arm.data.bones["Hand.L"]
    fa_l = arm.data.bones["Forearm.L"]
    build_sculpted_gripping_hand(
        "WuYong_GrippingGauntlet_L", arm, "Hand.L", "Forearm.L",
        socket_head_w=arm.matrix_world @ (hd_l.head_local.lerp(hd_l.tail_local, 0.52)),
        socket_dir_w=Vector((0.0, -0.94, 0.34)),
        forearm_dir_w=(arm.matrix_world @ fa_l.tail_local) - (arm.matrix_world @ fa_l.head_local),
        side_sign=1.0,
        mat_bracer=mat_bracer, mat_palm=mat_palm, mat_fingers=mat_fingers, mat_trim=mat_gold,
        bracer_len=0.065, bracer_rad_wrist=0.041, bracer_rad_elbow=0.045, scale=0.98,
    )

    repair_hero_materials_in_blender("wuYong")
    export_hero_glb(path, "wuYong")

    cfg = {
        "heightMeters": 1.84,
        "facingYawOffsetDeg": 0.0,
        "rightWeapon": {
            "boneName": "weapon_socket_r",
            "position": [0.0, 0.0, 0.0],
            "eulerDeg": [0.0, 180.0, 0.0],
            "scale": 1.0,
        },
    }
    (RES_DIR / "DuelChar_wuYong.json").write_text(json.dumps(cfg, indent=2) + "\n")


def rescue_liu_quanwei() -> None:
    print("\n=== RESCUING LIU QUANWEI (Nonna) ===")
    path = RES_DIR / "DuelChar_liuQuanwei.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    clear_all_pose_transforms(arm)

    refit_arm_bones(arm, {
        "UpperArm.R":      ((-0.215, 0.120, 1.425), (-0.250, 0.128, 1.190), "Shoulder.R"),
        "Forearm.R":       ((-0.250, 0.128, 1.190), (-0.242, 0.112, 0.975), "UpperArm.R"),
        "Hand.R":          ((-0.242, 0.112, 0.975), (-0.242, 0.102, 0.895), "Forearm.R"),
        "weapon_socket_r": ((-0.242, 0.090, 0.928), (-0.242, -0.130, 1.010), "Hand.R"),
        "UpperArm.L":      (( 0.228, 0.105, 1.425), ( 0.278, 0.124, 1.190), "Shoulder.L"),
        "Forearm.L":       (( 0.278, 0.124, 1.190), ( 0.272, 0.110, 0.975), "UpperArm.L"),
        "Hand.L":          (( 0.272, 0.110, 0.975), ( 0.272, 0.100, 0.895), "Forearm.L"),
    })

    # Because Liu's wide kimono robe fuses sleeve hems directly into the coat skirt below z=1.10,
    # keep arm weights strictly above z=1.12 on his upper sleeve shoulders while our sculpted
    # leather-wrapped forearm bracers + hands emerge smoothly out of the sleeves (ZERO coat stretching!)
    body = next(o for o in bpy.data.objects if o.type == "MESH" and "outfit" in o.name)
    despiked, arm_n = despike_cape_and_clean_arms(
        body, arm,
        arm_r_cyl={
            "pred": lambda co: co.x < -0.225 and co.x > -0.33 and co.y < 0.17 and 1.14 < co.z < 1.42,
            "inner_x": -0.225, "max_r": 0.082, "allow_hand": False, "cape_y": 0.175, "min_fa_z": 1.16,
        },
        arm_l_cyl={
            "pred": lambda co: co.x > 0.235 and co.x < 0.34 and co.y < 0.17 and 1.14 < co.z < 1.42,
            "inner_x": 0.235, "max_r": 0.082, "allow_hand": False, "min_fa_z": 1.16,
        },
    )
    print(f"  [weights] despiked={despiked}, arm_reweighted={arm_n}")

    mat_bracer = make_pbr_mat("Liu_LeatherBracer", "leather", tint=(0.24, 0.18, 0.14), roughness=0.70, metallic=0.06, normal_strength=1.2)
    mat_palm = make_pbr_mat("Liu_WrappedPalm", "leather", tint=(0.18, 0.15, 0.13), roughness=0.76, metallic=0.04, normal_strength=1.1)
    mat_fingers = make_pbr_mat("Liu_HandSkin", None, tint=(0.64, 0.49, 0.40), roughness=0.62, metallic=0.0)
    mat_bronze = make_pbr_mat("Liu_BronzeClasp", "steel", tint=(0.66, 0.48, 0.24), roughness=0.34, metallic=0.86, normal_strength=0.9)

    sock_r = arm.data.bones["weapon_socket_r"]
    fa_r = arm.data.bones["Forearm.R"]
    build_sculpted_gripping_hand(
        "Liu_GrippingHand_R", arm, "Hand.R", "Forearm.R",
        socket_head_w=arm.matrix_world @ sock_r.head_local,
        socket_dir_w=(arm.matrix_world @ sock_r.tail_local) - (arm.matrix_world @ sock_r.head_local),
        forearm_dir_w=(arm.matrix_world @ fa_r.tail_local) - (arm.matrix_world @ fa_r.head_local),
        side_sign=-1.0,
        mat_bracer=mat_bracer, mat_palm=mat_palm, mat_fingers=mat_fingers, mat_trim=mat_bronze,
        bracer_len=0.22, bracer_rad_wrist=0.045, bracer_rad_elbow=0.058, scale=1.04,
    )
    hd_l = arm.data.bones["Hand.L"]
    fa_l = arm.data.bones["Forearm.L"]
    build_sculpted_gripping_hand(
        "Liu_GrippingHand_L", arm, "Hand.L", "Forearm.L",
        socket_head_w=arm.matrix_world @ (hd_l.head_local.lerp(hd_l.tail_local, 0.55)),
        socket_dir_w=Vector((0.0, -0.94, 0.34)),
        forearm_dir_w=(arm.matrix_world @ fa_l.tail_local) - (arm.matrix_world @ fa_l.head_local),
        side_sign=1.0,
        mat_bracer=mat_bracer, mat_palm=mat_palm, mat_fingers=mat_fingers, mat_trim=mat_bronze,
        bracer_len=0.22, bracer_rad_wrist=0.045, bracer_rad_elbow=0.058, scale=1.02,
    )

    wire_liu_body_pbr(body)
    repair_hero_materials_in_blender("liuQuanwei")
    export_hero_glb(path, "liuQuanwei")

    cfg = {
        "heightMeters": 1.82,
        "facingYawOffsetDeg": 0.0,
        "rightWeapon": {
            "boneName": "weapon_socket_r",
            "position": [0.0, 0.0, 0.0],
            "eulerDeg": [0.0, 90.0, 0.0],
            "scale": 1.0,
        },
    }
    (RES_DIR / "DuelChar_liuQuanwei.json").write_text(json.dumps(cfg, indent=2) + "\n")


def rescue_sun_deng() -> None:
    print("\n=== RESCUING SUN DENG (Midnight) ===")
    path = RES_DIR / "DuelChar_sunDeng.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    clear_all_pose_transforms(arm)

    refit_arm_bones(arm, {
        "UpperArm.R":      ((-0.230, -0.020, 1.430), (-0.275, -0.075, 1.195), "Shoulder.R"),
        "Forearm.R":       ((-0.275, -0.075, 1.195), (-0.295, -0.115, 0.975), "UpperArm.R"),
        "Hand.R":          ((-0.295, -0.115, 0.975), (-0.295, -0.125, 0.895), "Forearm.R"),
        "weapon_socket_r": ((-0.295, -0.135, 0.928), (-0.295, -0.355, 1.010), "Hand.R"),
        "UpperArm.L":      (( 0.240, -0.025, 1.430), ( 0.312, -0.038, 1.195), "Shoulder.L"),
        "Forearm.L":       (( 0.312, -0.038, 1.195), ( 0.345, -0.062, 0.965), "UpperArm.L"),
        "Hand.L":          (( 0.345, -0.062, 0.965), ( 0.345, -0.072, 0.885), "Forearm.L"),
        "weapon_socket_l": (( 0.345, -0.082, 0.918), ( 0.345, -0.302, 1.000), "Hand.L"),
    })

    # Keep wide drooping robe folds below z=1.10 pinned to Spine/Hips while upper sleeves + sculpted
    # shinobi forearm wraps & gripping hands emerge cleanly!
    body = bpy.data.objects["SunDeng_222_Body"]
    despiked, arm_n = despike_cape_and_clean_arms(
        body, arm,
        arm_r_cyl={
            "pred": lambda co: co.x < -0.24 and co.y < 0.075 and 1.12 < co.z < 1.44,
            "inner_x": -0.24, "max_r": 0.095, "allow_hand": False, "cape_y": 0.08, "min_fa_z": 1.14,
        },
        arm_l_cyl={
            "pred": lambda co: co.x > 0.24 and co.y < 0.075 and 1.12 < co.z < 1.44,
            "inner_x": 0.24, "max_r": 0.105, "allow_hand": False, "min_fa_z": 1.14,
        },
    )
    print(f"  [weights] despiked={despiked}, arm_reweighted={arm_n}")

    mat_wrap = make_pbr_mat("SunDeng_ShinobiWrap", "leather", tint=(0.12, 0.15, 0.18), roughness=0.74, metallic=0.05, normal_strength=1.15)
    mat_glove = make_pbr_mat("SunDeng_ShinobiGlove", "leather", tint=(0.08, 0.10, 0.12), roughness=0.66, metallic=0.08, normal_strength=1.0)
    mat_skin = make_pbr_mat("SunDeng_HandSkin", None, tint=(0.64, 0.49, 0.40), roughness=0.62, metallic=0.0)
    mat_teal = make_pbr_mat("SunDeng_TealTrim", "steel", tint=(0.24, 0.52, 0.58), roughness=0.36, metallic=0.72, normal_strength=0.8)

    sock_r = arm.data.bones["weapon_socket_r"]
    fa_r = arm.data.bones["Forearm.R"]
    build_sculpted_gripping_hand(
        "SunDeng_GrippingHand_R", arm, "Hand.R", "Forearm.R",
        socket_head_w=arm.matrix_world @ sock_r.head_local,
        socket_dir_w=(arm.matrix_world @ sock_r.tail_local) - (arm.matrix_world @ sock_r.head_local),
        forearm_dir_w=(arm.matrix_world @ fa_r.tail_local) - (arm.matrix_world @ fa_r.head_local),
        side_sign=-1.0,
        mat_bracer=mat_wrap, mat_palm=mat_glove, mat_fingers=mat_skin, mat_trim=mat_teal,
        bracer_len=0.22, bracer_rad_wrist=0.042, bracer_rad_elbow=0.055, scale=1.0,
    )
    sock_l = arm.data.bones["weapon_socket_l"]
    fa_l = arm.data.bones["Forearm.L"]
    build_sculpted_gripping_hand(
        "SunDeng_GrippingHand_L", arm, "Hand.L", "Forearm.L",
        socket_head_w=arm.matrix_world @ sock_l.head_local,
        socket_dir_w=(arm.matrix_world @ sock_l.tail_local) - (arm.matrix_world @ sock_l.head_local),
        forearm_dir_w=(arm.matrix_world @ fa_l.tail_local) - (arm.matrix_world @ fa_l.head_local),
        side_sign=1.0,
        mat_bracer=mat_wrap, mat_palm=mat_glove, mat_fingers=mat_skin, mat_trim=mat_teal,
        bracer_len=0.22, bracer_rad_wrist=0.042, bracer_rad_elbow=0.055, scale=1.0,
    )

    repair_hero_materials_in_blender("sunDeng")
    export_hero_glb(path, "sunDeng")

    cfg = {
        "heightMeters": 1.8,
        "facingYawOffsetDeg": 0.0,
        "rightWeapon": {
            "boneName": "weapon_socket_r",
            "position": [0.0, 0.0, 0.0],
            "eulerDeg": [0.0, 90.0, 0.0],
            "scale": 1.0,
        },
        "leftWeapon": {
            "boneName": "weapon_socket_l",
            "position": [0.0, 0.0, 0.0],
            "eulerDeg": [0.0, 90.0, 0.0],
            "scale": 1.0,
        },
    }
    (RES_DIR / "DuelChar_sunDeng.json").write_text(json.dumps(cfg, indent=2) + "\n")


def rescue_xu_xiao() -> None:
    print("\n=== RESCUING XU XIAO (Grand Inquisitor) ===")
    path = RES_DIR / "DuelChar_xuXiao.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    clear_all_pose_transforms(arm)

    refit_arm_bones(arm, {
        "Hand.R":          ((-0.413, -0.275, 1.097), (-0.390, -0.345, 1.055), "Forearm.R"),
        "weapon_socket_r": ((-0.398, -0.312, 1.072), (-0.398, -0.495, 1.215), "Hand.R"),
        "Hand.L":          (( 0.366, -0.053, 0.981), ( 0.355, -0.105, 0.905), "Forearm.L"),
    })

    # NUCLEAR-CLEAN Crusader cape de-spiking:
    # Only the exposed right armored forearm/gauntlet (y < 0.02, x < -0.26, z > 0.96) and upper left
    # shoulder sleeve (y < 0.04, x > 0.27, z > 1.15) keep arm weights!
    # The ENTIRE draped white Crusader mantle & left-hip tome are 100% free of arm/hand weights -> ZERO spikes EVER!
    body = bpy.data.objects["XuXiao_Body_CutAtCollar"]
    despiked, arm_n = despike_cape_and_clean_arms(
        body, arm,
        arm_r_cyl={
            "pred": lambda co: co.x < -0.26 and co.y < 0.025 and 0.96 < co.z < 1.48,
            "inner_x": -0.26, "max_r": 0.098, "allow_hand": True, "reweight": False, "cape_y": 0.08,
        },
        arm_l_cyl={
            "pred": lambda co: co.x > 0.275 and co.y < 0.035 and 1.15 < co.z < 1.47,
            "inner_x": 0.275, "max_r": 0.088, "allow_hand": False, "reweight": True, "min_fa_z": 1.16,
        },
        hip_pin_predicate=lambda co: (0.14 < co.x < 0.34 and co.y < 0.02 and 0.82 < co.z < 1.08),
    )
    print(f"  [weights] despiked+tome_pinned={despiked}, left_arm_reweighted={arm_n}")

    mat_steel = make_pbr_mat("XuXiao_GauntletSteel", "steel", tint=(0.24, 0.26, 0.30), roughness=0.26, metallic=0.92, normal_strength=1.0)
    mat_leather = make_pbr_mat("XuXiao_GauntletLeather", "leather", tint=(0.14, 0.11, 0.09), roughness=0.66, metallic=0.08, normal_strength=0.9)
    mat_gold = make_pbr_mat("XuXiao_GauntletGold", "steel", tint=(0.88, 0.68, 0.26), roughness=0.22, metallic=0.94, normal_strength=0.6)

    sock_r = arm.data.bones["weapon_socket_r"]
    fa_r = arm.data.bones["Forearm.R"]
    build_sculpted_gripping_hand(
        "XuXiao_GrippingGauntlet_R", arm, "Hand.R", "Forearm.R",
        socket_head_w=arm.matrix_world @ sock_r.head_local,
        socket_dir_w=(arm.matrix_world @ sock_r.tail_local) - (arm.matrix_world @ sock_r.head_local),
        forearm_dir_w=(arm.matrix_world @ fa_r.tail_local) - (arm.matrix_world @ fa_r.head_local),
        side_sign=-1.0,
        mat_bracer=mat_steel, mat_palm=mat_leather, mat_fingers=mat_steel, mat_trim=mat_gold,
        bracer_len=0.14, bracer_rad_wrist=0.048, bracer_rad_elbow=0.056, scale=1.05,
    )
    hd_l = arm.data.bones["Hand.L"]
    fa_l = arm.data.bones["Forearm.L"]
    build_sculpted_gripping_hand(
        "XuXiao_GrippingGauntlet_L", arm, "Hand.L", "Forearm.L",
        socket_head_w=arm.matrix_world @ (hd_l.head_local.lerp(hd_l.tail_local, 0.50)),
        socket_dir_w=Vector((0.0, -0.82, 0.57)),
        forearm_dir_w=(arm.matrix_world @ fa_l.tail_local) - (arm.matrix_world @ fa_l.head_local),
        side_sign=1.0,
        mat_bracer=mat_steel, mat_palm=mat_leather, mat_fingers=mat_steel, mat_trim=mat_gold,
        bracer_len=0.22, bracer_rad_wrist=0.047, bracer_rad_elbow=0.056, scale=1.02,
    )

    repair_hero_materials_in_blender("xuXiao")
    export_hero_glb(path, "xuXiao")

    cfg = {
        "heightMeters": 1.82,
        "facingYawOffsetDeg": 0.0,
        "rightWeapon": {
            "boneName": "weapon_socket_r",
            "position": [0.0, 0.0, 0.0],
            "eulerDeg": [0.0, 90.0, 0.0],
            "scale": 1.0,
        },
    }
    (RES_DIR / "DuelChar_xuXiao.json").write_text(json.dumps(cfg, indent=2) + "\n")


# ------------------------------------------------------------------ Subdivided Organic 3D Obsidian-Flame Spirit Wolf & Owl
def build_spirit_wolf_glb() -> None:
    """Sculpt a sleek, subdivided obsidian-and-molten-flame leaping 3D Spirit Wolf."""
    print("\n=== BUILDING 3D SPIRIT WOLF GLB ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mat_obsidian = make_pbr_mat(
        "SpiritWolf_Obsidian", "steel", tint=(0.06, 0.04, 0.05), roughness=0.30, metallic=0.80,
        normal_strength=1.2, emission=(0.85, 0.16, 0.02), emission_strength=0.65,
    )
    mat_flame = make_pbr_mat(
        "SpiritWolf_MoltenMane", None, tint=(0.95, 0.36, 0.04), roughness=0.26, metallic=0.15,
        emission=(1.0, 0.30, 0.02), emission_strength=2.2,
    )
    mat_eye = make_pbr_mat(
        "SpiritWolf_Eye", None, tint=(1.0, 0.85, 0.25), roughness=0.1, metallic=0.0,
        emission=(1.0, 0.72, 0.12), emission_strength=5.0,
    )

    bm = bmesh.new()

    def add_sculpt_part(pts_r: list[tuple[Vector, float, float]], segs: int, mat_idx: int):
        rings = []
        n = len(pts_r)
        for i, (c, ry, rz) in enumerate(pts_r):
            t = (pts_r[min(i + 1, n - 1)][0] - pts_r[max(i - 1, 0)][0]).normalized()
            up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((0, 1, 0))
            side = up.cross(t).normalized()
            norm = t.cross(side).normalized()
            rings.append([bm.verts.new(c + side * (math.cos(2 * math.pi * s / segs) * ry) + norm * (math.sin(2 * math.pi * s / segs) * rz)) for s in range(segs)])
        for i in range(n - 1):
            ra, rb = rings[i], rings[i + 1]
            for s in range(segs):
                sn = (s + 1) % segs
                f = bm.faces.new((ra[s], ra[sn], rb[sn], rb[s]))
                f.material_index = mat_idx
        f0 = bm.faces.new(list(reversed(rings[0]))); f0.material_index = mat_idx
        f1 = bm.faces.new(rings[-1]); f1.material_index = mat_idx

    # Sleek muscular leaping wolf body (tucked waist, deep ribcage, fierce snarling head)
    add_sculpt_part([
        (Vector((-0.56, 0.0, 0.56)), 0.11, 0.13),
        (Vector((-0.34, 0.0, 0.52)), 0.10, 0.11),  # Tucked athletic wolf waist!
        (Vector((-0.06, 0.0, 0.58)), 0.14, 0.17),
        (Vector(( 0.20, 0.0, 0.67)), 0.19, 0.23),  # Deep muscular chest
        (Vector(( 0.42, 0.0, 0.75)), 0.16, 0.19),  # Shoulders
        (Vector(( 0.58, 0.0, 0.84)), 0.12, 0.14),  # Arched neck
        (Vector(( 0.72, 0.0, 0.86)), 0.12, 0.12),  # Brow / Cranium
        (Vector(( 0.90, 0.0, 0.80)), 0.055, 0.055),# Snout
        (Vector(( 0.99, 0.0, 0.78)), 0.025, 0.025),# Nose tip
    ], segs=12, mat_idx=0)

    # Lower snarling jaw
    add_sculpt_part([
        (Vector((0.68, 0.0, 0.77)), 0.075, 0.042),
        (Vector((0.91, 0.0, 0.70)), 0.036, 0.024),
    ], segs=8, mat_idx=0)

    # Ears, eyes, and articulated bent athletic wolf legs (upper arm -> bent elbow -> extended paw!)
    for sgn in (-1.0, 1.0):
        add_sculpt_part([
            (Vector((0.65, sgn * 0.085, 0.93)), 0.040, 0.030),
            (Vector((0.58, sgn * 0.115, 1.10)), 0.010, 0.010),
        ], segs=6, mat_idx=1)
        ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.022,
                                         matrix=Matrix.Translation(Vector((0.78, sgn * 0.080, 0.875))))
        for v in ret["verts"]:
            for f in v.link_faces:
                f.material_index = 2

        # Articulated front lunging legs (shoulder -> bent elbow back -> angled forearm forward -> clawed paw!)
        add_sculpt_part([
            (Vector((0.36, sgn * 0.14, 0.68)), 0.085, 0.095),
            (Vector((0.26, sgn * 0.15, 0.48)), 0.058, 0.062),  # Bent elbow
            (Vector((0.52, sgn * 0.14, 0.30)), 0.042, 0.042),  # Reaching forearm
            (Vector((0.72, sgn * 0.13, 0.24)), 0.048, 0.030),  # Lunging paw
        ], segs=8, mat_idx=0)

        # Articulated hind driving legs (muscular thigh -> bent hock back -> driving metatarsal -> paw!)
        add_sculpt_part([
            (Vector((-0.46, sgn * 0.14, 0.56)), 0.095, 0.110),
            (Vector((-0.34, sgn * 0.15, 0.36)), 0.062, 0.068),  # Stifle knee
            (Vector((-0.64, sgn * 0.14, 0.22)), 0.042, 0.045),  # Hock
            (Vector((-0.82, sgn * 0.14, 0.06)), 0.046, 0.028),  # Push-off paw
        ], segs=8, mat_idx=0)

    # Sweeping sculpted flame-mane ridges & lush streaming flame tail
    for fx, fz, flen in [(0.60, 0.94, 0.30), (0.44, 0.90, 0.36), (0.24, 0.84, 0.34), (0.04, 0.76, 0.26)]:
        for lat in (-0.075, 0.0, 0.075):
            add_sculpt_part([
                (Vector((fx, lat, fz)), 0.036, 0.042),
                (Vector((fx - flen * 0.55, lat * 1.3, fz + flen * 0.42)), 0.022, 0.028),
                (Vector((fx - flen, lat * 1.6, fz + flen * 0.22)), 0.006, 0.008),
            ], segs=6, mat_idx=1)

    add_sculpt_part([
        (Vector((-0.56, 0.0, 0.58)), 0.072, 0.075),
        (Vector((-0.82, 0.0, 0.68)), 0.095, 0.105),
        (Vector((-1.10, 0.0, 0.76)), 0.064, 0.072),
        (Vector((-1.34, 0.0, 0.72)), 0.014, 0.018),
    ], segs=8, mat_idx=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("SpiritWolfMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("DuelProp_SpiritWolf", mesh)
    bpy.context.collection.objects.link(obj)
    for m in (mat_obsidian, mat_flame, mat_eye):
        obj.data.materials.append(m)
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 1; sub.render_levels = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Subsurf")
    for p in obj.data.polygons:
        p.use_smooth = True
    box_uv(obj, scale=2.5)

    out_path = RES_DIR / "DuelProp_SpiritWolf.glb"
    bpy.ops.export_scene.gltf(filepath=str(out_path), export_format="GLB", export_yup=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO")
    print(f"[saved] {out_path.name} ({out_path.stat().st_size // 1024} KB, {len(obj.data.polygons)} tris)")


def build_spirit_owl_glb() -> None:
    """Sculpt a sleek, subdivided obsidian-and-solar-flame swooping 3D Spirit Owl."""
    print("\n=== BUILDING 3D SPIRIT OWL GLB ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mat_plumage = make_pbr_mat(
        "SpiritOwl_ObsidianPlumage", "steel", tint=(0.08, 0.05, 0.06), roughness=0.34, metallic=0.72,
        normal_strength=1.1, emission=(0.85, 0.22, 0.02), emission_strength=0.65,
    )
    mat_solar = make_pbr_mat(
        "SpiritOwl_SolarFeather", None, tint=(0.98, 0.44, 0.06), roughness=0.24, metallic=0.18,
        emission=(1.0, 0.38, 0.04), emission_strength=2.4,
    )
    mat_eye = make_pbr_mat(
        "SpiritOwl_Eye", None, tint=(1.0, 0.90, 0.30), roughness=0.1, metallic=0.0,
        emission=(1.0, 0.78, 0.14), emission_strength=5.5,
    )

    bm = bmesh.new()

    def add_loft(pts_r, segs, mat_idx):
        rings = []
        n = len(pts_r)
        for i, (c, ry, rz) in enumerate(pts_r):
            t = (pts_r[min(i + 1, n - 1)][0] - pts_r[max(i - 1, 0)][0]).normalized()
            up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            side = up.cross(t).normalized()
            norm = t.cross(side).normalized()
            rings.append([bm.verts.new(c + side * (math.cos(2 * math.pi * s / segs) * ry) + norm * (math.sin(2 * math.pi * s / segs) * rz)) for s in range(segs)])
        for i in range(n - 1):
            ra, rb = rings[i], rings[i + 1]
            for s in range(segs):
                sn = (s + 1) % segs
                f = bm.faces.new((ra[s], ra[sn], rb[sn], rb[s]))
                f.material_index = mat_idx
        f0 = bm.faces.new(list(reversed(rings[0]))); f0.material_index = mat_idx
        f1 = bm.faces.new(rings[-1]); f1.material_index = mat_idx

    add_loft([
        (Vector((-0.34, 0.0, -0.04)), 0.05, 0.03),
        (Vector((-0.14, 0.0, -0.02)), 0.12, 0.11),
        (Vector(( 0.08, 0.0,  0.02)), 0.15, 0.14),
        (Vector(( 0.24, 0.0,  0.08)), 0.13, 0.13),
        (Vector(( 0.34, 0.0,  0.06)), 0.06, 0.05),
    ], segs=12, mat_idx=0)
    add_loft([
        (Vector((0.32, 0.0, 0.06)), 0.035, 0.040),
        (Vector((0.43, 0.0, 0.00)), 0.009, 0.012),
    ], segs=6, mat_idx=1)

    for sgn in (-1.0, 1.0):
        add_loft([
            (Vector((0.22, sgn * 0.08, 0.17)), 0.035, 0.028),
            (Vector((0.12, sgn * 0.15, 0.30)), 0.008, 0.008),
        ], segs=6, mat_idx=1)
        ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.028,
                                         matrix=Matrix.Translation(Vector((0.30, sgn * 0.065, 0.10))))
        for v in ret["verts"]:
            for f in v.link_faces:
                f.material_index = 2
        add_loft([
            (Vector(( 0.08, sgn * 0.12, 0.06)), 0.11, 0.034),
            (Vector(( 0.02, sgn * 0.38, 0.20)), 0.13, 0.026),
            (Vector((-0.10, sgn * 0.66, 0.28)), 0.11, 0.020),
            (Vector((-0.26, sgn * 0.90, 0.18)), 0.04, 0.010),
        ], segs=8, mat_idx=0)
        for k in range(5):
            frac = k / 4.0
            base = Vector((0.02 - frac * 0.22, sgn * (0.34 + frac * 0.48), 0.18 + (0.08 if k in (1, 2) else 0.02)))
            tip = base + Vector((-0.26 - frac * 0.12, sgn * (0.16 + frac * 0.10), -0.02 - frac * 0.04))
            add_loft([(base, 0.030, 0.009), (tip, 0.006, 0.004)], segs=6, mat_idx=1)

    for lat in (-0.12, -0.06, 0.0, 0.06, 0.12):
        add_loft([
            (Vector((-0.28, lat * 0.4, -0.03)), 0.028, 0.010),
            (Vector((-0.60, lat * 1.4, -0.06)), 0.010, 0.005),
        ], segs=6, mat_idx=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("SpiritOwlMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("DuelProp_SpiritOwl", mesh)
    bpy.context.collection.objects.link(obj)
    for m in (mat_plumage, mat_solar, mat_eye):
        obj.data.materials.append(m)
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 1; sub.render_levels = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Subsurf")
    for p in obj.data.polygons:
        p.use_smooth = True
    box_uv(obj, scale=2.5)

    out_path = RES_DIR / "DuelProp_SpiritOwl.glb"
    bpy.ops.export_scene.gltf(filepath=str(out_path), export_format="GLB", export_yup=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO")
    print(f"[saved] {out_path.name} ({out_path.stat().st_size // 1024} KB, {len(obj.data.polygons)} tris)")


def main() -> None:
    import sys
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only: set[str] | None = None
    if "--heroes" in argv:
        idx = argv.index("--heroes")
        only = set()
        for tok in argv[idx + 1:]:
            if tok.startswith("--"):
                break
            only.add(tok)

    def want(k: str) -> bool:
        return only is None or k in only

    if want("wuYong"):
        rescue_wu_yong()
    if want("liuQuanwei"):
        rescue_liu_quanwei()
    if want("sunDeng"):
        rescue_sun_deng()
    if want("xuXiao"):
        rescue_xu_xiao()
    if want("spirits"):
        build_spirit_wolf_glb()
        build_spirit_owl_glb()
    print("\n=== HERO RESCUE COMPLETE! ===")


if __name__ == "__main__":
    main()
