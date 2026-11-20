"""Protected qualification of a clean Xu preview, one unsigned 539-resource Release App on both simulators. No upload."""
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

import build_fighter_network_rules as rules
import completion_native_preflight as pre
from completion_active_pack import active_inventory, inspect, RETIRED
from verify_active_native_build import KEY_NAMES, CONTRACT, native_child_environment, result_counts, failed_test_receipt

SELECTED = ("ArenaFlowTests/DuelXuXiaoPracticeFlowTests/testReplacementPracticePlaysAndReturnsToGames",)
BUNDLE = "com.kriswu.shiftreminder"

FROZEN_BASE = "73a0cf1ef86e35f40ed99ed9cc0ec467f10f4826"
PRODUCTION_PATCH_SHA256 = "d7921fa6f7b01cd1a9aedb168ea68dca96aeddbec2dbff7b94d2f821f11a3a13"
ACTIVE_DIGEST = "68518f4887200da348b97535a76b6f3b88e3ef7943a1022993a4b6f20c1618fb"
RELEASE_SHA256 = "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3"
ESCROW_ENV = "FIGHTER_RECIPIENT_ESCROW_ZIP_B64"
XU_SHIPPING_PATCH_SHA256 = 'ea0d04361889902ddcd81a6bd481fda3effb09cd5d23b0bc1cd5ca6a6f092041'
XU_RUNTIME_SOURCES = {'App/Services/DuelXuXiaoPracticeController.swift': '4b0a22e71a5dd64a1beb44eb8c5f6b051e1ab259daf272f4970bdc62ffadb2b4', 'App/Views/DuelXuXiaoPracticeView.swift': '166b4dbade0f5b9455e7d1469e42c7d4b9d7ba2862063889e2237de56021a999', 'App/Views/GamesHomeView.swift': '65c57e715a870df74d6c98e1a679859f7e04c755e44240c2b57ca799cd15fcda', 'Sources/ShiftCore/DuelXuXiaoPractice.swift': 'ed060354946867c6b5d98cf2b5e8b88f9b362c442e9d12190b51acda0448085f'}


def exact(condition, stage):
    if not condition:
        raise ValueError(stage)

KNOWN_STAGES = ('xu-preview-closed', 'xu-preview-fighter-exists', 'xu-preview-games-entry', 'xu-preview-games-entry-hittable', 'xu-preview-initial-figure-frame', 'xu-preview-landscape', 'xu-preview-movement-controls', 'xu-preview-notice', 'xu-preview-pause-hittable', 'xu-preview-pause-state', 'xu-preview-paused-input', 'xu-preview-player-figure-moved', 'xu-preview-rematch', 'xu-preview-replacement-label', 'xu-preview-restarted', 'xu-preview-result', 'xu-preview-result-input', 'xu-preview-resume-state', 'xu-preview-returned', 'xu-preview-title', 'xu-preview-title-unique')

def verify_xu_source(root):
    """Identity check, not original-character authenticity or behavior proof."""
    result = {}
    for relative, expected in XU_RUNTIME_SOURCES.items():
        path = root / relative
        exact(path.is_file() and not path.is_symlink(), "xu-shipping-source-file")
        content = path.read_bytes()
        exact(b"L12_PRESENTATION_DIAGNOSTICS" not in content
              and b"DuelXuXiaoPresentationTrace" not in content, "xu-shipping-diagnostics")
        result[relative] = hashlib.sha256(content).hexdigest()
        exact(result[relative] == expected, "xu-shipping-source-identity")
    exact(not (root / "App/Services/DuelXuXiaoPresentationTrace.swift").exists(), "xu-shipping-trace-helper")
    return result

def unique_pairs(rows):
    result = {}
    for key, value in rows:
        exact(key not in result, "network-rules-duplicate-key")
        result[key] = value
    return result

