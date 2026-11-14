#!/usr/bin/env python3
"""One source-pinned Pangu native contract run; publish encrypted text evidence.

The 46 new tests use synthetic fixtures. Three selected legacy tests additionally
load the existing authenticated packs. No original Pangu asset is introduced, no
old visual workflow guard is changed, and no app or raw xcresult is uploaded.
"""
import argparse
import collections
import datetime
import hashlib
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
REVIEWED_SOURCE = "ea383be06819fc93c36f99b874fdd18a0a358f4b"
# Git Data API publication can produce a different commit object. These fixed
# entries prove the reviewed source content without needing the local commit to
# exist remotely. CI configuration and evidence metadata are outside this set.
REVIEWED_ENTRIES = {
    "App": "0b7abd46a9ae5d628a94b1e7603784a421bbf77d",
    "Sources": "03a563ad464524bc2947fcfc700c6208db6ab196",
    "Shared": "e41e160b4262a9defbb3c5e92b4d020c5e0c2b80",
    "Tests": "f924617fb78f17dd1b60b6f4f1b0c7ac7fb38d54",
    "scripts": "9b71896f67a12ab967171c09404565e6471a7d15",
    "Package.swift": "ffc64914ed88ae83bb4569fea0777b08ea2d29b6",
    "project.yml": "16f1e55826ae257c96182c692b7f9ad8c450aa38",
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
)
LEGACY_METHODS = (
    ("DuelLifecycleTests+CompatibilityIdentity.swift", "DuelLifecycleTests",
     "testNetworkIdentityVerifiesCompleteInstalledPrivateContentWithoutStartingClock"),
    ("DuelLifecycleTests+VerifiedPreparation.swift", "DuelLifecycleTests",
     "testVerifiedPreparationRetainsAllOriginalObjectsAndReleasesPayloadOnce"),
    ("DuelWeaponAssetTests.swift", "DuelWeaponAssetTests",
     "testEquippedRecoveryBlendsToIdleWithoutChangingSourceSample"),
)
EXPECTED_COUNT = 49
KEY_NAMES = ("FIGHTER_LIU_MODEL_KEY", "FIGHTER_PRESENTATION_KEY")


class PhaseFailure(Exception):
    def __init__(self, detail, code=1):
        super().__init__(detail)
        self.code = code if isinstance(code, int) and 1 <= code <= 255 else 1


def work():
    parent = Path(os.environ["RUNNER_TEMP"])
    if not parent.is_absolute() or parent.is_symlink():
        raise ValueError("Expected an absolute runner temporary directory")
    path = parent / "fighter-pangu-native"
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

    for klass, count in SYNTHETIC_SOURCES:
        relative, methods = declared(klass + ".swift", klass)
        if len(methods) != count:
            raise ValueError("Synthetic method count changed")
        rows.extend({"identifier": "SiteTests/" + klass + "/" + method,
                     "sourceFile": relative, "scenarioType": "synthetic fixture contract"}
                    for method in methods)
    for filename, klass, method in LEGACY_METHODS:
        relative, methods = declared(filename, klass)
        if methods.count(method) != 1:
            raise ValueError("Missing exact legacy method")
        rows.append({"identifier": "SiteTests/" + klass + "/" + method,
                     "sourceFile": relative, "scenarioType": "existing authenticated resource regression"})
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
        raise ValueError("New evidence public recipient differs from its reviewed pin")
    rows, hashes = selected_inventory()
    for relative in (*MANIFESTS, "project.yml", WORKFLOW, ".github/scripts/fighter_pangu_native.py",
                     ".github/scripts/fighter_private_model.py", ".github/scripts/fighter_sf3_assets.py",
                     ".github/scripts/fighter_sf3_distinct.py", ".github/scripts/fighter_presentation_assets.py",
                     ".github/scripts/fighter_source_trails.py", ".github/scripts/build_identity.py"):
        hashes[relative] = digest(regular(ROOT / relative, 2 * 1024**2))
    work().mkdir(mode=0o700, exist_ok=False)
    write_json(work() / "identity.json", {
        "sourceSha": actual, "reviewedLocalSourceSha": REVIEWED_SOURCE, "reviewedEntries": REVIEWED_ENTRIES,
        "sourceMapping": "Exact reviewed tree/blob entries; the remote commit object may differ",
        "ref": BRANCH, "runId": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "workflowSource": WORKFLOW, "preparedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "expectedNativeMethods": EXPECTED_COUNT, "syntheticNativeMethods": 46, "existingResourceMethods": 3,
        "selectors": rows, "selectedSourceSHA256": hashes, "resourceManifestReferences": MANIFESTS,
        "recipientSPKISHA256": RECIPIENT_SPKI_SHA256, "wrappedKeyEncoding": "raw-32",
        "keyWrapping": "RSA-OAEP-SHA256; same fresh evidence key to existing and current recipients",
        "limitations": ["46 synthetic contracts and three legacy resource regressions",
                        "No production Pangu model, motion, effects or audio supplied or activated",
                        "Simulator evidence; physical-device and audible/visual original parity remain unverified",
                        "No SwiftPM rerun, second host build, UI runner, signing, app upload or TestFlight action"],
    })
    print("Pinned reviewed source content and 49 exact native methods; no native execution yet.")


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


