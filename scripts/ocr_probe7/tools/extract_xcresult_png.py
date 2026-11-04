#!/usr/bin/env python3
"""Extract Probe 7 PNG bytes from an existing xcresult; never decode/re-encode images.

The XCTest print log supplies the expected attachment names, SHA256, byte counts,
and prepared dimensions. Only exact logged PNG hashes are written. xcresult data
objects may be raw or Zstandard-compressed; other objects remain untouched.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import io
import json
import re
import struct
from pathlib import Path
import zlib

import zstandard


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ZSTD_SIGNATURE = b"\x28\xb5\x2f\xfd"
EXPECTED_ROWS = (1, 4, 7, 10, 13, 16, 19, 22)
EXPECTED_GEOMETRIES = ("headerCapped",)
EXPECTED_SCALES = (1, 3)
SAFE_NAME = re.compile(r"probe7-row-(1|4|7|10|13|16|19|22)-(headerCapped)-(1|3)x\.png\Z")


def parse_log(path: Path) -> tuple[dict[str, dict], dict[str, tuple[int, int]], int]:
    expected: dict[str, dict] = {}
    prepared: dict[str, tuple[int, int]] = {}
    base_sizes: dict[tuple[int, str], tuple[int, int]] = {}
    duplicates = 0
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "OCRPROBE7|" not in line:
            continue
        text = line.split("OCRPROBE7|", 1)[1]
        try:
            event = json.loads(text)
        except json.JSONDecodeError as error:
            raise ValueError(f"Incomplete probe JSON at log line {number}: {error}") from error
        if event.get("kind") != "prepared":
            continue
        row, geometry, scale = event.get("row"), event.get("geometry"), event.get("scale")
        if row not in EXPECTED_ROWS or geometry not in EXPECTED_GEOMETRIES or scale not in EXPECTED_SCALES:
            raise ValueError(f"Unexpected cell identity at log line {number}: {(row, geometry, scale)}")
        image_id = f"row-{row}-{geometry}-{scale}x"
        if event.get("imageID") != image_id:
            raise ValueError(f"Request ID does not match cell identity: {event.get('imageID')}")
        size, base = tuple(event["size"]), tuple(event["baseCropSize"])
        if len(size) != 2 or len(base) != 2 or not all(type(v) is int and v > 0 for v in size + base):
            raise ValueError(f"Invalid prepared/base dimensions: {image_id}")
        if size != tuple(value * scale for value in base):
            raise ValueError(f"Prepared dimensions do not match fixed scale: {image_id}")
        if (row, geometry) in base_sizes and base_sizes[(row, geometry)] != base:
            raise ValueError(f"Base crop differs between scales: {(row, geometry)}")
        base_sizes[(row, geometry)] = base
        if image_id in prepared:
            raise ValueError(f"Duplicate prepared image identity: {image_id}")
        prepared[image_id] = size
        name, digest = event["pngName"], event["pngSHA256"]
        if not SAFE_NAME.fullmatch(name) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"Invalid attachment name/hash at log line {number}")
        if name != f"probe7-{image_id}.png":
            raise ValueError(f"Attachment name does not match event identity: {name}")
        if type(event["pngBytes"]) is not int or event["pngBytes"] <= 0:
            raise ValueError(f"Invalid PNG byte count: {name}")
        record = {"name": name, "sha256": digest, "bytes": event["pngBytes"],
                  "imageID": image_id, "pngName": name, "size": list(size), "row": row, "geometry": geometry,
                  "scale": scale, "baseCropSize": list(base)}
        if name in expected:
            if expected[name] != record:
                raise ValueError(f"Conflicting duplicate attachment record: {name}")
            duplicates += 1
        expected[name] = record
    required = {f"probe7-row-{row}-{geometry}-{scale}x.png"
                for row in EXPECTED_ROWS for geometry in EXPECTED_GEOMETRIES for scale in EXPECTED_SCALES}
    if set(expected) != required:
        raise ValueError(f"Expected 16 attachment records; missing={sorted(required-set(expected))}, "
                         f"unexpected={sorted(set(expected)-required)}")
    return expected, prepared, duplicates


def png_at(blob: bytes, start: int) -> tuple[int, tuple[int, int], int] | None:
    """Return exact IEND end offset, IHDR size, chunk count after validating all CRCs."""
    if blob[start:start + 8] != PNG_SIGNATURE:
        return None
    offset = start + 8
    size = None
    count = 0
    saw_idat = False
    while offset + 12 <= len(blob):
        length = struct.unpack_from(">I", blob, offset)[0]
        kind = blob[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(blob) or not all(65 <= c <= 90 or 97 <= c <= 122 for c in kind):
            return None
        expected_crc = struct.unpack_from(">I", blob, end - 4)[0]
        actual_crc = zlib.crc32(memoryview(blob)[offset + 4:end - 4]) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            return None
        if count == 0:
            if kind != b"IHDR" or length != 13:
                return None
            size = struct.unpack_from(">II", blob, offset + 8)
            if min(size) < 1:
                return None
        elif kind == b"IHDR":
            return None
        if kind == b"IDAT":
            saw_idat = True
        count += 1
        if kind == b"IEND":
            if length != 0 or not saw_idat or size is None:
                return None
            return end, size, count
        offset = end
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xcresult", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-object-mib", type=int, default=256)
    args = parser.parse_args()
    expected, prepared, log_duplicates = parse_log(args.log)
    data_dir = args.xcresult / "Data"
    if not data_dir.is_dir():
        raise ValueError(f"xcresult Data directory not found: {data_dir}")
    args.output.mkdir(parents=True, exist_ok=True)
    by_hash = collections.defaultdict(list)
    for record in expected.values():
        by_hash[record["sha256"]].append(record)
    matches: dict[str, dict] = {}
    counters = collections.Counter()
    errors = []
    limit = args.max_object_mib * 1024 * 1024
    for path in sorted(data_dir.glob("data.*")):
        counters["objects"] += 1
        if path.is_symlink():
            errors.append({"object": path.name, "error": "symlink not inspected"})
            continue
        if path.stat().st_size > limit:
            errors.append({"object": path.name, "error": "compressed/raw object exceeds byte limit"})
            continue
        raw = path.read_bytes()
        compression = "raw"
        blob = raw
        if raw.startswith(ZSTD_SIGNATURE):
            compression = "zstd"
            try:
                with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(raw), read_across_frames=True) as reader:
                    blob = reader.read(limit + 1)
                if len(blob) > limit:
                    errors.append({"object": path.name, "error": "decoded object exceeds byte limit"})
                    continue
            except zstandard.ZstdError as error:
                errors.append({"object": path.name, "error": str(error)})
                continue
        counters[compression + "_objects"] += 1
        search = 0
        while True:
            start = blob.find(PNG_SIGNATURE, search)
            if start < 0:
                break
            search = start + len(PNG_SIGNATURE)
            found = png_at(blob, start)
            if found is None:
                counters["invalid_png_signatures"] += 1
                continue
            end, size, chunks = found
            counters["crc_valid_png_payloads"] += 1
            png = blob[start:end]
            digest = hashlib.sha256(png).hexdigest()
            for record in by_hash.get(digest, ()):
                name = record["name"]
                if len(png) != record["bytes"]:
                    raise ValueError(f"Logged byte count differs despite matching SHA256: {name}")
                if size != prepared[record["imageID"]]:
                    raise ValueError(f"PNG dimensions differ from prepared input: {name}")
                destination = args.output / name
                if destination.exists() and destination.read_bytes() != png:
                    raise ValueError(f"Refusing to overwrite different bytes: {destination}")
                if not destination.exists():
                    destination.write_bytes(png)
                provenance = {"object": path.name, "compression": compression,
                              "decoded_offset": start, "decoded_end": end,
                              "object_sha256": hashlib.sha256(raw).hexdigest()}
                if name in matches:
                    matches[name]["additional_sources"].append(provenance)
                else:
                    matches[name] = {**record, "width": size[0], "height": size[1],
                                     "crc_validated_chunks": chunks, "allCRCVerified": True, "sha256_verified": True,
                                     "reencoded": False, "output": str(destination.resolve()),
                                     "source": provenance, "additional_sources": []}
            search = end
    missing = sorted(set(expected) - set(matches))
    report = {"xcresult": str(args.xcresult.resolve()), "log": str(args.log.resolve()),
              "log_sha256": hashlib.sha256(args.log.read_bytes()).hexdigest(),
              "extractor_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "extraction": "raw or zstd-decoded xcresult object; exact PNG signature through IEND bytes",
              "expected_attachments": len(expected), "verified_attachments": len(matches),
              "missing": missing, "duplicate_log_attachment_records": log_duplicates,
              "counts": dict(counters), "object_errors": errors,
              "attachments": [matches[name] for name in sorted(matches)]}
    (args.output / "extraction-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"expected": len(expected), "verified": len(matches), "missing": missing,
                      "object_errors": len(errors), "report": str((args.output / "extraction-report.json").resolve())}))
    return 0 if not missing and not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
