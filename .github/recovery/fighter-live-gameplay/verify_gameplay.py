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
from verify_active_native_build import (CONTRACT, FAILURE_SOURCES, KEY_NAMES, failed_test_receipt,
                                        native_child_environment, result_counts)
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
    "DuelLiveInputTests/testFreshWeaponTapStartsOnFirstPlayableFrameAgainstSun",
    "DuelOptionalResourceIsolationInstalledTests/testLocalMatchLoadsOnlySelectedPairFromBundledIndex",
    "DuelBoundedGzipTests/testTriadManifestPreparationRejectsChangedBytesAndCancellation",
    "DuelLocalMatchPreparationTests/testLatePreparationsCannotMountAfterBackgroundingOrExit",
    "DuelRecoveredCharacterInstalledTests/testLocalTriadEffectsPrepareOnlyForTheChosenPair",
    "DuelFighterCharacterContainerTests/testValidatedContainerRetainsTheOriginalJSONAndBinaryChunk",
    "DuelRecoveredCharacterInstalledTests/testErlangAudioChecksDiskChangesAndSuppliedProfilesAgainstTheInstalledPin",
    "DuelWeaponAssetTests/testArtworkCoordinatesConvertBetweenMountedViewsAndClearWhenWorldDetaches",
)
WHOLE_CLASSES = ("DuelSourceProjectedShadowRendererTests", "DuelDisplayedRigidBoundsTests",
                 "DuelMusicTests", "DuelLobbyMusicSelectionTests")
