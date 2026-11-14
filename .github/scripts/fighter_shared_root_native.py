#!/usr/bin/env python3
"""Fixed unsigned Apple increments with independent native and UI evidence.

Never selects the previously successful 117 methods. Existing protected
helpers are reused only for pinned envelope and receipt operations; their old
event, source, release and test gates remain unchanged. No signing, upload,
Secret mutation, TestFlight operation, media conversion or asset acquisition.
The material followup selects the four failed resource methods plus two new
uniform regressions, and never reexecutes the five contracts already passed.
The UI remediation rebuilds the changed App and selects only the failed UI
method. Native results remain historical and are never counted in that scope.
"""
from __future__ import annotations

import argparse
import ast
import base64
import collections
import datetime
import hashlib
import importlib
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
import struct
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "wuyong9494-lab/kriswu"
BRANCH = "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
INITIAL_SCOPE = "initial-nine"
MATERIAL_SCOPE = "material-followup-six"
UI_SCOPE = "ui-remediation-only"
SCOPE = os.environ.get("FIGHTER_SHARED_ROOT_SCOPE", INITIAL_SCOPE)
if SCOPE not in (INITIAL_SCOPE, MATERIAL_SCOPE, UI_SCOPE):
    raise ValueError("Unreviewed shared-root execution scope")
IS_MATERIAL_FOLLOWUP = SCOPE == MATERIAL_SCOPE
IS_UI_REMEDIATION = SCOPE == UI_SCOPE
WORKFLOW = (".github/workflows/fighter-shared-root-ui-remediation.yml" if IS_UI_REMEDIATION else
            ".github/workflows/fighter-shared-root-material-followup.yml" if IS_MATERIAL_FOLLOWUP
            else ".github/workflows/fighter-shared-root-native.yml")
COMMIT_MESSAGE = ("Verify shared root UI remediation 20261115" if IS_UI_REMEDIATION else
                  "Verify shared root material followup 20261115" if IS_MATERIAL_FOLLOWUP
                  else "Verify shared root native increment 20261115")
SOURCE_BASELINE = ("5afd8195e2f611ab2e7c37f5096a4251a4616ee9" if IS_UI_REMEDIATION else
                   "68f1e7de45351c3e4b2607c56ff8ab111d0c7130" if IS_MATERIAL_FOLLOWUP
                   else "6ebca235dfb579454c99528791f5c8e84bc9ff6f")
REVIEWED_ENTRIES = {
    "App": "093a5558930ad0702f6e977f300498707a97630c",
    "Package.swift": "ffc64914ed88ae83bb4569fea0777b08ea2d29b6",
    "Shared": "e41e160b4262a9defbb3c5e92b4d020c5e0c2b80",
    "Sources": "e151525e2b8db6592379a120bfe1007c3e0edc41",
    "Widget": "dc5c0075ea1fb8ed0a44c68f2fea21dfc92112d3",
    "project.yml": "4659145612fbca682db5fb915784d9c6e9dc8cab",
    "scripts": "de93f174f9996a30c1a38cfff072d693bba050bf",
}
BASE_TEST_INVENTORY_SHA = "3bb84dbb20328290337ab9e10f96848dfe8475d3e1d4460f235413978edb259d"
MATERIAL_SOURCE = "App/Services/DuelTriadSourceMaterial.swift"
BASE_OTHER_APP_INVENTORY_SHA = "823f65ee5de955a7dd8ba2de3abd7290ed1e6c3b8fc58bd6bb3f7b193c6c162a"
# These are the independently reviewed fix and the two new Apple test methods.
MATERIAL_SOURCE_SHA = "efb78001996c8e66721cafbcdb99765b3af9d4ca17e827385ca6d3968ef75856"
UNIFORM_TEST = "Tests/SiteTests/DuelTriadRuntimeUniformTests.swift"
UNIFORM_TEST_SHA = "e982e1ab17702552571a2fc8b00445039cf9e217ad615bf122074e67ece7b3ac"
MODEL_TEST = "Tests/SiteTests/DuelSharedRootInstalledModelTests.swift"
MODEL_TEST_SHA = "58a5d25eb978e443b79ad4844d57a6cc2fad5e264fd6f1a0ac51e2f4b4fbbe93"
UI_TEST = "Tests/ArenaFlowTests/DuelSharedRootVisualCaptureTests.swift"
UI_TEST_SHA = ("d144949cad4b14eeef47ad7bf7d0134a5671016732d9690f77599aa54b911cee" if IS_UI_REMEDIATION
               else "50cbcd0d6f43f843bc5c1fd2a3b05f18632217a0a32a2384626c0c21477080f0")
UI_APP_PINS = {
    "App/Views/DuelWorld.swift": "e01058a8f5f57ce516621534f0e642397537a3532b7b3ffc88e80cf93bcf948e",
    "App/Services/DuelTriadSurfaceFrameDriver.swift": "1986d589d7ca309e426491f818f4f9e0f9d81a2a99f6a2c4c2e1b6274f347849",
    "App/Views/DuelView.swift": "7576166011575d14e94a7d8fc880039afc3cd03cd1b8eab02928ec66beed3925",
}
UI_OTHER_APP_INVENTORY_SHA = "d246306f6801c0ac9ccc11c0e42f3258ecade2d21f351f7f0b340e78b9ca9efc"
UI_OTHER_TEST_INVENTORY_SHA = "6025ca6ccb2c1dea8214bd32002ca6ddb5dd17dfdfd65a3c976856ef019ebd40"
UI_OTHER_SCRIPT_INVENTORY_SHA = "d5e7f85e8e6a416ff4b9d92b506191b27c8f1ded5bfb39416d34840d9daf5131"
UI_OTHER_WORKFLOW_INVENTORY_SHA = "5bcbb3b977eb5803f3b27dec8eca538dd16b8d00be09a0dfd38648f71a22a6b8"
UI_SCRIPTS_TREE = "64730d41241222d66e0837afdd50ae3b813be83d"
UI_SCOPE_TEST = ".github/scripts/test_fighter_shared_root_ui_remediation.py"
UI_SCOPE_TEST_SHA = "6ab2868fd65dc7da7e0651fd14898e7ed3db61c9f025fd23c77cde50e514f3b4"
# Only this exact, single workflow field is replaced by 64 zeroes when hashing.
# The real field and environment must equal this helper's complete byte digest.
UI_WORKFLOW_CANONICAL_SHA = "caaee04b088eae85ba53c2f9cc7071a02ecc95ce1c4da662248d688f8e55ca93"
UI_HELPER_PIN_FIELD = '      EXPECTED_SHARED_ROOT_UI_HELPER_SHA256: "'
UI_SELECTORS = ("ArenaFlowTests/DuelSharedRootVisualCaptureTests/"
                "testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls",)
INITIAL_TEST_METHODS = {
    "DuelTriadFloorfallIntegrationTests": (
        "testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals",
        "testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset",
        "testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback",
    ),
    "DuelTriadRootVictimAudioTests": (
        "testVerifiedRootEndUsesLiuOwnershipAtTick38AndDeduplicatesTheSameFrame",
        "testRootEndRejectsWrongClockFrameContextVariantCountAndSunImpersonation",
        "testEveryVictimClipMustMatchSourceSHAFramesTicksGridAndPelvisBeforeSharing",
        "testOrdinarySharedThrowsKeepSoundFrameClockWithoutTheRootEndException",
        "testMorphTargetMetadataAcceptsOnlyReviewedHammersAndCompleteNewVictimCapability",
    ),
    "DuelSharedRootInstalledModelTests": (
        "testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions",
    ),
}
UNIFORM_METHODS = (
    "testInstalledSourceMaterialsResolveOnlyReviewedUnassignedCustomPosition",
    "testUnreviewedMissingUniformsRemainRejectedAndExplicitValuesKeepPriority",
)
MATERIAL_TEST_METHODS = {
    "DuelTriadFloorfallIntegrationTests": INITIAL_TEST_METHODS["DuelTriadFloorfallIntegrationTests"],
    "DuelSharedRootInstalledModelTests": INITIAL_TEST_METHODS["DuelSharedRootInstalledModelTests"],
    "DuelTriadRuntimeUniformTests": UNIFORM_METHODS,
}
TEST_METHODS = ({} if IS_UI_REMEDIATION else MATERIAL_TEST_METHODS
                if IS_MATERIAL_FOLLOWUP else INITIAL_TEST_METHODS)
PREVIOUS_PASSED_SELECTORS = tuple("SiteTests/DuelTriadRootVictimAudioTests/" + method
    for method in INITIAL_TEST_METHODS["DuelTriadRootVictimAudioTests"])
MODEL_SELECTOR = "SiteTests/DuelSharedRootInstalledModelTests/" + \
    INITIAL_TEST_METHODS["DuelSharedRootInstalledModelTests"][0]
SELECTORS = tuple("SiteTests/" + klass + "/" + method
                  for klass, methods in TEST_METHODS.items() for method in methods)
EXPECTED_COUNT = 0 if IS_UI_REMEDIATION else 6 if IS_MATERIAL_FOLLOWUP else 9
METHOD_SCOPE = {"installedAudio": 0 if IS_UI_REMEDIATION else 3,
                "syntheticContracts": 0 if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION else 5,
                "installedModels": 0 if IS_UI_REMEDIATION else 1,
                "runtimeUniformRegressions": 2 if IS_MATERIAL_FOLLOWUP else 0}
