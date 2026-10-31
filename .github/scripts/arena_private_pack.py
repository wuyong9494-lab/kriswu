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

PACK_NAME = "arena-original-resources.arenapack"
MAX_BYTES = 1024 * 1024 * 1024 + 8 * 1024 * 1024 + 15


def specification(request):
    value = request.get("private_resource_pack")
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {"id", "bytes", "sha256"}:
        raise ValueError("Private resource pack requires id, bytes and sha256 only")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,160}", value["id"]) or value["id"] in {".", ".."}:
        raise ValueError("Invalid private resource pack identity")
    if type(value["bytes"]) is not int or not 15 < value["bytes"] <= MAX_BYTES:
        raise ValueError("Invalid private resource pack size")
    if not re.fullmatch(r"[a-f0-9]{64}", value["sha256"]):
        raise ValueError("Invalid private resource pack digest")
    return value


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


def install(expected, source):
    url = os.environ.get("ARENA_PRIVATE_PACK_URL", "")
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        raise ValueError("Configure the private resource pack download secret")
    output = source / "App/Resources" / PACK_NAME
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".partial")
    try:
        # Do not allow an HTTP error's exception text to expose a signed URL.
        opener = urllib.request.build_opener(HTTPSOnly())
        with opener.open(urllib.request.Request(url, headers={"Accept": "application/octet-stream"}), timeout=60) as response:
            if response.geturl().split(":", 1)[0] != "https":
                raise ValueError("Private resource download requires HTTPS")
            length = response.headers.get("Content-Length")
            if length is not None and int(length) != expected["bytes"]:
                raise ValueError("Private resource download length mismatch")
            written = 0
            with temporary.open("wb") as destination:
                while block := response.read(1024 * 1024):
                    written += len(block)
                    if written > expected["bytes"]:
                        raise ValueError("Private resource download exceeded expected size")
                    destination.write(block)
                destination.flush()
                os.fsync(destination.fileno())
        report = verify(temporary, expected, source)
        temporary.replace(output)
        return report
    except Exception:
        raise RuntimeError("Private resource preparation failed; check secret access, expected size and digest") from None
    finally:
        temporary.unlink(missing_ok=True)


def archive(expected, source, archive_path):
    app = archive_path / "Products/Applications/ShiftReminder.app"
    paths = list(app.rglob(PACK_NAME))
    expected_path = app / PACK_NAME
    if len(paths) != 1 or paths[0] != expected_path:
        raise ValueError("Signed main app must contain exactly one private resource pack at its bundle root")
    return verify(expected_path, expected, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["install", "archive"])
    parser.add_argument("request", type=Path)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    expected = required_specification(json.loads(args.request.read_text()), args.source)
    if expected is None:
        print("This release request does not include a private resource pack")
        return
    if args.command == "install":
        report = install(expected, args.source)
    else:
        if args.archive is None:
            parser.error("--archive is required")
        report = archive(expected, args.source, args.archive)
    # Only identity/counts are safe to retain in public CI logs.
    print(json.dumps({"private_resource_pack": expected["id"], "stage": args.command, **report}))


if __name__ == "__main__":
    main()
