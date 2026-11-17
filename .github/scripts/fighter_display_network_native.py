#!/usr/bin/env python3
"""One unsigned build and exact source-only fighter integration regression."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "fighter-display-network-20261116"
SOURCES = (
    ("DuelLifecycleTests+Television.swift", "DuelLifecycleTests", 8),
    ("DuelNetworkCombatCoordinatorTests.swift", "DuelLifecycleTests", 31),
    ("DuelTriadMetalRendererTests.swift", "DuelTriadMetalRendererTests", 6),
    ("DuelFighterAssetReleaseLoaderTests.swift", "DuelFighterAssetReleaseLoaderTests", 12),
    ("DuelFighterCharacterContainerTests.swift", "DuelFighterCharacterContainerTests", 10),
    ("DuelLifecycleTests+SelectionPresentation.swift", "DuelLifecycleTests", 9),
    ("DuelLocalWeaponProfileTests.swift", "DuelLocalWeaponProfileTests", 12),
    ("DuelLocalRosterTests.swift", "DuelLocalRosterTests", 15),
)
CORE_CLASSES = (
    "DuelDisplayRenderBudgetTests", "DuelPhysicalInputTests",
    "DuelMultiplayerSelectionTests", "DuelCharacterIdentityTests", "DuelGameTests", "DuelWeaponMotionTests",
    "DuelSerpentStateTests", "DuelSerpentStatusPulseTests", "DuelSerpentWitheringTests",
    "DuelReplayStateTests", "DuelReplayStateAuditTests",
)
# Authenticated Action/Rain/FightIntegration suites run separately with private
# source profiles. Selecting them here would only produce skipped tests.
CORE_METHODS = (
    ("DuelTriadStateTests", "testSourceForceNoCriticalCannotBeOverriddenByPreparedBreakthroughOrGrantCriticalRewards"),
    ("DuelTriadStateTests", "testSourceForceNoCriticalReevaluatesTheRealHeraldSoulAtContact"),
)


def run(args, name, timeout):
    with (WORK / (name + ".log")).open("w") as output:
        result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print((WORK / (name + ".log")).read_text(errors="replace")[-16000:])
        raise RuntimeError(f"{name} exited {result.returncode}")
    print(name + " completed with exit code 0", flush=True)


def selectors():
    result = []
    for filename, klass, expected in SOURCES:
        text = (ROOT / "Tests/SiteTests" / filename).read_text()
        methods = re.findall(r"^    func (test\w+)\(", text, re.M)
        if len(methods) != expected or len(set(methods)) != expected:
            raise RuntimeError(f"Expected {expected} native methods in {filename}, found {len(methods)}")
        result.extend(f"SiteTests/{klass}/{method}" for method in methods)
    if not result or len(set(result)) != len(result):
        raise RuntimeError("Native test selectors must be nonempty and unique")
    return result


def core_selectors():
    result = []
    for klass in CORE_CLASSES:
        source = ROOT / "Tests/ShiftCoreTests" / (klass + ".swift")
        methods = re.findall(r"^    func (test\w+)\(", source.read_text(), re.M)
        if not methods or len(set(methods)) != len(methods):
            raise RuntimeError(f"Core test methods must be nonempty and unique: {klass}")
        result.extend(f"ShiftCoreTests.{klass}/{method}" for method in methods)
    for klass, method in CORE_METHODS:
        source = ROOT / "Tests/ShiftCoreTests" / (klass + ".swift")
        if len(re.findall(r"^    func " + re.escape(method) + r"\(", source.read_text(), re.M)) != 1:
            raise RuntimeError(f"Missing exact core method: {klass}/{method}")
        result.append(f"ShiftCoreTests.{klass}/{method}")
    if not result or len(set(result)) != len(result):
        raise RuntimeError("Core test selectors must be nonempty and unique")
    return result


def prepare():
    assert os.environ["GITHUB_REPOSITORY"] == "wuyong9494-lab/kriswu"
    assert os.environ["GITHUB_REF"] == "refs/heads/codex/fighter-visual-acceptance-20261113-1200"
    assert os.environ["GITHUB_RUN_ATTEMPT"] == "1"
    assert subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == os.environ["GITHUB_SHA"]
    assert not (ROOT / "App/Resources/FighterPrivate").exists()
    assert not (ROOT / "App/Resources/arena-original-resources.arenapack").exists()
    WORK.mkdir(exist_ok=False)
    (WORK / "plan.json").write_text(json.dumps({"commit": os.environ["GITHUB_SHA"],
        "selectors": selectors(), "coreSelectors": core_selectors(),
        "privateResources": False, "signed": False}, indent=2))
    xcode = "/Applications/Xcode_26.6.app"
    assert Path(xcode).is_dir()
    run(["sudo", "xcode-select", "-s", xcode], "select-xcode", 60)
    run(["xcodebuild", "-version"], "xcode-version", 60)
    if not shutil.which("xcodegen"):
        run(["brew", "install", "xcodegen"], "install-xcodegen", 300)
    (ROOT / "App/Resources/FighterPrivate").mkdir(mode=0o700, parents=True)
    project = ROOT / "project.yml"
    text = project.read_text()
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    assert text.count(needle) == 1
    project.write_text(text.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true'))
    run(["python3", ".github/scripts/build_identity.py"], "build-identity", 60)
    run(["xcodegen", "generate"], "project-generation", 120)


def core():
    selected = json.loads((WORK / "plan.json").read_text())["coreSelectors"]
    if not selected or len(set(selected)) != len(selected):
        raise RuntimeError("Core test plan must be nonempty and unique")
    expression = "^(?:" + "|".join(re.escape(value) for value in selected) + r")(?:\(\))?$"
    run(["swift", "test", "--jobs", "4", "--filter", expression], "core-tests", 1200)
    # SwiftPM's xUnit output can omit XCTest skips. The serial XCTest transcript
    # records every completed method, so require exactly the selected passes.
    completed = []
    log = (WORK / "core-tests.log").read_text(errors="replace")
    for identity, state in re.findall(r"^Test Case '(.+)' (passed|failed|skipped)\b", log, re.M):
        if identity.startswith("-[") and identity.endswith("]"):
            klass, method = identity[2:-1].split(" ", 1)
        else:
            klass, method = identity.rsplit(".", 1)
        if not klass.startswith("ShiftCoreTests."):
            klass = "ShiftCoreTests." + klass
        completed.append({"selector": klass + "/" + method.removesuffix("()"), "result": state})
    summary = {"expectedTests": len(selected), "totalTestCount": len(completed),
        "passedTests": sum(row["result"] == "passed" for row in completed),
        "failedTests": sum(row["result"] == "failed" for row in completed),
        "skippedTests": sum(row["result"] == "skipped" for row in completed), "tests": completed}
    (WORK / "core-test-summary.json").write_text(json.dumps(summary, indent=2))
    if sorted(row["selector"] for row in completed) != sorted(selected) or \
            summary["passedTests"] != len(selected) or summary["failedTests"] or summary["skippedTests"]:
        raise RuntimeError("Every selected core test must run and pass without skips; see core-test-summary.json")
    print(f"{len(selected)} selected core tests passed; zero failed/skipped.")


def build():
    run(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj",
        "-scheme", "ShiftReminder", "-configuration", "Debug", "-sdk", "iphonesimulator",
        "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(WORK / "derived"),
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        "FIGHTER_ASSET_RELEASE_SHA256=", "FIGHTER_XUXIAO_PROFILE_SHA256="], "native-build", 1500)
    products = WORK / "derived/Build/Products"
    plans = list(products.glob("*.xctestrun")); assert len(plans) == 1
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info.get("FighterAssetReleaseSHA256") in (None, "")
    assert info.get("FighterXuXiaoProfileSHA256") in (None, "")
    for path in app.rglob("*"):
        if path.is_file():
            assert not path.name.startswith(("SF3_", "SF3UI_", "SF3FX_", "SF3WE_", "SF3PG_"))
            assert path.suffix not in (".enc", ".pem", ".key", ".arenapack", ".texture")
    (WORK / "xctestrun-path.txt").write_text(str(plans[0]))


def simulator():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"], text=True))
    runtimes = {r["identifier"]: r for r in data["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]}
    choices = [(tuple(map(int, re.findall(r"\d+", runtimes[r]["version"]))), r, d["deviceTypeIdentifier"])
        for r, devices in data["devices"].items() if r in runtimes for d in devices
        if d.get("isAvailable") and d.get("deviceTypeIdentifier", "").endswith(".iPhone-17-Pro-Max")]
    assert choices, "Installed iPhone 17 Pro Max simulator required"
    _, runtime, device = max(choices)
    name = "Fighter display " + os.environ["GITHUB_RUN_ID"]
    udid = subprocess.check_output(["xcrun", "simctl", "create", name, device, runtime], text=True).strip()
    assert re.fullmatch(r"[0-9a-fA-F-]{36}", udid)
    (WORK / "simulator.json").write_text(json.dumps({"udid": udid, "runtime": runtime, "physicalDevice": False}))
    run(["xcrun", "simctl", "boot", udid], "simulator-boot", 120)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], "simulator-ready", 480)


def test():
    udid = json.loads((WORK / "simulator.json").read_text())["udid"]
    plan = (WORK / "xctestrun-path.txt").read_text()
    selected = json.loads((WORK / "plan.json").read_text())["selectors"]
    run(["xcodebuild", "test-without-building", "-xctestrun", plan,
        "-destination", "id=" + udid, "-resultBundlePath", str(WORK / "result.xcresult"),
        "-parallel-testing-enabled", "NO"] +
        ["-only-testing:" + value for value in selected], "native-tests", 900)


def export():
    result = WORK / "result.xcresult"
    if not result.is_dir():
        raise RuntimeError("No native result bundle; preparation or compilation cannot count as passing tests")
    raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result), "--format", "json"], text=True)
    (WORK / "test-summary.json").write_text(raw)
    summary = json.loads(raw)
    expected = len(json.loads((WORK / "plan.json").read_text())["selectors"])
    if not expected or summary.get("totalTestCount") != expected or summary.get("passedTests") != expected or \
            summary.get("failedTests") != 0 or summary.get("skippedTests") != 0:
        raise RuntimeError("Every selected native test must run and pass without skips: " + raw)
    print(f"{expected} native tests passed; zero failed/skipped. Simulator only, no private-resource or TV-device acceptance.")


def cleanup():
    path = WORK / "simulator.json"
    if path.exists():
        udid = json.loads(path.read_text())["udid"]
        assert re.fullmatch(r"[0-9a-fA-F-]{36}", udid)
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=60)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=True, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("prepare", "core", "build", "simulator", "test", "export", "cleanup"))
    globals()[parser.parse_args().phase]()