EXPECTED_ATTACHMENTS = {
    "native": {"shared-root-installed-model-report": (MODEL_SELECTOR, "data")},
    "ui": {
        **{label: (UI_SELECTORS[0], "image") for label in (
            "shared-root-ui-sun-lobby", "shared-root-ui-sun-practice",
            "shared-root-ui-sun-root-observed", "shared-root-ui-sun-root-control-released",
            "shared-root-ui-liu-lobby", "shared-root-ui-liu-practice")},
        "shared-root-ui-observations": (UI_SELECTORS[0], "data"),
    },
}
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY", "FIGHTER_H17_D19_KEY")
BASE_MANIFESTS = {
    ".github/private/sf3/manifest.json": "f454b50969212171dfe07c34abc497854a6fc59fd55f62aceec64e74eef5c7d0",
    ".github/private/sf3-distinct/manifest.json": "a1eb14298057e11ebe3099d5a6b19df9ce404c2243446f9caffed2f7b0163e4e",
    ".github/private/fighter-presentation/manifest.json": "0595cdd5b06068a1c2ea8e1a304195ac1b7d404d5051935e19cc4188c0d3cad5",
    ".github/private/fighter-source-trails/manifest.json": "390dd75ac5aa218bdd2cd3c5909ca75a0c2148c5676687dd6fd732fb797471cb",
}
BASE_PACK = ".github/private/fighter-h17-d19/manifest.json"
BASE_PACK_SHA = "697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff"
BASE_RELEASE_SHA = "7bf9aa17a1e15273dbe7ae04eecd1ef092c2ad9a72360b99cd4f7ac08695704b"
DELTA_PACK = ".github/private/fighter-h17-shared-root/manifest.json"
DELTA_PACK_SHA = "d50b7fc6f711a55849b259b0f78d348612782f5e3765f9629db50291e20fe2b9"
DELTA_DOCUMENT_SHA = "dd08d99764fcbba6f791e1db941b9eb607e715f40ade2faf8b8bdf0051365765"
RELEASE_SHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
RECIPIENT = ".github/public/fighter-pangu-native-20261114.public.pem"
RECIPIENT_SPKI_SHA = "ba82f15dbd713e0fbd980f6ae455382f8cc20c1118ae692ef0fe67710eca4e15"
DEPENDENCY_PINS = {
    ".github/scripts/fighter_h17_d19_native.py": "896cb07ddea3fa2c816a64063d52c69af18910568b01ebd9675012e3a0b595d1",
    ".github/scripts/fighter_private_model.py": "925c25094359c4df9cc901a54e11e4374ea471e7cb8680b77380360767b15d79",
    ".github/scripts/fighter_sf3_assets.py": "fb8cd750f4ff134fd27f1040e47691a3932c062660d7ba7b4e9508e4d6151d11",
    ".github/scripts/fighter_sf3_distinct.py": "9f27051a445c96e038881cf67793a7968f46efd94b2866dfbe9ce4971f1e619c",
    ".github/scripts/fighter_presentation_assets.py": "7265d99a7aac0a27b8ee09dd259f00c6feec71a9c0f0d645c5a72b439e5d54a3",
    ".github/scripts/fighter_source_trails.py": "ef80f69675f657c281ab0e8c9f3079466c0ecfcbe7042d7d9bdfe0b4d33d31a0",
    ".github/scripts/build_identity.py": "f2ed2c4cf9d66f463275f1dc7bdf83888b614b06831eec9090667d412ed1249b",
    ".github/scripts/fighter_recover_screenshots.py": "35b31b9de3b75708889db9e967a266f4e796954633c9b76ec68e94d39faf0241",
    "scripts/stage_h17_shared_root_release.py": "31bf0de7697678630b6722914d44b93c65773d0a38c11bedc4721a805a384bbd",
    "scripts/stage_h17_floorfall_release.py": "0bf36ee23b2d2e85623c560d5de764a37e6ac2f38c7ddcec2c79be4ba1b7e409",
    "scripts/source_floorfall_audio.py": "066091ae3f8188409283e5584e0edc054e3f6503d3251315747417f6d3287fd1",
    "Tests/SiteTests/DuelTriadFloorfallIntegrationTests.swift": "dc6cf6e6a78eca5ec3bbd81eb565353fe095b0c81a8c6b8e31b445e342ce427d",
    "Tests/SiteTests/DuelTriadRootVictimAudioTests.swift": "708e2c9854bc29149550aac5cc8403011b0b005b6a981ab80efce864e9f688a4",
}


class PhaseFailure(Exception):
    def __init__(self, detail, code=1):
        super().__init__(detail)
        self.code = code if isinstance(code, int) and 0 < code < 256 else 1


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def regular(path, maximum):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, "Expected bounded regular file")
    return path


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def read_json(path, maximum=16 * 1024**2):
    return json.loads(regular(path, maximum).read_text())


def work():
    parent = Path(os.environ["RUNNER_TEMP"])
    require(parent.is_absolute() and not parent.is_symlink(), "Unsafe runner directory")
    path = parent / "fighter-shared-root-native"
    require(not path.is_symlink(), "Unsafe run directory")
    return path


def no_resource_keys():
    require(not any(name in os.environ for name in KEY_NAMES), "Resource keys are restricted to staging")


def pinned(path, expected, maximum=2 * 1024**2):
    result = regular(ROOT / path, maximum)
    require(digest(result) == expected, "Reviewed dependency or manifest pin differs: " + path)
    return result


def dependencies():
    for name, expected in DEPENDENCY_PINS.items():
        pinned(name, expected)
    return importlib.import_module("fighter_h17_d19_native")


def selected_inventory():
    result = []
    for klass, methods in TEST_METHODS.items():
        path = "Tests/SiteTests/" + klass + ".swift"
        source = regular(ROOT / path, 512 * 1024).read_text()
        require(re.search(r"\bclass\s+" + klass + r"\b", source), "Selected XCTest class missing")
        found = re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M)
        require(collections.Counter(found) == collections.Counter(methods), "Selected method declarations changed")
        require("XCTSkip" not in source, "Selected tests cannot use XCTest skip")
        result.extend({"identifier": "SiteTests/" + klass + "/" + method,
                       "sourceFile": path, "sourceSHA256": digest(ROOT / path)} for method in methods)
    require(len(result) == len(set(SELECTORS)) == EXPECTED_COUNT, "Exact native inventory differs")
    require(not IS_MATERIAL_FOLLOWUP or not set(SELECTORS) & set(PREVIOUS_PASSED_SELECTORS),
            "Previously passed contracts cannot enter the failure followup")
    return result


def preserved_prior_evidence():
    if not (IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION):
        return []
    result = [{
        "runID": "43644209347", "sourceSHA": "68f1e7de45351c3e4b2607c56ff8ab111d0c7130",
        "runURL": "https://github.com/wuyong9494-lab/kriswu/actions/runs/43644209347",
        "artifactID": "14133862654",
        "artifactSHA256": "c0b586e5cea26be6e243d0156f1d4b1f57effbc52bfdbff3721b2c412af0c0a8",
        "nativeSummarySHA256": "d9e0145c6a6fe9491a691d9b651591038d246f55d5db900cbc196da4426f6e6f",
        "nativeTestNodesSHA256": "3881bbb758b1d0071f25de827e1a55553f712ad4ffdac4d6899efa3047c6d1d9",
        "passedSelectors": PREVIOUS_PASSED_SELECTORS, "passedMethods": 5,
        "selectedAgain": False, "countsBelongToCurrentRun": False,
        "scope": "Historical synthetic binding/capability contracts; not original-media loading or playback",
    }]
    if IS_UI_REMEDIATION:
        result.append({
            "runID": "43647414701", "sourceSHA": "5788ebb1001a6e0f31c5208cb2b955b48b00741c",
            "runURL": "https://github.com/wuyong9494-lab/kriswu/actions/runs/43647414701",
            "artifactID": "14134893882",
            "artifactSHA256": "1f157104bba6e631461a994ef5291e2babf3326d91ed0f407eb1697ea99a1b6e",
            "nativeSummarySHA256": "62006d5fdbdd2379c23b1e61812c8e09a1321f904603db298b88789484ee0ea0",
            "nativeTestNodesSHA256": "4ee46ce530c0f2c51d9c7951f6d1dded32cce8386891c8f446d735b70fbb6438",
            "passedSelectors": tuple("SiteTests/" + klass + "/" + method
                for klass, methods in MATERIAL_TEST_METHODS.items() for method in methods),
            "passedMethods": 6, "selectedAgain": False, "countsBelongToCurrentRun": False,
            "scope": "Historical installed audio/model and runtime-uniform methods; no current native execution",
        })
    return result


def reviewed_test_pins():
    if IS_UI_REMEDIATION:
        return {UI_TEST: UI_TEST_SHA}
    result = {MODEL_TEST: MODEL_TEST_SHA, UI_TEST: UI_TEST_SHA}
    if IS_MATERIAL_FOLLOWUP:
        result[UNIFORM_TEST] = UNIFORM_TEST_SHA
    return result


def pin_scope_sources():
    for path, expected in reviewed_test_pins().items():
        require(re.fullmatch(r"[a-f0-9]{64}", expected), "New source review pin is not finalized")
        pinned(path, expected)
    if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION:
        require(re.fullmatch(r"[a-f0-9]{64}", MATERIAL_SOURCE_SHA), "Material review pin is not finalized")
        pinned(MATERIAL_SOURCE, MATERIAL_SOURCE_SHA)
    if IS_UI_REMEDIATION:
        for path, expected in UI_APP_PINS.items():
            pinned(path, expected)
        pin_ui_ci_sources()


def normalized_ui_workflow(raw):
    text = raw.decode("utf-8")
    pattern = re.compile(r"^" + re.escape(UI_HELPER_PIN_FIELD) + r'([a-f0-9]{64})"$', re.M)
    matches = list(pattern.finditer(text))
    require(len(matches) == 1 and text.count("EXPECTED_SHARED_ROOT_UI_HELPER_SHA256") == 1,
            "Workflow must contain exactly one exact helper-pin field")
    match = matches[0]
    normalized = text[:match.start(1)] + "0" * 64 + text[match.end(1):]
    return normalized.encode("utf-8"), match.group(1)


def pin_ui_ci_sources():
    require(re.fullmatch(r"[a-f0-9]{64}", UI_SCOPE_TEST_SHA)
            and re.fullmatch(r"[a-f0-9]{64}", UI_WORKFLOW_CANONICAL_SHA), "UI CI review pins are not finalized")
    pinned(UI_SCOPE_TEST, UI_SCOPE_TEST_SHA)
    normalized, helper_sha = normalized_ui_workflow(regular(ROOT / WORKFLOW, 64 * 1024).read_bytes())
    require(sha(normalized) == UI_WORKFLOW_CANONICAL_SHA
            and helper_sha == digest(Path(__file__))
            and os.environ.get("EXPECTED_SHARED_ROOT_UI_HELPER_SHA256") == helper_sha,
            "Reviewed workflow, helper bytes or exact helper-pin environment differs")


def selected_ui_inventory():
    path = regular(ROOT / UI_TEST, 512 * 1024)
    source = path.read_text()
    methods = re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.M)
    require(methods == [UI_SELECTORS[0].split("/")[-1]] and "XCTSkip" not in source,
            "Exact UI-only method or no-skip contract changed")
    return [{"identifier": UI_SELECTORS[0], "sourceFile": UI_TEST, "sourceSHA256": digest(path)}]


def retained_tree_digest(rows, excluded):
    names = [line.split(b"\t", 1)[1].decode() for line in rows.splitlines()]
    require(set(excluded) <= set(names), "A pinned source is not present in the committed tree")
    return sha(b"".join(line + b"\n" for line, name in zip(rows.splitlines(), names) if name not in excluded))


def validate_source_trees(entries, test_rows, app_rows=None, script_rows=None, workflow_rows=None):
    if IS_UI_REMEDIATION:
        expected = {name: value for name, value in REVIEWED_ENTRIES.items() if name != "App"}
        expected["scripts"] = UI_SCRIPTS_TREE
        require(entries == expected, "UI build inputs differ from the reviewed 5afd source baseline")
        require(app_rows is not None and retained_tree_digest(app_rows, UI_APP_PINS) == UI_OTHER_APP_INVENTORY_SHA,
                "App changed outside the reviewed frame-lifecycle and readiness-description files")
        require(retained_tree_digest(test_rows, {UI_TEST}) == UI_OTHER_TEST_INVENTORY_SHA,
                "Tests changed outside the one reviewed UI-readiness method")
        require(script_rows is not None and retained_tree_digest(script_rows,
                {".github/scripts/fighter_shared_root_native.py", UI_SCOPE_TEST}) == UI_OTHER_SCRIPT_INVENTORY_SHA,
                "CI scripts changed outside the reviewed helper and its new scope tests")
        require(workflow_rows is not None and retained_tree_digest(workflow_rows, {WORKFLOW}) == UI_OTHER_WORKFLOW_INVENTORY_SHA,
                "An existing workflow changed outside the new UI-only workflow")
        return
    expected = {name: value for name, value in REVIEWED_ENTRIES.items()
                if not (IS_MATERIAL_FOLLOWUP and name == "App")}
    require(entries == expected, "Application or build inputs differ from source baseline")
    require(retained_tree_digest(test_rows, reviewed_test_pins()) == BASE_TEST_INVENTORY_SHA,
            "Original Tests tree changed beyond independently pinned additions")
    if IS_MATERIAL_FOLLOWUP:
        require(app_rows is not None and retained_tree_digest(app_rows, {MATERIAL_SOURCE}) ==
                BASE_OTHER_APP_INVENTORY_SHA, "Application changed beyond the reviewed source material file")


