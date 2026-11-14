#!/usr/bin/env python3
"""One reviewed H17/D19 native acceptance build; encrypted diagnostics only.

Reuses the established 73 authenticated resources and adds an independently
pinned private release. Original source media and shader programs never appear
in public logs/artifacts. Existing helpers and their scope guards are untouched.
"""
import argparse
import base64
import binascii
import collections
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
WORKFLOW = ".github/workflows/fighter-pangu-native.yml"
COMMIT_MESSAGE = "Verify Pangu native bindings 20261114"
# Filled only after the source and private release are frozen and reviewed.
# A pending pin deliberately makes preparation fail before native execution.
REVIEWED_SOURCE = 'aa4ba2d34794b73c13d5f7eb49cf8ace372d9eb2'
REVIEWED_ENTRIES = {'App': '56ef51ae632528816d4bcea6f046146153502b2e', 'Package.swift': 'ffc64914ed88ae83bb4569fea0777b08ea2d29b6', 'Shared': 'e41e160b4262a9defbb3c5e92b4d020c5e0c2b80', 'Sources': '2aa8e3f1fd076cafe63bede38ee63170033d1690', 'Tests': '48608814af25c4bf1905527ec618d18d547466f2', 'Widget': 'dc5c0075ea1fb8ed0a44c68f2fea21dfc92112d3', 'project.yml': 'e0bc07a690e2195cc3caff27a6098aeebd608c7c', 'scripts': '9d299a98b97676035dfb392d7205f0ec0499da5d'}
RELEASE_MANIFEST = ".github/private/fighter-h17-d19/manifest.json"
RELEASE_MANIFEST_SHA256 = '6dfb96cb056834521f6dac0d19235cea6208ed09247171313dff3927a522c69e'
BASE_MANIFEST_PINS = {
    ".github/private/sf3/manifest.json": "f454b50969212171dfe07c34abc497854a6fc59fd55f62aceec64e74eef5c7d0",
    ".github/private/sf3-distinct/manifest.json": "a1eb14298057e11ebe3099d5a6b19df9ce404c2243446f9caffed2f7b0163e4e",
    ".github/private/fighter-presentation/manifest.json": "0595cdd5b06068a1c2ea8e1a304195ac1b7d404d5051935e19cc4188c0d3cad5",
    ".github/private/fighter-source-trails/manifest.json": "390dd75ac5aa218bdd2cd3c5909ca75a0c2148c5676687dd6fd732fb797471cb",
}
RECIPIENT = ROOT / ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA256 = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
MANIFESTS = (
    ".github/private/sf3/manifest.json",
    ".github/private/sf3-distinct/manifest.json",
    ".github/private/fighter-presentation/manifest.json",
    ".github/private/fighter-source-trails/manifest.json",
)
SYNTHETIC_SOURCES = (
    ("DuelFighterAssetReleaseLoaderTests", 12),
    ("DuelFighterCharacterContainerTests", 10),
    ("DuelPanguSourceAudioBindingTests", 13),
    ("DuelPanguSourceTrailBindingTests", 11),
    ("DuelTriadSourceMaterialTests", 19),
    ("DuelTriadMetalRendererTests", 5),
    ("DuelTriadSourceAudioBindingTests", 22),
    ("DuelBoundedGzipTests", 5),
)
# The three old resource-specific checks intentionally are not selected: they
# assert the old catalog identity. The new exact release has its own native tests.
REAL_SOURCES = (("DuelTriadInstalledSourceTests", 5),)
EXPECTED_COUNT = sum(count for _, count in SYNTHETIC_SOURCES + REAL_SOURCES)
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")

CAPTURE_SELECTOR = "SiteTests/DuelTriadInstalledSourceTests/testInstalledWorldRendersOriginalSkillsAndStopsWithoutAdvancingOnRedraw"
EXPECTED_ATTACHMENTS = {
    "native-scenekit-metal-formats": {
        "selector": "SiteTests/DuelTriadMetalRendererTests/testControlledSurfaceUsesPublicFormatsAndCannotDrawAfterPauseOrShutdown", "kind": "data"},
    "sun-source-capture-report": {"selector": CAPTURE_SELECTOR, "kind": "data"},
    **{label: {"selector": CAPTURE_SELECTOR, "kind": "image"} for label in (
        "sun-source-idle", "sun-source-wave-1", "sun-source-wave-2", "sun-source-wave-3",
        "sun-source-roots", "sun-source-legion", "sun-source-ninjato")},
}



class PhaseFailure(Exception):
    def __init__(self, detail, code=1):
        super().__init__(detail)
        self.code = code if isinstance(code, int) and 1 <= code <= 255 else 1


def work():
    parent = Path(os.environ["RUNNER_TEMP"])
    if not parent.is_absolute() or parent.is_symlink():
        raise ValueError("Expected an absolute runner temporary directory")
    path = parent / "fighter-h17-d19-native"
    if path.is_symlink():
        raise ValueError("Working directory cannot be a symbolic link")
    return path


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def regular(path, maximum):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
        raise ValueError("Expected a bounded regular file")
    return path


def read_json(path, maximum=16 * 1024**2):
    return json.loads(regular(path, maximum).read_text())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def no_resource_keys():
    if any(name in os.environ for name in KEY_NAMES):
        raise ValueError("Resource keys are restricted to the staging step")


