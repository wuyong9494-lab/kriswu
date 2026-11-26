#!/usr/bin/env python3
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
