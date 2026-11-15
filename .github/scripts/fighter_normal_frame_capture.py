#!/usr/bin/env python3
"""Follow up one failed normal-window UI method with original PNG orientation.

This independent entry owns source/event/selector/device/evidence gates. Only
SHA-pinned resource/envelope utilities are imported; no old gate or scope is
modified or called. A sidecar is image evidence, never an XCTest pass claim.
"""
from __future__ import annotations
import argparse
import base64
import datetime
import hashlib
import importlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import signal
import stat
import struct
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
SOURCE_BASELINE = "c0da35df68e7bbe7d40fbc83ad122268af48cfc6"
BASELINE_TREE = "2ae0ebe5944414205beedef340bd53813d6383e9"
SCOPE = "normal-production-frame-capture-ui-one"
COMMIT_MESSAGE = "Capture original PNG orientation in the normal frame flow 20261115"
HELPER = ".github/scripts/fighter_normal_frame_capture.py"
CHECKS = ".github/scripts/test_fighter_normal_frame_capture.py"
WORKFLOW = ".github/workflows/fighter-normal-frame-capture.yml"
SWIFT_TEST = "Tests/ArenaFlowTests/DuelNormalFrameCaptureTests.swift"
SWIFT_TEST_SHA = "c241b5d32eeeeeff9902660ffce7532be8db06fc3d9e6e5576c8cdca455b403f"
CLASS_NAME = "DuelNormalFrameCaptureTests"
METHOD_NAME = "testSunPracticeCapturesTwoNormalWindowFrames"
SELECTOR = "ArenaFlowTests/" + CLASS_NAME + "/" + METHOD_NAME
CHECKS_SHA = "6e548743022248cabcc55f1d7e6c564b4dd02759700bb5526f74c22fb381b54a"
WORKFLOW_CANONICAL_SHA = "7867a01a32d791fbaf261bbe5029f5cd8255b06ef18ae8749603943104a665d5"
HELPER_PIN_FIELD = '      EXPECTED_NORMAL_FRAME_CAPTURE_HELPER_SHA256: "'
RETAINED_TREE_SHA = "1f5e0748bedf1c890ab8dc77e1aa7e9ec12355ec8c7877cd16036cb21ae6e5c2"
APP_TREE = "440cbf24a285397d34dc3e9ccf84463230d12664"
WORLD_SOURCE = "App/Views/DuelWorld.swift"
WORLD_SOURCE_SHA = "843637f274d48e2bc7710b71fd3d19aca179acae67082ce7cd746bd125e2cb62"
OLD_UI = "Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift"
OLD_UI_SHA = "d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee"
CO_PUBLISHED_NON_INPUTS = ()
RESOURCE_TOOLS = ".github/scripts/fighter_shared_root_native.py"
RESOURCE_TOOLS_SHA = "945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036"
RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
DELTA_MANIFEST_SHA = "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")
REPORT_SCHEMA = "fighter-normal-frame-capture-v3"
PNG_ORIENTATION_POLICY = "embedded-exif-nonmirrored-display-at-3x-AX; XMP-if-present-must-agree"
FRAME_LABELS = ("normal-sun-practice-ready", "normal-sun-practice-later")
REPORT_FILE = "normal-frame-capture-report.json"
SIDECAR_DIRECTORY = "FighterNormalFrameCapture"
DIAGNOSTIC_LABELS = ("lobby-before-sun-touch", "normal-frame-failure")
ALLOWED_SIDECAR_FILES = frozenset((REPORT_FILE, *(label + ".png" for label in (*FRAME_LABELS, *DIAGNOSTIC_LABELS))))
STEM = "fighter-normal-frame-capture-evidence"
METAL_DIAGNOSTICS = {
    "doublePresent": "Each CAMetalLayerDrawable can only be presented once!",
    "textureAfterPresent": "[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.",
}
RUNTIME_OK = "Complete owned UI invocation source scanned; zero two known drawable diagnostics. Pixels pending.\n"
UI_RUNTIME_OK = RUNTIME_OK
_resource_module = None


class PhaseFailure(Exception):
    def __init__(self, detail, code=1):
        super().__init__(detail)
        self.code = code if type(code) is int and 0 < code < 256 else 1

def require(condition, detail):
    if not condition:
        raise ValueError(detail)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()

def regular(path, maximum):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, "Expected bounded regular file")
    return path

def read_json(path, maximum=16 * 1024**2):
    return json.loads(regular(path, maximum).read_text())

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")

def pinned(relative, expected, maximum=2 * 1024**2):
    require(re.fullmatch(r"[a-f0-9]{64}", expected), "Review pin not finalized: " + relative)
    path = regular(ROOT / relative, maximum)
    require(digest(path) == expected, "Reviewed bytes differ: " + relative)
    return path

def no_resource_keys():
    require(not any(name in os.environ for name in KEY_NAMES), "Resource keys are restricted to staging")

def resource_tools():
    """Load byte-pinned utilities without invoking or altering an old gate."""
    global _resource_module
    pinned(RESOURCE_TOOLS, RESOURCE_TOOLS_SHA)
    require("FIGHTER_SHARED_ROOT_SCOPE" not in os.environ, "An old execution scope cannot enter this independent diagnostic")
    if _resource_module is None:
        sys.path.insert(0, str(ROOT / ".github/scripts"))
        _resource_module = importlib.import_module("fighter_shared_root_native")
    require(Path(_resource_module.__file__).resolve() == (ROOT / RESOURCE_TOOLS).resolve(),
            "Resource tools loaded from another location")
    _resource_module.dependencies()  # Transitive resource/envelope byte pins only.
    require(_resource_module.RELEASE_SHA == RELEASE_SHA and _resource_module.DELTA_PACK_SHA == DELTA_MANIFEST_SHA,
            "Resource revision differs from this diagnostic")
    return _resource_module

def co_published_non_inputs():
    seen, result = set(), []
    for item in CO_PUBLISHED_NON_INPUTS:
        require(isinstance(item, dict) and set(item) == {"path", "sha256", "bytes", "usedByThisExecution"},
                "Co-published non-input review is incomplete")
        path = item["path"]
        require(isinstance(path, str) and path not in seen and path not in (HELPER, CHECKS, WORKFLOW, RESOURCE_TOOLS)
                and re.fullmatch(r"\.github/(?:scripts/[A-Za-z0-9_]+\.py|workflows/[A-Za-z0-9_-]+\.yml)", path)
                and type(item["bytes"]) is int and 0 < item["bytes"] <= 2 * 1024**2
                and re.fullmatch(r"[a-f0-9]{64}", item["sha256"])
                and item["usedByThisExecution"] is False,
                "Only exact bounded reviewed non-inputs may be excluded from retained CI trees")
        seen.add(path); result.append(dict(item))
    return result

def validate_event(environment, event, actual):
    expected = environment.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[a-f0-9]{40}", expected) and actual == expected, "Trigger and checkout differ")
    require(environment.get("GITHUB_REPOSITORY") == REPOSITORY and environment.get("GITHUB_REF") == BRANCH
            and environment.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH
            and environment.get("GITHUB_WORKFLOW_SHA") == expected
            and environment.get("GITHUB_RUN_ATTEMPT") == "1"
            and re.fullmatch(r"[0-9]+", environment.get("GITHUB_RUN_ID", ""))
            and environment.get("GITHUB_EVENT_NAME") == "push", "Unexpected run identity or repeated/dispatch execution")
    require(event.get("repository", {}).get("full_name") == REPOSITORY and event.get("ref") == BRANCH
            and event.get("deleted", False) is False and event.get("head_commit", {}).get("id") == expected
            and event.get("head_commit", {}).get("message") == COMMIT_MESSAGE, "Unreviewed push event")

def once(label):
    with (work() / (label + "-invoked.json")).open("x") as output:
        json.dump({"phase": label, "attempts": 1}, output)

def timing(label, started, code):
    path = work() / "timings.json"
    value = read_json(path) if path.exists() else {}
    value[label] = {"durationSeconds": round(time.monotonic() - started, 3), "exitCode": code}
    write_json(path, value)

def run_logged(command, label, timeout, check=True, output_name=None, key_names=()):
    environment = dict(os.environ)
    require(set(key_names) <= set(KEY_NAMES), "Unreviewed secret forwarding")
    for key in KEY_NAMES:
        if key not in key_names:
            environment.pop(key, None)
    started, code = time.monotonic(), None
    try:
        with (work() / (output_name or label + ".log")).open("w") as output, \
                (work() / (label + "-stderr.log")).open("w") as errors:
            process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output, stderr=errors,
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
        raise PhaseFailure(label + " failed; private diagnostics retained", code)
    return code

def tools():
    no_resource_keys()
    identity()
    xcode = "/Applications/Xcode_26.6.app"
    require(Path(xcode).is_dir(), "Reviewed installed Xcode 26.6 required")
    run_logged(["sudo", "xcode-select", "-s", xcode], "select-xcode", 60)
    run_logged(["xcodebuild", "-version"], "xcode-version", 60, output_name="xcode-version.txt")
    require("Xcode 26.6" in (work() / "xcode-version.txt").read_text().splitlines(), "Xcode version differs")
    run_logged(["swift", "--version"], "swift-version", 60, output_name="swift-version.txt")
    run_logged(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], "sdk-version", 60,
               output_name="sdk-version.txt")
    if not shutil.which("xcodegen"):
        run_logged(["brew", "install", "xcodegen"], "install-xcodegen", 240)
    if not any(Path(p).is_file() for p in ("/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl")):
        run_logged(["brew", "install", "openssl@3"], "install-openssl", 240)
    print("Selected installed Xcode 26.6; no simulator runtime download.")

