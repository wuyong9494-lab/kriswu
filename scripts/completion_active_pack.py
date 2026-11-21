#!/usr/bin/env python3
"""Verify the active fighter pack after retiring the legacy hammer GLB.

The original 541-file inventory remains immutable as recovery evidence.
Only the retired model and a separately staged XCTest oracle are excluded.
This does not sign, upload, stage, move, or delete any source file.
"""
import argparse
import hashlib
import json
from pathlib import Path

import completion_native_preflight as original

RETIRED = {"name": "Liu_Legion_Hammers.glb", "bytes": 11_585_516,
           "sha256": "d873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80"}
TEST_ONLY = {"name": "Validation_D13_Bottle_Source_Oracle.json", "bytes": 10_209,
             "sha256": "5621596a5a4713aa39132f16aaae672766ba0a7ad0ea1e9895cd6272a40f93f4"}
EXCLUDED = {RETIRED["name"]: RETIRED, TEST_ONLY["name"]: TEST_ONLY}
REQUIRED = frozenset({"Liu_KingOfSerpents_D13_Recovered_Combat.glb", "SF3_Serpent_Profile.json",
                      "SF3_D13_Bottle_Source.glb",
                      "SF3_H17_SerpentMorph.json", "Sun_DeadForestTriad_Ninjato.glb",
                      "SF3_DistinctFighters.json", "SF3_FighterRelease.json"})


def active_inventory(root):
    _, historical = original.metadata(root)
    rows = historical["compiledFiles"]
    original.require({r["name"]: r for r in rows if r["name"] in EXCLUDED} == EXCLUDED,
                     "retirement-pin", "Historical exclusions differ")
    active = [r for r in rows if r["name"] not in EXCLUDED]
    original.require(REQUIRED <= {r["name"] for r in active} and len(active) == 539,
                     "active-pack-closure", "Missing an active character or release resource")
    canonical = (json.dumps({"buildSettings": historical["buildSettings"], "files": active},
                            ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
    return active, hashlib.sha256(canonical).hexdigest()


def inspect(root, *, staged=None, app=None):
    active, content_sha = active_inventory(root)
    report = {"requiredFiles": len(active), "requiredBytes": sum(r["bytes"] for r in active),
              "compiledContentSHA256": content_sha, "historicalLedgerSHA256": original.INVENTORY_SHA256,
              "retired": RETIRED["name"], "testOnly": TEST_ONLY["name"], "stage": None, "app": None, "deviceTested": False,
              "testflightUploaded": False}
    if staged is not None:
        report["stage"] = original.flat_resources(staged, active)
    if app is not None:
        report["app"] = original.app_resources(app, active, forbidden_names=EXCLUDED.keys(),
                                               compiled_sha256=content_sha)
    return report


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument("--stage", type=Path)
    p.add_argument("--app", type=Path)
    a = p.parse_args()
    try:
        print(json.dumps(inspect(a.repo, staged=a.stage, app=a.app), indent=2))
    except (original.CheckError, OSError, ValueError) as exc:
        p.exit(1, f"Active pack validation failed: {exc}\n")
