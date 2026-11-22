#!/usr/bin/env python3
"""Build a genuine sculpted PBR 3D Ancient Mountain Sanctuary Courtyard (.glb) in Blender 4.2.

Zero primitive SCNBox walls, zero flat sticker billboards, zero MS-Paint triangles.
Produces App/Resources/DuelCharacters/DuelStage_Sanctuary.glb (~20-26k tris, ~4.5 MB)
with embedded Albedo + Normal + Roughness + AO maps, vaulted segmented stone voussoir
arches, beveled columns, broken ruins, stone temple braziers, 3D woody climbing vines
with layered volumetric crimson maple/ivy canopies, midground cloister parallax, and
curved painted misty mountain valley sky cyclorama.

Run with: /home/antigravity/blender/blender --background --python scripts/build_sanctuary_stage_glb.py
"""
from __future__ import annotations

import math
import random
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix, Vector, Euler

PBR_DIR = Path("/tmp/pbr_build")
OUT_GLB = Path("App/Resources/DuelCharacters/DuelStage_Sanctuary.glb")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_pbr_material(
    name: str,
    albedo_file: str,
    normal_file: str | None = None,
    orm_file: str | None = None,
    normal_strength: float = 1.15,
    base_tint: tuple[float, float, float] | None = None,
    rough_default: float = 0.80,
    metal_default: float = 0.0,
    double_sided: bool = False,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rough_default
    bsdf.inputs["Metallic"].default_value = metal_default
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Albedo
    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.image = bpy.data.images.load(str(PBR_DIR / albedo_file), check_existing=True)
    tex_alb.image.colorspace_settings.name = "sRGB"
    if base_tint is not None:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*base_tint, 1.0)
        nt.links.new(tex_alb.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    # Normal map
    if normal_file:
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = bpy.data.images.load(str(PBR_DIR / normal_file), check_existing=True)
        tex_n.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    # Packed ORM (R=AO, G=Roughness, B=Metalness)
    if orm_file:
        tex_orm = nt.nodes.new("ShaderNodeTexImage")
        tex_orm.image = bpy.data.images.load(str(PBR_DIR / orm_file), check_existing=True)
        tex_orm.image.colorspace_settings.name = "Non-Color"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

        # glTF Occlusion node group (recognized by Blender 4.2 glTF exporter!)
        ao_group = bpy.data.node_groups.get("glTF Material Output")
        if ao_group is None:
            ao_group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
            ao_group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        ao_node = nt.nodes.new("ShaderNodeGroup")
        ao_node.node_tree = ao_group
        nt.links.new(sep.outputs["Red"], ao_node.inputs["Occlusion"])

    return mat


def make_vines_material() -> bpy.types.Material:
    mat = bpy.data.materials.new(name="Mat_CrimsonVines")
    mat.use_nodes = True
    mat.use_backface_culling = False
    mat.blend_method = "CLIP"
    mat.alpha_threshold = 0.42
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.78
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(PBR_DIR / "vines_atlas_rgba.png"), check_existing=True)
    tex.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])

    tex_n = nt.nodes.new("ShaderNodeTexImage")
    tex_n.image = bpy.data.images.load(str(PBR_DIR / "vines_atlas_normal.png"), check_existing=True)
    tex_n.image.colorspace_settings.name = "Non-Color"
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_sky_material() -> bpy.types.Material:
    """Unlit painterly sky dome material (KHR_materials_unlit via Background shader -> Output)."""
    mat = bpy.data.materials.new(name="Mat_SkyPanorama")
    mat.use_nodes = True
    mat.use_backface_culling = False
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(PBR_DIR / "sanctuary_sky_pano.jpg"), check_existing=True)
    tex.image.colorspace_settings.name = "sRGB"
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    return mat


def make_ember_material() -> bpy.types.Material:
    mat = bpy.data.materials.new(name="Mat_BrazierEmber")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.85, 0.28, 0.05, 1.0)
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.40, 0.08, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 2.0
    bsdf.inputs["Roughness"].default_value = 0.65
    return mat


def make_iron_material() -> bpy.types.Material:
    return make_pbr_material(
        "Mat_ForgedIron",
        "steel_albedo.jpg",
        "steel_normal.png",
        "steel_orm.png",
        normal_strength=0.9,
        base_tint=(0.42, 0.44, 0.48),
    )