def stage():
    verify_identity()
    commands = (("fighter_sf3_assets.py", [], "stage-scenery", 180),
                ("fighter_sf3_distinct.py", [], "stage-distinct", 180),
                ("fighter_presentation_assets.py", ["stage"], "stage-presentation", 60),
                ("fighter_source_trails.py", ["stage"], "stage-trails", 60))
    for filename, arguments, label, timeout in commands:
        run_logged([sys.executable, ".github/scripts/" + filename, *arguments], label, timeout)
    audit_resources(ROOT / "App/Resources/FighterPrivate", bundled=False)
    print("Authenticated the existing 73 resource files for three backward-compatibility checks.")


def test_targets(data):
    if "TestConfigurations" in data:
        return [t for c in data["TestConfigurations"] for t in c.get("TestTargets", [])]
    return [dict(v, BlueprintName=k) for k, v in data.items()
            if isinstance(v, dict) and k != "__xctestrun_metadata__"]


def build():
    no_resource_keys()
    verify_identity()
    project = ROOT / "project.yml"
    source, original = project.read_text(), digest(project)
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    if source.count(needle) != 1:
        raise ValueError("Ambiguous host test scheme")
    project.write_text(source.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true'))
    write_json(work() / "compiled-project.json", {
        "originalProjectSHA256": original, "compiledProjectSHA256": digest(project),
        "onlyProjectConfigurationChange": "SiteTests inherits the existing -demo host launch path",
        "configuration": "Debug", "signingAllowed": False, "productionPanguReleasePin": "",
    })
    run_logged([sys.executable, ".github/scripts/build_identity.py"], "build-identity", 60)
    run_logged(["xcodegen", "generate"], "project-generation", 120)
    run_logged(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj", "-scheme", "ShiftReminder",
                "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(work() / "derived"), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGN_IDENTITY=", "FIGHTER_ASSET_RELEASE_SHA256="], "native-build", 1200)
    products = work() / "derived/Build/Products"
    runs = list(products.glob("*.xctestrun"))
    if len(runs) != 1:
        raise ValueError("Ambiguous xctestrun output")
    targets = test_targets(plistlib.loads(regular(runs[0], 2 * 1024**2).read_bytes()))
    if (len(targets) != 1 or targets[0].get("BlueprintName") != "SiteTests" or
            "-demo" not in targets[0].get("CommandLineArguments", []) or
            targets[0].get("IsUITestBundle", False) or targets[0].get("SkipTestIdentifiers")):
        raise ValueError("The compiled test plan must contain only the demo SiteTests host")
    (work() / "xctestrun-path.txt").write_text(str(runs[0]))
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    audit_resources(app, bundled=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("FighterAssetReleaseSHA256") != "" or list(app.rglob("SF3_FighterRelease.json")):
        raise ValueError("Synthetic validation must not activate a production Pangu asset release")
    if any(p.suffix in (".enc", ".pem", ".key") for p in app.rglob("*") if p.is_file()):
        raise ValueError("Encrypted packs or key files must not enter the application")
    (work() / "build-ok.txt").write_text("One unsigned demo build; 73 compiled resource identities verified\n")
    print("Built the unsigned SiteTests host once and verified all 73 compiled resource identities.")


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
    name = "Fighter Pangu " + os.environ["GITHUB_RUN_ID"] + " attempt " + os.environ["GITHUB_RUN_ATTEMPT"]
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
    (work() / "native-ok.txt").write_text("49 passed; 0 failed; 0 skipped; every exact method once\n")
    print("Native XCTest: 49 passed, 0 failed, 0 skipped; exact methods, one iteration.")


def public_summary():
    identity = read_json(work() / "identity.json")
    result = {"sourceSha": identity["sourceSha"], "reviewedLocalSourceSha": REVIEWED_SOURCE,
              "runId": identity["runId"], "attempt": identity["attempt"], "expectedNativeMethods": EXPECTED_COUNT,
              "syntheticMethods": 46, "existingResourceMethods": 3,
              "buildAndCompiledResourcesVerified": (work() / "build-ok.txt").is_file(),
              "nativeExactSetPassed": (work() / "native-ok.txt").is_file(),
              "physicalDeviceAcceptance": "NOT VERIFIED", "productionPanguAssetsActivated": False,
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
        # Only bounded text at the working root is included. No attachments,
        # runtime resources, application products or xcresult are traversed.
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
            output.writestr("text-evidence-inventory.json", json.dumps(entries, indent=2))
        if not entries or archive.stat().st_size > 25 * 1024**2:
            raise ValueError("Invalid bounded evidence archive")
        key = secrets.token_bytes(32)
        wrap_key(key, EXISTING_RECIPIENT.encode(), published / "fighter-pangu-native-evidence.key.enc")
        wrap_key(key, public_data, published / "fighter-pangu-native-evidence.session-key.enc")
        os.environ["FIGHTER_LIU_MODEL_KEY"] = key.hex()
        try:
            envelope.seal_evidence_file(archive, published / "fighter-pangu-native-evidence.enc")
        finally:
            os.environ.pop("FIGHTER_LIU_MODEL_KEY", None)
        files = sorted(published.glob("*.enc"))
        if len(files) != 3:
            raise ValueError("Incomplete encrypted evidence set")
        (published / "fighter-pangu-native-evidence.SHA256SUMS").write_text(
            "".join(digest(path) + "  " + path.name + "\n" for path in files))
        timing("evidence-sealing", started, 0)
        print("Sealed bounded build/test diagnostics for the existing and current private recipients.")
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
            output.write("### Pangu native contract validation\n\n```json\n" + json.dumps(summary, indent=2) + "\n```\n")
    # The report is also a final gate. A sealed diagnostic artifact is never
    # presented as a successful native acceptance when an earlier step failed.
    if not all(summary.get(key) is True for key in
               ("buildAndCompiledResourcesVerified", "nativeExactSetPassed", "cleanupComplete")):
        raise PhaseFailure("Native acceptance did not reach all required gates")


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("inventory", "prepare", "tools", "stage", "build", "simulator",
                                             "test", "seal", "cleanup", "report"))
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
        print("Pangu native phase failed: " + operation + "; diagnostics remain in the encrypted evidence.", file=sys.stderr)
        raise SystemExit(error.code if isinstance(error, PhaseFailure) else 1) from None