def audit_resources(directory, rows, bundled=False):
    require(directory.is_dir() and not directory.is_symlink(), "Expected resource directory")
    if not bundled:
        require({p.name for p in directory.iterdir()} == {r["file"] for r in rows}, "Resource closure differs")
    receipt, valid = [], True
    for row in rows:
        matches = list(directory.rglob(row["file"])) if bundled else [directory / row["file"]]
        entry = dict(row, verified=False)
        if len(matches) == 1:
            try:
                path = regular(matches[0], 128_000_000)
                entry["verified"] = path.stat().st_size == row["bytes"] and digest(path) == row["sha256"]
            except (OSError, ValueError):
                pass
        valid = valid and entry["verified"]
        receipt.append(entry)
    write_json(work() / ("compiled-resources.json" if bundled else "staged-resources.json"), receipt)
    require(valid, "A resource is absent, duplicated or byte-modified")

def stage():
    identity()
    once("stage")
    for key in KEY_NAMES[:2]:
        require(re.fullmatch(r"[a-f0-9]{64}", os.environ.get(key, "")), "Missing or malformed resource key: " + key)
    encoded = os.environ.get(KEY_NAMES[2], "")
    try:
        raw_key = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise ValueError("H17/D19 resource key missing or malformed") from None
    require(len(raw_key) == 32 and base64.b64encode(raw_key).decode() == encoded, "Resource key encoding differs")
    raw_key = b""
    shared = resource_tools()
    legacy, base, manifest = shared.manifests()
    rows = shared.final_inventory(base, manifest, legacy.resource_records())
    for filename, arguments, key in (
        ("fighter_sf3_assets.py", [], KEY_NAMES[0]), ("fighter_sf3_distinct.py", [], KEY_NAMES[0]),
        ("fighter_presentation_assets.py", ["stage"], KEY_NAMES[1]),
        ("fighter_source_trails.py", ["stage"], KEY_NAMES[1]),
    ):
        run_logged([sys.executable, ".github/scripts/" + filename, *arguments],
                   "baseline-" + filename.removesuffix(".py"), 180, key_names=(key,))
    destination = ROOT / "App/Resources/FighterPrivate"
    audit_resources(destination, legacy.resource_records())
    cipher, old_clear, delta_clear = [work() / n for n in ("original-overlay.enc", "original-overlay.zip", "delta-clear.zip")]
    script, overlay = work() / "authenticate-resources.swift", work() / "verified-overlay"
    delta_cipher = regular((ROOT / shared.DELTA_PACK).parent / manifest["cipher"]["name"], 8 * 1024**2 + 28)
    require(delta_cipher.stat().st_size == manifest["cipher"]["bytes"] and digest(delta_cipher) == manifest["cipher"]["sha256"],
            "Delta ciphertext pin differs")
    try:
        legacy.assemble_cipher(base, (ROOT / shared.BASE_PACK).parent, cipher)
        script.write_text(shared.GCM_SWIFT)
        run_logged(["swift", str(script), str(cipher), str(old_clear), str(delta_cipher), str(delta_clear)],
                   "authenticate-source-and-delta", 240, key_names=(KEY_NAMES[2],))
        legacy.overlay_zip(regular(old_clear, 128 * 1024**2).read_bytes(), base, overlay)
        delta, payloads = shared.decode_delta(regular(delta_clear, 8 * 1024**2).read_bytes(), manifest)
        shared.reconstruct_delta(delta, payloads, overlay, base)
        for path in sorted(overlay.iterdir()):
            require(not (destination / path.name).is_symlink(), "Unsafe baseline replacement")
            os.replace(path, destination / path.name)
    finally:
        for path in (cipher, old_clear, delta_clear, script):
            path.unlink(missing_ok=True)
        shutil.rmtree(overlay, ignore_errors=True)
    audit_resources(destination, rows)
    write_json(work() / "stage-ok.json", {"baselineFiles": 73, "originalOverlayFiles": 295, "deltaPayloadFiles": 13,
        "unchangedOverlayFiles": 289, "finalOverlayFiles": 302, "compiledResourceTarget": 373,
        "assetReleaseSHA256": RELEASE_SHA, "redecodedMedia": False, "downloadedAssets": False, "keyFilesCreated": False})
    print("Authenticated the unchanged 73 + 295 source files and 13-payload delta; final 373 bytes match v2 pins.")

def simulator():
    no_resource_keys()
    identity()
    once("simulator")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], text=True, timeout=60))
    runtimes = {r["identifier"]: r for r in catalog["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]}
    choices = [(tuple(map(int, re.findall(r"\d+", runtimes[r]["version"]))), r, d["deviceTypeIdentifier"])
               for r, devices in catalog["devices"].items() if r in runtimes for d in devices
               if d.get("isAvailable") and d.get("deviceTypeIdentifier", "").endswith(".iPhone-17-Pro-Max")]
    require(choices, "Installed iPhone 17 Pro Max required; no runtime download or fallback")
    _, runtime, dtype = max(choices)
    name = simulator_name()
    udid = subprocess.check_output(["xcrun", "simctl", "create", name, dtype, runtime], text=True, timeout=60).strip()
    require(re.fullmatch(r"[0-9A-Fa-f-]{36}", udid), "Unexpected simulator identifier")
    write_json(work() / "simulator.json", {"udid": udid, "name": name, "runtime": runtime, "type": dtype,
        "osVersion": runtimes[runtime]["version"], "physicalDevice": False})
    run_logged(["xcrun", "simctl", "boot", udid], "simulator-boot", 120)
    run_logged(["xcrun", "simctl", "bootstatus", udid, "-b"], "simulator-ready", 480)
    print("Prepared one owned iPhone 17 Pro Max simulator.")

def verify_runtime_log(path, *, collection_code, device, started, finished, scope="ui"):
    require(scope == "ui", "Only the selected UI runtime scope is allowed")
    require(collection_code == 0 and started.tzinfo is not None and finished.tzinfo is not None and started <= finished,
            "Runtime collection or interval invalid")
    require(device.get("name") == simulator_name() and device.get("physicalDevice") is False
            and re.fullmatch(r"[0-9A-Fa-f-]{36}", device.get("udid", "")), "Runtime simulator identity differs")
    raw = regular(path, 128 * 1024**2).read_bytes()
    events = json.loads(raw)
    require(isinstance(events, list) and events and all(isinstance(row, dict) for row in events),
            "Runtime log is empty or lacks a complete JSON structure")
    low = started.replace(microsecond=0)
    high = finished.replace(microsecond=0) + datetime.timedelta(seconds=1)
    counts, stamps = {name: 0 for name in METAL_DIAGNOSTICS}, []
    for row in events:
        if not str(row.get("processImagePath", "")).endswith("/ShiftReminder.app/ShiftReminder"):
            continue
        message = row.get("eventMessage") or row.get("formatString")
        require(isinstance(message, str) and message, "App runtime entry has no message")
        stamp = datetime.datetime.fromisoformat(str(row.get("timestamp", "")).replace(" ", "T", 1))
        require(stamp.tzinfo is not None and low <= stamp <= high, "Runtime entry lies outside this invocation")
        stamps.append(stamp)
        normalized = " ".join(message.split()).casefold()
        for name, diagnostic in METAL_DIAGNOSTICS.items():
            counts[name] += int(diagnostic.casefold() in normalized)
    require(stamps, "No App runtime entries captured for this invocation")
    return {"collectionExitCode": collection_code, "completeJSONParsed": True, "ownedSimulatorVerified": True,
        "simulatorUDID": device["udid"], "requestedStartUTC": low.isoformat(), "requestedEndUTC": high.isoformat(),
        "invocationScope": scope,
        "coverage": "Full " + scope + " process invocation; complete source scanned before sealing",
        "sourceBytes": len(raw), "sourceSHA256": sha(raw), "entries": len(events), "appEntries": len(stamps),
        "firstAppEntryUTC": min(stamps).isoformat(), "lastAppEntryUTC": max(stamps).isoformat(),
        "knownDiagnosticCounts": counts, "knownDiagnosticCount": sum(counts.values()),
        "knownDiagnosticsAbsent": not any(counts.values()), "sealedTextTailOnly": len(raw) > 2 * 1024**2,
        "pixels": "PENDING", "liveUIValidated": False, "performanceAcceptance": False}

def collect_runtime(started, finished, scope="ui"):
    require(scope == "ui", "Only the selected UI runtime scope is allowed")
    device = read_json(work() / "simulator.json")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True, timeout=30))
    matches = [d for rows in catalog["devices"].values() for d in rows if d.get("udid") == device["udid"]]
    require(len(matches) == 1 and matches[0].get("name") == device["name"], "Runtime device ownership differs")
    low = started.replace(microsecond=0); high = finished.replace(microsecond=0) + datetime.timedelta(seconds=1)
    prefix = "runtime" if scope == "native" else "ui-runtime"
    code = run_logged(["xcrun", "simctl", "spawn", device["udid"], "log", "show", "--start",
        low.strftime("%Y-%m-%d %H:%M:%S%z"), "--end", high.strftime("%Y-%m-%d %H:%M:%S%z"),
        "--style", "json", "--predicate", 'process == "ShiftReminder"'], prefix + "-log", 60, check=False)
    receipt = verify_runtime_log(work() / (prefix + "-log.log"), collection_code=code, device=device,
                                 started=started, finished=finished, scope=scope)
    write_json(work() / (prefix + "-diagnostics.json"), receipt)
    require(receipt["knownDiagnosticsAbsent"], "Known drawable diagnostic occurred; full counts retained")
    (work() / (prefix + "-ok.txt")).write_text(RUNTIME_OK if scope == "native" else UI_RUNTIME_OK)

