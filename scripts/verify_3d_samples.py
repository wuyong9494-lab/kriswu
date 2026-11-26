#!/usr/bin/env python3
"""
Real end-to-end verification suite for WUMIND「AI 3D 空间工坊」3D Technical Library samples:
  1. CAD Mechanical (ezdxf 1.4.5 + CadQuery 2.8.0):
     - Generates native parametric Python source + 2D DXF (OUTLINE/HOLES/DIMENSIONS) + ISO STEP
       for a 160x120x10mm 4-hole mounting plate (pitch 120x80mm).
     - Mutates hole spacing to 130x90mm, regenerates DXF + STEP, and externally re-opens BOTH
       DXF & STEP to assert exact dimensions, hole center coordinates, diameter, and net solid volume.
  2. Architecture / Interior BIM (IfcOpenShell 0.9.0.post1):
     - Generates IFC4 apartment storey (5200x4400x2800mm) with 4 walls, IfcOpeningElement void,
       IfcDoor fill, and Pset_WuMindDimensionSource (`标注尺寸` vs `扫描值` vs `估算值`).
     - Moves ONLY the door & opening from X=1800mm to X=2400mm (+600mm), exports updated IFC4,
       and externally re-opens BOTH IFC files via ifcopenshell.open() to assert exact placement & voids.
  3. Large Game Scene — Red River Town (赤河镇):
     - Exports .wumind3d.json, binary glTF 2.0 .glb (verified via trimesh.load), and Godot 4 .tscn
       with StaticBody3D colliders, plus geometric walkability check from Saloon -> Bridge -> Station.
  4. Rigged Humanoid Character Audit:
     - Inspects App/Resources/DuelCharacters/DuelChar_wuYong.glb glTF JSON chunk for skins, joints,
       animation clips, and metric height.
  5. Generates 4-panel visual proof sheet PNG for human visual inspection.
"""
import json
import math
import os
import struct
import sys
from pathlib import Path

import cadquery as cq
import ezdxf
import ifcopenshell
import ifcopenshell.api
import numpy as np
import trimesh
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
SAMPLES_DIR = REPO_ROOT / "Samples" / "WuMind3D"
ARTIFACT_DIR = Path(
    os.environ.get(
        "WUMIND_ARTIFACT_DIR",
        "/home/antigravity/.gemini/jetski/brain/v1/default/jetski_remote_agents_3p_devbox/f45c01f0-90cf-4537-a9d6-42bfc0dff771",
    )
)


# =============================================================================
# 1. CAD 4-HOLE MOUNTING PLATE (ezdxf + CadQuery STEP)
# =============================================================================

PARAMETRIC_SOURCE_TEMPLATE = '''#!/usr/bin/env python3
"""
Native Parametric CAD Source for WUMIND 4-Hole Mounting Plate.
NOTE: Keep this native .py (or FreeCAD .FCStd) as the editable parametric master!
Exported STEP (.step) and GLB (.glb) are geometry exchange formats and do NOT preserve full feature history.
DWG compatibility must be validated separately via ODA File Converter / LibreDWG.
"""
import cadquery as cq

def build_mounting_plate(
    width_mm: float = 160.0,
    depth_mm: float = 120.0,
    thickness_mm: float = 10.0,
    hole_pitch_x_mm: float = 120.0,
    hole_pitch_y_mm: float = 80.0,
    hole_diameter_mm: float = 10.0,
) -> cq.Workplane:
    return (
        cq.Workplane("XY")
        .box(width_mm, depth_mm, thickness_mm)
        .faces(">Z")
        .workplane()
        .rect(hole_pitch_x_mm, hole_pitch_y_mm, forConstruction=True)
        .vertices()
        .hole(hole_diameter_mm)
    )
'''


