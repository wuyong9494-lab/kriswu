"""One unsigned ArenaFlow build; one real-control test on each simulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import subprocess
import sys
import uuid

import completion_native_preflight as pre
from completion_active_pack import active_inventory, inspect, RETIRED
from verify_active_native_build import KEY_NAMES, CONTRACT, native_child_environment, result_counts, failed_test_receipt

SELECTED = ("ArenaFlowTests/DuelRecoveredCharacterFlowTests/testRecoveredFightersSelectMoveHitTwicePauseAndReturn",)
BUNDLE = "com.kriswu.shiftreminder"

def exact(condition, stage):
    if not condition:
        raise ValueError(stage)

HEROES = ("ember", "liu", "wuyong_erlang")
STEPS = {"select", "lobby-ready", "practice-ready", "close-weapon-range", "paused",
         "pause-stable", "resumed", "exit-available", "returned-to-lobby"}
MARKER = re.compile(r"\bRIFT_UI_CHECKPOINT hero=(none|ember|liu|wuyong_erlang) phase=([a-z0-9_-]{1,70}) completed=([0-3])(?![0-9])")

def parse_marker(*sources):
    valid = set()
    for payload in sources:
        for hero, phase, count in MARKER.findall(payload):
            count = int(count)
            if hero == "none":
                if count != 0 or phase not in {"not-launched", "prepare-evidence", "launch", "landscape-lobby"}:
                    continue
                step = phase
            else:
                if not phase.startswith(hero + "-") or count not in {HEROES.index(hero), HEROES.index(hero) + 1}:
                    continue
                step = phase[len(hero) + 1:]
                if step not in STEPS and not re.fullmatch(
                    r"(?:weapon-ready|weapon-contact)-[12]|(?:approach|movement)-[12]-(?:[0-9]|1[0-5])", step
                ):
                    continue
            valid.add((hero, step, count))
    if len(valid) == 1:
        hero, step, count = valid.pop()
        return dict(checkpointHero=hero, checkpointPhase=step, completedHeroes=count)
    return dict(checkpointStatus="conflict" if valid else "unavailable")

def configure_plan(plan, app, identity):
    content = plistlib.loads(plan.read_bytes())
    if "TestConfigurations" in content:
        configurations = content["TestConfigurations"]
        exact(len(configurations) == 1 and configurations[0].get("IsEnabled", True) is True, "ui-plan-configuration")
        targets = configurations[0]["TestTargets"]
    else:
        targets = [r for r in content.values() if isinstance(r, dict) and "TestBundlePath" in r]
    exact(len(targets) == 1, "ui-plan-target-count")
    target = targets[0]
    exact(target.get("BlueprintName") == "ArenaFlowTests" and target.get("IsUITestBundle") is True
          and target.get("IsEnabled", True) is True and not target.get("SkipTestIdentifiers")
          and not target.get("OnlyTestIdentifiers") and not target.get("UseDestinationArtifacts"), "ui-plan-target")
    path = target["UITargetAppPath"].replace("__TESTROOT__", str(plan.parent))
    exact(Path(path).resolve(strict=True) == app.resolve(strict=True), "ui-plan-app")
    environment = target.setdefault("EnvironmentVariables", {})
    exact(not (set(identity) & set(environment)), "ui-plan-capture-environment")
    environment.update(identity)
    output = plan.with_name("DualDeviceReviewed.xctestrun")
    with output.open("xb") as stream:
        plistlib.dump(content, stream, fmt=plistlib.FMT_BINARY)
    return output

def run_all(root, work, xcodegen, sha, run_id, attempt):
    exact(sys.platform == "darwin" and all(k not in os.environ for k in KEY_NAMES), "unsigned-mac-runner")
    exact(bool(re.fullmatch(r"[0-9a-f]{40}", sha)) and bool(re.fullmatch(r"[1-9][0-9]{0,19}", run_id))
          and attempt == "1", "capture-identity")
    identity = dict(FIGHTER_CAPTURE_SOURCE_SHA=sha, FIGHTER_CAPTURE_RUN_ID=run_id, FIGHTER_CAPTURE_RUN_ATTEMPT=attempt)
    root, work = root.resolve(strict=True), work.resolve(strict=True)
    exact(not (work.is_relative_to(root) or root.is_relative_to(work)), "separate-derived-data")
    os.umask(0o077)
    env = native_child_environment(os.environ, pwd.getpwuid(os.getuid()).pw_name)
    def run(argv, stage, timeout=120, allow_fail=False):
        try:
            p = subprocess.run(argv, cwd=root, env=env, timeout=timeout, capture_output=True)
        except subprocess.TimeoutExpired:
            raise ValueError("timeout-" + stage) from None
        (work / (stage + ".log")).write_bytes(p.stdout + p.stderr)
        if not allow_fail:
            exact(p.returncode == 0, stage)
        return p
    def jout(argv, stage):
        return json.loads(run(argv, stage).stdout)
    def receipt(lane, **fields):
        print(json.dumps(dict(lane=lane, **fields)), flush=True)
    xcode, sim = "/usr/bin/xcodebuild", ["/usr/bin/xcrun", "simctl"]
    exact(run([xcode, "-version"], "xcode-version").stdout.startswith(b"Xcode 26.6\n"), "xcode-version")
    exact(run(["/usr/bin/uname", "-m"], "runner-arch").stdout.strip() == b"arm64", "runner-arch")
    inspect(root, staged=root / "App/Resources/FighterPrivate")
    active, content_sha = active_inventory(root)
    exact(len(active) == 539, "active-inventory")
    devices = jout([*sim, "list", "-j"], "sim-inventory")
    runtimes = [r["identifier"] for r in devices["runtimes"] if r.get("isAvailable") and r["version"] == "26.5" and ".iOS-" in r["identifier"]]
    phones = sorted(t["identifier"] for t in devices["devicetypes"] if t["name"] == "iPhone 17 Pro Max")
    pads = sorted((t["name"], t["identifier"]) for t in devices["devicetypes"] if t["name"].startswith("iPad"))
    exact(len(runtimes) == len(phones) == 1 and bool(pads), "simulator-destinations")
    # Prefer a 13-inch Pro, then a deterministic installed iPad device type.
    pads.sort(key=lambda item: (not item[0].startswith("iPad Pro 13-inch"), item[0], item[1]))
    authorized_destinations = [("iphone-ui", "iPhone 17 Pro Max", phones[0]), ("ipad-ui", *pads[0])]
    run([str(xcodegen), "generate", "--spec", str(root / "project.yml"), "--project", str(root)], "project-generation")
    derived = work / "ui-derived"
    run([xcode, "-project", str(root / "ShiftReminder.xcodeproj"), "-scheme", "ArenaFlow", "-sdk", "iphonesimulator",
         "build-for-testing", "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
         "-derivedDataPath", str(derived), *CONTRACT, "ARCHS=arm64"], "ui-build", 2200)
    products = derived / "Build/Products"
    app = products / "Debug-iphonesimulator/ShiftReminder.app"
    plan_files = list(products.glob("ArenaFlow_*.xctestrun"))
    exact(len(plan_files) == 1, "ui-plan-count")
    plan = configure_plan(plan_files[0], app, identity)
    def fingerprint(bundle):
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        exact(info["CFBundleIdentifier"] == BUNDLE and set(info["UIDeviceFamily"]) == {1,2}
              and info["CFBundleExecutable"] == "ShiftReminder", "universal-app-identity")
        pre.app_resources(bundle, active, forbidden_names=[RETIRED["name"]], compiled_sha256=content_sha)
        with (bundle / "ShiftReminder").open("rb") as stream:
            executable_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        return (executable_hash, info["CFBundleVersion"], info["CFBundleShortVersionString"])
    reference = fingerprint(app)
    receipt("shared-build", buildCount=1, resourceCount=539, universal=True,
            workflowSHA=sha, executableSHA256=reference[0], resourceSHA256=content_sha)
    failed = []
    for lane, model, type_id in authorized_destinations:
        udid = None
        try:
            value = run([*sim, "create", "Rift accepted dual " + lane, type_id, runtimes[0]], lane + "-create").stdout.decode().strip()
            udid = str(uuid.UUID(value)).upper()
            run([*sim, "boot", udid], lane + "-boot")
            run([*sim, "bootstatus", udid], lane + "-bootstatus", 600)
            run([*sim, "install", udid, str(app)], lane + "-install", 180)
            installed = Path(run([*sim, "get_app_container", udid, BUNDLE, "app"], lane + "-pre-ui-container").stdout.decode().strip())
            exact(fingerprint(installed) == reference, lane + "-pre-ui-installed-build-mismatch")
            receipt(lane, checkpoint="before-ui", sameBuild=True, installedResourceCount=539)
            args = [xcode, "test-without-building", "-xctestrun", str(plan), "-destination", "id=" + udid,
                    "-parallel-testing-enabled", "NO"]
            result = work / (lane + ".xcresult")
            p = run([*args, "-resultBundlePath", str(result), "-only-testing:" + SELECTED[0]],
                    lane + "-exercise", 1000, allow_fail=True)
            prefix = ["/usr/bin/xcrun", "xcresulttool", "get", "test-results"]
            exact(result.is_dir(), lane + "-missing-result")
            summary = jout([*prefix, "summary", "--path", str(result)], lane + "-summary")
            counts = {k: summary.get(k) if type(summary.get(k)) is int else None for k in
                      ("totalTestCount", "passedTests", "failedTests", "skippedTests")}
            receipt(lane, simulator=model, testExit=p.returncode, **counts)
            data = jout([*prefix, "tests", "--path", str(result)], lane + "-tests")
            if p.returncode:
                raw = (p.stdout + p.stderr).decode("utf-8", errors="replace")
                marker = parse_marker(json.dumps(summary), json.dumps(data), raw)
                if marker == {"checkpointStatus": "unavailable"}:
                    try:
                        container = run([*sim, "get_app_container", udid, BUNDLE + ".arenaflowtests.xctrunner", "data"],
                                        lane + "-runner-container", 30, allow_fail=True)
                        if container.returncode == 0:
                            path = Path(container.stdout.decode().strip())
                            if path.is_absolute() and path.is_dir():
                                evidence = path / "Documents/FighterRecoveredCharacterCapture/recovered-character-flow.json"
                                if evidence.is_file() and not evidence.is_symlink():
                                    with evidence.open("rb") as stream:
                                        blob = stream.read(2_000_001)
                                    if len(blob) <= 2_000_000:
                                        report = json.loads(blob)
                                        heroes = report.get("completedHeroes")
                                        phase = report.get("lastPhase")
                                        if (report.get("schema") == "recovered-character-flow-v1"
                                            and report.get("identity") == identity
                                            and report.get("flowCompleted") is False
                                            and type(phase) is str and type(heroes) is list
                                            and heroes == list(HEROES[:len(heroes)])):
                                            hero = next((h for h in HEROES if phase.startswith(h + "-")), "none")
                                            marker = parse_marker(f"RIFT_UI_CHECKPOINT hero={hero} phase={phase} completed={len(heroes)}")
                    except (OSError, ValueError, AttributeError):
                        pass
                receipt(lane, **marker)
                receipt(lane, **failed_test_receipt(summary, data, SELECTED))
            exact(p.returncode == 0 and result_counts(summary, data, SELECTED) == 1, lane + "-test-not-proven")
            installed = Path(run([*sim, "get_app_container", udid, BUNDLE, "app"], lane + "-app-container").stdout.decode().strip())
            exact(fingerprint(installed) == reference, lane + "-installed-build-mismatch")
            receipt(lane, uiPassed=1, installedResourceCount=539, sameBuild=True,
                    characters=3, originalCaptureProduced=True, visualReviewCompleted=False)
        except Exception as exc:
            failed.append(lane)
            receipt(lane, success=False, reason=safe_reason(exc))
        finally:
            if udid:
                try:
                    run([*sim, "shutdown", udid], lane + "-shutdown", allow_fail=True)
                    run([*sim, "delete", udid], lane + "-delete", allow_fail=True)
                except (OSError, ValueError):
                    receipt(lane, cleanupWarning=True)
    receipt("dual-ui", success=not failed, failedLanes=failed, physicalDevices=False, testflightUploaded=False)
    return not failed

def safe_reason(exc):
    reason = str(exc)
    return reason if type(exc) is ValueError and re.fullmatch(r"[a-z0-9-]{1,100}", reason) else type(exc).__name__

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "work", "xcodegen"):
        parser.add_argument(name, type=Path)
    for name in ("sha", "run_id", "attempt"):
        parser.add_argument(name)
    a = parser.parse_args()
    try:
        passed = run_all(a.repo, a.work, a.xcodegen, a.sha, a.run_id, a.attempt)
    except Exception as exc:
        print(json.dumps(dict(lane="dual-ui", success=False, reason=safe_reason(exc))), flush=True)
        passed = False
    raise SystemExit(0 if passed else 1)