def validate_event(environment, event, actual):
    expected = environment.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[a-f0-9]{40}", expected) and actual == expected, "Checkout differs from triggering commit")
    require(environment.get("FIGHTER_SHARED_ROOT_SCOPE", INITIAL_SCOPE) == SCOPE,
            "Execution scope changed after helper initialization")
    require(environment.get("GITHUB_REPOSITORY") == REPOSITORY
            and environment.get("GITHUB_REF") == BRANCH
            and environment.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@" + BRANCH
            and environment.get("GITHUB_RUN_ATTEMPT") == "1"
            and re.fullmatch(r"[0-9]+", environment.get("GITHUB_RUN_ID", "")),
            "Unexpected repository, branch, workflow or repeated attempt")
    if IS_UI_REMEDIATION:
        require(environment.get("GITHUB_WORKFLOW_SHA") == expected
                and event.get("repository", {}).get("full_name") == REPOSITORY,
                "UI workflow commit or event repository differs")
    if environment.get("GITHUB_EVENT_NAME") == "push":
        require(event.get("ref") == BRANCH and not event.get("deleted", False)
                and event.get("head_commit", {}).get("id") == expected
                and event.get("head_commit", {}).get("message") == COMMIT_MESSAGE, "Unreviewed push trigger")
    elif environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        require(not IS_UI_REMEDIATION, "The UI-only remediation has no dispatch or repeat entry")
        require(event.get("inputs", {}).get("source_sha") == expected, "Dispatch requires explicit workflow SHA")
    else:
        raise ValueError("No PR, schedule or reusable workflow execution")


def source_gate():
    names = [name for name in REVIEWED_ENTRIES if not ((IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION) and name == "App")]
    raw = subprocess.check_output(["git", "ls-tree", "HEAD", *names], cwd=ROOT, text=True)
    entries = {line.split("\t")[1]: line.split("\t")[0].split()[2] for line in raw.splitlines()}
    test_rows = subprocess.check_output(["git", "ls-tree", "-r", "HEAD", "Tests"], cwd=ROOT)
    app_rows = (subprocess.check_output(["git", "ls-tree", "-r", "HEAD", "App"], cwd=ROOT)
                if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION else None)
    script_rows = (subprocess.check_output(["git", "ls-tree", "-r", "HEAD", ".github/scripts"], cwd=ROOT)
                   if IS_UI_REMEDIATION else None)
    workflow_rows = (subprocess.check_output(["git", "ls-tree", "-r", "HEAD", ".github/workflows"], cwd=ROOT)
                     if IS_UI_REMEDIATION else None)
    validate_source_trees(entries, test_rows, app_rows, script_rows, workflow_rows)
    pin_scope_sources()
    if IS_UI_REMEDIATION:
        selected_ui_inventory()
        paths = ("App", "Sources", "Shared", "Widget", "Tests", "scripts", ".github/scripts", ".github/workflows")
        for options in (("--others", "--exclude-standard"), ("--others", "--ignored", "--exclude-standard")):
            require(not subprocess.check_output(["git", "ls-files", *options, "--", *paths], cwd=ROOT).strip(),
                    "Untracked or ignored files could change discovered build inputs")
    require(not subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).strip(),
            "Tracked modifications exist before preparation")


def manifests():
    legacy = dependencies()
    for name, expected in BASE_MANIFESTS.items():
        pinned(name, expected)
    base = legacy.validate_release_manifest(read_json(pinned(BASE_PACK, BASE_PACK_SHA)))
    require(len(base["files"]) == 295 and base["releaseSHA256"] == BASE_RELEASE_SHA, "Original overlay differs")
    delta = read_json(pinned(DELTA_PACK, DELTA_PACK_SHA))
    require(delta["schema"] == "fighter-h17-shared-root-sealed-delta-v1"
            and delta["basePackManifestSHA256"] == BASE_PACK_SHA and delta["baseReleaseSHA256"] == BASE_RELEASE_SHA
            and delta["targetReleaseSHA256"] == RELEASE_SHA and delta["deltaManifestSHA256"] == DELTA_DOCUMENT_SHA
            and delta["aad"] == "fighter-h17-shared-root-delta-v1" and delta["unchangedBaseFiles"] == 289
            and len(delta["payloadFiles"]) == len(delta["targetFiles"]) == 13, "Shared-root envelope differs")
    return legacy, base, delta


def final_inventory(base, delta, baseline):
    old = {row["file"]: dict(row) for row in base["files"]}
    changed = {row["name"]: {"file": row["name"], "bytes": row["bytes"], "sha256": row["sha256"]}
               for row in delta["targetFiles"]}
    require(len(old) == 295 and len(changed) == 13, "Duplicate overlay receipts")
    require(len(set(old) & set(changed)) == 6 and len(set(changed) - set(old)) == 7,
            "Expected six replacements and seven added WAVs")
    old.update(changed)
    require(len(old) == 302 and old["SF3_FighterRelease.json"]["sha256"] == RELEASE_SHA, "Final overlay differs")
    result = {row["file"]: {k: row[k] for k in ("file", "bytes", "sha256")} for row in baseline}
    require(len(result) == 73 and set(result) & set(old) ==
            {"Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"}, "Unreviewed baseline collision")
    result.update(old)
    require(len(result) == 373, "Expected complete 373-resource application inventory")
    return [result[name] for name in sorted(result)]


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
    require(valid, "A runtime resource is absent, duplicated or byte-modified")


def identity():
    value = read_json(work() / "identity.json")
    require(value["sourceSHA"] == os.environ["GITHUB_SHA"] and value["runID"] == os.environ["GITHUB_RUN_ID"]
            and value["attempt"] == os.environ["GITHUB_RUN_ATTEMPT"] and value["selectors"] == selected_inventory()
            and value["executionScope"] == SCOPE and value["sourceBaselineSHA"] == SOURCE_BASELINE
            and value["helperSHA256"] == digest(Path(__file__))
            and value["workflowSHA256"] == digest(ROOT / WORKFLOW), "Prepared run or source identity changed")
    if IS_UI_REMEDIATION:
        require(value.get("nativeExecutionStatus") == "not_selected"
                and value.get("expectedNativeMethods") == 0 and value.get("methodScope") == METHOD_SCOPE
                and value.get("uiSelectors") == list(UI_SELECTORS)
                and value.get("uiSourceInventory") == selected_ui_inventory()
                and value.get("appRemediationSourcePins") == UI_APP_PINS,
                "UI-only scope or exact source inventory changed")
    dependencies()
    pin_scope_sources()
    return value


def timing(label, started, code):
    path = work() / "timings.json"
    result = read_json(path) if path.exists() else {}
    result[label] = {"durationSeconds": round(time.monotonic() - started, 3), "exitCode": code}
    write_json(path, result)


def run_logged(command, label, timeout, check=True, output_name=None, key_names=()):
    """Keep compiler, test, media and key material out of public job logs."""
    environment = dict(os.environ)
    for key in KEY_NAMES:
        if key not in key_names:
            environment.pop(key, None)
    started, code = time.monotonic(), None
    try:
        with (work() / (output_name or label + ".log")).open("w") as output, \
                (work() / (label + "-stderr.log")).open("w") as errors:
            process = subprocess.Popen(command, cwd=ROOT, env=environment,
                                       stdout=output, stderr=errors, start_new_session=True)
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


def once(label):
    with (work() / (label + "-invoked.json")).open("x") as output:
        json.dump({"phase": label, "attempts": 1}, output)


def recipient_digest(raw):
    require(raw.startswith(b"-----BEGIN PUBLIC KEY-----\n") and b"PRIVATE KEY" not in raw, "Public recipient required")
    data = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=raw,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=20).stdout
    return sha(data)


def prepare():
    no_resource_keys()
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    validate_event(os.environ, read_json(Path(os.environ["GITHUB_EVENT_PATH"])), actual)
    source_gate()
    legacy, base, delta = manifests()
    rows = final_inventory(base, delta, legacy.resource_records())
    for relative in ("App/Resources/FighterPrivate", "App/Resources/arena-original-resources.arenapack"):
        path = ROOT / relative
        require(not path.exists() and not path.is_symlink(), "Private resources already exist before staging")
    require(recipient_digest(regular(ROOT / RECIPIENT, 16_384).read_bytes()) == RECIPIENT_SPKI_SHA,
            "Evidence recipient differs")
    work().mkdir(mode=0o700, exist_ok=False)
    write_json(work() / "identity.json", {
        "sourceSHA": actual, "sourceBaselineSHA": SOURCE_BASELINE,
        "reviewedEntries": {name: (UI_SCRIPTS_TREE if IS_UI_REMEDIATION and name == "scripts" else value)
                            for name, value in REVIEWED_ENTRIES.items()
                            if not ((IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION) and name == "App")},
        "executionScope": SCOPE,
        "sourceMapping": ("Build inputs match 5afd except three exact App frame/readiness files and one UI predicate file; only the failed UI method is selected."
                          if IS_UI_REMEDIATION else
                          "Application/build inputs and prior tests match 68f1e7 except the pinned Material file; two new pinned uniform tests."
                          if IS_MATERIAL_FOLLOWUP else
                          "Application and prior tests exactly match 6ebca; two independently pinned new test files."),
        "materialSourceSHA256": MATERIAL_SOURCE_SHA if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION else None,
        "otherAppInventorySHA256": (UI_OTHER_APP_INVENTORY_SHA if IS_UI_REMEDIATION else
                                     BASE_OTHER_APP_INVENTORY_SHA if IS_MATERIAL_FOLLOWUP else None),
        "appRemediationSourcePins": UI_APP_PINS if IS_UI_REMEDIATION else None,
        "scriptsTree": UI_SCRIPTS_TREE if IS_UI_REMEDIATION else REVIEWED_ENTRIES["scripts"],
        "uiSourceInventory": selected_ui_inventory() if IS_UI_REMEDIATION else None,
        "newUniformTestSHA256": UNIFORM_TEST_SHA if IS_MATERIAL_FOLLOWUP else None,
        "newModelTestSHA256": MODEL_TEST_SHA, "runID": os.environ["GITHUB_RUN_ID"],
        "newUITestSHA256": UI_TEST_SHA, "uiSelectors": UI_SELECTORS, "expectedUIMethods": 1,
        "attempt": os.environ["GITHUB_RUN_ATTEMPT"], "ref": BRANCH, "selectors": selected_inventory(),
        "expectedNativeMethods": EXPECTED_COUNT, "methodScope": METHOD_SCOPE,
        "installedAudioMethods": METHOD_SCOPE["installedAudio"], "syntheticContractMethods": METHOD_SCOPE["syntheticContracts"],
        "installedModelMethods": METHOD_SCOPE["installedModels"], "runtimeUniformRegressions": METHOD_SCOPE["runtimeUniformRegressions"],
        "nativeExecutionStatus": "not_selected" if IS_UI_REMEDIATION else "selected",
        "preservedPriorEvidence": preserved_prior_evidence(),
        "assetReleaseSHA256": RELEASE_SHA, "deltaManifestSHA256": DELTA_PACK_SHA,
        "helperSHA256": digest(Path(__file__)), "workflowSHA256": digest(ROOT / WORKFLOW),
        "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "recipientSPKISHA256": RECIPIENT_SPKI_SHA, "diagnosticKeyEncoding": "raw-32; RSA-OAEP-SHA256",
        "previous117Selected": False, "physicalDevice": False, "TestFlight": False,
    })
    write_json(work() / "expected-resources.json", rows)
    print("Pinned " + str(EXPECTED_COUNT) + " native methods + 1 separate UI capture for " + SCOPE +
          "; reviewed source and final v2 373-resource closure.")


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
    if not any(Path(p).is_file() for p in ("/opt/homebrew/opt/openssl@3/bin/openssl",
                                         "/usr/local/opt/openssl@3/bin/openssl")):
        run_logged(["brew", "install", "openssl@3"], "install-openssl", 240)
    print("Selected installed Xcode 26.6; no simulator runtime download.")


