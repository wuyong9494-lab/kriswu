#!/usr/bin/env python3
"""One new installed scene-registration diagnostic; no UI or historical test rerun.

This entry owns its source, run, method, simulator and evidence gates. The
SHA-pinned shared-root helper supplies only reviewed resource/envelope tools;
none of its scope/identity/stage/build/test/report operations are called or
modified. Diagnostic captures remain pending human pixel review.
"""
from __future__ import annotations

import argparse
import base64
import collections
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
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
SCOPE = "installed-scene-registration-diagnostic-one"
SOURCE_BASELINE = "4bd85374273b39f61724342b7e1d72631ab2042d"
COMMIT_MESSAGE = "Diagnose installed scene registration 20261115"
HELPER = ".github/scripts/fighter_scene_registration_diagnostic.py"
CHECKS = ".github/scripts/test_fighter_scene_registration_diagnostic.py"
WORKFLOW = ".github/workflows/fighter-scene-registration-diagnostic.yml"
SWIFT_TEST = "Tests/SiteTests/DuelSceneRegistrationDiagnosticTests.swift"
CLASS_NAME = "DuelSceneRegistrationDiagnosticTests"
METHOD_NAME = "testInstalledSceneRegistrationChangesAreIsolatedAtFrameZero"
SELECTOR = "SiteTests/" + CLASS_NAME + "/" + METHOD_NAME
SELECTORS = (SELECTOR,)
SWIFT_TEST_SHA = "87c876e637fd4e6afd9656a848a302cf0813b4d46a0e6948793778622fe45e1b"
CHECKS_SHA = "fada2b290b21d49685875e0fa23b70117c1ef8a8f52440b6aa7dcb2f98b845f5"
WORKFLOW_CANONICAL_SHA = "706c346326f1b7bf324b6b63369e72c0e1f758ae0fc407149e2ad8cf928f8202"
HELPER_PIN_FIELD = '      EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256: "'
REVIEWED_ENTRIES = {
    "App": "c817ebac7b8cf6c491fbcb354b993420764ea4d8",
    "Package.swift": "ffc64914ed88ae83bb4569fea0777b08ea2d29b6",
    "Shared": "e41e160b4262a9defbb3c5e92b4d020c5e0c2b80",
    "Sources": "e151525e2b8db6592379a120bfe1007c3e0edc41",
    "Widget": "dc5c0075ea1fb8ed0a44c68f2fea21dfc92112d3",
    "project.yml": "4659145612fbca682db5fb915784d9c6e9dc8cab",
    "scripts": "64730d41241222d66e0837afdd50ae3b813be83d",
}
OTHER_TESTS_SHA = "40b9a4796c2a4ff7f5f4a7b3eaf8238db9db469dae2616a48a994745e7737e58"
OTHER_CI_SCRIPTS_SHA = "3d5d1fc1ded4a6a91970f60fb2e3a643129c9c156ea04689a1bd6c58e40e96d7"
OTHER_WORKFLOWS_SHA = "bebe4e9fd033320ebfd9dca0614d562935db5be3c0aa3ee2a8758fafc1da1a82"
RESOURCE_TOOLS = ".github/scripts/fighter_shared_root_native.py"
RESOURCE_TOOLS_SHA = "945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036"
RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
DELTA_MANIFEST_SHA = "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")
FRAME_LABELS = ("registration-base-before", "registration-original-projector", "registration-original-rebound", "registration-fresh-associated")
REPORT_LABEL = "scene-registration-diagnostic-report"
EXPECTED_ATTACHMENTS = {**{label: "image" for label in FRAME_LABELS}, REPORT_LABEL: "data"}
REPORT_SCHEMA = "fighter-scene-registration-diagnostic-v1"
# Exact per-capture contract from the independently reviewed Swift report.
CAPTURE_ISOLATION = (
    "cold original surface; original projector detached before first explicit draw; no fresh renderer",
    "same original projector restored; no active-renderer rebind or fresh renderer",
    "same active renderer rebound to the same scene and camera; original projector retained",
    "one fresh renderer associated without preparing or rendering; original surface and projector still capture",
)
CAPTURE_PROJECTOR_STATES = (False, True, True, True)
CAPTURE_REBIND_COUNTS = (0, 0, 1, 1)
CAPTURE_FRESH_COUNTS = (0, 0, 0, 1)
METAL_DIAGNOSTICS = {
    "doublePresent": "Each CAMetalLayerDrawable can only be presented once!",
    "textureAfterPresent": "[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.",
}
RUNTIME_OK = "Complete owned diagnostic invocation log; zero known drawable diagnostics. Pixels pending.\n"
TEMP_SPEC = "project.scene-registration-diagnostic.yml"
STEM = "fighter-scene-registration-diagnostic-evidence"
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


def work():
    parent = Path(os.environ["RUNNER_TEMP"])
    require(parent.is_absolute() and not parent.is_symlink(), "Unsafe runner directory")
    directory = parent / "fighter-scene-registration-diagnostic"
    require(not directory.is_symlink(), "Unsafe diagnostic directory")
    return directory


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


def normalized_workflow(raw):
    value = raw.decode("utf-8")
    pattern = re.compile(r"^" + re.escape(HELPER_PIN_FIELD) + r'([a-f0-9]{64})"$', re.M)
    matches = list(pattern.finditer(value))
    require(len(matches) == 1 and value.count("EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256") == 1,
            "Workflow must have one exact helper-pin field")
    match = matches[0]
    return (value[:match.start(1)] + "0" * 64 + value[match.end(1):]).encode(), match.group(1)


def pin_sources():
    pinned(SWIFT_TEST, SWIFT_TEST_SHA)
    pinned(CHECKS, CHECKS_SHA)
    normalized, helper_sha = normalized_workflow(regular(ROOT / WORKFLOW, 64 * 1024).read_bytes())
    require(sha(normalized) == WORKFLOW_CANONICAL_SHA and helper_sha == digest(Path(__file__))
            and os.environ.get("EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256") == helper_sha,
            "Workflow, helper or exact helper-pin environment differs")
    resource_tools()


def selected_inventory():
    source = regular(ROOT / SWIFT_TEST, 512 * 1024).read_text()
    require(re.search(r"\bclass\s+" + CLASS_NAME + r"\b", source), "Selected class missing")
    require(re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M) == [METHOD_NAME]
            and "XCTSkip" not in source, "Only the one new no-skip diagnostic method may be selected")
    return [{"identifier": SELECTOR, "sourceFile": SWIFT_TEST, "sourceSHA256": digest(ROOT / SWIFT_TEST)}]


def retained_tree_digest(rows, excluded):
    names = [row.split(b"\t", 1)[1].decode() for row in rows.splitlines()]
    require(set(excluded) <= set(names), "A new pinned file is absent from the committed tree")
    return sha(b"".join(row + b"\n" for row, name in zip(rows.splitlines(), names) if name not in excluded))


