"""Run the real games entry and protected combat regressions for the same Release simulator build."""
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import pwd
import re
import subprocess
import sys
import uuid

from completion_active_pack import inspect
from verify_active_native_build import CONTRACT, KEY_NAMES, native_child_environment, result_counts
from verify_xuxiao_qualified_ui import ACTIVE_DIGEST, BUNDLE, FROZEN_BASE, RELEASE_SHA256, verify_compiled_rules

LIVE = "ArenaFlowTests/DuelLiveMatchFlowTests/testLiuCanHitSunFromToday"
PRACTICE = "ArenaFlowTests/DuelXuXiaoPracticeFlowTests/testReplacementPracticePlaysAndReturnsToGames"
CORE = ("DuelCombatRulesTests", "DuelTriadStanceTests", "DuelWeaponInputTests", "DuelXuXiaoPracticeTests",
        "DuelGameTests", "DuelErlangFightIntegrationTests", "DuelManualGuardTests", "DuelReplayStateAuditTests",
        "DuelTriadFightTests", "DuelTriadStunImpactTests")
INDIVIDUAL = (
    "DuelRecoveredCharacterInstalledTests/testLiuPersonalHeadIsDisplayedAndFollowsRecoveredRig",
    "DuelRecoveredCharacterInstalledTests/testWuPortraitHasShorterNeckAndKeepsAnimatedCollarSeams",
    "DuelSerpentMorphSourceTests/testActualD13GeometryInstallsCompleteMorphAndRestoresAfterHideAndCancellation",
    "DuelWeaponGameplayTests/testFreshWeaponTapStartsOnFirstPlayableFrameAgainstSun",
    "DuelOptionalResourceIsolationInstalledTests/testLocalMatchLoadsOnlySelectedPairFromBundledIndex",
)
WHOLE_CLASSES = ("DuelSourceProjectedShadowRendererTests", "DuelDisplayedRigidBoundsTests",
                 "DuelMusicTests", "DuelLobbyMusicSelectionTests")
SITE_SOURCES = (
    "DuelRecoveredCharacterInstalledTests", "DuelSerpentMorphSourceTests", "DuelWeaponGameplayTests",
    "DuelOptionalResourceIsolationTests", "DuelLocalWeaponProfileTests", *WHOLE_CLASSES,
)
MEASUREMENTS = {
    "entryMs", "lobbyMs", "matchMs", "hitMs", "hpBefore", "hpAfter", "weaponPresses",
    "frameP95Ms", "slowFrames", "frameSamples",
}
SCHEME = """
  LiveGameplay:
    build:
      targets:
        ShiftReminder: all
        SiteTests: [test]
        ArenaFlowTests: [test]
    test:
      config: Release
      targets:
        - SiteTests
        - ArenaFlowTests
"""


class Failure(Exception):
    pass


def require(ok, message):
    if not ok:
        raise Failure(message)


def report(stage, **values):
    print(json.dumps(dict(stage=stage, **values), ensure_ascii=True, allow_nan=False), flush=True)


def diagnostic(raw):
    # Diagnostics point to public source. Suppress arbitrary process dumps and unbounded XCTest values.
    result = []
    for line in raw.splitlines():
        match = re.search(r'([\w.+-]+\.swift):(\d+)(?::(\d+))?: (?:fatal )?error: (.+)', line)
        if not match:
            continue
        detail = re.sub(r'(?:[A-Za-z0-9+/=_-]{40,}|/[^\s]+)', '<omitted>', match[4])[:300]
        label = f"{match[1]}:{match[2]}: {detail}"
        if label not in result:
            result.append(label)
        if len(result) == 3:
            break
    if not result:
        for line in raw.splitlines():
            if re.search(r'(?:xcodebuild: error:|(?:^|\s)error: |XCTAssert\w* failed|XCTUnwrap failed|failed to tap|Failed to (?:launch|boot|install))', line, re.I):
                brief = re.sub(r'(?:[A-Za-z0-9+/=_-]{40,}|/[^\s]+)', '<omitted>', line.strip())[:300]
                result.append(brief)
                break
    return result