def selected_inventory(root=ROOT):
    """Produce method selectors, never class wildcards or caller-chosen tests."""
    rows, hashes = [], {}

    def declared(filename, klass):
        relative = "Tests/SiteTests/" + filename
        path = regular(root / relative, 512 * 1024)
        source = path.read_text()
        if not re.search(r"\b(?:class|extension)\s+" + re.escape(klass) + r"\b", source):
            raise ValueError("Missing selected class")
        methods = re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M)
        if not methods or len(methods) != len(set(methods)):
            raise ValueError("Empty or duplicated method declarations")
        hashes[relative] = digest(path)
        return relative, methods

    for klass, count in SYNTHETIC_SOURCES + REAL_SOURCES:
        relative, methods = declared(klass + ".swift", klass)
        if len(methods) != count:
            raise ValueError("Synthetic method count changed")
        rows.extend({"identifier": "SiteTests/" + klass + "/" + method,
                     "sourceFile": relative, "scenarioType": "authenticated source release" if (klass, count) in REAL_SOURCES else "synthetic fixture contract"}
                    for method in methods)
    if len(rows) != EXPECTED_COUNT or len({r["identifier"] for r in rows}) != EXPECTED_COUNT:
        raise ValueError("Unexpected selected method inventory")
    return rows, hashes


def tree_entries(root=ROOT):
    output = subprocess.check_output(["git", "ls-tree", "HEAD", *REVIEWED_ENTRIES], cwd=root, text=True)
    return {line.split("\t", 1)[1]: line.split("\t", 1)[0].split()[2]
            for line in output.splitlines()}


def validate_event(environment, event, actual_sha):
    expected = environment.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[a-f0-9]{40}", expected) or actual_sha != expected:
        raise ValueError("Checkout must match the triggering commit")
    checks = (
        environment.get("GITHUB_REPOSITORY") == REPOSITORY,
        environment.get("GITHUB_REF") == BRANCH,
        environment.get("GITHUB_EVENT_NAME") == "push",
        environment.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH,
        environment.get("GITHUB_RUN_ATTEMPT") == "1",
        event.get("ref") == BRANCH,
        event.get("head_commit", {}).get("id") == expected,
        event.get("head_commit", {}).get("message") == COMMIT_MESSAGE,
    )
    if not all(checks):
        raise ValueError("Unexpected branch, workflow, event, message or repeated attempt")


def verify_identity():
    value = read_json(work() / "identity.json")
    rows, hashes = selected_inventory()
    if (value.get("sourceSha") != os.environ["GITHUB_SHA"] or value.get("ref") != BRANCH or
            value.get("runId") != os.environ["GITHUB_RUN_ID"] or
            value.get("attempt") != os.environ["GITHUB_RUN_ATTEMPT"] or
            value.get("expectedNativeMethods") != EXPECTED_COUNT or value.get("selectors") != rows):
        raise ValueError("Prepared native validation identity changed")
    if any(value["selectedSourceSHA256"].get(path) != sha for path, sha in hashes.items()):
        raise ValueError("Selected test source changed after preparation")
    return value


def timing(label, started, code):
    path = work() / "timings.json"
    records = read_json(path) if path.exists() else {}
    records[label] = {"durationSeconds": round(time.monotonic() - started, 3), "exitCode": code}
    write_json(path, records)


def run_logged(command, label, timeout, check=True, output_name=None):
    """Keep command output private; kill the owned process group on timeout."""
    started, code = time.monotonic(), None
    try:
        with (work() / (output_name or label + ".log")).open("w") as output, \
                (work() / (label + "-stderr.log")).open("w") as errors:
            process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=errors,
                                       start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
                code = 124
    finally:
        timing(label, started, code)
    if check and code:
        raise PhaseFailure(label + " failed; see encrypted command output", code)
    return code


def recipient_digest(data):
    if not data.startswith(b"-----BEGIN PUBLIC KEY-----\n") or b"PRIVATE KEY" in data:
        raise ValueError("Only a public recipient may be committed")
    result = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=20)
    return hashlib.sha256(result.stdout).hexdigest()


def prepare():
    no_resource_keys()
    if (not re.fullmatch(r"[a-f0-9]{40}", REVIEWED_SOURCE) or
            any(not re.fullmatch(r"[a-f0-9]{40}", pin) for pin in REVIEWED_ENTRIES.values()) or
            not re.fullmatch(r"[a-f0-9]{64}", RELEASE_MANIFEST_SHA256) or not REAL_SOURCES):
        raise ValueError("Source, private manifest and real native inventory require final reviewed pins")
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    event = read_json(Path(os.environ["GITHUB_EVENT_PATH"]))
    validate_event(os.environ, event, actual)
    if tree_entries() != REVIEWED_ENTRIES:
        raise ValueError("App, core, tests or build inputs differ from the reviewed source trees")
    if subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).strip():
        raise ValueError("Checkout contains tracked modifications before preparation")
    for relative in ("App/Resources/FighterPrivate", "App/Resources/arena-original-resources.arenapack"):
        path = ROOT / relative
        if path.exists() or path.is_symlink():
            raise ValueError("Private runtime resources must be staged only by this run")
    if recipient_digest(regular(RECIPIENT, 16_384).read_bytes()) != RECIPIENT_SPKI_SHA256:
        raise ValueError("Evidence public recipient differs from its reviewed pin")
    for relative, expected in BASE_MANIFEST_PINS.items():
        if digest(regular(ROOT / relative, 2 * 1024**2)) != expected:
            raise ValueError("An established resource manifest differs from its reviewed pin")
    release = release_manifest()
    rows, hashes = selected_inventory()
    for relative in (*MANIFESTS, RELEASE_MANIFEST, "project.yml", WORKFLOW,
                     ".github/scripts/fighter_h17_d19_native.py", ".github/scripts/fighter_private_model.py",
                     ".github/scripts/fighter_sf3_assets.py", ".github/scripts/fighter_sf3_distinct.py",
                     ".github/scripts/fighter_presentation_assets.py", ".github/scripts/fighter_source_trails.py",
                     ".github/scripts/build_identity.py"):
        hashes[relative] = digest(regular(ROOT / relative, 2 * 1024**2))
    work().mkdir(mode=0o700, exist_ok=False)
    write_json(work() / "identity.json", {
        "sourceSha": actual, "reviewedLocalSourceSha": REVIEWED_SOURCE, "reviewedEntries": REVIEWED_ENTRIES,
        "sourceMapping": "Exact reviewed tree/blob entries; the remote commit object may differ",
        "ref": BRANCH, "runId": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "workflowSource": WORKFLOW, "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "expectedNativeMethods": EXPECTED_COUNT, "syntheticNativeMethods": sum(n for _, n in SYNTHETIC_SOURCES),
        "sourceReleaseMethods": sum(n for _, n in REAL_SOURCES),
        "selectors": rows, "selectedSourceSHA256": hashes, "resourceManifestReferences": MANIFESTS,
        "privateManifestSHA256": RELEASE_MANIFEST_SHA256, "assetReleaseSHA256": release["releaseSHA256"],
        "recipientSPKISHA256": RECIPIENT_SPKI_SHA256, "wrappedKeyEncoding": "raw-32",
        "keyWrapping": "RSA-OAEP-SHA256; same fresh evidence key to existing and current recipients",
        "limitations": ["Native synthetic contracts and recovered H17 resource acceptance",
                        "D19 exclusive model, VFX and audio remain unavailable in the original source recovery",
                        "Simulator evidence; physical-device and audible/visual original parity remain unverified",
                        "No SwiftPM rerun, second host build, UI runner, signing, app upload or TestFlight action"],
    })
    print(f"Pinned reviewed source content, private release and {EXPECTED_COUNT} exact native methods.")


