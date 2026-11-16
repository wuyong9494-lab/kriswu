#!/usr/bin/env python3
"""One unsigned build and exact asset-free display/network native regression."""
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
    ("DuelNetworkCombatCoordinatorTests.swift", "DuelLifecycleTests", 29),
    ("DuelTriadMetalRendererTests.swift", "DuelTriadMetalRendererTests", 6),
)


def run(args, name, timeout):
    with (WORK / (name + ".log")).open("w") as output:
        result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print((WORK / (name + ".log")).read_text(errors="replace")[-16000:])
        raise RuntimeError(f"{name} exited {result.returncode}")
    print(name + " passed", flush=True)


def selectors():
    result = []
    for filename, klass, expected in SOURCES:
        text = (ROOT / "Tests/SiteTests" / filename).read_text()
        methods = re.findall(r"^    func (test\w+)\(", text, re.M)
        assert len(methods) == expected and len(set(methods)) == expected
        result.extend(f"SiteTests/{klass}/{method}" for method in methods)
    assert len(result) == 43 and len(set(result)) == 43
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
        "selectors": selectors(), "privateResources": False, "signed": False}, indent=2))
    xcode = "/Applications/Xcode_26.6.app"
    assert Path(xcode).is_dir()
    run(["sudo", "xcode-select", "-s", xcode], "select-xcode", 60)
    run(["xcodebuild", "-version"], "xcode-version", 60)
    if not shutil.which("xcodegen"):
        run(["brew", "install", "xcodegen"], "install-xcodegen", 300)
    (ROOT / "App/Resources/FighterPrivate").mkdir(mode=0o700)
    project = ROOT / "project.yml"
    text = project.read_text()
    needle = "    scheme:\n      testTargets:\n        - SiteTests"
    assert text.count(needle) == 1
    project.write_text(text.replace(needle, needle + '\n      commandLineArguments:\n        "-demo": true'))
    run(["python3", ".github/scripts/build_identity.py"], "build-identity", 60)
    run(["xcodegen", "generate"], "project-generation", 120)


def build():
    run(["xcodebuild", "build-for-testing", "-project", "ShiftReminder.xcodeproj",
        "-scheme", "ShiftReminder", "-configuration", "Debug", "-sdk", "iphonesimulator",
        "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(WORK / "derived"),
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        "FIGHTER_ASSET_RELEASE_SHA256="], "native-build", 1500)
    products = WORK / "derived/Build/Products"
    plans = list(products.glob("*.xctestrun")); assert len(plans) == 1
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info.get("FighterAssetReleaseSHA256") in (None, "")
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
    selected = selectors()
    run(["xcodebuild", "test-without-building", "-xctestrun", plan,
        "-destination", "id=" + udid, "-resultBundlePath", str(WORK / "result.xcresult"),
        "-parallel-testing-enabled", "NO", "-test-iterations", "1"] +
        ["-only-testing:" + value for value in selected], "native-tests", 900)


def export():
    result = WORK / "result.xcresult"
    if not result.exists():
        print("No test result bundle; inspect the build log."); return
    raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result), "--format", "json"], text=True)
    (WORK / "test-summary.json").write_text(raw)
    summary = json.loads(raw)
    assert summary.get("totalTestCount") == 43, summary
    assert summary.get("passedTests") == 43 and summary.get("failedTests") == 0
    assert summary.get("skippedTests") == 0
    print("43 native tests passed; zero failed/skipped. Simulator only, no private-resource or TV-device acceptance.")


def cleanup():
    path = WORK / "simulator.json"
    if path.exists():
        udid = json.loads(path.read_text())["udid"]
        assert re.fullmatch(r"[0-9a-fA-F-]{36}", udid)
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=60)
        subprocess.run(["xcrun", "simctl", "delete", udid], check=True, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("prepare", "build", "simulator", "test", "export", "cleanup"))
    globals()[parser.parse_args().phase]()