GCM_SWIFT = r"""import Foundation
import CryptoKit
import Darwin
do {
    guard CommandLine.arguments.count == 5,
          let encoded = ProcessInfo.processInfo.environment["FIGHTER_H17_D19_KEY"],
          let rawKey = Data(base64Encoded: encoded), rawKey.count == 32,
          rawKey.base64EncodedString() == encoded else { throw NSError(domain: "PrivateKey", code: 1) }
    for (index, aad, cap) in [(1, "fighter-h17-d19-v1", 134217728),
                              (3, "fighter-h17-shared-root-delta-v1", 8388636)] {
        let cipher = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index]))
        guard cipher.count > 28, cipher.count <= cap else { throw NSError(domain: "Envelope", code: 1) }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: cipher.prefix(12)),
                      ciphertext: cipher.dropFirst(12).dropLast(16), tag: cipher.suffix(16))
        let clear = try AES.GCM.open(box, using: SymmetricKey(data: rawKey), authenticating: Data(aad.utf8))
        try clear.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .withoutOverwriting)
    }
} catch {
    FileHandle.standardError.write(Data("Private resource authentication or output failed.\n".utf8))
    exit(1)
}
"""


def decode_delta(clear, manifest):
    require(len(clear) == manifest["clearZIPBytes"] and sha(clear) == manifest["clearZIPSHA256"],
            "Authenticated delta ZIP differs")
    expected = {row["name"]: row for row in manifest["payloadFiles"]}
    with zipfile.ZipFile(io.BytesIO(clear)) as archive:
        members = archive.infolist()
        require(len(members) == 14 and {m.filename for m in members} ==
                set(expected) | {"delta-manifest.json"}, "Delta member closure differs")
        require(sum(m.file_size for m in members) <= 8 * 1024**2, "Delta expansion exceeds bound")
        for member in members:
            require(stat.S_ISREG(member.external_attr >> 16) and not member.flag_bits & 1
                    and member.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    and 0 < member.file_size <= 4 * 1024**2, "Unsafe delta member")
        raw = archive.read("delta-manifest.json")
        require(len(raw) <= 32_768 and sha(raw) == DELTA_DOCUMENT_SHA, "Authenticated delta instructions differ")
        delta = json.loads(raw)
        require(delta["payloads"] == manifest["payloadFiles"] and delta["files"] == manifest["targetFiles"],
                "Delta envelope and authenticated inventory disagree")
        payloads = {}
        for name, row in expected.items():
            raw = archive.read(name)
            require(len(raw) == row["bytes"] and sha(raw) == row["sha256"], "Delta payload differs")
            payloads[name] = raw
    return delta, payloads


def reconstruct_delta(delta, payloads, overlay, original):
    """Rebuild only the two reviewed patch targets; preserve original BIN bytes."""
    sys.path.insert(0, str(ROOT / "scripts"))
    stage_module = importlib.import_module("stage_h17_shared_root_release")
    inventory = stage_module.inventory_from_pack(original)
    changed = {name: raw for name, raw in payloads.items()
               if name not in (stage_module.GLB_PATCH_NAME, stage_module.CATALOG_PATCH_NAME)}
    require(len(delta["transforms"]) == 2, "Expected model and catalog transforms")
    for transform in delta["transforms"]:
        name = transform["target"]
        require(transform["base"] == inventory[name], "Delta transform base differs")
        old = stage_module.checked_file(overlay, inventory[name])
        if name == stage_module.CHARACTER_NAME:
            rebuilt = stage_module.rebuild_glb(old, payloads[transform["payload"]])
        elif name == stage_module.CATALOG_NAME:
            rebuilt = stage_module.rebuild_catalog(old, payloads[transform["payload"]])
        else:
            raise ValueError("Unexpected delta transformation")
        changed[name] = rebuilt
    target = {row["name"]: row for row in delta["files"]}
    require(set(changed) == set(target), "Reconstructed target closure differs")
    for name, raw in changed.items():
        row = target[name]
        require(len(raw) == row["bytes"] and sha(raw) == row["sha256"], "Reconstructed target hash differs")
    # No output is replaced before every new byte sequence matches the pin.
    for name, raw in changed.items():
        path = overlay / name
        require(not path.is_symlink(), "Unsafe target replacement")
        path.write_bytes(raw)


def stage():
    identity()
    once("stage")
    for name in KEY_NAMES[:2]:
        require(re.fullmatch(r"[a-f0-9]{64}", os.environ.get(name, "")), "Missing or malformed resource key: " + name)
    encoded = os.environ.get(KEY_NAMES[2], "")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise ValueError("H17/D19 key missing or malformed") from None
    require(len(raw) == 32 and base64.b64encode(raw).decode() == encoded, "H17/D19 key encoding differs")
    raw = b""
    legacy, base, manifest = manifests()
    rows = final_inventory(base, manifest, legacy.resource_records())
    for filename, arguments, key_name in (
        ("fighter_sf3_assets.py", [], KEY_NAMES[0]),
        ("fighter_sf3_distinct.py", [], KEY_NAMES[0]),
        ("fighter_presentation_assets.py", ["stage"], KEY_NAMES[1]),
        ("fighter_source_trails.py", ["stage"], KEY_NAMES[1]),
    ):
        run_logged([sys.executable, ".github/scripts/" + filename, *arguments],
                   "baseline-" + filename.removesuffix(".py"), 180, key_names=(key_name,))
    destination = ROOT / "App/Resources/FighterPrivate"
    audit_resources(destination, legacy.resource_records())
    cipher, old_clear, delta_clear = [work() / n for n in ("original-overlay.enc", "original-overlay.zip", "delta-clear.zip")]
    script, overlay = work() / "authenticate-resources.swift", work() / "verified-overlay"
    delta_cipher = regular((ROOT / DELTA_PACK).parent / manifest["cipher"]["name"], 8 * 1024**2 + 28)
    require(delta_cipher.stat().st_size == manifest["cipher"]["bytes"]
            and digest(delta_cipher) == manifest["cipher"]["sha256"], "Delta ciphertext pin differs")
    try:
        legacy.assemble_cipher(base, (ROOT / BASE_PACK).parent, cipher)
        script.write_text(GCM_SWIFT)
        run_logged(["swift", str(script), str(cipher), str(old_clear), str(delta_cipher), str(delta_clear)],
                   "authenticate-source-and-delta", 240, key_names=(KEY_NAMES[2],))
        legacy.overlay_zip(regular(old_clear, 128 * 1024**2).read_bytes(), base, overlay)
        delta, payloads = decode_delta(regular(delta_clear, 8 * 1024**2).read_bytes(), manifest)
        reconstruct_delta(delta, payloads, overlay, base)
        for path in sorted(overlay.iterdir()):
            require(not (destination / path.name).is_symlink(), "Unsafe baseline replacement")
            os.replace(path, destination / path.name)
    finally:
        for path in (cipher, old_clear, delta_clear, script):
            path.unlink(missing_ok=True)
        shutil.rmtree(overlay, ignore_errors=True)
    audit_resources(destination, rows)
    write_json(work() / "stage-ok.json", {"baselineFiles": 73, "originalOverlayFiles": 295,
               "deltaPayloadFiles": 13, "unchangedOverlayFiles": 289, "finalOverlayFiles": 302,
               "compiledResourceTarget": 373, "assetReleaseSHA256": RELEASE_SHA,
               "redecodedMedia": False, "downloadedAssets": False, "keyFilesCreated": False})
    print("Authenticated 73 + 295 resources and 13-payload delta; final 373 files match v2 pins.")


def build():
    no_resource_keys()
    identity()
    once("build")
    require((work() / "stage-ok.json").is_file(), "Resource authentication must complete before build")
    project = ROOT / "project.yml"
    original = project.read_bytes()
    if IS_UI_REMEDIATION:
        # This existing scheme builds the changed App and its UI runner only.
        # SiteTests is neither a target in its test plan nor an execution scope.
        spec, scheme, change = project, "ArenaFlow", "None; use the existing ArenaFlow scheme without modifying project.yml"
        require("  ArenaFlow:\n    build:\n      targets:\n        ShiftReminder: all\n        ArenaFlowTests: [test]" in original.decode(),
                "The existing reviewed UI scheme is absent")
        generation = ["xcodegen", "generate"]
    else:
        needle = "    scheme:\n      testTargets:\n        - SiteTests"
        source = original.decode()
        require(source.count(needle) == 1, "Ambiguous host scheme")
        generated = source.replace(needle, needle + '\n        - ArenaFlowTests\n      commandLineArguments:\n        "-demo": true')
        spec = ROOT / "project.shared-root-native.yml"
        require(not spec.exists() and not spec.is_symlink(), "Temporary generated spec already exists")
        spec.write_text(generated)
        scheme = "ShiftReminder"
        change = "Add existing ArenaFlowTests target and -demo to this run's temporary scheme"
        generation = ["xcodegen", "generate", "--spec", spec.name]
    write_json(work() / "compiled-project.json", {
        "originalSHA256": sha(original), "generatedSHA256": digest(spec),
        "onlyProjectConfigurationChange": change, "scheme": scheme,
        "trackedProjectModified": False,
        "signingAllowed": False, "releaseSHA256": RELEASE_SHA,
    })
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(generation, "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj",
                "-scheme", scheme, "-configuration", "Debug", "-sdk", "iphonesimulator",
                "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(work() / "derived"),
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
                "FIGHTER_ASSET_RELEASE_SHA256=" + RELEASE_SHA], "native-build", 1200)
    products = work() / "derived/Build/Products"
    runs = list(products.glob("*.xctestrun"))
    require(len(runs) == 1, "Ambiguous build-for-testing result")
    targets = dependencies().test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    by_name = {t.get("BlueprintName"): t for t in targets}
    if IS_UI_REMEDIATION:
        require(len(targets) == 1 and set(by_name) == {"ArenaFlowTests"}
                and by_name["ArenaFlowTests"].get("IsUITestBundle") is True
                and not by_name["ArenaFlowTests"].get("SkipTestIdentifiers"), "Only the reviewed UI target may be built for testing")
        bundles = list(products.rglob("*.xctest"))
        require(bundles and {path.name for path in bundles} == {"ArenaFlowTests.xctest"},
                "UI-only build unexpectedly produced a native test bundle")
        require(project.read_bytes() == original and not (ROOT / "project.shared-root-native.yml").exists(),
                "UI-only build must retain the existing project specification")
    else:
        require(len(targets) == 2 and set(by_name) == {"SiteTests", "ArenaFlowTests"}
                and "-demo" in by_name["SiteTests"].get("CommandLineArguments", [])
                and not by_name["SiteTests"].get("IsUITestBundle", False)
                and by_name["ArenaFlowTests"].get("IsUITestBundle") is True
                and not any(t.get("SkipTestIdentifiers") for t in targets), "Unexpected compiled test hosts")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    audit_resources(app, read_json(work() / "expected-resources.json"), bundled=True)
    info = plistlib.loads(regular(app / "Info.plist", 1024**2).read_bytes())
    require(info.get("FighterAssetReleaseSHA256") == RELEASE_SHA
            and info.get("ArenaCommitSHA") == os.environ["GITHUB_SHA"]
            and info.get("CFBundleIdentifier") == "com.kriswu.shiftreminder",
            "Compiled application source or resource identity differs")
    require(not any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()),
            "Ciphertext or key material must not enter the app")
    (work() / "build-ok.txt").write_text("One unsigned build; all 373 compiled resources match.\n")
    print("One unsigned host built; all 373 compiled resource byte identities verified.")