def validate_source_trees(entries, tests, ci_scripts, workflows):
    require(entries == REVIEWED_ENTRIES, "App/Core/build/resource scripts changed from the 4bd85374 baseline")
    require(retained_tree_digest(tests, {SWIFT_TEST}) == OTHER_TESTS_SHA, "An existing test changed")
    require(retained_tree_digest(ci_scripts, {HELPER, CHECKS}) == OTHER_CI_SCRIPTS_SHA,
            "An existing CI helper changed")
    require(retained_tree_digest(workflows, {WORKFLOW}) == OTHER_WORKFLOWS_SHA, "An existing workflow changed")


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


def source_gate():
    raw = subprocess.check_output(["git", "ls-tree", "HEAD", *REVIEWED_ENTRIES], cwd=ROOT, text=True)
    entries = {row.split("\t")[1]: row.split("\t")[0].split()[2] for row in raw.splitlines()}
    rows = [subprocess.check_output(["git", "ls-tree", "-r", "HEAD", path], cwd=ROOT)
            for path in ("Tests", ".github/scripts", ".github/workflows")]
    validate_source_trees(entries, *rows)
    pin_sources()
    selected_inventory()
    paths = ("App", "Sources", "Shared", "Widget", "Tests", "scripts", ".github/scripts", ".github/workflows")
    for options in (("--others", "--exclude-standard"), ("--others", "--ignored", "--exclude-standard")):
        require(not subprocess.check_output(["git", "ls-files", *options, "--", *paths], cwd=ROOT).strip(),
                "Untracked or ignored files could alter discovered build inputs")
    require(not subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT).strip(),
            "Tracked modifications exist before preparation")


def preserved_prior_evidence():
    return [
        {"runID": "43611931466", "sourceSHA": "ef3064085879c497d59533459c94b429a40f9cee", "passedMethods": 117,
         "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43644209347", "sourceSHA": "68f1e7de45351c3e4b2607c56ff8ab111d0c7130", "passedMethods": 5,
         "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43647414701", "sourceSHA": "5788ebb1001a6e0f31c5208cb2b955b48b00741c", "passedMethods": 6,
         "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43658526616", "sourceSHA": "cdd0d496bf63fd186de6f8d9cf91646c1dc88917", "passedMethods": 1,
         "pixels": "FAILED", "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43661312798", "sourceSHA": "00442b097747d95308ca69339fa999a46c216bc6", "passedMethods": 1,
         "productionPixels": "NOT_VERIFIED", "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43664242283", "sourceSHA": "4bd85374273b39f61724342b7e1d72631ab2042d", "passedMethods": 1,
         "pixels": "FAILED", "selectedAgain": False, "countsBelongToCurrentRun": False},
    ]


def identity():
    value = read_json(work() / "identity.json")
    require(value.get("sourceSHA") == os.environ["GITHUB_SHA"] and value.get("runID") == os.environ["GITHUB_RUN_ID"]
            and value.get("attempt") == os.environ["GITHUB_RUN_ATTEMPT"] and value.get("executionScope") == SCOPE
            and value.get("sourceBaselineSHA") == SOURCE_BASELINE and value.get("selectors") == selected_inventory()
            and value.get("expectedNativeMethods") == 1 and value.get("uiExecutionStatus") == "not_selected"
            and value.get("expectedUIMethods") == 0 and value.get("uiSelectors") == []
            and value.get("expectedSimulationFrames") == [0] and value.get("expectedSimulationAdvanceCalls") == 0
            and value.get("reportSchema") == REPORT_SCHEMA and value.get("expectedCaptureLabels") == list(FRAME_LABELS)
            and value.get("expectedActiveRendererPrepareCalls") == 0
            and value.get("expectedOriginalRendererRebindCalls") == 1
            and value.get("expectedFreshRendererCreateCalls") == 1
            and value.get("expectedFreshRendererAssociationCalls") == 1
            and value.get("expectedFreshRendererRenderCalls") == 0 and value.get("expectedSnapshotCalls") == 0
            and value.get("expectedSourceProjectorStates") == list(CAPTURE_PROJECTOR_STATES)
            and value.get("helperSHA256") == digest(Path(__file__))
            and value.get("workflowSHA256") == digest(ROOT / WORKFLOW)
            and value.get("assetReleaseSHA256") == RELEASE_SHA, "Prepared diagnostic identity changed")
    pin_sources()
    return value


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
    write_json(work() / "identity.json", {
        "sourceSHA": actual, "sourceBaselineSHA": SOURCE_BASELINE, "reviewedEntries": REVIEWED_ENTRIES,
        "executionScope": SCOPE, "runID": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "ref": BRANCH, "selectors": selected_inventory(), "expectedNativeMethods": 1,
        "nativeExecutionStatus": "selected", "uiSelectors": [], "expectedUIMethods": 0,
        "uiExecutionStatus": "not_selected", "preservedPriorEvidence": preserved_prior_evidence(),
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedActiveRendererPrepareCalls": 0, "expectedOriginalRendererRebindCalls": 1,
        "expectedFreshRendererCreateCalls": 1, "expectedFreshRendererAssociationCalls": 1,
        "expectedFreshRendererRenderCalls": 0, "expectedSnapshotCalls": 0,
        "expectedSourceProjectorStates": list(CAPTURE_PROJECTOR_STATES),
        "sourceMapping": "All App/Core/build inputs match 4bd85374; one new exact diagnostic test and three independent CI files only",
        "assetReleaseSHA256": RELEASE_SHA, "deltaManifestSHA256": DELTA_MANIFEST_SHA,
        "helperSHA256": digest(Path(__file__)), "workflowSHA256": digest(ROOT / WORKFLOW),
        "resourceToolsSHA256": RESOURCE_TOOLS_SHA, "recipientSPKISHA256": RECIPIENT_SPKI_SHA,
        "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "pixels": "PENDING", "physicalDevice": False, "TestFlight": False,
    })
    write_json(work() / "expected-resources.json", rows)
    print("Pinned one new installed native diagnostic; UI and historical methods not selected; final 373 resources unchanged.")


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