def tools():
    no_resource_keys()
    verify_identity()
    xcode = "/Applications/Xcode_26.6.app"
    if not Path(xcode).is_dir():
        raise ValueError("The installed Xcode 26.6 image is required")
    run_logged(["sudo", "xcode-select", "-s", xcode], "select-xcode", 60)
    run_logged(["xcodebuild", "-version"], "xcode-version", 60, output_name="xcode-version.txt")
    if "Xcode 26.6" not in (work() / "xcode-version.txt").read_text().splitlines():
        raise ValueError("Selected Xcode version mismatch")
    run_logged(["swift", "--version"], "swift-version", 60, output_name="swift-version.txt")
    run_logged(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], "sdk-version", 60,
               output_name="sdk-version.txt")
    if not shutil.which("xcodegen"):
        run_logged(["brew", "install", "xcodegen"], "install-xcodegen", 240)
    if not any(Path(p).is_file() for p in ("/opt/homebrew/opt/openssl@3/bin/openssl",
                                         "/usr/local/opt/openssl@3/bin/openssl")):
        run_logged(["brew", "install", "openssl@3"], "install-openssl", 240)
    print("Selected installed Xcode 26.6 and simulator tools.")


def resource_records():
    rows = []
    for relative in MANIFESTS:
        manifest = read_json(ROOT / relative, 2 * 1024**2)
        for item in manifest.get("assets", manifest.get("files", [])):
            name, size, sha = item["file"], item["bytes"], item["sha256"]
            if (not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in (".", "..") or
                    type(size) is not int or not 0 < size <= 32 * 1024**2 or
                    not re.fullmatch(r"[a-f0-9]{64}", sha)):
                raise ValueError("Invalid pinned resource receipt")
            rows.append({"file": name, "bytes": size, "sha256": sha, "manifest": relative})
    if len(rows) != 73 or len({r["file"] for r in rows}) != 73:
        raise ValueError("Expected exactly the existing 73 resource receipts")
    return rows


def audit_resources(base, bundled):
    rows, valid = resource_records(), True
    if base.is_symlink() or not base.is_dir():
        raise ValueError("Expected staged resources or a built application")
    if not bundled and {p.name for p in base.iterdir()} != {r["file"] for r in rows}:
        raise ValueError("Staging produced an unexpected resource set")
    for row in rows:
        matches = list(base.rglob(row["file"])) if bundled else [base / row["file"]]
        row["result"] = "failed"
        if len(matches) == 1:
            try:
                path = regular(matches[0], 32 * 1024**2)
                row["actualBytes"], row["actualSHA256"] = path.stat().st_size, digest(path)
                if (row["actualBytes"], row["actualSHA256"]) == (row["bytes"], row["sha256"]):
                    row["result"] = "verified"
            except (OSError, ValueError):
                pass
        valid = valid and row["result"] == "verified"
    write_json(work() / ("compiled-resources.json" if bundled else "staged-resources.json"), rows)
    if not valid:
        raise ValueError("Existing resource bytes or hashes changed; details retained privately")