def simulator():
    no_resource_keys()
    identity()
    once("simulator")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], text=True, timeout=60))
    runtimes = {r["identifier"]: r for r in catalog["runtimes"]
                if r.get("isAvailable") and ".iOS-" in r["identifier"]}
    choices = [(tuple(map(int, re.findall(r"\d+", runtimes[r]["version"]))), r, d["deviceTypeIdentifier"])
               for r, devices in catalog["devices"].items() if r in runtimes for d in devices
               if d.get("isAvailable") and d.get("deviceTypeIdentifier", "").endswith(".iPhone-17-Pro-Max")]
    require(choices, "Installed iPhone 17 Pro Max simulator required; no download or fallback")
    _, runtime, dtype = max(choices)
    name = "Fighter shared root " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
    udid = subprocess.check_output(["xcrun", "simctl", "create", name, dtype, runtime], text=True, timeout=60).strip()
    require(re.fullmatch(r"[0-9A-Fa-f-]{36}", udid), "Unexpected simulator identifier")
    write_json(work() / "simulator.json", {"udid": udid, "name": name, "runtime": runtime,
               "type": dtype, "osVersion": runtimes[runtime]["version"], "physicalDevice": False})
    run_logged(["xcrun", "simctl", "boot", udid], "simulator-boot", 120)
    run_logged(["xcrun", "simctl", "bootstatus", udid, "-b"], "simulator-ready", 480)
    print("Prepared one owned iPhone 17 Pro Max simulator.")


def verify_results(summary, data, expected=SELECTORS):
    require(len(expected) > 0 and tuple(expected) in (SELECTORS, UI_SELECTORS) and len(set(expected)) == len(expected),
            "Unexpected test selection")
    for key, value in (("totalTestCount", len(expected)), ("passedTests", len(expected)),
                       ("failedTests", 0), ("skippedTests", 0)):
        require(type(summary.get(key)) is int and summary[key] == value, "Native count differs: " + key)
    require(summary.get("result") == "Passed" and isinstance(data.get("testNodes"), list),
            "A completed process is not a successful exact native result")
    seen = []

    def walk(nodes):
        require(isinstance(nodes, list), "Malformed native result children")
        for node in nodes:
            require(isinstance(node, dict), "Malformed native result node")
            if node.get("nodeType") == "Test Case":
                raw = node.get("nodeIdentifier")
                require(isinstance(raw, str), "Missing native method identifier")
                normalized = raw.removesuffix("()")
                matches = [s for s in expected if normalized in (s, "/".join(s.split("/")[1:]))]
                require(len(matches) == 1 and node.get("result") == "Passed",
                        "Unexpected, failed or skipped native method")
                seen.append(matches[0])
            else:
                walk(node.get("children", []))
    walk(data["testNodes"])
    require(collections.Counter(seen) == collections.Counter(expected), "Missing, extra or repeated native method")


def execute_tests(ui=False):
    require(not IS_UI_REMEDIATION or ui, "Native execution is prohibited in the UI-only remediation")
    no_resource_keys()
    identity()
    scope, expected = ("ui", UI_SELECTORS) if ui else ("native", SELECTORS)
    once(scope)
    require((work() / "build-ok.txt").is_file(), "Verified native build required")
    device = read_json(work() / "simulator.json")
    command = ["xcodebuild", "test-without-building", "-xctestrun",
               (work() / "xctestrun-path.txt").read_text(), "-destination", "id=" + device["udid"],
               "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(work() / (scope + ".xcresult"))]
    command += ["-only-testing:" + selector for selector in expected]
    code = run_logged(command, "selected-" + scope, 720 if not ui else 360, check=False)
    result = {"exitCode": code, "selectedCount": len(expected), "iterations": 1, "exports": {}}
    write_json(work() / (scope + "-process.json"), result)
    if (work() / (scope + ".xcresult/Info.plist")).is_file():
        for kind in ("summary", "tests"):
            try:
                result["exports"][kind] = run_logged(
                    ["xcrun", "xcresulttool", "get", "test-results", kind,
                     "--path", str(work() / (scope + ".xcresult"))], scope + "-result-" + kind, 60,
                    check=False, output_name=scope + "-" + kind + ".json")
            except Exception as error:
                result["exports"][kind] = type(error).__name__
    write_json(work() / (scope + "-process.json"), result)
    if code:
        raise PhaseFailure("Native invocation failed; original process code and failure bodies retained", code)
    require(result["exports"] == {"summary": 0, "tests": 0}, "Missing native result exports")
    summary = read_json(work() / (scope + "-summary.json"))
    verify_results(summary,
                   read_json(work() / (scope + "-tests.json")), expected)
    if IS_UI_REMEDIATION:
        verify_ui_result_device(summary, device)
    (work() / (scope + "-ok.txt")).write_text(str(len(expected)) + " passed; 0 failed; 0 skipped; exact methods once.\n")
    print(scope + " XCTest: " + str(len(expected)) + " passed, 0 failed, 0 skipped; one execution per method.")


def verify_ui_result_device(summary, device):
    configurations = summary.get("devicesAndConfigurations")
    require(isinstance(configurations, list) and len(configurations) == 1,
            "UI results must belong to exactly one owned simulator")
    configuration = configurations[0]
    observed = configuration.get("device", {})
    require(observed.get("deviceId") == device["udid"] and observed.get("deviceName") == device["name"]
            and observed.get("modelName") == "iPhone 17 Pro Max" and observed.get("platform") == "iOS Simulator"
            and configuration.get("passedTests") == 1 and configuration.get("failedTests") == 0
            and configuration.get("skippedTests") == 0, "UI result simulator ownership or exact counts differ")


def test():
    execute_tests()


def ui():
    if IS_UI_REMEDIATION:
        started = datetime.datetime.now(datetime.timezone.utc)
        failure = None
        try:
            execute_tests(ui=True)
        except Exception as error:
            failure = error
        try:
            finished = datetime.datetime.now(datetime.timezone.utc)
            collect_ui_runtime_diagnostics(started, finished)
        except Exception as error:
            write_json(work() / "ui-runtime-log-failure.json",
                       {"errorType": type(error).__name__, "detail": str(error)[:2000]})
            if failure is None:
                failure = error
        if failure is not None:
            raise failure
        return
    try:
        execute_tests(ui=True)
    finally:
        path = work() / "simulator.json"
        if path.is_file():
            try:
                udid = read_json(path)["udid"]
                run_logged(["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "5m", "--style", "json",
                            "--predicate", 'process == "ShiftReminder"'], "ui-runtime-log", 60, check=False)
            except Exception as error:
                write_json(work() / "ui-runtime-log-failure.json", {"errorType": type(error).__name__})


DRAWABLE_DIAGNOSTICS = {
    "doublePresent": "Each CAMetalLayerDrawable can only be presented once!",
    "textureAfterPresent": "[CAMetalLayerDrawable texture] should not be called after already presenting this drawable.",
}
UI_RUNTIME_OK = "Complete owned UI invocation log; zero known drawable diagnostics. Pixel review pending.\n"


def verify_ui_runtime_log(path, *, collection_code, device, started, finished):
    require(collection_code == 0, "Runtime log collection did not succeed")
    require(started.tzinfo is not None and finished.tzinfo is not None and started <= finished,
            "UI runtime coverage interval is invalid")
    expected_name = "Fighter shared root " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
    require(device.get("name") == expected_name and device.get("physicalDevice") is False
            and re.fullmatch(r"[0-9A-Fa-f-]{36}", device.get("udid", "")), "Runtime log simulator identity differs")
    raw = regular(path, 128 * 1024**2).read_bytes()
    events = json.loads(raw)
    require(isinstance(events, list) and events and all(isinstance(row, dict) for row in events),
            "Runtime log is empty or has an invalid complete JSON structure")
    counts = {name: 0 for name in DRAWABLE_DIAGNOSTICS}
    owned, stamps = 0, []
    # log --start/--end uses second-granularity bounds. Parse only messages from
    # this installed App and refuse entries outside the requested full interval.
    low = started.replace(microsecond=0)
    high = finished.replace(microsecond=0) + datetime.timedelta(seconds=1)
    for row in events:
        if not str(row.get("processImagePath", "")).endswith("/ShiftReminder.app/ShiftReminder"):
            continue
        message = row.get("eventMessage") or row.get("formatString")
        require(isinstance(message, str) and message, "Owned runtime entry has no message")
        stamp = datetime.datetime.fromisoformat(str(row.get("timestamp", "")).replace(" ", "T", 1))
        require(stamp.tzinfo is not None and low <= stamp <= high, "Runtime entry falls outside this UI invocation")
        owned += 1
        stamps.append(stamp)
        normalized = " ".join(message.split()).casefold()
        for name, diagnostic in DRAWABLE_DIAGNOSTICS.items():
            if diagnostic.casefold() in normalized:
                counts[name] += 1
    require(owned > 0, "No entries from the installed App were captured for this UI invocation")
    return {
        "collectionExitCode": collection_code, "completeJSONParsed": True,
        "ownedSimulatorVerified": True, "simulatorUDID": device["udid"],
        "requestedStartUTC": low.isoformat(), "requestedEndUTC": high.isoformat(),
        "coverage": "Full UI invocation through result export; source log scanned before sealing",
        "sourceBytes": len(raw), "sourceSHA256": sha(raw), "entries": len(events), "appEntries": owned,
        "firstAppEntryUTC": min(stamps).isoformat(), "lastAppEntryUTC": max(stamps).isoformat(),
        "knownDiagnosticCounts": counts, "knownDiagnosticCount": sum(counts.values()),
        "knownDiagnosticsAbsent": not any(counts.values()),
        "sealedTextTailOnly": len(raw) > 2 * 1024**2,
        "pixelReview": "PENDING", "performanceVerified": False,
    }


def collect_ui_runtime_diagnostics(started, finished):
    device = read_json(work() / "simulator.json")
    catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"],
                                                text=True, timeout=30))
    owned = [row for rows in catalog["devices"].values() for row in rows if row.get("udid") == device["udid"]]
    require(len(owned) == 1 and owned[0].get("name") == device["name"], "Runtime log device is not the owned simulator")
    low = started.replace(microsecond=0)
    high = finished.replace(microsecond=0) + datetime.timedelta(seconds=1)
    code = run_logged(["xcrun", "simctl", "spawn", device["udid"], "log", "show",
                       "--start", low.strftime("%Y-%m-%d %H:%M:%S%z"),
                       "--end", high.strftime("%Y-%m-%d %H:%M:%S%z"), "--style", "json",
                       "--predicate", 'process == "ShiftReminder"'], "ui-runtime-log", 60, check=False)
    result = verify_ui_runtime_log(work() / "ui-runtime-log.log", collection_code=code,
                                  device=device, started=started, finished=finished)
    write_json(work() / "ui-runtime-diagnostics.json", result)
    require(result["knownDiagnosticsAbsent"], "Known drawable double-present or texture-after-present diagnostic occurred")
    (work() / "ui-runtime-ok.txt").write_text(UI_RUNTIME_OK)