def build():
    no_resource_keys()
    identity()
    once("build")
    require((work() / "stage-ok.json").is_file(), "Authenticated resources required")
    project = ROOT / "project.yml"
    original = project.read_bytes()
    source = original.decode()
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    require(source.count(needle) == 1, "Existing SiteTests host scheme is ambiguous")
    generated = source.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true')
    spec = ROOT / TEMP_SPEC
    require(not spec.exists() and not spec.is_symlink(), "Temporary diagnostic spec exists")
    spec.write_text(generated)
    write_json(work() / "compiled-project.json", {"originalSHA256": sha(original), "generatedSHA256": digest(spec),
        "onlyProjectConfigurationChange": "Add -demo to the existing ShiftReminder host scheme; SiteTests only",
        "scheme": "ShiftReminder", "trackedProjectModified": False, "uiTargetSelected": False,
        "signingAllowed": False, "releaseSHA256": RELEASE_SHA})
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate", "--spec", spec.name], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
                "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY=", "FIGHTER_ASSET_RELEASE_SHA256=" + RELEASE_SHA], "native-build", 1200)
    products = work() / "derived/Build/Products"
    runs = list(products.glob("*.xctestrun"))
    require(len(runs) == 1, "Ambiguous build-for-testing result")
    targets = resource_tools().dependencies().test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    require(len(targets) == 1 and targets[0].get("BlueprintName") == "SiteTests"
            and not targets[0].get("IsUITestBundle", False) and "-demo" in targets[0].get("CommandLineArguments", [])
            and not targets[0].get("SkipTestIdentifiers"), "Only the existing native host target may be built for testing")
    bundles = list(products.rglob("*.xctest"))
    require(bundles and {p.name for p in bundles} == {"SiteTests.xctest"}, "Unexpected UI or other test bundle")
    require(project.read_bytes() == original, "Tracked project specification changed")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    audit_resources(app, read_json(work() / "expected-resources.json"), bundled=True)
    info = plistlib.loads(regular(app / "Info.plist", 1024**2).read_bytes())
    require(info.get("FighterAssetReleaseSHA256") == RELEASE_SHA and info.get("ArenaCommitSHA") == os.environ["GITHUB_SHA"]
            and info.get("CFBundleIdentifier") == "com.kriswu.shiftreminder", "Compiled App source or release differs")
    require(not any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()),
            "Ciphertext or key material entered the App")
    (work() / "build-ok.txt").write_text("One unsigned native host build; 373 compiled resources verified; no UI target.\n")
    print("Built one unsigned SiteTests host and verified all 373 compiled resources; UI target not selected.")


def simulator_name():
    return "Fighter scene registration diagnostic " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]


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


def verify_results(summary, data, device):
    for key, value in (("totalTestCount", 1), ("passedTests", 1), ("failedTests", 0), ("skippedTests", 0)):
        require(type(summary.get(key)) is int and summary[key] == value, "Exact diagnostic count differs: " + key)
    require(summary.get("result") == "Passed" and isinstance(data.get("testNodes"), list), "An executed diagnostic must actually pass")
    seen = []

    def walk(nodes):
        require(isinstance(nodes, list), "Malformed result children")
        for node in nodes:
            require(isinstance(node, dict), "Malformed result node")
            if node.get("nodeType") == "Test Case":
                raw = node.get("nodeIdentifier")
                require(isinstance(raw, str) and raw.removesuffix("()") in (SELECTOR, CLASS_NAME + "/" + METHOD_NAME)
                        and node.get("result") == "Passed", "Unexpected, skipped or failed diagnostic method")
                seen.append(SELECTOR)
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    require(seen == [SELECTOR], "Missing, duplicate or additional method")
    configurations = summary.get("devicesAndConfigurations")
    require(isinstance(configurations, list) and len(configurations) == 1, "Exactly one result device is required")
    configuration = configurations[0]
    observed = configuration.get("device", {})
    require(observed.get("deviceId") == device["udid"] and observed.get("deviceName") == device["name"]
            and observed.get("modelName") == "iPhone 17 Pro Max" and observed.get("platform") == "iOS Simulator"
            and all(type(configuration.get(key)) is int and configuration[key] == value for key, value in
                    (("passedTests", 1), ("failedTests", 0), ("skippedTests", 0))), "Result device or its counts differ")


def execute_native():
    no_resource_keys()
    identity()
    once("native")
    require((work() / "build-ok.txt").is_file(), "Verified build required")
    device = read_json(work() / "simulator.json")
    command = ["xcodebuild", "test-without-building", "-xctestrun", (work() / "xctestrun-path.txt").read_text(),
               "-destination", "id=" + device["udid"], "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(work() / "native.xcresult"), "-only-testing:" + SELECTOR]
    code = run_logged(command, "selected-native", 720, check=False)
    result = {"exitCode": code, "selectedCount": 1, "iterations": 1, "exports": {}}
    write_json(work() / "native-process.json", result)
    if (work() / "native.xcresult/Info.plist").is_file():
        for kind in ("summary", "tests"):
            try:
                result["exports"][kind] = run_logged(["xcrun", "xcresulttool", "get", "test-results", kind,
                    "--path", str(work() / "native.xcresult")], "native-result-" + kind, 60, check=False,
                    output_name="native-" + kind + ".json")
            except Exception as error:
                result["exports"][kind] = type(error).__name__
    write_json(work() / "native-process.json", result)
    if code:
        raise PhaseFailure("Diagnostic invocation failed; original process code and failure bodies retained", code)
    require(result["exports"] == {"summary": 0, "tests": 0}, "Result exports unavailable")
    verify_results(read_json(work() / "native-summary.json"), read_json(work() / "native-tests.json"), device)
    (work() / "native-ok.txt").write_text("1 passed; 0 failed; 0 skipped; exactly the one new diagnostic once. Pixels pending.\n")
    print("New diagnostic XCTest: 1 passed, 0 failed, 0 skipped; UI and historical methods not selected; pixels pending.")


def verify_runtime_log(path, *, collection_code, device, started, finished):
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
        "coverage": "Full new diagnostic invocation through result export; complete source scanned before sealing",
        "sourceBytes": len(raw), "sourceSHA256": sha(raw), "entries": len(events), "appEntries": len(stamps),
        "firstAppEntryUTC": min(stamps).isoformat(), "lastAppEntryUTC": max(stamps).isoformat(),
        "knownDiagnosticCounts": counts, "knownDiagnosticCount": sum(counts.values()),
        "knownDiagnosticsAbsent": not any(counts.values()), "sealedTextTailOnly": len(raw) > 2 * 1024**2,
        "pixels": "PENDING", "liveUIValidated": False, "performanceAcceptance": False}


def collect_runtime(started, finished):
    device = read_json(work() / "simulator.json")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True, timeout=30))
    matches = [d for rows in catalog["devices"].values() for d in rows if d.get("udid") == device["udid"]]
    require(len(matches) == 1 and matches[0].get("name") == device["name"], "Runtime device ownership differs")
    low = started.replace(microsecond=0)
    high = finished.replace(microsecond=0) + datetime.timedelta(seconds=1)
    code = run_logged(["xcrun", "simctl", "spawn", device["udid"], "log", "show", "--start",
                       low.strftime("%Y-%m-%d %H:%M:%S%z"), "--end", high.strftime("%Y-%m-%d %H:%M:%S%z"),
                       "--style", "json", "--predicate", 'process == "ShiftReminder"'], "runtime-log", 60, check=False)
    receipt = verify_runtime_log(work() / "runtime-log.log", collection_code=code, device=device, started=started, finished=finished)
    write_json(work() / "runtime-diagnostics.json", receipt)
    require(receipt["knownDiagnosticsAbsent"], "Known drawable diagnostic occurred; full counts retained")
    (work() / "runtime-ok.txt").write_text(RUNTIME_OK)


