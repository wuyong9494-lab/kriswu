#!/usr/bin/env python3
"""Compare authorized, already-decrypted flat resource directories to the pinned candidate.

Does not decrypt, copy, publish, or promote resources. Exit 2 for a partial
inventory; a successful exact-byte audit is not iOS runtime evidence.
"""
import argparse
import json
from pathlib import Path

from completion_native_preflight import (
    CheckError, INVENTORY_BYTES, INVENTORY_PATH, INVENTORY_SHA256,
    MAX_RESOURCE_BYTES, NAME_RE, checked_rows, json_file, nonsymlink, snapshot,
)


def audit(rows, sources, aliases=None):
    checked_rows(rows)
    known = {row["name"] for row in rows}
    aliases = aliases or {}
    if not isinstance(aliases, dict) or set(aliases) - known:
        raise ValueError("Alias target is not in the pinned inventory")
    for target, names in aliases.items():
        if (not isinstance(names, list) or not 0 < len(names) <= 8
                or any(not isinstance(n, str) or not NAME_RE.fullmatch(n) or ".." in n
                       for n in names)
                or target in names or len(set(names)) != len(names)):
            raise ValueError("Alias must be an explicit, distinct flat source filename")
    verified, rejected = {}, []
    for index, directory in enumerate(sources, 1):
        root = nonsymlink(directory.absolute())
        if not root.is_dir():
            raise ValueError("Resource source is not a directory")
        for row in rows:
            name = row["name"]
            for member in [name, *aliases.get(name, [])]:
                path = root / member
                try:
                    path.lstat()
                except FileNotFoundError:
                    continue
                try:
                    snapshot(path, maximum=MAX_RESOURCE_BYTES,
                             size=row["bytes"], sha256=row["sha256"])
                except CheckError as error:
                    rejected.append({"name": name, "member": member, "source": index,
                                     "reason": error.code})
                    continue
                if name not in verified:
                    verified[name] = {"firstVerifiedSource": index, "firstVerifiedMember": member,
                                      "sourceMatches": [index]}
                else:
                    verified[name]["sourceMatches"].append(index)
                break
    missing = sorted(row["name"] for row in rows if row["name"] not in verified)
    return {"expected": len(rows), "verifiedCount": len(verified),
            "verified": verified, "missingCount": len(missing), "missing": missing,
            "rejected": rejected, "complete": not missing, "installed": False,
            "runtimeVerified": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path,
                        help="Authorized clear directories, in preferred source order")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--aliases", type=Path,
                        help="Optional reviewed JSON mapping candidate names to old flat names")
    args = parser.parse_args()
    try:
        inventory = json_file(args.repo / INVENTORY_PATH, size=INVENTORY_BYTES, sha256=INVENTORY_SHA256)
        aliases = json_file(args.aliases) if args.aliases else None
        report = audit(inventory["compiledFiles"], args.roots, aliases)
    except (CheckError, OSError, ValueError, KeyError) as e:
        print(json.dumps({"complete": False, "error": str(e), "installed": False}))
        raise SystemExit(1) from None
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["complete"] else 2)
