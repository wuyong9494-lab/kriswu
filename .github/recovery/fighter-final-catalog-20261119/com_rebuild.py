"""Diagnostic ordered COM reconstruction from pinned old rigs and BonesData.

Not a mass solver: every positive mass is an exact XML declaration. Historical
COM selects among a finite set of declaration/order candidates; a tie is fatal.
Caller authenticates catalog and raw GLB before passing their parsed objects.
This module separately pins both XMLs and checks profile/model references.
No files, assets, catalog values or release pins are written by this module.
"""
from __future__ import annotations

import hashlib
import json
import math
import xml.etree.ElementTree as ET

import numpy as np

from endpoint_consensus import animation_samples
from sun_triad_assets import world_poses
from sun_triad_source_bones import parse_bones_data

XML553_SHA = "0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455"
XML608_SHA = "5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8"
PROFILES = {
    "sun_triad": (65, 15_458_776, "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6"),
    "liu_hammers": (59, 10_792_864, "a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517"),
}
LIMBS = (("handL", "hand_l"), ("handR", "hand_r"), ("footL", "foot_l"), ("footR", "foot_r"))


class MassInferenceError(ValueError):
    def __init__(self, message, report=None):
        self.report = report or {}
        super().__init__(message + ("; " + json.dumps(self.report, sort_keys=True) if report else ""))


def require(condition, message):
    if not condition:
        raise MassInferenceError(message)


def _declarations(raw):
    """Use only Bones/Bone declarations, never Mirroring instructions."""
    declarations = parse_bones_data(raw)["bones"]
    result = []
    for element in ET.fromstring(raw).find("Bones"):
        number = int(element.get("ID"))
        mass = float(element.get("Mass", "0"))
        require(math.isfinite(mass) and mass >= 0, "Invalid source mass")
        result.append(dict(sourceBoneID=number, name=declarations[number], mass=mass))
    return result


def _hierarchy(nodes):
    require(isinstance(nodes, list) and 1 <= len(nodes) <= 4096, "Invalid rig size")
    parents = {}
    for index, node in enumerate(nodes):
        require("matrix" not in node, "Matrix/TRS convention not supported")
        for child in node.get("children", []):
            require(type(child) is int and 0 <= child < len(nodes) and child not in parents,
                    "Invalid or multiply parented rig")
            parents[child] = index
    order, visiting, visited = [], set(), set()
    def walk(index):
        require(index not in visiting, "Cyclic rig")
        if index in visited:
            return
        visiting.add(index); order.append(index)
        for child in nodes[index].get("children", []):
            walk(child)
        visiting.remove(index); visited.add(index)
    for index in range(len(nodes)):
        if index not in parents:
            walk(index)
    require(len(visited) == len(nodes), "Disconnected cyclic rig")
    return order, parents


