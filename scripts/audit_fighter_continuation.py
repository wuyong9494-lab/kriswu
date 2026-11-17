#!/usr/bin/env python3
"""Audit an existing private character checkpoint without activating its assets.

Reads the content-addressed ZIP, SHA-pinned prior ZIPs and an optional restored directory. Every
blob and every referenced resource is checked by bytes and SHA-256. The receipt
contains identities and gaps, never source arrays, media bytes or download URLs.
Exit 2 means intact evidence with incomplete resource closure; it is not a pass.
No downloads, decryption, extraction, gameplay changes or release writes occur.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile
import zlib

REPOSITORY = Path(__file__).resolve().parents[1]
MAX_ARCHIVE = 512 * 1024**2
MAX_FILE = 128 * 1024**2
MAX_EXPANDED = 768 * 1024**2
MAX_FILES = 10000
MAX_SUPPLEMENTS = 4
MAX_ALL_EXPANDED = 2 * 1024**3
CURRENT_CONTOUR = "continued-20261116/erlang-runtime-contour-v2"


class AuditError(ValueError):
    pass


def require(value, message):
    if not value:
        raise AuditError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def checked_sha(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value),
            "Invalid SHA-256")
    return value


def checked_size(value):
    require(type(value) is int and 0 <= value <= MAX_FILE, "Invalid file byte count")
    return value


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value
            and all(ord(c) >= 32 for c in value), "Invalid checkpoint path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and path.as_posix() == value
            and all(part not in ("", ".", "..") for part in path.parts),
            "Unsafe checkpoint path")
    return path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def decode(raw):
    try:
        return json.loads(raw, object_pairs_hook=unique_object,
                          parse_constant=lambda _: (_ for _ in ()).throw(AuditError("Non-finite JSON")))
    except (UnicodeError, ValueError, RecursionError) as error:
        raise AuditError("Invalid checkpoint JSON") from error


def regular(path, maximum):
    path = Path(path).absolute()
    require(path.resolve(strict=True) == path and stat.S_ISREG(path.lstat().st_mode),
            "Input must be a regular file without symlinks")
    require(path.stat().st_size <= maximum, "Input exceeds byte budget")
    return path


def checked_archive(path, expected_sha256):
    path = regular(path, MAX_ARCHIVE)
    expected_sha256 = checked_sha(expected_sha256)
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    require(h.hexdigest() == expected_sha256, "Archive SHA-256 differs")
    return path


class Checkpoint:
    def __init__(self, archive, expected_sha256, restored_directory=None):
        self.archive = checked_archive(archive, expected_sha256)
        self.sha256 = expected_sha256
        self.zip = zipfile.ZipFile(self.archive)
        self.supplements, self.supplement_readers, self.supplement_members = [], [], {}
        try:
            self._verify(restored_directory)
            self.primary_paths = set(self.rows)
            self.primary_blob_count = len(self.by_digest)
            self.expanded_bytes = sum(r["bytes"] for r in self.rows.values())
        except Exception:
            self.zip.close()
            raise

    def _verify(self, restored_directory):
        members = self.zip.infolist()
        require(len(members) <= MAX_FILES + 3 and len({m.filename for m in members}) == len(members),
                "Duplicate or excessive ZIP entries")
        require(sum(m.file_size for m in members) <= MAX_EXPANDED, "Expanded ZIP exceeds budget")
        for item in members:
            safe_path(item.filename)
            require(not item.is_dir() and not stat.S_ISLNK(item.external_attr >> 16)
                    and item.file_size <= MAX_FILE, "Unsupported ZIP entry")
        require("checkpoint.json" in self.zip.namelist() and "README.txt" in self.zip.namelist(),
                "Checkpoint manifest or README missing")
        self.document = decode(self.zip.read("checkpoint.json"))
        require(self.document.get("format") == "rift-private-continuation-v1", "Unsupported checkpoint format")
        records = self.document.get("files")
        require(isinstance(records, list) and 0 < len(records) <= MAX_FILES, "Missing file inventory")
        self.rows, self.by_digest = {}, defaultdict(list)
        for row in records:
            require(isinstance(row, dict), "Invalid file record")
            name = str(safe_path(row.get("path")))
            require(name not in self.rows, "Duplicate logical file path")
            size, sha = checked_size(row.get("bytes")), checked_sha(row.get("sha256"))
            self.rows[name] = {"path": name, "bytes": size, "sha256": sha}
            self.by_digest[sha].append(self.rows[name])
        require(sum(r["bytes"] for r in self.rows.values()) <= MAX_EXPANDED,
                "Logical checkpoint exceeds budget")
        for sha, rows in self.by_digest.items():
            require(len({r["bytes"] for r in rows}) == 1, "One digest has conflicting byte counts")
            raw = self.zip.read("blobs/" + sha)
            require(len(raw) == rows[0]["bytes"] and digest(raw) == sha, "Checkpoint blob differs")
        for key, actual in (("logicalFileCount", len(self.rows)),
                            ("uniqueBlobCount", len(self.by_digest)),
                            ("logicalBytes", sum(r["bytes"] for r in self.rows.values())),
                            ("uniqueBytes", sum(rows[0]["bytes"] for rows in self.by_digest.values()))):
            require(self.document.get(key) == actual, "Checkpoint count differs: " + key)
        self.restored_verified = False
        if restored_directory is not None:
            base = Path(restored_directory).absolute()
            require(base.resolve(strict=True) == base and base.is_dir(), "Invalid restored directory")
            for name, row in self.rows.items():
                file = regular(base.joinpath(*PurePosixPath(name).parts), MAX_FILE)
                require(file.is_relative_to(base), "Restored file escapes root")
                raw = file.read_bytes()
                require(len(raw) == row["bytes"] and digest(raw) == row["sha256"],
                        "Restored bytes differ: " + name)
            self.restored_verified = True

    def add_supplement(self, archive, expected_sha256):
        """Hash prior saved files in place; a matching name alone proves nothing."""
        require(len(self.supplements) < MAX_SUPPLEMENTS, "Too many supplemental archives")
        path = checked_archive(archive, expected_sha256)
        require(expected_sha256 != self.sha256
                and all(s["sha256"] != expected_sha256 for s in self.supplements),
                "Duplicate supplemental archive")
        reader = zipfile.ZipFile(path)
        try:
            members = reader.infolist()
            require(len(members) <= MAX_FILES and len({m.filename for m in members}) == len(members),
                    "Duplicate or excessive supplemental ZIP entries")
            expanded = sum(m.file_size for m in members)
            require(expanded <= MAX_EXPANDED and self.expanded_bytes + expanded <= MAX_ALL_EXPANDED,
                    "Supplemental expanded ZIP exceeds budget")
            prefix = "supplements/" + str(len(self.supplements)) + "/"
            count = 0
            for item in members:
                name = str(safe_path(item.filename[:-1] if item.is_dir() else item.filename))
                mode = stat.S_IFMT(item.external_attr >> 16)
                require(mode in (0, stat.S_IFDIR if item.is_dir() else stat.S_IFREG)
                        and item.file_size <= MAX_FILE, "Unsupported supplemental ZIP entry")
                if item.is_dir():
                    require(item.file_size == 0, "Nonempty supplemental directory")
                    continue
                key = prefix + name
                require(key not in self.rows, "Supplement namespace conflicts with checkpoint")
                h, actual = hashlib.sha256(), 0
                with reader.open(item) as handle:
                    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                        actual += len(chunk)
                        require(actual <= item.file_size, "Supplemental entry exceeds its byte count")
                        h.update(chunk)
                require(actual == item.file_size, "Supplemental entry byte count differs")
                row = {"path": key, "bytes": actual, "sha256": h.hexdigest()}
                self.rows[key] = row
                self.by_digest[row["sha256"]].append(row)
                self.supplement_members[key] = (reader, item.filename)
                count += 1
            self.supplements.append({"name": path.name, "sha256": expected_sha256,
                                     "bytes": path.stat().st_size, "files": count,
                                     "expandedBytes": expanded, "namespace": prefix})
            self.expanded_bytes += expanded
            self.supplement_readers.append(reader)
        except Exception:
            reader.close()
            raise

    def close(self):
        self.zip.close()
        for reader in self.supplement_readers:
            reader.close()

    def raw(self, name):
        require(name in self.rows, "Missing checkpoint document: " + name)
        if name in self.supplement_members:
            reader, member = self.supplement_members[name]
            return reader.read(member)
        return self.zip.read("blobs/" + self.rows[name]["sha256"])

    def json(self, name):
        value = decode(self.raw(name))
        require(isinstance(value, dict), "Expected a JSON object: " + name)
        return value

    def locate(self, suffix):
        safe_path(suffix)
        matches = [name for name in self.rows if name == suffix or name.endswith("/" + suffix)]
        primary = [name for name in matches if name in self.primary_paths]
        if primary:
            matches = primary
        require(len(matches) == 1, "Expected one checkpoint file: " + suffix)
        return matches[0]

    def identity(self, size, sha, label):
        size, sha = checked_size(size), checked_sha(sha)
        matches = [r["path"] for r in self.by_digest.get(sha, []) if r["bytes"] == size]
        return {"label": label, "bytes": size, "sha256": sha,
                "status": "verified" if matches else "missing-from-checkpoint", "paths": matches}

    def reference(self, parent, row):
        require(isinstance(row, dict), "Invalid resource reference")
        name = row.get("file", row.get("name"))
        safe_path(name)
        result = self.identity(row.get("bytes"), row.get("sha256"), name)
        near = str(PurePosixPath(parent) / name)
        if near in self.rows:
            require(self.rows[near]["bytes"] == result["bytes"]
                    and self.rows[near]["sha256"] == result["sha256"],
                    "Resource differs from its local reference: " + near)
            result["path"] = near
        elif result["paths"]:
            result["path"] = result["paths"][0]
        return result


def source_state(document):
    """Keep recorded acceptance flags separate from checks performed now."""
    fields = ("sourceOnly", "runtimeBound", "productionActivated", "productionPinsChanged",
              "nativeRenderingVerified", "nativePlaybackVerified", "nativeOrAppExecuted",
              "gameplayOrReleaseActivated", "testFlightUploaded", "fullCharacterComplete")
    return {key: document[key] for key in fields if key in document}


def audit_d13(cp):
    bindings = []
    for kind in ("Cloud", "Bottle"):
        path = cp.locate("SF3_D13_" + kind + "_Motion_Binding.json")
        obj = cp.json(path)
        model = cp.identity(obj.get("modelBytes"), obj.get("modelSHA256"), kind.lower() + "-model")
        bindings.append({"kind": kind.lower(), "binding": cp.rows[path], "model": model,
                         "samples": len(obj.get("samples", [])),
                         "modelPresenceInferredFromBinding": False})
    path = cp.locate("serpent-abilities-models-v1/receipt-private.json")
    receipt = cp.json(path)
    products = [cp.reference(str(PurePosixPath(path).parent), row) for row in receipt.get("products", [])]
    require(products, "Ability receipt has no products")
    match_path = cp.locate("serpent-match-v2/match-integration-receipt-private.json")
    match = cp.json(match_path)
    profile = cp.reference(str(PurePosixPath(match_path).parent), match["profile"])
    return {"auditedScope": "cloud/bottle models, ability receipt products and match profile; not full D13 gameplay",
            "bindings": bindings, "abilityReceipt": cp.rows[path], "abilityProducts": products,
            "recordedAbilityState": source_state(receipt), "matchProfile": profile,
            "recordedMatchBoundaries": {key: value for key, value in match.get("boundaries", {}).items()
                                        if type(value) is bool},
            "resourceClosureComplete": all(r["status"] == "verified"
                                            for r in products + [profile] + [r["model"] for r in bindings])}


def audit_d15(cp):
    path = cp.locate(CURRENT_CONTOUR + "/erlang-contour-media-binding-private.json")
    receipt, parent = cp.json(path), str(PurePosixPath(path).parent)
    profile, character = (cp.reference(parent, receipt[key]) for key in ("profile", "character"))
    groups, media = [], {}
    audio_context = None
    reference_count = 0
    require({row.get("kind") for row in receipt.get("groups", [])} == {"audio", "hound", "stomp", "sword", "skill"}
            and len(receipt["groups"]) == 5, "D15 media groups differ")
    for group in receipt["groups"]:
        manifest = cp.reference(parent, group["manifest"])
        require(manifest["status"] == "verified", "D15 manifest missing")
        document = cp.json(manifest["path"])
        require(document.get("characterSHA256") == character["sha256"], "D15 media targets a stale character")
        if "profileSHA256" in document:
            require(document["profileSHA256"] == profile["sha256"], "D15 media targets a stale profile")
        if group["kind"] == "audio":
            audio_context = document.get("context")
        compressed = None
        if "compressedManifest" in group:
            compressed = cp.reference(parent, group["compressedManifest"])
            require(compressed["status"] == "verified", "D15 compressed manifest missing")
            raw = cp.raw(compressed["path"])
            # A compressed member may not expand beyond its already verified plain peer.
            decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
            expanded = decoder.decompress(raw, manifest["bytes"] + 1)
            require(decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data
                    and expanded == cp.raw(manifest["path"]), "D15 gzip and plain manifest differ")
        files = [cp.reference(parent, row) for row in document.get("files", [])]
        require(files, "D15 media inventory missing")
        reference_count += len(files)
        for ref in files:
            name = ref["label"]
            require(name not in media or (media[name]["sha256"], media[name]["bytes"])
                    == (ref["sha256"], ref["bytes"]), "Conflicting D15 media identities")
            media[name] = ref
        groups.append({"kind": group["kind"], "manifest": manifest,
                       "compressedManifest": compressed, "referencedMediaFiles": len(files)})
    require(receipt.get("referencedMediaFiles") == reference_count
            and receipt.get("uniqueMediaFiles") == len(media)
            and receipt.get("uniqueMediaBytes") == sum(r["bytes"] for r in media.values()),
            "D15 media receipt counts differ from referenced bytes")
    additional = []
    for name in ("SF3_D15_Companions.json", "SF3_H17_WuMorph.json"):
        paths = [p for p in cp.rows if PurePosixPath(p).name == name]
        result = {"file": name, "paths": paths, "requiredForCompleteAppCandidate": True,
                  "status": "present-but-current-actor-binding-unverified" if paths else "missing-from-checkpoint"}
        if name == "SF3_D15_Companions.json" and paths:
            require(len(paths) == 1, "Ambiguous D15 companion manifest")
            document = cp.json(paths[0])
            require(document.get("profileID") == "wuyong_erlang"
                    and document.get("characterSHA256") == character["sha256"],
                    "D15 companions target a stale character")
            models = document.get("models")
            require(isinstance(models, list) and len(models) == 1, "Unexpected D15 companion count")
            model = models[0]
            target = cp.json(profile["path"])
            track = model.get("track")
            require(isinstance(track, dict) and track.get("role") == "erlangSummon_hound"
                    and [t for t in target.get("summonTracks", []) if t.get("role") == track["role"]] == [track],
                    "D15 companion and profile tracks differ")
            resource = cp.reference(str(PurePosixPath(paths[0]).parent), model.get("file"))
            result.update(manifest=cp.rows[paths[0]], model=resource,
                          physicsAndPresentationTrackIdentical=True,
                          status="verified-current-actor-model-and-track" if resource["status"] == "verified"
                          else "missing-companion-model-bytes")
        additional.append(result)
    stage = {"requiredForCompleteAppCandidate": True, "status": "not-recorded-in-audio-manifest"}
    if audio_context:
        name, sha = str(safe_path(audio_context.get("stageName"))), checked_sha(audio_context.get("stageSHA256"))
        matches = cp.by_digest.get(sha, [])
        stage.update(file=name, sha256=sha, files=matches,
                     byteCountRecordedByAudioManifest=False,
                     status="hash-verified-size-not-recorded-by-reference" if matches else "missing-from-checkpoint")
    verified = all(r["status"] == "verified" for r in [profile, character] + list(media.values()))
    return {"receipt": cp.rows[path], "profile": profile, "character": character, "groups": groups,
            "mediaFiles": sorted(media.values(), key=lambda r: r["label"]),
            "referencedMediaFiles": reference_count, "uniqueMediaFiles": len(media),
            "uniqueMediaBytes": sum(r["bytes"] for r in media.values()),
            "contourMediaClosureComplete": verified, "additionalRuntimeManifests": additional,
            "audioContextStage": stage,
            "completeAppCandidateVerified": False, "recordedState": source_state(receipt),
            "nextAction": "Authenticate companions and victory morph against this exact actor/profile before changing production pins."}


def audit_d20(cp):
    path = cp.locate("xuxiao-founder-source-v2/xuxiao-required-resources-v1.json")
    document = cp.json(path)
    require(isinstance(document.get("equipment"), list) and isinstance(document.get("motions"), list),
            "D20 resource requirements missing")
    missing_equipment, missing_motions, bundle_refs = [], [], {}
    resources = {"equipment": [], "motions": []}
    for kind, entries in (("equipment", document["equipment"]), ("motions", document["motions"])):
        for row in entries:
            bundles = row.get("sourceBundles")
            require(isinstance(bundles, list), "Missing explicit D20 source bundle list")
            identity = {key: row[key] for key in ("symbol", "model", "sourceFile", "aliases") if key in row}
            if not bundles:
                (missing_equipment if kind == "equipment" else missing_motions).append(
                    identity)
            verified_refs = []
            for item in bundles:
                ref = cp.identity(item.get("bytes"), item.get("sha256"), str(safe_path(item.get("file"))))
                bundle_refs[(ref["sha256"], ref["bytes"])] = ref
                verified_refs.append(ref)
            resources[kind].append(dict(identity, sourceBundles=verified_refs,
                catalogMappingPresent=bool(bundles),
                allReferencedBundleBytesVerified=bool(verified_refs)
                    and all(r["status"] == "verified" for r in verified_refs),
                decodedSourceObjectVerifiedByThisAudit=False))
    candidates = [cp.rows[name] for name in cp.rows
                  if re.fullmatch(r"bundles_[0-9]+\.bytes|bundlesConfig_[^/]+\.bytes", PurePosixPath(name).name)]
    archives = [cp.rows[name] for name in cp.rows if PurePosixPath(name).name == "archive.bytes"]
    return {"requirements": cp.rows[path], "recordedState": source_state(document),
            "equipmentCandidates": len(document["equipment"]), "motionFiles": len(document["motions"]),
            "missingEquipment": missing_equipment, "missingMotionFiles": missing_motions,
            "missingListMeaning": "no authenticated catalog mapping; mapped resources can still lack physical bundle bytes",
            "resources": resources,
            "equipmentWithoutVerifiedBundleBytes": sum(not r["allReferencedBundleBytesVerified"] for r in resources["equipment"]),
            "motionsWithoutVerifiedBundleBytes": sum(not r["allReferencedBundleBytesVerified"] for r in resources["motions"]),
            "catalogBundleReferences": list(bundle_refs.values()),
            "catalogMatchesArePhysicalByteProof": False, "indexFileCandidates": candidates,
            "configArchiveFiles": archives, "authenticatedDynamicIndexRecoveredByThisAudit": False,
            "resourceClosureComplete": False,
            "resumeRequirements": [
                "Use an already captured successful original balancer response or the actual ordinary-client bundle index; do not infer an index URL from the APK number.",
                "Authenticate BConfigData against the original descriptor, resolve all exact equipment/motion paths and close archive dependencies by real hash and byte count.",
                "Treat archive.bytes as an unclassified config container until its actual decoded member schema proves it contains a bundle index.",
                "Retain screenshots/UI stage and ordinary initialization/network logs when an index is absent; elapsed polls and a live PID do not establish completed initialization."],
            "repeatDownloadOrRuntimeRequiredByThisAudit": False}


def audit(archive, expected_sha256, restored_directory=None, supplemental_archives=()):
    cp = Checkpoint(archive, expected_sha256, restored_directory)
    try:
        for supplemental, sha in supplemental_archives:
            cp.add_supplement(supplemental, sha)
        d13, d15, d20 = audit_d13(cp), audit_d15(cp), audit_d20(cp)
        return {"schema": "fighter-continuation-audit-v1", "integrityVerified": True,
                "archive": {"bytes": cp.archive.stat().st_size, "sha256": cp.sha256,
                            "logicalFiles": len(cp.primary_paths), "uniqueBlobs": cp.primary_blob_count},
                "supplementalArchives": cp.supplements,
                "readmeSHA256": digest(cp.zip.read("README.txt")),
                "restoredFilesVerified": cp.restored_verified,
                "D13": d13, "D15": d15, "D20": d20,
                "resourceClosureComplete": False, "productionReady": False,
                "nativeTestsExecuted": False, "deviceAcceptancePerformed": False,
                "productionPinsChanged": False, "testFlightUploaded": False}
    finally:
        cp.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--restored-directory", type=Path)
    parser.add_argument("--supplemental-archive", nargs=2, action="append", default=[],
                        metavar=("ZIP", "SHA256"),
                        help="Existing saved plain ZIP and its exact SHA-256; repeat for each saved checkpoint or candidate")
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    target = args.receipt.absolute()
    require(target.parent.resolve(strict=True) == target.parent and not target.is_relative_to(REPOSITORY),
            "Receipt must be outside the repository in an existing private directory")
    report = audit(args.archive, args.expected_sha256, args.restored_directory, args.supplemental_archive)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
    print(json.dumps({"integrityVerified": True, "resourceClosureComplete": report["resourceClosureComplete"],
                      "D13AuditedResourcesComplete": report["D13"]["resourceClosureComplete"],
                      "D15ContourMediaComplete": report["D15"]["contourMediaClosureComplete"],
                      "D20MissingEquipment": len(report["D20"]["missingEquipment"]),
                      "D20MotionsWithoutCatalogMatch": len(report["D20"]["missingMotionFiles"]),
                      "D20MotionsWithoutVerifiedBundleBytes": report["D20"]["motionsWithoutVerifiedBundleBytes"],
                      "productionReady": False}))
    return 0 if report["resourceClosureComplete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
