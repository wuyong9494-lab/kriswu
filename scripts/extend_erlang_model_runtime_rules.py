#!/usr/bin/env python3
"""Join the seven authenticated D15 model tracks to the real actor profile.

Static releases use the original named body IntervalStart. Meditation release
and the six persistent swords require their own state events and are recorded
separately; this builder never invents a body marker for either one.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path

from append_cached_root_victim_motions import encoded, pinned
from stage_h17_floorfall_release import fresh_output, write_private
from sun_triad_assets import require


MODELS_SHA = "870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc"
HELD_SHA = "22cf4bd31691a19adeaf92b10e745ca452c4f5d31ac390893a742527caf6b55e"
SOURCE_SHA = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
SOURCE_VERSION = "1.46.0.16.16733-prod"
STATIC = {
    "erlangSummon_stomp": ("erlangStep", "D15_Leg_Model_Create", "enemy.pelvis.x", 2),
    "erlangSummon_earth": ("erlangEarthshaker", "D15_Spear_Ground_Shake_Model_Creation", "pelvis.x", 2),
    "erlangSummon_eye": ("erlangEye", "D15_Laser_Fx", "head.x", 2),
    "erlangSummon_judgement": ("erlangJudgment", "D15_Ulta_DMG", "head.x", 6),
    "erlangSummon_aftershock": ("erlangAxe", "D15_Ground_FX", "pelvis.x", 6),
}
OWNER_ROLE = dict((role, row[0]) for role, row in STATIC.items()) | {
    "erlangSummon_meditation": "erlangMeditationEnd",
    "erlangSummon_sword": "erlangSwords",
}
KINDS = {"WeaponDamage": "weapon", "UnarmedDamage": "unarmed", "MagicPower": "shadow", "RangedDamage": "ranged"}


def source_marker_tick(clip, name):
    binding = clip["sourceConfiguration"]
    require(binding["sourceSHA256"] == SOURCE_SHA, "Expected original D15 body configuration")
    config = binding["configuration"]
    intervals = [i for i in config["Intervals"] if i["Name"] == name]
    require(len(intervals) == 1, "Missing or ambiguous source creation marker")
    interval = intervals[0]
    start = max(0, (interval["Start"] or 1) - 1)
    stride = (1 if config["MidFrames"] is None else config["MidFrames"]) + 1
    tick = (start - clip["sourceFirstIndex"]) * stride
    require(0 <= tick <= clip["sourceEndEventTick"], "Creation occurs after the body end event")
    return tick


def extend(profile, source):
    require(profile["id"] == profile["hero"] == "wuyong_erlang"
            and source["sourceConfigurationSHA256"] == SOURCE_SHA,
            "Wrong original D15 actor or model configuration")
    result = deepcopy(profile)
    rules = result["erlangRules"]
    require(rules["sourceVersion"] == SOURCE_VERSION and len(rules["attacks"]) == 2
            and len(rules["releases"]) == 1, "Expected the reviewed body-and-hound base rules")
    require(len(source["models"]) == len(source["summonTracks"]) == len(source["receipts"]) == 7,
            "Expected seven distinct source model windows")
    tracks = {t["role"]: t for t in source["summonTracks"]}
    require(set(tracks) == set(OWNER_ROLE), "Model role set differs")
    existing = result.get("summonTracks", [])
    require(len(existing) == 1 and existing[0]["role"] == "erlangSummon_hound",
            "Independent models are already bound or the hound is missing")
    result["summonTracks"] = existing + deepcopy(source["summonTracks"])
    clips = {c["name"]: c for c in result["clips"]}
    evidence = dict(schema="erlang-independent-model-runtime-bindings-v1", sourceConfigurationSHA256=SOURCE_SHA,
        attacks=[], releases=[], omittedExpiredIntervals=[], dynamicEvents=[],
        damagePolicy="Source BaseDamage times the explicit arena power; meditation remains source BaseDamage=0 until a149 overrides normalized hit damage.",
        responsePolicy="Existing arena response adapter: 200mm/10ticks, no added launch, gravity18, hitstop2. Original impulses and reaction tags retained separately.")
    for model, receipt in zip(source["models"], source["receipts"]):
        role = model["role"]
        require(receipt["role"] == role and model["sourceConfigurationSHA256"] == SOURCE_SHA,
                "Model and source receipt order differs")
        track = tracks[role]
        require(track["sourceEndEventTick"] == model["sourceEndEventTick"]
                and track.get("sourceDeleteEventTick") == model["sourceDeleteEventTick"],
                "Model deletion/end clock differs")
        parts = {e["id"] for e in track["collisionEdges"]}
        for interval in model["sourceAttackIntervals"]:
            window = interval["effective"]
            if window is None:
                evidence["omittedExpiredIntervals"].append(dict(role=role, interval=interval))
                continue
            original = interval["original"]
            require(0 <= window["startTick"] <= window["endTick"] <= model["effectiveLastTick"]
                    and set(original["AttackingParts"]) <= parts,
                    "Attack exceeds original lifetime or refers to missing source geometry")
            damage = original["Damage"]
            require(damage["Attack"] in KINDS and damage["BaseDamage"] is not None,
                    "Unsupported original damage kind")
            tags = original["HitTags"] or []
            identity = f"d15_model_{model['sourceRecordIndex']}_{interval['index']}"
            rules["attacks"].append(dict(id=identity, ability=model["ability"], role=OWNER_ROLE[role],
                modelRole=role, sourceConfigurationSHA256=SOURCE_SHA,
                sourceRecordIndex=model["sourceRecordIndex"], startTick=window["startTick"], endTick=window["endTick"],
                parts=original["AttackingParts"], damageKind=KINDS[damage["Attack"]],
                baseDamageBps=round(damage["BaseDamage"] * 10_000), unblockable="Unblockable" in tags,
                knocksDown=any(t.endswith("_Fall") or t == "To_Physics" for t in tags),
                impact=dict(distanceMillimeters=200, durationTicks=10,
                    launchVelocityMillimetersPerTick=0, gravityMillimetersPerTickSquared=18),
                hitStopTicks=2, hitTags=tags))
            evidence["attacks"].append(dict(id=identity, role=role, original=original,
                                             native=interval["native"], effective=window))
        if role in STATIC:
            owner_role, marker, anchor, minimum_level = STATIC[role]
            owner_clip = clips[result["roles"][owner_role]]
            if anchor == "head.x":
                head = owner_clip["tracks"].get("head")
                require(head is not None and len(head) == 2 * owner_clip["frames"] - 1,
                        "Real head FK is required for original beam alignment")
            creation = receipt["creation"]
            triggers = creation["creationTriggers"]
            require(len(triggers) == 1 and {"a18": ["enum65537", marker]} in triggers[0]["events"],
                    "Source creation event does not match the actual body marker")
            shift = model["origin"]["sourceShiftCentimeters"] or [0, 0, 0]
            require(shift in ([0, 0, 0], [2000, 0, 0]), "Unreviewed original model shift")
            offset = [component / 100 for component in shift]
            release = dict(id=f"d15_create_{model['sourceRecordIndex']}", ability=model["ability"],
                ownerRole=owner_role, atTick=source_marker_tick(owner_clip, marker), modelRole=role,
                anchor=anchor, offset=offset, minimumLevel=minimum_level)
            rules["releases"].append(release)
            evidence["releases"].append(dict(binding=release, sourceCreation=creation, sourceOrigin=model["origin"],
                coordinates="Source target axes only; Shift centimeters/100, transformed by cast direction once. Track root displacement is added separately once."))
        else:
            evidence["dynamicEvents"].append(dict(role=role, creation=receipt["creation"],
                sourceOrigin=model["origin"], stateEventRequired=True,
                reason="Input release or persistent sword slot transition, not a named body IntervalStart."))
    require(len(rules["attacks"]) == 36 and len(rules["releases"]) == 6,
            "Unexpected original effective attack/release count")
    return result, evidence


def append_held_swords(profile, evidence, held):
    require(held["schema"] == "original-d15-sword-held-poses-v1"
            and held["sourceConfigurationSHA256"] == SOURCE_SHA
            and held["modelCandidateSHA256"] == MODELS_SHA,
            "Held poses do not belong to these original D15 source models")
    roles = {f"erlangSummon_swordBirth{i}" for i in range(1, 7)} | {"erlangSummon_swordIdle"}
    tracks = held["summonTracks"]
    require(len(tracks) == 7 and {t["role"] for t in tracks} == roles
            and not roles.intersection(t["role"] for t in profile["summonTracks"]),
            "Expected distinct original six-slot birth and idle tracks")
    require(all(t["sourceEndEventTick"] == 92 and t.get("sourceDeleteEventTick") is None for t in tracks)
            and held["lifecycle"]["birthEndAction"] == "D15_Hovering_Sword_Model_Idle",
            "Birth AnimationEnd transitions to idle; it cannot delete the held sword")
    profile["summonTracks"].extend(deepcopy(tracks))
    states = {m["role"]: m for m in held["models"]}
    slots = []
    for slot in range(1, 7):
        role = f"erlangSummon_swordBirth{slot}"
        model = states[role]
        require(model["slot"] == slot and model["sourceRecordIndex"] == 109 + slot
                and model["origin"]["selectedAlignAxes"] == ["X", "Z"],
                "Sword slot and parent alignment differ from the original birth record")
        shift = model["origin"]["sourceShiftCentimeters"]
        # Native Align39421 flips only Shift.X for LEFT. Unity-to-Arena
        # reflects Z once; neither source RIGHT nor cast direction flips Z.
        slots.append(dict(slot=slot, birthRole=role,
            offset=[shift[0] / 100, shift[1] / 100, -shift[2] / 100],
            sourceRecordIndex=model["sourceRecordIndex"]))
    require(profile["erlangRules"].get("swordSlots") is None, "Sword slots are already bound")
    profile["erlangRules"]["swordSlots"] = slots
    evidence["heldSwordSourceSHA256"] = HELD_SHA
    evidence["heldSwordLifecycle"] = deepcopy(held["lifecycle"])
    evidence["heldSwordBindings"] = slots
    evidence["heldSwordShiftContract"] = "Align39421: only source X reverses for LEFT. Arena offset=[cmX,cmY,-cmZ]/100. Parent pelvis supplies X/Z; Y remains the source offset. RIGHT rotation is already in model FK and is not applied to Shift."
    evidence["heldSwordStates"] = [dict(role=m["role"], slot=m["slot"],
        sourceRecordIndex=m["sourceRecordIndex"], origin=m["origin"],
        sourceLooped=m["sourceLooped"], sourceSounds=m["sourceSounds"],
        sourceChecks=m["sourceChecks"]) for m in held["models"]]
    evidence["heldSwordBoundary"] = "Rotate retains its single original pose in the authenticated held candidate; it is not padded into a sampled summon track. Birth/idle state changes require the live source state machine."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("profile", "models", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--profile-sha256", required=True)
    parser.add_argument("--sword-holds", type=Path)
    args = parser.parse_args()
    raw_profile = pinned(args.profile, args.profile_sha256, 32_000_000)
    raw_models = pinned(args.models, MODELS_SHA, 1_000_000)
    profile, evidence = extend(json.loads(raw_profile), json.loads(raw_models))
    if args.sword_holds:
        append_held_swords(profile, evidence, json.loads(pinned(args.sword_holds, HELD_SHA, 1_000_000)))
    evidence["inputProfileSHA256"] = args.profile_sha256; evidence["inputModelsSHA256"] = MODELS_SHA
    receipt = encoded(evidence); profile["erlangRules"]["sourceSHA256"] = hashlib.sha256(receipt).hexdigest()
    output = fresh_output(args.output); os.mkdir(output, 0o700)
    files = {}
    for name, raw in (("SF3_Erlang_Profile.json", encoded(profile)),
                      ("SF3_Erlang_Runtime_Rules.json", encoded(profile["erlangRules"])),
                      ("erlang-model-runtime-binding-private.json", receipt)):
        write_private(output / name, raw)
        files[name] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    print(json.dumps(dict(files=files, attacks=len(profile["erlangRules"]["attacks"]),
                         releases=len(profile["erlangRules"]["releases"]),
                         summonTracks=len(profile["summonTracks"]),
                         dynamicStateEventsPending=True), sort_keys=True))


if __name__ == "__main__":
    main()