def box_uv_project(bm: bmesh.types.BMesh, scale: float = 0.45) -> None:
    """Clean tri-planar world-space box UV projection so every carved stone face has zero stretching."""
    bm.normal_update()
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


def add_weathered_block(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    bevel: float = 0.045,
    chip: float = 0.025,
    rot_euler: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rng: random.Random | None = None,
) -> None:
    """Create a chamfered, subtly weathered stone block (never raw sharp-edged cubes!)."""
    sub = bmesh.new()
    bmesh.ops.create_cube(sub, size=1.0)
    sx, sy, sz = size
    for v in sub.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    if bevel > 0:
        bmesh.ops.bevel(
            sub,
            geom=list(sub.edges),
            offset=min(bevel, min(sx, sy, sz) * 0.28),
            segments=2,
            affect="EDGES",
            clamp_overlap=True,
        )
    if chip > 0 and rng is not None:
        for v in sub.verts:
            v.co.x += (rng.random() - 0.5) * chip
            v.co.y += (rng.random() - 0.5) * chip
            v.co.z += (rng.random() - 0.5) * chip * 0.7

    xf = Matrix.Translation(Vector(center)) @ Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(sub, matrix=xf, verts=sub.verts)

    # Copy into target bmesh
    vert_map = {}
    for v in sub.verts:
        vert_map[v.index] = bm.verts.new(v.co)
    for f in sub.faces:
        try:
            nf = bm.faces.new([vert_map[v.index] for v in f.verts])
            nf.smooth = False
        except ValueError:
            pass
    sub.free()


def add_octagonal_column(
    bm: bmesh.types.BMesh,
    x: float,
    y: float,
    z0: float,
    height: float,
    radius: float,
    rng: random.Random,
    broken_top: bool = False,
) -> None:
    """Sculpted ancient sanctuary column: stepped plinth base + chamfered octagonal shaft + carved capital."""
    # Stepped carved plinth base
    add_weathered_block(bm, (x, y, z0 + 0.14), (radius * 2.55, radius * 2.55, 0.28), bevel=0.04, chip=0.018, rng=rng)
    add_weathered_block(bm, (x, y, z0 + 0.34), (radius * 2.15, radius * 2.15, 0.16), bevel=0.035, chip=0.015, rng=rng)

    # Multi-drum carved octagonal shaft (slight weathering shift per drum!)
    shaft_z0 = z0 + 0.42
    shaft_h = max(0.5, height - (0.42 if broken_top else 0.72))
    drums = max(3, int(shaft_h / 0.60))
    dh = shaft_h / drums
    for d in range(drums):
        dz = shaft_z0 + d * dh
        r_bot = radius * (1.0 - 0.04 * (d / max(1, drums)))
        r_top = radius * (1.0 - 0.04 * ((d + 1) / max(1, drums)))
        sub = bmesh.new()
        bmesh.ops.create_cone(
            sub,
            cap_ends=True,
            cap_tris=False,
            segments=12,
            radius1=r_bot,
            radius2=r_top,
            depth=dh - 0.012,
        )
        # Jagged sheared break on top drum if broken column
        if broken_top and d == drums - 1:
            slope_a = rng.uniform(0.0, math.tau)
            for v in sub.verts:
                if v.co.z > 0:
                    ang = math.atan2(v.co.y, v.co.x)
                    v.co.z += math.cos(ang - slope_a) * 0.22 + (rng.random() - 0.5) * 0.07
        else:
            for v in sub.verts:
                v.co.x += (rng.random() - 0.5) * 0.016
                v.co.y += (rng.random() - 0.5) * 0.016
        jx = (rng.random() - 0.5) * 0.018
        jy = (rng.random() - 0.5) * 0.018
        xf = Matrix.Translation((x + jx, y + jy, dz + dh * 0.5))
        bmesh.ops.transform(sub, matrix=xf, verts=sub.verts)
        vmap = {v.index: bm.verts.new(v.co) for v in sub.verts}
        for f in sub.faces:
            try:
                nf = bm.faces.new([vmap[v.index] for v in f.verts])
                nf.smooth = abs(f.normal.z) < 0.5
            except ValueError:
                pass
        sub.free()

    # Carved stepped capital if intact
    if not broken_top:
        top_z = z0 + height
        add_weathered_block(bm, (x, y, top_z - 0.22), (radius * 2.20, radius * 2.20, 0.14), bevel=0.03, chip=0.016, rng=rng)
        add_weathered_block(bm, (x, y, top_z - 0.06), (radius * 2.65, radius * 2.65, 0.16), bevel=0.04, chip=0.018, rng=rng)