def generate_cad_plate_pair(out_dir: Path, pitch_x: float, pitch_y: float):
    width, depth, thickness, hole_d = 160.0, 120.0, 10.0, 10.0
    stem = f"plate_{int(pitch_x)}x{int(pitch_y)}"

    # A. 2D DXF via ezdxf with explicit layers + linear dimension annotations
    doc = ezdxf.new("R2018")
    doc.units = ezdxf.units.MM
    doc.layers.add("OUTLINE", color=7)
    doc.layers.add("HOLES", color=1)
    doc.layers.add("CENTERLINES", color=3)
    doc.layers.add("DIMENSIONS", color=5)
    msp = doc.modelspace()

    hw, hd = width / 2.0, depth / 2.0
    msp.add_lwpolyline(
        [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd), (-hw, -hd)],
        dxfattribs={"layer": "OUTLINE"},
    )
    hx, hy = pitch_x / 2.0, pitch_y / 2.0
    centers = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    for cx, cy in centers:
        msp.add_circle((cx, cy), radius=hole_d / 2.0, dxfattribs={"layer": "HOLES"})
        msp.add_line((cx - 8, cy), (cx + 8, cy), dxfattribs={"layer": "CENTERLINES"})
        msp.add_line((cx, cy - 8), (cx, cy + 8), dxfattribs={"layer": "CENTERLINES"})

    # Add real CAD linear dimension annotations
    dim_w = msp.add_linear_dim(base=(0, hd + 18), p1=(-hw, hd), p2=(hw, hd), dxfattribs={"layer": "DIMENSIONS"})
    dim_w.render()
    dim_px = msp.add_linear_dim(base=(0, -hd - 18), p1=(-hx, -hy), p2=(hx, -hy), dxfattribs={"layer": "DIMENSIONS"})
    dim_px.render()
    dim_py = msp.add_linear_dim(base=(hw + 18, 0), p1=(hx, -hy), p2=(hx, hy), angle=90, dxfattribs={"layer": "DIMENSIONS"})
    dim_py.render()

    dxf_path = out_dir / f"{stem}.dxf"
    doc.saveas(dxf_path)

    # B. 3D Parametric B-Rep Solid -> ISO STEP via CadQuery
    solid = (
        cq.Workplane("XY")
        .box(width, depth, thickness)
        .faces(">Z")
        .workplane()
        .rect(pitch_x, pitch_y, forConstruction=True)
        .vertices()
        .hole(hole_d)
    )
    step_path = out_dir / f"{stem}.step"
    cq.exporters.export(solid, str(step_path), exportType="STEP")

    # C. External Independent Verification: Re-open DXF & STEP from disk!
    reopened_dxf = ezdxf.readfile(dxf_path)
    circles = list(reopened_dxf.modelspace().query('CIRCLE[layer=="HOLES"]'))
    assert len(circles) == 4, f"Expected 4 holes in DXF, got {len(circles)}"
    dxf_centers = sorted([(round(c.dxf.center.x, 3), round(c.dxf.center.y, 3)) for c in circles])
    expected_centers = sorted([(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)])
    assert dxf_centers == expected_centers, f"DXF hole centers mismatch: {dxf_centers} != {expected_centers}"
    for c in circles:
        assert math.isclose(c.dxf.radius, hole_d / 2.0, abs_tol=1e-4)

    reopened_step = cq.importers.importStep(str(step_path))
    bb = reopened_step.val().BoundingBox()
    assert math.isclose(bb.xlen, width, abs_tol=1e-3), f"STEP width mismatch: {bb.xlen}"
    assert math.isclose(bb.ylen, depth, abs_tol=1e-3), f"STEP depth mismatch: {bb.ylen}"
    assert math.isclose(bb.zlen, thickness, abs_tol=1e-3), f"STEP thickness mismatch: {bb.zlen}"
    expected_vol = width * depth * thickness - 4.0 * math.pi * ((hole_d / 2.0) ** 2) * thickness
    actual_vol = reopened_step.val().Volume()
    assert math.isclose(actual_vol, expected_vol, rel_tol=1e-4), f"STEP volume mismatch: {actual_vol} vs {expected_vol}"

    # Verify cylindrical hole face centers inside re-opened STEP
    cyl_centers = []
    for face in reopened_step.faces().vals():
        if face.geomType() == "CYLINDER":
            c = face.Center()
            cyl_centers.append((round(c.x, 2), round(c.y, 2)))
    cyl_centers_sorted = sorted(cyl_centers)
    assert len(cyl_centers_sorted) == 4, f"Expected 4 cylindrical hole faces in STEP, got {len(cyl_centers_sorted)}"
    assert cyl_centers_sorted == expected_centers, f"STEP hole centers mismatch: {cyl_centers_sorted} != {expected_centers}"

    return {
        "dxfPath": str(dxf_path.relative_to(REPO_ROOT)),
        "stepPath": str(step_path.relative_to(REPO_ROOT)),
        "widthMM": width,
        "depthMM": depth,
        "thicknessMM": thickness,
        "holePitchXMM": pitch_x,
        "holePitchYMM": pitch_y,
        "holeDiameterMM": hole_d,
        "verifiedDXFHoleCentersMM": dxf_centers,
        "verifiedSTEPHoleCentersMM": cyl_centers_sorted,
        "verifiedSTEPVolumeMM3": round(actual_vol, 2),
        "verifiedSTEPBytes": step_path.stat().st_size,
        "verifiedDXFBytes": dxf_path.stat().st_size,
    }