def verify_compiled_rules(root, bundle):
    path = bundle / "FighterNetworkRules.json"
    exact(path.is_file() and not path.is_symlink() and path.stat().st_size <= 262144,
          "network-rules-file")
    data = path.read_bytes()
    manifest = json.loads(data, object_pairs_hook=unique_pairs)
    exact(isinstance(manifest, dict), "network-rules-shape")
    context = manifest.get("build", {})
    exact(isinstance(context, dict) and all(isinstance(v, str) for v in context.values())
          and context.get("CONFIGURATION") == "Release"
          and context.get("PLATFORM_NAME") == "iphonesimulator"
          and context.get("FIGHTER_ASSET_RELEASE_SHA256") == RELEASE_SHA256
          and context.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split() == ["L12_INTERNAL_PREVIEW"],
          "xu-clean-preview-compiled-conditions")
    exact(context == rules.xcode_build_context(context)
          and manifest == rules.build_manifest(root, context), "network-rules-source-identity")
    return hashlib.sha256(data).hexdigest()

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
    exact(sys.platform == "darwin" and all(k not in os.environ for k in (*KEY_NAMES, ESCROW_ENV)), "unsigned-mac-runner")
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
    exact(run(["/usr/bin/git", "rev-parse", "HEAD"], "frozen-base").stdout.decode().strip() == FROZEN_BASE, "frozen-base-identity")
    source_hashes = verify_xu_source(root)
    inspect(root, staged=root / "App/Resources/FighterPrivate")
    active, content_sha = active_inventory(root)
    exact(len(active) == 539 and content_sha == ACTIVE_DIGEST, "active-inventory")
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
         "L12_INTERNAL_PREVIEW_CONDITION=L12_INTERNAL_PREVIEW", "ARCHS=arm64"], "ui-build", 2200)
    products = derived / "Build/Products"
    app = products / "Release-iphonesimulator/ShiftReminder.app"
    plan_files = list(products.glob("ArenaFlow_*.xctestrun"))
    exact(len(plan_files) == 1, "ui-plan-count")
    plan = configure_plan(plan_files[0], app, identity)
    def fingerprint(bundle):
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        exact(info["CFBundleIdentifier"] == BUNDLE and set(info["UIDeviceFamily"]) == {1,2}
              and info["CFBundleExecutable"] == "ShiftReminder"
              and info.get("FighterAssetReleaseSHA256") == RELEASE_SHA256
              and info.get("FighterXuXiaoProfileSHA256") == "", "universal-app-identity")
        pre.app_resources(bundle, active, forbidden_names=[RETIRED["name"], "Validation_D13_Bottle_Source_Oracle.json", "rift-xu-presentation-stages.log"], compiled_sha256=content_sha)
        with (bundle / "ShiftReminder").open("rb") as stream:
            executable_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        return (executable_hash, info["CFBundleVersion"], info["CFBundleShortVersionString"], verify_compiled_rules(root, bundle))
    reference = fingerprint(app)
    receipt("shared-build", buildCount=1, resourceCount=539, universal=True,
            workflowSHA=sha, executableSHA256=reference[0], resourceSHA256=content_sha,
            frozenBaseSHA=FROZEN_BASE, productionSourcePatchSHA256=PRODUCTION_PATCH_SHA256,
            xuShippingPatchSHA256=XU_SHIPPING_PATCH_SHA256, xuRuntimeSourceSHA256=source_hashes,
            xuPresentationDiagnostics=False, networkRulesSHA256=reference[3])
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
                sources = raw + json.dumps(summary) + json.dumps(data)
                receipt(lane, xuPreviewFailureStages=[code for code in KNOWN_STAGES if code in sources])
                receipt(lane, **failed_test_receipt(summary, data, SELECTED))
            exact(p.returncode == 0 and result_counts(summary, data, SELECTED) == 1, lane + "-test-not-proven")
            installed = Path(run([*sim, "get_app_container", udid, BUNDLE, "app"], lane + "-app-container").stdout.decode().strip())
            exact(fingerprint(installed) == reference, lane + "-installed-build-mismatch")
            receipt(lane, uiPassed=1, installedResourceCount=539, sameBuild=True,
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