def validate_release_manifest(value):
    required = {"version", "purpose", "algorithm", "aad", "keyEncoding", "cipherLayout", "cipherBytes",
                "cipherSHA256", "clearZIPBytes", "clearZIPSHA256", "shards", "files", "replacements", "releaseSHA256"}
    if not isinstance(value, dict) or set(value) != required:
        raise ValueError("Unknown private release manifest fields")
    expected = {"version": 1, "purpose": "h17-d19", "algorithm": "AES-256-GCM",
                "aad": "fighter-h17-d19-v1", "keyEncoding": "base64-32",
                "cipherLayout": "nonce12-ciphertext-tag16"}
    if type(value["version"]) is not int or any(value[k] != v for k, v in expected.items()):
        raise ValueError("Unknown private release encryption contract")
    for prefix in ("cipher", "clearZIP"):
        size, sha = value[prefix + "Bytes"], value[prefix + "SHA256"]
        if (type(size) is not int or not 0 < size <= 128 * 1024**2 or
                not isinstance(sha, str) or not re.fullmatch(r"[a-f0-9]{64}", sha)):
            raise ValueError("Invalid private archive bound or digest")
    if value["cipherBytes"] != value["clearZIPBytes"] + 28:
        raise ValueError("GCM ciphertext must contain exactly the nonce, plaintext-length ciphertext and tag")
    shards = value["shards"]
    if not isinstance(shards, list) or not 1 <= len(shards) <= 128:
        raise ValueError("Invalid private ciphertext shard count")
    for index, shard in enumerate(shards):
        if (not isinstance(shard, dict) or set(shard) != {"file", "encoding", "bytes", "sha256"} or
                shard["file"] != f"assets.part{index:03d}.enc" or shard["encoding"] not in ("binary", "base64") or
                type(shard["bytes"]) is not int or not 0 < shard["bytes"] <= 1_398_104 or
                not isinstance(shard["sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", shard["sha256"])):
            raise ValueError("Invalid ordered ciphertext shard receipt")
    rows = value["files"]
    if not isinstance(rows, list) or not 1 <= len(rows) <= 512:
        raise ValueError("Invalid private release file inventory")
    names, total = [], 0
    for item in rows:
        if not isinstance(item, dict) or set(item) != {"file", "bytes", "sha256"}:
            raise ValueError("Unknown resource receipt fields")
        name, size, sha = item["file"], item["bytes"], item["sha256"]
        if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", name) or ".." in name or
                not name.endswith((".glb", ".json", ".json.gz", ".png", ".wav", ".metal", ".texture")) or
                type(size) is not int or not 0 < size <= 128_000_000 or
                not isinstance(sha, str) or not re.fullmatch(r"[a-f0-9]{64}", sha)):
            raise ValueError("Invalid private release file receipt")
        names.append(name); total += size
    if (names != sorted(set(names)) or total > 160 * 1024**2 or "SF3_FighterRelease.json" not in names or
            value["replacements"] != ["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"] or
            not {"Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"}.issubset(names)):
        raise ValueError("Private file order, bound, release or explicit replacements changed")
    release = next(r for r in rows if r["file"] == "SF3_FighterRelease.json")
    if release["sha256"] != value["releaseSHA256"]:
        raise ValueError("Release file and signed-build pin disagree")
    return value


def release_manifest():
    path = regular(ROOT / RELEASE_MANIFEST, 2 * 1024**2)
    if digest(path) != RELEASE_MANIFEST_SHA256:
        raise ValueError("Private release manifest differs from its independent pin")
    return validate_release_manifest(read_json(path))


def assemble_cipher(manifest, directory, destination):
    """Hash the stored shard bytes before strict base64 decoding or assembly."""
    total, checksum = 0, hashlib.sha256()
    with destination.open("xb") as output:
        for index, row in enumerate(manifest["shards"]):
            path = regular(directory / row["file"], 1_398_104)
            raw = path.read_bytes()
            if len(raw) != row["bytes"] or hashlib.sha256(raw).hexdigest() != row["sha256"]:
                raise ValueError("A private ciphertext shard differs from its pin")
            if row["encoding"] == "base64":
                try: decoded = base64.b64decode(raw, validate=True)
                except binascii.Error: raise ValueError("Malformed base64 ciphertext shard") from None
                if base64.b64encode(decoded) != raw:
                    raise ValueError("Noncanonical base64 ciphertext shard")
            else: decoded = raw
            if (not 0 < len(decoded) <= 1024**2 or
                    (index < len(manifest["shards"]) - 1 and len(decoded) != 1024**2)):
                raise ValueError("A private shard violates its one-megabyte layout")
            total += len(decoded)
            if total > manifest["cipherBytes"]: raise ValueError("Ciphertext exceeds its authenticated bound")
            checksum.update(decoded); output.write(decoded)
    if total != manifest["cipherBytes"] or checksum.hexdigest() != manifest["cipherSHA256"]:
        raise ValueError("Assembled private ciphertext identity mismatch")


GCM_SWIFT = r"""import Foundation
import CryptoKit
import Darwin
// Apple CryptoKit: nonce12 || ciphertext || tag16; authenticate the fixed AAD.
do {
    guard CommandLine.arguments.count == 3,
          let encoded = ProcessInfo.processInfo.environment["FIGHTER_H17_D19_KEY"],
          let key = Data(base64Encoded: encoded), key.count == 32,
          key.base64EncodedString() == encoded else { throw NSError(domain: "PrivateReleaseKey", code: 1) }
    let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard input.count > 28, input.count <= 134217728 else { throw NSError(domain: "PrivateReleaseEnvelope", code: 1) }
    let nonce = try AES.GCM.Nonce(data: input.prefix(12))
    let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: input.dropFirst(12).dropLast(16), tag: input.suffix(16))
    let clear = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data("fighter-h17-d19-v1".utf8))
    try clear.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .withoutOverwriting)
} catch {
    FileHandle.standardError.write(Data("Private release authentication or output failed.\n".utf8))
    exit(1)
}
"""


def overlay_zip(clear, manifest, destination):
    """Validate every authenticated ZIP entry before any baseline replacement."""
    if (len(clear) != manifest["clearZIPBytes"] or
            hashlib.sha256(clear).hexdigest() != manifest["clearZIPSHA256"]):
        raise ValueError("Private archive plaintext identity mismatch")
    records = {r["file"]: r for r in manifest["files"]}
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        entries = archive.infolist()
        if len(entries) != len(records) or len({i.filename for i in entries}) != len(entries):
            raise ValueError("Extra, missing or duplicate private ZIP entry")
        for entry in entries:
            kind = stat.S_IFMT(entry.external_attr >> 16)
            row = records.get(entry.filename)
            if (row is None or entry.is_dir() or kind not in (0, stat.S_IFREG) or entry.flag_bits & 1 or
                    entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED) or
                    entry.file_size != row["bytes"]):
                raise ValueError("Private ZIP entry is outside the pinned regular-file inventory")
        destination.mkdir(mode=0o700, exist_ok=False)
        for entry in entries:
            row = records[entry.filename]
            with archive.open(entry) as source:
                raw = source.read(row["bytes"] + 1)
            if len(raw) != row["bytes"] or hashlib.sha256(raw).hexdigest() != row["sha256"]:
                raise ValueError("Private ZIP member identity mismatch")
            target = destination / entry.filename
            with target.open("xb") as output: output.write(raw)