def verify_cad_samples():
    cad_dir = SAMPLES_DIR / "cad_mounting_plate"
    cad_dir.mkdir(parents=True, exist_ok=True)
    src_path = cad_dir / "mounting_plate_parametric.py"
    src_path.write_text(PARAMETRIC_SOURCE_TEMPLATE, encoding="utf-8")

    v1 = generate_cad_plate_pair(cad_dir, pitch_x=120.0, pitch_y=80.0)
    v2 = generate_cad_plate_pair(cad_dir, pitch_x=130.0, pitch_y=90.0)
    assert v1["verifiedSTEPHoleCentersMM"] != v2["verifiedSTEPHoleCentersMM"]
    return {
        "status": "PASS",
        "toolVersions": {"ezdxf": ezdxf.__version__, "cadquery": cq.__version__},
        "nativeParametricSource": str(src_path.relative_to(REPO_ROOT)),
        "historyCaveat": "原生参数工程保存在 .py / .FCStd；STEP 与 GLB 仅为几何交换文件，不保留建模历史；DWG 需经 ODA/LibreDWG 单独验证。",
        "v1_120x80": v1,
        "v2_130x90": v2,
    }


# =============================================================================
# 2. BIM / INTERIOR FLOORPLAN WITH MOVABLE DOOR (IfcOpenShell IFC4)
# =============================================================================

def build_ifc_floorplan(ifc_path: Path, door_x_m: float):
    model = ifcopenshell.api.run("project.create_file", version="IFC4")
    project = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcProject", name="WuMind_BIM_Floorplan")
    ifcopenshell.api.run("unit.assign_unit", model, length={"is_metric": True, "raw": "METERS"})
    ctx = ifcopenshell.api.run("context.add_context", model, context_type="Model")
    body = ifcopenshell.api.run(
        "context.add_context",
        model,
        context_type="Model",
        context_identifier="Body",
        target_view="MODEL_VIEW",
        parent=ctx,
    )

    site = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcSite", name="Site")
    building = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcBuilding", name="Apartment")
    storey = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcBuildingStorey", name="1F_KitchenDining")
    ifcopenshell.api.run("aggregate.assign_object", model, relating_object=project, products=[site])
    ifcopenshell.api.run("aggregate.assign_object", model, relating_object=site, products=[building])
    ifcopenshell.api.run("aggregate.assign_object", model, relating_object=building, products=[storey])

    def place_matrix(x: float, y: float, z: float, rot_z_rad: float = 0.0):
        c, s = math.cos(rot_z_rad), math.sin(rot_z_rad)
        return np.array(
            [
                [c, -s, 0.0, x],
                [s, c, 0.0, y],
                [0.0, 0.0, 1.0, z],
                [0.0, 0.0, 0.0, 1.0],
            ],
            dtype=float,
        )

    # 4 perimeter walls: 5.2m (X) x 4.4m (Y) x 2.8m (H), thickness 0.2m
    walls_spec = [
        ("SouthWall", 5.2, 0.2, 2.8, 0.0, 0.0, 0.0, "标注尺寸"),
        ("NorthWall", 5.2, 0.2, 2.8, 0.0, 4.2, 0.0, "标注尺寸"),
        ("WestWall", 4.4, 0.2, 2.8, 0.2, 0.0, math.pi / 2.0, "扫描值"),
        ("EastWall", 4.4, 0.2, 2.8, 5.2, 0.0, math.pi / 2.0, "估算值"),
    ]
    south_wall = None
    for name, length, thick, height, x, y, rot, dim_source in walls_spec:
        wall = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcWall", name=name)
        ifcopenshell.api.run("spatial.assign_container", model, relating_structure=storey, products=[wall])
        rep = ifcopenshell.api.run(
            "geometry.add_wall_representation", model, context=body, length=length, height=height, thickness=thick
        )
        ifcopenshell.api.run("geometry.assign_representation", model, product=wall, representation=rep)
        ifcopenshell.api.run("geometry.edit_object_placement", model, product=wall, matrix=place_matrix(x, y, 0.0, rot))
        pset = ifcopenshell.api.run("pset.add_pset", model, product=wall, name="Pset_WuMindDimensionSource")
        ifcopenshell.api.run(
            "pset.edit_pset",
            model,
            pset=pset,
            properties={"DimensionSource": dim_source, "LengthMM": round(length * 1000), "HeightMM": round(height * 1000)},
        )
        if name == "SouthWall":
            south_wall = wall

    # Opening void inside SouthWall + Door filling that opening (width 0.90m, height 2.10m)
    opening = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcOpeningElement", name="SouthDoorOpening")
    open_rep = ifcopenshell.api.run(
        "geometry.add_wall_representation", model, context=body, length=0.90, height=2.10, thickness=0.30
    )
    ifcopenshell.api.run("geometry.assign_representation", model, product=opening, representation=open_rep)
    ifcopenshell.api.run("geometry.edit_object_placement", model, product=opening, matrix=place_matrix(door_x_m, -0.05, 0.0))
    ifcopenshell.api.run("feature.add_feature", model, feature=opening, element=south_wall)

    door = ifcopenshell.api.run("root.create_entity", model, ifc_class="IfcDoor", name="MainEntryDoor")
    door.OverallWidth = 0.90
    door.OverallHeight = 2.10
    ifcopenshell.api.run("spatial.assign_container", model, relating_structure=storey, products=[door])
    door_rep = ifcopenshell.api.run(
        "geometry.add_wall_representation", model, context=body, length=0.90, height=2.10, thickness=0.06
    )
    ifcopenshell.api.run("geometry.assign_representation", model, product=door, representation=door_rep)
    ifcopenshell.api.run("geometry.edit_object_placement", model, product=door, matrix=place_matrix(door_x_m, 0.07, 0.0))
    ifcopenshell.api.run("feature.add_filling", model, opening=opening, element=door)
    d_pset = ifcopenshell.api.run("pset.add_pset", model, product=door, name="Pset_WuMindDimensionSource")
    ifcopenshell.api.run(
        "pset.edit_pset",
        model,
        pset=d_pset,
        properties={
            "DimensionSource": "标注尺寸",
            "DoorOffsetXMM": round(door_x_m * 1000),
            "DoorWidthMM": 900,
            "ClearLeftWallMM": round(door_x_m * 1000),
            "ClearRightWallMM": round((5.2 - door_x_m - 0.9) * 1000),
        },
    )
    model.write(str(ifc_path))


