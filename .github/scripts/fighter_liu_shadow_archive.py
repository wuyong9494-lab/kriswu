#!/usr/bin/env python3
"""Audit a user-supplied FBX ZIP for Liu's shadow transformation.

No assets are committed by this tool. The output is a local manifest only.
FBX conversion, rigging, attack animations and collision remain separate steps.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

MAX_ARCHIVE = 64 * 1024 * 1024
MAX_MEMBER = 32 * 1024 * 1024
EXPECTED = {".fbx": 1, ".jpeg": 2}


def audit(path: Path) -> dict:
    if not zipfile.is_zipfile(path):
        raise ValueError("Expected a ZIP-wrapped FBX resource")
    if path.stat().st_size > MAX_ARCHIVE:
        raise ValueError("Archive exceeds limit")
    files = []
    suffix_counts = {}
    with zipfile.ZipFile(path) as archive:
        entries = [info for info in archive.infolist() if not info.is_dir()]
        if len(entries) != 3:
            raise ValueError("Expected one FBX and two JPEG textures")
        for info in entries:
            parts = Path(info.filename)
            if parts.is_absolute() or ".." in parts.parts or "\\" in info.filename:
                raise ValueError("Unsafe archive path")
            suffix = parts.suffix.lower()
            if suffix not in EXPECTED or info.file_size > MAX_MEMBER:
                raise ValueError("Unexpected asset or oversized member")
            suffix_counts[suffix] = suffix_counts.get(suffix, 0) + 1
            data = archive.read(info)
            if len(data) != info.file_size:
                raise ValueError("Truncated member")
            if suffix == ".fbx" and not (data.startswith(b"Kaydara FBX Binary  ") or data.lstrip().startswith(b"; FBX")):
                raise ValueError("Invalid FBX header")
            if suffix == ".jpeg" and not data.startswith(bytes.fromhex("ffd8ff")):
                raise ValueError("Invalid JPEG header")
            files.append({"path": info.filename, "bytes": len(data),
                          "sha256": hashlib.sha256(data).hexdigest()})
    if suffix_counts != EXPECTED:
        raise ValueError("Missing model or textures")
    return {"role": "liu_shadow_transformation_candidate",
            "archive_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "members": files, "rig_verified": False, "animation_verified": False,
            "runtime_ready": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    result = audit(args.archive)
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)


if __name__ == "__main__":
    main()