def test():
    started, failure = datetime.datetime.now(datetime.timezone.utc), None
    try:
        execute_native()
    except Exception as error:
        failure = error
    try:
        collect_runtime(started, datetime.datetime.now(datetime.timezone.utc))
    except Exception as error:
        write_json(work() / "runtime-failure.json", {"errorType": type(error).__name__, "detail": str(error)[:2000]})
        if failure is None:
            failure = error
    if failure is not None:
        raise failure


def validate_report(value, images):
    """Join four original-surface images to one cold registration sequence.

    Image equality and normal submission after explicit draw are observations.
    No successful image, forced drawable submission or ARC destruction is inferred.
    """
    def integer(row, key, expected):
        return type(row.get(key)) is int and row[key] == expected

    def zeros(row, fields):
        return all(integer(row, key, 0) for key in fields)

    def nonnegative(number):
        return type(number) is int and number >= 0

    def nullable_int(row, key):
        return key in row and (row[key] is None or nonnegative(row[key]))

    def finite(number):
        return type(number) in (int, float) and math.isfinite(number)

    def vector(values, length):
        return isinstance(values, list) and len(values) == length and all(finite(n) for n in values)

    def fresh_state(row, created):
        if not created:
            return row == {"created": False, "testStrongReferencePresent": False} and all(type(v) is bool for v in row.values())
        return (isinstance(row, dict) and all(row.get(k) is True for k in ("created", "testStrongReferencePresent",
            "distinctFromActiveRenderer", "sameDevice", "sameScene", "samePointOfView", "delegateAbsent"))
            and all(row.get(k) is False for k in ("usesReverseZ", "autoenablesDefaultLighting", "isPlaying"))
            and zeros(row, ("renderCalls", "prepareCalls", "snapshotCalls")))

    require(isinstance(value, dict) and value.get("schema") == REPORT_SCHEMA and integer(value, "schemaVersion", 1)
            and value.get("scope") == SCOPE and value.get("releaseSHA256") == RELEASE_SHA,
            "Registration diagnostic schema, scope or release differs")
    require(value.get("diagnosticCompleted") is True and value.get("lastPhase") == "diagnostic-completed-pixels-pending"
            and value.get("pixels") == "PENDING" and value.get("stateInvariant") is True and value.get("restorationInvariant") is True
            and value.get("captureLabels") == list(FRAME_LABELS) and value.get("expectedSimulationFrames") == [0]
            and type(value["expectedSimulationFrames"][0]) is int
            and all(integer(value, k, 1) for k in ("explicitDrawStateCalls", "activeSceneRebindCalls",
                "freshRendererCreationCalls", "freshAssociationCalls"))
            and zeros(value, ("simulationAdvanceCalls", "explicitPrepareCalls", "freshRenderCalls", "freshPrepareCalls",
                "freshSnapshotCalls", "snapshotCalls")), "Frame-zero registration sequence did not complete exactly once")
    require(all(value.get(k) is False for k in ("combatStateInjected", "liveDisplayLinkAdvancesSelected", "sceneKitLightsChanged",
                "freshRendererUsedForCapture", "postFreshDetachmentCaptureTaken", "physicalDeviceValidated", "liveUIValidated",
                "audiblePlaybackVerified", "performanceVerified", "panguEquipmentActivated"))
            and value.get("sourcePacketsExpectedZero") is True and value.get("captureTimingIncludesGPUReadbackWait") is True
            and value.get("uiExecutionStatus") == "not_selected" and value.get("sourceProjectorRemovedBeforeFirstExplicitDraw") is True,
            "Registration diagnostic overclaims its scope or lost the unprojected first draw")
    states = value.get("captureSourceProjectorStates")
    require(isinstance(states, list) and len(states) == 4
            and all(type(x) is bool and x is expected for x, expected in zip(states, CAPTURE_PROJECTOR_STATES)),
            "Source-projector schedule differs")
    require(integer(value, "surfaceSubmittedFramesBeforeExperiment", 0)
            and nullable_int(value, "surfaceLastSubmittedTickBeforeExperiment")
            and nonnegative(value.get("surfaceSubmittedFramesAfterExplicitDraw"))
            and nullable_int(value, "surfaceLastSubmittedTickAfterExplicitDraw"),
            "The initial normal-submission boundary or its observations are invalid")
    submitted_after = value["surfaceSubmittedFramesAfterExplicitDraw"]
    tick_after = value["surfaceLastSubmittedTickAfterExplicitDraw"]
    require(finite(value.get("elapsedSeconds")) and value["elapsedSeconds"] >= 0, "Invalid elapsed time")
    timings = value.get("timings")
    require(isinstance(timings, list) and timings and all(isinstance(t, dict) and isinstance(t.get("phase"), str)
            and t["phase"] and finite(t.get("seconds")) and t["seconds"] >= 0 for t in timings), "Invalid timing records")
    operations = value.get("registrationOperations")
    require(isinstance(operations, list) and len(operations) == 2, "Exactly two registration operations are required")
    for i, (operation, name, phase) in enumerate(zip(operations,
            ("rebind-active-scene", "associate-fresh-renderer"), ("rebind-active-scene-once", "associate-fresh-renderer-once"))):
        require(isinstance(operation, dict) and integer(operation, "order", i + 1) and operation.get("operation") == name
                and integer(operation, "calls", 1) and operation.get("beforeCaptureLabel") == FRAME_LABELS[i + 1]
                and operation.get("afterCaptureLabel") == FRAME_LABELS[i + 2]
                and finite(operation.get("seconds")) and operation["seconds"] >= 0
                and all(operation.get(k) is True for k in ("sameActiveRendererAfter", "sameSceneAfter",
                    "samePointOfViewAfter", "sameOriginalProjectorAfter")), "Registration operation identity or ownership differs")
        observed = [t for t in timings if t["phase"] == phase]
        require(len(observed) == 1 and observed[0]["seconds"] == operation["seconds"], "Registration timing or multiplicity differs")
    require(operations[0].get("nilSceneObserved") is True and integer(operations[1], "creationCalls", 1)
            and fresh_state(operations[1].get("freshRenderer"), True), "Rebinding or nonrendering association was not observed")
    cleanup = value.get("cleanup")
    require(isinstance(cleanup, dict) and all(cleanup.get(k) is True for k in ("sceneReleased", "surfaceReleased", "rendererReleased",
                "sourceProjectorRestoredBeforeShutdown", "originalSceneAndPointOfViewRestoredBeforeShutdown",
                "freshBindingsClearedBeforeShutdown", "freshTestReferenceClearedBeforeShutdown"))
            and cleanup.get("freshObjectDeallocationVerified") is False
            and nonnegative(cleanup.get("activeClocksBefore")) and type(cleanup.get("activeClocksAfter")) is int
            and cleanup["activeClocksAfter"] == cleanup["activeClocksBefore"], "Owner restoration or bounded fresh cleanup failed")
    captures, samples = value.get("captures"), value.get("samples")
    require(isinstance(captures, list) and len(captures) == 4 and isinstance(samples, list) and len(samples) == 4
            and set(images) == set(FRAME_LABELS), "Registration image closure differs")
    first_model_camera, first_lights, first_fighters, first_readiness, encoded_projector = None, None, None, None, None
    for i, (capture, sample, label) in enumerate(zip(captures, samples, FRAME_LABELS)):
        image = images[label]
        require(isinstance(capture, dict) and isinstance(sample, dict) and capture.get("label") == sample.get("label") == label
                and zeros(capture, ("frame", "animationTick", "sourceLiveTick", "submittedPackets"))
                and zeros(sample, ("frame", "animationTick", "sourceLiveTick", "displayLinkCallbacks", "submittedPackets")),
                "A capture advanced gameplay, clock or packets")
        for row in (capture, sample):
            require(row.get("rendererRoute") == "surface.captureFrame"
                    and row.get("sourceProjectorInstalled") is CAPTURE_PROJECTOR_STATES[i]
                    and row.get("projectorEncodedForCapture") is CAPTURE_PROJECTOR_STATES[i]
                    and integer(row, "activeSceneRebindCallsSoFar", CAPTURE_REBIND_COUNTS[i])
                    and integer(row, "freshRendererCreationCallsSoFar", CAPTURE_FRESH_COUNTS[i])
                    and integer(row, "freshAssociationCallsSoFar", CAPTURE_FRESH_COUNTS[i])
                    and integer(row, "requestedSurfaceSamples", 2) and integer(row, "resolvedSurfaceSamples", 4)
                    and integer(row, "surfaceSubmittedFrames", submitted_after)
                    and nullable_int(row, "surfaceLastSubmittedTick") and row["surfaceLastSubmittedTick"] == tick_after,
                    "Wrong capture route, order, projector state, sampling or normal-submission snapshot")
        require(capture.get("isolation") == CAPTURE_ISOLATION[i] and capture.get("pngSHA256") == image["sha256"]
                and type(capture.get("bytes")) is int and capture["bytes"] == image["bytes"]
                and integer(capture, "width", 956) and image["width"] == 956
                and integer(capture, "height", 440) and image["height"] == 440
                and capture.get("pixelsRequireReview") is True and capture.get("simulationAndModelCameraUnchanged") is True,
                "Original PNG identity or invariant metadata differs")
        require(all(sample.get(k) is True for k in ("sameActiveSurface", "sameActiveRenderer", "sameScene", "samePointOfView",
                "modelObjectIdentityUnchanged", "simulationInvariant", "sourceIntroActive"))
                and sample.get("sourceStance") == "firstBirth" and integer(sample, "sourceStanceTick", 0)
                and sample.get("sourceEffectIDs") == [] and all(sample.get(k) == "" for k in
                    ("rendererFailure", "surfaceFailure", "sourcePreparationFailure")), "Original objects or source state differ")
        require(all(sample.get(k) is False for k in ("rendererUsesReverseZ", "rendererAutoenablesDefaultLighting", "rendererIsPlaying"))
                and all(type(sample.get(k)) is bool for k in ("weaponReady", "branchesReady")), "Renderer flags or readiness are invalid")
        viewport, camera = sample.get("viewport"), sample.get("camera")
        require(isinstance(viewport, dict) and all(finite(viewport.get(k)) and viewport[k] == expected for k, expected in
                (("pointsWidth", 956), ("pointsHeight", 440), ("captureWidth", 956), ("captureHeight", 440)))
                and all(finite(viewport.get(k)) and viewport[k] > 0 for k in
                    ("drawableWidth", "drawableHeight", "viewScale", "surfaceScale")), "Viewport evidence differs")
        require(isinstance(camera, dict) and vector(camera.get("modelWorldTransform"), 16)
                and vector(camera.get("presentationWorldTransform"), 16) and vector(camera.get("metalProjection"), 16)
                and isinstance(camera.get("model"), dict) and isinstance(camera.get("presentation"), dict), "Camera observations are incomplete")
        model = camera["model"]
        require(model.get("exists") is True and finite(model.get("fieldOfView")) and type(model.get("categoryMask")) is int,
                "Model camera identity is absent")
        model_camera = (camera["modelWorldTransform"], model["fieldOfView"], model["categoryMask"])
        lights, fighters, inventory = sample.get("lights"), sample.get("fighters"), sample.get("sceneInventory")
        require(isinstance(lights, list) and all(isinstance(light, dict) for light in lights)
                and isinstance(fighters, list) and len(fighters) == 2
                and all(isinstance(fighter, dict) and integer(fighter, "index", j) for j, fighter in enumerate(fighters))
                and isinstance(inventory, list) and inventory and all(isinstance(row, dict) for row in inventory),
                "Light, fighter or scene observations are incomplete")
        readiness = (sample["weaponReady"], sample["branchesReady"])
        if i == 0:
            first_model_camera, first_lights, first_fighters, first_readiness = model_camera, lights, fighters, readiness
        require(model_camera == first_model_camera and lights == first_lights and fighters == first_fighters
                and readiness == first_readiness, "Model camera, lights, fighters or readiness changed")
        frame = sample.get("projectorLastFrame")
        require(isinstance(frame, dict) and type(frame.get("available")) is bool, "Projector observation missing")
        if frame["available"]:
            require(integer(frame, "tick", 0) and finite(frame.get("aspect")) and frame["aspect"] > 0
                    and vector(frame.get("sourceCameraPosition"), 3)
                    and all(vector(frame.get(k), 16) for k in ("sourceView", "sourceProjection", "sourceShadowMatrix"))
                    and all(nonnegative(frame.get(k)) for k in ("casterCount", "triangleCount"))
                    and isinstance(frame.get("factors"), list) and all(finite(n) for n in frame["factors"]),
                    "Retained projector metadata is incomplete")
        else:
            require(i == 0 and frame == {"available": False}, "Only the first unprojected capture may lack lastFrame")
        if i > 0:
            require(frame["available"], "Installed original projector has no encoded frame")
            if i == 1:
                encoded_projector = frame
            require(frame == encoded_projector, "Original projector metadata changed across B/C/D")
        fresh = sample.get("freshRenderer")
        require(fresh_state(fresh, i == 3), "Fresh renderer was created early or used for rendering")
        if i == 3:
            require(fresh == operations[1]["freshRenderer"], "Fresh association receipt differs from capture D")
    equalities = value.get("adjacentPNGEqualities")
    require(isinstance(equalities, list) and len(equalities) == 3
            and all(type(x) is bool and x == (images[FRAME_LABELS[i]]["sha256"] == images[FRAME_LABELS[i + 1]]["sha256"])
                for i, x in enumerate(equalities)), "Adjacent PNG observations conflict with original bytes")
    return {"registrationSequenceVerified": True, "originalRendererRebindCalls": 1, "freshRendererCreatedCount": 1,
            "freshRendererAssociatedCount": 1, "freshRendererRenderCalls": 0, "prepareCalls": 0, "snapshotCalls": 0,
            "surfaceSubmittedFramesBeforeExperiment": 0, "surfaceSubmittedFramesAfterExplicitDraw": submitted_after,
            "surfaceLastSubmittedTickAfterExplicitDraw": tick_after, "adjacentPNGEqualities": equalities}


