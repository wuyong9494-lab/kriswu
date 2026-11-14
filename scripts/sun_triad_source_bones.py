#!/usr/bin/env python3
"""Read original BonesData without confusing mirror rules with bone IDs.

This module deliberately contains no source asset bytes or resource decryption.
Its caller supplies already decoded, identity-checked private XML files.
"""
from __future__ import annotations
import math
import xml.etree.ElementTree as ET


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_bones_data(raw: bytes) -> dict:
    require(len(raw) <= 1_000_000, "BonesData exceeds the bounded XML size")
    require(b"<!DOCTYPE" not in raw.upper() and b"<!ENTITY" not in raw.upper(),
            "XML declarations and external entities are not supported")
    root = ET.fromstring(raw)
    require(root.tag == "BonesData", "Expected original BonesData root")
    groups = root.findall("Bones")
    require(len(groups) == 1, "Expected exactly one source Bones section")
    bones, names = {}, set()
    # Mirroring/Mirrorer Bone records are instructions, never declarations.
    for element in groups[0]:
        require(element.tag == "Bone", "Unexpected bone declaration")
        name, number = element.get("Name"), element.get("ID")
        require(name and number is not None, "Incomplete bone declaration")
        number = int(number)
        require(0 <= number <= 65535, "Bone ID outside source motion range")
        require(number not in bones and name not in names, "Duplicate source bone ID or name")
        bones[number] = name
        names.add(name)
    require(bool(bones), "BonesData has no declared bones")
    vertices = {}
    for element in root.findall("./Vertexes/Vertex"):
        name, bone = element.get("Name"), element.get("BoneName")
        position = [float(x) for x in element.get("LocalPosition", "").split()]
        require(name and name not in vertices, "Duplicate or empty source vertex")
        require(bone in names, "Source vertex refers to an undeclared bone")
        require(len(position) == 3 and all(math.isfinite(x) for x in position),
                "Invalid source vertex position")
        vertices[name] = dict(name=name, bone=bone, localPositionCentimeters=position)
    capsules, capsule_names = [], set()
    for element in root.findall("./Capsules/Capsule"):
        name = element.get("Name")
        require(name and name not in capsule_names, "Duplicate or empty source capsule")
        first, second = element.get("Vertex1"), element.get("Vertex2")
        require(first in vertices and second in vertices, "Source capsule vertex is unresolved")
        radius = float(element.get("Radius", "nan"))
        require(math.isfinite(radius) and radius > 0, "Invalid source capsule radius")
        capsules.append(dict(id=name, base=vertices[first], tip=vertices[second],
                             radiusCentimeters=radius, sourceAttributes=dict(element.attrib)))
        capsule_names.add(name)
    for capsule in capsules:
        mirror = capsule["sourceAttributes"].get("LeftMirrorCapsule")
        require(mirror is None or mirror in capsule_names, "Source mirror capsule is unresolved")
    return dict(bones=bones, vertices=vertices, capsules=capsules)


def merge_bone_ids(*sources: dict) -> dict[int, str]:
    merged, reverse = {}, {}
    for source in sources:
        for number, name in source["bones"].items():
            require(number not in merged or merged[number] == name, "Source bone ID conflict")
            require(name not in reverse or reverse[name] == number, "Source bone name conflict")
            merged[number] = name
            reverse[name] = number
    return merged


def capsule_binding(capsule: dict, kind: str) -> dict:
    """Convert names and exact centimeter radii to the catalog contract."""
    millimeters = capsule["radiusCentimeters"] * 10
    require(abs(millimeters - round(millimeters)) < 1e-6, "Capsule radius needs submillimeter precision")
    value = dict(id=capsule["id"], radiusMillimeters=round(millimeters))
    if kind == "attack":
        require(capsule["id"].endswith(("_l", "_r")), "Attack capsule side is unproven")
        value["side"] = "left" if capsule["id"].endswith("_l") else "right"
    elif kind == "hurt":
        defense = capsule["sourceAttributes"].get("Defense")
        require(defense in ("HeadDefense", "BodyDefense"), "Source defense binding is unproven")
        value["defense"] = "head" if defense == "HeadDefense" else "body"
    else:
        raise ValueError("Unknown capsule binding kind")
    return value
