#!/usr/bin/env python3
"""Join recovered D19 motion identities to semantic animation markers.

Inputs are local recovery receipts, not original assets for publication. The
output contains identities, digests, frame markers, and sound identifiers only.
It deliberately preserves absent configuration values and does not infer a
complete clip, effect, sound, or skeleton binding from a matching alias.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath


MARKERS = (
    "FirstFrame", "EndFrame", "MidFrames", "Looped", "BlendingFrames",
    "SelfEndFrame", "Mirrored", "SelfNoMirroring", "IgnoreWeaponMirroring",
    "ShowAllSkeletons", "ForceDetachWeapon", "SaveMirroringOnNextAnimation",
    "ForceDisableSnapping", "WeaponSwitchFrames", "EndsStage", "Groups",
    "ComboAnimations", "AttackType",
)
DEFAULTS = {
    "MidFrames": 1, "FirstFrame": 0, "EndFrame": 2147483647,
    "Looped": False, "BlendingFrames": 4, "SelfEndFrame": 4,
}
NATIVE_SHA256 = "7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b"


def load(path: Path) -> dict:
    raw = path.read_bytes()
    if len(raw) > 8_000_000:
        raise ValueError("Recovery receipt exceeds the input limit")
    return json.loads(raw)


def build(bindings: dict, configurations: dict, source_root: Path | None = None) -> dict:
    if configurations["knownDefaults"] != DEFAULTS:
        raise ValueError("The verified native defaults changed; review before regeneration")
    configuration_version = configurations["packagedConfigurationVersion"]
    if configuration_version != bindings["sourceConfigurationVersion"]:
        raise ValueError("Mixed configuration versions")
    selected = {}
    for record in configurations["records"]:
        name = record["configuration"]["Animation"]
        if not name.startswith("D19_"):
            continue
        if name in selected:
            raise ValueError("Duplicate D19 configuration")
        selected[name] = record
    results, seen = [], set()
    for binding in bindings["records"]:
        name = binding["animation"]
        if name in seen or name not in selected:
            raise ValueError("Duplicate or unknown recovered alias")
        seen.add(name)
        original = selected[name]
        config = original["configuration"]
        if config["FileName"] != binding["sourceFile"]:
            raise ValueError("Motion identity mismatch")
        path = PurePosixPath(binding["sourceFile"])
        if path.is_absolute() or ".." in path.parts or path.suffix != ".bin":
            raise ValueError("Invalid source motion path")
        if source_root is not None:
            raw_path = source_root / Path(binding["rawPath"]).name
            raw = raw_path.read_bytes()
            if len(raw) != binding["rawBytes"] or hashlib.sha256(raw).hexdigest() != binding["rawSHA256"]:
                raise ValueError("Recovered original object no longer matches its receipt")
        arrays = binding["arrays"]
        if not arrays or any(a["frameCount"] <= 0 or len(a["boneIDs"]) != len(set(a["boneIDs"])) for a in arrays):
            raise ValueError("Invalid decoded array inventory")
        identity = {
            "sourceFile": str(path), "sourceBundle": binding["sourceBundle"],
            "sourceObjectPath": "assets/gamedata/resources/content/animations/binaries/" + str(path.with_suffix(".bytes")),
            "pathID": str(binding["pathID"]), "bytes": binding["rawBytes"],
            "sha256": binding["rawSHA256"], "arrays": arrays,
        }
        if "sourceURL" in binding:
            identity["publicDownload"] = {
                "url": binding["sourceURL"], "bytes": binding["downloadBytes"],
                "sha256": binding["downloadSHA256"],
                "wholeBundleEqualToOlderAPK": False,
            }
        results.append({
            "animation": name,
            "configurationSource": {"entry": original["sourceEntry"], "sha256": original["sourceSHA256"], "recordIndex": original["sourceRecordIndex"]},
            "motion": identity,
            "rawMarkers": {key: config[key] for key in MARKERS},
            "soundMarkers": config["Sounds"],
            "intervalMarkers": [
                {key: interval.get(key) for key in ("Name", "Type", "Start", "End")}
                for interval in (config["Intervals"] or [])
            ],
        })
    if len(results) != bindings["aliases"] or len({r["motion"]["sha256"] for r in results}) != bindings["uniqueClips"]:
        raise ValueError("Recovery counts do not match actual unique source objects")
    missing = [{"animation": name, "sourceFile": record["configuration"]["FileName"]}
               for name, record in selected.items() if name not in seen]
    return {
        "schema": "pangu-original-motion-semantic-inventory-v1",
        "suppliedClientVersion": configurations["suppliedClientVersion"],
        "packagedConfigurationVersion": configuration_version,
        "recoveredAliasCount": len(results),
        "recoveredSourceObjectCount": len({r["motion"]["sha256"] for r in results}),
        "unrecoveredAliasCount": len(missing),
        "unrecoveredSourceFileCount": len({r["sourceFile"] for r in missing}),
        "verifiedNativeDefaults": DEFAULTS,
        "nativeEvidence": {
            "imageSHA256": NATIVE_SHA256,
            "animationSchemaMethod": 16684,
            "animationReaderMethods": [16478, 16506],
            "simulationClockHz": 60,
            "simulationClockMethods": [25564, 36929, 36942, 25601, 26044, 26047],
            "sampleAdvanceMethods": [39552, 39182],
            "sampleAdvance": "Each core step advances the source frame position by the supplied animation speed divided by (configured MidFrames + 1).",
            "intervalMarkers": "A positive Start/End value is converted to max(value - 1, 0); method 39602.",
            "soundMarkers": "Frame is converted to max(value, 0), without subtracting one; method 39579.",
            "animationEndEvent": "Method 39182 invokes the event when EndIndex - floor(position) <= SelfEndFrame; delegate 39328 is installed by 39347 through 39149 and reaches AnimationEnd in 37586.",
        },
        "interpretation": [
            "null is an absent source value, not zero; only the listed native defaults are resolved here.",
            "Frame markers remain in their source coordinate system. Clip cropping and event projection must account for FirstFrame, EndFrame, MidFrames, SelfEndFrame, and animation speed.",
            "Both packed arrays are retained. The second array is not asserted to be a second animation or mirrored track.",
            "An original sound identifier is not evidence that its audio bytes have been recovered.",
            "An alias resolving to a shared source motion does not establish the missing dedicated Pangu mesh or effect binding.",
        ],
        "records": results,
        "unrecovered": missing,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bindings", type=Path, required=True)
    parser.add_argument("--configurations", type=Path, required=True)
    parser.add_argument("--verify-source-root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(load(args.bindings), load(args.configurations), args.verify_source_root)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print(json.dumps({key: result[key] for key in ("recoveredAliasCount", "recoveredSourceObjectCount", "unrecoveredAliasCount", "unrecoveredSourceFileCount")}))


if __name__ == "__main__":
    main()
