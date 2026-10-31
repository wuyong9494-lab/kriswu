#!/usr/bin/env python3
"""Bind a private data pack to one signed TestFlight archive.

The download location is supplied only through an Actions secret. This script
never prints the URL or exports the payload as a workflow artifact.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import urllib.parse
import urllib.request
import zlib

import asc_promote as promotion

PACK_NAME = "arena-original-resources.arenapack"
MAX_BYTES = 1024 * 1024 * 1024 + 8 * 1024 * 1024 + 15
MAX_TRANSPORT_BYTES = MAX_BYTES + 8 * 1024 * 1024
TRANSFER_CHUNK = 1024 * 1024
DEFERRED_MODE = "resource-runtime-gameplay-deferred"
DEFERRED_NOTE = "完整对局与录像验收已延期，本版未完成该项验证。"
SOURCE_BRANCH = "codex/arena-quality-sample"
ARCHIVE_REPORT = "promotion-private-resources.json"
OPAQUE_TEXTURE_SOURCES = (
    "App/Arena3D/hexagons_medieval.png",
    "App/Arena3D/skeleton_texture.png",
    "App/ArenaVendor/vendor_axe_texture.png",
    "App/ArenaVendor/vendor_knight_texture.png",
    "App/ArenaVendor/vendor_mage_texture.png",
    "App/ArenaVendor/vendor_rogue_texture.png",
)


def specification(request):
    value = request.get("private_resource_pack")
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {"id", "bytes", "sha256"}:
        raise ValueError("Private resource pack requires id, bytes and sha256 only")
    if not isinstance(value["id"], str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", value["id"]) or value["id"] in {".", ".."}:
        raise ValueError("Invalid private resource pack identity")
    if type(value["bytes"]) is not int or not 15 < value["bytes"] <= MAX_BYTES:
        raise ValueError("Invalid private resource pack size")
    if not isinstance(value["sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", value["sha256"]):
        raise ValueError("Invalid private resource pack digest")
    return value


def transport_specification(request):
    value = request.get("private_resource_pack_transport")
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {"encoding", "bytes", "sha256"}:
        raise ValueError("Private transport requires encoding, bytes and sha256 only")
    if value["encoding"] not in ("raw", "gzip"):
        raise ValueError("Unsupported private resource transport encoding")
    if type(value["bytes"]) is not int or not 0 < value["bytes"] <= MAX_TRANSPORT_BYTES:
        raise ValueError("Invalid private resource transport size")
    if not isinstance(value["sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", value["sha256"]):
        raise ValueError("Invalid private resource transport digest")
    if specification(request) is None:
        raise ValueError("Private transport requires resource pack metadata")
    return value


def validation_specification(request):
    value = request.get("source_validation")
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {"mode", "resource_run_id"}:
        raise ValueError("Source validation requires mode and resource_run_id only")
    if value["mode"] != DEFERRED_MODE:
        raise ValueError("Unsupported source validation mode")
    for run_id in (request.get("source_run_id"), value["resource_run_id"]):
        if type(run_id) is not int or run_id <= 0:
            raise ValueError("Source and resource CI run IDs must be positive integers")
    if specification(request) is None:
        raise ValueError("Deferred resource validation requires private resource pack metadata")
    if DEFERRED_NOTE not in request.get("notes", ""):
        raise ValueError("Deferred release notes must include: " + DEFERRED_NOTE)
    return value


def validate_deferred_source(request, run, jobs, resource_run, resource_jobs):
    validation = validation_specification(request)
    if validation is None:
        raise ValueError("Deferred source validation must be explicitly requested")
    for actual, workflow, run_id in (
            (run, ".github/workflows/ios.yml", request["source_run_id"]),
            (resource_run, ".github/workflows/arena-resource-validation.yml", validation["resource_run_id"])):
        if actual.get("id") != run_id or actual.get("path") != workflow:
            raise ValueError("Unexpected source or resource workflow run")
        if actual.get("head_sha") != request["source_sha"]:
            raise ValueError("Source and resource CI must verify the exact same commit")
        if actual.get("event") != "push" or actual.get("head_branch") != SOURCE_BRANCH:
            raise ValueError("Deferred release requires a source-branch push, not a manual upload")
        if actual.get("status") != "completed" or actual.get("conclusion") != "success":
            raise ValueError("Source and resource CI must both complete successfully")
    if str(run.get("run_number")) != request["build_number"]:
        raise ValueError("Source CI build number mismatch")
    if "[defer-arena-validation]" not in run.get("head_commit", {}).get("message", ""):
        raise ValueError("Source commit did not explicitly defer gameplay validation")
    for collection, name, conclusion in (
            (jobs, "build", "success"), (jobs, "core-tests-linux", "success"),
            (jobs, "arena-look", "skipped"), (resource_jobs, "resource-runtime", "success")):
        matched = [job for job in collection if job.get("name") == name]
        if (len(matched) != 1 or matched[0].get("status") != "completed"
                or matched[0].get("conclusion") != conclusion):
            raise ValueError("Required CI result not satisfied: " + name)


def check_deferred_source(request):
    validation = validation_specification(request)
    if validation is None:
        raise ValueError("Deferred source validation must be explicitly requested")
    head = promotion.github("/git/ref/heads/" + SOURCE_BRANCH)
    if head.get("object", {}).get("sha") != request["source_sha"]:
        raise ValueError("Source was superseded; refusing a stale release")
    run_id, resource_id = request["source_run_id"], validation["resource_run_id"]
    run = promotion.github(f"/actions/runs/{run_id}")
    jobs = promotion.github(f"/actions/runs/{run_id}/jobs?filter=latest&per_page=100")["jobs"]
    resource_run = promotion.github(f"/actions/runs/{resource_id}")
    resource_jobs = promotion.github(f"/actions/runs/{resource_id}/jobs?filter=latest&per_page=100")["jobs"]
    validate_deferred_source(request, run, jobs, resource_run, resource_jobs)
    return {"validation_mode": validation["mode"], "resource_run_id": resource_id,
            "source_ci_conclusion": run["conclusion"], "resource_ci_conclusion": resource_run["conclusion"],
            "arena_look_conclusion": "skipped", "gameplay_validation": "deferred",
            "current_source_head_verified": True}


def preflight(request):
    validation = validation_specification(request)
    transport = transport_specification(request)
    if validation is None:
        # Preserve the existing strict acceptance path. Never fall back after it fails.
        promotion.preflight(request)
        return
    acceptance = check_deferred_source(request)
    build = promotion.find_build(request)
    promotion.output("upload_required", "false" if build else "true")
    promotion.output("source_sha", request["source_sha"])
    promotion.output("build_number", request["build_number"])
    promotion.save_report("promotion-preflight.json", request, upload_required=build is None,
                          existing_build_id=build["id"] if build else None,
                          processing_state=build["attributes"].get("processingState") if build else None,
                          **acceptance,
                          private_resource_pack=specification(request), private_resource_pack_transport=transport)


def required_specification(request, source):
    expected = specification(request)
    info = plistlib.loads((source / "App/Info.plist").read_bytes())
    if info.get("ArenaResourcePackRequiredForPromotion") is True and expected is None:
        raise ValueError("This source version requires private_resource_pack in its release request")
    return expected


def verify(path, expected, source):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != expected["bytes"]:
        raise ValueError("Private resource pack missing or size mismatch")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != expected["sha256"]:
        raise ValueError("Private resource pack digest mismatch")
    script = source / "scripts/assets/build_resource_pack.py"
    spec = importlib.util.spec_from_file_location("verified_pack", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    report = module.verify(path)
    with path.open("rb") as stream:
        stream.read(len(module.MAGIC))
        length = struct.unpack("<I", stream.read(4))[0]
        header = json.loads(stream.read(length))
    if header["id"] != expected["id"]:
        raise ValueError("Private resource pack identity mismatch")
    return {key: report[key] for key in ("bytes", "sha256", "files", "heroes", "maps", "music", "themes", "all_payload_hashes_verified")}


class HTTPSOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise ValueError("Private resource download requires HTTPS")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_payload(response, destination, expected, transport=None):
    # HTTP reads may return fewer bytes than requested, even for the two magic bytes.
    prefix = b""
    while len(prefix) < 2:
        part = response.read(2 - len(prefix))
        if not part:
            break
        prefix += part
    encoding = "gzip" if prefix == b"\x1f\x8b" else "raw"
    if transport and transport["encoding"] != encoding:
        raise ValueError("Private resource transport encoding mismatch")
    transfer_size = transport["bytes"] if transport else expected["bytes"] if encoding == "raw" else None
    transfer_limit = transfer_size if transfer_size is not None else MAX_TRANSPORT_BYTES
    header = response.headers.get("Content-Length")
    content_length = int(header) if header is not None else None
    if content_length is not None and (not 0 <= content_length <= transfer_limit
                                      or transfer_size is not None and content_length != transfer_size):
        raise ValueError("Private resource download length mismatch")
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS) if encoding == "gzip" else None
    digest = hashlib.sha256()
    received = written = 0
    block = prefix
    while block:
        received += len(block)
        if received > transfer_limit:
            raise ValueError("Private resource download exceeded expected size")
        digest.update(block)
        if decoder is None:
            if written + len(block) > expected["bytes"]:
                raise ValueError("Private resource payload exceeded expected size")
            destination.write(block)
            written += len(block)
        else:
            if decoder.eof:
                raise ValueError("Trailing bytes or multiple members in private gzip transport")
            pending = block
            while pending:
                # remaining + 1 detects a bomb without ever writing beyond the bound.
                decoded = decoder.decompress(pending, min(TRANSFER_CHUNK, expected["bytes"] - written + 1))
                if written + len(decoded) > expected["bytes"]:
                    raise ValueError("Private resource payload exceeded expected size")
                destination.write(decoded)
                written += len(decoded)
                if decoder.unused_data:
                    raise ValueError("Trailing bytes or multiple members in private gzip transport")
                pending = decoder.unconsumed_tail
        block = response.read(TRANSFER_CHUNK)
    if decoder is not None and not decoder.eof:
        raise ValueError("Truncated private gzip transport")
    if written != expected["bytes"] or transfer_size is not None and received != transfer_size:
        raise ValueError("Private resource download or payload size mismatch")
    if content_length is not None and received != content_length:
        raise ValueError("Private resource response ended before its declared length")
    if transport and digest.hexdigest() != transport["sha256"]:
        raise ValueError("Private resource transport digest mismatch")
    return {"transport_encoding": encoding, "transport_bytes": received, "transport_sha256": digest.hexdigest()}


def install(expected, source, transport=None):
    output = source / "App/Resources" / PACK_NAME
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".partial")
    try:
        # URL parsing, redirects and reads all stay behind the sanitized error boundary.
        url = os.environ.get("ARENA_PRIVATE_PACK_URL", "")
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
            raise ValueError("Configure the private resource pack download secret")
        opener = urllib.request.build_opener(HTTPSOnly())
        with opener.open(urllib.request.Request(url, headers={"Accept": "application/octet-stream",
                                                              "Accept-Encoding": "identity"}), timeout=60) as response:
            final_url = urllib.parse.urlsplit(response.geturl())
            if final_url.scheme != "https" or not final_url.hostname or final_url.username or final_url.password:
                raise ValueError("Private resource download requires HTTPS")
            with temporary.open("wb") as destination:
                transfer_report = download_payload(response, destination, expected, transport)
                destination.flush()
                os.fsync(destination.fileno())
        report = verify(temporary, expected, source)
        temporary.replace(output)
        return {**report, **transfer_report}
    except Exception:
        raise RuntimeError("Private resource preparation failed; check secret access, expected size and digest") from None
    finally:
        temporary.unlink(missing_ok=True)


def png_dimensions(data):
    """Validate PNG structure, accepting Xcode's lossless CgBI representation."""
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Invalid PNG signature")
    offset, dimensions, pixels = 8, None, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated PNG chunk")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("Truncated PNG payload")
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        checksum = struct.unpack(">I", data[offset + 8 + length:end])[0]
        if zlib.crc32(kind + payload) & 0xffffffff != checksum:
            raise ValueError("Invalid PNG chunk checksum")
        if kind == b"IHDR":
            if dimensions is not None or length != 13:
                raise ValueError("Invalid PNG header")
            dimensions = struct.unpack(">II", payload[:8])
            if not all(value > 0 for value in dimensions):
                raise ValueError("Empty PNG dimensions")
        elif kind == b"IDAT":
            if dimensions is None:
                raise ValueError("PNG pixels before header")
            pixels = True
        elif kind == b"IEND":
            if dimensions is None or not pixels or length != 0 or end != len(data):
                raise ValueError("Incomplete PNG or unexpected trailing data")
            return dimensions
        offset = end
    raise ValueError("Missing PNG end marker")


