#!/usr/bin/env python3
"""Join original BonesData masses to preserved private character skeletons.

The original controller initializes bone mass to zero and treats an omitted
Mass attribute as zero (38624/38915). It constructs bone arrays in Transform
child traversal order (38914/38916); the actor then sums position * mass in
array order (37731/37752). Mirror instructions are not bone declarations.

This tool exports ordered positive masses and provenance. It never modifies a
GLB or assigns a mass to a missing source bone. Actual half-frame FK sampling
belongs to the character profile exporter.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from sun_triad_assets import private_output, require, write_private
from sun_triad_source_bones import parse_bones_data


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def mass_declarations(raw):
    declarations = parse_bones_data(raw)["bones"]
    root = ET.fromstring(raw)
    result = {}
    for bone in root.find("Bones"):
        source_id = int(bone.get("ID"))
        mass = float(bone.get("Mass", "0"))
        require(math.isfinite(mass) and mass >= 0, "Invalid original bone mass")
        result[source_id] = dict(name=declarations[source_id], mass=mass,
                                 sourceBoneID=source_id)
    return result


def ordered_mass_bindings(bindings, nodes, sources):
    declarations, by_name = {}, {}
    for source in sources:
        for source_id, row in source.items():
            require(source_id not in declarations or declarations[source_id] == row,
                    "Conflicting source mass declaration")
            require(row["name"] not in by_name or by_name[row["name"]] == source_id,
                    "Conflicting source bone name")
            declarations[source_id] = row
            by_name[row["name"]] = source_id
    by_node = {}
    for binding in bindings:
        node = binding["targetNode"]
        require(type(node) is int and 0 <= node < len(nodes) and node not in by_node,
                "Ambiguous source skeleton target")
        require(nodes[node].get("name") == binding["name"], "Source node name mismatch")
        source_id = binding.get("sourceID")
        if source_id is not None:
            require(source_id in declarations, "Bone mass configuration is missing")
            require(declarations[source_id]["name"] == binding["name"],
                    "Source mass ID/name mismatch")
        by_node[node] = binding
    parents = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            require(type(child) is int and 0 <= child < len(nodes) and child not in parents,
                    "Ambiguous character hierarchy")
            parents[child] = index
    roots = [index for index in by_node if parents.get(index) not in by_node]
    require(len(roots) == 1, "Source skeleton must have one preserved root")
    result, visited = [], set()

    def walk(index):
        require(index not in visited, "Cyclic source hierarchy")
        visited.add(index)
        binding = by_node.get(index)
        if binding is not None and binding.get("sourceID") is not None:
            row = declarations[binding["sourceID"]]
            if row["mass"] > 0:
                result.append(dict(row, targetNode=index))
        for child in nodes[index].get("children", []):
            walk(child)

    walk(roots[0])
    require(set(by_node).issubset(visited), "Disconnected source bone binding")
    positive = {row["name"] for row in declarations.values() if row["mass"] > 0}
    require({row["name"] for row in result} == positive,
            "Positive source mass has no preserved skeleton node")
    require(bool(result), "Source skeleton has no positive bone mass")
    return result


def glb_json(raw):
    require(len(raw) >= 20, "Truncated GLB")
    magic, version, length, count, kind = struct.unpack_from("<5I", raw)
    require(magic == 0x46546C67 and version == 2 and length == len(raw)
            and kind == 0x4E4F534A and 20 + count <= len(raw), "Invalid GLB header")
    return json.loads(raw[20:20 + count])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = private_output(args.output)
    spec = json.loads(args.spec.read_bytes())
    profiles, evidence = {}, []
    for item in spec["profiles"]:
        profile_path = Path(item["profile"])
        profile_raw = profile_path.read_bytes()
        profile = json.loads(profile_raw)
        glb_raw = Path(item["glb"]).read_bytes()
        require(digest(glb_raw) == profile["sha256"], "Character digest mismatch")
        sources, pins = [], []
        for path_string in item["bones"]:
            path = Path(path_string)
            raw = path.read_bytes()
            sources.append(mass_declarations(raw))
            pins.append(dict(file=str(path), bytes=len(raw), sha256=digest(raw)))
        ordered = ordered_mass_bindings(profile["sourceBoneBindings"],
                                        glb_json(glb_raw)["nodes"], sources)
        profiles[profile["id"]] = ordered
        evidence.append(dict(profileID=profile["id"], characterSHA256=digest(glb_raw),
            sourceProfileSHA256=digest(profile_raw), boneConfigurations=pins,
            positiveMassCount=len(ordered), totalMass=sum(row["mass"] for row in ordered),
            missingMassDefault=0,
            order="Preserved original Transform hierarchy preorder; zero-mass bones omitted without reordering positive terms."))
    result = dict(version=1, sourceCentersOfMass=profiles)
    write_private(output / "source-center-of-mass-weights-private.json",
                  json.dumps(result, indent=2, allow_nan=False).encode())
    write_private(output / "source-center-of-mass-provenance-private.json",
                  json.dumps(dict(nativeMethods=[38624,38914,38915,38916,37731,37752],
                                  profiles=evidence), indent=2, allow_nan=False).encode())
    print(json.dumps({"profiles": {key:len(rows) for key,rows in profiles.items()}}))


if __name__ == "__main__":
    main()