def inspect_ifc_external(ifc_path: Path):
    f = ifcopenshell.open(str(ifc_path))
    storeys = f.by_type("IfcBuildingStorey")
    walls = f.by_type("IfcWall")
    openings = f.by_type("IfcOpeningElement")
    doors = f.by_type("IfcDoor")
    voids = f.by_type("IfcRelVoidsElement")
    fills = f.by_type("IfcRelFillsElement")

    assert len(storeys) == 1
    assert len(walls) == 4
    assert len(openings) == 1
    assert len(doors) == 1
    assert len(voids) == 1
    assert len(fills) == 1

    import ifcopenshell.util.element as ifc_elem
    import ifcopenshell.util.placement as ifc_place

    door_m = ifc_place.get_local_placement(doors[0].ObjectPlacement)
    open_m = ifc_place.get_local_placement(openings[0].ObjectPlacement)
    door_psets = ifc_elem.get_psets(doors[0]).get("Pset_WuMindDimensionSource", {})
    wall_sources = {
        w.Name: ifc_elem.get_psets(w).get("Pset_WuMindDimensionSource", {}).get("DimensionSource")
        for w in walls
    }
    return {
        "ifcPath": str(ifc_path.relative_to(REPO_ROOT)),
        "schema": f.schema,
        "storeyCount": len(storeys),
        "wallCount": len(walls),
        "openingCount": len(openings),
        "doorCount": len(doors),
        "doorXMM": round(float(door_m[0, 3]) * 1000.0, 1),
        "openingXMM": round(float(open_m[0, 3]) * 1000.0, 1),
        "doorClearLeftMM": door_psets.get("ClearLeftWallMM"),
        "doorClearRightMM": door_psets.get("ClearRightWallMM"),
        "wallDimensionSources": wall_sources,
        "fileBytes": ifc_path.stat().st_size,
    }


def verify_bim_samples():
    bim_dir = SAMPLES_DIR / "bim_floorplan"
    bim_dir.mkdir(parents=True, exist_ok=True)
    ifc_before = bim_dir / "apartment_door_x1800.ifc"
    ifc_after = bim_dir / "apartment_door_x2400.ifc"
    build_ifc_floorplan(ifc_before, door_x_m=1.80)
    build_ifc_floorplan(ifc_after, door_x_m=2.40)

    before_info = inspect_ifc_external(ifc_before)
    after_info = inspect_ifc_external(ifc_after)
    assert math.isclose(before_info["doorXMM"], 1800.0, abs_tol=0.5)
    assert math.isclose(before_info["openingXMM"], 1800.0, abs_tol=0.5)
    assert math.isclose(after_info["doorXMM"], 2400.0, abs_tol=0.5)
    assert math.isclose(after_info["openingXMM"], 2400.0, abs_tol=0.5)
    assert after_info["doorClearLeftMM"] == 2400 and after_info["doorClearRightMM"] == 1900
    assert set(before_info["wallDimensionSources"].values()) == {"标注尺寸", "扫描值", "估算值"}
    return {
        "status": "PASS",
        "toolVersion": ifcopenshell.version,
        "before_door_x1800": before_info,
        "after_door_x2400": after_info,
    }


# =============================================================================
# 3. RED RIVER TOWN (赤河镇) — JSON + GLB + GODOT 4 .TSCN + WALKABILITY CHECK
# =============================================================================