def bundled_file(app, name):
    if not isinstance(name, str) or not name or name in (".", "..") or Path(name).name != name or "\\" in name:
        raise ValueError("Unsafe bundled resource name")
    matches = list(app.rglob(name))
    if (len(matches) != 1 or matches[0].is_symlink() or not matches[0].is_file()
            or any(part in {"PlugIns", "Frameworks"} for part in matches[0].relative_to(app).parts[:-1])):
        raise ValueError("Missing or ambiguous main-app resource: " + name)
    return matches[0]


def source_file(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing source resource: " + path.name)
    return path.read_bytes()


def verify_existing_resources(source, app):
    """Bind existing assets to the exact checked-out source, independently of old release pins."""
    vendor = source / "App/ArenaVendor"
    name = "arena-vendor-runtime.json"
    manifest_bytes = source_file(vendor / name)
    if bundled_file(app, name).read_bytes() != manifest_bytes:
        raise ValueError("Bundled vendor manifest differs from verified source")
    manifest = json.loads(manifest_bytes)
    if not isinstance(manifest, dict) or not isinstance(manifest.get("files"), list) or not manifest["files"]:
        raise ValueError("Invalid source vendor manifest")
    files, pack_count = manifest["files"], manifest.get("packCount")
    if type(pack_count) is not int or pack_count <= 0:
        raise ValueError("Invalid source vendor pack count")
    names, packs, png_count = set(), set(), 0
    for entry in files:
        if not isinstance(entry, dict):
            raise ValueError("Invalid source vendor resource entry")
        name, pack, expected = entry.get("file"), entry.get("pack"), entry.get("sha256")
        actual_path = bundled_file(app, name)
        if name in names or not isinstance(pack, str) or not pack:
            raise ValueError("Duplicate resource name or invalid source pack identity")
        if not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected):
            raise ValueError("Invalid source vendor resource digest")
        if type(entry.get("bytes")) is not int or entry["bytes"] <= 0:
            raise ValueError("Invalid source vendor resource size")
        original = source_file(vendor / name)
        if len(original) != entry["bytes"] or hashlib.sha256(original).hexdigest() != expected:
            raise ValueError("Source vendor resource differs from its manifest: " + name)
        actual = actual_path.read_bytes()
        if name.lower().endswith(".png"):
            if png_dimensions(actual) != png_dimensions(original):
                raise ValueError("Bundled PNG dimensions differ from source: " + name)
            png_count += 1
        elif hashlib.sha256(actual).hexdigest() != expected:
            raise ValueError("Bundled vendor resource differs from source: " + name)
        names.add(name)
        packs.add(pack)
    if len(packs) != pack_count:
        raise ValueError("Source vendor pack count does not match its resources")
    name = "arena-asset-configuration.json"
    configuration_bytes = source_file(vendor / name)
    if bundled_file(app, name).read_bytes() != configuration_bytes:
        raise ValueError("Bundled asset configuration differs from verified source")
    configuration = json.loads(configuration_bytes)
    canonical = configuration.get("canonicalRanger") if isinstance(configuration, dict) else None
    if not isinstance(canonical, dict) or canonical.get("file") != "Ranger_FaceSample.glb":
        raise ValueError("Missing source canonical ranger configuration")
    expected, name = canonical.get("sha256"), canonical["file"]
    if not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Invalid source canonical ranger digest")
    if hashlib.sha256(source_file(source / "App/Arena3D" / name)).hexdigest() != expected:
        raise ValueError("Source canonical ranger differs from its configuration")
    if hashlib.sha256(bundled_file(app, name).read_bytes()).hexdigest() != expected:
        raise ValueError("Bundled canonical ranger differs from verified source")
    return {"vendor_runtime_verified": True, "vendor_runtime_file_count": len(files),
            "vendor_pack_count": pack_count, "vendor_png_count": png_count,
            "vendor_png_verification": "structure-and-dimensions",
            "vendor_manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
            "asset_configuration_verified": True,
            "asset_configuration_sha256": hashlib.sha256(configuration_bytes).hexdigest(),
            "canonical_ranger_verified": True, "canonical_ranger_file": name,
            "canonical_ranger_sha256": expected}