class Runner:
    def __init__(self, root, work):
        self.root = root
        self.work = work
        self.env = native_child_environment(os.environ, pwd.getpwuid(os.getuid()).pw_name)

    def run(self, name, args, *, timeout=120, check=True):
        log = self.work / (name + ".log")
        with log.open("wb") as stream:
            try:
                status = subprocess.run(list(map(str, args)), cwd=self.root, env=self.env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                raise Failure(name + " timed out") from None
        output = log.read_text(errors="replace")
        if check and status:
            report(name, exitCode=status, diagnostics=diagnostic(output))
            raise Failure(name + " failed")
        return status, output

    def read(self, name, args):
        return self.run(name, args)[1].strip()


def exercise_core(r):
    status, log = r.run("combat-core", ["/usr/bin/xcrun", "swift", "test", "--scratch-path", r.work / "swift",
                        "-Xswiftc", "-DL12_INTERNAL_PREVIEW", "--filter", "|".join(CORE)], timeout=1000, check=False)
    totals = re.findall(r'Executed (\d+) tests?, with (\d+) failures?', log)
    passed = {suite: bool(re.search(r"Test Suite '(?:[^']*\.)?" + suite + r"' passed", log)) for suite in CORE}
    ok = (status == 0 and totals and int(totals[-1][0]) > 0 and int(totals[-1][1]) == 0 and
          all(passed.values()) and not re.search(r"\bskipped\b", log, re.I))
    report("combat-core", success=bool(ok), suites=passed, passed=int(totals[-1][0]) if ok else None,
           diagnostics=[] if ok else diagnostic(log))
    return bool(ok)


def write_project(root):
    # Retain the original hosted target, settings and target dependencies. The additional
    # Release scheme compiles the checked hosted sources plus their Swift fixture once.
    spec = (root / "project.yml").read_text()
    source = "      - path: Tests/SiteTests\n"
    require(spec.count(source) == 1, "unexpected hosted source definition")
    files = [root / f"Tests/SiteTests/{name}.swift" for name in SITE_SOURCES]
    require(all(f.is_file() for f in files), "hosted test source missing")
    focused = "".join(f"      - path: {f.relative_to(root)}\n" for f in files)
    path = root / ".live-gameplay-project.yml"
    with path.open("x") as stream:
        stream.write(spec.replace(source, focused).rstrip() + "\n" + SCHEME)
    return path


def expected_selectors(root):
    selected = [LIVE, PRACTICE, *("SiteTests/" + test for test in INDIVIDUAL)]
    for suite in WHOLE_CLASSES:
        text = (root / f"Tests/SiteTests/{suite}.swift").read_text()
        methods = re.findall(r'^    func (test\w+)\(', text, flags=re.M)
        require(methods and len(methods) == len(set(methods)), "invalid hosted suite methods")
        selected.extend("SiteTests/" + suite + "/" + method for method in methods)
    for expected in ("testPackedPalettesPreserveDistinctPosesAcrossPendingMaps", "testTwoActorsAppendInOrderAndClearHiddenPreviousFramePoints"):
        require(any(test.endswith("/" + expected) for test in selected), "missing renderer regression " + expected)
    return selected


def installed_identity(root, app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == BUNDLE and set(info.get("UIDeviceFamily", [])) == {1, 2}
            and info.get("CFBundleExecutable") == "ShiftReminder" and info.get("FighterAssetReleaseSHA256") == RELEASE_SHA256
            and info.get("FighterXuXiaoProfileSHA256") == "", "bundle release identity")
    assets = inspect(root, app=app)
    require(assets["compiledContentSHA256"] == ACTIVE_DIGEST and assets["requiredFiles"] == 539, "installed active asset pack")
    with (app / "ShiftReminder").open("rb") as stream:
        executable = hashlib.file_digest(stream, "sha256").hexdigest()
    return executable, verify_compiled_rules(root, app)


def verify_plan(plan, app):
    content = plistlib.loads(plan.read_bytes())
    if "TestConfigurations" in content:
        configs = [c for c in content["TestConfigurations"] if c.get("IsEnabled", True)]
        require(len(configs) == 1, "unexpected test plan configurations")
        targets = configs[0]["TestTargets"]
    else:
        targets = [v for v in content.values() if isinstance(v, dict) and "TestBundlePath" in v]
    require(len(targets) == 2 and {t["BlueprintName"] for t in targets} == {"SiteTests", "ArenaFlowTests"}, "test plan targets")
    for t in targets:
        require(t.get("IsEnabled", True) and not t.get("SkipTestIdentifiers") and not t.get("UseDestinationArtifacts"), "test plan destination")
        key = "UITargetAppPath" if t["BlueprintName"] == "ArenaFlowTests" else "TestHostPath"
        declared = Path(t[key].replace("__TESTROOT__", str(plan.parent))).resolve(strict=True)
        require(declared == app.resolve(strict=True) or declared == (app / "ShiftReminder").resolve(strict=True), "test plan host")


def get_measurements(raw):
    for line in raw.splitlines():
        _, sep, rest = line.partition("RIFT_LIVE ")
        if not sep:
            continue
        try:
            data, _ = json.JSONDecoder().raw_decode(rest.lstrip()[:2048])
        except ValueError:
            continue
        if valid_measurements(data):
            return data


def valid_measurements(data):
    return (isinstance(data, dict) and set(data) == MEASUREMENTS
            and all(type(v) in (int, float) and math.isfinite(v) and 0 <= v <= 1_000_000 for v in data.values())
            and data["hpBefore"] > data["hpAfter"] and data["weaponPresses"] > 0
            and data["frameP95Ms"] > 0 and 0 <= data["slowFrames"] <= data["frameSamples"] and data["frameSamples"] >= 2)


def read_attached_measurements(r, lane, result):
    # Attachments stay in runner temporary storage. Only return a small JSON with this exact schema.
    directory = r.work / (lane + "-attachments")
    directory.mkdir()
    r.run(lane + "-export-metrics", ["/usr/bin/xcrun", "xcresulttool", "export", "attachments",
          "--path", result, "--output-path", directory], timeout=120)
    for path in directory.rglob("*"):
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 2048:
            continue
        try:
            data = json.loads(path.read_bytes())
        except (ValueError, UnicodeError):
            continue
        if valid_measurements(data):
            return data
    raise Failure(lane + " live metrics missing")


def run_lane(r, lane, device, runtime, plan, app, reference, selected):
    sim = ["/usr/bin/xcrun", "simctl"]
    model, device_type = device
    udid = str(uuid.UUID(r.read(lane + "-create", [*sim, "create", "Rift live " + lane, device_type, runtime]))).upper()
    try:
        r.run(lane + "-boot", [*sim, "boot", udid])
        r.run(lane + "-bootstatus", [*sim, "bootstatus", udid], timeout=600)
        r.run(lane + "-install", [*sim, "install", udid, app], timeout=180)

        def check_installed(tag):
            path = r.read(lane + tag, [*sim, "get_app_container", udid, BUNDLE, "app"])
            require(installed_identity(r.root, Path(path)) == reference, lane + " installed app differs")

        check_installed("-before")
        result = r.work / (lane + ".xcresult")
        status, raw = r.run(lane + "-tests", ["/usr/bin/xcodebuild", "test-without-building", "-xctestrun", plan,
                            "-destination", "id=" + udid, "-parallel-testing-enabled", "NO", "-resultBundlePath", result,
                            *("-only-testing:" + key for key in selected)], timeout=1500, check=False)
        if not result.is_dir():
            report(lane, exitCode=status, diagnostics=diagnostic(raw))
            raise Failure(lane + " test result missing")
        prefix = ["/usr/bin/xcrun", "xcresulttool", "get", "test-results"]
        summary = json.loads(r.read(lane + "-summary", [*prefix, "summary", "--path", result]))
        tests = json.loads(r.read(lane + "-identifiers", [*prefix, "tests", "--path", result]))
        counts = {key: summary.get(key) for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests")}
        if status or summary.get("result") != "Passed":
            failed = summary.get("testFailures") or []
            messages = "\n".join(str(item.get("failureText", "")) for item in failed if isinstance(item, dict))
            names = [item.get("testIdentifier", "") for item in failed if isinstance(item, dict)]
            report(lane, simulator=model, exitCode=status, **counts,
                   failedTestsByName=[name for name in names if re.fullmatch(r"[A-Za-z0-9_./() +\[\]-]{1,210}", name)][:8],
                   diagnostics=diagnostic(raw + "\n" + messages))
            raise Failure(lane + " native tests failed")
        count = result_counts(summary, tests, selected)
        measures = get_measurements(raw) or read_attached_measurements(r, lane, result)
        check_installed("-after")
        info = dict(model=model, passed=count, metrics=measures,
                    slowFramePercent=round(100 * measures["slowFrames"] / measures["frameSamples"], 2))
        report(lane, **info)
        return info
    finally:
        r.run(lane + "-shutdown", [*sim, "shutdown", udid], check=False)
        r.run(lane + "-delete", [*sim, "delete", udid], check=False)


def main(root, work, xcodegen, sha):
    import build_fighter_network_rules as rules
    root, work = Path(root).resolve(strict=True), Path(work).resolve(strict=True)
    require(sys.platform == "darwin" and not any(k in os.environ for k in (*KEY_NAMES, "FIGHTER_RECIPIENT_ESCROW_ZIP_B64")), "protected tool environment")
    require(not (work.is_relative_to(root) or root.is_relative_to(work)) and re.fullmatch(r"[0-9a-f]{40}", sha), "runner inputs")
    os.umask(0o077)
    r = Runner(root, work)
    require(r.read("xcode", ["/usr/bin/xcodebuild", "-version"]).splitlines()[0] == "Xcode 26.6", "unexpected Xcode")
    require(r.read("arch", ["/usr/bin/uname", "-m"]) == "arm64", "unexpected runner architecture")
    require(r.read("frozen-base", ["/usr/bin/git", "rev-parse", "HEAD"]) == FROZEN_BASE, "unexpected pinned source")
    staged = inspect(root, staged=root / "App/Resources/FighterPrivate")
    require(staged["compiledContentSHA256"] == ACTIVE_DIGEST and staged["requiredFiles"] == 539, "staged active asset pack")
    core_ok = exercise_core(r)
    spec, selected = write_project(root), expected_selectors(root)
    r.run("xcodegen", [xcodegen, "generate", "--spec", spec, "--project", root])
    derived = work / "derived"
    r.run("release-build-for-testing", ["/usr/bin/xcodebuild", "-project", root / "ShiftReminder.xcodeproj",
          "-scheme", "LiveGameplay", "-sdk", "iphonesimulator", "build-for-testing", "-configuration", "Release",
          "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived,
          *(x for x in CONTRACT if not x.startswith("L12_INTERNAL_PREVIEW_CONDITION=")),
          "L12_INTERNAL_PREVIEW_CONDITION=L12_INTERNAL_PREVIEW", "ENABLE_TESTABILITY=YES", "ARCHS=arm64"], timeout=2200)
    products = derived / "Build/Products"
    app = products / "Release-iphonesimulator/ShiftReminder.app"
    plans = list(products.glob("LiveGameplay_*.xctestrun"))
    require(len(plans) == 1, "unexpected live testplan count")
    verify_plan(plans[0], app)
    reference = installed_identity(root, app)
    source = rules.build_manifest(root)["fingerprint"]
    report("shared-build", workflowSHA=sha, frozenBase=FROZEN_BASE, resourceSHA256=ACTIVE_DIGEST,
           resourceCount=539, sourceFingerprint=source, executableSHA256=reference[0], networkRulesSHA256=reference[1])
    inventory = json.loads(r.read("simulator-inventory", ["/usr/bin/xcrun", "simctl", "list", "-j"]))
    runtimes = [x["identifier"] for x in inventory["runtimes"] if x.get("isAvailable") and x["version"] == "26.5" and ".iOS-" in x["identifier"]]
    models = [(x["name"], x["identifier"]) for x in inventory["devicetypes"]]
    phones = [item for item in models if item[0] == "iPhone 17 Pro Max"]
    pads = sorted((item for item in models if item[0].startswith("iPad")),
                  key=lambda item: (not item[0].startswith("iPad Pro 13-inch"), item))
    require(len(runtimes) == len(phones) == 1 and pads, "simulator device types unavailable")
    devices = {}
    for lane, model in (("iphone", phones[0]), ("ipad", pads[0])):
        try:
            devices[lane] = run_lane(r, lane, model, runtimes[0], plans[0], app, reference, selected)
        except Exception as exc:
            report(lane, success=False, failure=str(exc) if isinstance(exc, Failure) else type(exc).__name__)
    ok = core_ok and len(devices) == 2
    report("gameplayReleaseGate", success=ok, workflowSHA=sha, sourceFingerprint=source, resourceSHA256=ACTIVE_DIGEST,
           resourceCount=539, passedSelectors=selected if ok else [], devices=devices)
    return ok


if __name__ == "__main__":
    try:
        ok = main(*sys.argv[1:])
    except Exception as exc:
        report("gameplayReleaseGate", success=False, failure=str(exc) if isinstance(exc, Failure) else type(exc).__name__)
        ok = False
    sys.exit(0 if ok else 1)