def target_records():
    base = resource_records()
    manifest = release_manifest()
    old = {row["file"]: row for row in base}
    overlay = {row["file"]: dict(row, manifest=RELEASE_MANIFEST) for row in manifest["files"]}
    if set(old) & set(overlay) != set(manifest["replacements"]):
        raise ValueError("A baseline replacement is missing or was not explicitly reviewed")
    old.update(overlay)
    return sorted(old.values(), key=lambda row: row["file"])


def audit_target_resources(base, bundled):
    rows, valid = target_records(), True
    if base.is_symlink() or not base.is_dir():
        raise ValueError("Expected staged resources or a built application")
    if not bundled and {p.name for p in base.iterdir()} != {r["file"] for r in rows}:
        raise ValueError("Unexpected staged target resource set")
    for row in rows:
        matches = list(base.rglob(row["file"])) if bundled else [base / row["file"]]
        row["result"] = "failed"
        if len(matches) == 1:
            try:
                path = regular(matches[0], 128_000_000)
                row["actualBytes"], row["actualSHA256"] = path.stat().st_size, digest(path)
                if (row["actualBytes"], row["actualSHA256"]) == (row["bytes"], row["sha256"]): row["result"] = "verified"
            except (OSError, ValueError): pass
        valid = valid and row["result"] == "verified"
    write_json(work() / ("compiled-target-resources.json" if bundled else "staged-target-resources.json"), rows)
    if not valid:
        raise ValueError("A target resource is missing, duplicated or byte-modified")



def stage():
    verify_identity()
    key = os.environ.get("FIGHTER_H17_D19_KEY", "")
    try: decoded = base64.b64decode(key, validate=True)
    except (ValueError, binascii.Error): raise ValueError("The private release key is missing or malformed") from None
    if len(decoded) != 32 or base64.b64encode(decoded).decode() != key:
        raise ValueError("The private release key must be canonical base64 of 32 bytes")
    decoded = b""
    commands = (("fighter_sf3_assets.py", [], "stage-scenery", 180),
                ("fighter_sf3_distinct.py", [], "stage-distinct", 180),
                ("fighter_presentation_assets.py", ["stage"], "stage-presentation", 60),
                ("fighter_source_trails.py", ["stage"], "stage-trails", 60))
    for filename, arguments, label, timeout in commands:
        run_logged([sys.executable, ".github/scripts/" + filename, *arguments], label, timeout)
    baseline = ROOT / "App/Resources/FighterPrivate"
    audit_resources(baseline, bundled=False)
    manifest = release_manifest()
    cipher = work() / "private-release.enc"
    clear_path = work() / "private-release.zip"
    script = work() / "private-release-decrypt.swift"
    overlay = work() / "verified-overlay"
    clear = b""
    try:
        assemble_cipher(manifest, (ROOT / RELEASE_MANIFEST).parent, cipher)
        script.write_text(GCM_SWIFT)
        # This small CryptoKit staging tool is not another app/host build and
        # needs no package download, pip dependency or source encryption key file.
        run_logged(["swift", str(script), str(cipher), str(clear_path)], "release-authentication", 180)
        clear = regular(clear_path, 128 * 1024**2).read_bytes()
        overlay_zip(clear, manifest, overlay)
        target_records()  # All baseline collisions must be reviewed before replacement.
        for row in manifest["files"]:
            target = baseline / row["file"]
            if target.is_symlink(): raise ValueError("Target resource cannot be a symbolic link")
            os.replace(overlay / row["file"] , target)
    finally:
        clear = b""
        for path in (cipher, clear_path, script): path.unlink(missing_ok=True)
        shutil.rmtree(overlay, ignore_errors=True)
    audit_target_resources(baseline, bundled=False)
    print("Authenticated the 73 baseline files and the independently pinned AES-GCM source release overlay.")


def test_targets(data):
    if "TestConfigurations" in data:
        return [t for c in data["TestConfigurations"] for t in c.get("TestTargets", [])]
    return [dict(v, BlueprintName=k) for k, v in data.items()
            if isinstance(v, dict) and k != "__xctestrun_metadata__"]


def build():
    no_resource_keys()
    verify_identity()
    release = release_manifest()
    project = ROOT / "project.yml"
    source, original = project.read_text(), digest(project)
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    if source.count(needle) != 1: raise ValueError("Ambiguous host test scheme")
    project.write_text(source.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true'))
    write_json(work() / "compiled-project.json", {
        "originalProjectSHA256": original, "compiledProjectSHA256": digest(project),
        "onlyProjectConfigurationChange": "SiteTests inherits the existing -demo host launch path",
        "configuration": "Debug", "signingAllowed": False, "assetReleaseSHA256": release["releaseSHA256"],
    })
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate"], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
                "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY=", "FIGHTER_ASSET_RELEASE_SHA256=" + release["releaseSHA256"]], "native-build", 1200)
    products = work() / "derived/Build/Products"
    runs = list(products.glob("*.xctestrun"))
    if len(runs) != 1: raise ValueError("Ambiguous xctestrun output")
    targets = test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    if (len(targets) != 1 or targets[0].get("BlueprintName") != "SiteTests" or
            "-demo" not in targets[0].get("CommandLineArguments", []) or
            targets[0].get("IsUITestBundle", False) or targets[0].get("SkipTestIdentifiers")):
        raise ValueError("The compiled test plan must contain only the demo SiteTests host")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    audit_target_resources(app, bundled=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("FighterAssetReleaseSHA256") != release["releaseSHA256"]:
        raise ValueError("Built application does not contain the independently pinned release")
    if any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()):
        raise ValueError("Encrypted packs or key files must not enter the application")
    (work() / "build-ok.txt").write_text("One unsigned demo build; every target resource and release pin verified\n")
    print("Built the unsigned SiteTests host once and verified all target compiled resource identities.")