def typed_equal(left, right):
    if type(left) is not type(right): return False
    if isinstance(right, dict): return set(left) == set(right) and all(typed_equal(left[k], v) for k, v in right.items())
    if isinstance(right, list): return len(left) == len(right) and all(typed_equal(a, b) for a, b in zip(left, right))
    return left == right

def exact_fields(value, expected, detail):
    require(isinstance(value, dict) and all(k in value and typed_equal(value[k], v) for k, v in expected.items()), detail)

TEMP_SPEC = "project-fighter-normal-frame-capture.yml"
PIN_ENV = "EXPECTED_NORMAL_FRAME_CAPTURE_HELPER_SHA256"
CAPTURE_ENV_KEYS = (
    "FIGHTER_CAPTURE_SOURCE_SHA", "FIGHTER_CAPTURE_RUN_ID", "FIGHTER_CAPTURE_RUN_ATTEMPT",
    "FIGHTER_CAPTURE_NONCE", "FIGHTER_CAPTURE_SIMULATOR_UDID",
)


def work():
    parent = Path(os.environ["RUNNER_TEMP"])
    require(parent.is_absolute() and not parent.is_symlink(), "Unsafe runner directory")
    directory = parent / "fighter-normal-frame-capture"
    require(not directory.is_symlink(), "Unsafe evidence directory")
    return directory


def simulator_name():
    return "Fighter normal frames " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]


def normalized_workflow(raw):
    value = raw.decode("utf-8")
    pattern = re.compile(r"^" + re.escape(HELPER_PIN_FIELD) + r'([a-f0-9]{64})"$', re.M)
    matches = list(pattern.finditer(value))
    require(len(matches) == 1 and value.count(PIN_ENV) == 1, "Workflow must have exactly one helper pin")
    match = matches[0]
    return (value[:match.start(1)] + "0" * 64 + value[match.end(1):]).encode(), match.group(1)


def pin_sources():
    for relative, expected in ((SWIFT_TEST, SWIFT_TEST_SHA), (CHECKS, CHECKS_SHA),
                               (WORLD_SOURCE, WORLD_SOURCE_SHA), (OLD_UI, OLD_UI_SHA)):
        pinned(relative, expected)
    for row in co_published_non_inputs():
        require(pinned(row["path"], row["sha256"]).stat().st_size == row["bytes"], "Co-published size differs")
    normalized, helper_sha = normalized_workflow(regular(ROOT / WORKFLOW, 64 * 1024).read_bytes())
    require(sha(normalized) == WORKFLOW_CANONICAL_SHA and helper_sha == digest(Path(__file__))
            and os.environ.get(PIN_ENV) == helper_sha, "Workflow, helper or environment pin differs")
    resource_tools()


def selected_inventory():
    source = regular(ROOT / SWIFT_TEST, 512 * 1024).read_text()
    require(re.search(r"\bclass\s+" + CLASS_NAME + r"\b", source)
            and re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M) == [METHOD_NAME]
            and "XCTSkip" not in source, "Only the selected failed no-skip UI method may be selected")
    return [{"identifier": SELECTOR, "sourceFile": SWIFT_TEST, "sourceSHA256": digest(ROOT / SWIFT_TEST)}]


def retained_tree_digest(rows, excluded):
    return sha(b"".join(row + b"\n" for row in rows.splitlines()
                        if row.split(b"\t", 1)[1].decode() not in excluded
                        and not row.split(b"\t", 1)[1].decode().startswith("docs/")))


def source_gate():
    excluded = {HELPER, CHECKS, WORKFLOW, SWIFT_TEST} | {r["path"] for r in co_published_non_inputs()}
    rows = subprocess.check_output(["git", "ls-tree", "-r", "HEAD"], cwd=ROOT)
    names = {row.split(b"\t", 1)[1].decode() for row in rows.splitlines()}
    require(excluded <= names and retained_tree_digest(rows, excluded) == RETAINED_TREE_SHA,
            "A retained source/build/test/resource/workflow changed from c0da35df")
    require(subprocess.check_output(["git", "rev-parse", "HEAD:App"], cwd=ROOT, text=True).strip() == APP_TREE,
            "Production App tree must be unchanged")
    pin_sources(); selected_inventory()
    paths = ("App", "Sources", "Shared", "Widget", "Tests", "scripts", ".github/scripts", ".github/workflows")
    for options in (("--others", "--exclude-standard"), ("--others", "--ignored", "--exclude-standard")):
        require(not subprocess.check_output(["git", "ls-files", *options, "--", *paths], cwd=ROOT).strip(),
                "Undeclared files could alter discovered build inputs")
    require(not subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT).strip(),
            "Tracked inputs changed before preparation")


def identity_fields():
    return {"sourceSHA": os.environ["GITHUB_SHA"], "sourceBaselineSHA": SOURCE_BASELINE,
        "sourceBaselineTree": BASELINE_TREE, "appTree": APP_TREE, "executionScope": SCOPE,
        "runID": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "ref": BRANCH, "selectors": selected_inventory(), "expectedNativeMethods": 0,
        "expectedUIMethods": 1, "historicalSuccessfulMethodsSelectedAgain": False,
        "failedMethodFollowup": {"runID": "43689256803", "sourceSHA": SOURCE_BASELINE,
            "priorPassedTests": None, "priorFailedTests": None, "priorSkippedTests": None,
            "priorUIProcessExitCode": 124, "priorStructuredCountsAvailable": False,
            "priorReportedPhase": "sun-practice-ready", "priorConsoleError": "invalidPNG",
            "priorConsoleErrorEvidence": "metadata/selected-ui.log: caught error: invalidPNG",
            "sameFailedMethodSelectedAgain": True,
            "previousCountsBelongToCurrentRun": False},
        "coPublishedNonInputs": co_published_non_inputs(), "assetReleaseSHA256": RELEASE_SHA,
        "deltaManifestSHA256": DELTA_MANIFEST_SHA, "helperSHA256": digest(Path(__file__)),
        "workflowSHA256": digest(ROOT / WORKFLOW), "recipientSPKISHA256": RECIPIENT_SPKI_SHA}


def identity():
    value = read_json(work() / "identity.json")
    exact_fields(value, identity_fields(), "Prepared source, selector, scope or evidence identity changed")
    pin_sources()
    return value


def prepare():
    no_resource_keys()
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    validate_event(os.environ, read_json(Path(os.environ["GITHUB_EVENT_PATH"])), actual)
    source_gate()
    shared = resource_tools()
    legacy, base, delta = shared.manifests()
    rows = shared.final_inventory(base, delta, legacy.resource_records())
    for relative in ("App/Resources/FighterPrivate", "App/Resources/arena-original-resources.arenapack", TEMP_SPEC):
        path = ROOT / relative
        require(not path.exists() and not path.is_symlink(), "Private/generated input exists before preparation")
    require(shared.recipient_digest(regular(ROOT / RECIPIENT, 16_384).read_bytes()) == RECIPIENT_SPKI_SHA,
            "Evidence recipient differs")
    work().mkdir(mode=0o700, exist_ok=False)
    value = identity_fields()
    value.update({"preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "preservedPriorRun": {"runID": "43683433407", "sourceSHA": "903b5b61f399f7db7748c3912fcbb5afaa46553e",
            "nativePassed": 1, "uiConsolePassed": 1, "uiStructuredCounts": None,
            "selectedAgain": False, "countsBelongToCurrentRun": False},
        "productionAppChanged": False, "pixels": "PENDING", "physicalDevice": False, "TestFlight": False})
    write_json(work() / "identity.json", value)
    write_json(work() / "expected-resources.json", rows)
    print("Pinned the failed normal-window method with observed touch geometry; successful historical methods are not selected.")


def compiled_path(value, products, host=None):
    require(isinstance(value, str), "Compiled product path missing")
    expanded = value.replace("__TESTROOT__", str(products))
    if host is not None:
        expanded = expanded.replace("__TESTHOST__", str(host))
    path = Path(expanded)
    require("__" not in expanded and path.is_absolute() and not path.is_symlink()
            and path.resolve().is_relative_to(products.resolve()), "Compiled product escaped its owned directory")
    return path


