#!/usr/bin/env python3
"""Inspect the APK URL returned by the official SF3 download resolver.

Consumes already captured anonymous resolver/HEAD receipts, then reads only
bounded ZIP ranges. No credentials, key lookup, decryption, game execution,
media conversion, environment changes, publication or guessed endpoint exists.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
from urllib.error import HTTPError
from urllib.request import Request, build_opener, HTTPRedirectHandler
import zlib

ROOT = Path(__file__).resolve().parents[1]
RESOLVER_SHA = "572ea8def9fdb890f008cf722a0c4e7a1f433c41455ffa21f779f39289b01c0d"
APK_URL = "https://sf3assets.nekki.com/builds/apk/7/19221.apk"
APK_BYTES = 263_891_547
MAX_RANGE = 2_000_000
MAX_TRANSFER = 4_000_000
MAX_ENTRIES = 10_000
MAX_MEMBER = 2_000_000


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read_file(path, maximum):
    path = Path(path).absolute()
    require(path.resolve(strict=True) == path, "Input must not use symlinks")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, "Bounded regular input required")
        raw = handle.read(maximum + 1)
        require(len(raw) == info.st_size, "Input changed while reading")
        return raw


def write_file(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(raw)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Ranges:
    def __init__(self, url, size, output):
        require(url == APK_URL and size == APK_BYTES, "Only the observed official APK is permitted")
        self.url, self.size, self.output = url, size, output
        self.used, self.receipts, self.requests = 0, [], set()
        self.client = build_opener(NoRedirect())

    def get(self, offset, count):
        require(type(offset) is int and type(count) is int and 0 <= offset < self.size
                and 0 < count <= MAX_RANGE and offset + count <= self.size, "Range exceeds bounds")
        require(self.used + count <= MAX_TRANSFER and (offset, count) not in self.requests,
                "Do not repeat a range or exceed the transfer budget")
        self.requests.add((offset, count))
        request = Request(self.url, headers={"Range": f"bytes={offset}-{offset + count - 1}", "Accept-Encoding": "identity"})
        try:
            response = self.client.open(request, timeout=20)
        except HTTPError as error:
            response = error
        row = dict(offset=offset, requestedBytes=count, status=response.status,
                   contentRange=response.headers.get("Content-Range"), contentLength=response.headers.get("Content-Length"))
        self.receipts.append(row)
        try:
            require(response.status == 206, "Server did not honor the range; full APK will not be downloaded")
            require(row["contentRange"] == f"bytes {offset}-{offset + count - 1}/{self.size}"
                    and row["contentLength"] == str(count)
                    and response.headers.get("Content-Encoding", "identity") == "identity", "Unexpected range envelope")
            raw = response.read(count + 1)
            require(len(raw) == count, "Truncated or oversized range")
        finally:
            response.close()
        self.used += len(raw)
        row.update(bytes=len(raw), sha256=sha(raw), file=f"range-{offset}-{count}.bin")
        write_file(self.output / row["file"], raw)
        return raw


def central_entries(raw, total, eocd):
    entries, offset, names = [], 0, set()
    while offset < len(raw):
        require(len(entries) < MAX_ENTRIES and offset + 46 <= len(raw) and raw[offset:offset + 4] == b"PK\x01\x02",
                "Malformed central directory")
        flags, method = struct.unpack_from("<HH", raw, offset + 8)
        crc, compressed, size = struct.unpack_from("<III", raw, offset + 16)
        name_size, extra_size, comment_size, disk = struct.unpack_from("<HHHH", raw, offset + 28)
        local = struct.unpack_from("<I", raw, offset + 42)[0]
        end = offset + 46 + name_size + extra_size + comment_size
        require(end <= len(raw) and disk == 0 and local < total and compressed <= total,
                "Unsupported multi-disk, ZIP64 or truncated entry")
        name = raw[offset + 46:offset + 46 + name_size].decode("utf-8" if flags & 0x800 else "cp437")
        require(name not in names and not name.startswith("/") and ".." not in name.split("/") and "\x00" not in name,
                "Unsafe or duplicate entry name")
        names.add(name)
        entries.append(dict(path=name, flags=flags, method=method, crc32=f"{crc:08x}", compressedBytes=compressed, bytes=size, offset=local))
        offset = end
    require(len(entries) == eocd, "Central entry count differs")
    return entries


def load_directory(source):
    count = min(65_557, source.size)
    tail = source.get(source.size - count, count)
    at = tail.rfind(b"PK\x05\x06")
    require(at >= 0 and at + 22 <= len(tail), "ZIP EOCD missing")
    disk, start_disk, on_disk, total, length, offset, comment = struct.unpack_from("<4H2IH", tail, at + 4)
    require(disk == start_disk == 0 and on_disk == total and 0 < total < MAX_ENTRIES
            and at + 22 + comment == len(tail) and 0 < length <= MAX_RANGE
            and offset + length == source.size - count + at, "Unsupported ZIP directory layout")
    raw = source.get(offset, length)
    return central_entries(raw, source.size, total), dict(offset=offset, bytes=length, sha256=sha(raw), entries=total)


def member_data(source, entry, prefix=False):
    require(entry["method"] in (0, 8) and not entry["flags"] & 1, "Unsupported or encrypted ZIP member")
    require(prefix or entry["bytes"] <= MAX_MEMBER, "Member exceeds its extraction bound")
    raw = source.get(entry["offset"], 30)
    require(raw[:4] == b"PK\x03\x04", "Local member header differs")
    flags, method = struct.unpack_from("<HH", raw, 6)
    name_size, extra_size = struct.unpack_from("<HH", raw, 26)
    require(flags == entry["flags"] and method == entry["method"] and name_size + extra_size <= 65_535,
            "Local member flags or header bounds differ")
    names = source.get(entry["offset"] + 30, name_size + extra_size)
    require(names[:name_size].decode("utf-8" if flags & 0x800 else "cp437") == entry["path"],
            "Local and central member names differ")
    start = entry["offset"] + 30 + name_size + extra_size
    raw = source.get(start, min(entry["compressedBytes"], 16_384) if prefix else entry["compressedBytes"])
    if method == 8:
        decoder = zlib.decompressobj(-15)
        value = decoder.decompress(raw, 16_384 if prefix else MAX_MEMBER + 1)
        if not prefix:
            require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, "Member deflate stream differs")
    else:
        value = raw
    if not prefix:
        require(len(value) == entry["bytes"] and f"{zlib.crc32(value):08x}" == entry["crc32"], "Member CRC/length differs")
    return value


def axml_manifest(raw):
    require(raw[:2] == b"\x03\x00" and struct.unpack_from("<I", raw, 4)[0] == len(raw), "Not Android binary XML")
    strings, offset = [], 8
    while offset < len(raw):
        kind, header, size = struct.unpack_from("<HHI", raw, offset)
        require(8 <= header <= size and offset + size <= len(raw), "Malformed AXML chunk")
        if kind == 1:
            count, _, flags, start, _ = struct.unpack_from("<5I", raw, offset + 8)
            require(count <= 20_000 and flags & ~0x101 == 0, "Unsupported string pool")
            locations = struct.unpack_from(f"<{count}I", raw, offset + header)
            for location in locations:
                at = offset + start + location
                if flags & 0x100:
                    def length8(at):
                        first = raw[at]
                        return (((first & 0x7f) << 8) | raw[at + 1], at + 2) if first & 0x80 else (first, at + 1)
                    _, at = length8(at)
                    length, at = length8(at)
                    value = raw[at:at + length].decode("utf-8")
                else:
                    length = struct.unpack_from("<H", raw, at)[0]
                    at += 2
                    if length & 0x8000:
                        length = ((length & 0x7fff) << 16) | struct.unpack_from("<H", raw, at)[0]
                        at += 2
                    value = raw[at:at + 2 * length].decode("utf-16le")
                strings.append(value)
        elif kind == 0x102:
            _, name, attribute_start, attribute_size, count = struct.unpack_from("<IIHHH", raw, offset + 16)
            require(name < len(strings) and attribute_size >= 20, "Malformed AXML element")
            if strings[name] == "manifest":
                result = {}
                for index in range(count):
                    at = offset + 16 + attribute_start + index * attribute_size
                    _, name, original, _, _, value_type, value = struct.unpack_from("<IIIHBBI", raw, at)
                    key = strings[name]
                    if key in ("versionCode", "versionName", "package"):
                        result[key] = strings[value] if value_type == 3 else value
                require(set(result) == {"versionCode", "versionName", "package"}, "Manifest version attributes missing")
                return result
        offset += size
    raise ValueError("AXML manifest not found")


def old_entry(row):
    return dict(path=row.get("path", row.get("name")), bytes=row.get("bytes", row.get("uncompressed_bytes")),
                crc32=row["crc32"].lower())


def inspect(args):
    output = args.output.absolute()
    require(output.parent.resolve(strict=True) == output.parent and not output.exists() and not output.is_symlink()
            and not output.is_relative_to(ROOT), "Output must be a new private directory outside the repository")
    response = read_file(args.resolver_response, 4096)
    require(sha(response) == RESOLVER_SHA, "Official resolver receipt differs")
    obj = json.loads(response)
    url = obj.get("url") or obj.get("data", {}).get("url") or obj.get("data", {}).get("data", {}).get("url")
    head = json.loads(read_file(args.head_receipt, 16_384))
    require(url == APK_URL and head["url"] == url and head["method"] == "HEAD" and head["status"] == 200
            and head["headers"]["Content-Length"] == str(APK_BYTES), "Resolver and HEAD identities differ")
    previous = []
    for path in args.previous_index:
        raw = read_file(path, 4_000_000)
        entries = [old_entry(row) for row in json.loads(raw)]
        previous.append((str(path), sha(raw), {row["path"]: row for row in entries}))
    output.mkdir(mode=0o700)
    source = Ranges(url, APK_BYTES, output)
    result = dict(schema="pangu-official-remote-index-20261115-v1", sourcePage="https://shadowfight3.com/",
                  resolverSource="https://shadowfight3.com/dist/index-page/js/main.js",
                  resolver="https://shadowfight3.com/rest/build/download/index", apkURL=url,
                  fullAPKDownloaded=False, credentialsRead=False, decryptionAttempted=False,
                  environmentChanged=False, assetsPublished=False, errors=[])
    try:
        entries, directory = load_directory(source)
        write_file(output / "apk-entry-index-private.json", json_bytes(entries))
        result["centralDirectory"] = directory
        result["entryKinds"] = dict(Counter(row["path"].split("/")[0] for row in entries))
        current = {row["path"]: row for row in entries}
        target = current["AndroidManifest.xml"]
        raw = member_data(source, target)
        write_file(output / "AndroidManifest.xml.bin", raw)
        result["manifest"] = dict(attributes=axml_manifest(raw), bytes=len(raw), sha256=sha(raw), crcVerified=True)
        result["comparisons"] = []
        for path, pin, old in previous:
            new_names = sorted(set(current) - set(old))
            changed = [name for name in current.keys() & old.keys()
                       if current[name]["bytes"] != old[name]["bytes"] or current[name]["crc32"] != old[name]["crc32"]]
            scope = [name for name in current if name.startswith("assets/bin/Data/")]
            result["comparisons"].append(dict(previousIndex=path, previousIndexSHA256=pin,
                newMembers=new_names, changedMembers=sorted(changed),
                unityMembers=len(scope), unchangedUnityCRCAndSize=sum(name in old and name not in changed for name in scope),
                CRCAndSizeIsNotSHA256Equality=True))
        result["namedIndexCandidates"] = [row["path"] for row in entries if re.search(r"(?:bundlesConfig_|bundles_\d+|\.obb$|catalog)", row["path"], re.I)]
        result["literalD19Candidates"] = [row["path"] for row in entries if re.search(r"D19_|arm__agl_48|twohanded_axe_01_02|helm__agl_48|pilum_01_08", row["path"], re.I)]
        archive_name = "assets/bin/Data/5b5574f6588b7c54db57a2940da4aabb"
        if archive_name in current:
            raw = member_data(source, current[archive_name], prefix=True)
            write_file(output / "startup-archive-prefix-private.bin", raw)
            versions = sorted(set(value.decode() for value in re.findall(rb"\d+\.\d+\.\d+\.\d+\.\d+-[a-z]+(?:_splits)?\.zip\.enc", raw)))
            result["archivePrefix"] = dict(entry=archive_name, bytes=len(raw), sha256=sha(raw),
                configMembers=versions, completeMemberDownloaded=False, completeMemberCRCVerified=False)
    except (ValueError, OSError, KeyError, UnicodeError, struct.error, zlib.error) as error:
        result["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        result["newAPKRangeBytes"] = source.used
        result["requests"] = source.receipts
        write_file(output / "recovery-receipt-private.json", json_bytes(result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolver-response", type=Path, required=True)
    parser.add_argument("--head-receipt", type=Path, required=True)
    parser.add_argument("--previous-index", type=Path, action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    result = inspect(parser.parse_args())
    print(json.dumps({key: result.get(key) for key in ("manifest", "centralDirectory", "namedIndexCandidates",
          "literalD19Candidates", "archivePrefix", "newAPKRangeBytes", "errors")}, ensure_ascii=False))
    return bool(result["errors"])


if __name__ == "__main__":
    raise SystemExit(main())