def _candidates(nodes, first, second, bindings=None, discarded=None):
    """Finite source-declaration choices, not fitted/permuted/averaged masses.

    Native audit favors transform preorder. Target-index and XML declaration
    order are diagnostic alternatives for historical exporter behavior, never
    silently promoted to proof of original native traversal.
    """
    hierarchy, parents = _hierarchy(nodes)
    by_name = {}
    for index, node in enumerate(nodes):
        by_name.setdefault(node.get("name"), []).append(index)
    tables = [("553", first), ("608", second)]
    # Matching overlapping declarations can be unioned without choosing which
    # config wins. Different declarations are NOT overwritten or averaged.
    merged, reverse, compatible = {}, {}, True
    for row in first + second:
        number, name = row["sourceBoneID"], row["name"]
        if (number in merged and merged[number] != row) or (name in reverse and reverse[name] != number):
            compatible = False; break
        merged[number] = row; reverse[name] = number
    if compatible:
        tables.append(("553+608-compatible", list(merged.values())))
    discarded = [] if discarded is None else discarded
    bound_sources = None
    if bindings is not None:
        require(isinstance(bindings, list) and bool(bindings), "Invalid original sourceBoneBindings")
        bound_sources, bound_nodes = {}, set()
        for binding in bindings:
            node, name, number = binding.get("targetNode"), binding.get("name"), binding.get("sourceID")
            require(type(node) is int and 0 <= node < len(nodes) and node not in bound_nodes
                    and nodes[node].get("name") == name, "Original source binding node/name differs")
            bound_nodes.add(node)
            if number is not None:
                require(type(number) is int and 0 <= number <= 65535 and number not in bound_sources,
                        "Invalid/duplicate original source binding ID")
                bound_sources[number] = (name, node)
    expanded = []
    for label, declarations in tables:
        positive = [row for row in declarations if row["mass"] > 0]
        expanded.append((label + "/all-declared", positive))
        if bound_sources is not None:
            intersection = []
            for row in positive:
                match = bound_sources.get(row["sourceBoneID"])
                if match is not None:
                    require(match[0] == row["name"], "Source binding ID/name conflicts with pinned mass XML")
                    intersection.append(row)
            expanded.append((label + "/bound-sourceIDs-intersection", intersection))
    unique = {}
    for label, positive in expanded:
        if not positive:
            discarded.append(dict(table=label, reason="no-positive-bound-mass")); continue
        missing = [row["name"] for row in positive if len(by_name.get(row["name"], [])) != 1]
        if missing:
            # An inapplicable full-body table must not suppress a valid base
            # table. Do not silently truncate it to names present in this rig.
            discarded.append(dict(table=label, reason="missing-or-ambiguous-positive-node", names=missing)); continue
        bound = [dict(row, targetNode=by_name[row["name"]][0]) for row in positive]
        roots = set()
        for row in bound:
            index = row["targetNode"]
            while index in parents:
                index = parents[index]
            roots.add(index)
        if len(roots) != 1:
            discarded.append(dict(table=label, reason="positive-masses-span-rig-roots")); continue
        by_node = {row["targetNode"]: row for row in bound}
        for order_name, rows in [
            ("transform-preorder", [by_node[n] for n in hierarchy if n in by_node]),
            ("target-index", sorted(bound, key=lambda row: row["targetNode"])),
            ("xml-declaration", bound),
        ]:
            key = json.dumps(rows, sort_keys=True, separators=(",", ":"))
            if key not in unique:
                unique[key] = dict(labels=[], bones=rows)
            unique[key]["labels"].append(label + "/" + order_name)
    require(bool(unique), "No positive source mass candidate")
    return list(unique.values())


def _weighted(world, rows):
    """world is already RIGHT-oriented; preserve native Float32 sum order."""
    acc, total = np.zeros(3, dtype=np.float32), np.float32(0)
    for row in rows:
        mass = np.float32(row["mass"])
        point = np.asarray(world[row["targetNode"], :3, 3], dtype=np.float32)
        acc = np.asarray(acc + point * mass, dtype=np.float32)
        total = np.float32(total + mass)
    require(np.isfinite(acc).all() and np.isfinite(total) and total > 0, "Invalid COM accumulation")
    return acc / total


def _exact(actual, expected):
    """Match serialization precision AND signed zero, not a tolerance fit."""
    a, b = np.asarray(actual, dtype=np.float64), np.asarray(expected, dtype=np.float64)
    return a.shape == b.shape and np.array_equal(a.view(np.uint64), b.view(np.uint64))