def attachment_files(directory):
    require(directory.is_dir() and not directory.is_symlink(), "Unsafe attachment directory")
    paths, total = [], 0
    for path in sorted(directory.rglob("*")):
        info = path.lstat()
        require(not stat.S_ISLNK(info.st_mode), "Attachment symlink is forbidden")
        if stat.S_ISDIR(info.st_mode):
            continue
        require(stat.S_ISREG(info.st_mode) and info.st_size <= 128 * 1024**2, "Attachment type or individual bound differs")
        paths.append(path)
        total += info.st_size
    require(1 <= len(paths) <= 512 and total <= 384 * 1024**2, "Attachment count or aggregate bound exceeded")
    return paths


def attachment_label(item, path):
    human, suffix = item.get("suggestedHumanReadableName", ""), path.suffix.lower()
    return [label for label in EXPECTED_ATTACHMENTS if isinstance(human, str) and re.fullmatch(
        re.escape(label) + r"(?:_[0-9]+_[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})?" + re.escape(suffix), human)]


def attachment_inventory(directory, device):
    paths = attachment_files(directory)
    groups = read_json(directory / "manifest.json", 24 * 1024**2)
    require(isinstance(groups, list), "Unexpected attachment manifest")
    labels, seen, entries, automatic, images = set(), set(), [], [], {}
    diagnostic = None
    mandatory_bytes, automatic_bytes = 0, 0
    for group in groups:
        require(isinstance(group, dict) and isinstance(group.get("attachments"), list), "Malformed attachment group")
        identifier = group.get("testIdentifier", "")
        require(isinstance(identifier, str), "Malformed attachment owner")
        identifier = identifier.removesuffix("()")
        for item in group["attachments"]:
            require(isinstance(item, dict), "Malformed attachment record")
            name = item.get("exportedFileName", "")
            require(isinstance(name, str) and name and Path(name).name == name and "\\" not in name
                    and ".." not in name and name not in seen, "Unsafe or repeated attachment filename")
            path = directory / name
            require(path in paths, "Missing manifest attachment")
            seen.add(name)
            candidates = attachment_label(item, path)
            if not candidates:
                automatic_bytes += path.stat().st_size
                automatic.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path), "countsAsCoverage": False})
                continue
            require(len(candidates) == 1 and candidates[0] not in labels, "Duplicate required attachment label")
            label = candidates[0]
            require(identifier in (SELECTOR, CLASS_NAME + "/" + METHOD_NAME) and item.get("deviceId") == device["udid"]
                    and item.get("deviceName") == device["name"], "Required attachment owner or device differs")
            regular(path, 24 * 1024**2)
            suffix, kind = path.suffix.lower(), EXPECTED_ATTACHMENTS[label]
            if kind == "image":
                require(suffix == ".png", "Expected original PNG evidence")
                images[label] = resource_tools().png_metadata(path)
            else:
                require(suffix in (".json", ".txt"), "Expected JSON diagnostic report")
                diagnostic = read_json(path)
            labels.add(label)
            mandatory_bytes += path.stat().st_size
            entries.append({"label": label, "selector": SELECTOR, "file": name, "kind": kind,
                            "bytes": path.stat().st_size, "sha256": digest(path)})
    require(labels == set(EXPECTED_ATTACHMENTS), "Missing required diagnostic captures or report")
    registration_observations = validate_report(diagnostic, images)
    require(mandatory_bytes <= 160 * 1024**2 and automatic_bytes <= 256 * 1024**2, "Evidence category exceeds bounded budget")
    return {"completeExpectedLabels": True, "exactMethodAndSimulatorOwnership": True, "files": entries,
            "automaticDiagnostics": automatic, "automaticAttachmentsNeverCountAsCoverage": True,
            "registrationObservations": registration_observations, "pixels": "PENDING"}