def bundle_identity(path, maximum=128 * 1024**2):
    require(path.is_dir() and not path.is_symlink(), "Bundle directory missing or unsafe")
    info_path = regular(path / "Info.plist", 2 * 1024**2)
    info = plistlib.loads(info_path.read_bytes())
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", executable), "Unsafe executable name")
    identifier = info.get("CFBundleIdentifier")
    require(isinstance(identifier, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", identifier), "Bundle identifier missing")
    # Modern Xcode debug builds leave a tiny launcher at CFBundleExecutable;
    # application Swift code lives in the companion debug dylib when present.
    debug = path / (executable + ".debug.dylib")
    debug_identity = None
    if debug.exists() or debug.is_symlink():
        regular(debug, 512 * 1024**2)
        debug_identity = {"file": debug.name, "bytes": debug.stat().st_size, "sha256": digest(debug)}
    return {"bundleIdentifier": identifier, "infoSHA256": digest(info_path), "executable": executable,
            "executableSHA256": digest(regular(path / executable, maximum)), "debugDylib": debug_identity}, info


def build():
    no_resource_keys(); identity(); once("build")
    require((work() / "stage-ok.json").is_file(), "Authenticated resources required")
    project = ROOT / "project.yml"; original = project.read_bytes(); source = original.decode()
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    require(source.count(needle) == 1, "Existing test scheme is ambiguous")
    generated = source.replace(needle, "    scheme:\n      testTargets:\n        - ArenaFlowTests")
    spec = ROOT / TEMP_SPEC
    require(not spec.exists() and not spec.is_symlink(), "Temporary capture spec already exists")
    spec.write_text(generated)
    write_json(work() / "compiled-project.json", {"originalSHA256": sha(original), "generatedSHA256": digest(spec),
        "onlyProjectConfigurationChange": "Select existing ArenaFlowTests target in a temporary scheme",
        "scheme": "ShiftReminder", "trackedProjectModified": False, "builtTestTargets": ["ArenaFlowTests"],
        "builtTargetsDoNotProveExecution": True, "signingAllowed": False, "releaseSHA256": RELEASE_SHA})
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate", "--spec", spec.name], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
        "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGN_IDENTITY=", "FIGHTER_ASSET_RELEASE_SHA256=" + RELEASE_SHA], "ui-build", 1200)
    products = work() / "derived/Build/Products"; runs = list(products.glob("*.xctestrun"))
    require(len(runs) == 1, "Ambiguous build-for-testing result")
    targets = resource_tools().dependencies().test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    require(len(targets) == 1 and targets[0].get("BlueprintName") == "ArenaFlowTests"
            and targets[0].get("IsUITestBundle") is True and not targets[0].get("SkipTestIdentifiers"),
            "Only the UI test target may be built")
    require({p.name for p in products.rglob("*.xctest")} == {"ArenaFlowTests.xctest"}, "Unexpected test bundles")
    require(project.read_bytes() == original, "Tracked project specification changed")
    target = targets[0]
    host = compiled_path(target.get("TestHostPath"), products)
    bundle = compiled_path(target.get("TestBundlePath"), products, host)
    app = compiled_path(target.get("UITargetAppPath"), products, host)
    require(host.name == "ArenaFlowTests-Runner.app" and bundle.name == "ArenaFlowTests.xctest"
            and bundle.is_relative_to(host / "PlugIns") and app.name == "ShiftReminder.app", "Compiled runner layout differs")
    runner, _ = bundle_identity(host); test, _ = bundle_identity(bundle); application, app_info = bundle_identity(app)
    require(runner["bundleIdentifier"] != application["bundleIdentifier"] == "com.kriswu.shiftreminder"
            and runner["bundleIdentifier"] != test["bundleIdentifier"], "Runner/test/application identity is ambiguous")
    require(app_info.get("FighterAssetReleaseSHA256") == RELEASE_SHA
            and app_info.get("ArenaCommitSHA") == os.environ["GITHUB_SHA"], "Compiled App source or release differs")
    audit_resources(app, read_json(work() / "expected-resources.json"), bundled=True)
    require(not any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()), "Key or cipher entered App")
    write_json(work() / "compiled-bundles.json", {"runner": runner, "test": test, "app": application,
        "testBundleRelativePath": str(bundle.relative_to(host)), "sourceSHA": os.environ["GITHUB_SHA"],
        "releaseSHA256": RELEASE_SHA, "compiledXctestrunSHA256": digest(runs[0])})
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    (work() / "build-ok.txt").write_text("One unsigned UI target build; 373 resources verified; no test executed.\n")
    print("Built the single UI target once; existing methods will not be executed.")


def invocation_environment(device, nonce):
    return dict(zip(CAPTURE_ENV_KEYS, (os.environ["GITHUB_SHA"], os.environ["GITHUB_RUN_ID"],
        os.environ["GITHUB_RUN_ATTEMPT"], nonce, device["udid"])))


def mutable_test_targets(value):
    # The legacy read-only helper copies v1 target dictionaries. Configuration
    # must modify the actual plist nodes for both supported xctestrun formats.
    require(isinstance(value, dict), "Malformed xctestrun")
    if "TestConfigurations" in value:
        configurations = value["TestConfigurations"]
        require(isinstance(configurations, list), "Malformed test configurations")
        return [(target.get("BlueprintName"), target) for config in configurations
                for target in config.get("TestTargets", [])]
    return [(name, target) for name, target in value.items()
            if isinstance(target, dict) and name != "__xctestrun_metadata__"]


def configure_invocation(device):
    source = Path((work() / "xctestrun-path.txt").read_text())
    require(source.resolve().is_relative_to((work() / "derived/Build/Products").resolve()), "Unowned xctestrun")
    built = read_json(work() / "compiled-bundles.json")
    require(digest(regular(source, 2 * 1024**2)) == built["compiledXctestrunSHA256"], "Compiled xctestrun changed")
    value = plistlib.loads(source.read_bytes())
    targets = mutable_test_targets(value)
    require(len(targets) == 1 and targets[0][0] == "ArenaFlowTests"
            and targets[0][1].get("IsUITestBundle") is True, "Invocation target differs")
    target = targets[0][1]; nonce = str(uuid.uuid4())
    environment = target.setdefault("EnvironmentVariables", {})
    require(isinstance(environment, dict) and not (set(CAPTURE_ENV_KEYS) & set(environment))
            and not any(k in environment for k in KEY_NAMES), "Runner environment already contains protected values")
    launch = invocation_environment(device, nonce)
    environment.update(launch)
    target["OnlyTestIdentifiers"] = [CLASS_NAME + "/" + METHOD_NAME]
    require(not target.get("SkipTestIdentifiers"), "An invocation cannot skip selected tests")
    path = source.with_name("normal-frame-capture.xctestrun")
    require(not path.exists(), "Invocation already configured")
    path.write_bytes(plistlib.dumps(value))
    write_json(work() / "invocation.json", {"sourceSHA": os.environ["GITHUB_SHA"], "runID": os.environ["GITHUB_RUN_ID"],
        "runAttempt": os.environ["GITHUB_RUN_ATTEMPT"], "nonce": nonce, "simulatorUDID": device["udid"],
        "runnerBundleIdentifier": built["runner"]["bundleIdentifier"], "testBundleIdentifier": built["test"]["bundleIdentifier"],
        "targetAppBundleIdentifier": built["app"]["bundleIdentifier"], "selector": SELECTOR,
        "launchEnvironment": launch, "xctestrunSHA256": digest(path), "processDeadlineSeconds": 360,
        "nativeMethodsSelected": 0, "historicalMethodsSelected": 0})
    return path


def verify_results(summary, data, device):
    for key, value in (("totalTestCount", 1), ("passedTests", 1), ("failedTests", 0), ("skippedTests", 0)):
        require(type(summary.get(key)) is int and summary[key] == value, "Exact UI count differs: " + key)
    require(summary.get("result") == "Passed" and isinstance(data.get("testNodes"), list), "UI method did not pass")
    seen = []
    def walk(nodes):
        require(isinstance(nodes, list), "Malformed result children")
        for node in nodes:
            require(isinstance(node, dict), "Malformed test result")
            if node.get("nodeType") == "Test Case":
                identifier = node.get("nodeIdentifier")
                require(isinstance(identifier, str) and identifier.removesuffix("()") in
                        (SELECTOR, CLASS_NAME + "/" + METHOD_NAME) and node.get("result") == "Passed",
                        "Unexpected, failed or skipped method")
                seen.append(SELECTOR)
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    require(seen == [SELECTOR], "Missing, duplicate or additional test method")
    configurations = summary.get("devicesAndConfigurations")
    require(isinstance(configurations, list) and len(configurations) == 1, "Exactly one result device required")
    config = configurations[0]; observed = config.get("device", {})
    require(observed.get("deviceId") == device["udid"] and observed.get("deviceName") == device["name"]
            and observed.get("modelName") == "iPhone 17 Pro Max" and observed.get("platform") == "iOS Simulator"
            and all(type(config.get(k)) is int and config[k] == v for k, v in
                    (("passedTests", 1), ("failedTests", 0), ("skippedTests", 0))), "Result device/counts differ")