def simulator():
    no_resource_keys()
    verify_identity()
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], text=True, timeout=60))
    runtimes = {r["identifier"]: r for r in catalog["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]}
    choices = [(tuple(map(int, re.findall(r"\d+", runtimes[r]["version"]))), r, d["deviceTypeIdentifier"])
               for r, devices in catalog["devices"].items() if r in runtimes for d in devices
               if d.get("isAvailable") and d.get("deviceTypeIdentifier", "").endswith(".iPhone-17-Pro-Max")]
    if not choices:
        raise ValueError("An installed iPhone 17 Pro Max runtime is required; no download or fallback")
    _, runtime, dtype = max(choices)
    name = "Fighter H17 D19 " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
    udid = subprocess.check_output(["xcrun", "simctl", "create", name, dtype, runtime], text=True, timeout=60).strip()
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
        raise ValueError("Unexpected simulator identifier")
    write_json(work() / "simulator.json", {"udid": udid, "name": name, "runtime": runtime,
               "type": dtype, "osVersion": runtimes[runtime]["version"], "physicalDevice": False})
    run_logged(["xcrun", "simctl", "boot", udid], "simulator-boot", 120)
    run_logged(["xcrun", "simctl", "bootstatus", udid, "-b"], "simulator-ready", 480)
    print("Prepared one installed iPhone 17 Pro Max simulator.")


def verify_results(summary, data, expected):
    if len(expected) != EXPECTED_COUNT or len(set(expected)) != EXPECTED_COUNT:
        raise ValueError("Invalid expected method set")
    for key, value in (("totalTestCount", EXPECTED_COUNT), ("passedTests", EXPECTED_COUNT),
                       ("failedTests", 0), ("skippedTests", 0)):
        if type(summary.get(key)) is not int or summary[key] != value:
            raise ValueError("Unexpected native summary count: " + key)
    if summary.get("result") != "Passed" or not isinstance(data.get("testNodes"), list):
        raise ValueError("Missing successful native result tree")
    seen = []

    def walk(nodes):
        if not isinstance(nodes, list):
            raise ValueError("Invalid native result children")
        for node in nodes:
            if not isinstance(node, dict):
                raise ValueError("Invalid native result node")
            if node.get("nodeType") == "Test Case":
                raw = node.get("nodeIdentifier")
                if not isinstance(raw, str):
                    raise ValueError("Missing XCTest method identifier")
                normalized = raw.removesuffix("()")
                matches = [s for s in expected if normalized in (s, "/".join(s.split("/")[1:]))]
                if len(matches) != 1 or node.get("result") != "Passed":
                    raise ValueError("Unexpected, skipped or failing native method")
                seen.append(matches[0])
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    if collections.Counter(seen) != collections.Counter(expected):
        raise ValueError("Missing, extra or duplicated native methods")


def test():
    no_resource_keys()
    identity = verify_identity()
    device = read_json(work() / "simulator.json")
    expected = [row["identifier"] for row in identity["selectors"]]
    command = ["xcodebuild", "test-without-building", "-xctestrun", (work() / "xctestrun-path.txt").read_text(),
               "-destination", "id=" + device["udid"], "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(work() / "selected.xcresult")]
    command.extend("-only-testing:" + selector for selector in expected)
    code = run_logged(command, "selected-native", 720, check=False)
    result = {"exitCode": code, "selectedCount": EXPECTED_COUNT, "iterations": 1, "exports": {}}
    write_json(work() / "native-process.json", result)
    # Export both diagnostics even after test failure. An exporter must never
    # replace the actual xcodebuild failure with a misleading success.
    if (work() / "selected.xcresult/Info.plist").is_file():
        for kind in ("summary", "tests"):
            try:
                result["exports"][kind] = run_logged(
                    ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(work() / "selected.xcresult")],
                    "result-" + kind, 60, check=False, output_name=kind + ".json")
            except Exception as error:
                result["exports"][kind] = type(error).__name__
    write_json(work() / "native-process.json", result)
    if code:
        raise PhaseFailure("Native test invocation failed; diagnostics retained privately", code)
    if result["exports"] != {"summary": 0, "tests": 0}:
        raise ValueError("A successful process without complete native results is not acceptance")
    verify_results(read_json(work() / "summary.json"), read_json(work() / "tests.json"), expected)
    (work() / "native-ok.txt").write_text(f"{EXPECTED_COUNT} passed; 0 failed; 0 skipped; every exact method once\n")
    print(f"Native XCTest: {EXPECTED_COUNT} passed, 0 failed, 0 skipped; exact methods, one iteration.")



def attachment_inventory(root, expected_device, expected_selectors):
    """Only exact XCTest-owned labels on this run's simulator satisfy coverage."""
    paths = sorted(root.rglob("*"))
    if any(path.is_symlink() for path in paths): raise ValueError("Symlink in exported evidence")
    files = [path for path in paths if path.is_file()]
    if not 1 <= len(files) <= 160: raise ValueError("Attachment count exceeds its bound")
    for path in files: regular(path, 12 * 1024**2)
    manifest_path = root / "manifest.json"
    manifest = read_json(manifest_path)
    if not isinstance(manifest, list): raise ValueError("Unexpected xcresult attachment manifest")
    methods, names, labels, entries = set(), set(), set(), []
    for group in manifest:
        if not isinstance(group, dict) or not isinstance(group.get("attachments"), list):
            raise ValueError("Invalid attachment method group")
        identifier = group.get("testIdentifier", "").removesuffix("()")
        matches = [s for s in expected_selectors if identifier in (s, "/".join(s.split("/")[1:]))]
        if len(matches) != 1 or matches[0] in methods: raise ValueError("Unexpected or repeated attachment method")
        selector = matches[0]; methods.add(selector)
        for item in group["attachments"]:
            name = item.get("exportedFileName", "")
            if not isinstance(name, str) or not name or Path(name).name != name or "\\" in name or ".." in name:
                raise ValueError("Unsafe exported attachment name")
            path = root / name
            if path not in files or name in names: raise ValueError("Missing or repeated attachment file")
            names.add(name)
            human, suffix = item.get("suggestedHumanReadableName", ""), path.suffix.lower()
            matches = [label for label in EXPECTED_ATTACHMENTS if re.fullmatch(
                re.escape(label) + r"_[0-9]+_[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}" + re.escape(suffix), human)]
            if len(matches) != 1 or matches[0] in labels: raise ValueError("Unexpected or repeated exact attachment label")
            label = matches[0]; labels.add(label); expected = EXPECTED_ATTACHMENTS[label]
            if (expected["selector"] != selector or item.get("deviceId") != expected_device["udid"] or
                    item.get("deviceName") != expected_device["name"]):
                raise ValueError("Attachment method or simulator identity mismatch")
            if expected["kind"] == "image":
                if suffix != ".png" or path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                    raise ValueError("Expected a genuine PNG capture")
            else:
                if suffix not in (".json", ".txt"): raise ValueError("Expected JSON capture/format data")
                json.loads(path.read_text())
            entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path),
                            "label": label, "selector": selector, "kind": expected["kind"]})
    if labels != set(EXPECTED_ATTACHMENTS): raise ValueError("Missing required original-source captures or data")
    if names | {"manifest.json"} != {str(p.relative_to(root)) for p in files}:
        raise ValueError("Unreferenced attachment payload")
    return {"completeExpectedLabels": True, "exactMethodOwnership": True,
            "imageCount": sum(v["kind"] == "image" for v in EXPECTED_ATTACHMENTS.values()),
            "files": entries}


