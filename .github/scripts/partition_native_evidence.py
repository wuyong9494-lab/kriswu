#!/usr/bin/env python3
"""Partition existing encrypted evidence without reading a key or decrypting it.

The source archive digest is GitHub's metadata for the downloaded artifact ZIP.
The ciphertext and part digests below are computed locally. Reassembly verifies
transport integrity only; the existing authenticated unsealer must still verify
the complete envelope before anyone reads its plaintext.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import zipfile
import tempfile


REPOSITORY = "wuyong9494-lab/kriswu"
SOURCE_RUN = 42746304926
SOURCE_HEAD = "8d6fc923a105110e3e54925f201b82d8958794e3"
SOURCE_ATTEMPT = 1
SOURCE_ARTIFACT = 13733892592
ARTIFACT_NAME = "fighter-character-private"
CIPHERTEXT_NAME = "fighter-evidence.enc"
PART_BYTES = 400 * 1024 * 1024
MAX_PARTS = 8
MAX_ARCHIVE_BYTES = PART_BYTES * MAX_PARTS + 16 * 1024 * 1024
BUFFER_BYTES = 4 * 1024 * 1024
PREFIX = b"FIGHTER1\0evidence\0"
MIN_BYTES = len(PREFIX) + 48
VERIFICATION = "Byte-preserving transport only; no decryption or envelope MAC verification."
SOURCE_KEYS = {
    "repository", "runID", "runAttempt", "headSHA", "runStatus", "runConclusion",
    "runURL", "runStartedAt", "runUpdatedAt", "artifactID", "artifactName",
    "artifactDigest", "artifactBytes", "artifactCreatedAt",
}


def positive_integer(value, maximum):
    return type(value) is int and 0 < value <= maximum


def sha256_string(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def validate_source(source):
    if not isinstance(source, dict) or set(source) != SOURCE_KEYS:
        raise ValueError("Unexpected source metadata fields")
    expected = {
        "repository": REPOSITORY, "runID": SOURCE_RUN, "headSHA": SOURCE_HEAD,
        "runStatus": "completed", "artifactName": ARTIFACT_NAME,
        "runAttempt": SOURCE_ATTEMPT, "artifactID": SOURCE_ARTIFACT,
        "runURL": f"https://github.com/{REPOSITORY}/actions/runs/{SOURCE_RUN}",
    }
    if any(source[key] != value for key, value in expected.items()):
        raise ValueError("Source repository, run, head, status or artifact does not match")
    if not positive_integer(source["runAttempt"], 1000) or not positive_integer(source["artifactID"], 2**63 - 1):
        raise ValueError("Invalid source attempt or artifact ID")
    if not positive_integer(source["artifactBytes"], MAX_ARCHIVE_BYTES):
        raise ValueError("Source artifact is empty or exceeds the bounded recovery size")
    digest = source["artifactDigest"]
    if not isinstance(digest, str) or not digest.startswith("sha256:") or not sha256_string(digest[7:]):
        raise ValueError("Missing source artifact SHA-256 metadata")
    if source["runConclusion"] not in {
        "success", "failure", "neutral", "cancelled", "timed_out", "action_required",
        "stale", "skipped", "startup_failure",
    }:
        raise ValueError("A completed source run must have an explicit conclusion")
    try:
        started, created, updated = (
            datetime.fromisoformat(source[key].replace("Z", "+00:00"))
            for key in ("runStartedAt", "artifactCreatedAt", "runUpdatedAt")
        )
        if any(value.tzinfo is None for value in (started, created, updated)) or not started <= created <= updated:
            raise ValueError("Artifact timestamp is outside the completed source attempt")
    except (AttributeError, TypeError, ValueError) as error:
        raise ValueError("Invalid source attempt timestamps") from error
    return dict(source)


def safe_path(value, *, file=False, directory=False):
    path = Path(value)
    if ".." in path.parts:
        raise ValueError("Parent traversal is not allowed")
    path = path.absolute()
    if any(candidate.is_symlink() for candidate in (path, *path.parents)):
        raise ValueError("Symlink paths are not allowed")
    if file and not path.is_file():
        raise ValueError("Expected a regular file")
    if directory and not path.is_dir():
        raise ValueError("Expected a directory")
    return path


def read_json(path):
    path = safe_path(path, file=True)
    if path.stat().st_size > 32 * 1024:
        raise ValueError("Metadata exceeds the fixed recovery limit")
    return json.loads(path.read_text(encoding="utf-8"))


def check_header(header, size):
    if size < MIN_BYTES or not header.startswith(PREFIX + b"Salted__"):
        raise ValueError("Empty, truncated or wrong-purpose encrypted evidence envelope")


def part_name(index):
    return f"{CIPHERTEXT_NAME}.part-{index:03d}"


def load_manifest(directory):
    directory = safe_path(directory, directory=True)
    manifest = read_json(directory / "manifest.json")
    keys = {"schemaVersion", "source", "ciphertext", "partBytes", "maximumParts", "partCount", "parts", "verification"}
    if (not isinstance(manifest, dict) or set(manifest) != keys
            or type(manifest["schemaVersion"]) is not int or manifest["schemaVersion"] != 1):
        raise ValueError("Unsupported recovery manifest")
    validate_source(manifest["source"])
    cipher = manifest["ciphertext"]
    if not isinstance(cipher, dict) or set(cipher) != {"file", "bytes", "sha256"}:
        raise ValueError("Invalid ciphertext metadata")
    if cipher["file"] != CIPHERTEXT_NAME or not positive_integer(cipher["bytes"], PART_BYTES * MAX_PARTS) or cipher["bytes"] < MIN_BYTES or not sha256_string(cipher["sha256"]):
        raise ValueError("Invalid ciphertext size, name or digest")
    limit, count = manifest["partBytes"], manifest["partCount"]
    if not positive_integer(limit, PART_BYTES) or not positive_integer(count, MAX_PARTS) or manifest["maximumParts"] != MAX_PARTS:
        raise ValueError("Invalid partition bounds")
    if count != (cipher["bytes"] + limit - 1) // limit or manifest["verification"] != VERIFICATION:
        raise ValueError("Incomplete partition manifest")
    parts = manifest["parts"]
    if not isinstance(parts, list) or len(parts) != count:
        raise ValueError("Missing partition records")
    for index, part in enumerate(parts, 1):
        offset = (index - 1) * limit
        if not isinstance(part, dict) or set(part) != {"index", "name", "offset", "bytes", "sha256"}:
            raise ValueError("Invalid partition record")
        if (any(type(part[key]) is not int for key in ("index", "offset", "bytes"))
                or part["index"] != index or part["name"] != part_name(index) or part["offset"] != offset
                or part["bytes"] != min(limit, cipher["bytes"] - offset) or not sha256_string(part["sha256"])):
            raise ValueError("Partition order, path, size or digest is invalid")
    expected = {"manifest.json", *(part["name"] for part in parts)}
    if {path.name for path in directory.iterdir()} != expected:
        raise ValueError("Recovery directory must contain every listed part and no extra files")
    return directory, manifest


def read_verified_parts(directory, manifest, destination=None):
    full_hash, total, header = hashlib.sha256(), 0, bytearray()
    for part in manifest["parts"]:
        path = safe_path(directory / part["name"], file=True)
        if path.stat().st_size != part["bytes"]:
            raise ValueError("Partition byte count mismatch")
        part_hash, size = hashlib.sha256(), 0
        with path.open("rb") as source:
            while block := source.read(BUFFER_BYTES):
                size += len(block)
                total += len(block)
                part_hash.update(block)
                full_hash.update(block)
                header.extend(block[:max(0, len(PREFIX) + 8 - len(header))])
                if destination is not None:
                    destination.write(block)
        if size != part["bytes"] or part_hash.hexdigest() != part["sha256"]:
            raise ValueError("Partition SHA-256 mismatch")
    if total != manifest["ciphertext"]["bytes"] or full_hash.hexdigest() != manifest["ciphertext"]["sha256"]:
        raise ValueError("Reassembled ciphertext SHA-256 mismatch")
    check_header(header, total)


def verify(directory):
    directory, manifest = load_manifest(directory)
    read_verified_parts(directory, manifest)
    return manifest


def partition(source, output, metadata, *, part_bytes=PART_BYTES):
    metadata = validate_source(metadata)
    source = safe_path(source, file=True)
    output = safe_path(output)
    if source.name != CIPHERTEXT_NAME or output.exists() or not output.parent.is_dir():
        raise ValueError("Expected the fixed ciphertext name and a new output directory")
    if not positive_integer(part_bytes, PART_BYTES):
        raise ValueError("Partition size exceeds the 400 MiB limit")
    with source.open("rb") as original:
        size = os.fstat(original.fileno()).st_size
        check_header(original.read(len(PREFIX) + 8), size)
        count = (size + part_bytes - 1) // part_bytes
        if count > MAX_PARTS:
            raise ValueError("Evidence exceeds the maximum of eight partitions")
        original.seek(0)
        staging = Path(tempfile.mkdtemp(prefix="native-evidence-", dir=output.parent))
        try:
            parts, full_hash, offset = [], hashlib.sha256(), 0
            for index in range(1, count + 1):
                length, part_hash = min(part_bytes, size - offset), hashlib.sha256()
                remaining = length
                with (staging / part_name(index)).open("xb") as target:
                    while remaining:
                        block = original.read(min(BUFFER_BYTES, remaining))
                        if not block:
                            raise ValueError("Ciphertext changed during partitioning")
                        target.write(block)
                        full_hash.update(block)
                        part_hash.update(block)
                        remaining -= len(block)
                parts.append({"index": index, "name": part_name(index), "offset": offset,
                              "bytes": length, "sha256": part_hash.hexdigest()})
                offset += length
            if original.read(1) or os.fstat(original.fileno()).st_size != size:
                raise ValueError("Ciphertext changed during partitioning")
            manifest = {
                "schemaVersion": 1, "source": metadata,
                "ciphertext": {"file": CIPHERTEXT_NAME, "bytes": size, "sha256": full_hash.hexdigest()},
                "partBytes": part_bytes, "maximumParts": MAX_PARTS, "partCount": count,
                "parts": parts, "verification": VERIFICATION,
            }
            (staging / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            verify(staging)
            if output.exists():
                raise ValueError("Output appeared during partitioning")
            staging.rename(output)
            return manifest
        finally:
            if staging.exists():
                shutil.rmtree(staging)


def extract_archive(archive, output, metadata):
    """Verify the exact ZIP digest before extracting only its fixed ciphertext member."""
    metadata = validate_source(metadata)
    archive, output = safe_path(archive, file=True), safe_path(output)
    if output.name != CIPHERTEXT_NAME or output.exists() or not output.parent.is_dir():
        raise ValueError("Extraction requires a new fixed-name ciphertext file")
    if archive.stat().st_size != metadata["artifactBytes"]:
        raise ValueError("Source artifact byte count mismatch")
    descriptor, temporary = tempfile.mkstemp(prefix="native-evidence-", dir=output.parent)
    try:
        # Keep the same open descriptor for hashing and ZIP reads.
        with archive.open("rb") as original, os.fdopen(descriptor, "wb") as target:
            digest = hashlib.file_digest(original, "sha256").hexdigest()
            if "sha256:" + digest != metadata["artifactDigest"]:
                raise ValueError("Source artifact SHA-256 mismatch")
            original.seek(0)
            with zipfile.ZipFile(original) as container:
                matches = [info for info in container.infolist() if info.filename == CIPHERTEXT_NAME]
                if len(matches) != 1:
                    raise ValueError("Source archive must contain exactly one fixed ciphertext member")
                member = matches[0]
                kind = stat.S_IFMT(member.external_attr >> 16)
                if (kind not in (0, stat.S_IFREG) or member.flag_bits & 1
                        or not MIN_BYTES <= member.file_size <= PART_BYTES * MAX_PARTS):
                    raise ValueError("Invalid ciphertext member type, flags or size")
                with container.open(member) as source:
                    header = source.read(len(PREFIX) + 8)
                    check_header(header, member.file_size)
                    target.write(header)
                    written = len(header)
                    while block := source.read(BUFFER_BYTES):
                        written += len(block)
                        if written > member.file_size:
                            raise ValueError("Ciphertext exceeds its declared size")
                        target.write(block)
                    if written != member.file_size:
                        raise ValueError("Ciphertext byte count mismatch")
        os.link(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return metadata


def reassemble(directory, output):
    directory, manifest = load_manifest(directory)
    output = safe_path(output)
    if output.exists() or not output.parent.is_dir():
        raise ValueError("Reassembly requires a new output file")
    descriptor, temporary = tempfile.mkstemp(prefix="native-evidence-", dir=output.parent)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            read_verified_parts(directory, manifest, destination)
        # A hard link publishes the verified file atomically without overwriting
        # an existing destination. The temporary file is on the same filesystem.
        os.link(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("partition", "extract"):
        split = commands.add_parser(name)
        split.add_argument("--input", required=True)
        split.add_argument("--source-metadata", required=True)
        split.add_argument("--output", required=True)
    for name in ("verify", "reassemble"):
        command = commands.add_parser(name)
        command.add_argument("--directory", required=True)
        if name == "reassemble":
            command.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.command == "extract":
        metadata = extract_archive(args.input, args.output, read_json(args.source_metadata))
        print(json.dumps({"sourceConclusion": metadata["runConclusion"], "archiveDigestVerified": True}))
        return
    if args.command == "partition":
        manifest = partition(args.input, args.output, read_json(args.source_metadata))
    elif args.command == "verify":
        manifest = verify(args.directory)
    else:
        manifest = reassemble(args.directory, args.output)
    print(json.dumps({"partCount": manifest["partCount"], "ciphertext": manifest["ciphertext"],
                      "sourceConclusion": manifest["source"]["runConclusion"], "verification": VERIFICATION}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Evidence recovery rejected: {error}") from error
