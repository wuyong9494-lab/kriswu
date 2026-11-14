#!/usr/bin/env python3
"""Bind private source exports to the H17 runtime without publishing source media.

The caller supplies private, independently recovered configuration snapshots.
The output contains original geometry/timings and belongs in the encrypted pack.
Stat normalization and the arena impulse adapter remain explicitly identified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from sun_triad_assets import private_output, require


OWNER_ROLES = {
    "triadBranches": "H17_Root_Spike_Start",
    "triadBranchesLoop": "H17_Root_Spike_Loop",
    "triadBranchesEnd": "H17_Root_Spike_End",
    "triadMistBlade": "H17_Blade_Ability",
    "triadMistOnslaught": "H17_Illusion_Wave_1",
    "triadMistOnslaught2": "H17_Illusion_Wave_2",
    "triadMistOnslaught3": "H17_Illusion_Wave_3",
    "triadCryingDance": "H17_Trans_In",
    "triadCryingDanceLoop": "H17_Trans_Loop",
    "triadCryingDanceOut": "H17_Trans_Out",
}
COMMANDS = {
    "weapon": ["Ninjato_Slash_1", "Ninjato_Slash_2"],
    "heavy": ["Ninjato_Heavy_Slash"],
    "weaponUp": ["Ninjato_Upper_Slash"],
    "weaponDown": ["Ninjato_Low_Slash"],
    "weaponBack": ["Ninjato_Spinning_Slash_1", "Ninjato_Spinning_Slash_2"],
    "weaponForward": ["Ninjato_Super_1_Slash_1", "Ninjato_Super_1_Slash_2"],
    "kick": ["K_Prc_Kick_1", "K_Prc_Kick_2", "K_Prc_Jump_Up"],
    "kickForward": ["K_Prc_Front_Kick", "K_Prc_Jump_Up"],
    "kickDown": ["K_Prc_Low", "K_Prc_Jump_Up"],
    "kickBack": ["K_Prc_Spinning_Kick", "K_Prc_Jump_Up"],
}
PHYSICAL_OWNER_ROLES = ("triadBranches", "triadMistOnslaught", "triadMistOnslaught2", "triadMistOnslaught3")
HOST_ATTACKS = {
    "triadSummon_legionSword": "H17_Spirit_Legion_Twohanded_Sword_Heavy_Slash",
    "triadSummon_heraldDash": "H17_Spirit_Herald_Shadow_Dash",
    "triadSummon_legionHammer": "H17_Spirit_Legion_Hammer",
    "triadSummon_danceNinjato": "H17_Spirit_Herald_Ninjato_Slash_Miss",
    "triadSummon_ninjatoActiveEnd": "H17_Spirit_Herald_Ninjato_Active_End",
    "triadSummon_danceRift1": "H17_Spirit_Rift_1",
    "triadSummon_danceRift2": "H17_Spirit_Rift_2",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def file_record(path: Path) -> dict:
    return dict(name=path.name, bytes=path.stat().st_size, sha256=digest(path))


def build(args) -> dict:
    character_profile = args.character_profile or args.candidate / "Sun_DeadForestTriad_Ninjato_profile.json"
    candidate = load(character_profile)
    character_model = character_profile.parent / (candidate["resourceName"] + ".glb")
    require(digest(character_model) == candidate["sha256"] and character_model.stat().st_size == candidate["bytes"], "Main source character pin mismatch")
    rules = load(args.rules)
    require(rules.get("runtime") is not None and rules["level"] == 6, "Expected exported source H17 L6 rules")
    snapshots = [load(args.settings), load(args.kicks)]
    records = {r["configuration"]["Animation"]: r for d in snapshots for r in d["records"]}
    clips = {c["name"]: c for c in candidate["clips"]}
    profile_keys = ("id", "hero", "faction", "resourceName", "bytes", "sha256", "bodyID", "weaponID", "activeWeaponSides", "roles", "clips")
    profile = {key: candidate[key] for key in profile_keys}
    profile["roles"] = {key: value for key, value in profile["roles"].items() if not key.startswith("shadow")}
    profile["roles"]["weaponBack"] = "ninjato_spinning_slash_1"
    profile["triadRules"] = rules
    if args.ordinary_throws:
        throws = load(args.ordinary_throws)
        require(throws.get("source") and not throws.get("attempts") and
                throws.get("simultaneousContactPolicy") == "sourceComplementaryLottery",
                "Expected source immediate paired throw rules")
        require(all(c["tracks"].get("centerOfMass") and
                    len(c["tracks"]["centerOfMass"]) == 2 * c["frames"] - 1 for c in candidate["clips"]),
                "Source throw profile is missing original mass-weighted COM tracks")
        profile["ordinaryThrows"] = throws
    if args.model_tracks:
        model_tracks = load(args.model_tracks)
        require(set(model_tracks) == {"roots", "mistWave"}, "Expected both independent source model tracks")
        rules["runtime"]["modelTracks"] = model_tracks

    def source_clip(animation: str):
        record = records[animation]
        name = Path(record["configuration"]["FileName"]).stem
        require(name in clips, "Missing original clip: " + name)
        return record, clips[name]

    for role, animation in OWNER_ROLES.items():
        record, clip = source_clip(animation)
        require(record["configuration"]["FirstFrame"] is None and record["configuration"]["EndFrame"] is None,
                "Owner crop requires an explicit timing adapter")
        profile["roles"][role] = clip["name"]

    # Separate source hit parts from the application's stats/impulse adapter.
    attacks, attack_receipts = [], []
    power = {"WeaponDamage": args.weapon_power, "UnarmedDamage": args.unarmed_power}
    impulse = dict(distanceMillimeters=160, durationTicks=8, launchVelocityMillimetersPerTick=0,
                   gravityMillimetersPerTickSquared=18)
    blocked_impulse = dict(distanceMillimeters=60, durationTicks=6, launchVelocityMillimetersPerTick=0,
                           gravityMillimetersPerTickSquared=18)

    def attack_rule(command: str, animation: str):
        record, clip = source_clip(animation); config = record["configuration"]
        require(config["MidFrames"] in (None, 1), "Unbound source stride")
        shapes = clip["tracks"].get("collisionEdges", []) + clip["tracks"].get("hurtCapsules", [])
        by_id = {shape["id"]: shape for shape in shapes}
        strikes = []
        for interval in config["Intervals"] or []:
            if interval["Type"] != "Attack": continue
            parts = interval["AttackingParts"]
            require(parts and set(parts) <= set(by_id), "Unbound physical source attack capsule: " + animation)
            factor = interval["Damage"]
            require(factor and factor["Attack"] in power and factor["BaseDamage"] is not None,
                    "Unknown source physical damage formula")
            damage = round(factor["BaseDamage"] * power[factor["Attack"]])
            start = 2 * max(0, (interval["Start"] or 1) - 1)
            end = min(2 * (clip["frames"] - 1), 2 * (interval["End"] or clip["frames"]) - 1)
            sides = [] if command.startswith("kick") else sorted({by_id[p]["side"] for p in parts if "side" in by_id[p]})
            require(command.startswith("kick") or sides, "Weapon strike lacks an original blade part")
            strikes.append(dict(id=len(strikes), startTick=start, endTick=end, weaponSides=sides,
                damage=damage, blockedDamage=round(damage * .25), knocksDown=False,
                hitStopTicks=4, blockedHitStopTicks=2, impact=impulse, blockedImpact=blocked_impulse,
                collisionEdgeIDs=parts))
            attack_receipts.append(dict(animation=animation, clip=clip["name"], command=command,
                sourceEntry=record["sourceEntry"], sourceSHA256=record["sourceSHA256"],
                sourceRecordIndex=record["sourceRecordIndex"], interval=interval, normalizedDamage=damage,
                applicationWeaponPower=args.weapon_power, applicationUnarmedPower=args.unarmed_power))
        require(strikes, "Physical attack has no source interval: " + animation)
        attacks.append(dict(command=command, clipName=clip["name"], strikes=strikes))

    for command, animations in COMMANDS.items():
        for animation in animations: attack_rule(command, animation)
    for role in PHYSICAL_OWNER_ROLES: attack_rule("weapon", OWNER_ROLES[role])
    profile["combatRules"] = dict(id="h17-black-ninjato-source-geometry-v1", basis="applicationAdaptation",
        sourceVersion=rules["runtime"]["evidence"]["version"], evidence=[
            "Original Ninjato/H17 attack intervals, damage ratios, bone capsules and 60 Hz frame conversion.",
            "Application normalization: WeaponDamage=" + str(args.weapon_power) + "; UnarmedDamage=" + str(args.unarmed_power) + ".",
            "Hit-stop and impulse distances remain the explicitly identified arena adapter, not raw source Newton forces."], attacks=attacks)

    # Combo control is provided as a separate recovered native receipt. Do not
    # infer an input transition from visually similar adjacent animation poses.
    combo = load(args.combo)
    require(combo.get("basis") == "sourceConfiguration" and combo.get("links"), "Expected recovered source combo receipt")
    profile["comboLinks"] = combo["links"]
    for link in profile["comboLinks"]:
        require(link["from"] in clips and link["to"] in clips and
                0 <= link["sourceFrame"] < min(clips[link["from"]]["frames"], clips[link["to"]]["frames"]) - 1,
                "Invalid original combo anchor")

    summons = load(args.candidate / "spirits/SF3_H17_Summons.json")
    tracks = load(args.candidate / "spirits/SF3_H17_Summon_Tracks.json")
    require(summons["characterSHA256"] == tracks["characterSHA256"] == profile["sha256"], "Companion character identity mismatch")
    require(tracks["sourceManifestSHA256"] == digest(args.candidate / "spirits/SF3_H17_Summons.json"), "Companion track manifest mismatch")
    geometry = {role: motion for motion in tracks["motions"] for role in motion["roles"]}
    source_parts = {r["animation"]: r for r in load(args.soul_attacks)["records"]}
    result_tracks = []
    for model in summons["models"]:
        for motion in model["motions"]:
            for role in motion["roles"]:
                shape = geometry[role]
                require(shape["clip"] == motion["clip"] and shape["sourceSHA256"] == motion["sourceSHA256"] and
                        shape["tracks"]["root"] == motion["root"] and shape["tracks"]["groundLift"] == motion["groundLift"],
                        "Companion renderer/simulation samples disagree")
                parts = {}
                if role in HOST_ATTACKS:
                    attacks_source = source_parts[HOST_ATTACKS[role]]["Attacks"]
                    require(len(attacks_source) == 1, "Unexpected multi-strike companion binding")
                    parts["ninjatoFinal" if role == "triadSummon_ninjatoActiveEnd" else "primary"] = attacks_source[0]["AttackingParts"]
                result_tracks.append(dict(role=role, clip=motion["clip"], frames=motion["frames"],
                    sourceSHA256=motion["sourceSHA256"], sourceBundle=motion["sourceBundle"], root=motion["root"], groundLift=motion["groundLift"],
                    boneConfigurationSHA256=shape["sourceBoneConfigurationSHA256"],
                    collisionEdges=shape["tracks"]["collisionEdges"], hurtCapsules=shape["tracks"]["hurtCapsules"], attackParts=parts))
    require(len(result_tracks) == 20, "Expected all twenty source companion roles")
    profile["summonTracks"] = sorted(result_tracks, key=lambda item: item["role"])
    output = private_output(args.output); output.mkdir(parents=True, exist_ok=True)
    target = output / "SF3_Triad_Profile.json"
    target.write_text(json.dumps(profile, ensure_ascii=False, separators=(",", ":")) + "\n")
    receipt = dict(profile=file_record(target), character=file_record(character_model),
        sourceInputs=[file_record(path) for path in (character_profile, args.settings, args.kicks, args.rules,
            args.combo, args.soul_attacks, args.ordinary_throws, args.model_tracks) if path is not None],
        ownerRoles=OWNER_ROLES, attackIntervals=attack_receipts, companionRoles=len(result_tracks),
        collisionGeometry="source FK half-frame capsules", sourceTiming="60 Hz / MidFrames default 1; source frame stride 2")
    (output / "SF3_Triad_Profile_receipt-private.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    return dict(profile=target.name, sha256=digest(target), bytes=target.stat().st_size,
                attacks=len(attacks), strikes=sum(len(a["strikes"]) for a in attacks), companionRoles=len(result_tracks))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "settings", "kicks", "rules", "combo", "soul-attacks", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("character-profile", "ordinary-throws", "model-tracks"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--weapon-power", type=int, default=1000)
    parser.add_argument("--unarmed-power", type=int, default=1000)
    args = parser.parse_args()
    require(1 <= args.weapon_power <= 1_000_000 and 1 <= args.unarmed_power <= 1_000_000, "Invalid normalized power")
    print(json.dumps(build(args)))


if __name__ == "__main__": main()