def export():
    no_resource_keys()
    identity = verify_identity()
    bundle = work() / "selected.xcresult"
    if not (bundle / "Info.plist").is_file(): raise ValueError("No finalized native results to export")
    destination = work() / "attachments"
    destination.mkdir(mode=0o700, exist_ok=False)
    run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                "--output-path", str(destination)], "export-attachments", 180)
    result = attachment_inventory(destination, read_json(work() / "simulator.json"),
                                  [row["identifier"] for row in identity["selectors"]])
    write_json(work() / "attachment-inventory.json", result)
    (work() / "attachments-ok.txt").write_text("Every exact source capture and data attachment verified\n")
    print("Exported seven original-source images and two data attachments with exact XCTest and simulator ownership.")


def bounded_attachment_files(directory):
    """Seal bounded partial media after failures; never claim it passed coverage."""
    if not directory.exists(): return []
    if directory.is_symlink() or not directory.is_dir(): raise ValueError("Invalid evidence directory")
    files, total = [], 0
    for path in sorted(directory.rglob("*")):
        if path.is_symlink(): raise ValueError("Symlink in partial evidence")
        if path.is_dir(): continue
        if path.suffix.lower() not in (".png", ".json", ".txt"):
            continue  # Unknown/binary diagnostic attachments do not enter this narrow artifact.
        regular(path, 12 * 1024**2)
        total += path.stat().st_size
        if total > 128 * 1024**2 or len(files) >= 160: raise ValueError("Partial attachments exceed evidence bounds")
        if path.suffix.lower() == ".png" and path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError("Malformed partial image")
        files.append(path)
    return files


def public_summary():
    identity = read_json(work() / "identity.json")
    result = {"sourceSha": identity["sourceSha"], "reviewedLocalSourceSha": REVIEWED_SOURCE,
              "runId": identity["runId"], "attempt": identity["attempt"], "expectedNativeMethods": EXPECTED_COUNT,
              "syntheticMethods": sum(n for _, n in SYNTHETIC_SOURCES), "sourceReleaseMethods": sum(n for _, n in REAL_SOURCES),
              "buildAndCompiledResourcesVerified": (work() / "build-ok.txt").is_file(),
              "nativeExactSetPassed": (work() / "native-ok.txt").is_file(),
              "exactSourceCapturesVerified": (work() / "attachments-ok.txt").is_file(),
              "physicalDeviceAcceptance": "NOT VERIFIED", "productionPanguAssetsActivated": False, "sourceH17ReleaseBuilt": (work() / "build-ok.txt").is_file(),
              "originalVisualAudioParity": "NOT VERIFIED"}
    if (work() / "native-process.json").exists():
        native = read_json(work() / "native-process.json")
        result["nativeProcess"] = {key: native.get(key) for key in ("exitCode", "selectedCount", "iterations")}
    if (work() / "timings.json").exists():
        result["timings"] = read_json(work() / "timings.json")
    if (work() / "simulator.json").exists():
        device = read_json(work() / "simulator.json")
        result["simulator"] = {key: device[key] for key in ("type", "runtime", "osVersion", "physicalDevice")}
    return result


