"""One resource-independent unsigned Xu presentation diagnostic on iPhone and iPad."""
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

from verify_active_native_build import KEY_NAMES, CONTRACT, native_child_environment, result_counts, failed_test_receipt

SELECTED = ("ArenaFlowTests/DuelXuXiaoPracticeFlowTests/testReplacementPracticePlaysAndReturnsToGames",)
BUNDLE = "com.kriswu.shiftreminder"

def exact(condition, stage):
    if not condition:
        raise ValueError(stage)

KNOWN_STAGES = ('xu-preview-closed', 'xu-preview-fighter-exists', 'xu-preview-games-entry', 'xu-preview-games-entry-hittable', 'xu-preview-initial-figure-frame', 'xu-preview-landscape', 'xu-preview-movement-controls', 'xu-preview-notice', 'xu-preview-pause-hittable', 'xu-preview-pause-state', 'xu-preview-paused-input', 'xu-preview-player-figure-moved', 'xu-preview-rematch', 'xu-preview-replacement-label', 'xu-preview-restarted', 'xu-preview-result', 'xu-preview-result-input', 'xu-preview-resume-state', 'xu-preview-returned', 'xu-preview-title', 'xu-preview-title-unique')

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
    output = plan.with_name("XuPreviewReviewed.xctestrun")
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
    # This lane intentionally does not copy or verify the private three-character pack.
    exact(not (root / "App/Resources/FighterPrivate").exists(), "unexpected-private-resource-stage")
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
         "build-for-testing", "-configuration", "Release", "-destination", "generic/platform=iOS Simulator",
         "-derivedDataPath", str(derived), *(x for x in CONTRACT if not x.startswith("L12_INTERNAL_PREVIEW_CONDITION=")),
         "L12_INTERNAL_PREVIEW_CONDITION=L12_INTERNAL_PREVIEW L12_PRESENTATION_DIAGNOSTICS", "ARCHS=arm64"], "ui-build", 2200)
    products = derived / "Build/Products"
    app = products / "Release-iphonesimulator/ShiftReminder.app"
    plan_files = list(products.glob("ArenaFlow_*.xctestrun"))
    exact(len(plan_files) == 1, "ui-plan-count")
    plan = configure_plan(plan_files[0], app, identity)
    def fingerprint(bundle):
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        exact(info["CFBundleIdentifier"] == BUNDLE and set(info["UIDeviceFamily"]) == {1,2}
              and info["CFBundleExecutable"] == "ShiftReminder", "universal-app-identity")
        with (bundle / "ShiftReminder").open("rb") as stream:
            executable_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        return (executable_hash, info["CFBundleVersion"], info["CFBundleShortVersionString"])
    reference = fingerprint(app)
    receipt("shared-build", buildCount=1, privateResourcePackTested=False, universal=True,
            workflowSHA=sha, executableSHA256=reference[0])
    failed = []
    for lane, model, type_id in authorized_destinations:
        udid = None
        try:
            value = run([*sim, "create", "Rift Xu preview " + lane, type_id, runtimes[0]], lane + "-create").stdout.decode().strip()
            udid = str(uuid.UUID(value)).upper()
            run([*sim, "boot", udid], lane + "-boot")
            run([*sim, "bootstatus", udid], lane + "-bootstatus", 600)
            run([*sim, "install", udid, str(app)], lane + "-install", 180)
            installed = Path(run([*sim, "get_app_container", udid, BUNDLE, "app"], lane + "-pre-ui-container").stdout.decode().strip())
            exact(fingerprint(installed) == reference, lane + "-pre-ui-installed-build-mismatch")
            receipt(lane, checkpoint="before-ui", sameBuild=True)
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
            if p.returncode != 0:
                # Only predefined stage marker strings, never raw accessibility or screenshots.
                found = run([*sim, "get_app_container", udid, BUNDLE, "data"], lane + "-trace-container", allow_fail=True)
                trace = []
                if found.returncode == 0:
                    path = Path(found.stdout.decode().strip()) / "Library/Caches/rift-xu-presentation-stages.log"
                    if path.is_file() and not path.is_symlink() and path.stat().st_size <= 256:
                        rows = path.read_text(encoding="ascii", errors="replace").splitlines()
                        allowed = {"xu-entry-tapped", "xu-cover-constructed", "xu-preview-appeared", "xu-preview-disappeared"}
                        if len(rows) <= len(allowed) and len(set(rows)) == len(rows) and all(x in allowed for x in rows):
                            trace = rows
                receipt(lane, xuPresentationTrace=trace)
            data = jout([*prefix, "tests", "--path", str(result)], lane + "-tests")
            if p.returncode:
                raw = (p.stdout + p.stderr).decode("utf-8", errors="replace")
                sources = raw + json.dumps(summary) + json.dumps(data)
                receipt(lane, xuPreviewFailureStages=[code for code in KNOWN_STAGES if code in sources])
                receipt(lane, **failed_test_receipt(summary, data, SELECTED))
            exact(p.returncode == 0 and result_counts(summary, data, SELECTED) == 1, lane + "-test-not-proven")
            installed = Path(run([*sim, "get_app_container", udid, BUNDLE, "app"], lane + "-app-container").stdout.decode().strip())
            exact(fingerprint(installed) == reference, lane + "-installed-build-mismatch")
            receipt(lane, uiPassed=1, sameBuild=True, privateResourcePackTested=False,
                    xuReplacementPractice=True, officialXuRestoration=False, visualReviewCompleted=False)
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