SITE_SOURCES = (
    "DuelRecoveredCharacterInstalledTests", "DuelSerpentMorphSourceTests", "DuelLiveInputTests",
    "DuelOptionalResourceIsolationTests", "DuelLocalWeaponProfileTests", "DuelBoundedGzipTests",
    "DuelLocalMatchPreparationTests", "DuelFighterCharacterContainerTests",
    "DuelWeaponAssetTests", "DuelWeaponAssetTests+LobbyFraming", *WHOLE_CLASSES,
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
    # Never copy process output, asset names, assertion operands or paths to CI.
    message = raw.casefold()
    phrases = {
        "compile-error": (".swift:", " error:"),
        "assertion": ("xctassert",), "unwrap": ("xctunwrap",),
        "launch": ("failed to launch",), "boot": ("failed to boot",),
        "install": ("failed to install",), "destination": ("ineligible destination",),
        "timeout": ("timed out",), "crash": ("crashed",),
        "command-error": ("xcodebuild: error:",),
    }
    return [key for key, parts in phrases.items() if all(part in message for part in parts)]


def selector_receipt(summary, tests, selected, raw=""):
    aliases = {alias: key for key in selected for alias in (key, key.split("/", 1)[1])}
    require(len(aliases) == 2 * len(selected), "ambiguous selected tests")
    states = {key: "missing" for key in selected}
    failures = []
    lines = {key: set() for key in selected}
    invalid_nodes = 0

    def lookup(value):
        return aliases.get(value.removesuffix("()")) if isinstance(value, str) else None

    def remember(key, detail):
        # Only a public XCTest filename belonging to this selector and an integer
        # source line may be emitted. Older summary records can omit a source URL.
        suite = key.split("/")[1]
        names = {suite + ".swift", FAILURE_SOURCES.get(suite)}
        names.update(name + ".swift" for name in SITE_SOURCES if name.startswith(suite + "+"))
        message = detail.get("failureText")
        if isinstance(message, str):
            pattern = r'(?<![\w.+-])([\w.+-]+\.swift):(\d{1,5})(?=\D|$)'
            for name, line in re.findall(pattern, message):
                if name in names and 1 <= int(line) <= 99999:
                    lines[key].add((name, int(line)))
        failures.append(dict(detail, testIdentifierString=key))

    def walk(nodes, owner=None):
        nonlocal invalid_nodes
        if not isinstance(nodes, list):
            invalid_nodes += 1
            return
        for node in nodes:
            if not isinstance(node, dict):
                invalid_nodes += 1
                continue
            key = owner
            if node.get("nodeType") == "Test Case":
                key = lookup(node.get("nodeIdentifier"))
                if key is None:
                    invalid_nodes += 1
                else:
                    actual = node.get("result")
                    status = {"Passed": "passed", "Failed": "failed", "Failure": "failed",
                              "Skipped": "skipped", "Expected Failure": "expected-failure"}.get(actual, "unknown") if isinstance(actual, str) else "unknown"
                    states[key] = status if states[key] == "missing" else "duplicate"
            if key and node.get("nodeType") == "Failure Message":
                remember(key, {"failureText": node.get("name")})
            walk(node.get("children", []), key)

    walk(tests.get("testNodes"))
    records = summary.get("testFailures", [])
    if not isinstance(records, list):
        records = []
        invalid_nodes += 1
    for row in records:
        if not isinstance(row, dict):
            invalid_nodes += 1
            continue
        # Xcode 26 returns a deprecated numeric testIdentifier alongside the
        # structured string. Only names from the reviewed selector set survive.
        key = next((key for field in ("testIdentifierString", "testIdentifier", "nodeIdentifier")
                    if (key := lookup(row.get(field)))), None)
        if key and row.get("targetName", key.split("/")[0]) == key.split("/")[0]:
            remember(key, row)
            if states[key] == "missing":
                states[key] = "failed-summary-only"
            elif states[key] not in ("failed", "duplicate"):
                states[key] = "conflicting"
        else:
            invalid_nodes += 1
    # xcodebuild includes the exact failing public source location even when
    # the xcresult summary has only failureText and a numeric identifier.
    for line in raw.splitlines():
        match = re.search(r": error: [-+]\[(?:[\w.]+\.)?(\w+) (test\w+)\]\s*:", line)
        if match:
            key = lookup("/".join(match.groups()))
            if key and states[key] in ("failed", "failed-summary-only", "conflicting", "duplicate"):
                remember(key, {"failureText": line})
    for key, state in states.items():
        if state == "failed" and not any(row["testIdentifierString"] == key for row in failures):
            remember(key, {})
    details = failed_test_receipt({"testFailures": failures}, {"testNodes": []}, selected)
    for item in details["failures"]:
        locations = lines[item["selector"]]
        if locations:
            item["locations"] = [{"file": name, "line": line} for name, line in sorted(locations)[:3]]
    counts = {name: summary.get(name) if type(summary.get(name)) is int and 0 <= summary[name] <= 1_000_000 else None
              for name in ("totalTestCount", "passedTests", "failedTests", "skippedTests")}
    return dict(selectorResults=states, unexpectedRecords=invalid_nodes, **counts, **details)


def read_result_object(r, lane, result, kind):
    try:
        value = json.loads(r.read(lane + "-result-" + kind, ["/usr/bin/xcrun", "xcresulttool", "get",
                           "test-results", kind, "--path", result]))
    except (Failure, ValueError, OSError):
        return None
    return value if isinstance(value, dict) else None


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
                if check:
                    raise Failure(name + " timed out") from None
                # xcodebuild may already have written a usable partial result.
                status = 124
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


def movement_observation(raw):
    fields = {"startX", "endX", "startHP", "endHP", "startOpponentX", "endOpponentX", "figureDX", "windowW",
              "windowH", "rightCX", "rightCY", "pressCallMs", "terminal", "paused", "shapeValid"}
    for line in raw.splitlines():
        _, sep, rest = line.partition("XU_PREVIEW_MOVEMENT ")
        if not sep:
            continue
        try:
            values, _ = json.JSONDecoder().raw_decode(rest.lstrip()[:1024])
        except ValueError:
            continue
        if (isinstance(values, dict) and set(values) == fields
                and all(type(n) is int and -10000 <= n <= 99999 for n in values.values())
                and all(values[key] in (0, 1) for key in ("terminal", "paused", "shapeValid"))):
            return values


def get_measurements(raw, marker="RIFT_LIVE", validate=None):
    if validate is None:
        validate = measurement_shape
    for line in raw.splitlines():
        _, sep, rest = line.partition(marker + " ")
        if not sep:
            continue
        try:
            data, _ = json.JSONDecoder().raw_decode(rest.lstrip()[:2048])
        except ValueError:
            continue
        if validate(data):
            return data


def measurement_shape(data):
    return (isinstance(data, dict) and set(data) == MEASUREMENTS
            and all(type(v) in (int, float) and 0 <= v <= 1_000_000 and math.isfinite(v) for v in data.values())
            and all(type(data[key]) is int for key in MEASUREMENTS - {"frameP95Ms"}))


def valid_measurements(data):
    return (measurement_shape(data) and data["hpBefore"] > data["hpAfter"] and data["weaponPresses"] > 0
            and data["frameP95Ms"] > 0 and 0 <= data["slowFrames"] <= data["frameSamples"] and data["frameSamples"] >= 2)


def valid_practice_movement(data):
    fields = {"modelDelta", "figureDeltaPt", "relativeToControlDeltaPt", "windowWidthPt",
              "windowHeightPt", "requestedHoldMs", "pressCallMs"}
    if not isinstance(data, dict) or set(data) != fields:
        return False
    if not all(type(v) in (int, float) and 0 <= v <= 1_500_000 and math.isfinite(v) for v in data.values()):
        return False
    return (type(data["modelDelta"]) is int and 96 <= data["modelDelta"] <= 8600
            and data["figureDeltaPt"] >= 5 and data["relativeToControlDeltaPt"] >= 5
            and 0 < data["windowHeightPt"] < data["windowWidthPt"]
            and type(data["requestedHoldMs"]) is int and data["requestedHoldMs"] == 380
            and type(data["pressCallMs"]) is int)


def read_attached_measurements(r, lane, result, selector=LIVE, marker="RIFT_LIVE", validate=None):
    if validate is None:
        validate = measurement_shape
    # Read only named JSON metrics attached to the specified test.
    category = "" if selector == LIVE else "-practice"
    directory = r.work / (lane + category + "-attachments")
    directory.mkdir()
    short = selector.split("/", 1)[1] + "()"
    r.run(lane + category + "-export-metrics", ["/usr/bin/xcrun", "xcresulttool", "export", "attachments",
          "--test-id", short, "--path", result, "--output-path", directory], timeout=120)
    manifest = directory / "manifest.json"
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 1_000_000:
        return None
    rows = json.loads(manifest.read_bytes())
    if not isinstance(rows, list):
        return None
    for row in rows:
        if not isinstance(row, dict) or row.get("testIdentifier") not in (short, selector + "()"):
            continue
        attachments = row.get("attachments")
        if not isinstance(attachments, list):
            continue
        for attachment in attachments:
            if not isinstance(attachment, dict):
                continue
            name = attachment.get("suggestedHumanReadableName")
            file = attachment.get("exportedFileName")
            if not isinstance(name, str) or not re.fullmatch(re.escape(marker) + r"(?:[._-][a-zA-Z0-9._-]{1,180})?", name):
                continue
            if not isinstance(file, str) or not re.fullmatch(r"[\w.-]{1,250}", file) or file in (".", ".."):
                continue
            path = directory / file
            if path.is_symlink() or not path.is_file() or path.stat().st_size > 2048:
                continue
            try:
                data = json.loads(path.read_bytes())
            except (ValueError, UnicodeError):
                continue
            if validate(data):
                return data


def run_lane(r, lane, device, runtime, plan, app, reference, selected):
    sim = ["/usr/bin/xcrun", "simctl"]
    model, device_type = device
    phase = "create"
    has_results = False
    udid = None
    try:
        udid = str(uuid.UUID(r.read(lane + "-create", [*sim, "create", "Rift live " + lane, device_type, runtime]))).upper()
        phase = "boot"
        r.run(lane + "-boot", [*sim, "boot", udid])
        r.run(lane + "-bootstatus", [*sim, "bootstatus", udid], timeout=600)
        phase = "install"
        r.run(lane + "-install", [*sim, "install", udid, app], timeout=180)

        def check_installed(tag):
            path = r.read(lane + tag, [*sim, "get_app_container", udid, BUNDLE, "app"])
            require(installed_identity(r.root, Path(path)) == reference, lane + " installed app differs")

        phase = "installed-before"
        check_installed("-before")
        phase = "run-xctest"
        result = r.work / (lane + ".xcresult")
        status, raw = r.run(lane + "-tests", ["/usr/bin/xcodebuild", "test-without-building", "-xctestrun", plan,
                            "-destination", "id=" + udid, "-parallel-testing-enabled", "NO", "-resultBundlePath", result,
                            *("-only-testing:" + key for key in selected)], timeout=1500, check=False)
        phase = "read-xcresult"
        movement = movement_observation(raw)
        if movement is not None:
            report(lane + "-xu-movement", selector=PRACTICE, movement=movement)
        if not result.is_dir():
            has_results = True
            report(lane + "-results", exitCode=status, summaryAvailable=False, testsAvailable=False,
                   diagnostics=diagnostic(raw), **selector_receipt({}, {}, selected))
            report(lane + "-live-ui", selector=LIVE, selectorResult="missing", metrics=get_measurements(raw))
            raise Failure(lane + " test result missing")
        summary = read_result_object(r, lane, result, "summary")
        tests = read_result_object(r, lane, result, "tests")
        receipt = selector_receipt(summary or {}, tests or {}, selected, raw)
        report(lane + "-results", simulator=model, exitCode=status, summaryAvailable=summary is not None,
               testsAvailable=tests is not None, **receipt)
        has_results = True
        phase = "live-metrics"
        # This is a real UI measurement independently of unrelated hosted tests.
        # It never grants a pass to a missing, failed or skipped selector.
        measures = get_measurements(raw)
        if measures is None:
            try:
                measures = read_attached_measurements(r, lane, result)
            except (Failure, OSError, ValueError):
                pass
        report(lane + "-live-ui", selector=LIVE, selectorResult=receipt["selectorResults"][LIVE], metrics=measures)
        # Older reviewed test sources predate the separate practice movement receipt.
        practice_test = r.root / "Tests/ArenaFlowTests/DuelXuXiaoPracticeFlowTests.swift"
        practice_required = '"RIFT_PRACTICE"' in practice_test.read_text()
        practice = None
        if practice_required:
            practice = get_measurements(raw, "RIFT_PRACTICE", valid_practice_movement)
            if practice is None:
                try:
                    practice = read_attached_measurements(r, lane, result, PRACTICE, "RIFT_PRACTICE", valid_practice_movement)
                except (Failure, OSError, ValueError):
                    pass
            report(lane + "-practice-ui", selector=PRACTICE, selectorResult=receipt["selectorResults"][PRACTICE], movement=practice)
        phase = "verify-xcresult"
        require(summary is not None and tests is not None, lane + " test results unreadable")
        require(status == 0 and summary.get("result") == "Passed", lane + " native tests failed")
        require(not receipt["unexpectedRecords"] and not receipt["identifiedFailures"] and
                all(state == "passed" for state in receipt["selectorResults"].values()), lane + " incomplete test results")
        count = result_counts(summary, tests, selected)
        require(valid_measurements(measures), lane + " live metrics missing or invalid")
        require(not practice_required or practice is not None, lane + " practice movement missing or invalid")
        phase = "installed-after"
        check_installed("-after")
        info = dict(model=model, passed=count, metrics=measures,
                    slowFramePercent=round(100 * measures["slowFrames"] / measures["frameSamples"], 2))
        if practice is not None:
            info["practiceMovement"] = practice
        report(lane, **info)
        return info
    except Exception as exc:
        if not has_results:
            report(lane + "-results", summaryAvailable=False, testsAvailable=False, **selector_receipt({}, {}, selected))
            report(lane + "-live-ui", selector=LIVE, selectorResult="missing", metrics=None)
        report(lane + "-error", phase=phase, errorClass=type(exc).__name__)
        raise
    finally:
        if udid:
            for command in ("shutdown", "delete"):
                try:
                    r.run(lane + "-" + command, [*sim, command, udid], check=False)
                except (Failure, OSError):
                    report(lane + "-cleanup", command=command, warning=True)


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