def export():
    no_resource_keys()
    identity()
    once("export")
    result = work() / "native.xcresult"
    require((result / "Info.plist").is_file(), "Native result bundle unavailable")
    directory = work() / "native-attachments"
    run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                "--output-path", str(directory)], "native-export-attachments", 180)
    try:
        receipt = attachment_inventory(directory, read_json(work() / "simulator.json"))
        write_json(work() / "attachments-ok.json", receipt)
    except Exception as error:
        write_json(work() / "attachments-failure.json", {"errorType": type(error).__name__, "detail": str(error)[:2000]})
        raise
    print("Exported four exact method/device-owned PNGs and the diagnostic report; human pixel review remains pending.")


def bounded_attachments():
    directory = work() / "native-attachments"
    paths = attachment_files(directory) if directory.exists() else []
    manifest = directory / "manifest.json"
    priority = {manifest} if manifest in paths else set()
    if manifest in paths and 0 < manifest.stat().st_size <= 24 * 1024**2:
        try:
            groups = read_json(manifest, 24 * 1024**2)
            for group in groups if isinstance(groups, list) else []:
                for item in group.get("attachments", []) if isinstance(group, dict) else []:
                    if not isinstance(item, dict):
                        continue
                    name = item.get("exportedFileName")
                    path = directory / name if isinstance(name, str) else None
                    if path in paths and attachment_label(item, path):
                        priority.add(path)
        except (OSError, ValueError, TypeError):
            pass
    receipt_path = work() / "attachments-ok.json"
    required = set()
    if receipt_path.is_file():
        receipt = read_json(receipt_path)
        required = {directory / row["file"] for row in receipt["files"]} | {manifest}
        priority.update(required)
    selected, omitted, total = [], [], 0
    for path in sorted(paths, key=lambda p: (p not in priority, p.as_posix())):
        size, suffix = path.stat().st_size, path.suffix.lower()
        reason = ("unsupported-media-type" if suffix not in (".png", ".json", ".txt") else
                  "empty-system-record" if not size else "sealed-file-limit" if size > 24 * 1024**2 else
                  "sealed-total-or-count-limit" if total + size > 160 * 1024**2 or len(selected) >= 256 else None)
        if reason:
            omitted.append({"file": path.relative_to(directory).as_posix(), "bytes": size, "sha256": digest(path),
                            "reason": reason, "mandatoryLabelCandidate": path in priority, "countsAsCoverage": False})
            continue
        total += size
        selected.append((path, "native-attachments/" + path.relative_to(directory).as_posix()))
    complete = bool(required) and required <= {path for path, _ in selected}
    write_json(work() / "attachment-seal-policy.json", {"selectedFileCount": len(selected), "selectedBytes": total,
        "omittedFileCount": len(omitted), "omitted": omitted, "mandatoryValidationPassed": receipt_path.is_file(),
        "completeValidatedMandatorySetSealed": complete, "automaticAttachmentsNeverCountAsCoverage": True})
    return selected