def opaque_png_dimensions(data):
    """Require the standard RGB8/RGBA8 PNG format used by the opaque decoder."""
    dimensions = png_dimensions(data)
    if (data[8:16] != b"\x00\x00\x00\x0dIHDR" or data[24] != 8
            or data[25] not in (2, 6) or data[26:29] != b"\x00\x00\x00"):
        raise ValueError("Opaque texture requires standard noninterlaced RGB8/RGBA8 PNG")
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"CgBI":
            raise ValueError("Opaque texture cannot use Xcode CgBI PNG encoding")
        offset += length + 12  # png_dimensions already checked every chunk and CRC.
    return dimensions


def verify_opaque_textures(source, app):
    """Preserve hidden RGB at alpha zero by binding these PNG bytes to source."""
    matches = {Path(relative).name.casefold(): [] for relative in OPAQUE_TEXTURE_SOURCES}
    for path in app.rglob("*"):
        if path.name.casefold() in matches:
            matches[path.name.casefold()].append(path)
    verified = []
    for relative in OPAQUE_TEXTURE_SOURCES:
        name = Path(relative).name
        paths = matches[name.casefold()]
        if (len(paths) != 1 or paths[0] != app / name
                or paths[0].is_symlink() or not paths[0].is_file()):
            raise ValueError("Missing or ambiguous main-app opaque texture: " + name)
        original = source_file(source / relative)
        actual = paths[0].read_bytes()
        dimensions = opaque_png_dimensions(original)
        opaque_png_dimensions(actual)
        expected = hashlib.sha256(original).hexdigest()
        if hashlib.sha256(actual).hexdigest() != expected:
            raise ValueError("Bundled opaque texture differs from verified source: " + name)
        verified.append({"file": name, "source_file": relative, "bytes": len(original),
                         "width": dimensions[0], "height": dimensions[1], "sha256": expected})
    return {"opaque_textures_verified": True, "opaque_texture_count": len(verified),
            "opaque_texture_verification": "standard-png-exact-source-sha256",
            "opaque_textures": verified}


