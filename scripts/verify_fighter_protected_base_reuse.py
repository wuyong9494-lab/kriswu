#!/usr/bin/env python3
"""Report reusable files from the exact old 302-file recovery directory.

Invoke after authorized reconstruction, inside the same protected build job.
No keys, decryptions, uploads, source edits, or copies are performed here.
The emitted report is metadata only and does not prove native acceptance.
"""
import argparse
import ast
import json
from pathlib import Path

from audit_fighter_resource_reuse import audit
from completion_native_preflight import (
    CheckError, INVENTORY_BYTES, INVENTORY_PATH, INVENTORY_SHA256,
    flat_resources, json_file, snapshot,
)

HISTORICAL_HELPER = ".github/scripts/fighter_base_recovery.py"
HISTORICAL_HELPER_SHA = "f1b7625ddca710f26a379bbddb4b67d4ef649b1eded2fce85349c7a6fe0ad8d6"


def historical_inventory(root):
    raw = snapshot(root / HISTORICAL_HELPER, maximum=128_000, keep=True,
                   sha256=HISTORICAL_HELPER_SHA)["data"]
    tree = ast.parse(raw)
    tables = [node.value for node in tree.body if isinstance(node, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == "PAYLOADS" for t in node.targets)]
    if len(tables) != 1 or not isinstance(tables[0], ast.Dict):
        raise ValueError("Historical inventory declaration is missing or ambiguous")
    rows = ast.literal_eval(tables[0])
    if len(rows) != len(tables[0].keys) or len(rows) != 302:
        raise ValueError("Historical inventory must contain exactly 302 unique files")
    return [{"name": n, "bytes": size, "sha256": digest}
            for n, (size, digest) in sorted(rows.items())]


def trusted_aliases(historical, current):
    # Exact byte-equivalent names only, not filename similarity.
    by_identity = {}
    for row in historical:
        by_identity.setdefault((row["bytes"], row["sha256"]), []).append(row["name"])
    out = {}
    for row in current:
        values = [n for n in by_identity.get((row["bytes"], row["sha256"]), []) if n != row["name"]]
        if values:
            out[row["name"]] = sorted(values)
    return out


def run(repo, older_resources):
    original = historical_inventory(repo)
    inventory = json_file(repo / INVENTORY_PATH, size=INVENTORY_BYTES,
                          sha256=INVENTORY_SHA256)["compiledFiles"]
    # Rehash every old byte first, including files deliberately not reusable.
    flat_resources(older_resources, original)
    result = audit(inventory, [older_resources], trusted_aliases(original, inventory))
    return {"historicalFilesActuallyRehashed": len(original),
            "eligibleTargetFilesActuallyRehashed": result["verifiedCount"],
            "matchedNames": sorted(result["verified"]),
            "sameNameUnusable": sorted({r["name"] for r in result["rejected"] if r["member"] == r["name"]}),
            "targetFullyAvailable": result["complete"],
            "signed": False, "published": False}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("older_resources", type=Path)
    p.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = p.parse_args()
    try:
        print(json.dumps(run(args.repo, args.older_resources), indent=2))
    except (CheckError, OSError, ValueError, KeyError) as e:
        print(json.dumps({"verified": False, "error": str(e), "published": False}))
        raise SystemExit(2) from None