def runtime_summary():
    try:
        value = read_json(work() / "runtime-diagnostics.json")
        device = read_json(work() / "simulator.json")
        source, marker = work() / "runtime-log.log", work() / "runtime-ok.txt"
        verified = (marker.is_file() and marker.read_text() == RUNTIME_OK and value.get("collectionExitCode") == 0
                    and value.get("completeJSONParsed") is True and value.get("ownedSimulatorVerified") is True
                    and value.get("simulatorUDID") == device["udid"] and type(value.get("appEntries")) is int
                    and 0 < value["appEntries"] <= value.get("entries", 0)
                    and value.get("knownDiagnosticCounts") == {key: 0 for key in METAL_DIAGNOSTICS}
                    and value.get("knownDiagnosticCount") == 0 and value.get("knownDiagnosticsAbsent") is True
                    and source.is_file() and value.get("sourceBytes") == source.stat().st_size
                    and value.get("sourceSHA256") == digest(source) and value.get("pixels") == "PENDING"
                    and value.get("liveUIValidated") is False and value.get("performanceAcceptance") is False)
        return dict(value, verified=bool(verified))
    except (OSError, ValueError, KeyError, TypeError):
        return {"verified": False, "status": "UNAVAILABLE", "pixels": "PENDING"}


def unexpected_ui_artifacts():
    return sorted(path.name for path in work().iterdir() if path.name.startswith(("ui-", "selected-ui"))
                  or path.name == "ui.xcresult")


def public_summary():
    ident = read_json(work() / "identity.json")
    runtime = runtime_summary()
    ui_artifacts = unexpected_ui_artifacts()
    result = {"sourceSHA": ident["sourceSHA"], "sourceBaselineSHA": SOURCE_BASELINE, "executionScope": SCOPE,
        "runID": ident["runID"], "attempt": ident["attempt"], "expectedNativeMethods": 1,
        "expectedUIMethods": 0, "uiExecutionStatus": "not_selected", "uiExactMethodPassed": False,
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedActiveRendererPrepareCalls": 0, "expectedOriginalRendererRebindCalls": 1,
        "expectedFreshRendererCreateCalls": 1, "expectedFreshRendererAssociationCalls": 1,
        "expectedFreshRendererRenderCalls": 0, "expectedSnapshotCalls": 0,
        "expectedSourceProjectorStates": list(CAPTURE_PROJECTOR_STATES),
        "uiArtifactsAbsent": not ui_artifacts, "unexpectedUIArtifacts": ui_artifacts,
        "preservedPriorEvidence": preserved_prior_evidence(), "assetReleaseSHA256": RELEASE_SHA,
        "deltaManifestSHA256": DELTA_MANIFEST_SHA, "resourcesAuthenticated": (work() / "stage-ok.json").is_file(),
        "compiled373ResourcesVerified": (work() / "build-ok.txt").is_file(),
        "nativeExactMethodPassed": (work() / "native-ok.txt").is_file(),
        "exactDiagnosticCaptureSetVerified": (work() / "attachments-ok.json").is_file(),
        "sealedDiagnosticCaptureSetComplete": False, "registrationSequenceVerified": None,
        "originalRendererRebindCallCount": None, "freshRendererCreateCount": None,
        "freshRendererAssociationCallCount": None, "freshRendererRenderCallCount": None,
        "prepareCallCount": None, "snapshotCallCount": None,
        "runtimeDiagnostics": runtime,
        "runtimeDiagnosticGatePassed": runtime["verified"], "pixels": "PENDING", "liveUIValidated": False,
        "physicalIPhoneAcceptance": "NOT VERIFIED", "performanceAcceptance": False, "audiblePlayback": "NOT VERIFIED",
        "productionPanguAssetsActivated": False, "previous117SelectedAgain": False,
        "previousFiveSelectedAgain": False, "previousSixSelectedAgain": False,
        "previousEntranceDiagnosticSelectedAgain": False, "previousSceneBaseDiagnosticSelectedAgain": False,
        "previousScenePreparationDiagnosticSelectedAgain": False,
        "TestFlightUploaded": False}
    if (work() / "attachments-ok.json").is_file():
        observation = read_json(work() / "attachments-ok.json").get("registrationObservations", {})
        require(observation.get("registrationSequenceVerified") is True,
                "Validated attachment receipt lacks registration observations")
        result["registrationSequenceVerified"] = True
        for public_key, report_key, expected in (
                ("originalRendererRebindCallCount", "originalRendererRebindCalls", 1),
                ("freshRendererCreateCount", "freshRendererCreatedCount", 1),
                ("freshRendererAssociationCallCount", "freshRendererAssociatedCount", 1),
                ("freshRendererRenderCallCount", "freshRendererRenderCalls", 0),
                ("prepareCallCount", "prepareCalls", 0), ("snapshotCallCount", "snapshotCalls", 0)):
            require(type(observation.get(report_key)) is int and observation[report_key] == expected,
                    "Observed registration call count is missing or inconsistent")
            result[public_key] = observation[report_key]
    if (work() / "attachment-seal-policy.json").is_file():
        policy = read_json(work() / "attachment-seal-policy.json")
        result["attachmentSealPolicy"] = {key: policy.get(key) for key in ("selectedFileCount", "selectedBytes", "omittedFileCount",
            "mandatoryValidationPassed", "completeValidatedMandatorySetSealed", "automaticAttachmentsNeverCountAsCoverage")}
        result["sealedDiagnosticCaptureSetComplete"] = policy.get("completeValidatedMandatorySetSealed") is True
    if (work() / "native-process.json").is_file():
        result["nativeProcess"] = {key: value for key, value in read_json(work() / "native-process.json").items()
                                   if key in ("exitCode", "selectedCount", "iterations")}
    if (work() / "native-summary.json").is_file():
        try:
            counts = read_json(work() / "native-summary.json")
            result["nativeObservedCounts"] = {key: counts.get(key) for key in
                                              ("totalTestCount", "passedTests", "failedTests", "skippedTests", "result")}
        except (OSError, ValueError):
            result["nativeObservedCounts"] = "UNAVAILABLE"
    if (work() / "timings.json").is_file():
        result["timings"] = read_json(work() / "timings.json")
    return result


