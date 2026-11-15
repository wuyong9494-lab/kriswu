#!/usr/bin/env python3
"""Bind already recovered D15 intervals to the arena's exact source geometry.

This does not fetch or decode game assets. Outputs stay in the caller's private
staging directory. Full source impulses are retained as evidence; the existing
arena impact response is an explicit adapter, not a claimed native conversion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

SOURCE_VERSION = "1.46.0.16.16733-prod"
DYNASTY_SHA = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
HOUND_SHA = "70e1ebe77b6ba26c01e077b04ca8ecd0abd2220568d69328cfe34788eaf47807"
NAMED_SHA = "030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path, sha: str | None = None):
    raw = path.read_bytes()
    actual = hashlib.sha256(raw).hexdigest()
    require(sha is None or actual == sha, f"Unexpected input bytes: {path.name}")
    return json.loads(raw), {"file": path.name, "bytes": len(raw), "sha256": actual}


def encoded(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()


def interval_ticks(interval, clip):
    config = clip["sourceConfiguration"]["configuration"]
    stride = (config["MidFrames"] if config["MidFrames"] is not None else 1) + 1
    first, last = clip["sourceFirstIndex"], clip["sourceLastIndex"]
    require(stride in (1, 2) and clip["playbackTicks"] == (last - first) * stride,
            "Source clock does not match the actor FK timeline")
    start_index = max(first, 0 if interval["Start"] is None else interval["Start"] - 1)
    end_index = min(last, last if interval["End"] is None else interval["End"] - 1)
    require(first <= start_index <= end_index <= last, "Interval lies outside the recovered actor crop")
    return (start_index - first) * stride, min(clip["playbackTicks"], (end_index - first + 1) * stride - 1)


def build(args):
    actor, actor_record = read_json(args.profile, args.profile_sha256)
    named, named_record = read_json(args.named, NAMED_SHA)
    dog, dog_record = read_json(args.hound, HOUND_SHA)
    _, rules_record = read_json(args.source_rules_receipt)
    require(actor["id"] == actor["hero"] == "wuyong_erlang", "Wrong actor identity")
    records = {(r["sourceEntry"], r["sourceRecordIndex"]): r for r in named["records"]}
    clips = {c["name"]: c for c in actor["clips"]}
    controls = []
    for role, name in sorted(actor["roles"].items()):
        clip = clips[name]
        binding = clip.get("sourceConfiguration")
        if binding is None:
            # Existing paired throws carry their own validated source rules.
            continue
        config = binding["configuration"]
        for interval in config["Intervals"] or []:
            kind = {"Uninterrupt": "uninterrupt", "Blocking": "blocking", "Throwable": "throwable"}.get(interval["Name"])
            if kind is None:
                continue
            start, end = interval_ticks(interval, clip)
            controls.append(dict(role=role, kind=kind, startTick=start, endTick=end,
                sourceConfigurationSHA256=binding["sourceSHA256"], sourceRecordIndex=binding["sourceRecordIndex"]))

    axe = clips[actor["roles"]["erlangAxe"]]
    source = records[("settings_sets_dynasty.bytes", 101)]
    require(axe["sourceConfiguration"] == source and source["sourceSHA256"] == DYNASTY_SHA,
            "Axe actor must use the exact original D15 configuration")
    interval, = [i for i in source["configuration"]["Intervals"] if i["Type"] == "Attack"]
    start, end = interval_ticks(interval, axe)
    parts = interval["AttackingParts"]
    available = {c["id"] for field in ("collisionEdges", "hurtCapsules") for c in axe["tracks"].get(field, [])}
    require(set(parts) <= available, "Axe source attack refers to unavailable original capsules")
    require(interval["Damage"]["Attack"] == "WeaponDamage" and (start, end) == (64, 73),
            "Axe source attack changed")
    axe_attack = dict(id="d15_axe_source_101", ability="axe", role="erlangAxe", modelRole=None,
        sourceConfigurationSHA256=DYNASTY_SHA, sourceRecordIndex=101, startTick=start, endTick=end,
        parts=parts, damageKind="weapon", baseDamageBps=round(interval["Damage"]["BaseDamage"] * 10_000),
        unblockable="Unblockable" in interval["HitTags"], knocksDown=True,
        impact=dict(distanceMillimeters=200, durationTicks=10, launchVelocityMillimetersPerTick=0,
                    gravityMillimetersPerTickSquared=18), hitStopTicks=2, hitTags=interval["HitTags"])
    require(dog["track"]["role"] == "erlangSummon_hound" and dog["track"]["sourceEndEventTick"] == 110,
            "Dog source lifetime changed")
    dog_attack = dict(dog["attackBinding"], hitTags=dog["sourceAttack"]["HitTags"])
    runtime = dict(schemaVersion=1, sourceVersion=SOURCE_VERSION, sourceSHA256=rules_record["sha256"],
        maximumHealth=2000, normalizedWeaponPower=1000, normalizedUnarmedPower=1000,
        normalizedMagicPower=1000, normalizedRangedPower=1000,
        attacks=[dog_attack, axe_attack], releases=[dog["releaseBinding"]], controls=controls)
    evidence = dict(schema="erlang-runtime-source-bindings-v1", inputs=[actor_record, named_record, dog_record, rules_record],
        sourceConfigurationVersion=SOURCE_VERSION, normalizedPowers=dict(weapon=1000, unarmed=1000, magic=1000, ranged=1000),
        maximumHealth=2000,
        damagePolicy="BaseDamage multiplies the explicit normalized power, independently of maximumHealth.",
        impactPolicy="200 mm / 10 ticks / no extra external launch / gravity 18 / hit-stop 2 is the arena response adapter; source Impulse is not numerically reinterpreted as millimetres.",
        attacks=[dict(id=dog_attack["id"], sourceInterval=dog["sourceAttack"]),
                 dict(id=axe_attack["id"], sourceInterval=interval)],
        controlsCount=len(controls),
        remainingModelAbilities=["meditation explosion", "stomp", "eye", "earth", "swords", "judgement"],
        resourceAvailabilityDoesNotProveGameplayOrNativeVisualAcceptance=True)
    require(not args.output.exists(), "Output directory already exists")
    args.output.mkdir(parents=True)
    outputs = []
    for filename, value in [("SF3_Erlang_Runtime_Rules.json", runtime),
                            ("erlang-runtime-binding-evidence-private.json", evidence)]:
        raw = encoded(value)
        with (args.output / filename).open("xb") as file:
            file.write(raw)
        outputs.append(dict(file=filename, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
    return {"outputs": outputs, "attacks": len(runtime["attacks"]), "releases": len(runtime["releases"]), "controls": len(controls)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("profile", "named", "hound", "source-rules-receipt", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--profile-sha256", required=True)
    print(json.dumps(build(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