RED_RIVER_NODES = [
    {"name": "赤河河道水面", "category": "waterway", "pos": (0, -0.30, 0), "size": (14.0, 0.22, 100.0), "color": (140, 74, 50, 224)},
    {"name": "赤河西岸台地（酒馆区）", "category": "courtyard", "pos": (-29.0, 0.0, 0), "size": (44.0, 0.24, 96.0), "color": (185, 139, 98, 255)},
    {"name": "赤河东岸台地（车站区）", "category": "courtyard", "pos": (29.0, 0.0, 0), "size": (44.0, 0.24, 96.0), "color": (181, 134, 94, 255)},
    {"name": "西部主街（西段 · 酒馆门前）", "category": "road", "pos": (-27.0, 0.24, 0), "size": (34.0, 0.12, 9.0), "color": (156, 115, 78, 255)},
    {"name": "赤河木石主桥桥面", "category": "road", "pos": (0.0, 0.24, 0), "size": (20.4, 0.16, 8.4), "color": (122, 82, 51, 255)},
    {"name": "主桥北侧木护栏", "category": "cityWall", "pos": (0.0, 0.40, -4.0), "size": (20.4, 1.05, 0.32), "color": (91, 59, 36, 255)},
    {"name": "主桥南侧木护栏", "category": "cityWall", "pos": (0.0, 0.40, 4.0), "size": (20.4, 1.05, 0.32), "color": (91, 59, 36, 255)},
    {"name": "西部主街（东段 · 车站门前）", "category": "road", "pos": (27.0, 0.24, 0), "size": (34.0, 0.12, 9.0), "color": (156, 115, 78, 255)},
    {"name": "赤河西部酒馆（Saloon）", "category": "wall", "pos": (-24.0, 0.24, -15.5), "size": (16.0, 7.6, 12.0), "color": (139, 84, 47, 255)},
    {"name": "酒馆二层木廊台与招牌檐", "category": "roof", "pos": (-24.0, 7.84, -15.5), "size": (17.2, 1.8, 13.4), "color": (94, 56, 32, 255)},
    {"name": "赤河火车站主站房", "category": "wall", "pos": (25.0, 0.24, -16.0), "size": (20.0, 6.8, 11.0), "color": (138, 59, 43, 255)},
    {"name": "火车站坡屋顶与站台雨棚", "category": "roof", "pos": (25.0, 7.04, -15.5), "size": (22.0, 2.2, 14.0), "color": (60, 62, 68, 255)},
    {"name": "赤河火车站铁轨与枕木路基", "category": "road", "pos": (26.0, 0.24, -26.5), "size": (42.0, 0.20, 3.6), "color": (74, 72, 71, 255)},
    {"name": "西部铁匠铺与补给行", "category": "wall", "pos": (-22.0, 0.24, 14.5), "size": (13.0, 5.2, 10.0), "color": (122, 106, 91, 255)},
    {"name": "治安官办公室与邮局", "category": "wall", "pos": (22.0, 0.24, 14.5), "size": (13.0, 5.4, 10.0), "color": (154, 107, 70, 255)},
]