def _select(profile, g, b, candidates):
    """Internal testable selector; public entry separately authenticates XML/ID."""
    order, _ = _hierarchy(g["nodes"])
    require(len(order) == len(g["nodes"]), "Rig incomplete")
    names = [node.get("name") for node in g["nodes"]]
    require(all(names.count(name) == 1 for _, name in LIMBS), "Ambiguous/missing limb control")
    limb_indices = [(field, names.index(name)) for field, name in LIMBS]
    animations = {a["name"]: a for a in g["animations"]}
    require(len(animations) == len(g["animations"]), "Duplicate animation")
    clips = profile["clips"]
    require(len({c["name"] for c in clips}) == len(clips), "Duplicate catalog clip")
    _, rest, parents = world_poses(g["nodes"])
    records = []
    for clip in clips:
        frames = clip["frames"]
        require(type(frames) is int and 1 <= frames <= 2000 and clip["name"] in animations, "Invalid source clip")
        animation = animations[clip["name"]]
        require(animation.get("extras", {}).get("sourceSHA256") == clip["sha256"], "Source motion identity differs")
        tracks = clip["tracks"]; count = 2 * frames - 1
        require(tracks.get("samplesPerSourceFrame") == 2, "Wrong historical source sampling")
        for key in ("centerOfMass", *[key for key, _ in LIMBS]):
            array = np.asarray(tracks.get(key), dtype=float)
            require(array.shape == (count, 3) and np.isfinite(array).all(), "Missing/nonfinite original track: " + key)
        records.append((clip, animation, count))
    require(records, "No historical COM witnesses")
    live = list(range(len(candidates))); rejections = []
    checked = 0; per_clip = []
    # Every old tick is a witness, including half-frame local interpolation.
    # Stop testing discarded candidates, but always check all controls/old COM
    # for any survivor. Do not tune arithmetic or masses to minimize error.
    for clip, animation, count in records:
        for tick, world in enumerate(animation_samples(g, b, animation, clip["frames"], range(count), rest, parents)):
            require(np.isfinite(world).all(), "Nonfinite FK")
            for field, node in limb_indices:
                require(_exact(np.round(world[node, :3, 3], 7), clip["tracks"][field][tick]),
                        "Historical limb control mismatch: " + clip["name"] + "/" + field + "/" + str(tick))
            expected = clip["tracks"]["centerOfMass"][tick]
            survivors = []
            for candidate in live:
                actual = np.round(_weighted(world, candidates[candidate]["bones"]), 7)
                if _exact(actual, expected):
                    survivors.append(candidate)
                else:
                    rejections.append(dict(candidate=candidate, labels=candidates[candidate]["labels"],
                        clip=clip["name"], tick=tick, maximumError=float(np.max(np.abs(np.asarray(actual, float)-expected)))))
            live = survivors; checked += 1
            if not live:
                raise MassInferenceError("No exact historical COM candidate", dict(
                    candidateCount=len(candidates), matchingCandidateCount=0, checkedSamples=checked, rejected=rejections))
        per_clip.append(dict(name=clip["name"], samples=count))
    report = dict(candidateCount=len(candidates), matchingCandidateCount=len(live),
        checkedClips=len(records), checkedSamples=checked, controlsPerSample=4,
        matchingCandidates=[dict(candidate=index, labels=candidates[index]["labels"],
            positiveMassCount=len(candidates[index]["bones"]),
            totalMass=sum(row["mass"] for row in candidates[index]["bones"])) for index in live],
        rejected=rejections, clips=per_clip,
        basis="RIGHT; Float32 point/multiply/ordered sum/divide; Float32 round7; exact serialized-value comparison")
    if len(live) != 1:
        raise MassInferenceError("Historical COM mass declaration/order remains ambiguous", report)
    return [dict(row) for row in candidates[live[0]]["bones"]], report


def diagnose_mass_bindings(profile, historic_g, historic_b, xml553_bytes, xml608_bytes):
    """Return (rows, report); unknown/zero/multiple matches raise with .report."""
    require(hashlib.sha256(xml553_bytes).hexdigest() == XML553_SHA, "Unpinned 553 BonesData")
    require(hashlib.sha256(xml608_bytes).hexdigest() == XML608_SHA, "Unpinned 608 BonesData")
    pin = PROFILES.get(profile.get("id"))
    require(pin is not None, "Only old Sun65/Liu59 diagnostic inputs are supported")
    count, size, digest = pin
    require((profile.get("bytes"), profile.get("sha256")) == (size, digest)
            and len(profile["clips"]) == count and len(historic_g["animations"]) == count,
            "Historical model identity/count differs")
    discarded = []
    candidates = _candidates(historic_g["nodes"], _declarations(xml553_bytes), _declarations(xml608_bytes),
                             profile.get("sourceBoneBindings"), discarded)
    try:
        rows, report = _select(profile, historic_g, historic_b, candidates)
    except MassInferenceError as error:
        error.report["discardedDeclarationTables"] = discarded
        raise
    report["discardedDeclarationTables"] = discarded
    return rows, report


def infer_mass_bindings(profile, historic_g, historic_b, xml553_bytes, xml608_bytes):
    """Parent compiler API; returns exactly one ordered list or fails closed.

    Raw GLB and enclosing catalog SHA authentication are the caller's job.
    These parsed objects alone cannot prove their original byte containers.
    Result matches all old COM and limb ticks, not a native/device acceptance.
    """
    return diagnose_mass_bindings(profile, historic_g, historic_b, xml553_bytes, xml608_bytes)[0]