def ui():
    no_resource_keys(); identity(); once("ui")
    require((work() / "build-ok.txt").is_file(), "Verified build required")
    device = read_json(work() / "simulator.json")
    invocation = configure_invocation(device)
    started = datetime.datetime.now(datetime.timezone.utc)
    result = {"exitCode": None, "selectedCount": 1, "iterations": 1, "exports": {}}
    try:
        result["exitCode"] = run_logged(["xcodebuild", "test-without-building", "-xctestrun", str(invocation),
            "-destination", "id=" + device["udid"], "-parallel-testing-enabled", "NO",
            "-resultBundlePath", str(work() / "ui.xcresult"), "-only-testing:" + SELECTOR],
            "selected-ui", 360, check=False)
        write_json(work() / "ui-process.json", result)
        if (work() / "ui.xcresult/Info.plist").is_file():
            for kind in ("summary", "tests"):
                result["exports"][kind] = run_logged(["xcrun", "xcresulttool", "get", "test-results", kind,
                    "--path", str(work() / "ui.xcresult")], "ui-result-" + kind, 45, check=False,
                    output_name="ui-" + kind + ".json")
        write_json(work() / "ui-process.json", result)
        if result["exitCode"]:
            raise PhaseFailure("UI process did not complete; recover durable sidecars separately", result["exitCode"])
        require(result["exports"] == {"summary": 0, "tests": 0}, "Structured XCTest exports unavailable")
        verify_results(read_json(work() / "ui-summary.json"), read_json(work() / "ui-tests.json"), device)
        (work() / "ui-ok.txt").write_text("New UI method: one pass; no failures/skips; pixels require independent review.\n")
    finally:
        write_json(work() / "ui-process.json", result)
        collect_runtime(started, datetime.datetime.now(datetime.timezone.utc))
    print("The failed UI method followup passed; no successful historical method repeated; visual review is still pending.")


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def png_dimensions(raw, *, landscape=True):
    require(24 <= len(raw) <= 24 * 1024**2 and raw[:8] == b"\x89PNG\r\n\x1a\n", "Not a bounded original PNG")
    offset, header, compressed, ended = 8, None, bytearray(), False
    while offset < len(raw):
        require(offset + 12 <= len(raw), "Truncated PNG chunk")
        size = struct.unpack_from(">I", raw, offset)[0]
        kind = raw[offset + 4:offset + 8]; end = offset + 12 + size
        require(end <= len(raw), "PNG chunk escapes file")
        payload = raw[offset + 8:offset + 8 + size]
        require(zlib.crc32(kind + payload) & 0xffffffff == struct.unpack_from(">I", raw, end - 4)[0], "PNG CRC differs")
        if kind == b"IHDR":
            require(header is None and offset == 8 and size == 13, "Duplicate/invalid PNG header")
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            require(header is not None and not ended, "Unordered PNG data")
            compressed.extend(payload)
        elif kind == b"IEND":
            require(size == 0 and end == len(raw), "PNG has trailing bytes")
            ended = True
        else:
            require(kind[:1].islower(), "Unsupported critical PNG chunk")
        offset = end
    require(ended and header is not None and compressed, "PNG is incomplete")
    width, height, depth, color, compression, filtering, interlace = header
    require(0 < width <= 5000 and 0 < height <= 5000 and (not landscape or width > height)
            and depth in (8, 16) and color in (2, 6)
            and (compression, filtering, interlace) == (0, 0, 0), "Unexpected normal-window PNG layout")
    stride = 1 + width * (3 if color == 2 else 4) * (depth // 8)
    expected = height * stride
    require(expected <= 200 * 1024**2, "Decoded PNG exceeds bound")
    inflater = zlib.decompressobj()
    decoded = inflater.decompress(bytes(compressed), expected + 1)
    require(len(decoded) == expected and inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail
            and all(decoded[y * stride] <= 4 for y in range(height)), "PNG compressed scanlines are incomplete or oversized")
    return width, height


def tiff_orientation(payload):
    """Read the one IFD0 orientation in bounded PNG eXIf TIFF bytes, not image pixels."""
    require(8 <= len(payload) <= 65536 and payload[:2] in (b"II", b"MM"), "Unsupported bounded eXIf TIFF")
    order = "<" if payload[:2] == b"II" else ">"
    require(struct.unpack_from(order + "H", payload, 2)[0] == 42, "Invalid TIFF magic")
    offset = struct.unpack_from(order + "I", payload, 4)[0]
    require(8 <= offset <= len(payload) - 2, "TIFF IFD0 escapes eXIf")
    count = struct.unpack_from(order + "H", payload, offset)[0]
    end = offset + 2 + 12 * count
    require(1 <= count <= 64 and end + 4 <= len(payload)
            and struct.unpack_from(order + "I", payload, end)[0] == 0,
            "Unbounded, truncated or chained TIFF IFD0")
    values = []
    for index in range(count):
        entry = offset + 2 + 12 * index
        tag, kind, size = struct.unpack_from(order + "HHI", payload, entry)
        if tag == 274:
            require(kind == 3 and size == 1, "TIFF orientation must be one SHORT")
            values.append(struct.unpack_from(order + "H", payload, entry + 8)[0])
    require(len(values) == 1 and values[0] in (1, 3, 6, 8), "Missing, duplicated or mirrored TIFF orientation")
    return values[0]


def xmp_orientation(payload):
    """Only the bounded, uncompressed PNG XMP representation used by XCUIScreen."""
    require(len(payload) <= 65536, "PNG XMP exceeds bound")
    pieces = payload.split(b"\0", 1)
    require(len(pieces) == 2 and pieces[0] == b"XML:com.adobe.xmp", "Unexpected PNG XMP keyword")
    tail = pieces[1]
    require(len(tail) >= 4 and tail[:2] == b"\0\0", "Compressed or invalid PNG XMP is unsupported")
    parts = tail[2:].split(b"\0", 2)
    require(len(parts) == 3, "Truncated PNG XMP language fields")
    document = parts[2]
    require(b"<!DOCTYPE" not in document and b"<!ENTITY" not in document, "PNG XMP declarations are not allowed")
    try:
        root = ET.fromstring(document.decode("utf-8"))
    except (UnicodeDecodeError, ET.ParseError) as error:
        raise ValueError("Invalid PNG XMP XML") from error
    tag = "{http://ns.adobe.com/tiff/1.0/}Orientation"
    values = []
    for node in root.iter():
        if node.tag == tag:
            require(len(node) == 0, "Nested XMP orientation")
            values.append((node.text or "").strip())
        if tag in node.attrib:
            values.append(node.attrib[tag].strip())
    require(len(values) <= 1 and all(value in ("1", "3", "6", "8") for value in values),
            "Duplicated or unsupported XMP orientation")
    return int(values[0]) if values else None


def png_display_geometry(raw, observation):
    # IHDR is encoded storage geometry. PNG eXIf carries TIFF orientation;
    # ImageIO's kCGImagePropertyOrientation uses that same numeric convention.
    # https://www.w3.org/TR/png/#eXIf
    # https://developer.apple.com/documentation/imageio/kcgimagepropertyorientation
    width, height = png_dimensions(raw, landscape=False)
    offset, exif, xmp = 8, [], []
    while offset < len(raw):
        size = struct.unpack_from(">I", raw, offset)[0]
        kind, payload = raw[offset + 4:offset + 8], raw[offset + 8:offset + 8 + size]
        if kind == b"eXIf":
            exif.append(tiff_orientation(payload))
        elif kind == b"iTXt" and payload.split(b"\0", 1)[0] == b"XML:com.adobe.xmp":
            xmp.append(xmp_orientation(payload))
        offset += 12 + size
    require(len(exif) == 1 and len(xmp) <= 1, "Exactly one PNG eXIf and at most one XMP packet required")
    orientation = exif[0]
    require(not xmp or xmp[0] is None or xmp[0] == orientation, "PNG eXIf and XMP orientation disagree")
    display_width, display_height = (height, width) if orientation in (6, 8) else (width, height)
    require(isinstance(observation, dict) and finite(observation.get("width"))
            and finite(observation.get("height")) and observation["width"] > observation["height"] > 0
            and display_width > display_height
            and display_width == observation["width"] * 3 and display_height == observation["height"] * 3,
            "PNG display geometry does not match the owned iPhone's landscape AX frame at 3x")
    return {"width": width, "height": height, "storedWidth": width, "storedHeight": height,
        "exifOrientation": orientation, "displayWidth": display_width, "displayHeight": display_height,
        "displayToAXScale": 3, "xmpOrientation": xmp[0] if xmp else None}


def ready_observation(row):
    if not isinstance(row, dict) or row.get("error") is not None or not finite(row.get("width")) or not finite(row.get("height")):
        return False
    elements = row.get("elements", {})
    def count(key): return len(elements.get(key, []))
    def field(key, name): return elements.get(key, [{}])[0].get(name) if count(key) else None
    return (row["width"] > row["height"] > 0 and count("duel.resourceError") == 0
        and count("duel.pause") == 1 and count("duel.resume") == 0
        and all(count(k) == 1 for k in ("duel.stats.0", "duel.stats.1", "duel.name.0", "duel.name.1"))
        and field("duel.name.0", "label") == "孙登 · 黑色双刀"
        and field("duel.name.1", "label") == "刘泉纬 · 双锤"
        and field("duel.control.joystick", "value") == "居中"
        and field("duel.control.weapon", "value") == "可施放")


def frame_valid(frame):
    return (isinstance(frame, dict) and set(frame) == {"x", "y", "width", "height"}
            and all(finite(v) for v in frame.values()) and 0 < frame["width"] <= 5000
            and 0 < frame["height"] <= 5000)


def contains_frame(outer, inner):
    return (frame_valid(outer) and frame_valid(inner) and inner["x"] >= outer["x"] and inner["y"] >= outer["y"]
            and inner["x"] + inner["width"] <= outer["x"] + outer["width"]
            and inner["y"] + inner["height"] <= outer["y"] + outer["height"])


def frames_overlap(a, b):
    return (a["x"] < b["x"] + b["width"] and b["x"] < a["x"] + a["width"]
            and a["y"] < b["y"] + b["height"] and b["y"] < a["y"] + a["height"])


def verify_selection_touch(touch, rows):
    if touch is None:
        return None
    exact_fields(touch, {"identifier": "duel.hero.ember",
        "api": "XCUIApplication.coordinate(withNormalizedOffset:).withOffset(_:).tap()",
        "maximumObservationAgeAtInvocationSeconds": 2, "synthesizedEventTimeObserved": False,
        "internalSelectionStateInjected": False, "retryPerformed": False}, "Unexpected touch policy or repeated input")
    index = touch.get("observationIndex")
    require(type(index) is int and 0 <= index < len(rows), "Touch observation missing")
    row = rows[index]
    elements = row.get("elements", {})
    sun, liu = elements.get("duel.hero.ember", []), elements.get("duel.hero.liu", [])
    require(row.get("phase") == "sun-touch-geometry" and row.get("error") is None
            and len(sun) == len(liu) == 1 and sun[0].get("value") == "未选择"
            and liu[0].get("value") == "已选择" and sun[0].get("enabled") is True,
            "Touch did not begin with the uniquely observed unselected Sun button")
    root, window, button, target = (touch.get(k) for k in ("rootFrame", "windowFrame", "buttonFrame", "targetFrame"))
    other = liu[0].get("frame")
    require(all(frame_valid(f) for f in (root, window, button, target, other))
            and root == row.get("rootFrame") and root["width"] == row["width"] and root["height"] == row["height"]
            and root["width"] > root["height"] and button == sun[0].get("frame")
            and window == sun[0].get("windowFrame") and window in row.get("windowFrames", [])
            and contains_frame(root, button) and contains_frame(window, button) and contains_frame(button, target)
            and not frames_overlap(button, other), "Touch geometry is unowned, overlapping or outside the visible window")
    titles = [f for f in row.get("sunTitleFrames", []) if frame_valid(f) and contains_frame(button, f)]
    require(len(titles) <= 1, "Sun title geometry is ambiguous")
    kind = "observed-sun-title-center" if titles else "observed-button-center"
    require(touch.get("targetKind") == kind and target == (titles[0] if titles else button), "Unobserved touch target")
    point, offset = touch.get("pointInScreenCoordinates"), touch.get("offsetFromAppOrigin")
    require(isinstance(point, dict) and isinstance(offset, dict) and set(point) == set(offset) == {"x", "y"}
            and all(finite(v) for v in [*point.values(), *offset.values()]), "Touch coordinates malformed")
    require(point == {"x": target["x"] + target["width"] / 2, "y": target["y"] + target["height"] / 2}
            and offset == {"x": point["x"] - root["x"], "y": point["y"] - root["y"]}
            and button["x"] + 1 <= point["x"] < button["x"] + button["width"] - 1
            and button["y"] + 1 <= point["y"] < button["y"] + button["height"] - 1,
            "Recorded touch does not lie inside the observed Sun button")
    observed_end, intent, invoked, returned = (touch.get(k) for k in
        ("observationFinishedUptime", "intentPreparedAtUptime", "invokedAtUptime", "returnedAtUptime"))
    require(finite(observed_end) and observed_end == row["uptime"] + row["snapshotSeconds"]
            and finite(intent) and intent >= observed_end, "Touch intent lacks its observation timestamp")
    state, count = touch.get("invocationState"), touch.get("tapCount")
    require(type(count) is int and count in (0, 1), "A touch cannot be inferred from an unbounded/ambiguous count")
    if invoked is None:
        require(state == "intent" and count == 0 and returned is None,
                "Uninvoked intent cannot claim a call or return")
    else:
        require(count == 1 and finite(invoked) and intent <= invoked <= observed_end + 2,
                "Touch used stale geometry or lacks its actual invocation timestamp")
        if returned is None:
            require(state == "called", "An unreturned invocation cannot claim completion")
        else:
            require(state == "returned" and finite(returned) and returned >= invoked,
                    "Touch return precedes invocation or has the wrong state")
    return {"observationIndex": index, "targetKind": kind, "pointInScreenCoordinates": point,
        "rootFrame": root, "windowFrame": window, "buttonFrame": button, "targetFrame": target,
        "intentPreparedAtUptime": intent, "invokedAtUptime": invoked, "returnedAtUptime": returned,
        "invocationState": state, "invoked": invoked is not None, "returned": returned is not None,
        "tapCount": count, "retryPerformed": False, "synthesizedEventTimeObserved": False}


def verify_diagnostics(value, directory):
    rows, errors = value.get("diagnosticCaptures"), value.get("diagnosticCaptureErrors")
    require(isinstance(rows, list) and len(rows) <= 2 and isinstance(errors, list) and len(errors) <= 1,
            "Unbounded diagnostic captures/errors")
    seen, receipts, last_end = set(), [], -1
    for row in rows:
        label = row.get("label") if isinstance(row, dict) else None
        require(label in DIAGNOSTIC_LABELS and label not in seen, "Unexpected or duplicate diagnostic label")
        seen.add(label)
        exact_fields(row, {"file": label + ".png", "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation",
            "originalBytesUnmodified": True, "countsAsNormalPracticeFrame": False}, "Diagnostic cannot count as a practice frame")
        require(isinstance(row.get("phase"), str), "Diagnostic phase missing")
        if label == DIAGNOSTIC_LABELS[0]:
            require(row["phase"] == "sun-select-before-touch" and len(receipts) == 0, "Pre-touch diagnostic order differs")
        else:
            require(value.get("flowCompleted") is False, "Success cannot include a failure diagnostic")
        started, ended = row.get("captureStartedUptime"), row.get("captureFinishedUptime")
        require(finite(started) and finite(ended) and 0 <= started <= ended and started >= last_end,
                "Diagnostic capture timing is invalid")
        raw = regular(directory / row["file"], 24 * 1024**2).read_bytes()
        width, height = png_dimensions(raw, landscape=False)
        exact_fields(row, {"bytes": len(raw), "sha256": sha(raw), "width": width, "height": height}, "Diagnostic PNG bytes differ")
        receipts.append({"label": label, "file": row["file"], "phase": row["phase"], "bytes": len(raw),
            "sha256": sha(raw), "width": width, "height": height, "countsAsNormalPracticeFrame": False})
        last_end = ended
    for row in errors:
        exact_fields(row, {"label": DIAGNOSTIC_LABELS[1], "error": "normal-window-capture-unavailable"}, "Unexpected diagnostic failure")
        require(value.get("flowCompleted") is False and DIAGNOSTIC_LABELS[1] not in seen, "Diagnostic capture failed and passed simultaneously")
    touch = value.get("selectionTouch")
    if touch is not None:
        pre = next((r for r in rows if r["label"] == DIAGNOSTIC_LABELS[0]), None)
        require(pre is not None and pre["captureFinishedUptime"] <= touch["observationFinishedUptime"],
                "Recorded touch lacks its earlier pre-touch original")
    return receipts, last_end


def verify_sidecars(directory, invocation):
    require(directory.is_dir() and not directory.is_symlink(), "Sidecar directory missing")
    names = {p.name for p in directory.iterdir()}
    require(REPORT_FILE in names and names <= ALLOWED_SIDECAR_FILES, "Unexpected or missing sidecar files")
    report_path = regular(directory / REPORT_FILE, 1024**2)
    report_data = report_path.read_bytes(); value = json.loads(report_data)
    exact_fields(value, {"schema": REPORT_SCHEMA, "selector": SELECTOR, "expectedReleaseSHA256": RELEASE_SHA,
        "launchArguments": ["-demo", "-screen", "fighter"], "sidecarDirectory": SIDECAR_DIRECTORY,
        "reportFile": REPORT_FILE, "expectedCaptureLabels": list(FRAME_LABELS),
        "selectionTouchPolicy": "one-coordinate-touch-from-fresh-observed-geometry",
        "allowedDiagnosticCaptureLabels": list(DIAGNOSTIC_LABELS), "diagnosticsCountAsNormalPracticeFrames": False,
        "normalPNGOrientationPolicy": PNG_ORIENTATION_POLICY,
        "screenshotsRequireVisualReview": True,
        "visualReview": "PENDING"}, "Sidecar report schema/scope differs")
    require(finite(value.get("minimumSecondsBetweenCaptureOneEndAndLaterObservationStart"))
            and value["minimumSecondsBetweenCaptureOneEndAndLaterObservationStart"] == 1
            and finite(value.get("secondObservationWaitBudgetSeconds"))
            and value["secondObservationWaitBudgetSeconds"] == 4, "Observation timing contract differs")
    false_claims = ("observationsAndScreenshotsShareExactFrame", "xctestOutcomeIsProvidedByThisReport",
        "normalDrawableCountersVerified", "sourcePreparationSequenceVerifiedByUI", "frameOrTickProgressVerified",
        "offscreenCaptureUsed", "renderAPIsInvoked", "internalCombatStateInjected", "shadowSkillInvoked",
        "joystickInvoked", "pauseOrResumeInvoked", "otherCharacterPracticeInvoked", "audiblePlaybackVerified",
        "physicalDeviceVerified", "panguEquipmentActivated")
    require(all(value.get(key) is False for key in false_claims), "Image evidence cannot claim broader acceptance")
    identity_expected = {k: invocation[k] for k in ("sourceSHA", "runID", "runAttempt", "nonce",
        "runnerBundleIdentifier", "testBundleIdentifier", "targetAppBundleIdentifier", "launchEnvironment")}
    identity_expected.update({"expectedSimulatorUDID": invocation["simulatorUDID"], "actualSimulatorUDID": invocation["simulatorUDID"]})
    exact_fields(value.get("identity"), identity_expected, "Sidecar runner/source/run/nonce/simulator identity differs")
    internals = value.get("normalPresentationInternals", {})
    require(internals.get("status") == "notObserved" and all(k in internals and internals[k] is None for k in
        ("normalFrames", "gameTick", "animationTick", "sourceLiveTick", "firstCommitCount", "presentationKickAttempts",
         "preparationReady", "sourceMusicReady")), "Unobserved internals must remain unknown")
    rows = value.get("observations"); captures = value.get("captures")
    require(isinstance(rows, list) and len(rows) <= 128 and isinstance(captures, list) and len(captures) <= 2,
            "Unbounded observation/capture collection")
    previous_end = -1
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get("phase"), str)
                and finite(row.get("uptime")) and finite(row.get("snapshotSeconds")) and row["snapshotSeconds"] >= 0
                and row["uptime"] >= previous_end and finite(row.get("width")) and finite(row.get("height"))
                and 0 <= row["width"] <= 5000 and 0 <= row["height"] <= 5000
                and row.get("error") in (None, "accessibility-snapshot-unavailable")
                and isinstance(row.get("elements"), dict), "Malformed observation timing or geometry")
        for key, elements in row["elements"].items():
            require(isinstance(key, str) and key.startswith("duel.") and isinstance(elements, list) and len(elements) <= 32,
                    "Malformed accessibility elements")
            for element in elements:
                require(isinstance(element, dict) and isinstance(element.get("label"), str)
                        and type(element.get("enabled")) is bool and
                        (element.get("value") is None or isinstance(element["value"], str)), "Malformed accessibility element")
        previous_end = row["uptime"] + row["snapshotSeconds"]
    touch = verify_selection_touch(value.get("selectionTouch"), rows)
    receipts, previous_capture_end, previous_index = [], -1, -1
    for index, capture in enumerate(captures):
        label = FRAME_LABELS[index]; phase = ("sun-practice-ready", "sun-practice-later")[index]
        exact_fields(capture, {"label": label, "file": label + ".png", "phase": "capture-" + label, "ordinal": index + 1,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": True,
            "orientationReader": "ImageIO CGImageSourceCopyPropertiesAtIndex"}, "Capture ordering/API differs")
        oi = capture.get("observationIndex")
        require(type(oi) is int and previous_index < oi < len(rows), "Capture lacks its own preceding observation")
        row = rows[oi]
        require(ready_observation(row) and row["phase"] == phase, "Capture UI preconditions were not observed")
        start, end, observed_end = (capture.get(k) for k in ("captureStartedUptime", "captureFinishedUptime", "observationFinishedUptime"))
        require(all(finite(t) for t in (start, end, observed_end)) and observed_end == row["uptime"] + row["snapshotSeconds"]
                and previous_capture_end <= observed_end <= start <= end, "Capture timing/order differs")
        if index:
            require(row["uptime"] >= previous_capture_end + 1.0, "Second observation is not one elapsed second after first capture")
        path = regular(directory / capture["file"], 24 * 1024**2); raw = path.read_bytes()
        geometry = png_display_geometry(raw, row)
        exact_fields(capture, {"bytes": len(raw), "sha256": sha(raw),
            **{key: value for key, value in geometry.items() if key != "xmpOrientation"}},
            "Original PNG bytes or independently parsed display orientation differ")
        receipts.append({"file": capture["file"], "bytes": len(raw), "sha256": sha(raw), **geometry})
        previous_index, previous_capture_end = oi, end
    diagnostics, diagnostic_end = verify_diagnostics(value, directory)
    require(names == {REPORT_FILE} | {r["file"] for r in receipts + diagnostics}, "PNG file set differs from report")
    touch_end = max((t for t in (touch.get("intentPreparedAtUptime"), touch.get("invokedAtUptime"),
        touch.get("returnedAtUptime")) if t is not None), default=-1) if touch else -1
    require(type(value.get("flowCompleted")) is bool and finite(value.get("writtenAtUptime"))
            and value["writtenAtUptime"] >= max(previous_end, previous_capture_end, diagnostic_end, touch_end), "Report completion/timestamp invalid")
    if value["flowCompleted"]:
        require(len(captures) == 2 and value.get("phase") == "two-normal-window-images-saved"
                and value.get("failurePhase") is None, "Completed flow lacks exactly two originals")
        require(touch is not None and touch["returned"] and len(diagnostics) == 1
                and diagnostics[0]["label"] == DIAGNOSTIC_LABELS[0], "Completed flow lacks its single observed touch/pre-touch original")
        require(captures[0]["observationIndex"] > touch["observationIndex"]
                and rows[captures[0]["observationIndex"]]["uptime"] >= touch["returnedAtUptime"],
                "Normal practice evidence preceded the actual touch return")
    return {"reportSHA256": sha(report_data), "reportBytes": len(report_data), "reportIdentityVerified": True,
        "sourceAndInstalledBundlesVerifiedSeparately": True, "flowCompleted": value["flowCompleted"],
        "captureCount": len(receipts), "captures": receipts, "originalBytesUnmodified": True,
        "diagnosticCaptureCount": len(diagnostics), "diagnosticCaptures": diagnostics,
        "diagnosticsCountAsNormalPracticeFrames": False, "selectionTouch": touch,
        "uiVisibleReadinessObserved": any(ready_observation(row) for row in rows),
        "normalPresentationInternals": "notObserved",
        "visualReview": "PENDING", "xctestPassed": False, "physicalDeviceVerified": False}


