#!/usr/bin/env python3
"""Bind the original paired Imperial Active contact without resampling media."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path

from append_cached_root_victim_motions import encoded, pinned
from erlang_source_profile import combat_rules
from stage_h17_floorfall_release import fresh_output, write_private
from sun_triad_assets import require


INPUT_SHA256 = "e9001357a0bda99f2fcc8f833b5e5dbc1c48846551def88aa2057d4d1ee1ad23"
BODY_SHA256 = "debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd"
CONFIG_SHA256 = "fb54e61b150349f0a02735ee8354ed6fe21a4263862dd6162e0123583705e8b0"
MOTION_SHA256 = "493596ad52f62dd88ba6a0a6f34760b404cce0cf5eca2c8e1ca8a490b39ab979"
ROLE = "imperialHeavyActive"
CLIP = "imperial_spear_heavy_slash_active"


def append(profile_path: Path, output_path: Path) -> dict:
    original = json.loads(pinned(profile_path, INPUT_SHA256, 32_000_000))
    require(original["id"] == "wuyong_erlang" and original["sha256"] == BODY_SHA256
            and len(original["clips"]) == 62 and original["roles"][ROLE] == CLIP,
            "Expected the reviewed 62-motion Wu profile")
    body_name = original["resourceName"] + ".glb"
    body = pinned(profile_path.parent / body_name, BODY_SHA256, 32_000_000)
    require(len(body) == original["bytes"], "Body size differs")
    active = next(c for c in original["clips"] if c["name"] == CLIP)
    require(active["sha256"] == MOTION_SHA256 and active["frames"] == 103
            and active["playbackTicks"] == 204 and active["sourceEndEventTick"] == 196,
            "Original Active crop or clock differs")
    source = active["sourceConfiguration"]
    require(source["sourceEntry"] == "settings_style_imperial_spear.bytes"
            and source["sourceSHA256"] == CONFIG_SHA256 and source["sourceRecordIndex"] == 8,
            "Original Imperial Active configuration differs")
    configuration = source["configuration"]
    require(configuration["Animation"] == "Imperial_Spear_Heavy_Slash_Active"
            and configuration["Transitions"] == [[0, True, ["Imperial_Spear_Heavy_Slash_Miss"]]],
            "Active must inherit the original Miss clock through FrameShift zero")
    intervals = [row for row in configuration["Intervals"] if row["Type"] == "Attack"]
    require(len(intervals) == 1, "Expected the one original Active strike")
    interval = intervals[0]
    require(interval["Start"] == 82 and interval["End"] == 85
            and interval["AttackingParts"] == ["Spear_Attacking_Edge_l"]
            and interval["Impulse"] == {"X": 0.0, "Y": -12000.0, "Z": None}
            and interval["HitTags"] == ["Hit_TYPE_HEAVY"]
            and interval["Damage"]["Attack"] == "WeaponDamage"
            and interval["Damage"]["BaseDamage"] == 0.07999999821186066,
            "Original Active contact fields differ")
    # These records already live inside the independently pinned profile.
    # Deduplicate shared aliases, preserving the exact complete source record.
    records = {}
    for clip in original["clips"]:
        record = clip.get("sourceConfiguration")
        if record is None:
            continue
        key = (record["sourceEntry"], record["sourceRecordIndex"])
        require(key not in records or records[key] == record, "Conflicting retained source records")
        records[key] = record
    rules, receipts = combat_rules(original, {"records": list(records.values())})
    previous = original["combatRules"]
    require(len(previous["attacks"]) == 19 and len(rules["attacks"]) == 20
            and rules["attacks"][:-1] == previous["attacks"]
            and {k: v for k, v in rules.items() if k != "attacks"}
                == {k: v for k, v in previous.items() if k != "attacks"},
            "Binding the Active stage changed an established physical attack")
    added = rules["attacks"][-1]
    require(added["command"] == "heavy" and added["clipName"] == CLIP
            and len(added["strikes"]) == 1, "Active rule is missing or ambiguous")
    strike = added["strikes"][0]
    require(strike["startTick"] == 162 and strike["endTick"] == 169
            and strike["damage"] == 80 and strike["blockedDamage"] == 20
            and strike["collisionEdgeIDs"] == ["Spear_Attacking_Edge_l"],
            "Active conversion differs from the original interval")
    profile = copy.deepcopy(original)
    profile["combatRules"] = rules
    require(all(profile[k] == value for k, value in original.items() if k != "combatRules"),
            "Non-combat profile data changed")
    output = fresh_output(output_path)
    os.mkdir(output, 0o700)
    raw = encoded(profile)
    write_private(output / "SF3_Erlang_Profile.json", raw)
    write_private(output / body_name, body)
    receipt = {
        "schema": "erlang-imperial-active-runtime-binding-v1",
        "inputProfileSHA256": INPUT_SHA256,
        "profile": {"name": "SF3_Erlang_Profile.json", "bytes": len(raw),
                    "sha256": hashlib.sha256(raw).hexdigest()},
        "character": {"name": body_name, "bytes": len(body), "sha256": BODY_SHA256},
        "addedRule": added,
        "sourceReceipts": [r for r in receipts if r["clip"] == CLIP],
        "preservedPhysicalAttacks": 19, "preservedClips": 62,
        "bodyAndIndependentModelRulesUnchanged": True,
        "nativePairedRuntimeObserved": False,
        "boundary": "Original source timing, part and damage coefficient; established arena power, recoil and hit-stop adapters remain explicit. A real first contact must select Active, and a real second capsule contact must cause its damage."
    }
    write_private(output / "erlang-imperial-active-binding-private.json", encoded(receipt))
    return {k: receipt[k] for k in ("profile", "character", "preservedPhysicalAttacks", "preservedClips")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(append(args.profile, args.output), sort_keys=True))


if __name__ == "__main__":
    main()