def attachment_inventory(directory, device, scope):
    if IS_UI_REMEDIATION:
        require(scope == "ui", "Native attachments are not selected in UI remediation")
        return ui_remediation_attachment_inventory(directory, device)
    expected = EXPECTED_ATTACHMENTS[scope]
    selectors = SELECTORS if scope == "native" else UI_SELECTORS
    paths = sorted(directory.rglob("*"))
    require(not any(p.is_symlink() for p in paths), "Symlink in exported native evidence")
    files = [p for p in paths if p.is_file()]
    require(1 <= len(files) <= 200, "Attachment count exceeds bound")
    for path in files:
        regular(path, 24 * 1024**2)
    manifest = read_json(directory / "manifest.json")
    require(isinstance(manifest, list), "Unexpected xcresult attachment manifest")
    labels, entries, seen_files = set(), [], set()
    for group in manifest:
        require(isinstance(group, dict) and isinstance(group.get("attachments"), list), "Malformed attachment group")
        identifier = group.get("testIdentifier", "").removesuffix("()")
        owners = [s for s in selectors if identifier in (s, "/".join(s.split("/")[1:]))]
        for item in group["attachments"]:
            name = item.get("exportedFileName", "")
            require(isinstance(name, str) and name and Path(name).name == name
                    and "\\" not in name and ".." not in name and name not in seen_files,
                    "Unsafe or repeated exported attachment name")
            path = directory / name
            require(path in files, "Missing referenced native attachment")
            seen_files.add(name)
            human, suffix = item.get("suggestedHumanReadableName", ""), path.suffix.lower()
            candidates = [label for label in expected if re.fullmatch(
                re.escape(label) + r"(?:_[0-9]+_[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})?"
                + re.escape(suffix), human)]
            if not candidates:
                continue  # Automatic failure screenshots stay private diagnostics, never coverage.
            require(len(candidates) == 1 and candidates[0] not in labels, "Repeated exact attachment label")
            label = candidates[0]
            selector, kind = expected[label]
            require(owners == [selector] and item.get("deviceId") == device["udid"]
                    and item.get("deviceName") == device["name"], "Attachment method or simulator identity differs")
            if kind == "image":
                require(suffix == ".png", "Expected a real PNG attachment")
                png_metadata(path)
            else:
                require(suffix in (".json", ".txt"), "Expected JSON metadata attachment")
                value = read_json(path)
                require(isinstance(value, dict), "Expected attachment object")
                if scope == "native":
                    require(value.get("releaseSHA256") == RELEASE_SHA
                            and len(value.get("characters", [])) == 2
                            and len(value.get("liuVictimMotions", [])) == 3,
                            "Installed model receipt did not record the final two characters and three motions")
                else:
                    require(value.get("expectedReleaseSHA256") == RELEASE_SHA and value.get("flowCompleted") is True
                            and value.get("internalCombatStateInjected") is False
                            and value.get("exactRootAnimationTicksObserved") is False,
                            "UI observations did not complete the reviewed real-control scenario")
            labels.add(label)
            entries.append({"label": label, "selector": selector, "file": name, "kind": kind,
                            "bytes": path.stat().st_size, "sha256": digest(path)})
    require(labels == set(expected), "Missing required method-owned captures or metadata")
    return {"scope": scope, "completeExpectedLabels": True, "exactMethodAndSimulatorOwnership": True,
            "files": entries, "unknownAutomaticAttachments": len(seen_files) - len(entries)}


def ui_attachment_files(directory):
    require(directory.is_dir() and not directory.is_symlink(), "Unsafe UI attachment directory")
    paths = sorted(directory.rglob("*"))
    require(not any(path.is_symlink() for path in paths), "Symlink in exported UI evidence")
    files, total = [], 0
    for path in paths:
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            continue
        require(stat.S_ISREG(info.st_mode) and info.st_size <= 128 * 1024**2,
                "Automatic UI attachment is not regular or exceeds its 128 MiB bound")
        total += info.st_size
        files.append(path)
    require(1 <= len(files) <= 512 and total <= 384 * 1024**2, "UI attachment count or total byte bound exceeded")
    return files


def attachment_label(item, path, expected):
    human, suffix = item.get("suggestedHumanReadableName", ""), path.suffix.lower()
    require(isinstance(human, str), "Malformed attachment label")
    return [label for label in expected if re.fullmatch(
        re.escape(label) + r"(?:_[0-9]+_[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})?"
        + re.escape(suffix), human)]


def ui_remediation_attachment_inventory(directory, device):
    expected = EXPECTED_ATTACHMENTS["ui"]
    files = ui_attachment_files(directory)
    manifest = read_json(directory / "manifest.json", 24 * 1024**2)
    require(isinstance(manifest, list), "Unexpected UI attachment manifest")
    labels, seen, entries, mandatory_paths = set(), set(), [], set()
    for group in manifest:
        require(isinstance(group, dict) and isinstance(group.get("attachments"), list), "Malformed UI attachment group")
        identifier = group.get("testIdentifier", "")
        require(isinstance(identifier, str), "Malformed UI attachment owner")
        identifier = identifier.removesuffix("()")
        owners = [selector for selector in UI_SELECTORS if identifier in (selector, "/".join(selector.split("/")[1:]))]
        for item in group["attachments"]:
            require(isinstance(item, dict), "Malformed UI attachment entry")
            name = item.get("exportedFileName", "")
            require(isinstance(name, str) and name and Path(name).name == name and "\\" not in name
                    and ".." not in name and name not in seen, "Unsafe or repeated UI attachment file")
            path = directory / name
            require(path in files, "Referenced UI attachment does not exist")
            seen.add(name)
            candidates = attachment_label(item, path, expected)
            if not candidates:
                continue
            require(len(candidates) == 1 and candidates[0] not in labels, "Repeated exact UI attachment label")
            label = candidates[0]
            selector, kind = expected[label]
            require(owners == [selector] and item.get("deviceId") == device["udid"]
                    and item.get("deviceName") == device["name"], "UI attachment method or simulator identity differs")
            regular(path, 24 * 1024**2)  # Mandatory artifacts retain their original nonempty 24 MiB limit.
            if kind == "image":
                require(path.suffix.lower() == ".png", "Expected a real mandatory PNG")
                png_metadata(path)
            else:
                require(path.suffix.lower() in (".json", ".txt"), "Expected mandatory UI observations JSON")
                value = read_json(path, 24 * 1024**2)
                require(isinstance(value, dict) and value.get("expectedReleaseSHA256") == RELEASE_SHA
                        and value.get("flowCompleted") is True and value.get("internalCombatStateInjected") is False
                        and value.get("exactRootAnimationTicksObserved") is False,
                        "UI observations did not complete the reviewed real-control scenario")
            labels.add(label)
            mandatory_paths.add(path)
            entries.append({"label": label, "selector": selector, "file": name, "kind": kind,
                            "bytes": path.stat().st_size, "sha256": digest(path)})
    automatic = [path for path in files if path not in mandatory_paths and path.name != "manifest.json"]
    require(sum(path.stat().st_size for path in automatic) <= 256 * 1024**2,
            "Automatic UI attachment aggregate exceeds 256 MiB")
    require(labels == set(expected), "Missing required UI method-owned captures or observations")
    require(sum(row["bytes"] for row in entries) <= 160 * 1024**2,
            "Mandatory UI evidence exceeds the unchanged sealed-media budget")
    diagnostics = [{"file": path.relative_to(directory).as_posix(), "bytes": path.stat().st_size,
                    "sha256": digest(path), "countsAsCoverage": False,
                    "videoOmittedFromSealedEvidence": path.suffix.lower() in (".mp4", ".mov", ".m4v", ".hevc")}
                   for path in automatic]
    return {"scope": "ui", "completeExpectedLabels": True, "exactMethodAndSimulatorOwnership": True,
            "files": entries, "unknownAutomaticAttachments": len(automatic),
            "automaticDiagnostics": diagnostics,
            "omittedVideoCount": sum(row["videoOmittedFromSealedEvidence"] for row in diagnostics),
            "automaticAttachmentsNeverCountAsCoverage": True}


def export():
    no_resource_keys()
    identity()
    once("export")
    failures = []
    device = read_json(work() / "simulator.json") if (work() / "simulator.json").is_file() else None
    for scope in (("ui",) if IS_UI_REMEDIATION else ("native", "ui")):
        bundle, destination = work() / (scope + ".xcresult"), work() / (scope + "-attachments")
        try:
            require(device and (bundle / "Info.plist").is_file(), "No finalized result bundle for attachment export")
            destination.mkdir(mode=0o700, exist_ok=False)
            run_logged(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                        "--output-path", str(destination)], scope + "-export-attachments", 120)
            result = attachment_inventory(destination, device, scope)
            write_json(work() / (scope + "-attachments-ok.json"), result)
        except Exception as error:
            failures.append(scope)
            write_json(work() / (scope + "-attachments-failure.json"),
                       {"scope": scope, "errorType": type(error).__name__, "detail": str(error)[:4000]})
    require(not failures, "One or more method-owned attachment sets are incomplete; partial evidence retained")
    print("Exported six exact UI screenshots plus observations with method and device ownership; native receipts are not selected."
          if IS_UI_REMEDIATION else "Exported exact native model metadata and six UI screenshots plus observations with method and device ownership.")


def png_metadata(path):
    raw = regular(path, 24 * 1024**2).read_bytes()
    require(raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR" and len(raw) >= 24,
            "Simulator screenshot is not a PNG")
    width, height = struct.unpack(">II", raw[16:24])
    require(100 <= width <= 5000 and 100 <= height <= 5000, "Unexpected screenshot dimensions")
    return {"bytes": len(raw), "sha256": sha(raw), "width": width, "height": height}


def capture():
    no_resource_keys()
    identity()
    once("capture")
    require((work() / "build-ok.txt").is_file(), "Verified compiled resources required")
    device = read_json(work() / "simulator.json")
    udid = device["udid"]
    app = work() / "derived/Build/Products/Debug-iphonesimulator/ShiftReminder.app"
    capture_dir = work() / "captures"
    capture_dir.mkdir(mode=0o700, exist_ok=False)
    run_logged(["xcrun", "simctl", "install", udid, str(app)], "lobby-install", 90)
    run_logged(["xcrun", "simctl", "launch", "--terminate-running-process", udid,
                "com.kriswu.shiftreminder", "-demo", "-screen", "fighter"], "lobby-launch", 60)
    receipts = []
    try:
        for index in (1, 2):
            time.sleep(8 if index == 1 else 4)
            path = capture_dir / ("liu-shared-root-lobby-" + str(index) + ".png")
            run_logged(["xcrun", "simctl", "io", udid, "screenshot", str(path)],
                       "lobby-screenshot-" + str(index), 30)
            receipts.append(dict(file=path.name, **png_metadata(path)))
    finally:
        run_logged(["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "3m", "--style", "json",
                    "--predicate", 'process == "ShiftReminder"'], "lobby-runtime-log", 60, check=False)
    write_json(work() / "capture-ok.json", {
        "screen": "fighter", "defaultHero": "liu_hammers", "screenshots": receipts,
        "launchArguments": ["-demo", "-screen", "fighter"], "physicalDevice": False,
        "visualReview": "PENDING; valid PNG and successful launch do not prove visible character rendering",
        "modelLoadingProof": "Only the separate installed model XCTest result, if it passed",
        "rootSkillGameplayCaptured": False, "audiblePlaybackVerified": False,
    })
    print("Captured two Liu lobby images and private logs; image review remains required.")