def owned_simulator():
    device = read_json(work() / "simulator.json")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True, timeout=30))
    matches = [d for rows in catalog["devices"].values() for d in rows if d.get("udid") == device["udid"]]
    require(len(matches) == 1 and matches[0].get("name") == device["name"] == simulator_name()
            and device.get("physicalDevice") is False, "Simulator ownership differs")
    return device, matches[0]


def simulator_container(device, identifier, kind):
    require(kind in ("data", "app") and re.fullmatch(r"[A-Za-z0-9_.-]+", identifier), "Unreviewed container lookup")
    path = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device["udid"], identifier, kind],
                                        text=True, timeout=30).strip())
    require(path.is_absolute() and path.is_dir() and not path.is_symlink()
            and device["udid"].upper() in (part.upper() for part in path.resolve().parts), "Unowned simulator container")
    return path


def recover():
    no_resource_keys(); identity(); once("recover")
    require((work() / "ui-invoked.json").is_file(), "No current UI invocation to recover")
    invocation = read_json(work() / "invocation.json"); built = read_json(work() / "compiled-bundles.json")
    device, _ = owned_simulator()
    exact_fields(invocation, {"sourceSHA": os.environ["GITHUB_SHA"], "runID": os.environ["GITHUB_RUN_ID"],
        "runAttempt": os.environ["GITHUB_RUN_ATTEMPT"], "simulatorUDID": device["udid"], "selector": SELECTOR,
        "runnerBundleIdentifier": built["runner"]["bundleIdentifier"], "testBundleIdentifier": built["test"]["bundleIdentifier"],
        "targetAppBundleIdentifier": built["app"]["bundleIdentifier"]}, "Recovery invocation differs")
    require(str(uuid.UUID(invocation["nonce"])) == invocation["nonce"], "Malformed invocation nonce")
    require(invocation["launchEnvironment"] == invocation_environment(device, invocation["nonce"]), "Recovery environment differs")
    runner_id = built["runner"]["bundleIdentifier"]
    # Stop only our runner if it survived an xcodebuild timeout; this never launches
    # the App or chooses replacement frames. Atomic sidecars are recovered as-is.
    run_logged(["xcrun", "simctl", "terminate", device["udid"], runner_id], "runner-stop-before-recovery", 30, check=False)
    runner_path = simulator_container(device, runner_id, "app")
    installed_runner, _ = bundle_identity(runner_path)
    installed_test, _ = bundle_identity(runner_path / built["testBundleRelativePath"])
    app_path = simulator_container(device, built["app"]["bundleIdentifier"], "app")
    installed_app, info = bundle_identity(app_path)
    require(installed_runner == built["runner"] and installed_test == built["test"] and installed_app == built["app"]
            and info.get("ArenaCommitSHA") == os.environ["GITHUB_SHA"] and info.get("FighterAssetReleaseSHA256") == RELEASE_SHA,
            "Installed runner/test/application bytes differ from verified build")
    write_json(work() / "installed-bundles.json", {"verified": True, "sourceSHA": os.environ["GITHUB_SHA"],
        "releaseSHA256": RELEASE_SHA, "simulatorUDID": device["udid"], "runner": installed_runner,
        "test": installed_test, "app": installed_app})
    data = simulator_container(device, runner_id, "data")
    original = data / "Documents" / SIDECAR_DIRECTORY / invocation["nonce"]
    require(original.is_dir() and not original.is_symlink() and original.resolve().is_relative_to(data.resolve())
            and not any(p.is_symlink() for p in (data / "Documents", original.parent)), "Unsafe or missing runner sidecars")
    paths = sorted(original.iterdir())
    require(len(paths) <= 5 and all(p.name in ALLOWED_SIDECAR_FILES for p in paths), "Unexpected sidecar files")
    destination = work() / "ui-sidecars"; destination.mkdir(mode=0o700, exist_ok=False)
    copied = []
    for path in paths:
        raw = regular(path, 1024**2 if path.name == REPORT_FILE else 24 * 1024**2).read_bytes()
        (destination / path.name).write_bytes(raw)
        copied.append({"file": path.name, "bytes": len(raw), "sha256": sha(raw)})
    write_json(work() / "sidecar-copy.json", {"simulatorUDID": device["udid"], "runnerBundleIdentifier": runner_id,
        "nonce": invocation["nonce"], "files": copied, "copiedWithoutReencoding": True, "xcresultRequired": False})
    receipt = verify_sidecars(destination, invocation)
    write_json(work() / "sidecar-verification.json", receipt)
    require(receipt["flowCompleted"] and receipt["captureCount"] == 2, "Partial evidence preserved; two normal frames not completed")
    (work() / "sidecars-ok.txt").write_text("Exactly two original normal-window PNGs and report verified; pixel review pending.\n")
    print("Recovered two original normal-window PNGs independently of XCTest result finalization.")


