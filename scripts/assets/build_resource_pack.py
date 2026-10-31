#!/usr/bin/env python3
"""Write/verify the App's streaming, data-only .arenapack container.

Input manifest uses ArenaResourcePackManifest's schema. Asset files stay outside
the public source tree. No network, executable code or archive-path extraction.
"""
import argparse
import hashlib
import json
import math
import os
import struct
import unicodedata
from pathlib import Path, PurePosixPath

MAGIC = b"KRISARENA1\n"
MAX_HEADER = 8 * 1024 * 1024
MAX_PAYLOAD = 1024 * 1024 * 1024
KINDS = {"model": {".glb"}, "image": {".png", ".jpg", ".jpeg"},
         "music": {".m4a", ".wav"}, "data": {".json"}, "notice": {".txt"}}


def safe_path(name):
    return (isinstance(name, str) and 0 < len(name.encode()) <= 240
            and not name.startswith("/") and not any(c in name for c in "\\:%")
            and all(ord(c) >= 32 and ord(c) != 127 for c in name)
            and all(p and not p.startswith(".") for p in name.split("/"))
            and unicodedata.normalize("NFC", name).lower().split("/")[0] != "manifest.json")


def sha_file(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def validate_files(manifest):
    assert manifest["schemaVersion"] == 1
    files = manifest["files"]
    assert 0 < len(files) <= 10000
    assert sum(f["bytes"] for f in files) <= MAX_PAYLOAD
    seen = set()
    for item in files:
        name = item["path"]
        assert safe_path(name), name
        key = unicodedata.normalize("NFC", name).lower()
        assert key not in seen, name
        seen.add(key)
        assert 0 < item["bytes"] <= 128 * 1024 * 1024
        assert len(item["sha256"]) == 64 and set(item["sha256"]) <= set("0123456789abcdef")
        assert PurePosixPath(name).suffix.lower() in KINDS[item["kind"]]
    for name in seen:
        pieces = name.split("/")
        assert all("/".join(pieces[:i]) not in seen for i in range(1, len(pieces))), name
    table = {f["path"]: f["kind"] for f in files}
    for hero in manifest["heroes"]:
        if hero.get("modelFile"):
            assert table.get(hero["modelFile"]) == "model"
        for field in ["animationFile", "faceFile"]:
            if hero.get(field):
                assert table.get(hero[field]) == "data"
        if hero.get("modelBounds") is not None:
            bounds = hero["modelBounds"]
            assert len(bounds) == 6 and all(isinstance(v, (int, float)) and math.isfinite(v) and abs(v) < 100000 for v in bounds)
            assert all(bounds[i + 3] >= bounds[i] for i in range(3))
    for field in ["gameAudioFile", "menuArtworkFile", "combatFile", "playableMapsFile", "mapArtworkFile", "skillArtworkFile"]:
        if manifest.get(field):
            assert table.get(manifest[field]) == "data"
    for theme in manifest["themes"]:
        assert table.get(theme["backgroundFile"]) == "image"
    for track in manifest["music"]:
        assert table.get(track["file"]) == "music"
    for map_ in manifest["maps"]:
        assert table.get(map_["layoutFile"]) == "data"
    for group in ["heroes", "themes", "music", "maps"]:
        ids = [entry["id"] for entry in manifest[group]]
        assert len(ids) == len(set(ids)), group
    track_ids = {t["id"] for t in manifest["music"]}
    assert all(k in {"lobby", "battle", "win", "lose"} and v in track_ids
               for k, v in manifest["musicBindings"].items())


def verify(path):
    with path.open("rb") as source:
        assert source.read(len(MAGIC)) == MAGIC
        length = struct.unpack("<I", source.read(4))[0]
        assert 0 < length <= MAX_HEADER
        manifest = json.loads(source.read(length))
        validate_files(manifest)
        for item in manifest["files"]:
            digest = hashlib.sha256()
            remaining = item["bytes"]
            while remaining:
                data = source.read(min(remaining, 1 << 20))
                assert data, item["path"]
                digest.update(data)
                remaining -= len(data)
            assert digest.hexdigest() == item["sha256"], item["path"]
        assert source.read(1) == b"", "Unexpected trailing bytes"
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha_file(path),
            "files": len(manifest["files"]), "heroes": len(manifest["heroes"]),
            "maps": len(manifest["maps"]), "music": len(manifest["music"]),
            "themes": len(manifest["themes"]), "all_payload_hashes_verified": True}


def build(manifest_path, root, output):
    manifest = json.loads(manifest_path.read_text())
    validate_files(manifest)
    raw = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    assert len(raw) <= MAX_HEADER
    root = root.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".partial")
    try:
        with temporary.open("wb") as destination:
            destination.write(MAGIC)
            destination.write(struct.pack("<I", len(raw)))
            destination.write(raw)
            for item in manifest["files"]:
                path = root / item["path"]
                assert path.is_file() and not path.is_symlink()
                assert root in path.resolve().parents
                assert path.stat().st_size == item["bytes"]
                digest = hashlib.sha256()
                with path.open("rb") as source:
                    while data := source.read(1 << 20):
                        digest.update(data)
                        destination.write(data)
                assert digest.hexdigest() == item["sha256"], item["path"]
            destination.flush()
            os.fsync(destination.fileno())
        result = verify(temporary)
        temporary.replace(output)
        result["path"] = str(output)
        return result
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify", type=Path)
    args = parser.parse_args()
    if args.verify:
        result = verify(args.verify)
    else:
        assert args.manifest and args.root and args.output
        result = build(args.manifest, args.root, args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