def current_native_artifacts():
    # These two filenames label the common application build, not XCTest
    # execution. Every other native result/invocation path is forbidden here.
    build_logs = {"native-build.log", "native-build-stderr.log"}
    return sorted(path.name for path in work().iterdir() if path.name not in build_logs
                  and (path.name.startswith(("native-", "native.", "selected-native"))))


def ui_runtime_summary():
    path, marker = work() / "ui-runtime-diagnostics.json", work() / "ui-runtime-ok.txt"
    if not path.is_file():
        return {"verified": False, "status": "UNAVAILABLE", "pixelReview": "PENDING"}
    try:
        value = read_json(path)
        device = read_json(work() / "simulator.json")
        keys = ("collectionExitCode", "completeJSONParsed", "ownedSimulatorVerified", "simulatorUDID",
                "requestedStartUTC", "requestedEndUTC", "coverage", "sourceBytes", "sourceSHA256", "entries",
                "appEntries", "firstAppEntryUTC", "lastAppEntryUTC", "knownDiagnosticCounts",
                "knownDiagnosticCount", "knownDiagnosticsAbsent", "sealedTextTailOnly", "pixelReview",
                "performanceVerified")
        counts = value.get("knownDiagnosticCounts")
        source = work() / "ui-runtime-log.log"
        verified = (marker.is_file() and marker.read_text() == UI_RUNTIME_OK
                    and value.get("collectionExitCode") == 0 and value.get("completeJSONParsed") is True
                    and value.get("ownedSimulatorVerified") is True and value.get("simulatorUDID") == device["udid"]
                    and type(value.get("appEntries")) is int and 0 < value["appEntries"] <= value.get("entries", 0)
                    and counts == {name: 0 for name in DRAWABLE_DIAGNOSTICS}
                    and value.get("knownDiagnosticCount") == 0 and value.get("knownDiagnosticsAbsent") is True
                    and source.is_file() and value.get("sourceBytes") == source.stat().st_size
                    and value.get("sourceSHA256") == digest(source)
                    and value.get("pixelReview") == "PENDING" and value.get("performanceVerified") is False)
        return dict({key: value.get(key) for key in keys}, verified=bool(verified))
    except (OSError, ValueError, KeyError, TypeError):
        return {"verified": False, "status": "INVALID", "pixelReview": "PENDING"}


def public_summary():
    ident = read_json(work() / "identity.json")
    result = {
        "sourceSHA": ident["sourceSHA"], "sourceBaselineSHA": SOURCE_BASELINE,
        "runID": ident["runID"], "attempt": ident["attempt"], "expectedNativeMethods": EXPECTED_COUNT,
        "executionScope": SCOPE, "methodScope": METHOD_SCOPE,
        "preservedPriorEvidence": preserved_prior_evidence(),
        "previousFiveContractsSelectedAgain": False if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION else None,
        "materialSourceSHA256": MATERIAL_SOURCE_SHA if IS_MATERIAL_FOLLOWUP or IS_UI_REMEDIATION else None,
        "newUniformTestSHA256": UNIFORM_TEST_SHA if IS_MATERIAL_FOLLOWUP else None,
        "assetReleaseSHA256": RELEASE_SHA, "deltaManifestSHA256": DELTA_PACK_SHA,
        "resourcesAuthenticated": (work() / "stage-ok.json").is_file(),
        "compiled373ResourcesVerified": (work() / "build-ok.txt").is_file(),
        "nativeExactSetPassed": False if IS_UI_REMEDIATION else (work() / "native-ok.txt").is_file(),
        "uiExactMethodPassed": (work() / "ui-ok.txt").is_file(),
        "nativeModelReceiptVerified": False if IS_UI_REMEDIATION else (work() / "native-attachments-ok.json").is_file(),
        "uiExactCaptureSetVerified": (work() / "ui-attachments-ok.json").is_file(),
        "expectedUIMethods": 1,
        "simulatorLobbyCaptured": (work() / "capture-ok.json").is_file(),
        "simulatorVisualReview": "PENDING", "physicalIPhoneAcceptance": "NOT VERIFIED",
        "audiblePlayback": "NOT VERIFIED",
        "rootGameplayScreenshot": (work() / "ui-attachments-ok.json").is_file(),
        "productionPanguAssetsActivated": False, "previous117Rerun": False, "TestFlightUploaded": False,
    }
    if IS_UI_REMEDIATION:
        unexpected = current_native_artifacts()
        runtime = ui_runtime_summary()
        result.update(nativeExecutionStatus="not_selected", nativeModelReceiptStatus="not_selected",
                      nativeArtifactsAbsent=not unexpected, unexpectedNativeArtifacts=unexpected,
                      previousSixNativeMethodsSelectedAgain=False, appRemediationSourcePins=UI_APP_PINS,
                      newUITestSHA256=UI_TEST_SHA, uiRuntimeDiagnostics=runtime,
                      uiRuntimeDiagnosticGatePassed=runtime["verified"],
                      uiSealedCaptureSetComplete=False,
                      automaticAttachmentsNeverCountAsCoverage=True)
        if (work() / "attachment-seal-policy.json").is_file():
            policy = read_json(work() / "attachment-seal-policy.json")
            result["attachmentSealPolicy"] = {key: policy.get(key) for key in
                ("selectedFileCount", "selectedBytes", "omittedFileCount", "omittedVideoCount",
                 "mandatoryValidationPassed", "completeValidatedMandatorySetSealed", "automaticAttachmentsNeverCountAsCoverage")}
            result["uiSealedCaptureSetComplete"] = policy.get("completeValidatedMandatorySetSealed") is True
    for scope in (("ui",) if IS_UI_REMEDIATION else ("native", "ui")):
        if (work() / (scope + "-process.json")).is_file():
            native = read_json(work() / (scope + "-process.json"))
            result[scope + "Process"] = {k: native.get(k) for k in ("exitCode", "selectedCount", "iterations")}
        if (work() / (scope + "-summary.json")).is_file():
            try:
                native = read_json(work() / (scope + "-summary.json"))
                result[scope + "ObservedCounts"] = {k: native.get(k) for k in
                    ("totalTestCount", "passedTests", "failedTests", "skippedTests", "result")}
            except (ValueError, OSError):
                result[scope + "ObservedCounts"] = "UNAVAILABLE"
    if (work() / "timings.json").is_file():
        result["timings"] = read_json(work() / "timings.json")
    if (work() / "ui-recovery.json").is_file():
        result["uiRecovery"] = read_json(work() / "ui-recovery.json")
    return result


def wrap_key(key, public_data, destination):
    public = destination.with_suffix(".public.pem")
    try:
        public.write_bytes(public_data)
        result = subprocess.run(["openssl", "pkeyutl", "-encrypt", "-pubin", "-inkey", str(public),
                                 "-pkeyopt", "rsa_padding_mode:oaep", "-pkeyopt", "rsa_oaep_md:sha256"],
                                input=key, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=30)
        destination.write_bytes(result.stdout)
    finally:
        public.unlink(missing_ok=True)


def existing_recipient():
    # Read the reviewed public constant without executing old recovery commands.
    path = pinned(".github/scripts/fighter_recover_screenshots.py",
                  DEPENDENCY_PINS[".github/scripts/fighter_recover_screenshots.py"])
    tree = ast.parse(path.read_text())
    values = [ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == "PUBLIC_KEY" for t in n.targets)]
    require(len(values) == 1 and isinstance(values[0], str), "Existing public recipient missing")
    return values[0].encode()


def reusable_ui_products():
    """Preserve a successful native build only when the separate UI gate failed.

    No restore or test rerun occurs here. A future authorized recovery must use
    the same source SHA/release pin and select only the failed UI method.
    """
    receipt = {"needed": False, "available": False, "nativeNineReexecutionAllowed": False,
               "passedNativeScopeReexecutionAllowed": False, "executionScope": SCOPE,
               "previousFiveContractsReexecutionAllowed": False}
    if IS_UI_REMEDIATION:
        receipt.update(nativeExecutionStatus="not_selected", previousSixNativeMethodsReexecutionAllowed=False,
                       reason="Changed App requires this scope's new UI-only build; no historical native products reused")
        write_json(work() / "ui-recovery.json", receipt)
        return None
    target = work() / "private-ui-recovery.zip"
    if not ((work() / "native-ok.txt").is_file() and
            not ((work() / "ui-ok.txt").is_file() and (work() / "ui-attachments-ok.json").is_file())):
        write_json(work() / "ui-recovery.json", receipt)
        return None
    receipt.update(needed=True, sourceSHA=os.environ["GITHUB_SHA"], assetReleaseSHA256=RELEASE_SHA,
                   authorizedSelector=UI_SELECTORS[0], maxPlainBytes=768 * 1024**2,
                   maxCompressedBytes=256 * 1024**2)
    try:
        products = work() / "derived/Build/Products"
        require(products.is_dir() and not products.is_symlink(), "Successful build products absent")
        paths = sorted(products.rglob("*"))
        require(not any(p.is_symlink() for p in paths), "Reusable products contain a symlink")
        files = [p for p in paths if p.is_file()]
        total = sum(p.stat().st_size for p in files)
        receipt.update(files=len(files), plainBytes=total)
        require(0 < len(files) <= 8000 and 0 < total <= receipt["maxPlainBytes"], "Reusable product byte/count limit")
        with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
            inventory = []
            for path in files:
                info = path.lstat()
                require(stat.S_ISREG(info.st_mode), "Reusable product is not a regular file")
                name = "Products/" + path.relative_to(products).as_posix()
                archive.write(path, name)
                inventory.append({"file": name, "bytes": info.st_size, "sha256": digest(path)})
            archive.writestr("reuse-identity.json", json.dumps({
                "sourceSHA": os.environ["GITHUB_SHA"], "assetReleaseSHA256": RELEASE_SHA,
                "nativeExactSetPassed": True, "uiSelectorOnly": UI_SELECTORS[0],
                "xctestrun": Path((work() / "xctestrun-path.txt").read_text()).name,
                "nativeResult": read_json(work() / "native-summary.json"),
                "requiresSourceAndResourcePinMatch": True, "testExecutionAttemptedByRecovery": False,
                "relocation": "Use the archived Products directory as __TESTROOT__; validate every file before use.",
                "files": inventory,
            }, indent=2))
        receipt["compressedBytes"] = target.stat().st_size
        require(receipt["compressedBytes"] <= receipt["maxCompressedBytes"], "Compressed UI recovery exceeds limit")
        receipt["packagedAwaitingEncryption"] = True
        write_json(work() / "ui-recovery.json", receipt)
        return target
    except Exception as error:
        target.unlink(missing_ok=True)
        receipt["unavailableReason"] = str(error)[:200] if isinstance(error, ValueError) else type(error).__name__
        write_json(work() / "ui-recovery.json", receipt)
        return None


