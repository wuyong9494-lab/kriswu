#!/usr/bin/env python3
"""Read-only inventory of encrypted fighter manifests; never decrypt or stage assets.

This verifies manifest structure and intended character/weapon identity only.
It does NOT establish ownership, licensing, actual mesh contents or visual quality.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "private"
DISTINCT = ROOT / "sf3-distinct" / "manifest.json"
ORIGINAL = ROOT / "sf3-original" / "manifest.json"
REQUIRED = {
    "Sun_Herald_Katana.glb",
    "Liu_Legion_Hammers.glb",
    "SF3_DistinctFighters.json",
    "SF3FX_manifest.json",
    "SF3WE_manifest.json",
}
ORIGINAL_REQUIRED = {"Sun_OriginalRig_ActionSet.glb", "Liu_OriginalRig_ActionSet.glb"}


def inspect(distinct=DISTINCT, original=ORIGINAL):
    a = json.loads(Path(distinct).read_text(encoding="utf-8"))
    b = json.loads(Path(original).read_text(encoding="utf-8"))
    if a.get("version") != 1 or b.get("version") != 1:
        raise ValueError("Unsupported manifest version")
    entries = a.get("files")
    if not isinstance(entries, list):
        raise ValueError("Distinct fighter file inventory missing")
    names = [entry.get("file") for entry in entries]
    if len(names) != len(set(names)) or not REQUIRED.issubset(names):
        raise ValueError("Missing or duplicated fighter resources")
    originals = b.get("assets")
    if (not isinstance(originals, list) or len(originals) != len(ORIGINAL_REQUIRED)
            or any(not isinstance(row, dict) for row in originals)
            or {row.get("file") for row in originals} != ORIGINAL_REQUIRED):
        raise ValueError("Original rig pair is missing or ambiguous")
    for row in originals:
        if not isinstance(row.get("bytes"), int) or row["bytes"] <= 0:
            raise ValueError("Invalid rig size")
        parts = row.get("parts")
        if not isinstance(parts, list) or not parts:
            raise ValueError("Missing encrypted rig parts")
        if sum(p.get("bytes", 0) for p in parts) <= row["bytes"]:
            # Ciphertext includes an authenticated envelope and may be larger than clear bytes.
            raise ValueError("Encrypted rig size unexpectedly small")
    counts = {
        "characters": len([n for n in names if n.endswith(".glb")]),
        "sounds": len([n for n in names if n.endswith(".wav")]),
        "textures": len([n for n in names if n.endswith(".png")]),
        "original_rigs": len(originals),
        "distinct_files": len(names),
        "distinct_encrypted_parts": len(a.get("parts", [])),
    }
    if counts["characters"] != 2 or counts["sounds"] == 0:
        raise ValueError("Expected two equipped characters and sound resources")
    return {"status": "manifest_only", "counts": counts,
            "warning": "No decryption, asset-content verification or license verification performed"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--distinct", type=Path, default=DISTINCT)
    parser.add_argument("--original", type=Path, default=ORIGINAL)
    args = parser.parse_args()
    print(json.dumps(inspect(args.distinct, args.original), indent=2))