def add_voussoir_arch(
    bm: bmesh.types.BMesh,
    cx: float,
    y: float,
    spring_z: float,
    span_radius: float,
    arch_thick: float,
    arch_depth: float,
    rng: random.Random,
    segments: int = 13,
    collapsed_side: str | None = None,
) -> None:
    """True architectural segmented curved stone voussoir arch with protruding carved keystone!"""
    for i in range(segments):
        if collapsed_side == "left" and i < segments // 2 - 1:
            continue
        if collapsed_side == "right" and i > segments // 2 + 1:
            continue
        t0 = math.pi * (i / segments)
        t1 = math.pi * ((i + 1) / segments)
        tm = 0.5 * (t0 + t1)
        is_keystone = (i == segments // 2)
        r_mid = span_radius + arch_thick * (0.56 if is_keystone else 0.5)
        bx = cx - math.cos(tm) * r_mid
        bz = spring_z + math.sin(tm) * r_mid
        arc_len = (t1 - t0) * (span_radius + arch_thick * 0.55) * 1.06
        rad_h = arch_thick * (1.28 if is_keystone else 1.0)
        dep = arch_depth * (1.14 if is_keystone else 1.0)
        pitch_y = -(tm - math.pi * 0.5)
        add_weathered_block(
            bm,
            (bx, y, bz),
            (arc_len, dep, rad_h),
            bevel=0.032,
            chip=0.020,
            rot_euler=(0.0, pitch_y, 0.0),
            rng=rng,
        )

    # Broken jagged coping masonry along upper arch haunches
    if collapsed_side is None:
        for side in (-1.0, 1.0):
            add_weathered_block(
                bm,
                (cx + side * (span_radius + 0.10), y, spring_z + span_radius * 0.58),
                (span_radius * 0.42, arch_depth * 0.88, span_radius * 0.62),
                bevel=0.035,
                chip=0.022,
                rng=rng,
            )


def add_woody_vine_branch(
    bm: bmesh.types.BMesh,
    points: list[tuple[float, float, float]],
    r_start: float,
    r_end: float,
    sides: int = 6,
) -> None:
    """Create a sculpted tapered 3D woody climbing vine tube along a 3D curve."""
    rings = []
    n_pts = len(points)
    for idx, pt in enumerate(points):
        p = Vector(pt)
        if idx == 0:
            tang = (Vector(points[1]) - p).normalized()
        elif idx == n_pts - 1:
            tang = (p - Vector(points[idx - 1])).normalized()
        else:
            tang = (Vector(points[idx + 1]) - Vector(points[idx - 1])).normalized()
        ref = Vector((0, 0, 1)) if abs(tang.z) < 0.9 else Vector((1, 0, 0))
        u_ax = tang.cross(ref).normalized()
        v_ax = tang.cross(u_ax).normalized()
        r = r_start + (r_end - r_start) * (idx / max(1, n_pts - 1))
        ring = []
        for s in range(sides):
            a = math.tau * s / sides
            pos = p + (u_ax * math.cos(a) + v_ax * math.sin(a)) * r
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    for i in range(n_pts - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(sides):
            sn = (s + 1) % sides
            try:
                f = bm.faces.new([r0[s], r0[sn], r1[sn], r1[s]])
                f.smooth = True
            except ValueError:
                pass


def add_volumetric_vine_cluster(
    bm: bmesh.types.BMesh,
    anchor: tuple[float, float, float],
    width: float,
    height: float,
    quadrant: int,
    base_yaw: float = 0.0,
    drape_forward: float = 0.16,
) -> None:
    """Create a 3-strip intersecting curved 3D hanging crimson maple + ivy canopy (NOT a flat 2D billboard!)."""
    uv_layer = bm.loops.layers.uv.verify()
    qr, qc = divmod(quadrant % 4, 2)
    u0, u1 = qc * 0.5 + 0.008, (qc + 1) * 0.5 - 0.008
    v_top = 1.0 - (qr * 0.5 + 0.008)
    v_bot = 1.0 - ((qr + 1) * 0.5 - 0.008)

    strips = [
        (base_yaw - 0.48, 0.00, 1.00),
        (base_yaw + 0.04, -0.06, 0.94),
        (base_yaw + 0.52, 0.04, 0.88),
    ]
    rows = 5
    ax, ay, az = anchor
    for yaw, dy_off, scale in strips:
        cy, sy = math.cos(yaw), math.sin(yaw)
        w = width * scale
        h = height * scale
        grid = []
        for r in range(rows + 1):
            t = r / rows
            z = az - t * h
            bow = math.sin(t * math.pi) * drape_forward
            row_verts = []
            for c in range(3):
                cu = (c - 1)
                lx = cu * (w * 0.5)
                ly = -(1.0 - abs(cu)) * 0.08 - bow
                wx = ax + lx * cy - ly * sy
                wy = ay + dy_off + lx * sy + ly * cy
                row_verts.append((bm.verts.new((wx, wy, z)), u0 + (u1 - u0) * (c * 0.5), v_top + (v_bot - v_top) * t))
            grid.append(row_verts)

        for r in range(rows):
            for c in range(2):
                v00, u00, w00 = grid[r][c]
                v10, u10, w10 = grid[r][c + 1]
                v11, u11, w11 = grid[r + 1][c + 1]
                v01, u01, w01 = grid[r + 1][c]
                try:
                    f = bm.faces.new([v00, v10, v11, v01])
                    f.smooth = True
                    uvs = [(u00, w00), (u10, w10), (u11, w11), (u01, w01)]
                    for loop, uv in zip(f.loops, uvs):
                        loop[uv_layer].uv = uv
                except ValueError:
                    pass


def add_stone_brazier(
    bm_stone: bmesh.types.BMesh,
    bm_iron: bmesh.types.BMesh,
    bm_ember: bmesh.types.BMesh,
    x: float,
    y: float,
    z0: float,
    rng: random.Random,
) -> None:
    """Sculpted ancient temple stone lantern/brazier with iron cage & glowing amber coals."""
    add_weathered_block(bm_stone, (x, y, z0 + 0.11), (0.64, 0.64, 0.22), bevel=0.04, chip=0.015, rng=rng)
    add_weathered_block(bm_stone, (x, y, z0 + 0.52), (0.30, 0.30, 0.62), bevel=0.04, chip=0.012, rng=rng)
    add_weathered_block(bm_stone, (x, y, z0 + 0.88), (0.60, 0.60, 0.14), bevel=0.04, chip=0.012, rng=rng)
    for sx in (-0.18, 0.18):
        for sy in (-0.18, 0.18):
            add_weathered_block(bm_iron, (x + sx, y + sy, z0 + 1.10), (0.04, 0.04, 0.32), bevel=0.008)
    sub = bmesh.new()
    bmesh.ops.create_icosphere(sub, subdivisions=2, radius=0.115)
    for v in sub.verts:
        v.co.z *= 0.65
    bmesh.ops.transform(sub, matrix=Matrix.Translation((x, y, z0 + 1.02)), verts=sub.verts)
    vmap = {v.index: bm_ember.verts.new(v.co) for v in sub.verts}
    for f in sub.faces:
        try:
            nf = bm_ember.faces.new([vmap[v.index] for v in f.verts])
            nf.smooth = True
        except ValueError:
            pass
    sub.free()
    add_weathered_block(bm_stone, (x, y, z0 + 1.32), (0.76, 0.76, 0.11), bevel=0.035, chip=0.014, rng=rng)
    add_weathered_block(bm_stone, (x, y, z0 + 1.43), (0.46, 0.46, 0.12), bevel=0.035, chip=0.012, rng=rng)
    add_weathered_block(bm_stone, (x, y, z0 + 1.54), (0.18, 0.18, 0.12), bevel=0.03, chip=0.01, rng=rng)


def build_object(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, auto_uv_scale: float | None = None) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    if auto_uv_scale is not None:
        box_uv_project(bm, scale=auto_uv_scale)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def build_stage() -> None:
    clear_scene()
    rng = random.Random(20261122)

    mat_ground = make_pbr_material("Mat_CourtyardFloor", "ground_albedo.jpg", "ground_normal.png", "ground_orm.png", normal_strength=1.35)
    mat_earth = make_pbr_material("Mat_MossyEarth", "earth_moss_albedo.jpg", "earth_moss_normal.png", "earth_moss_orm.png", normal_strength=1.25)
    mat_stone = make_pbr_material("Mat_RuinStone", "masonry_albedo.jpg", "masonry_normal.png", "masonry_orm.png", normal_strength=1.35)
    mat_stone_dark = make_pbr_material("Mat_MidgroundRuins", "masonry_albedo.jpg", "masonry_normal.png", "masonry_orm.png", normal_strength=1.10, base_tint=(0.72, 0.76, 0.78))
    mat_wood = make_pbr_material("Mat_VineWood", "dark_wood_albedo.jpg", "dark_wood_normal.png", "dark_wood_orm.png", normal_strength=1.20)
    mat_vines = make_vines_material()
    mat_iron = make_iron_material()
    mat_ember = make_ember_material()
    mat_sky = make_sky_material()

    # 1. SCULPTED ANCIENT FLAGSTONE COURTYARD DECK
    bm_floor = bmesh.new()
    uv_f = bm_floor.loops.layers.uv.verify()
    nx, ny = 36, 18
    x0, x1 = -10.0, 20.0
    y0, y1 = -5.5, 4.2
    verts = []
    for j in range(ny + 1):
        row = []
        ty = j / ny
        y = y0 + (y1 - y0) * ty
        for i in range(nx + 1):
            tx = i / nx
            x = x0 + (x1 - x0) * tx
            lane_dist = max(0.0, abs(y) - 1.1)
            undul = (math.sin(x * 0.9 + y * 1.1) * 0.024 + math.cos(x * 2.1 - y * 1.7) * 0.012) * min(1.0, lane_dist / 1.5)
            z = -0.02 + undul
            row.append(bm_floor.verts.new((x, y, z)))
        verts.append(row)
    for j in range(ny):
        for i in range(nx):
            f = bm_floor.faces.new([verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]])
            f.smooth = True
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_f].uv = (co.x * 0.36, co.y * 0.36)
    build_object("Courtyard_Flagstones", bm_floor, mat_ground)

    # 2. SCULPTED MOSSY EARTH & GRAVEL TERRACE SHOULDERS / EMBANKMENTS
    bm_earth = bmesh.new()
    uv_e = bm_earth.loops.layers.uv.verify()
    enx, eny = 40, 20
    ex0, ex1 = -16.0, 26.0
    ey0, ey1 = 2.6, 16.5
    everts = []
    for j in range(eny + 1):
        row = []
        ty = j / eny
        y = ey0 + (ey1 - ey0) * ty
        for i in range(enx + 1):
            tx = i / enx
            x = ex0 + (ex1 - ex0) * tx
            terrace_h = 0.44 * min(1.0, max(0.0, (y - 2.75) / 0.85))
            valley_drop = -1.25 * min(1.0, max(0.0, (y - 6.8) / 4.5))
            flank_rise = (0.75 * max(0.0, (abs(x - 5.0) - 7.5) / 8.0)) * (1.0 - max(0.0, (y - 10.0) / 6.5))
            noise = math.sin(x * 0.55 + y * 0.7) * 0.14 + math.cos(x * 1.3 - y * 0.9) * 0.07
            z = -0.05 + terrace_h + valley_drop + flank_rise + noise * min(1.0, ty * 2.5)
            row.append(bm_earth.verts.new((x, y, z)))
        everts.append(row)
    for j in range(eny):
        for i in range(enx):
            f = bm_earth.faces.new([everts[j][i], everts[j][i + 1], everts[j + 1][i + 1], everts[j + 1][i]])
            f.smooth = True
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_e].uv = (co.x * 0.30, co.y * 0.30)
    build_object("Courtyard_MossyTerrain", bm_earth, mat_earth)

    # 3. SCULPTED 3D STONE SANCTUARY RUINS, VAULTED ARCHES, STEPS & RUBBLE
    bm_stone = bmesh.new()
    bm_iron = bmesh.new()
    bm_ember = bmesh.new()

    terrace_z = 0.42
    # 3a. Individual weathered retaining terrace curb blocks + central carved ancient stone stairs
    for cx in [x * 1.18 - 6.5 for x in range(21)]:
        if 3.1 < cx < 6.9:
            continue
        h_var = rng.uniform(0.44, 0.52)
        add_weathered_block(bm_stone, (cx, 2.85, h_var * 0.5 - 0.02), (1.14, 0.54, h_var), bevel=0.045, chip=0.025, rng=rng)
    for step_idx in range(3):
        sz = 0.15 * (step_idx + 1)
        sy = 2.48 + step_idx * 0.36
        sw = 3.85 - step_idx * 0.18
        add_weathered_block(bm_stone, (5.0, sy, sz * 0.5 - 0.02), (sw, 0.40, sz), bevel=0.035, chip=0.018, rng=rng)

    # 3b. Low carved ruined stone parapet balustrades along the terrace rim
    for bx in [-4.6, -2.5, 0.4, 9.6, 12.5, 14.6]:
        bh = rng.uniform(0.42, 0.54)
        add_weathered_block(bm_stone, (bx, 3.35, terrace_z + bh * 0.5), (1.42, 0.36, bh), bevel=0.04, chip=0.024, rng=rng)
        if abs(bx - 5.0) < 9.0:
            add_weathered_block(bm_stone, (bx, 3.35, terrace_z + bh + 0.045), (1.52, 0.44, 0.09), bevel=0.028, chip=0.015, rng=rng)

    # 3c. Main Sculpted Vaulted Sanctuary Colonnade (proportioned so FULL curved stone arches frame inside 34° FOV!)
    col_y = 4.65
    # Grand central arch columns (x = 2.6, 7.4) + curved voussoir arch (spring=2.12m, crown=4.18m — cleanly visible at top!)
    add_octagonal_column(bm_stone, 2.6, col_y, terrace_z, height=1.80, radius=0.36, rng=rng, broken_top=False)
    add_octagonal_column(bm_stone, 7.4, col_y, terrace_z, height=1.80, radius=0.36, rng=rng, broken_top=False)
    add_voussoir_arch(bm_stone, 5.0, col_y, spring_z=terrace_z + 1.72, span_radius=2.15, arch_thick=0.48, arch_depth=0.72, rng=rng, segments=15)

    # Flanking full vaulted side arches (left center x=-0.1, right center x=10.1, crown=3.75m!)
    add_octagonal_column(bm_stone, -2.8, col_y, terrace_z, height=1.68, radius=0.34, rng=rng, broken_top=False)
    add_voussoir_arch(bm_stone, -0.1, col_y, spring_z=terrace_z + 1.60, span_radius=2.35, arch_thick=0.44, arch_depth=0.66, rng=rng, segments=13)

    add_octagonal_column(bm_stone, 12.8, col_y, terrace_z, height=1.68, radius=0.34, rng=rng, broken_top=False)
    add_voussoir_arch(bm_stone, 10.1, col_y, spring_z=terrace_z + 1.60, span_radius=2.35, arch_thick=0.44, arch_depth=0.66, rng=rng, segments=13)

    # Outer half-collapsed broken ruin columns & partial arches
    add_octagonal_column(bm_stone, -6.4, col_y + 0.3, terrace_z, height=1.95, radius=0.34, rng=rng, broken_top=True)
    add_voussoir_arch(bm_stone, -4.6, col_y, spring_z=terrace_z + 1.60, span_radius=1.60, arch_thick=0.42, arch_depth=0.62, rng=rng, segments=11, collapsed_side="left")

    add_octagonal_column(bm_stone, 16.4, col_y + 0.3, terrace_z, height=1.85, radius=0.34, rng=rng, broken_top=True)
    add_voussoir_arch(bm_stone, 14.6, col_y, spring_z=terrace_z + 1.60, span_radius=1.60, arch_thick=0.42, arch_depth=0.62, rng=rng, segments=11, collapsed_side="right")

    # 3d. Fallen broken stone rubble
    rubble_specs = [
        (-1.2, 3.65, 0.58, (0.72, 0.56, 0.36), (0.08, -0.14, 0.42)),
        (1.15, 3.85, 0.55, (0.54, 0.46, 0.30), (-0.05, 0.12, -0.35)),
        (8.85, 3.75, 0.56, (0.64, 0.50, 0.34), (0.10, 0.08, 0.65)),
        (11.2, 3.65, 0.60, (0.78, 0.54, 0.38), (-0.12, -0.06, -0.50)),
        (-5.2, 2.55, 0.22, (0.95, 0.68, 0.48), (0.06, 0.10, 0.30)),
        (15.2, 2.55, 0.22, (0.90, 0.65, 0.46), (-0.05, -0.12, -0.45)),
        (-1.8, -3.55, 0.14, (1.15, 0.82, 0.48), (0.08, -0.05, 0.25)),
        (11.8, -3.55, 0.14, (1.10, 0.80, 0.46), (-0.06, 0.07, -0.28)),
    ]
    for rx, ry, rz, rsz, rrot in rubble_specs:
        add_weathered_block(bm_stone, (rx, ry, rz), rsz, bevel=0.055, chip=0.04, rot_euler=rrot, rng=rng)

    # 3e. Two Sculpted Ancient Temple Stone Braziers flanking the central steps
    add_stone_brazier(bm_stone, bm_iron, bm_ember, 2.25, 3.12, terrace_z, rng)
    add_stone_brazier(bm_stone, bm_iron, bm_ember, 7.75, 3.12, terrace_z, rng)

    build_object("Sanctuary_RuinsStone", bm_stone, mat_stone, auto_uv_scale=0.58)
    build_object("Sanctuary_BrazierIron", bm_iron, mat_iron, auto_uv_scale=1.2)
    build_object("Sanctuary_BrazierEmbers", bm_ember, mat_ember)

    # 4. MIDGROUND 3D BROKEN CLOISTER RUINS (y = 10.5..12.5 — real parallax depth!)
    bm_mid = bmesh.new()
    mid_y = 10.8
    mid_z = -0.15
    for mx in [-5.8, -1.6, 1.9, 8.1, 11.6, 15.8]:
        h_m = rng.uniform(2.5, 3.6)
        broken = abs(mx - 5.0) > 7.0 or mx in (-1.6, 11.6)
        add_octagonal_column(bm_mid, mx, mid_y + rng.uniform(-0.7, 0.7), mid_z, height=h_m, radius=0.40, rng=rng, broken_top=broken)
    add_voussoir_arch(bm_mid, -3.7, mid_y, spring_z=mid_z + 2.5, span_radius=1.9, arch_thick=0.46, arch_depth=0.68, rng=rng, segments=11)
    add_voussoir_arch(bm_mid, 13.7, mid_y, spring_z=mid_z + 2.5, span_radius=1.9, arch_thick=0.46, arch_depth=0.68, rng=rng, segments=11)
    add_weathered_block(bm_mid, (0.6, 9.2, 1.05), (0.88, 0.50, 2.4), bevel=0.06, chip=0.05, rot_euler=(0.04, 0.06, 0.18), rng=rng)
    add_weathered_block(bm_mid, (9.4, 9.4, 1.15), (0.95, 0.52, 2.6), bevel=0.06, chip=0.05, rot_euler=(-0.03, -0.05, -0.22), rng=rng)
    build_object("Sanctuary_MidgroundCloister", bm_mid, mat_stone_dark, auto_uv_scale=0.44)

    # 5. REAL 3D GNARLED WOODY CLIMBING VINES + VOLUMETRIC CRIMSON MAPLE CANOPIES
    bm_wood = bmesh.new()
    bm_vines = bmesh.new()

    vine_curves = [
        [(2.25, 4.28, 0.44), (2.82, 4.30, 1.15), (2.42, 4.26, 1.95), (2.92, 4.28, 2.85), (3.55, 4.32, 3.65), (4.35, 4.34, 4.25)],
        [(7.75, 4.28, 0.44), (7.18, 4.30, 1.20), (7.56, 4.26, 2.05), (7.08, 4.28, 2.90), (6.45, 4.32, 3.70), (5.65, 4.34, 4.28)],
        [(-2.50, 4.30, 0.44), (-2.98, 4.28, 1.30), (-2.62, 4.26, 2.15), (-1.70, 4.30, 3.30), (-0.60, 4.32, 3.90)],
        [(12.50, 4.30, 0.44), (12.98, 4.28, 1.25), (12.60, 4.26, 2.10), (11.70, 4.30, 3.25), (10.60, 4.32, 3.85)],
    ]
    for pts in vine_curves:
        add_woody_vine_branch(bm_wood, pts, r_start=0.072, r_end=0.022, sides=6)

    foliage_specs = [
        # Lush crimson maple + ivy drapes cascading cleanly over our newly framed central & flanking arches!
        ((2.65, 4.22, 3.65), 1.40, 2.45, 0, 0.10),
        ((3.20, 4.24, 4.30), 1.25, 1.95, 3, -0.18),
        ((7.35, 4.22, 3.70), 1.40, 2.50, 3, -0.12),
        ((6.80, 4.24, 4.30), 1.25, 1.90, 1, 0.16),
        ((5.00, 4.26, 4.70), 1.35, 1.55, 2, 0.05),
        ((-0.10, 4.24, 4.35), 1.35, 2.05, 2, 0.08),
        ((-2.75, 4.22, 3.35), 1.40, 2.35, 1, -0.15),
        ((10.10, 4.24, 4.35), 1.35, 2.05, 0, -0.08),
        ((12.75, 4.22, 3.35), 1.40, 2.35, 3, 0.15),
        ((0.40, 3.12, 1.30), 1.05, 1.15, 2, 0.20),
        ((9.60, 3.12, 1.30), 1.05, 1.15, 1, -0.20),
    ]
    for pos, fw, fh, quad, yaw in foliage_specs:
        add_volumetric_vine_cluster(bm_vines, pos, fw, fh, quadrant=quad, base_yaw=yaw, drape_forward=0.18)

    build_object("Sanctuary_WoodyVines", bm_wood, mat_wood, auto_uv_scale=1.4)
    build_object("Sanctuary_CrimsonFoliage", bm_vines, mat_vines)

    # =========================================================================
    # 6. CURVED PAINTERLY MISTY MOUNTAIN VALLEY SKY CYCLORAMA DOME (y = +21.5)
    # =========================================================================
    bm_sky = bmesh.new()
    uv_s = bm_sky.loops.layers.uv.verify()
    # Curved panoramic arc centered at arena midpoint (x=5, y=0) at radius 22.5m
    # Spans azimuth -68 deg to +68 deg (covers every possible iPhone/iPad pan with margin!)
    # Vertical height z = -2.2m to +12.2m so sunbeams, mountain peaks & distant temple citadel frame RIGHT through the central arch!
    arc_segs = 32
    v_segs = 6
    radius = 22.5
    ang_min, ang_max = math.radians(-68.0), math.radians(68.0)
    z_bot, z_top = -2.2, 12.0
    sgrid = []
    for j in range(v_segs + 1):
        tv = j / v_segs
        z = z_bot + (z_top - z_bot) * tv
        row = []
        for i in range(arc_segs + 1):
            tu = i / arc_segs
            ang = ang_min + (ang_max - ang_min) * tu
            x = 5.0 + math.sin(ang) * radius
            y = math.cos(ang) * radius
            row.append((bm_sky.verts.new((x, y, z)), tu, tv))
        sgrid.append(row)
    for j in range(v_segs):
        for i in range(arc_segs):
            v00, u00, w00 = sgrid[j][i]
            v10, u10, w10 = sgrid[j][i + 1]
            v11, u11, w11 = sgrid[j + 1][i + 1]
            v01, u01, w01 = sgrid[j + 1][i]
            # Face inward toward camera (-Y)
            f = bm_sky.faces.new([v00, v01, v11, v10])
            f.smooth = True
            for loop, uv in zip(f.loops, [(u00, w00), (u01, w01), (u11, w11), (u10, w10)]):
                loop[uv_s].uv = uv
    build_object("Sanctuary_SkyCyclorama", bm_sky, mat_sky)

    # Export clean glTF 2.0 binary (.glb)
    total_tris = sum(len(o.data.polygons) * 2 for o in bpy.data.objects if o.type == "MESH")
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_cameras=False,
        export_lights=False,
    )
    mb = OUT_GLB.stat().st_size / (1024 * 1024)
    print(f"[stage] exported {OUT_GLB} ({mb:.2f} MB, ~{total_tris} tris, {len(bpy.data.objects)} meshes)")


if __name__ == "__main__":
    build_stage()
