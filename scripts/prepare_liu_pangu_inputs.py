#!/usr/bin/env python3
"""Prepare exact D19 input mappings without building or activating a release.

The two committed inventories are reviewed trust anchors, not caller-authored
proofs. Original motion bytes are checked against their pinned object digests.
An optional existing Unity bundle catalog can locate equipment candidates, but
self-reported paths and hashes never promote a candidate to original identity.
No download, decoding, GLB conversion, resource copying, key access or upload
occurs. Exit 2 means a valid, useful partial input plan was written; it is not
an installed character. Updating the reviewed inventory pins requires review.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys

from pangu_source_identity import COLLECTION_KEY, inventory_strings, matches_model
from pangu_source_motion_inventory import DEFAULTS, MARKERS, NATIVE_SHA256


IDENTITY_NAME = "pangu_source_identity_20261114.json"
MOTIONS_NAME = "pangu_source_motion_inventory_20261114.json"
REVIEWED_PINS = {
    IDENTITY_NAME: "fdaf44812d2e5aa02baf876a401ea507a8f83a7e11f76ac274f60532825b1901",
    MOTIONS_NAME: "baa0a83c58348c3842b4a442ea534f875168a93a411646ed6c7e07e5d2941d45",
}
MAX_JSON_BYTES = 8_000_000
MAX_MOTION_BYTES = 8_000_000
MAX_BUNDLE_BYTES = 128_000_000
MAX_CATALOG_BYTES = 32_000_000
MAX_CATALOG_RECORDS = 100_000
MAX_TOTAL_INPUT_BYTES = 160 * 1024 * 1024
EQUIPMENT = {
    21094: ("WPN_TWOHANDEDAXE_02", "Top100/wpn__twohanded_axe_01_02", 3, "SET_DYNASTY_19_WPN"),
    21095: ("WPN_TWOHANDEDAXE_02a", "Top100/wpn__twohanded_axe_01_02a", 6, "SET_DYNASTY_19_WPN"),
    22064: ("ARM_AGL_48", "Top100/arm__agl_48", 6, "SET_DYNASTY_19_ARM"),
    23062: ("HLM_AGL_48", "Top100/helm__agl_48", 2, "SET_DYNASTY_19_HLM"),
    24046: ("RNG_PILUM_08", "Top100/rng__pilum_01_08", 4, "SET_DYNASTY_19_RNG"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def parse_json(raw):
    def invalid(_):
        raise ValueError("Non-finite JSON value")
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid)


def bounded_bytes(path, maximum):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum,
            "Expected a bounded regular input file")
    raw = path.read_bytes()
    require(len(raw) == info.st_size, "Input changed while reading")
    return raw


def reviewed_document(path, name):
    raw = bounded_bytes(path, MAX_JSON_BYTES)
    require(digest(raw) == REVIEWED_PINS[name], "Inventory differs from its independently reviewed pin: " + name)
    return parse_json(raw)


def relative_path(value):
    require(isinstance(value, str) and 0 < len(value) <= 512 and "\\" not in value,
            "Invalid relative input name")
    path = PurePosixPath(value)
    require(not path.is_absolute() and ".." not in path.parts and str(path) == value,
            "Unsafe relative input path")
    return path


def local_file(root, name):
    """Reject links in every component; return missing without searching elsewhere."""
    relative = relative_path(name)
    require(root.is_dir() and not root.is_symlink(), "Input root must be a real directory")
    current = root
    for part in relative.parts:
        current = current / part
        try:
            info = current.lstat()
        except FileNotFoundError:
            return None
        require(not stat.S_ISLNK(info.st_mode), "Symbolic-link input is not accepted")
    require(current.is_file(), "Expected a regular input file")
    return current


def locate_motion(root, motion):
    source = relative_path(motion["sourceFile"])
    require(source.suffix == ".bin", "Expected an original motion .bin identity")
    names = [str(source.with_suffix(".bytes")), str(source), source.with_suffix(".bytes").name, source.name]
    found = []
    for name in dict.fromkeys(names):
        path = local_file(root, name)
        if path is None:
            continue
        raw = bounded_bytes(path, MAX_MOTION_BYTES)
        require(len(raw) == motion["bytes"] and digest(raw) == motion["sha256"],
                "Motion bytes disagree with reviewed source identity: " + motion["sourceFile"])
        found.append(name)
    return found[0] if found else None


def validate_documents(identity, motions):
    require(identity.get("schemaVersion") == 1 and identity.get("collection") ==
            {"key": COLLECTION_KEY, "id": 141, "alias": "D19"}, "Expected the reviewed D19 collection")
    items = identity.get("items", [])
    require(len(items) == len(EQUIPMENT) and {row.get("itemID") for row in items} == set(EQUIPMENT),
            "Missing, duplicate or substituted D19 equipment identity")
    for row in items:
        symbol, model, mask, tag = EQUIPMENT[row["itemID"]]
        require((row.get("symbol"), row.get("model"), row.get("maskColorChannels"), row.get("equipmentTags")) ==
                (symbol, model, mask, [tag]), "Legacy equipment cannot be relabeled as D19")
    require(motions.get("schema") == "pangu-original-motion-semantic-inventory-v1" and
            identity["sourceVersion"] == motions.get("packagedConfigurationVersion"), "Mixed source configuration versions")
    require(motions.get("verifiedNativeDefaults") == DEFAULTS and
            motions.get("nativeEvidence", {}).get("imageSHA256") == NATIVE_SHA256,
            "Unreviewed native animation semantics")
    rows, missing = motions["records"], motions["unrecovered"]
    all_aliases = [row["animation"] for row in rows + missing]
    require(len(all_aliases) == len(set(all_aliases)) and all(a.startswith("D19_") for a in all_aliases),
            "Duplicate or unrelated motion alias")
    require(len(rows) == motions["recoveredAliasCount"] and len(missing) == motions["unrecoveredAliasCount"] and
            len({row["motion"]["sha256"] for row in rows}) == motions["recoveredSourceObjectCount"] and
            len({row["sourceFile"] for row in missing}) == motions["unrecoveredSourceFileCount"], "Motion inventory count mismatch")
    for row in rows:
        motion = row["motion"]
        require(0 < motion["bytes"] <= MAX_MOTION_BYTES and
                re.fullmatch(r"[0-9a-f]{64}", motion["sha256"]) is not None, "Invalid original object digest or size")
        require(set(row["rawMarkers"]) == set(MARKERS), "Incomplete original marker mapping")
        require(1 <= len(motion["arrays"]) <= 4 and all(
            type(a["frameCount"]) is int and 0 < a["frameCount"] <= 100_000 and
            a["boneIDs"] and len(a["boneIDs"]) == len(set(a["boneIDs"])) for a in motion["arrays"]),
            "Invalid original bone/frame inventory")
        expected_path = "assets/gamedata/resources/content/animations/binaries/" + str(relative_path(motion["sourceFile"]).with_suffix(".bytes"))
        require(motion["sourceObjectPath"] == expected_path, "Motion object path differs from source identity")


def catalog_rows(path):
    if path is None:
        return [], None
    raw = bounded_bytes(path, MAX_CATALOG_BYTES)
    rows = [parse_json(line) for line in raw.splitlines() if line.strip()]
    require(len(rows) <= MAX_CATALOG_RECORDS and len({r["file"] for r in rows}) == len(rows),
            "Oversized or duplicated bundle inventory")
    for row in rows:
        require(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", row["file"]) is not None and
                ".." not in row["file"] and type(row["bytes"]) is int and 0 < row["bytes"] <= MAX_BUNDLE_BYTES and
                re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) is not None, "Invalid bundle inventory record")
        require(all(isinstance(s, str) for s in inventory_strings(row)), "Invalid Unity container path inventory")
    return rows, digest(raw)


def equipment_mapping(identity, catalog, catalog_sha, bundle_root):
    reviewed = next(row for row in identity["sourceMembers"] if row["member"] == "research/android_bundle_catalog.jsonl")
    trusted_catalog = catalog_sha == reviewed["sha256"]
    rows, checked, total = [], {}, 0
    for item in identity["items"]:
        candidates = []
        for bundle in catalog:
            matches = [p for p in inventory_strings(bundle) if matches_model(p, item["model"])]
            if not matches:
                continue
            paths = [p["path"] for p in bundle["paths"] if matches_model(p["path"], item["model"])]
            key = bundle["file"]
            if key not in checked:
                verified_bytes = False
                if bundle_root is not None:
                    path = local_file(bundle_root, key)
                    if path is not None:
                        total += bundle["bytes"]
                        require(total <= MAX_TOTAL_INPUT_BYTES, "Equipment input byte budget exceeded")
                        raw = bounded_bytes(path, MAX_BUNDLE_BYTES)
                        require(len(raw) == bundle["bytes"] and digest(raw) == bundle["sha256"], "Candidate bundle bytes changed")
                        verified_bytes = True
                checked[key] = verified_bytes
            receipt = {k: bundle[k] for k in ("file", "bytes", "sha256")}
            # A bundle filename alone is not a recovered Unity object binding.
            original_identity = trusted_catalog and receipt in item["androidMatches"] and bool(paths)
            candidates.append({**receipt, "containerPaths": paths, "bytesVerified": checked[key],
                               "originalIdentityVerified": original_identity and checked[key],
                               "identityEvidence": "reviewed-catalog-and-item-join" if original_identity else "unreviewed-catalog-candidate"})
        rows.append({**{k: deepcopy(item[k]) for k in ("symbol", "itemID", "model", "maskColorChannels", "equipmentTags")},
                     "status": "verified-original-input" if any(c["originalIdentityVerified"] for c in candidates) else
                               "candidate-unverified" if candidates else "missing-exact-model",
                     "candidates": candidates})
    return rows


def prepare(source_root, *, identity_path=None, motions_path=None, bundle_catalog=None, bundle_root=None):
    here = Path(__file__).resolve().parent
    identity = reviewed_document(identity_path or here / IDENTITY_NAME, IDENTITY_NAME)
    motions = reviewed_document(motions_path or here / MOTIONS_NAME, MOTIONS_NAME)
    validate_documents(identity, motions)
    require(source_root.is_dir() and not source_root.is_symlink(), "Motion root must be a real directory")
    catalog, catalog_sha = catalog_rows(bundle_catalog)
    require(bundle_catalog is not None or bundle_root is None, "A bundle root requires a source catalog")
    equipment = equipment_mapping(identity, catalog, catalog_sha, bundle_root)
    objects, tasks, total = {}, [], 0
    for row in motions["records"]:
        motion = row["motion"]
        key = motion["sha256"]
        identity_fields = {k: deepcopy(motion[k]) for k in
                           ("sourceFile", "sourceBundle", "sourceObjectPath", "pathID", "bytes", "sha256", "arrays")}
        if key not in objects:
            total += motion["bytes"]
            require(total <= MAX_TOTAL_INPUT_BYTES, "Motion input byte budget exceeded")
            local = locate_motion(source_root, motion)
            objects[key] = {**identity_fields, "inputRelativePath": local,
                            "status": "verified-reviewed-bytes" if local else "missing-local-bytes", "aliases": []}
        else:
            require(all(objects[key][k] == v for k, v in identity_fields.items()),
                    "One digest cannot conceal conflicting original object bindings")
        objects[key]["aliases"].append(row["animation"])
        raw = row["rawMarkers"]
        resolved = {k: deepcopy(raw[k] if raw[k] is not None else v) for k, v in DEFAULTS.items()}
        tasks.append({"animation": row["animation"], "sourceObjectSHA256": key,
                      "status": objects[key]["status"], "configurationSource": deepcopy(row["configurationSource"]),
                      "rawMarkers": deepcopy(raw), "frameParametersWithVerifiedDefaults": resolved,
                      "soundIdentifiersAndFrames": deepcopy(row["soundMarkers"]),
                      "intervalMarkers": deepcopy(row["intervalMarkers"]),
                      "sourceFPS": None, "animationSpeed": None,
                      "nextOperation": "Decode both original arrays; join verified bones to the recovered D19 rig before GLB export"})
    tasks.extend({"animation": row["animation"], "sourceFile": row["sourceFile"],
                  "sourceObjectSHA256": None, "status": "unrecovered-original-motion",
                  "nextOperation": "Recover this exact original motion; never substitute a legacy hammer/axe clip"}
                 for row in motions["unrecovered"])
    verified = sum(row["status"] == "verified-reviewed-bytes" for row in objects.values())
    verified_models = sum(row["status"] == "verified-original-input" for row in equipment)
    complete = verified == len(objects) and not motions["unrecovered"] and verified_models == len(equipment)
    return {
        "schema": "liu-pangu-input-preparation-v1", "purpose": "input-mapping-only",
        "reviewedInputs": [{"file": name, "sha256": pin} for name, pin in REVIEWED_PINS.items()],
        "configurationVersion": identity["sourceVersion"], "collection": deepcopy(identity["collection"]),
        "inputCoverageComplete": complete, "releaseActivationAllowed": False,
        "counts": {"requiredEquipmentIdentities": len(equipment), "verifiedEquipmentInputs": verified_models,
                   "recoveredAliases": len(motions["records"]), "verifiedMotionObjects": verified,
                   "recoveredMotionObjects": len(objects), "missingLocalMotionObjects": len(objects) - verified,
                   "unrecoveredAliases": len(motions["unrecovered"]),
                   "unrecoveredSourceFiles": motions["unrecoveredSourceFileCount"], "totalAliasMappings": len(tasks)},
        "equipment": equipment, "motionObjects": sorted(objects.values(), key=lambda r: r["sourceFile"]),
        "aliasAssemblyTasks": sorted(tasks, key=lambda r: r["animation"]),
        "clockContract": {"simulationHz": 60, "sampleAdvance": "animationSpeed / (MidFrames + 1)",
                          "intervalFrameRule": "positive value -> max(value - 1, 0); preserve absent values",
                          "soundFrameRule": "max(value, 0); no subtract-one",
                          "endRule": "EndIndex - floor(position) <= SelfEndFrame",
                          "note": "These are source coordinates, not cropped/export frame indices; speed and actual rig remain unbound"},
        "remainingAssemblyGates": [
            "Exact D19 equipment, dedicated motion, material/texture and skeleton input identity",
            "Self-contained character GLB and every catalog motion/rig/material binding",
            "Exact source trail and audio bytes plus event/clip binding; identifiers alone are not media",
            "H17 Morph target/material contract currently pins liu_hammers; a D19 counterpart requires separate reviewed binding",
            "DuelFighterAssetRelease schema validation, independent signed-build SHA and full-resource native acceptance",
        ],
        "effects": {"downloaded": False, "decoded": False, "copiedResources": False,
                    "generatedGLB": False, "generatedRelease": False, "changedBuildPin": False},
    }


def write_plan(path, plan):
    require(path.suffix == ".json" and path.name not in ("SF3_FighterRelease.json", "SF3_DistinctFighters.json"),
            "Output must be an input-plan JSON, never a runtime release or catalog")
    raw = (json.dumps(plan, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    require(not path.exists() and not path.is_symlink(), "Preserve existing output; choose a new plan filename")
    with path.open("xb") as output:
        path.chmod(0o600)
        output.write(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motion-root", type=Path, required=True)
    parser.add_argument("--identity-inventory", type=Path)
    parser.add_argument("--motion-inventory", type=Path)
    parser.add_argument("--bundle-catalog", type=Path)
    parser.add_argument("--bundle-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        plan = prepare(args.motion_root, identity_path=args.identity_inventory,
                       motions_path=args.motion_inventory, bundle_catalog=args.bundle_catalog, bundle_root=args.bundle_root)
        write_plan(args.output, plan)
    except (ValueError, OSError, KeyError, TypeError) as error:
        # Do not echo private absolute input names, file contents or exception payloads.
        print(json.dumps({"prepared": False, "errorType": type(error).__name__, "releaseActivationAllowed": False}), file=sys.stderr)
        return 1
    print(json.dumps({"prepared": True, "inputCoverageComplete": plan["inputCoverageComplete"],
                      "releaseActivationAllowed": False, **plan["counts"]}))
    return 0 if plan["inputCoverageComplete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