def optional_json(name):
    path = work() / name
    if not path.is_file():
        return None
    try:
        return read_json(path)
    except (ValueError, OSError):
        return None


def public_summary():
    data = identity()
    process = optional_json("ui-process.json")
    summary = optional_json("ui-summary.json")
    sidecar = optional_json("sidecar-verification.json")
    counts = None if not summary else {key: summary.get(key) for key in
        ("totalTestCount", "passedTests", "failedTests", "skippedTests", "result")}
    return {"sourceSHA": data["sourceSHA"], "sourceBaselineSHA": SOURCE_BASELINE, "sourceBaselineTree": BASELINE_TREE,
        "appTree": APP_TREE, "executionScope": SCOPE, "runID": data["runID"], "attempt": data["attempt"],
        "selector": SELECTOR, "expectedNativeMethods": 0, "expectedUIMethods": 1,
        "coPublishedNonInputs": co_published_non_inputs(), "historicalSuccessfulMethodsSelectedAgain": False,
        "failedMethodFollowup": data["failedMethodFollowup"],
        "productionAppChanged": False, "assetReleaseSHA256": RELEASE_SHA,
        "resourcesAuthenticated": (work() / "stage-ok.json").is_file(),
        "compiled373ResourcesVerified": (work() / "build-ok.txt").is_file(),
        "installedBundlesVerified": (optional_json("installed-bundles.json") or {}).get("verified") is True,
        "uiExactMethodPassed": (work() / "ui-ok.txt").is_file(), "uiObservedCounts": counts,
        "uiProcess": process, "uiRuntimeDiagnostics": optional_json("ui-runtime-diagnostics.json"),
        "uiRuntimeDiagnosticGatePassed": (work() / "ui-runtime-ok.txt").is_file(),
        "sidecars": sidecar, "exactTwoOriginalNormalFramesVerified": (work() / "sidecars-ok.txt").is_file(),
        "sidecarCopy": optional_json("sidecar-copy.json"), "normalPresentationInternals": "notObserved",
        "frameOrTickProgressVerified": False, "normalDrawableCountersVerified": False,
        "pixels": "PENDING", "liveUIValidated": False, "physicalIPhoneAcceptance": "NOT VERIFIED",
        "performanceAcceptance": False, "audiblePlayback": "NOT VERIFIED", "productionPanguAssetsActivated": False,
        "TestFlightUploaded": False, "timings": optional_json("timings.json"),
        "diagnosticsSealed": (work() / "sealed-ok.txt").is_file()}