def bounded_attachments():
    if IS_UI_REMEDIATION:
        return bounded_ui_remediation_attachments()
    files, total = [], 0
    for scope in ("native", "ui"):
        directory = work() / (scope + "-attachments")
        if not directory.exists():
            continue
        require(directory.is_dir() and not directory.is_symlink(), "Unsafe attachment directory")
        for path in sorted(directory.rglob("*")):
            require(not path.is_symlink(), "Symlink in partial evidence")
            if path.is_dir() or path.suffix.lower() not in (".png", ".json", ".txt"):
                continue
            if path.is_file() and path.stat().st_size == 0:
                continue
            regular(path, 24 * 1024**2)
            total += path.stat().st_size
            require(total <= 160 * 1024**2 and len(files) < 256, "Partial evidence byte/count limit")
            files.append((path, scope + "-attachments/" + path.relative_to(directory).as_posix()))
    return files


def bounded_ui_remediation_attachments():
    directory = work() / "ui-attachments"
    paths = ui_attachment_files(directory) if directory.exists() else []
    priority = set()
    manifest = directory / "manifest.json"
    if manifest.is_file() and 0 < manifest.stat().st_size <= 24 * 1024**2:
        priority.add(manifest)  # Required to independently recheck method/device ownership after unsealing.
        try:
            groups = read_json(manifest, 24 * 1024**2)
            for group in groups if isinstance(groups, list) else []:
                for item in group.get("attachments", []) if isinstance(group, dict) else []:
                    if not isinstance(item, dict):
                        continue
                    name = item.get("exportedFileName", "")
                    path = directory / name if isinstance(name, str) else None
                    if path in paths and attachment_label(item, path, EXPECTED_ATTACHMENTS["ui"]):
                        priority.add(path)
        except (OSError, ValueError, TypeError):
            pass  # Export's strict validation remains failed; only partial diagnostics are preserved.
    receipt_path = work() / "ui-attachments-ok.json"
    validated_required = set()
    if receipt_path.is_file():
        receipt = read_json(receipt_path)
        validated_required = {directory / row["file"] for row in receipt["files"]} | {manifest}
        priority.update(validated_required)
    files, omitted, total = [], [], 0
    for path in sorted(paths, key=lambda p: (p not in priority, p.as_posix())):
        size, suffix = path.stat().st_size, path.suffix.lower()
        reason = ("unsupported-media-type" if suffix not in (".png", ".json", ".txt") else
                  "empty-system-record" if not size else
                  "exceeds-unchanged-24-MiB-sealed-file-limit" if size > 24 * 1024**2 else
                  "bounded-total-or-count-limit" if total + size > 160 * 1024**2 or len(files) >= 256 else None)
        if reason:
            omitted.append({"file": path.relative_to(directory).as_posix(), "bytes": size,
                            "sha256": digest(path), "reason": reason,
                            "mandatoryLabelCandidate": path in priority, "countsAsCoverage": False,
                            "video": suffix in (".mp4", ".mov", ".m4v", ".hevc")})
            continue
        total += size
        files.append((path, "ui-attachments/" + path.relative_to(directory).as_posix()))
    write_json(work() / "attachment-seal-policy.json", {
        "selectedFileCount": len(files), "selectedBytes": total, "omittedFileCount": len(omitted),
        "omittedVideoCount": sum(row["video"] for row in omitted), "omitted": omitted,
        "mandatoryValidationPassed": receipt_path.is_file(),
        "completeValidatedMandatorySetSealed": bool(validated_required) and validated_required <= {path for path, _ in files},
        "automaticAttachmentsNeverCountAsCoverage": True,
        "coverage": "Only the separate exact mandatory-label gate can certify capture completeness",
    })
    return files


def seal():
    no_resource_keys()
    identity()
    once("seal")
    envelope = importlib.import_module("fighter_private_model")
    public = regular(ROOT / RECIPIENT, 16_384).read_bytes()
    require(recipient_digest(public) == RECIPIENT_SPKI_SHA, "Evidence recipient changed")
    published = work() / "published"
    published.mkdir(mode=0o700, exist_ok=False)
    archive = work() / "private-evidence.zip"
    recovery = None
    try:
        recovery = reusable_ui_products()
        selected_attachments = bounded_attachments() if IS_UI_REMEDIATION else None
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
                    data = source.read(2 * 1024**2)
                total += len(data)
                require(total <= 32 * 1024**2 and len(entries) < 128, "Private text evidence exceeds bound")
                name = "metadata/" + path.name
                output.writestr(name, data)
                entries.append({"file": name, "sourceBytes": size, "archivedBytes": len(data),
                                "tailOnly": size != len(data), "sha256": sha(data)})
            capture_dir = work() / "captures"
            if capture_dir.exists():
                for path in sorted(capture_dir.iterdir()):
                    require(path.name in ("liu-shared-root-lobby-1.png", "liu-shared-root-lobby-2.png"),
                            "Unexpected capture output")
                    regular(path, 24 * 1024**2)
                    name = "captures/" + path.name
                    output.write(path, name)
                    entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path)})
            for path, name in (selected_attachments if selected_attachments is not None else bounded_attachments()):
                output.write(path, name)
                entries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest(path)})
            output.writestr("private-evidence-inventory.json", json.dumps(entries, indent=2))
        require(entries and archive.stat().st_size <= 242 * 1024**2, "Private evidence exceeds archive bound")
        key = secrets.token_bytes(32)
        stem = "fighter-shared-root-native-evidence"
        wrap_key(key, existing_recipient(), published / (stem + ".key.enc"))
        wrap_key(key, public, published / (stem + ".session-key.enc"))
        # This is a fresh diagnostic key, never a resource decryption key.
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / (stem + ".enc"))
            if recovery is not None:
                envelope.seal_evidence_file(recovery, published / "fighter-shared-root-native-ui-recovery.enc")
                receipt = read_json(work() / "ui-recovery.json")
                receipt["available"] = True
                receipt["encryptedBytes"] = (published / "fighter-shared-root-native-ui-recovery.enc").stat().st_size
                write_json(work() / "ui-recovery.json", receipt)
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
            key = b""
        files = sorted(published.glob("*.enc"))
        require(len(files) == (4 if recovery is not None else 3), "Incomplete encrypted diagnostic set")
        (published / (stem + ".SHA256SUMS")).write_text(
            "".join(digest(p) + "  " + p.name + "\n" for p in files))
        (work() / "sealed-ok.txt").write_text("Only authenticated ciphertext and wrapped fresh keys may be uploaded.\n")
    except BaseException:
        shutil.rmtree(published, ignore_errors=True)
        if (work() / "ui-recovery.json").is_file():
            receipt = read_json(work() / "ui-recovery.json")
            receipt["available"] = False
            write_json(work() / "ui-recovery.json", receipt)
        raise
    finally:
        archive.unlink(missing_ok=True)
        if recovery is not None:
            recovery.unlink(missing_ok=True)
    print("Sealed bounded failures, exact method results, resource receipts and captures for private recipients.")


def cleanup():
    no_resource_keys()
    # Always delete owned plaintext, even when a late source integrity check fails.
    summary, errors = {}, []
    try:
        identity()
        summary = public_summary()
    except Exception as error:
        errors.append("identity: " + type(error).__name__)
        summary = {"sourceSHA": os.environ.get("GITHUB_SHA"), "nativeExactSetPassed": False}
    summary["diagnosticsSealed"] = (work() / "sealed-ok.txt").is_file()
    try:
        path = work() / "simulator.json"
        if path.exists():
            device = read_json(path)
            catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"],
                                                        text=True, timeout=30))
            matches = [d for devices in catalog["devices"].values() for d in devices if d["udid"] == device["udid"]]
            expected_name = "Fighter shared root " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
            require(len(matches) == 1 and matches[0]["name"] == device["name"] == expected_name,
                    "Simulator cleanup ownership differs")
            if matches[0]["state"] != "Shutdown":
                run_logged(["xcrun", "simctl", "shutdown", device["udid"]], "simulator-shutdown", 90)
            run_logged(["xcrun", "simctl", "delete", device["udid"]], "simulator-delete", 60)
    except Exception as error:
        errors.append("simulator: " + type(error).__name__)
    for path in [ROOT / "App/Resources/FighterPrivate", ROOT / "project.shared-root-native.yml"] + [
            p for p in work().iterdir() if p.name != "published"]:
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
    print("Removed owned simulator, staged media, native products, xcresult and plaintext diagnostics.")


def report():
    no_resource_keys()
    summary = read_json(work() / "public-summary.json")
    print(json.dumps(summary, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
            output.write("### Shared-root " + SCOPE + (": native not selected; 1 UI capture\n\n"
                         if IS_UI_REMEDIATION else ": " + str(EXPECTED_COUNT) + " native methods + 1 UI capture\n\n"))
            output.write("Each scope requires its exact methods once and zero skipped. Pixel review remains separate.\n\n")
            if IS_UI_REMEDIATION:
                output.write("The six and five historical native passes retain their original runs; none are selected or counted here. Full-invocation runtime diagnostics are required; pixel review stays pending.\n\n")
            elif IS_MATERIAL_FOLLOWUP:
                output.write("Five contract passes remain attributed only to run 43644209347; this run selects none of them.\n\n")
            fence = chr(96) * 3
            output.write(fence + "json\n" + json.dumps(summary, indent=2) + "\n" + fence + "\n")
    required = ("resourcesAuthenticated", "compiled373ResourcesVerified", "uiExactMethodPassed",
                "uiExactCaptureSetVerified", "diagnosticsSealed", "cleanupComplete")
    if IS_UI_REMEDIATION:
        required += ("nativeArtifactsAbsent", "uiRuntimeDiagnosticGatePassed", "uiSealedCaptureSetComplete")
        require(summary.get("executionScope") == UI_SCOPE and summary.get("expectedNativeMethods") == 0
                and summary.get("nativeExecutionStatus") == "not_selected" and summary.get("methodScope") == METHOD_SCOPE
                and summary.get("nativeExactSetPassed") is False and summary.get("nativeModelReceiptVerified") is False
                and "nativeObservedCounts" not in summary and "nativeProcess" not in summary,
                "UI-only scope cannot count or accept a native result, including an empty result set")
    else:
        required += ("nativeExactSetPassed", "nativeModelReceiptVerified")
    require(all(summary.get(k) is True for k in required), "Increment did not reach every required execution and evidence gate")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("inventory", "prepare", "tools", "stage", "build",
                                             "simulator", "test", "ui", "capture", "export", "seal", "cleanup", "report"))
    operation = parser.parse_args().operation
    try:
        if operation == "inventory":
            legacy, base, delta = manifests()
            print(json.dumps({"sourceBaselineSHA": SOURCE_BASELINE, "selectors": selected_inventory(),
                  "executionScope": SCOPE, "methodScope": METHOD_SCOPE,
                  "preservedPriorEvidence": preserved_prior_evidence(),
                  "uiSelectors": UI_SELECTORS, "expectedUIMethods": 1,
                  "expectedNativeMethods": EXPECTED_COUNT, "finalResourceFiles": len(
                      final_inventory(base, delta, legacy.resource_records())),
                  "assetReleaseSHA256": RELEASE_SHA, "keyNamesRequired": KEY_NAMES}, indent=2))
        else:
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
        print("Shared-root native phase failed: " + operation + "; private diagnostics retained when prepared.",
              file=sys.stderr)
        return error.code if isinstance(error, PhaseFailure) else 1


if __name__ == "__main__":
    raise SystemExit(main())