def archive(expected, source, archive_path):
    app = archive_path / "Products/Applications/ShiftReminder.app"
    paths = list(app.rglob(PACK_NAME))
    expected_path = app / PACK_NAME
    if len(paths) != 1 or paths[0] != expected_path:
        raise ValueError("Signed main app must contain exactly one private resource pack at its bundle root")
    report = verify(expected_path, expected, source)
    return {**report, **verify_existing_resources(source, app), **verify_opaque_textures(source, app)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["preflight", "install", "archive"])
    parser.add_argument("request", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if args.command == "preflight":
        preflight(promotion.load_request(args.request))
        return
    if args.source is None:
        parser.error("--source is required for install and archive")
    request = json.loads(args.request.read_text())
    expected = required_specification(request, args.source)
    transport = transport_specification(request)
    if expected is None:
        print("This release request does not include a private resource pack")
        return
    if args.command == "install":
        report = install(expected, args.source, transport)
    else:
        if args.archive is None:
            parser.error("--archive is required")
        acceptance = check_deferred_source(request) if validation_specification(request) is not None else {}
        report = archive(expected, args.source, args.archive)
        # This metadata contains no signed URL or payload and is safe to retain as an artifact.
        promotion.save_report(ARCHIVE_REPORT, request, private_resource_pack=expected["id"],
                              stage="archive", **report, **acceptance)
    # Only identity/counts are safe to retain in public CI logs.
    print(json.dumps({"private_resource_pack": expected["id"], "stage": args.command, **report}))


if __name__ == "__main__":
    main()