def seal():
    no_resource_keys(); identity(); once("seal")
    shared = resource_tools(); public = regular(ROOT / RECIPIENT, 16_384).read_bytes()
    require(shared.recipient_digest(public) == RECIPIENT_SPKI_SHA, "Evidence recipient differs")
    envelope = importlib.import_module("fighter_private_model")
    published, archive = work() / "published", work() / "private-evidence.zip"
    published.mkdir(mode=0o700, exist_ok=False)
    try:
        write_json(work() / "public-summary.json", public_summary())
        entries, total = [], 0
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_STORED) as output:
            for path in sorted(work().iterdir()):
                if path.suffix not in (".log", ".json", ".txt") or not path.is_file() or path.stat().st_size == 0:
                    continue
                regular(path, 128 * 1024**2); size = path.stat().st_size
                # Keep structured reports intact. Only raw logs may be tailed.
                require(path.suffix == ".log" or size <= 16 * 1024**2, "Structured metadata exceeds bound")
                maximum = 2 * 1024**2 if path.suffix == ".log" else 16 * 1024**2
                with path.open("rb") as source:
                    source.seek(max(0, size - maximum)); raw = source.read(maximum)
                total += len(raw)
                require(total <= 48 * 1024**2 and len(entries) < 100, "Metadata exceeds bound")
                name = "metadata/" + path.name; output.writestr(name, raw)
                entries.append({"file": name, "sourceBytes": size, "archivedBytes": len(raw),
                    "tailOnly": size != len(raw), "sha256": sha(raw)})
            directory = work() / "ui-sidecars"
            if directory.is_dir():
                require(not directory.is_symlink(), "Unsafe recovered evidence directory")
                for path in sorted(directory.iterdir()):
                    require(path.name in ALLOWED_SIDECAR_FILES, "Unexpected recovered evidence")
                    regular(path, 1024**2 if path.name == REPORT_FILE else 24 * 1024**2)
                    name = "ui-sidecars/" + path.name; output.write(path, name)
                    entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path)})
            output.writestr("private-evidence-inventory.json", json.dumps(entries, indent=2))
        require(entries and archive.stat().st_size <= 160 * 1024**2, "Evidence archive exceeds bound")
        key = secrets.token_bytes(32)
        shared.wrap_key(key, shared.existing_recipient(), published / (STEM + ".key.enc"))
        shared.wrap_key(key, public, published / (STEM + ".session-key.enc"))
        os.environ[KEY_NAMES[0]] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / (STEM + ".enc"))
        finally:
            os.environ.pop(KEY_NAMES[0], None); key = b""
        files = sorted(published.glob("*.enc"))
        require({p.name for p in files} == {STEM + suffix for suffix in (".enc", ".key.enc", ".session-key.enc")},
                "Incomplete encrypted envelope")
        (published / (STEM + ".SHA256SUMS")).write_text("".join(digest(p) + "  " + p.name + "\n" for p in files))
        (work() / "sealed-ok.txt").write_text("Only ciphertext and wrapped fresh diagnostic keys may be uploaded.\n")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive.unlink(missing_ok=True)
    print("Sealed original/partial normal-window evidence and exact invocation receipts; no plaintext upload.")


def sealed_ciphertext_verified():
    published = work() / "published"
    expected = {STEM + suffix for suffix in (".enc", ".key.enc", ".session-key.enc")}
    try:
        require((work() / "sealed-ok.txt").is_file() and published.is_dir() and not published.is_symlink(),
                "No completed encrypted seal")
        sums = regular(published / (STEM + ".SHA256SUMS"), 4096).read_text().splitlines()
        require(len(sums) == 3, "Ciphertext inventory differs")
        seen = set()
        for row in sums:
            match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", row)
            require(match is not None and match[2] in expected and match[2] not in seen, "Unexpected ciphertext entry")
            seen.add(match[2])
            require(digest(regular(published / match[2], 161 * 1024**2)) == match[1], "Ciphertext bytes changed")
        require(seen == expected, "Encrypted envelope incomplete")
        return True
    except (OSError, ValueError):
        return False


def cleanup():
    no_resource_keys()
    # Refuse broad cleanup if this directory no longer belongs to this invocation.
    identity()
    summary = public_summary(); errors = []
    encrypted = sealed_ciphertext_verified()
    summary["diagnosticsSealed"] = encrypted
    try:
        if (work() / "simulator.json").is_file():
            device, current = owned_simulator()
            if current.get("state") != "Shutdown":
                run_logged(["xcrun", "simctl", "shutdown", device["udid"]], "simulator-shutdown", 90)
            run_logged(["xcrun", "simctl", "delete", device["udid"]], "simulator-delete", 60)
    except Exception as error:
        errors.append("simulator: " + type(error).__name__)
    removals = [ROOT / "App/Resources/FighterPrivate", ROOT / TEMP_SPEC]
    if encrypted:
        removals += [p for p in work().iterdir() if p.name != "published"]
    else:
        # Never destroy the only original screenshots/logs merely because the
        # envelope failed. No plaintext upload is enabled. Private game staging,
        # temporary clear packages and build products are still removed.
        removals += [work() / name for name in ("derived", "original-overlay.enc", "original-overlay.zip",
            "delta-clear.zip", "authenticate-resources.swift", "verified-overlay", "private-evidence.zip")]
        errors.append("evidence: encrypted seal unavailable; bounded originals retained privately")
    for path in removals:
        try:
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        except OSError as error:
            errors.append("plaintext: " + type(error).__name__)
    summary["unsealedOriginalsRetainedPrivately"] = not encrypted
    summary["cleanupComplete"], summary["cleanupErrors"] = not errors, errors
    write_json(work() / "public-summary.json", summary)
    if errors:
        raise PhaseFailure("Owned cleanup incomplete or evidence not sealed; original evidence is not silently discarded")
    print("Removed this capture run's simulator, staged media, products and plaintext evidence.")


def report():
    no_resource_keys(); value = read_json(work() / "public-summary.json")
    print(json.dumps(value, ensure_ascii=False, indent=2))
    exact_fields(value, {"sourceSHA": os.environ["GITHUB_SHA"], "sourceBaselineSHA": SOURCE_BASELINE,
        "executionScope": SCOPE, "expectedNativeMethods": 0, "expectedUIMethods": 1, "selector": SELECTOR,
        "pixels": "PENDING", "historicalSuccessfulMethodsSelectedAgain": False, "productionAppChanged": False,
        "normalPresentationInternals": "notObserved", "frameOrTickProgressVerified": False,
        "normalDrawableCountersVerified": False, "liveUIValidated": False, "physicalIPhoneAcceptance": "NOT VERIFIED",
        "performanceAcceptance": False, "audiblePlayback": "NOT VERIFIED", "productionPanguAssetsActivated": False,
        "TestFlightUploaded": False}, "Final scope/acceptance differs")
    require(typed_equal(value.get("uiObservedCounts"),
        {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "result": "Passed"}),
        "A sidecar is not a structured XCTest pass")
    require(all(value.get(k) is True for k in ("resourcesAuthenticated", "compiled373ResourcesVerified", "installedBundlesVerified",
        "uiExactMethodPassed", "uiRuntimeDiagnosticGatePassed", "exactTwoOriginalNormalFramesVerified", "diagnosticsSealed", "cleanupComplete")),
        "Not every UI followup, original image, encryption and cleanup gate completed")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "tools", "stage", "build", "simulator", "ui", "recover", "seal", "cleanup", "report"))
    operation = parser.parse_args().operation
    try:
        globals()[operation]()
        return 0
    except Exception as error:
        if operation not in ("cleanup", "report"):
            try:
                if work().is_dir():
                    write_json(work() / (operation + "-failure.json"),
                        {"phase": operation, "errorType": type(error).__name__, "detail": str(error)[:4000]})
            except (OSError, KeyError, ValueError):
                pass
        print("Normal-frame capture phase failed: " + operation + "; partial evidence retained where available.", file=sys.stderr)
        return error.code if isinstance(error, PhaseFailure) else 1


if __name__ == "__main__":
    sys.exit(main())