def verify_red_river_town():
    out_dir = SAMPLES_DIR / "red_river_town"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Build independent multi-node glTF 2.0 Scene via trimesh
    scene = trimesh.Scene()
    for n in RED_RIVER_NODES:
        sx, sy, sz = n["size"]
        cx, base_y, cz = n["pos"]
        mesh = trimesh.creation.box(extents=[sx, sy, sz])
        mesh.apply_translation([cx, base_y + sy / 2.0, cz])
        mesh.visual.vertex_colors = np.tile(np.array(n["color"], dtype=np.uint8), (len(mesh.vertices), 1))
        scene.add_geometry(mesh, node_name=n["name"], geom_name=n["name"])

    glb_path = out_dir / "red_river_town.glb"
    glb_bytes = scene.export(file_type="glb")
    glb_path.write_bytes(glb_bytes)

    # Re-open externally with trimesh.load to verify independent landmarks!
    reopened = trimesh.load(str(glb_path), force="scene")
    geom_names = list(reopened.geometry.keys())
    for required in ["赤河河道水面", "赤河木石主桥桥面", "赤河火车站主站房", "赤河西部酒馆（Saloon）"]:
        assert any(required in g for g in geom_names), f"Missing landmark {required} in GLB: {geom_names}"

    # 2. Export Godot 4 .tscn with StaticBody3D colliders
    collidable = [n for n in RED_RIVER_NODES if n["category"] != "waterway"]
    tscn_lines = [
        f"[gd_scene load_steps={2 + len(collidable)} format=3]",
        "",
        '[ext_resource type="PackedScene" path="res://red_river_town.glb" id="1_model"]',
        "",
        '[sub_resource type="Environment" id="Environment_main"]',
        "background_mode = 1",
        "",
    ]
    for i, n in enumerate(collidable, 1):
        sx, sy, sz = n["size"]
        tscn_lines.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{i}"]')
        tscn_lines.append(f"size = Vector3({sx:.3f}, {sy:.3f}, {sz:.3f})")
        tscn_lines.append("")
    tscn_lines.extend([
        '[node name="RedRiverTownRoot" type="Node3D"]',
        "",
        '[node name="VisualGeometry" parent="." instance=ExtResource("1_model")]',
        "",
        '[node name="Colliders" type="Node3D" parent="."]',
        "",
    ])
    for i, n in enumerate(collidable, 1):
        sx, sy, sz = n["size"]
        cx, base_y, cz = n["pos"]
        cy = base_y + sy / 2.0
        cname = f"Collider_{i}_{n['category']}"
        tscn_lines.append(f'[node name="{cname}" type="StaticBody3D" parent="Colliders"]')
        tscn_lines.append(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {cx:.3f}, {cy:.3f}, {cz:.3f})")
        tscn_lines.append("")
        tscn_lines.append(f'[node name="Shape" type="CollisionShape3D" parent="Colliders/{cname}"]')
        tscn_lines.append(f'shape = SubResource("BoxShape3D_{i}")')
        tscn_lines.append("")
    tscn_path = out_dir / "red_river_town.tscn"
    tscn_path.write_text("\n".join(tscn_lines), encoding="utf-8")

    # 3. Walkability & collision check along Main Street (X = -32m .. +32m, Z = 0)
    sampled, supported, blocked = 0, 0, 0
    for xm in range(-32, 33, 2):
        sampled += 1
        sup = [
            n for n in RED_RIVER_NODES
            if n["category"] in ("road", "courtyard")
            and (n["pos"][0] - n["size"][0] / 2.0 <= xm <= n["pos"][0] + n["size"][0] / 2.0)
            and (n["pos"][2] - n["size"][2] / 2.0 <= 0.0 <= n["pos"][2] + n["size"][2] / 2.0)
        ]
        if sup:
            supported += 1
        hits = [
            n for n in RED_RIVER_NODES
            if n["category"] in ("wall", "cityWall")
            and (n["pos"][0] - n["size"][0] / 2.0 - 0.45 <= xm <= n["pos"][0] + n["size"][0] / 2.0 + 0.45)
            and (n["pos"][2] - n["size"][2] / 2.0 - 0.45 <= 0.0 <= n["pos"][2] + n["size"][2] / 2.0 + 0.45)
        ]
        if hits:
            blocked += 1
    assert supported == sampled and blocked == 0, f"Walkability failed: supported={supported}/{sampled}, blocked={blocked}"

    # 4. Save lossless editable source project JSON
    json_path = out_dir / "red_river_town.wumind3d.json"
    json_path.write_text(json.dumps({"title": "赤河镇 · 西部可漫游小镇", "nodes": RED_RIVER_NODES}, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "status": "PASS",
        "glbPath": str(glb_path.relative_to(REPO_ROOT)),
        "glbBytes": glb_path.stat().st_size,
        "glbGeometryCount": len(geom_names),
        "tscnPath": str(tscn_path.relative_to(REPO_ROOT)),
        "tscnColliderCount": len(collidable),
        "projectJSONPath": str(json_path.relative_to(REPO_ROOT)),
        "walkabilityCheck": {"sampled": sampled, "supported": supported, "blocked": blocked, "pass": True},
    }


# =============================================================================
# 4. CHARACTER / RIG AUDIT (Existing Bundled Humanoid GLB)
# =============================================================================

def verify_bundled_rigged_character():
    glb_path = REPO_ROOT / "App" / "Resources" / "DuelCharacters" / "DuelChar_wuYong.glb"
    assert glb_path.exists(), f"Missing rigged character GLB: {glb_path}"
    raw = glb_path.read_bytes()
    magic, version, total_len = struct.unpack_from("<4sII", raw, 0)
    assert magic == b"glTF" and version == 2
    chunk_len, chunk_type = struct.unpack_from("<I4s", raw, 12)
    assert chunk_type == b"JSON"
    gltf = json.loads(raw[20 : 20 + chunk_len].decode("utf-8"))

    skins = gltf.get("skins", [])
    animations = [a.get("name", f"anim_{i}") for i, a in enumerate(gltf.get("animations", []))]
    joint_count = sum(len(s.get("joints", [])) for s in skins)
    loaded = trimesh.load(str(glb_path), force="scene")
    bounds = loaded.bounds
    height_m = float(bounds[1][1] - bounds[0][1])

    assert len(skins) >= 1 and joint_count >= 15, f"Expected rigged humanoid skeleton, got skins={len(skins)} joints={joint_count}"
    assert len(animations) >= 1, "Expected embedded animations in humanoid GLB"

    audit = {
        "status": "PASS",
        "asset": str(glb_path.relative_to(REPO_ROOT)),
        "fileBytes": glb_path.stat().st_size,
        "skinCount": len(skins),
        "jointCount": joint_count,
        "animationCount": len(animations),
        "animationNames": animations[:12],
        "metricHeightM": round(height_m, 3),
        "complianceNote": "自有合法绑骨资产；Mixamo 因中国区限制及禁止再分发原始 FBX 仅列研究候选。",
    }
    (SAMPLES_DIR / "character_rig_audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    return audit


# =============================================================================
# 5. VISUAL 4-PANEL PROOF SHEET (CAD / BIM / RED RIVER TOWN / SUMMARY)
# =============================================================================

def render_proof_sheet(report: dict):
    W, H = 1600, 1000
    img = Image.new("RGB", (W, H), (14, 16, 22))
    draw = ImageDraw.Draw(img)

    panels = [
        (20, 60, 790, 510, "1. CAD 4-Hole Mounting Plate (ezdxf 1.4.5 + CadQuery 2.8.0 STEP)"),
        (810, 60, 1580, 510, "2. BIM IFC4 Floorplan Door Move +600mm (IfcOpenShell 0.9.0)"),
        (20, 530, 790, 980, "3. Red River Town (GLB + Godot 4 .tscn + Walkable Bridge)"),
        (810, 530, 1580, 980, "4. Verified Audit Metrics & Rigged Humanoid GLB"),
    ]
    draw.text((24, 18), "WUMIND 3D Technical Library - Independent Sample Verification Proof Sheet (2026-11-26)", fill=(235, 240, 250))

    for x0, y0, x1, y1, title in panels:
        draw.rounded_rectangle([x0, y0, x1, y1], radius=14, fill=(24, 27, 36), outline=(65, 74, 96), width=2)
        draw.text((x0 + 16, y0 + 12), title, fill=(140, 210, 255))

    # Panel 1: CAD Plate v1 (120x80) vs v2 (130x90)
    for idx, (ox, label, px, py, col) in enumerate([
        (210, "v1: Pitch 120x80mm (Verified STEP+DXF)", 120, 80, (90, 185, 255)),
        (590, "v2: Pitch 130x90mm (Regenerated)", 130, 90, (90, 235, 165)),
    ]):
        cy = 290
        sc = 1.7
        pw, pd = 160 * sc, 120 * sc
        draw.rectangle([ox - pw / 2, cy - pd / 2, ox + pw / 2, cy + pd / 2], fill=(42, 48, 62), outline=col, width=3)
        for sx in (-1, 1):
            for sy in (-1, 1):
                hx, hy = ox + sx * (px / 2) * sc, cy + sy * (py / 2) * sc
                r = 5.0 * sc
                draw.ellipse([hx - r, hy - r, hx + r, hy + r], fill=(14, 16, 22), outline=(255, 190, 90), width=2)
                draw.line([hx - 12, hy, hx + 12, hy], fill=(90, 220, 140), width=1)
                draw.line([hx, hy - 12, hx, hy + 12], fill=(90, 220, 140), width=1)
        draw.text((ox - 120, cy + pd / 2 + 16), label, fill=col)

    # Panel 2: BIM IFC4 Door Move (X=1800mm -> X=2400mm)
    for ox, label, dx_mm, col in [
        (1000, "Before: Door X=1800mm (L:1800 R:2500)", 1800, (90, 185, 255)),
        (1385, "After: Door X=2400mm (L:2400 R:1900)", 2400, (90, 235, 165)),
    ]:
        cy = 290
        sc = 0.052  # mm -> px
        rw, rd = 5200 * sc, 4400 * sc
        xL, yT = ox - rw / 2, cy - rd / 2
        draw.rectangle([xL, yT, xL + rw, yT + rd], fill=(34, 39, 52), outline=(180, 195, 220), width=5)
        # Door opening gap + door leaf on south wall (yT + rd)
        d_x0 = xL + dx_mm * sc
        d_w = 900 * sc
        draw.rectangle([d_x0, yT + rd - 4, d_x0 + d_w, yT + rd + 4], fill=(24, 27, 36))
        draw.line([d_x0, yT + rd, d_x0 + d_w, yT + rd - d_w * 0.75], fill=col, width=4)
        draw.arc([d_x0, yT + rd - d_w, d_x0 + 2 * d_w, yT + rd + d_w], 180, 270, fill=col, width=2)
        draw.text((ox - 125, yT + rd + 18), label, fill=col)
        draw.text((xL + 8, yT + 8), "NorthWall [Annotated]", fill=(150, 205, 255))
        draw.text((xL + 8, yT + 26), "WestWall [Scanned] / EastWall [Estimated]", fill=(255, 195, 120))

    # Panel 3: Red River Town Plan (1:1 true metric scale, strictly inside [20..790, 530..980])
    ox, oy, sc = 250, 768, 3.65
    for n in RED_RIVER_NODES:
        if n["category"] == "roof":
            continue
        cx, _, cz = n["pos"]
        sx, _, sz = n["size"]
        rx0, ry0 = ox + (cx - sx / 2) * sc, oy + (cz - sz / 2) * sc
        rx1, ry1 = ox + (cx + sx / 2) * sc, oy + (cz + sz / 2) * sc
        c = n["color"][:3]
        draw.rectangle([rx0, ry0, rx1, ry1], fill=c, outline=(235, 235, 235), width=1)
    # Draw green verified walkable path across bridge from Saloon (-32m) to Station (+32m)
    draw.line([ox - 32 * sc, oy, ox + 32 * sc, oy], fill=(70, 255, 140), width=4)
    draw.text((ox - 24 * sc - 22, oy - 15.5 * sc - 10), "Saloon", fill=(255, 240, 200))
    draw.text((ox + 25 * sc - 30, oy - 16.0 * sc - 10), "Station", fill=(255, 225, 210))
    draw.text((ox - 20, oy - 24), "Bridge", fill=(100, 255, 160))
    draw.text((ox - 24, oy + 120), "Red River", fill=(255, 195, 175))
    # Right-side clean legend inside Panel 3
    lx, ly = 468, 596
    legend = [
        ("Scene Scale: 102m x 100m (1:1)", (215, 225, 240)),
        ("Green Line: Walkable Main St", (90, 255, 155)),
        ("  X = -32m .. +32m, Z = 0m", (175, 190, 210)),
        ("  33/33 supported, 0 blocked", (110, 245, 165)),
        ("", (0, 0, 0)),
        ("Independent Landmarks:", (140, 210, 255)),
        ("  - Red River (waterway)", (220, 175, 155)),
        ("  - Timber Bridge + Railings", (220, 195, 165)),
        ("  - Western Saloon (West)", (225, 185, 145)),
        ("  - Train Station + Tracks", (235, 170, 160)),
        ("  - Blacksmith & Sheriff", (200, 205, 215)),
        ("", (0, 0, 0)),
        ("Exports: .glb + .tscn + .json", (140, 210, 255)),
    ]
    for text, color in legend:
        if text:
            draw.text((lx, ly), text, fill=color)
        ly += 22

    # Panel 4: Verified Text Summary
    cad = report["cad"]
    bim = report["bim"]
    town = report["redRiverTown"]
    rig = report["characterRig"]
    lines = [
        f"[PASS] CAD ezdxf {cad['toolVersions']['ezdxf']} + CadQuery {cad['toolVersions']['cadquery']}",
        f"  v1 STEP Vol: {cad['v1_120x80']['verifiedSTEPVolumeMM3']} mm3 | Holes: {cad['v1_120x80']['verifiedSTEPHoleCentersMM']}",
        f"  v2 STEP Vol: {cad['v2_130x90']['verifiedSTEPVolumeMM3']} mm3 | Holes: {cad['v2_130x90']['verifiedSTEPHoleCentersMM']}",
        "",
        f"[PASS] BIM IfcOpenShell {bim['toolVersion']} (IFC4)",
        f"  Before: Door X={bim['before_door_x1800']['doorXMM']}mm, Opening X={bim['before_door_x1800']['openingXMM']}mm",
        f"  After : Door X={bim['after_door_x2400']['doorXMM']}mm, Opening X={bim['after_door_x2400']['openingXMM']}mm (+600mm)",
        "  Sources: Annotated / Scanned / Estimated preserved in Pset",
        "",
        "[PASS] Red River Town (Game Scene + Local Offline Export)",
        f"  GLB: {town['glbGeometryCount']} named landmarks ({town['glbBytes'] // 1024} KB) via trimesh.load()",
        f"  Godot 4 .tscn: {town['tscnColliderCount']} StaticBody3D colliders",
        f"  Walkability: {town['walkabilityCheck']['supported']}/{town['walkabilityCheck']['sampled']} supported, 0 blocked",
        "",
        "[PASS] Rigged Humanoid GLB (DuelChar_wuYong.glb)",
        f"  Skins: {rig['skinCount']} | Joints: {rig['jointCount']} | Animations: {rig['animationCount']} | Height: {rig['metricHeightM']}m",
        "  Single-Image-to-3D (TRELLIS.2 / Hunyuan3D / SAM 3D): Research Candidate (no 24GB GPU)",
    ]
    ty = 576
    for ln in lines:
        col = (110, 245, 165) if ln.startswith("[PASS]") else (215, 222, 235)
        draw.text((832, ty), ln, fill=col)
        ty += 22

    local_png = SAMPLES_DIR / "3d_samples_verification_sheet.png"
    img.save(local_png)
    if ARTIFACT_DIR.exists():
        img.save(ARTIFACT_DIR / "3d_samples_verification_sheet.png")
    return str(local_png.relative_to(REPO_ROOT))


def main():
    SAMPLES_DIR.mkdir(parents=True, exist_ok=True)
    report = {
        "verifiedDate": "2026-11-26",
        "cad": verify_cad_samples(),
        "bim": verify_bim_samples(),
        "redRiverTown": verify_red_river_town(),
        "characterRig": verify_bundled_rigged_character(),
    }
    report["proofSheet"] = render_proof_sheet(report)
    summary_path = SAMPLES_DIR / "verification_report.json"
    summary_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("\nALL 4 INDUSTRIAL 3D/CAD/BIM/RIG VERIFICATION SUITES PASSED!")


if __name__ == "__main__":
    main()
