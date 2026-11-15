#!/usr/bin/env python3
"""One new cold-scene assembly regression, then one conditional previously failed UI method.

This entry owns its source, run, method, simulator and evidence gates. The
SHA-pinned shared-root helper supplies only reviewed resource/envelope tools and pure UI attachment validation;
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
import struct
import zlib
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
SCOPE = "installed-scene-assembly-followup-one"
SOURCE_BASELINE = "09f2f3c2ea1c8ad0283e920d442995a5faa1b254"
COMMIT_MESSAGE = "Verify installed scene assembly followup 20261115"
HELPER = ".github/scripts/fighter_scene_assembly_followup.py"
CHECKS = ".github/scripts/test_fighter_scene_assembly_followup.py"
WORKFLOW = ".github/workflows/fighter-scene-assembly-followup.yml"
SWIFT_TEST = "Tests/SiteTests/DuelSceneAssemblyFollowupTests.swift"
CLASS_NAME = "DuelSceneAssemblyFollowupTests"
METHOD_NAME = "testInstalledColdSceneAssemblyRendersFirstFullFrameWithoutRegistrationWorkarounds"
SELECTOR = "SiteTests/" + CLASS_NAME + "/" + METHOD_NAME
SELECTORS = (SELECTOR,)
SWIFT_TEST_SHA = "d6873b4b3b20493de4b14f89585d3feb96dad96a30aa0bb75fac0b381c8045c6"
CHECKS_SHA = '31df8861fee6897e1ce8dd439b05773e030f6be94d8a267d1bb5f35f9a2e160b'
WORKFLOW_CANONICAL_SHA = 'de5de37746f0ea426ba186f857af1b6a0437b5c5fcf33ef6abceef72668dd055'
HELPER_PIN_FIELD = '      EXPECTED_SCENE_ASSEMBLY_FOLLOWUP_HELPER_SHA256: "'
REVIEWED_ENTRIES = {
    "Package.swift": "ffc64914ed88ae83bb4569fea0777b08ea2d29b6",
    "Shared": "e41e160b4262a9defbb3c5e92b4d020c5e0c2b80",
    "Sources": "e151525e2b8db6592379a120bfe1007c3e0edc41",
    "Widget": "dc5c0075ea1fb8ed0a44c68f2fea21dfc92112d3",
    "project.yml": "4659145612fbca682db5fb915784d9c6e9dc8cab",
    "scripts": "64730d41241222d66e0837afdd50ae3b813be83d",
}
WORLD_SOURCE = "App/Views/DuelWorld.swift"
WORLD_SOURCE_SHA = "2909c56d0c1e6e44f603e1ed68292bffa3133ef3d8a1a54b33bcb57230058b4f"
BASELINE_APP_TREE = "c817ebac7b8cf6c491fbcb354b993420764ea4d8"
OTHER_APP_SHA = '655d05a7485a0d5a40c11eccb65e88ec985951c063676d29aefff634b5de8227'
UI_TEST = "Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift"
UI_TEST_SHA = "d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee"
UI_SELECTOR = "ArenaFlowTests/DuelSharedRootVisualCaptureTests/testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls"
UI_SELECTORS = (UI_SELECTOR,)
UI_POLICY = "only_after_new_native_exact_pass_nonblack_evidence_and_runtime_gate"
OTHER_TESTS_SHA = '15df97783982db1bb085f0d29fd8ea8b75cf51b0010018eddca1a7690efbb2a5'
OTHER_CI_SCRIPTS_SHA = 'b19f3bb6ad4076737221e9ea90424a398070b25602ef00b322327b37af04bb0b'
OTHER_WORKFLOWS_SHA = '90cdb13d993fdaa6cb9d6aec196df730d0e098f820020c8984d5d52cd98a39b5'
RESOURCE_TOOLS = ".github/scripts/fighter_shared_root_native.py"
RESOURCE_TOOLS_SHA = "945f612990abba097a5b53a45b25d9230f8bfde14628d4a78e6e631e26782036"
RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
DELTA_MANIFEST_SHA = "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")
FRAME_LABELS = ("assembly-cold-first-full-frame",)
REPORT_LABEL = "scene-assembly-followup-report"
EXPECTED_ATTACHMENTS = {**{label: "image" for label in FRAME_LABELS}, REPORT_LABEL: "data"}
REPORT_SCHEMA = "fighter-scene-assembly-followup-v1"
# Exact per-capture contract from the independently reviewed Swift report.
METAL_DIAGNOSTICS = {
    "doublePresent": "Each CAMetalLayerDrawable can only be presented once!",
    "textureAfterPresent": "[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.",
}
RUNTIME_OK = "Complete owned diagnostic invocation log; zero known drawable diagnostics. Pixels pending.\n"
TEMP_SPEC = "project.scene-assembly-followup.yml"
STEM = "fighter-scene-assembly-followup-evidence"
UI_RUNTIME_OK = "Complete owned UI invocation log; zero known drawable diagnostics. Pixels pending.\n"
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
    directory = parent / "fighter-scene-assembly-followup"
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
    require(len(matches) == 1 and value.count("EXPECTED_SCENE_ASSEMBLY_FOLLOWUP_HELPER_SHA256") == 1,
            "Workflow must have one exact helper-pin field")
    match = matches[0]
    return (value[:match.start(1)] + "0" * 64 + value[match.end(1):]).encode(), match.group(1)


def pin_sources():
    pinned(SWIFT_TEST, SWIFT_TEST_SHA)
    pinned(WORLD_SOURCE, WORLD_SOURCE_SHA)
    pinned(UI_TEST, UI_TEST_SHA)
    pinned(CHECKS, CHECKS_SHA)
    normalized, helper_sha = normalized_workflow(regular(ROOT / WORKFLOW, 64 * 1024).read_bytes())
    require(sha(normalized) == WORKFLOW_CANONICAL_SHA and helper_sha == digest(Path(__file__))
            and os.environ.get("EXPECTED_SCENE_ASSEMBLY_FOLLOWUP_HELPER_SHA256") == helper_sha,
            "Workflow, helper or exact helper-pin environment differs")
    resource_tools()


def selected_inventory():
    source = regular(ROOT / SWIFT_TEST, 512 * 1024).read_text()
    require(re.search(r"\bclass\s+" + CLASS_NAME + r"\b", source), "Selected class missing")
    require(re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M) == [METHOD_NAME]
            and "XCTSkip" not in source, "Only the one new no-skip diagnostic method may be selected")
    return [{"identifier": SELECTOR, "sourceFile": SWIFT_TEST, "sourceSHA256": digest(ROOT / SWIFT_TEST)}]


def ui_inventory():
    source = regular(ROOT / UI_TEST, 512 * 1024).read_text()
    method = UI_SELECTOR.rsplit("/", 1)[1]
    require("class DuelSharedRootVisualCaptureTests" in source and "XCTSkip" not in source
            and re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M) == [method],
            "Only the unchanged, previously failed UI method may be selected")
    return [{"identifier": UI_SELECTOR, "sourceFile": UI_TEST, "sourceSHA256": digest(ROOT / UI_TEST)}]


def app_source_policy():
    return {"baselineAppTree": BASELINE_APP_TREE, "retainedAppExceptWorldSHA256": OTHER_APP_SHA,
            "allowedChanges": [{"path": WORLD_SOURCE, "sha256": WORLD_SOURCE_SHA}],
            "otherAppAndCoreChanged": False}


def retained_tree_digest(rows, excluded):
    names = [row.split(b"\t", 1)[1].decode() for row in rows.splitlines()]
    require(set(excluded) <= set(names), "A new pinned file is absent from the committed tree")
    return sha(b"".join(row + b"\n" for row, name in zip(rows.splitlines(), names) if name not in excluded))


def validate_source_trees(entries, app, tests, ci_scripts, workflows):
    require(entries == REVIEWED_ENTRIES, "Core/shared/build/resource scripts changed from the 09f2f3c2 baseline")
    require(retained_tree_digest(app, {WORLD_SOURCE}) == OTHER_APP_SHA,
            "An App file other than the one reviewed World candidate changed")
    require(retained_tree_digest(tests, {SWIFT_TEST}) == OTHER_TESTS_SHA, "An existing test changed")
    require(retained_tree_digest(ci_scripts, {HELPER, CHECKS}) == OTHER_CI_SCRIPTS_SHA, "An existing CI helper changed")
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
            for path in ("App", "Tests", ".github/scripts", ".github/workflows")]
    validate_source_trees(entries, *rows)
    pin_sources()
    selected_inventory()
    ui_inventory()
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
    ]


def identity():
    value = read_json(work() / "identity.json")
    expected = {"sourceSHA": os.environ["GITHUB_SHA"], "runID": os.environ["GITHUB_RUN_ID"],
        "attempt": os.environ["GITHUB_RUN_ATTEMPT"], "executionScope": SCOPE,
        "sourceBaselineSHA": SOURCE_BASELINE, "reviewedEntries": REVIEWED_ENTRIES,
        "appSourcePolicy": app_source_policy(), "selectors": selected_inventory(), "expectedNativeMethods": 1,
        "uiSelectors": ui_inventory(), "expectedUIMethodsIfEligible": 1, "uiSelectionPolicy": UI_POLICY,
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedOriginalProjectorInstalled": True, "expectedAuxiliaryRendererCount": 0,
        "expectedExplicitPrepareCalls": 0, "expectedRendererRebindCalls": 0,
        "helperSHA256": digest(Path(__file__)), "workflowSHA256": digest(ROOT / WORKFLOW),
        "assetReleaseSHA256": RELEASE_SHA}
    require(all(type(value.get(k)) is type(v) and value.get(k) == v for k, v in expected.items()),
            "Prepared source, candidate, scope, method or conditional UI identity changed")
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
        "appSourcePolicy": app_source_policy(), "executionScope": SCOPE,
        "runID": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "ref": BRANCH, "selectors": selected_inventory(), "expectedNativeMethods": 1,
        "nativeExecutionStatus": "selected", "uiSelectors": ui_inventory(),
        "expectedUIMethodsIfEligible": 1, "uiSelectionPolicy": UI_POLICY,
        "preservedPriorEvidence": preserved_prior_evidence(),
        "reselectedFailedUIEvidence": {"runID": "43652056280", "sourceSHA": "532fb03083da7053417b7ad7ba484a99e4c41c28",
            "selector": UI_SELECTOR, "previousResult": "Failed", "countsBelongToCurrentRun": False},
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedOriginalProjectorInstalled": True, "expectedAuxiliaryRendererCount": 0,
        "expectedExplicitPrepareCalls": 0, "expectedRendererRebindCalls": 0,
        "sourceMapping": "09f2 baseline; only the exact World candidate changes App; one new native and one unchanged failed UI selector",
        "assetReleaseSHA256": RELEASE_SHA, "deltaManifestSHA256": DELTA_MANIFEST_SHA,
        "helperSHA256": digest(Path(__file__)), "workflowSHA256": digest(ROOT / WORKFLOW),
        "resourceToolsSHA256": RESOURCE_TOOLS_SHA, "recipientSPKISHA256": RECIPIENT_SPKI_SHA,
        "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "pixels": "PENDING", "physicalDevice": False, "TestFlight": False,
    })
    write_json(work() / "expected-resources.json", rows)
    print("Pinned one new native method and one conditional previously failed UI method; historical successes excluded; 373 resources unchanged.")


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


def verify_compiled_targets(targets, bundle_names):
    require(isinstance(targets, list) and all(isinstance(t, dict) for t in targets), "Malformed compiled targets")
    by_name = {target.get("BlueprintName"): target for target in targets}
    require(len(targets) == 2 and set(by_name) == {"SiteTests", "ArenaFlowTests"}
        and not by_name["SiteTests"].get("IsUITestBundle", False)
        and "-demo" in by_name["SiteTests"].get("CommandLineArguments", [])
        and by_name["ArenaFlowTests"].get("IsUITestBundle") is True
        and not any(target.get("SkipTestIdentifiers") for target in targets), "Compiled test targets differ")
    require(bundle_names == {"SiteTests.xctest", "ArenaFlowTests.xctest"}, "Unexpected test bundle")


def build():
    no_resource_keys(); identity(); once("build")
    require((work() / "stage-ok.json").is_file(), "Authenticated resources required")
    project = ROOT / "project.yml"; original = project.read_bytes(); source = original.decode()
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    require(source.count(needle) == 1, "Existing SiteTests host scheme is ambiguous")
    generated = source.replace(needle, needle + '\n        - ArenaFlowTests\n      commandLineArguments:\n        "-demo": true')
    spec = ROOT / TEMP_SPEC
    require(not spec.exists() and not spec.is_symlink(), "Temporary followup spec exists")
    spec.write_text(generated)
    write_json(work() / "compiled-project.json", {"originalSHA256": sha(original), "generatedSHA256": digest(spec),
        "onlyProjectConfigurationChange": "Add existing ArenaFlowTests and -demo to this run's temporary ShiftReminder scheme",
        "scheme": "ShiftReminder", "trackedProjectModified": False, "builtTargets": ["SiteTests", "ArenaFlowTests"],
        "builtTargetsDoNotProveExecution": True, "signingAllowed": False, "releaseSHA256": RELEASE_SHA})
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate", "--spec", spec.name], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
        "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGN_IDENTITY=", "FIGHTER_ASSET_RELEASE_SHA256=" + RELEASE_SHA], "native-build", 1200)
    products = work() / "derived/Build/Products"; runs = list(products.glob("*.xctestrun"))
    require(len(runs) == 1, "Ambiguous build-for-testing result")
    targets = resource_tools().dependencies().test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    bundles = list(products.rglob("*.xctest"))
    verify_compiled_targets(targets, {path.name for path in bundles})
    require(project.read_bytes() == original, "Tracked project specification changed")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    audit_resources(app, read_json(work() / "expected-resources.json"), bundled=True)
    info = plistlib.loads(regular(app / "Info.plist", 1024**2).read_bytes())
    require(info.get("FighterAssetReleaseSHA256") == RELEASE_SHA and info.get("ArenaCommitSHA") == os.environ["GITHUB_SHA"]
        and info.get("CFBundleIdentifier") == "com.kriswu.shiftreminder", "Compiled App source or release differs")
    require(not any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()), "Key or cipher material entered App")
    (work() / "build-ok.txt").write_text("One unsigned build; exactly two test targets; 373 compiled resources verified.\n")
    print("Built two existing test targets once; target presence is not execution evidence.")


def simulator_name():
    return "Fighter scene assembly followup " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]


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


def verify_results(summary, data, device, selector=SELECTOR):
    require(selector in (SELECTOR, UI_SELECTOR), "Unreviewed test selector")
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
                require(isinstance(raw, str) and raw.removesuffix("()") in (selector, "/".join(selector.split("/")[1:]))
                        and node.get("result") == "Passed", "Unexpected, skipped or failed diagnostic method")
                seen.append(selector)
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    require(seen == [selector], "Missing, duplicate or additional method")
    configurations = summary.get("devicesAndConfigurations")
    require(isinstance(configurations, list) and len(configurations) == 1, "Exactly one result device is required")
    configuration = configurations[0]
    observed = configuration.get("device", {})
    require(observed.get("deviceId") == device["udid"] and observed.get("deviceName") == device["name"]
            and observed.get("modelName") == "iPhone 17 Pro Max" and observed.get("platform") == "iOS Simulator"
            and all(type(configuration.get(key)) is int and configuration[key] == value for key, value in
                    (("passedTests", 1), ("failedTests", 0), ("skippedTests", 0))), "Result device or its counts differ")


def execute_method(scope):
    require(scope in ("native", "ui"), "Unknown execution scope")
    no_resource_keys(); identity()
    if scope == "ui":
        require_native_ready_for_ui()
    once(scope)
    require((work() / "build-ok.txt").is_file(), "Verified build required")
    selector = SELECTOR if scope == "native" else UI_SELECTOR
    device = read_json(work() / "simulator.json")
    command = ["xcodebuild", "test-without-building", "-xctestrun", (work() / "xctestrun-path.txt").read_text(),
        "-destination", "id=" + device["udid"], "-parallel-testing-enabled", "NO",
        "-resultBundlePath", str(work() / (scope + ".xcresult")), "-only-testing:" + selector]
    code = run_logged(command, "selected-" + scope, 720 if scope == "native" else 360, check=False)
    result = {"exitCode": code, "selectedCount": 1, "iterations": 1, "exports": {}}
    write_json(work() / (scope + "-process.json"), result)
    if (work() / (scope + ".xcresult/Info.plist")).is_file():
        for kind in ("summary", "tests"):
            try:
                result["exports"][kind] = run_logged(["xcrun", "xcresulttool", "get", "test-results", kind,
                    "--path", str(work() / (scope + ".xcresult"))], scope + "-result-" + kind, 60, check=False,
                    output_name=scope + "-" + kind + ".json")
            except Exception as error:
                result["exports"][kind] = type(error).__name__
    write_json(work() / (scope + "-process.json"), result)
    if code:
        raise PhaseFailure(scope + " invocation failed; original results and process code retained", code)
    require(result["exports"] == {"summary": 0, "tests": 0}, "Result exports unavailable")
    verify_results(read_json(work() / (scope + "-summary.json")), read_json(work() / (scope + "-tests.json")), device, selector)
    (work() / (scope + "-ok.txt")).write_text("1 passed; 0 failed; 0 skipped; exactly the reviewed method once. Pixels pending.\n")
    print(scope + " XCTest: one exact method passed; historical successful methods excluded; pixels pending.")


def verify_runtime_log(path, *, collection_code, device, started, finished, scope="native"):
    require(scope in ("native", "ui"), "Unknown runtime scope")
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
        "coverage": "Full " + scope + " invocation through result export; complete source scanned before sealing",
        "sourceBytes": len(raw), "sourceSHA256": sha(raw), "entries": len(events), "appEntries": len(stamps),
        "firstAppEntryUTC": min(stamps).isoformat(), "lastAppEntryUTC": max(stamps).isoformat(),
        "knownDiagnosticCounts": counts, "knownDiagnosticCount": sum(counts.values()),
        "knownDiagnosticsAbsent": not any(counts.values()), "sealedTextTailOnly": len(raw) > 2 * 1024**2,
        "pixels": "PENDING", "liveUIValidated": False, "performanceAcceptance": False}


def collect_runtime(started, finished, scope="native"):
    require(scope in ("native", "ui"), "Unknown runtime scope")
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


def invoke_with_runtime(scope):
    if scope == "ui":
        require_native_ready_for_ui()
    started, failure = datetime.datetime.now(datetime.timezone.utc), None
    try:
        execute_method(scope)
    except Exception as error:
        failure = error
    try:
        collect_runtime(started, datetime.datetime.now(datetime.timezone.utc), scope)
    except Exception as error:
        prefix = "runtime" if scope == "native" else "ui-runtime"
        write_json(work() / (prefix + "-failure.json"), {"errorType": type(error).__name__, "detail": str(error)[:2000]})
        if failure is None: failure = error
    if failure is not None: raise failure


def test():
    invoke_with_runtime("native")


def ui():
    no_resource_keys(); identity()
    receipt = require_native_ready_for_ui()
    write_json(work() / "ui-eligibility.json", receipt)
    invoke_with_runtime("ui")


def png_pixels(raw):
    require(isinstance(raw, bytes) and 0 < len(raw) <= 24 * 1024**2 and raw[:8] == b"\x89PNG\r\n\x1a\n",
            "Expected bounded original PNG")
    offset, chunks, header, ended = 8, [], None, False
    while offset < len(raw):
        require(offset + 12 <= len(raw), "Truncated PNG chunk")
        size = struct.unpack(">I", raw[offset:offset + 4])[0]
        kind = raw[offset + 4:offset + 8]; end = offset + 12 + size
        require(end <= len(raw), "PNG chunk exceeds bytes")
        body = raw[offset + 8:offset + 8 + size]
        require(zlib.crc32(kind + body) & 0xffffffff == struct.unpack(">I", raw[end - 4:end])[0], "PNG CRC differs")
        if header is None:
            require(kind == b"IHDR" and size == 13, "PNG IHDR missing")
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IHDR": raise ValueError("Repeated PNG header")
        require(kind != b"tRNS" and (kind in (b"IHDR", b"IDAT", b"IEND") or bool(kind[0] & 32)),
                "Unsupported critical PNG or transparency chunk")
        if kind == b"IDAT": chunks.append(body)
        if kind == b"IEND":
            require(size == 0 and end == len(raw), "Unexpected PNG suffix")
            ended = True; break
        offset = end
    require(header and ended and chunks, "PNG structure incomplete")
    width, height, depth, color, compression, filtering, interlace = header
    require((width, height) == (956, 440) and depth == 8 and color in (2, 6)
            and compression == filtering == interlace == 0, "Original capture PNG format differs")
    channels = 4 if color == 6 else 3; stride = width * channels; expected = height * (stride + 1)
    decoder = zlib.decompressobj(); data = decoder.decompress(b"".join(chunks), expected + 1)
    require(len(data) == expected and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
            "PNG decoded size differs")
    previous = bytearray(stride); cursor = opaque = black = transparent = visible = 0
    for _ in range(height):
        filter_type = data[cursor]; cursor += 1
        require(filter_type <= 4, "Unsupported PNG row filter")
        row = bytearray(data[cursor:cursor + stride]); cursor += stride
        for i in range(stride):
            left = row[i - channels] if i >= channels else 0; up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1: row[i] = (row[i] + left) & 255
            elif filter_type == 2: row[i] = (row[i] + up) & 255
            elif filter_type == 3: row[i] = (row[i] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                prediction = left + up - upper_left
                pa, pb, pc = abs(prediction-left), abs(prediction-up), abs(prediction-upper_left)
                nearest = left if pa <= pb and pa <= pc else (up if pb <= pc else upper_left)
                row[i] = (row[i] + nearest) & 255
        for i in range(0, stride, channels):
            red, green, blue = row[i:i+3]; alpha = row[i+3] if channels == 4 else 255
            opaque += int(alpha == 255); transparent += int(alpha == 0)
            black += int(alpha == 255 and red == green == blue == 0)
            visible += int(alpha > 0 and bool(red or green or blue))
        previous = row
    return {"bytes": len(raw), "sha256": sha(raw), "width": width, "height": height,
        "pixelCount": width * height, "opaquePixelCount": opaque, "opaqueBlackPixelCount": black,
        "transparentPixelCount": transparent, "visibleNonBlackPixelCount": visible}


def typed_equal(left, right):
    if type(left) is not type(right): return False
    if isinstance(right, dict): return set(left) == set(right) and all(typed_equal(left[k], v) for k, v in right.items())
    if isinstance(right, list): return len(left) == len(right) and all(typed_equal(a, b) for a, b in zip(left, right))
    return left == right


def exact_fields(value, expected, detail):
    require(isinstance(value, dict) and all(k in value and typed_equal(value[k], v) for k, v in expected.items()), detail)


def validate_report(value, images):
    """Keep complete black-frame failures; only actual opaque nonblack pixels pass the narrow regression."""
    label = FRAME_LABELS[0]
    exact_fields(value, {"schemaVersion": 1, "schema": REPORT_SCHEMA, "scope": SCOPE, "releaseSHA256": RELEASE_SHA,
        "diagnosticCompleted": True, "lastPhase": "captured-before-regression-assertions",
        "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0, "explicitDrawStateCalls": 0,
        "captureFrameCalls": 1, "activeSceneRebindCalls": 0, "freshRendererCreationCalls": 0,
        "freshAssociationCalls": 0, "explicitPrepareCalls": 0, "snapshotCalls": 0, "projectorDetachCalls": 0,
        "stateInvariant": True, "identityInvariant": True, "combatStateInjected": False,
        "liveDisplayLinkAdvancesSelected": False, "sourcePacketsExpectedZero": True, "sceneKitLightsChanged": False,
        "firstCompleteOffscreenEncodingSelected": True, "normalDrawablePresentationValidated": False,
        "uiExecutionStatus": "not_selected", "physicalDeviceValidated": False, "liveUIValidated": False,
        "audiblePlaybackVerified": False, "performanceVerified": False, "pixels": "PENDING",
        "panguEquipmentActivated": False, "captureTimingIncludesGPUReadbackWait": True, "captureLabels": [label]},
        "Cold assembly report identity or experiment differs")
    def finite(v): return type(v) in (int, float) and math.isfinite(v)
    def matrix(v): return isinstance(v, list) and len(v) == 16 and all(finite(n) for n in v)
    require(finite(value.get("elapsedSeconds")) and value["elapsedSeconds"] >= 0, "Invalid elapsed wall time")
    exact_fields(value.get("construction"), {"sceneAssemblyCompleted": True, "surfaceCreationAttempts": 1,
        "initialPoseAppliedBeforeSurface": True, "surfaceSubviewCount": 1, "samePacketRenderer": True,
        "originalProjectorInstalled": True, "originalProjectorHasEncodedFrame": False,
        "renderCallbackInstalled": True, "lateGeometryProviderInstalled": True, "frameDriverInstalled": True,
        "surfaceSubmittedFrames": 0, "surfaceLastSubmittedTick": None, "frame": 0, "animationTick": 0,
        "sourceLiveTick": 0, "displayLinkCallbacks": 0}, "Cold construction or sole-surface binding differs")
    require(all(type(value["construction"].get(k)) is bool for k in
                ("sessionPaused", "worldWindowAbsent", "worldBoundsEmpty")), "Construction observation missing")
    exact_fields(value.get("beforeFirstCapture"), {"surfaceSubmittedFrames": 0, "surfaceLastSubmittedTick": None,
        "projectorLastFrameAvailable": False, "sourceProjectorInstalled": True, "displayLinkCallbacks": 0,
        "frame": 0, "animationTick": 0, "sourceLiveTick": 0, "submittedPackets": 0, "sourceEffectIDs": [],
        "sameActiveSurface": True, "sameActiveRenderer": True, "sameScene": True, "samePointOfView": True},
        "A normal submission, projector frame or ownership change occurred before first capture")
    samples, captures = value.get("samples"), value.get("captures")
    require(isinstance(samples, list) and len(samples) == 1 and isinstance(captures, list) and len(captures) == 1
            and isinstance(images, dict) and set(images) == {label}, "Expected exactly one original frame and sample")
    sample, capture, image = samples[0], captures[0], images[label]
    stat_keys = ("width", "height", "pixelCount", "opaquePixelCount", "opaqueBlackPixelCount",
                 "transparentPixelCount", "visibleNonBlackPixelCount")
    require(all(type(image.get(k)) is int and image[k] >= 0 for k in (*stat_keys, "bytes"))
        and image["width"] == 956 and image["height"] == 440 and image["pixelCount"] == 420640
        and 0 < image["bytes"] <= 24 * 1024**2 and re.fullmatch(r"[a-f0-9]{64}", image.get("sha256", "")),
        "Independent original PNG metadata invalid")
    nonblack = image["visibleNonBlackPixelCount"] > 0
    passed = nonblack and image["opaquePixelCount"] == image["pixelCount"]
    exact_fields(value.get("pixelStatistics"), {**{key: image[key] for key in stat_keys},
        "source": "decoded-original-png", "representation": "sRGB-RGBA8-premultipliedLast-byteOrder32Big",
        "criterion": "alpha > 0 and at least one RGB channel > 0", "opaqueOutputExpected": True,
        "nonBlackRegressionPassed": nonblack}, "Native pixel claims differ from independent original PNG bytes")
    require(type(value.get("nonBlackRegressionPassed")) is bool and value["nonBlackRegressionPassed"] is nonblack,
            "Nonblack report flag disagrees with pixels")
    route = {"label": label, "frame": 0, "animationTick": 0, "sourceLiveTick": 0,
        "rendererRoute": "surface.captureFrame", "sourceProjectorInstalled": True, "projectorEncodedForCapture": True,
        "surfaceSubmittedFrames": 0, "surfaceLastSubmittedTick": None, "submittedPackets": 0,
        "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": 4}
    exact_fields(capture, {**route, "pngSHA256": image["sha256"], "bytes": image["bytes"], "width": 956, "height": 440,
        "pixelsRequireReview": True, "simulationAndModelCameraUnchanged": True,
        "isolation": "first complete offscreen encoding after cold World assembly; original projector always installed; no registration workaround"},
        "Original PNG bytes or full-path capture provenance differs")
    exact_fields(sample, {**route, "displayLinkCallbacks": 0, "sourceIntroActive": True,
        "sourceStance": "firstBirth", "sourceStanceTick": 0, "weaponReady": False, "branchesReady": False,
        "sourceEffectIDs": [], "sameActiveSurface": True, "sameActiveRenderer": True, "sameScene": True,
        "samePointOfView": True, "sameOriginalProjector": True, "sameFrameDriver": True,
        "renderCallbackInstalled": True, "lateGeometryProviderInstalled": True,
        "rendererUsesReverseZ": False, "rendererAutoenablesDefaultLighting": False, "rendererIsPlaying": False,
        "simulationInvariant": True, "identityInvariant": True,
        "rendererFailure": "", "surfaceFailure": "", "sourcePreparationFailure": ""}, "Full-path sample or clocks differ")
    projector = sample.get("projectorLastFrame")
    exact_fields(projector, {"available": True, "tick": 0}, "Original projector did not encode the first complete frame")
    require(finite(projector.get("aspect")) and projector["aspect"] > 0
        and isinstance(projector.get("sourceCameraPosition"), list) and len(projector["sourceCameraPosition"]) == 3
        and all(finite(n) for n in projector["sourceCameraPosition"])
        and all(matrix(projector.get(k)) for k in ("sourceView", "sourceProjection", "sourceShadowMatrix"))
        and all(type(projector.get(k)) is int and 0 <= projector[k] <= 10_000_000 for k in ("casterCount", "triangleCount"))
        and isinstance(projector.get("factors"), list) and all(finite(n) for n in projector["factors"]),
        "Projector original metadata missing or invalid")
    camera = sample.get("camera")
    require(isinstance(camera, dict) and all(matrix(camera.get(k)) for k in
        ("modelWorldTransform", "presentationWorldTransform", "metalProjection")), "Camera matrices invalid")
    for key in ("model", "presentation"):
        values = camera.get(key)
        require(isinstance(values, dict) and type(values.get("exists")) is bool, "Camera observation missing")
        if key == "presentation" and values["exists"] is False:
            require(set(values) == {"exists"}, "Absent presentation camera payload differs"); continue
        require(values["exists"] and matrix(values.get("projectionTransform"))
            and all(finite(values.get(k)) for k in ("fieldOfView", "near", "far", "orthographicScale"))
            and type(values.get("categoryMask")) is int and type(values.get("usesOrthographicProjection")) is bool,
            "Camera values invalid")
    fighters = sample.get("fighters")
    require(isinstance(fighters, list) and len(fighters) == 2, "Two real fighters required")
    for seat, fighter in enumerate(fighters):
        exact_fields(fighter, {"index": seat, "hero": ("ember", "liu")[seat], "health": 1000, "clipTick": 0},
                     "Fighter identity or frame-zero state differs")
        require(type(fighter.get("x")) is int and type(fighter.get("y")) is int
                and isinstance(fighter.get("clip"), str) and bool(fighter["clip"]), "Fighter pose observation missing")
    inventory = sample.get("sceneInventory")
    require(isinstance(inventory, list) and 1 <= len(inventory) <= 512, "Scene inventory missing")
    for row in inventory:
        require(isinstance(row, dict) and isinstance(row.get("name"), str) and type(row.get("hidden")) is bool
            and finite(row.get("opacity")) and all(type(row.get(k)) is int and 0 <= row[k] <= 100_000
            for k in ("geometries", "skinners")), "Scene inventory malformed")
    names = collections.Counter(row["name"] for row in inventory)
    require(all(names[name] == 1 for name in ("duel.stage.palace", "duel.actor.0", "duel.actor.1")), "Installed scene roots missing")
    viewport = sample.get("viewport")
    require(isinstance(viewport, dict) and all(finite(viewport.get(k)) and viewport[k] == v for k, v in
        (("pointsWidth", 956), ("pointsHeight", 440), ("captureWidth", 956), ("captureHeight", 440)))
        and all(finite(viewport.get(k)) and viewport[k] >= 0 for k in ("drawableWidth", "drawableHeight"))
        and all(finite(viewport.get(k)) and viewport[k] > 0 for k in ("viewScale", "surfaceScale")), "Viewport differs")
    cleanup = value.get("cleanup")
    exact_fields(cleanup, {"worldSceneReleased": True, "worldSurfaceReleased": True, "worldPacketRendererReleased": True,
        "surfaceSceneDetached": True, "surfacePointOfViewDetached": True, "surfaceDelegateDetached": True,
        "sourceProjectorDetached": True, "renderCallbackCleared": True, "lateGeometryProviderCleared": True,
        "objectDeallocationVerified": False}, "Original owners or callbacks were not cleared")
    require(type(cleanup.get("activeClocksBefore")) is int and cleanup["activeClocksBefore"] >= 0
        and type(cleanup.get("activeClocksAfter")) is int and cleanup["activeClocksAfter"] == cleanup["activeClocksBefore"],
        "World clock ownership leaked")
    timings = value.get("timings")
    require(isinstance(timings, list) and 1 <= len(timings) <= 32 and all(isinstance(row, dict)
        and isinstance(row.get("phase"), str) and finite(row.get("seconds")) and row["seconds"] >= 0 for row in timings), "Timings malformed")
    phases = collections.Counter(row["phase"] for row in timings)
    require(all(phases[phase] == 1 for phase in ("construct-session", "construct-world", "mount-layout",
        "cold-first-offscreen-capture", "decode-png-pixel-statistics")), "Cold first-capture timing evidence incomplete")
    return {"structureVerified": True, "coldFrameRegressionPassed": passed,
        "nonBlackCriterionPassed": nonblack, "pixelStatistics": {key: image[key] for key in stat_keys},
        "firstCompleteOffscreenEncoding": True, "normalDrawablePresentationValidated": False,
        "explicitDrawStateCalls": 0, "captureFrameCalls": 1, "normalSubmittedFrames": 0,
        "sourceProjectorEncodedAtTick": 0, "auxiliaryRendererCount": 0, "rendererRebindCalls": 0,
        "prepareCalls": 0, "originalPNGHash": image["sha256"], "pixels": "PENDING"}


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
                images[label] = png_pixels(path.read_bytes())
            else:
                require(suffix in (".json", ".txt"), "Expected JSON diagnostic report")
                diagnostic = read_json(path)
            labels.add(label)
            mandatory_bytes += path.stat().st_size
            entries.append({"label": label, "selector": SELECTOR, "file": name, "kind": kind,
                            "bytes": path.stat().st_size, "sha256": digest(path)})
    require(labels == set(EXPECTED_ATTACHMENTS), "Missing required diagnostic captures or report")
    assembly_observations = validate_report(diagnostic, images)
    require(mandatory_bytes <= 160 * 1024**2 and automatic_bytes <= 256 * 1024**2, "Evidence category exceeds bounded budget")
    return {"completeExpectedLabels": True, "exactMethodAndSimulatorOwnership": True, "files": entries,
            "automaticDiagnostics": automatic, "automaticAttachmentsNeverCountAsCoverage": True,
            "assemblyObservations": assembly_observations, "pixels": "PENDING"}


def export():
    no_resource_keys(); identity(); once("native-export")
    result = work() / "native.xcresult"
    try:
        require((result / "Info.plist").is_file(), "Native result bundle unavailable")
        directory = work() / "native-attachments"
        run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                    "--output-path", str(directory)], "native-export-attachments", 180)
        receipt = attachment_inventory(directory, read_json(work() / "simulator.json"))
        write_json(work() / "attachments-ok.json", receipt)
    except Exception as error:
        write_json(work() / "attachments-failure.json", {"errorType": type(error).__name__, "detail": str(error)[:2000]})
        raise
    print("Exported one original native frame and report; nonblack regression is distinct from visual acceptance.")


def export_ui():
    no_resource_keys(); identity(); once("ui-export")
    try:
        require((work() / "ui-invoked.json").is_file(), "UI was blocked or never invoked")
        bundle, directory = work() / "ui.xcresult", work() / "ui-attachments"
        require((bundle / "Info.plist").is_file(), "No finalized UI result bundle")
        run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                    "--output-path", str(directory)], "ui-export-attachments", 180)
        # Pure bounded file/label/method/device validation only. No old scope,
        # globals, source gate, execution, export operation or report is invoked.
        receipt = resource_tools().ui_remediation_attachment_inventory(directory, read_json(work() / "simulator.json"))
        write_json(work() / "ui-attachments-ok.json", receipt)
    except Exception as error:
        write_json(work() / "ui-attachments-failure.json", {"errorType": type(error).__name__, "detail": str(error)[:2000]})
        raise
    print("Exported exact prior-failed UI method evidence; partial failures remain private when incomplete.")


def require_native_ready_for_ui():
    require((work() / "native-ok.txt").is_file(), "UI blocked: the new native method did not pass")
    device = read_json(work() / "simulator.json")
    process = read_json(work() / "native-process.json")
    require(process.get("exitCode") == 0 and process.get("selectedCount") == 1 and process.get("iterations") == 1
            and process.get("exports") == {"summary": 0, "tests": 0}, "UI blocked: native invocation differs")
    verify_results(read_json(work() / "native-summary.json"), read_json(work() / "native-tests.json"), device)
    receipt = attachment_inventory(work() / "native-attachments", device)
    require(receipt == read_json(work() / "attachments-ok.json"), "UI blocked: native evidence changed")
    require(receipt["assemblyObservations"].get("coldFrameRegressionPassed") is True,
            "UI blocked: the original full frame is black, transparent or not verified")
    require(runtime_summary("native").get("verified") is True, "UI blocked: native full-runtime gate failed")
    return {"nativeExactOncePassed": True, "nativeOriginalNonblackFrameVerified": True,
            "nativeEvidenceVerified": True, "nativeFullRuntimeVerified": True,
            "sameRunID": os.environ["GITHUB_RUN_ID"], "sameSourceSHA": os.environ["GITHUB_SHA"],
            "sameSimulatorUDID": device["udid"], "uiSelector": UI_SELECTOR}


def bounded_attachments():
    all_paths, priority, required_by_scope, scope_paths = [], set(), {}, {}
    shared = resource_tools()
    for scope in ("native", "ui"):
        directory = work() / (scope + "-attachments")
        paths = attachment_files(directory) if directory.exists() else []
        scope_paths[scope] = paths
        all_paths += [(scope, path) for path in paths]
        manifest = directory / "manifest.json"
        if manifest in paths: priority.add(manifest)
        if manifest in paths and 0 < manifest.stat().st_size <= 24 * 1024**2:
            try:
                groups = read_json(manifest, 24 * 1024**2)
                for group in groups if isinstance(groups, list) else []:
                    for item in group.get("attachments", []) if isinstance(group, dict) else []:
                        if not isinstance(item, dict): continue
                        name = item.get("exportedFileName"); path = directory / name if isinstance(name, str) else None
                        candidates = (attachment_label(item, path) if scope == "native" else
                            shared.attachment_label(item, path, shared.EXPECTED_ATTACHMENTS["ui"])) if path in paths else []
                        if candidates: priority.add(path)
            except (OSError, ValueError, TypeError): pass
        receipt_path = work() / ("attachments-ok.json" if scope == "native" else "ui-attachments-ok.json")
        required = set()
        if receipt_path.is_file():
            receipt = read_json(receipt_path)
            required = {directory / row["file"] for row in receipt["files"]} | {manifest}
            priority.update(required)
        required_by_scope[scope] = required
    selected, omitted, total = [], {"native": [], "ui": []}, 0
    for scope, path in sorted(all_paths, key=lambda row: (row[1] not in priority, row[0], row[1].as_posix())):
        size, suffix = path.stat().st_size, path.suffix.lower()
        reason = ("unsupported-media-type" if suffix not in (".png", ".json", ".txt") else
                  "empty-system-record" if not size else "sealed-file-limit" if size > 24 * 1024**2 else
                  "sealed-total-or-count-limit" if total + size > 160 * 1024**2 or len(selected) >= 256 else None)
        if reason:
            omitted[scope].append({"file": path.name, "bytes": size, "sha256": digest(path), "reason": reason,
                "mandatoryLabelCandidate": path in priority, "countsAsCoverage": False})
            continue
        total += size; selected.append((path, scope + "-attachments/" + path.name))
    selected_paths = {path for path, _ in selected}
    policies = {}
    for scope in ("native", "ui"):
        chosen = [(path, name) for path, name in selected if name.startswith(scope + "-attachments/")]
        required = required_by_scope[scope]
        policy = {"selectedFileCount": len(chosen), "selectedBytes": sum(path.stat().st_size for path, _ in chosen),
            "omittedFileCount": len(omitted[scope]), "omitted": omitted[scope],
            "mandatoryValidationPassed": bool(required),
            "completeValidatedMandatorySetSealed": bool(required) and required <= selected_paths,
            "automaticAttachmentsNeverCountAsCoverage": True}
        policies[scope] = policy
    write_json(work() / "attachment-seal-policy.json", {"scopes": policies,
        "selectedFileCount": len(selected), "selectedBytes": total, "sharedMaximumFiles": 256,
        "sharedMaximumBytes": 160 * 1024**2, "mandatoryAndManifestPriorityAcrossBothScopes": True})
    return selected


def runtime_summary(scope="native"):
    require(scope in ("native", "ui"), "Unknown runtime scope")
    prefix = "runtime" if scope == "native" else "ui-runtime"
    try:
        value = read_json(work() / (prefix + "-diagnostics.json")); source = work() / (prefix + "-log.log")
        marker = work() / (prefix + "-ok.txt")
        verified = (marker.is_file() and marker.read_text() == (RUNTIME_OK if scope == "native" else UI_RUNTIME_OK)
            and value.get("invocationScope") == scope and value.get("collectionExitCode") == 0
            and value.get("completeJSONParsed") is True and value.get("ownedSimulatorVerified") is True
            and value.get("simulatorUDID") == read_json(work() / "simulator.json").get("udid")
            and type(value.get("appEntries")) is int and value["appEntries"] > 0
            and value.get("knownDiagnosticCounts") == {key: 0 for key in METAL_DIAGNOSTICS}
            and value.get("knownDiagnosticCount") == 0 and value.get("knownDiagnosticsAbsent") is True
            and source.is_file() and value.get("sourceBytes") == source.stat().st_size
            and value.get("sourceSHA256") == digest(source) and value.get("pixels") == "PENDING"
            and value.get("liveUIValidated") is False and value.get("performanceAcceptance") is False)
        return dict(value, verified=bool(verified))
    except (OSError, ValueError, KeyError, TypeError):
        return {"verified": False, "status": "UNAVAILABLE", "invocationScope": scope, "pixels": "PENDING"}


def ui_execution_state(native_ready):
    invoked = (work() / "ui-invoked.json").is_file()
    artifacts = sorted(path.name for path in work().iterdir()
        if path.name.startswith(("ui-", "selected-ui")) or path.name == "ui.xcresult")
    if invoked:
        return {"status": "selected", "expectedMethods": 1, "observedMethods": None,
                "blockedByNative": False, "unexpectedArtifactsWhenBlocked": []}
    return {"status": "eligible_not_executed" if native_ready else "blocked_by_native",
        "expectedMethods": 1 if native_ready else 0,
        "observedMethods": None if artifacts else 0, "blockedByNative": not native_ready,
        "unexpectedArtifactsWhenBlocked": artifacts if not native_ready else []}


def public_summary():
    ident = read_json(work() / "identity.json")
    runtime, ui_runtime = runtime_summary("native"), runtime_summary("ui")
    native_capture = (work() / "attachments-ok.json").is_file()
    observation = read_json(work() / "attachments-ok.json").get("assemblyObservations") if native_capture else None
    native_exact = (work() / "native-ok.txt").is_file()
    nonblack = observation.get("coldFrameRegressionPassed") if isinstance(observation, dict) else None
    ready = native_exact and native_capture and nonblack is True and runtime["verified"]
    ui_state = ui_execution_state(ready)
    result = {"sourceSHA": ident["sourceSHA"], "sourceBaselineSHA": SOURCE_BASELINE, "executionScope": SCOPE,
        "appSourcePolicy": app_source_policy(), "runID": ident["runID"], "attempt": ident["attempt"],
        "expectedNativeMethods": 1, "expectedUIMethodsIfEligible": 1, "uiSelectionPolicy": UI_POLICY,
        "uiExecutionStatus": ui_state["status"], "uiExecution": ui_state,
        "uiExactMethodPassed": (work() / "ui-ok.txt").is_file(),
        "expectedSimulationFrames": [0], "expectedSimulationAdvanceCalls": 0,
        "reportSchema": REPORT_SCHEMA, "expectedCaptureLabels": list(FRAME_LABELS),
        "expectedOriginalProjectorInstalled": True, "expectedAuxiliaryRendererCount": 0,
        "expectedExplicitPrepareCalls": 0, "expectedRendererRebindCalls": 0,
        "preservedPriorEvidence": preserved_prior_evidence(),
        "reselectedFailedUIEvidence": ident["reselectedFailedUIEvidence"],
        "assetReleaseSHA256": RELEASE_SHA, "deltaManifestSHA256": DELTA_MANIFEST_SHA,
        "resourcesAuthenticated": (work() / "stage-ok.json").is_file(),
        "compiled373ResourcesVerified": (work() / "build-ok.txt").is_file(),
        "nativeExactMethodPassed": native_exact, "exactDiagnosticCaptureSetVerified": native_capture,
        "coldFrameRegressionPassed": nonblack, "assemblyObservations": observation,
        "normalDrawablePresentationValidatedByNative": False,
        "uiEligibleAfterNativeEvidence": bool(ready),
        "exactUICaptureSetVerified": (work() / "ui-attachments-ok.json").is_file(),
        "sealedDiagnosticCaptureSetComplete": False, "sealedUICaptureSetComplete": False,
        "runtimeDiagnostics": runtime, "runtimeDiagnosticGatePassed": runtime["verified"],
        "uiRuntimeDiagnostics": ui_runtime, "uiRuntimeDiagnosticGatePassed": ui_runtime["verified"],
        "pixels": "PENDING", "liveUIValidated": False, "physicalIPhoneAcceptance": "NOT VERIFIED",
        "performanceAcceptance": False, "audiblePlayback": "NOT VERIFIED", "productionPanguAssetsActivated": False,
        "previous117SelectedAgain": False, "previousFiveSelectedAgain": False, "previousSixSelectedAgain": False,
        "previousEntranceDiagnosticSelectedAgain": False, "previousSceneBaseDiagnosticSelectedAgain": False,
        "previousScenePreparationDiagnosticSelectedAgain": False, "previousSceneRegistrationDiagnosticSelectedAgain": False,
        "TestFlightUploaded": False}
    if (work() / "attachment-seal-policy.json").is_file():
        policy = read_json(work() / "attachment-seal-policy.json")
        result["attachmentSealPolicy"] = policy
        result["sealedDiagnosticCaptureSetComplete"] = policy["scopes"]["native"]["completeValidatedMandatorySetSealed"] is True
        result["sealedUICaptureSetComplete"] = policy["scopes"]["ui"]["completeValidatedMandatorySetSealed"] is True
    for scope in ("native", "ui"):
        result[scope + "ObservedCounts"] = None
        if (work() / (scope + "-process.json")).is_file():
            result[scope + "Process"] = {key: value for key, value in read_json(work() / (scope + "-process.json")).items()
                                        if key in ("exitCode", "selectedCount", "iterations")}
        if (work() / (scope + "-summary.json")).is_file():
            try:
                counts = read_json(work() / (scope + "-summary.json"))
                result[scope + "ObservedCounts"] = {key: counts.get(key) for key in
                    ("totalTestCount", "passedTests", "failedTests", "skippedTests", "result")}
                if scope == "ui" and type(counts.get("totalTestCount")) is int:
                    result["uiExecution"]["observedMethods"] = counts["totalTestCount"]
            except (OSError, ValueError): result[scope + "ObservedCounts"] = "UNAVAILABLE"
    if (work() / "timings.json").is_file(): result["timings"] = read_json(work() / "timings.json")
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
    print(json.dumps(value, ensure_ascii=False, indent=2))
    require(value.get("sourceSHA") == os.environ["GITHUB_SHA"] and value.get("sourceBaselineSHA") == SOURCE_BASELINE
        and value.get("executionScope") == SCOPE and value.get("expectedNativeMethods") == 1
        and value.get("appSourcePolicy") == app_source_policy() and value.get("uiSelectionPolicy") == UI_POLICY,
        "Final scope or source identity differs")
    require(value.get("pixels") == "PENDING" and value.get("normalDrawablePresentationValidatedByNative") is False
        and value.get("liveUIValidated") is False and value.get("physicalIPhoneAcceptance") == "NOT VERIFIED"
        and value.get("performanceAcceptance") is False and value.get("audiblePlayback") == "NOT VERIFIED"
        and value.get("productionPanguAssetsActivated") is False and value.get("TestFlightUploaded") is False
        and all(value.get(k) is False for k in ("previous117SelectedAgain", "previousFiveSelectedAgain", "previousSixSelectedAgain",
            "previousEntranceDiagnosticSelectedAgain", "previousSceneBaseDiagnosticSelectedAgain",
            "previousScenePreparationDiagnosticSelectedAgain", "previousSceneRegistrationDiagnosticSelectedAgain")),
        "Method, nonblack or completion cannot become broader acceptance or historical execution")
    expected_counts = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "result": "Passed"}
    require(typed_equal(value.get("nativeObservedCounts"), expected_counts)
            and typed_equal(value.get("uiObservedCounts"), expected_counts),
            "Final native and conditional UI method counts must each be exactly one real pass")
    gates = ("resourcesAuthenticated", "compiled373ResourcesVerified", "nativeExactMethodPassed", "coldFrameRegressionPassed",
        "exactDiagnosticCaptureSetVerified", "sealedDiagnosticCaptureSetComplete", "runtimeDiagnosticGatePassed",
        "uiEligibleAfterNativeEvidence", "uiExactMethodPassed", "exactUICaptureSetVerified", "sealedUICaptureSetComplete",
        "uiRuntimeDiagnosticGatePassed", "diagnosticsSealed", "cleanupComplete")
    require(value.get("uiExecutionStatus") == "selected"
        and value.get("uiExecution", {}).get("observedMethods") == 1
        and not value.get("uiExecution", {}).get("unexpectedArtifactsWhenBlocked"),
        "Conditional UI did not execute exactly once; blocked is not passed")
    require(all(value.get(key) is True for key in gates), "Followup did not reach every native, conditional UI and evidence gate")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("prepare", "tools", "stage", "build", "simulator", "test", "export", "ui", "export_ui", "seal", "cleanup", "report"))
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
        print("Scene-assembly followup phase failed: " + operation + "; private evidence retained when prepared.", file=sys.stderr)
        return error.code if isinstance(error, PhaseFailure) else 1


if __name__ == "__main__":
    sys.exit(main())