def seal():
    no_resource_keys()
    verify_identity()
    # Reuse only the established envelope and public-key wrapping functions.
    # The old visual helper's scope/branch checks and operations remain intact.
    import fighter_private_model as envelope
    from fighter_visual_acceptance import EXISTING_RECIPIENT, wrap_key
    public_data = regular(RECIPIENT, 16_384).read_bytes()
    if recipient_digest(public_data) != RECIPIENT_SPKI_SHA256:
        raise ValueError("Evidence public recipient changed")
    started = time.monotonic()
    published = work() / "published"
    published.mkdir(mode=0o700, exist_ok=False)
    archive = work() / "private-new-evidence.zip"
    try:
        # Only bounded root text and explicitly exported PNG/data are included.
        # Runtime resources, application products and raw xcresult are never traversed.
        write_json(work() / "public-summary.json", public_summary())
        entries, total = [], 0
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_STORED) as output:
            for path in sorted(work().iterdir()):
                if path.suffix not in (".log", ".json", ".txt"):
                    continue
                if path.is_file() and path.stat().st_size == 0:
                    continue
                regular(path, 128 * 1024**2)
                size = path.stat().st_size
                # Preserve the diagnostic tail, including compiler errors and
                # XCTest failure bodies, even when the preceding build failed.
                with path.open("rb") as stream:
                    stream.seek(max(0, size - 2 * 1024**2))
                    data = stream.read(2 * 1024**2)
                total += len(data)
                if total > 24 * 1024**2 or len(entries) >= 96:
                    raise ValueError("Text evidence exceeds the bounded archive")
                name = "metadata/" + path.name
                output.writestr(name, data)
                entries.append({"file": name, "sourceBytes": size, "archivedBytes": len(data),
                                "tailOnly": len(data) != size, "sha256": hashlib.sha256(data).hexdigest()})
            for path in bounded_attachment_files(work() / "attachments"):
                name = "attachments/" + str(path.relative_to(work() / "attachments"))
                output.write(path, name)
                entries.append({"file": name, "sourceBytes": path.stat().st_size,
                                "archivedBytes": path.stat().st_size, "tailOnly": False, "sha256": digest(path)})
            output.writestr("private-evidence-inventory.json", json.dumps(entries, indent=2))
        if not entries or archive.stat().st_size > 153 * 1024**2:
            raise ValueError("Invalid bounded evidence archive")
        key = secrets.token_bytes(32)
        wrap_key(key, EXISTING_RECIPIENT.encode(), published / "fighter-h17-d19-native-evidence.key.enc")
        wrap_key(key, public_data, published / "fighter-h17-d19-native-evidence.session-key.enc")
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / "fighter-h17-d19-native-evidence.enc")
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
        files = sorted(published.glob("*.enc"))
        if len(files) != 3:
            raise ValueError("Incomplete encrypted evidence set")
        (published / "fighter-h17-d19-native-evidence.SHA256SUMS").write_text(
            "".join(digest(path) + "  " + path.name + "\n" for path in files))
        timing("evidence-sealing", started, 0)
        print("Sealed bounded build/test diagnostics and exported source captures for both private recipients.")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive.unlink(missing_ok=True)


def cleanup():
    no_resource_keys()
    verify_identity()
    summary, errors = public_summary(), []
    device_path = work() / "simulator.json"
    try:
        if device_path.exists():
            device = read_json(device_path)
            catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"],
                                                        text=True, timeout=30))
            matches = [d for devices in catalog["devices"].values() for d in devices if d["udid"] == device["udid"]]
            if len(matches) != 1 or matches[0]["name"] != device["name"]:
                raise ValueError("Simulator cleanup ownership mismatch")
            if matches[0]["state"] != "Shutdown":
                run_logged(["xcrun", "simctl", "shutdown", device["udid"]], "simulator-shutdown", 90)
            run_logged(["xcrun", "simctl", "delete", device["udid"]], "simulator-delete", 60)
    except Exception as error:
        errors.append("simulator: " + type(error).__name__)
    # Always clean private products/logs even when simulator cleanup failed.
    for path in [ROOT / "App/Resources/FighterPrivate"] + [p for p in work().iterdir() if p.name != "published"]:
        try:
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        except OSError as error:
            errors.append("plaintext cleanup: " + type(error).__name__)
    summary["cleanupComplete"] = not errors
    summary["cleanupErrors"] = errors
    write_json(work() / "public-summary.json", summary)
    if errors:
        raise PhaseFailure("Owned simulator or plaintext cleanup did not complete")
    print("Removed this run's simulator, staged assets, app products, xcresult and private logs.")


def report():
    no_resource_keys()
    summary = read_json(work() / "public-summary.json")
    print(json.dumps(summary, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write("### H17/D19 native source validation\n\n```json\n" + json.dumps(summary, indent=2) + "\n```\n")
    # The report is also a final gate. A sealed diagnostic artifact is never
    # presented as a successful native acceptance when an earlier step failed.
    if not all(summary.get(key) is True for key in
               ("buildAndCompiledResourcesVerified", "nativeExactSetPassed", "exactSourceCapturesVerified", "cleanupComplete")):
        raise PhaseFailure("Native acceptance did not reach all required gates")


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("inventory", "prepare", "tools", "stage", "build", "simulator",
                                             "test", "export", "seal", "cleanup", "report"))
    operation = parser.parse_args().operation
    if operation == "inventory":
        rows, hashes = selected_inventory()
        print(json.dumps({"count": len(rows), "selectors": rows, "selectedSourceSHA256": hashes}, indent=2))
        raise SystemExit(0)
    try:
        globals()[operation]()
    except Exception as error:
        # No raw exception or compiler/test text enters public Actions logs.
        # seal runs with always() after prepare, including build/test failures.
        if operation not in ("cleanup", "report"):
            try:
                if work().is_dir():
                    write_json(work() / (operation + "-failure.json"), {
                        "phase": operation, "errorType": type(error).__name__, "detail": str(error)[:4000]})
            except (OSError, KeyError, ValueError):
                pass
        print("H17/D19 native phase failed: " + operation + "; diagnostics remain in the encrypted evidence.", file=sys.stderr)
        raise SystemExit(error.code if isinstance(error, PhaseFailure) else 1) from None