def seal():
    no_resource_keys()
    identity()
    once("seal")
    shared = resource_tools()
    public = regular(ROOT / RECIPIENT, 16_384).read_bytes()
    require(shared.recipient_digest(public) == RECIPIENT_SPKI_SHA, "Evidence recipient differs")
    envelope = importlib.import_module("fighter_private_model")
    published, archive = work() / "published", work() / "private-evidence.zip"
    published.mkdir(mode=0o700, exist_ok=False)
    try:
        attachments = bounded_attachments()
        write_json(work() / "public-summary.json", public_summary())
        entries, total = [], 0
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_STORED) as output:
            for path in sorted(work().iterdir()):
                if path.suffix not in (".log", ".json", ".txt") or not path.is_file() or path.stat().st_size == 0:
                    continue
                regular(path, 128 * 1024**2)
                size = path.stat().st_size
                with path.open("rb") as source:
                    source.seek(max(0, size - 2 * 1024**2))
                    raw = source.read(2 * 1024**2)
                total += len(raw)
                require(total <= 32 * 1024**2 and len(entries) < 128, "Text evidence exceeds bound")
                name = "metadata/" + path.name
                output.writestr(name, raw)
                entries.append({"file": name, "sourceBytes": size, "archivedBytes": len(raw),
                                "tailOnly": size != len(raw), "sha256": sha(raw)})
            for path, name in attachments:
                output.write(path, name)
                entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path)})
            output.writestr("private-evidence-inventory.json", json.dumps(entries, indent=2))
        require(entries and archive.stat().st_size <= 242 * 1024**2, "Evidence archive exceeds bound")
        key = secrets.token_bytes(32)
        shared.wrap_key(key, shared.existing_recipient(), published / (STEM + ".key.enc"))
        shared.wrap_key(key, public, published / (STEM + ".session-key.enc"))
        # Fresh diagnostic key only; no resource key is available in this phase.
        os.environ[KEY_NAMES[0]] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / (STEM + ".enc"))
        finally:
            os.environ.pop(KEY_NAMES[0], None)
            key = b""
        files = sorted(published.glob("*.enc"))
        require({p.name for p in files} == {STEM + suffix for suffix in (".enc", ".key.enc", ".session-key.enc")},
                "Incomplete ciphertext envelope")
        (published / (STEM + ".SHA256SUMS")).write_text("".join(digest(p) + "  " + p.name + "\n" for p in files))
        (work() / "sealed-ok.txt").write_text("Only diagnostic ciphertext and wrapped fresh keys may be uploaded.\n")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        raise
    finally:
        archive.unlink(missing_ok=True)
    print("Sealed bounded original diagnostic images, exact results, resource receipts and logs for private recipients.")


def cleanup():
    no_resource_keys()
    errors, summary = [], {}
    try:
        identity()
        summary = public_summary()
    except Exception as error:
        errors.append("identity: " + type(error).__name__)
        summary = {"sourceSHA": os.environ.get("GITHUB_SHA"), "nativeExactMethodPassed": False, "pixels": "PENDING"}
    summary["diagnosticsSealed"] = (work() / "sealed-ok.txt").is_file()
    try:
        path = work() / "simulator.json"
        if path.exists():
            device = read_json(path)
            catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True, timeout=30))
            matches = [d for rows in catalog["devices"].values() for d in rows if d.get("udid") == device["udid"]]
            require(len(matches) == 1 and matches[0].get("name") == device["name"] == simulator_name(), "Cleanup device ownership differs")
            if matches[0].get("state") != "Shutdown":
                run_logged(["xcrun", "simctl", "shutdown", device["udid"]], "simulator-shutdown", 90)
            run_logged(["xcrun", "simctl", "delete", device["udid"]], "simulator-delete", 60)
    except Exception as error:
        errors.append("simulator: " + type(error).__name__)
    for path in [ROOT / "App/Resources/FighterPrivate", ROOT / TEMP_SPEC] + [p for p in work().iterdir() if p.name != "published"]:
        try:
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        except OSError as error:
            errors.append("plaintext: " + type(error).__name__)
    summary["cleanupComplete"], summary["cleanupErrors"] = not errors, errors
    write_json(work() / "public-summary.json", summary)
    if errors:
        raise PhaseFailure("Owned simulator or plaintext cleanup incomplete")
    print("Removed this diagnostic's simulator, staged media, products and plaintext evidence.")


def report():
    no_resource_keys()
    value = read_json(work() / "public-summary.json")
    print(json.dumps(value, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write("### Installed scene-registration diagnostic: one new native method; UI not selected\n\n")
            output.write("This is source/renderer isolation evidence, not pixel, live UI, audible playback or physical-device acceptance. Historical 117/5/6, entrance, scene-base and scene-preparation diagnostic passes are not rerun; production pixel and live UI acceptance remain unverified.\n\n")
            fence = chr(96) * 3
            output.write(fence + "json\n" + json.dumps(value, indent=2) + "\n" + fence + "\n")
    require(value.get("executionScope") == SCOPE and value.get("expectedNativeMethods") == 1
            and value.get("expectedUIMethods") == 0 and value.get("uiExecutionStatus") == "not_selected"
            and value.get("uiExactMethodPassed") is False and "uiObservedCounts" not in value and "uiProcess" not in value
            and value.get("pixels") == "PENDING" and value.get("liveUIValidated") is False
            and value.get("performanceAcceptance") is False
            and value.get("expectedSimulationFrames") == [0] and value.get("expectedSimulationAdvanceCalls") == 0
            and value.get("reportSchema") == REPORT_SCHEMA and value.get("expectedCaptureLabels") == list(FRAME_LABELS)
            and value.get("expectedActiveRendererPrepareCalls") == 0
            and value.get("expectedOriginalRendererRebindCalls") == 1
            and value.get("expectedFreshRendererCreateCalls") == 1
            and value.get("expectedFreshRendererAssociationCalls") == 1
            and value.get("expectedFreshRendererRenderCalls") == 0 and value.get("expectedSnapshotCalls") == 0
            and value.get("expectedSourceProjectorStates") == list(CAPTURE_PROJECTOR_STATES)
            and all(value.get(key) is False for key in ("previous117SelectedAgain", "previousFiveSelectedAgain",
                "previousSixSelectedAgain", "previousEntranceDiagnosticSelectedAgain", "previousSceneBaseDiagnosticSelectedAgain",
                "previousScenePreparationDiagnosticSelectedAgain")),
            "Diagnostic scope cannot become UI, pixel, performance acceptance or historical execution")
    gates = ("resourcesAuthenticated", "compiled373ResourcesVerified", "nativeExactMethodPassed", "uiArtifactsAbsent",
             "exactDiagnosticCaptureSetVerified", "sealedDiagnosticCaptureSetComplete", "runtimeDiagnosticGatePassed",
             "diagnosticsSealed", "cleanupComplete", "registrationSequenceVerified")
    for field, expected in (("originalRendererRebindCallCount", 1), ("freshRendererCreateCount", 1),
            ("freshRendererAssociationCallCount", 1), ("freshRendererRenderCallCount", 0),
            ("prepareCallCount", 0), ("snapshotCallCount", 0)):
        require(type(value.get(field)) is int and value[field] == expected, "Observed registration counts are unavailable")
    require(all(value.get(key) is True for key in gates), "Diagnostic did not reach every required method/evidence gate")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "tools", "stage", "build", "simulator", "test", "export", "seal", "cleanup", "report"))
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
        print("Scene-registration diagnostic phase failed: " + operation + "; private evidence retained when prepared.", file=sys.stderr)
        return error.code if isinstance(error, PhaseFailure) else 1


if __name__ == "__main__":
    sys.exit(main())
