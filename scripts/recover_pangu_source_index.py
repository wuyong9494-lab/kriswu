#!/usr/bin/env python3
"""Inspect existing source containers and recover exact D19 resource candidates.

No network, credentials, decryption, game execution, conversion or release writes.
The supplied original protobuf descriptor pins the BConfigData schema. Local
Unity TextAssets are examined by type/content, not just by filename. A match is
an original container candidate, not proof of a finished animated character.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from contextlib import redirect_stderr, redirect_stdout
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import warnings
from urllib.parse import urlsplit, urlunsplit
from zipfile import BadZipFile, ZipFile

REPOSITORY = Path(__file__).resolve().parents[1]
DESCRIPTOR_SHA = "f6498173aceffbf75ce671493fed3d6a97525ec73e60847fe34809da5d9d4be5"
MOTION_SHA = "baa0a83c58348c3842b4a442ea534f875168a93a411646ed6c7e07e5d2941d45"
EQUIPMENT_SHA = "fdaf44812d2e5aa02baf876a401ea507a8f83a7e11f76ac274f60532825b1901"
MAX_INDEX = 16_000_000
MAX_ZIP_PAYLOAD = 32_000_000
MAX_ZIP_EXPANDED = 64_000_000
MAX_MEMBER = 160_000_000  # Supplied IPA resources.assets is 123,797,852 bytes.
MAX_SCAN = 400_000_000
MAX_ENTRIES = 100_000
SKIP_NAME = re.compile(r"(?i)(?:internalsettings|credential|secret|password|private.?key|decrypt|keychain|\.key$)")
EXTENSIONS = {".bin", ".bytes", ".assets", ".unity3d", ".json", ".gz"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON field")
        result[key] = value
    return result


def read_regular(path, maximum=MAX_MEMBER):
    path = Path(path)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), "Source must be a regular non-symlink file")
    require(0 < info.st_size <= maximum, "Source exceeds its byte bound")
    return path.read_bytes()


def load_json(path, expected=None):
    data = read_regular(path, MAX_INDEX)
    require(expected is None or sha(data) == expected, "Source receipt pin differs")
    return json.loads(data, object_pairs_hook=unique_object)


def varint(data, offset):
    result = 0
    for shift in range(0, 70, 7):
        require(offset < len(data), "Truncated protobuf varint")
        byte = data[offset]
        offset += 1
        require(shift < 63 or byte <= 1, "Protobuf varint overflow")
        result |= (byte & 127) << shift
        if byte < 128:
            return result, offset
    raise ValueError("Protobuf varint overflow")


def wire(data, limit=MAX_ENTRIES):
    require(isinstance(data, bytes) and len(data) <= MAX_INDEX, "Protobuf input exceeds its byte bound")
    offset, values = 0, []
    while offset < len(data):
        require(len(values) < limit, "Protobuf field count exceeds its bound")
        tag, offset = varint(data, offset)
        number, kind = tag >> 3, tag & 7
        require(number > 0, "Invalid protobuf field number")
        if kind == 0:
            value, offset = varint(data, offset)
        elif kind == 2:
            size, offset = varint(data, offset)
            require(size <= len(data) - offset, "Truncated protobuf field")
            value, offset = data[offset:offset + size], offset + size
        else:
            raise ValueError("Unsupported protobuf wire type for this source schema")
        values.append((number, kind, value))
    return values


def text(value):
    require(isinstance(value, bytes) and len(value) <= 4096, "Index string exceeds its bound")
    value = value.decode("utf-8")
    require("\x00" not in value and all(ord(c) >= 32 for c in value), "Index string has control characters")
    return value


def one(fields, number, kind, default=None):
    items = [(wire_kind, value) for field, wire_kind, value in fields if field == number]
    require(len(items) <= 1 and (not items or items[0][0] == kind), "Duplicate field or unexpected protobuf type")
    return items[0][1] if items else default


def string_field(fields, number, default=""):
    value = one(fields, number, 2)
    return default if value is None else text(value)


def string_list(fields, number):
    values = []
    for field, kind, value in fields:
        if field == number:
            require(kind == 2, "Unexpected repeated-string type")
            values.append(text(value))
    return values


def parse_archive(data):
    fields = wire(data)
    require(all(n in {1, 2, 4, 5, 6, 7, 8, 9, 10, 11} for n, _, _ in fields), "Unknown BArchiveData field")
    size = one(fields, 2, 0, 0)
    require(size < 2 ** 63, "Negative or overflowing source archive size")
    for flag in (5, 11):
        require(one(fields, flag, 0, 0) in (0, 1), "Invalid source archive bool")
    labels = {}
    for number, kind, payload in fields:
        if number != 1:
            continue
        require(kind == 2, "Invalid labels map type")
        entry = wire(payload)
        require(all(n in (1, 2) for n, _, _ in entry), "Unknown labels map field")
        key, value = string_field(entry, 1), one(entry, 2, 2, b"")
        require(key and key not in labels, "Empty or duplicate source label")
        nested = wire(value)
        require(all(n == 1 and k == 2 for n, k, _ in nested), "Unknown label value field")
        labels[key] = string_list(nested, 1)
    return dict(size=size, realHash=string_field(fields, 4), available=bool(one(fields, 5, 0, 0)),
                crc=string_field(fields, 6), tags=string_list(fields, 7), assets=string_list(fields, 8),
                dependencies=string_list(fields, 9), name=string_field(fields, 10),
                local=bool(one(fields, 11, 0, 0)), labels=labels)


def parse_bconfig(data):
    """Original paths map key is int64, not a resource-path string."""
    root = wire(data)
    require(root and all(n in (1, 2) and kind == 2 for n, kind, _ in root), "Not source BConfigData")
    archives, paths = {}, {}
    for number, _, payload in root:
        entry = wire(payload)
        require(all(n in (1, 2) for n, _, _ in entry), "Unknown source index map field")
        if number == 1:
            key, value = string_field(entry, 1), one(entry, 2, 2)
            require(key and key not in archives and value is not None, "Invalid archive map entry")
            archives[key] = parse_archive(value)
        else:
            key, value = one(entry, 1, 0, 0), string_field(entry, 2)
            key = key if key < 2 ** 63 else key - 2 ** 64
            require(key not in paths and value, "Invalid int64 path-map entry")
            paths[key] = value
    require(archives and any(row["assets"] or row["name"] for row in archives.values()), "No usable source archive entries")
    return dict(schema="BConfigData", archives=archives, paths=paths)


def metadata_url(document, platform):
    require(isinstance(document, dict) and set(document) == {"platforms", "baseUrl"}, "Not the recovered metadata schema")
    platforms = document["platforms"]
    require(isinstance(platforms, dict) and 0 < len(platforms) <= 32 and platform in platforms,
            "Requested platform absent from actual metadata")
    require(all(isinstance(k, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,63}", k) and
                type(v) is int and 0 <= v < 2 ** 63 for k, v in platforms.items()), "Invalid platform/version metadata")
    require(isinstance(document["baseUrl"], str), "Metadata baseUrl is not a string")
    url = urlsplit(document["baseUrl"])
    require(url.scheme == "https" and url.hostname and "." in url.hostname and not url.username and not url.password
            and not url.query and not url.fragment and url.port in (None, 443), "Metadata URL is not an uncredentialed HTTPS base")
    require(not any(x in url.path.split("/") for x in (".", "..")), "Metadata URL contains traversal")
    return urlunsplit((url.scheme, url.netloc, url.path.rstrip("/") + f"/{platform}-{platforms[platform]}.zip", "", ""))


def targets(motions, equipment):
    motion_groups = defaultdict(list)
    for item in motions["unrecovered"]:
        source = PurePosixPath(item["sourceFile"])
        require(not source.is_absolute() and ".." not in source.parts and source.suffix == ".bin"
                and str(source).lower().startswith("unique_moves/sets_d19/"), "Unexpected dedicated D19 source identity")
        motion_groups[str(source)].append(item["animation"])
    require(len(motion_groups) == 11 and sum(map(len, motion_groups.values())) == 12,
            "Reviewed D19 exclusive motion coverage changed")
    output = []
    for source, aliases in sorted(motion_groups.items()):
        asset = "content/animations/binaries/" + str(PurePosixPath(source).with_suffix(".bytes"))
        output.append(dict(id=source, kind="motion", aliases=aliases,
                           exactPaths=[source.lower(), asset.lower(), "assets/gamedata/resources/" + asset.lower()]))
    require(len(equipment["items"]) == 5, "Reviewed D19 equipment coverage changed")
    for item in equipment["items"]:
        model = item["model"].lower()
        require(any(x.startswith("SET_DYNASTY_19_") for x in item["equipmentTags"]), "Equipment is not source D19")
        output.append(dict(id=item["symbol"], kind="equipment", model=item["model"], itemID=item["itemID"],
                           bundleName="resources-content-items-models-" + model.replace("/", "-"),
                           prefixes=["content/items/models/" + model + "/",
                                     "assets/gamedata/resources/content/items/models/" + model + "/"]))
    return output


def matching_targets(path, specs):
    require(isinstance(path, str), "Resource path is not a string")
    path = path.replace("\\", "/").lower()
    return [s["id"] for s in specs if path in s.get("exactPaths", []) or
            path == s.get("bundleName") or any(path.startswith(prefix) for prefix in s.get("prefixes", []))]


def motion_names(name, specs):
    """An exact dedicated TextAsset name is a candidate, still pending path/decoder proof."""
    value = name.replace("\\", "/").lower()
    return [s["id"] for s in specs if s["kind"] == "motion" and value in
            {PurePosixPath(s["id"]).name.lower(), PurePosixPath(s["id"]).stem.lower(),
             str(PurePosixPath(s["id"]).with_suffix(".bytes")).split("/")[-1].lower()}]


def serialized_header(data, total_size=None):
    """Recognize bounded Unity serialized files even when the cached suffix is .bin."""
    if len(data) < 20:
        return False
    metadata, size, version, offset = struct.unpack_from(">4I", data)
    if not 6 <= version <= 30:
        return False
    if version >= 22:
        if len(data) < 48:
            return False
        metadata, size, offset = struct.unpack_from(">IQQ", data, 20)
    return size == (len(data) if total_size is None else total_size) and 0 < metadata < size and 16 <= offset < size


def supported_header(prefix, total_size):
    return (prefix.startswith((b"UnityFS\x00", b"PK\x03\x04", b"\x1f\x8b")) or
            serialized_header(prefix, total_size) or prefix.lstrip().startswith(b"{") or
            prefix[:1] in (b"\x0a", b"\x12"))


def dependency_closure(index, roots):
    archives = index["archives"]
    names = defaultdict(list)
    for key, row in archives.items():
        if row["name"]:
            names[row["name"]].append(key)
    found, unresolved, queue = set(), set(), list(roots)
    while queue:
        key = queue.pop()
        require(key in archives, "Unknown selected archive")
        if key in found:
            continue
        found.add(key)
        for dependency in archives[key]["dependencies"]:
            if dependency in archives:
                queue.append(dependency)
            elif len(names.get(dependency, [])) == 1:
                queue.append(names[dependency][0])
            else:
                unresolved.add(dependency)
    return sorted(found), sorted(unresolved)


def index_matches(index, specs):
    matches = defaultdict(set)
    for key, row in index["archives"].items():
        for path in [row["name"], *row["assets"]]:
            for target in matching_targets(path, specs):
                matches[target].add(key)
    roots = {x for values in matches.values() for x in values}
    closure, unresolved = dependency_closure(index, roots)
    return dict(matches={k: sorted(v) for k, v in sorted(matches.items())},
                archivesNeeded=closure, unresolvedDependencies=unresolved,
                pathMapEntries=len(index["paths"]),
                boundary="int64 path IDs are retained; labels/path-map strings are not guessed to be archive ownership.")


def sniff_index(payload):
    """Only known raw JSON/protobuf or bounded gzip wrappers; never decrypt."""
    if not payload or len(payload) > MAX_INDEX:
        return None
    wrapper = "raw"
    if payload.startswith(b"\x1f\x8b"):
        with gzip.GzipFile(fileobj=io.BytesIO(payload)) as compressed:
            payload = compressed.read(MAX_INDEX + 1)
        require(len(payload) <= MAX_INDEX, "Gzip index exceeds expanded byte bound")
        wrapper = "gzip"
    if not payload:
        return None
    if payload.lstrip().startswith(b"{"):
        try:
            document = json.loads(payload, object_pairs_hook=unique_object)
        except (ValueError, UnicodeError):
            return None
        if isinstance(document, dict) and set(document) == {"platforms", "baseUrl"}:
            return dict(kind="metadata", wrapper=wrapper, document=document)
        return None
    if payload[0] not in (10, 18):
        return None
    try:
        index = parse_bconfig(payload)
    except (ValueError, UnicodeError):
        return None
    return dict(kind="BConfigData", wrapper=wrapper, document=index)


def private_output(path):
    path = Path(path).absolute()
    require(path.parent.resolve(strict=True) == path.parent and REPOSITORY not in path.parents
            and not path.exists() and not path.is_symlink(), "Output must be new, outside the repo, without symlink parents")
    path.mkdir(mode=0o700)
    return path


def write_private(path, data):
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as file:
        file.write(data)


class Scan:
    def __init__(self, specs, output, maximum=MAX_SCAN):
        self.specs, self.output, self.maximum = specs, output, maximum
        self.bytes = 0
        self.seen = set()
        self.report = dict(scannedContainers=[], typedTextAssets=0, duplicateContainersReused=0,
                           skippedSensitiveNames=0, indexes=[], containerCandidates=[],
                           motionTextAssetCandidates=[], resourceManagerPaths=0,
                           zipPayloadMembers=0, zipPayloadBytes=0, skipped=[], errors=[])

    def inspect_payload(self, data, label, depth=0):
        if data.startswith(b"PK\x03\x04"):
            if depth >= 3 or len(data) > MAX_ZIP_PAYLOAD:
                self.report["skipped"].append(dict(source=label, reason="nested_zip_bound"))
                return
            try:
                with ZipFile(io.BytesIO(data)) as zipped:
                    infos = zipped.infolist()
                    require(len(infos) <= 10_000 and sum(x.file_size for x in infos) <= MAX_ZIP_EXPANDED,
                            "Expanded index ZIP exceeds bound")
                    require(len({x.filename for x in infos}) == len(infos), "Duplicate index ZIP member")
                    for info in infos:
                        if info.is_dir():
                            continue
                        if SKIP_NAME.search(info.filename) or info.flag_bits & 1 or stat.S_ISLNK(info.external_attr >> 16):
                            self.report["skipped"].append(dict(source=label + "::ZIP:" + info.filename,
                                                              reason="sensitive_encrypted_or_symlink_zip_member"))
                            continue
                        require(self.report["zipPayloadBytes"] + info.file_size <= 128_000_000,
                                "Aggregate nested index ZIP exceeds bound")
                        self.report["zipPayloadMembers"] += 1
                        self.report["zipPayloadBytes"] += info.file_size
                        self.inspect_payload(zipped.read(info), label + "::ZIP:" + info.filename, depth + 1)
            except (ValueError, OSError, EOFError, BadZipFile, RuntimeError, NotImplementedError) as error:
                self.report["errors"].append(dict(source=label, kind=type(error).__name__))
            return
        try:
            result = sniff_index(data)
        except (ValueError, OSError, EOFError):
            return
        if result is None:
            return
        value = dict(source=label, bytes=len(data), sha256=sha(data), kind=result["kind"], wrapper=result["wrapper"])
        if result["kind"] == "BConfigData":
            value.update(index_matches(result["document"], self.specs))
            value["archiveCount"] = len(result["document"]["archives"])
        else:
            document = result["document"]
            try:
                value["archiveURLs"] = {p: metadata_url(document, p) for p in document["platforms"]}
            except (ValueError, TypeError):
                return
            value["URLSource"] = "Only actual metadata values; no request has been made."
        self.report["indexes"].append(value)

    def container(self, data, label):
        require(self.bytes + len(data) <= self.maximum, "Aggregate container scan byte bound exceeded")
        self.bytes += len(data)
        digest = sha(data)
        if digest in self.seen:
            self.report["duplicateContainersReused"] += 1
            return
        self.seen.add(digest)
        self.inspect_payload(data, label)
        suffix = Path(label).suffix.lower()
        if not (data.startswith(b"UnityFS\x00") or serialized_header(data) or suffix in {".assets", ".unity3d"}):
            return
        import UnityPy
        UnityPy.config.FALLBACK_UNITY_VERSION = "6000.3.11f1"
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", Warning)
                with open(os.devnull, "w") as quiet, redirect_stdout(quiet), redirect_stderr(quiet):
                    environment = UnityPy.load(data)
                paths = []
                for path, pointer in environment.container.items():
                    matches = matching_targets(path, self.specs)
                    if matches:
                        obj = pointer.deref()
                        paths.append(dict(path=path, targets=matches, pathID=str(obj.path_id), type=obj.type.name))
                for obj in environment.objects:
                    if obj.type.name == "ResourceManager":
                        try:
                            manager = obj.read()
                            self.report["resourceManagerPaths"] += len(manager.m_Container)
                            for path, pointer in manager.m_Container:
                                matches = matching_targets(path, self.specs)
                                if matches:
                                    paths.append(dict(path=path, targets=matches, type="ResourceManager reference",
                                                      pathID=str(pointer.m_PathID), fileID=pointer.m_FileID))
                        except Exception as error:
                            self.report["errors"].append(dict(source=label, pathID=str(obj.path_id),
                                                              kind=type(error).__name__))
                        continue
                    if obj.type.name != "TextAsset":
                        continue
                    try:
                        asset = obj.read()
                    except Exception as error:
                        self.report["errors"].append(dict(source=label, pathID=str(obj.path_id),
                                                          kind=type(error).__name__))
                        continue
                    name = asset.m_Name
                    if SKIP_NAME.search(name):
                        self.report["skippedSensitiveNames"] += 1
                        continue
                    script = asset.m_Script
                    payload = script.encode("utf-8", "surrogateescape") if isinstance(script, str) else bytes(script)
                    self.report["typedTextAssets"] += 1
                    self.inspect_payload(payload, f"{label}::TextAsset:{name}:pathID={obj.path_id}")
                    hits = motion_names(name, self.specs)
                    if hits:
                        candidate = self.output / ("D19_motion_candidate_" + sha(payload) + ".bin")
                        if not candidate.exists():
                            write_private(candidate, payload)
                        self.report["motionTextAssetCandidates"].append(dict(file=candidate.name, source=label,
                            name=name, pathID=str(obj.path_id), targets=hits, bytes=len(payload), sha256=sha(payload),
                            fullPathVerified=False, motionDecoded=False, runtimeInstalled=False))
                self.report["scannedContainers"].append(dict(source=label, bytes=len(data), sha256=digest,
                    objects=len(environment.objects), containerPaths=len(environment.container)))
                if paths:
                    # Preserve the actual containing bundle, not converted meshes or an invented character.
                    name = "D19_container_" + digest + ".bin"
                    write_private(self.output / name, data)
                    self.report["containerCandidates"].append(dict(file=name, source=label, bytes=len(data),
                        sha256=digest, paths=paths, modelComplete=False, motionDecoded=False, runtimeInstalled=False))
        except Exception as error:
            self.report["errors"].append(dict(source=label, kind=type(error).__name__))

    def directory(self, directory):
        root = Path(directory)
        require(root.is_dir() and not root.is_symlink(), "Cache root must be a real directory")
        files = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in EXTENSIONS)
        require(len(files) <= MAX_ENTRIES, "Cache file count exceeds bound")
        for path in files:
            if SKIP_NAME.search(path.name) or path.is_symlink():
                self.report["skippedSensitiveNames"] += 1
                continue
            if not 0 < path.stat().st_size <= MAX_MEMBER:
                self.report["skipped"].append(dict(source=str(path), reason="member_size_bound"))
                continue
            self.container(read_regular(path), str(path))

    def archive(self, path):
        path = Path(path)
        require(stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink(),
                "Cache archive must be a regular non-symlink file")
        with ZipFile(path) as archive:
            infos = archive.infolist()
            require(len(infos) <= MAX_ENTRIES, "Archive member count exceeds bound")
            names = set()
            for info in infos:
                require(info.filename not in names, "Duplicate source archive member")
                names.add(info.filename)
                if info.is_dir():
                    continue
                label = str(path) + "::" + info.filename
                if SKIP_NAME.search(info.filename):
                    self.report["skippedSensitiveNames"] += 1
                    continue
                if info.flag_bits & 1 or not 0 < info.file_size <= MAX_MEMBER or stat.S_ISLNK(info.external_attr >> 16):
                    self.report["skipped"].append(dict(source=label, reason="encrypted_symlink_or_size_bound"))
                    continue
                if PurePosixPath(info.filename).suffix.lower() not in EXTENSIONS:
                    with archive.open(info) as member:
                        prefix = member.read(48)
                    if not supported_header(prefix, info.file_size):
                        continue
                require(self.bytes + info.file_size <= self.maximum, "Aggregate container scan byte bound exceeded")
                self.container(archive.read(info), label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--descriptor", type=Path, required=True)
    parser.add_argument("--motion-inventory", type=Path, default=Path(__file__).with_name("pangu_source_motion_inventory_20261114.json"))
    parser.add_argument("--equipment-inventory", type=Path, default=Path(__file__).with_name("pangu_source_identity_20261114.json"))
    parser.add_argument("--cache-root", type=Path, action="append", default=[])
    parser.add_argument("--archive", type=Path, action="append", default=[])
    parser.add_argument("--index", type=Path, action="append", default=[],
                        help="Existing raw protobuf/metadata or an unencrypted source ZIP wrapper")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(args.cache_root or args.archive or args.index, "Supply an existing cache, archive or actual index")
    descriptor = read_regular(args.descriptor, 1024)
    require(len(descriptor) == 591 and sha(descriptor) == DESCRIPTOR_SHA, "Original protobuf descriptor pin differs")
    specs = targets(load_json(args.motion_inventory, MOTION_SHA), load_json(args.equipment_inventory, EQUIPMENT_SHA))
    output = private_output(args.output)
    scan = Scan(specs, output)
    for path in args.index:
        data = read_regular(path, MAX_ZIP_PAYLOAD)
        require(data.startswith(b"PK\x03\x04") or sniff_index(data) is not None,
                "Supplied index is not a supported source index or source ZIP wrapper")
        scan.container(data, str(path))
    for path in args.cache_root:
        scan.directory(path)
    for path in args.archive:
        scan.archive(path)
    report = dict(schema="private-D19-source-index-recovery-v1", descriptorSHA256=DESCRIPTOR_SHA,
                  motionInventorySHA256=MOTION_SHA, equipmentInventorySHA256=EQUIPMENT_SHA,
                  targetSpecs=specs, scannedBytes=scan.bytes, **scan.report,
                  networkRequests=0, decrypted=False, keysRead=False, uploaded=False,
                  allPublicSourcesExhausted=False,
                  boundaries=["A matching original container is still pending object decoding, model/weapon binding and runtime acceptance.",
                              "realHash and crc stay opaque source fields; no unsupported digest algorithm is assumed.",
                              "Files excluded by bounds, sensitive names or unsupported framing remain explicitly outside this scan.",
                              "No absence result is claimed to cover unprovided on-device or remote caches."])
    write_private(output / "pangu-source-index-recovery-private.json",
                  (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode())
    print(json.dumps(dict(output=str(output), scannedBytes=scan.bytes,
        unityContainers=len(scan.report["scannedContainers"]), typedTextAssets=scan.report["typedTextAssets"],
        indexCandidates=len(scan.report["indexes"]), D19ContainerCandidates=len(scan.report["containerCandidates"]),
        D19MotionTextAssetCandidates=len(scan.report["motionTextAssetCandidates"]),
        parseErrors=len(scan.report["errors"]), networkRequests=0)))


if __name__ == "__main__":
    main()
