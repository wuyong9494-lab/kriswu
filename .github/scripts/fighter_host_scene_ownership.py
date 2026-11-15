#!/usr/bin/env python3
"""One new installed host-SCNView preparation diagnostic; no UI or historical test rerun.

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
SCOPE = "installed-host-scene-ownership-one"
SOURCE_BASELINE = "1efa361dbe454262e395221ba33b34d4779377d5"
COMMIT_MESSAGE = "Verify approved Android client and host ownership 20261115"
HELPER = ".github/scripts/fighter_host_scene_ownership.py"
CHECKS = ".github/scripts/test_fighter_host_scene_ownership.py"
WORKFLOW = ".github/workflows/fighter-host-scene-ownership.yml"
SWIFT_TEST = "Tests/SiteTests/DuelHostSceneOwnershipTests.swift"
CLASS_NAME = "DuelHostSceneOwnershipTests"
METHOD_NAME = "testInstalledHostScenePreparationIsIsolatedAtFrameZero"
SELECTOR = "SiteTests/" + CLASS_NAME + "/" + METHOD_NAME
SELECTORS = (SELECTOR,)
SWIFT_TEST_SHA = "df92c427f7223c4d931d24ff31e717303653defe9f57be48bc88d79a797514d0"
CHECKS_SHA = "ef6dc19ace268a23a8111be0410a25b46dc4bb1d8c07c0c54ec8ea92d4b602e8"
WORKFLOW_CANONICAL_SHA = "5fc9c172afde5788f9c31374e9b91e5c88a651ce1a25ae22f030e489d841e7af"
HELPER_PIN_FIELD = '      EXPECTED_HOST_SCENE_OWNERSHIP_HELPER_SHA256: "'
REVIEWED_ENTRIES = {
    "App": "c817ebac7b8cf6c491fbcb354b993420764ea4d8",
    "Package.swift": "ffc64914ed88ae83bb4569fea0777b08ea2d29b6",
    "Shared": "e41e160b4262a9defbb3c5e92b4d020c5e0c2b80",
    "Sources": "e151525e2b8db6592379a120bfe1007c3e0edc41",
    "Widget": "dc5c0075ea1fb8ed0a44c68f2fea21dfc92112d3",
    "project.yml": "4659145612fbca682db5fb915784d9c6e9dc8cab",
    "scripts": "64730d41241222d66e0837afdd50ae3b813be83d",
}
OTHER_TESTS_SHA = '15df97783982db1bb085f0d29fd8ea8b75cf51b0010018eddca1a7690efbb2a5'
OTHER_CI_SCRIPTS_SHA = '1cc28395bcb7b3b62075471c1a1a9f12bd401c82beadd2ce1919b50980602685'
OTHER_WORKFLOWS_SHA = 'dc83aa36c72239948563f86adf4e74b9fee2284cb8abb56325815bc0f2f5a0a0'
CO_PUBLISHED_CI_ADDITIONS = (
    ".github/scripts/fighter_android_official_client.py",
    ".github/scripts/fighter_android_sdk_install.py",
    ".github/scripts/test_fighter_android_official_client.py",
    ".github/workflows/fighter-android-official-client.yml",
)

RESOURCE_TOOLS = ".github/scripts/fighter_shared_root_native.py"
RESOURCE_TOOLS_SHA = "945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036"
RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
DELTA_MANIFEST_SHA = "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")
FRAME_LABELS = ('host-prepare-intercepted', 'host-world-prepared')
REPORT_LABEL = "host-scene-ownership-report"
EXPECTED_ATTACHMENTS = {**{label: "image" for label in FRAME_LABELS}, REPORT_LABEL: "data"}
REPORT_SCHEMA = "fighter-host-scene-ownership-v1"
# Final independent Swift contract; original captures remain subject to manual review.
CAPTURE_ISOLATION = (
    "automatic host SceneKit prepare intercepted; no explicit prepare; original Surface and projector",
    "one synchronous prepare on existing World SCNView; same original Surface and projector",
)
CAPTURE_PROJECTOR_STATES = (True, True)
CAPTURE_PREPARE_COUNTS = (0, 1)
METAL_DIAGNOSTICS = {
    "doublePresent": "Each CAMetalLayerDrawable can only be presented once!",
    "textureAfterPresent": "[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.",
}
RUNTIME_OK = "Complete owned diagnostic invocation log; zero known drawable diagnostics. Pixels pending.\n"
TEMP_SPEC = "project.host-scene-ownership.yml"
STEM = "fighter-host-scene-ownership-evidence"
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
    directory = parent / "fighter-host-scene-ownership"
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
    require(len(matches) == 1 and value.count("EXPECTED_HOST_SCENE_OWNERSHIP_HELPER_SHA256") == 1,
            "Workflow must have one exact helper-pin field")
    match = matches[0]
    return (value[:match.start(1)] + "0" * 64 + value[match.end(1):]).encode(), match.group(1)


def pin_sources():
    pinned(SWIFT_TEST, SWIFT_TEST_SHA)
    pinned(CHECKS, CHECKS_SHA)
    normalized, helper_sha = normalized_workflow(regular(ROOT / WORKFLOW, 64 * 1024).read_bytes())
    require(sha(normalized) == WORKFLOW_CANONICAL_SHA and helper_sha == digest(Path(__file__))
            and os.environ.get("EXPECTED_HOST_SCENE_OWNERSHIP_HELPER_SHA256") == helper_sha,
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
    require(entries == REVIEWED_ENTRIES, "App/Core/build/resource scripts changed from the 1efa361d baseline")
    require(retained_tree_digest(tests, {SWIFT_TEST}) == OTHER_TESTS_SHA, "An existing test changed")
    excluded_scripts = {HELPER, CHECKS} | {p for p in CO_PUBLISHED_CI_ADDITIONS if p.startswith(".github/scripts/")}
    excluded_workflows = {WORKFLOW} | {p for p in CO_PUBLISHED_CI_ADDITIONS if p.startswith(".github/workflows/")}
    require(retained_tree_digest(ci_scripts, excluded_scripts) == OTHER_CI_SCRIPTS_SHA,
            "An existing CI helper changed or an unreviewed addition appeared")
    require(retained_tree_digest(workflows, excluded_workflows) == OTHER_WORKFLOWS_SHA,
            "An existing workflow changed or an unreviewed addition appeared")


def co_published_inventory():
    # Exact names only. These independent Android files cannot affect the host
    # target and are not called. Their actual committed bytes remain traceable
    # without a cyclic self-pin between the two new execution entries.
    return [{"path": name, "bytes": regular(ROOT / name, 512 * 1024).stat().st_size,
             "sha256": digest(ROOT / name), "usedByThisExecution": False}
            for name in CO_PUBLISHED_CI_ADDITIONS]


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
        {"runID": "43666784396", "sourceSHA": "09f2f3c2ea1c8ad0283e920d442995a5faa1b254", "passedMethods": 1,
         "productionPixels": "NOT_VERIFIED", "selectedAgain": False, "countsBelongToCurrentRun": False},
        {"runID": "43670209830", "sourceSHA": "e35c51d7b0fbe4e7659892d1fcc0caf839479a65", "passedMethods": 0,
         "failedMethods": 1, "skippedMethods": 0, "pixels": "FAILED", "uiExecutionStatus": "blocked_by_native",
         "selectedAgain": False, "countsBelongToCurrentRun": False},
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
            and value.get("expectedHostSynchronousPrepareCalls") == 1
            and value.get("expectedAutomaticPrepareRequestsIntercepted") == 1
            and value.get("expectedGamePausedForIsolation") is True
            and value.get("expectedSourceProjectorStates") == list(CAPTURE_PROJECTOR_STATES)
            and value.get("helperSHA256") == digest(Path(__file__))
            and value.get("workflowSHA256") == digest(ROOT / WORKFLOW)
            and value.get("assetReleaseSHA256") == RELEASE_SHA
            and value.get("coPublishedNonInputs") == co_published_inventory(), "Prepared diagnostic identity changed")
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
        "expectedActiveRendererPrepareCalls": 0, "expectedHostSynchronousPrepareCalls": 1,
        "expectedAutomaticPrepareRequestsIntercepted": 1, "expectedGamePausedForIsolation": True,
        "expectedSourceProjectorStates": list(CAPTURE_PROJECTOR_STATES),
        "sourceMapping": "All App/Core/build inputs match restored 1efa361d; one new host diagnostic; exact Android additions are non-inputs",
        "coPublishedNonInputs": co_published_inventory(),
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
    return "Fighter host scene ownership " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]


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
    """Verify the two owned observations, preserving black images and prepare(false)."""
    def integer(row, field, expected):
        return isinstance(row, dict) and type(row.get(field)) is int and row[field] == expected
    def finite(number):
        return type(number) in (int, float) and math.isfinite(number)
    def vector(values, size):
        return isinstance(values, list) and len(values) == size and all(finite(n) for n in values)
    def fields(row, expected, message):
        require(isinstance(row, dict) and all(key in row and type(row[key]) is type(target)
                and row[key] == target for key, target in expected.items()), message)
    fields(value, {"schemaVersion": 1, "schema": REPORT_SCHEMA, "scope": SCOPE,
        "releaseSHA256": RELEASE_SHA, "diagnosticCompleted": True,
        "lastPhase": "captured-before-diagnostic-assertions", "pixels": "PENDING",
        "stateInvariant": True, "modelObjectIdentityInvariant": True,
        "automaticPrepareRequestsIntercepted": 1, "interceptedCompletionForwardCalls": 0,
        "backgroundPrepareCallsByTest": 0, "hostSynchronousPrepareCalls": 1,
        "activeRendererPrepareCalls": 0, "explicitDrawStateCalls": 0, "captureFrameCalls": 2,
        "simulationAdvanceCalls": 0, "activeSceneRebindCalls": 0, "hostSceneRebindCalls": 0,
        "freshRendererCreationCalls": 0, "snapshotCalls": 0, "projectorDetachCalls": 0,
        "gamePausedForIsolation": True, "presentationOnlyUnpauseCalls": 1,
        "interceptedCompletionIntentionallyNotForwarded": True,
        "combatStateInjected": False, "liveDisplayLinkAdvancesSelected": False,
        "sourcePacketsExpectedZero": True, "sceneKitLightsChanged": False,
        "normalDrawablePresentationValidated": False, "uiExecutionStatus": "not_selected",
        "physicalDeviceValidated": False, "liveUIValidated": False, "audiblePlaybackVerified": False,
        "performanceVerified": False, "panguEquipmentActivated": False,
        "captureTimingIncludesGPUReadbackWait": True}, "Host diagnostic identity, counters or scope differs")
    require(value.get("expectedSimulationFrames") == [0] and type(value["expectedSimulationFrames"][0]) is int
            and value.get("captureLabels") == list(FRAME_LABELS), "Host capture schedule differs")
    require(value.get("interceptedRequestSceneMatches") == [True]
            and type(value["interceptedRequestSceneMatches"][0]) is bool, "Automatic request was not the exact same scene")
    require(finite(value.get("elapsedSeconds")) and value["elapsedSeconds"] >= 0, "Elapsed time is invalid")
    setup = value.get("setup")
    fields(setup, {"pausedBeforeWorldConstruction": True, "gamePaused": True,
        "automaticPrepareRequestsIntercepted": 1, "hostAndSurfaceShareScene": True,
        "hostAndSurfaceSharePointOfView": True, "sameMetalDevice": True,
        "surfaceSubmittedFrames": 0, "surfaceLastSubmittedTick": None,
        "projectorLastFrameAvailable": False, "displayLinkCallbacks": 0,
        "hostMusicReadiness": False}, "Setup introduced a warmup, different owner or unpaused clock")
    require(setup.get("requestSceneMatches") == [True] and type(setup["requestSceneMatches"][0]) is bool
            and type(setup.get("activeClocksBefore")) is int and setup["activeClocksBefore"] >= 0
            and type(setup.get("activeClocksAfterMount")) is int
            and setup["activeClocksAfterMount"] == setup["activeClocksBefore"], "Setup clock or intercepted request differs")
    prep = value.get("preparation")
    fields(prep, {"api": "SCNView.prepare(_:shouldAbortBlock:)", "target": "existing-world-SCNView",
        "input": "same-installed-SCNScene", "synchronous": True, "calls": 1, "completionReturned": True,
        "beforeCaptureLabel": FRAME_LABELS[0], "afterCaptureLabel": FRAME_LABELS[1],
        "targetIsHostView": True, "targetIsActiveSurfaceRenderer": False,
        "hostSceneMatchesBeforeAndAfter": True, "activeRendererSceneMatchesBeforeAndAfter": True,
        "pointOfViewMatchesBeforeAndAfter": True, "sameOriginalProjector": True,
        "simulationInvariantAfter": True}, "Prepare receiver, API, scene or call count differs")
    require(type(prep.get("success")) is bool and finite(prep.get("seconds")) and prep["seconds"] >= 0,
            "Actual host preparation result is missing")
    timings = value.get("timings")
    require(isinstance(timings, list) and 1 <= len(timings) <= 24
            and all(isinstance(t, dict) and isinstance(t.get("phase"), str) and finite(t.get("seconds"))
                    and t["seconds"] >= 0 for t in timings), "Timings are invalid")
    phases = collections.Counter(t["phase"] for t in timings)
    expected_phases = ("construct-paused-session", "construct-world", "mount-layout-intercepted",
        FRAME_LABELS[0] + "-synchronous-capture", "prepare-existing-host-view-once",
        FRAME_LABELS[1] + "-synchronous-capture")
    require(all(phases[name] == 1 for name in expected_phases), "A required phase is missing or repeated")
    require(next(t["seconds"] for t in timings if t["phase"] == "prepare-existing-host-view-once") == prep["seconds"],
            "Prepare timing disagrees with its actual operation")
    cleanup = value.get("cleanup")
    fields(cleanup, {"interceptionHookCleared": True, "worldSceneReleased": True,
        "worldSurfaceReleased": True, "worldPacketRendererReleased": True, "surfaceSceneDetached": True,
        "surfacePointOfViewDetached": True, "surfaceDelegateDetached": True, "sourceProjectorDetached": True,
        "renderCallbackCleared": True, "lateGeometryProviderCleared": True,
        "objectDeallocationVerified": False}, "Actual ownership cleanup failed")
    require(type(cleanup.get("activeClocksBefore")) is int and type(cleanup.get("activeClocksAfter")) is int
            and cleanup["activeClocksBefore"] == cleanup["activeClocksAfter"] == setup["activeClocksBefore"],
            "Display clock ownership leaked")
    samples, captures = value.get("samples"), value.get("captures")
    require(isinstance(samples, list) and len(samples) == 2 and isinstance(captures, list) and len(captures) == 2
            and isinstance(images, dict) and set(images) == set(FRAME_LABELS), "The original two-image closure is incomplete")
    first_model, first_lights, first_fighters, first_frame, first_inventory = None, None, None, None, None
    for index, (label, capture, sample) in enumerate(zip(FRAME_LABELS, captures, samples)):
        common = {"label": label, "frame": 0, "animationTick": 0, "sourceLiveTick": 0,
            "rendererRoute": "surface.captureFrame", "sourceProjectorInstalled": True,
            "projectorEncodedForCapture": True, "submittedPackets": 0, "surfaceSubmittedFrames": 0,
            "surfaceLastSubmittedTick": None, "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": 4,
            "hostPrepareCallsSoFar": index}
        fields(capture, common, "Capture clocks, owner, projector or prepare ordering differs")
        fields(sample, common, "Sample clocks, owner, projector or prepare ordering differs")
        expected_success = None if index == 0 else prep["success"]
        require("hostPrepareSuccessSoFar" in sample and sample["hostPrepareSuccessSoFar"] is expected_success,
                "Host prepare result appears at the wrong observation")
        fields(sample, {"automaticPrepareRequestsIntercepted": 1, "displayLinkCallbacks": 0, "gamePaused": True,
            "sourceIntroActive": True, "sourceStance": "firstBirth", "sourceStanceTick": 0,
            "weaponReady": False, "branchesReady": False, "sameActiveSurface": True, "sameActiveRenderer": True,
            "sameScene": True, "samePointOfView": True, "hostStillOwnsScene": True, "hostStillOwnsPointOfView": True,
            "modelObjectIdentityUnchanged": True, "simulationInvariant": True, "rendererUsesReverseZ": False,
            "rendererIsPlaying": False, "rendererAutoenablesDefaultLighting": False,
            "hostRendersContinuously": False, "hostIsPlaying": False, "hostMusicReadiness": False,
            "sameMetalDevice": True, "rendererFailure": "", "surfaceFailure": "", "sourcePreparationFailure": ""},
            "Host or Surface state changed outside the one prepare operation")
        require(sample.get("sourceEffectIDs") == [] and type(sample.get("hostRenderingAPI")) is int,
                "Unexpected source effects or missing host API observation")
        image = images[label]
        require(isinstance(image, dict) and type(image.get("bytes")) is int and 0 < image["bytes"] <= 24*1024**2
                and isinstance(image.get("sha256"), str) and re.fullmatch(r"[a-f0-9]{64}", image["sha256"])
                and image.get("width") == 956 and image.get("height") == 440, "Original PNG metadata is invalid")
        fields(capture, {"isolation": CAPTURE_ISOLATION[index], "pngSHA256": image["sha256"], "bytes": image["bytes"],
            "width": 956, "height": 440, "pixelsRequireReview": True, "simulationAndModelCameraUnchanged": True},
            "Capture report does not match its original PNG")
        camera = sample.get("camera")
        require(isinstance(camera, dict) and all(vector(camera.get(k), 16) for k in
                ("modelWorldTransform", "presentationWorldTransform", "metalProjection")), "Camera matrices are missing")
        for camera_kind in ("model", "presentation"):
            lens = camera.get(camera_kind)
            require(isinstance(lens, dict) and type(lens.get("exists")) is bool, "Camera observation is missing")
            if camera_kind == "presentation" and lens["exists"] is False:
                require(set(lens) == {"exists"}, "Absent presentation camera contains fabricated fields")
            else:
                require(lens["exists"] is True and vector(lens.get("projectionTransform"), 16)
                        and all(finite(lens.get(k)) for k in ("fieldOfView", "near", "far", "orthographicScale"))
                        and type(lens.get("categoryMask")) is int and type(lens.get("usesOrthographicProjection")) is bool,
                        "Camera lens is incomplete")
        model = (camera["modelWorldTransform"], camera["model"], camera["metalProjection"])
        viewport = sample.get("viewport")
        require(isinstance(viewport, dict) and all(finite(viewport.get(k)) and viewport[k] == expected for k, expected in
                (("pointsWidth",956),("pointsHeight",440),("captureWidth",956),("captureHeight",440)))
                and all(finite(viewport.get(k)) and viewport[k] >= 0 for k in ("drawableWidth","drawableHeight"))
                and all(finite(viewport.get(k)) and viewport[k] > 0 for k in ("viewScale","surfaceScale")), "Viewport differs")
        fighters, lights, inventory = sample.get("fighters"), sample.get("lights"), sample.get("sceneInventory")
        require(isinstance(fighters, list) and len(fighters) == 2, "Two original fighters are required")
        for seat, fighter in enumerate(fighters):
            fields(fighter, {"index": seat, "hero": ("ember","liu")[seat], "health": 1000, "clipTick": 0},
                    "Fighter source identity or initial state differs")
            require(type(fighter.get("x")) is int and type(fighter.get("y")) is int
                    and isinstance(fighter.get("clip"), str) and fighter["clip"], "Fighter pose is absent")
        require(isinstance(lights, list) and lights and all(isinstance(light,dict) for light in lights), "Lights missing")
        require(isinstance(inventory,list) and len(inventory)==3
                and {row.get("name") for row in inventory if isinstance(row,dict)} == {"duel.stage.palace","duel.actor.0","duel.actor.1"},
                "Installed scene roots are missing")
        projected_inventory = []
        for row in inventory:
            require(type(row.get("hidden")) is bool and finite(row.get("opacity"))
                    and type(row.get("geometries")) is int and row["geometries"] > 0
                    and type(row.get("skinners")) is int and row["skinners"] >= 0
                    and vector(row.get("modelWorldTransform"),16) and vector(row.get("presentationWorldTransform"),16),
                    "Installed root observations are invalid")
            projected_inventory.append({k:row[k] for k in ("name","hidden","opacity","geometries","skinners","modelWorldTransform")})
        frame = sample.get("projectorLastFrame")
        fields(frame, {"available":True,"tick":0}, "The original projector did not encode frame zero")
        require(finite(frame.get("aspect")) and frame["aspect"]>0 and vector(frame.get("sourceCameraPosition"),3)
                and all(vector(frame.get(k),16) for k in ("sourceView","sourceProjection","sourceShadowMatrix"))
                and all(type(frame.get(k)) is int and frame[k]>=0 for k in ("casterCount","triangleCount"))
                and isinstance(frame.get("factors"),list) and all(finite(n) for n in frame["factors"]), "Projector observation missing")
        if index == 0:
            first_model, first_lights, first_fighters, first_frame, first_inventory = model, lights, fighters, frame, projected_inventory
        require(model==first_model and lights==first_lights and fighters==first_fighters
                and frame==first_frame and projected_inventory==first_inventory,
                "The one host prepare changed model state, lights, source projector or fighter state")
    same_png = images[FRAME_LABELS[0]]["sha256"] == images[FRAME_LABELS[1]]["sha256"]
    require(type(value.get("pngEqualBeforeAndAfterHostPreparation")) is bool
            and value["pngEqualBeforeAndAfterHostPreparation"] is same_png, "PNG equality differs from original bytes")
    return {"structureVerified": True, "hostPrepareCalls":1, "hostPreparationSucceeded":prep["success"],
        "automaticPrepareRequestsIntercepted":1, "activeRendererPrepareCalls":0,
        "pngEqualBeforeAndAfterHostPreparation":same_png, "pixels":"PENDING",
        "structurallyCompleteFailurePreserved":not prep["success"], "normalDrawablePresentationValidated":False}


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
    host_preparation_observations = validate_report(diagnostic, images)
    require(mandatory_bytes <= 160 * 1024**2 and automatic_bytes <= 256 * 1024**2, "Evidence category exceeds bounded budget")
    return {"completeExpectedLabels": True, "exactMethodAndSimulatorOwnership": True, "files": entries,
            "automaticDiagnostics": automatic, "automaticAttachmentsNeverCountAsCoverage": True,
            "hostPreparationObservations": host_preparation_observations, "pixels": "PENDING"}


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
    print("Exported two exact method/device-owned PNGs and the host preparation report; human pixel review remains pending.")


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
        "coPublishedNonInputs": ident["coPublishedNonInputs"],
        "expectedUIMethods": 0, "uiExecutionStatus": "not_selected", "uiExactMethodPassed": False,
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedActiveRendererPrepareCalls": 0, "expectedHostSynchronousPrepareCalls": 1,
        "expectedAutomaticPrepareRequestsIntercepted": 1, "expectedGamePausedForIsolation": True,
        "expectedSourceProjectorStates": list(CAPTURE_PROJECTOR_STATES),
        "uiArtifactsAbsent": not ui_artifacts, "unexpectedUIArtifacts": ui_artifacts,
        "preservedPriorEvidence": preserved_prior_evidence(), "assetReleaseSHA256": RELEASE_SHA,
        "deltaManifestSHA256": DELTA_MANIFEST_SHA, "resourcesAuthenticated": (work() / "stage-ok.json").is_file(),
        "compiled373ResourcesVerified": (work() / "build-ok.txt").is_file(),
        "nativeExactMethodPassed": (work() / "native-ok.txt").is_file(),
        "exactDiagnosticCaptureSetVerified": (work() / "attachments-ok.json").is_file(),
        "sealedDiagnosticCaptureSetComplete": False, "hostPreparationSucceeded": None, "hostPrepareCallCount": None,
        "automaticPrepareInterceptCount": None, "hostPreparationObservations": None, "nativeObservedCounts": None,
        "runtimeDiagnostics": runtime,
        "runtimeDiagnosticGatePassed": runtime["verified"], "pixels": "PENDING", "liveUIValidated": False,
        "physicalIPhoneAcceptance": "NOT VERIFIED", "performanceAcceptance": False, "audiblePlayback": "NOT VERIFIED",
        "productionPanguAssetsActivated": False, "previous117SelectedAgain": False,
        "previousFiveSelectedAgain": False, "previousSixSelectedAgain": False,
        "previousEntranceDiagnosticSelectedAgain": False, "previousSceneBaseDiagnosticSelectedAgain": False,
        "previousScenePreparationDiagnosticSelectedAgain": False, "previousSceneRegistrationDiagnosticSelectedAgain": False,
        "previousSceneAssemblyFollowupSelectedAgain": False,
        "TestFlightUploaded": False}
    if (work() / "attachments-ok.json").is_file():
        observation = read_json(work() / "attachments-ok.json").get("hostPreparationObservations", {})
        require(type(observation.get("hostPreparationSucceeded")) is bool
                and type(observation.get("hostPrepareCalls")) is int and observation["hostPrepareCalls"] == 1
                and type(observation.get("automaticPrepareRequestsIntercepted")) is int
                and observation["automaticPrepareRequestsIntercepted"] == 1,
                "Validated attachment receipt lacks preparation observations")
        result["hostPreparationSucceeded"] = observation["hostPreparationSucceeded"]
        result["hostPrepareCallCount"] = observation["hostPrepareCalls"]
        result["automaticPrepareInterceptCount"] = observation["automaticPrepareRequestsIntercepted"]
        result["hostPreparationObservations"] = observation
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
            output.write("### Installed host-SCNView preparation diagnostic: one new native method; UI not selected\n\n")
            output.write("This is source/renderer isolation evidence, not pixel, live UI, audible playback or physical-device acceptance. Historical 117/5/6 and all prior diagnostic methods, including the failed assembly candidate, are not rerun; production pixel and live UI acceptance remain unverified.\n\n")
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
            and value.get("expectedHostSynchronousPrepareCalls") == 1
            and value.get("expectedAutomaticPrepareRequestsIntercepted") == 1
            and value.get("expectedGamePausedForIsolation") is True
            and value.get("expectedSourceProjectorStates") == list(CAPTURE_PROJECTOR_STATES)
            and all(value.get(key) is False for key in ("previous117SelectedAgain", "previousFiveSelectedAgain",
                "previousSixSelectedAgain", "previousEntranceDiagnosticSelectedAgain", "previousSceneBaseDiagnosticSelectedAgain",
                "previousScenePreparationDiagnosticSelectedAgain", "previousSceneRegistrationDiagnosticSelectedAgain",
                "previousSceneAssemblyFollowupSelectedAgain")),
            "Diagnostic scope cannot become UI, pixel, performance acceptance or historical execution")
    gates = ("resourcesAuthenticated", "compiled373ResourcesVerified", "nativeExactMethodPassed", "uiArtifactsAbsent",
             "exactDiagnosticCaptureSetVerified", "sealedDiagnosticCaptureSetComplete", "runtimeDiagnosticGatePassed",
             "diagnosticsSealed", "cleanupComplete", "hostPreparationSucceeded")
    require(type(value.get("hostPrepareCallCount")) is int and value["hostPrepareCallCount"] == 1, "Observed host SCNView preparation is unavailable")
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
        print("Host-scene ownership phase failed: " + operation + "; private evidence retained when prepared.", file=sys.stderr)
        return error.code if isinstance(error, PhaseFailure) else 1


if __name__ == "__main__":
    sys.exit(main())
