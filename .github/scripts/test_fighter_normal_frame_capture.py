#!/usr/bin/env python3
"""Bounded offline regressions for the new normal-window evidence path.

These tests exercise loss/corruption/identity/count risks without launching an
Apple simulator, staging game assets or repeating historical XCTest methods.
"""
import copy
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

SPEC = importlib.util.spec_from_file_location("normal_capture", Path(__file__).with_name("fighter_normal_frame_capture.py"))
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def png(width=4, height=2, color=64):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + bytes([color]) * width * 3) * height)) + chunk(b"IEND", b""))


def fixtures():
    invocation = {"sourceSHA": "a" * 40, "runID": "42", "runAttempt": "1",
        "nonce": "01234567-89ab-4def-8123-456789abcdef", "simulatorUDID": "12345678-ABCD-4EF0-8123-456789ABCDEF",
        "runnerBundleIdentifier": "com.example.runner", "testBundleIdentifier": "com.example.tests",
        "targetAppBundleIdentifier": "com.kriswu.shiftreminder", "selector": m.SELECTOR}
    invocation["launchEnvironment"] = dict(zip(m.CAPTURE_ENV_KEYS, (invocation["sourceSHA"], "42", "1",
        invocation["nonce"], invocation["simulatorUDID"])))
    identity = {key: invocation[key] for key in ("sourceSHA", "runID", "runAttempt", "nonce", "runnerBundleIdentifier",
        "testBundleIdentifier", "targetAppBundleIdentifier", "launchEnvironment")}
    identity.update({"expectedSimulatorUDID": invocation["simulatorUDID"], "actualSimulatorUDID": invocation["simulatorUDID"]})
    elements = {key: [{"label": "", "enabled": True}] for key in
        ("duel.pause", "duel.stats.0", "duel.stats.1", "duel.name.0", "duel.name.1", "duel.control.joystick", "duel.control.weapon")}
    elements["duel.name.0"][0]["label"] = "孙登 · 黑色双刀"
    elements["duel.name.1"][0]["label"] = "刘泉纬 · 双锤"
    elements["duel.control.joystick"][0]["value"] = "居中"
    elements["duel.control.weapon"][0]["value"] = "可施放"
    observations, captures, files = [], [], {}
    for index, (label, phase, uptime) in enumerate(zip(m.FRAME_LABELS, ("sun-practice-ready", "sun-practice-later"), (10.0, 12.0))):
        observations.append({"phase": phase, "uptime": uptime, "snapshotSeconds": 0.25,
            "width": 956, "height": 440, "elements": copy.deepcopy(elements)})
        raw = png(color=64 + index); filename = label + ".png"; files[filename] = raw
        captures.append({"label": label, "file": filename, "phase": phase, "ordinal": index + 1,
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "width": 4, "height": 2,
            "captureStartedUptime": uptime + 0.5, "captureFinishedUptime": uptime + 0.75,
            "observationIndex": index, "observationFinishedUptime": uptime + 0.25,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": True})
    report = {"schema": m.REPORT_SCHEMA, "selector": m.SELECTOR, "identity": identity,
        "expectedReleaseSHA256": m.RELEASE_SHA, "launchArguments": ["-demo", "-screen", "fighter"],
        "sidecarDirectory": m.SIDECAR_DIRECTORY, "reportFile": m.REPORT_FILE, "expectedCaptureLabels": list(m.FRAME_LABELS),
        "phase": "two-normal-window-images-saved", "flowCompleted": True, "failurePhase": None,
        "observations": observations, "captures": captures, "writtenAtUptime": 13,
        "minimumSecondsBetweenCaptureOneEndAndLaterObservationStart": 1,
        "secondObservationWaitBudgetSeconds": 4, "screenshotsRequireVisualReview": True, "visualReview": "PENDING",
        "normalPresentationInternals": {"status": "notObserved", **{key: None for key in
            ("normalFrames", "gameTick", "animationTick", "sourceLiveTick", "firstCommitCount", "presentationKickAttempts",
             "preparationReady", "sourceMusicReady")}}}
    report.update({key: False for key in ("observationsAndScreenshotsShareExactFrame", "xctestOutcomeIsProvidedByThisReport",
        "normalDrawableCountersVerified", "sourcePreparationSequenceVerifiedByUI", "frameOrTickProgressVerified",
        "offscreenCaptureUsed", "renderAPIsInvoked", "internalCombatStateInjected", "shadowSkillInvoked", "joystickInvoked",
        "pauseOrResumeInvoked", "otherCharacterPracticeInvoked", "audiblePlaybackVerified", "physicalDeviceVerified", "panguEquipmentActivated")})
    return invocation, report, files


def write_sidecars(directory, report, files):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / m.REPORT_FILE).write_text(json.dumps(report))
    for name, data in files.items():
        (directory / name).write_bytes(data)


class NormalFrameEvidenceTests(unittest.TestCase):
    def test_originals_work_without_an_xcresult_and_never_claim_test_or_visual_pass(self):
        invocation, report, files = fixtures()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, files)
            result = m.verify_sidecars(directory, invocation)
            self.assertEqual(result["captureCount"], 2)
            self.assertTrue(result["flowCompleted"])
            self.assertFalse(result["xctestPassed"])
            self.assertEqual(result["visualReview"], "PENDING")
            self.assertEqual(result["normalPresentationInternals"], "notObserved")
            self.assertEqual(result["captures"][0]["sha256"], hashlib.sha256(files[m.FRAME_LABELS[0] + ".png"]).hexdigest())

    def test_partial_report_is_preserved_but_cannot_become_a_completed_capture(self):
        invocation, report, _ = fixtures()
        report.update({"captures": [], "observations": [], "flowCompleted": False, "phase": "launch", "failurePhase": None})
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, {})
            receipt = m.verify_sidecars(directory, invocation)
            self.assertFalse(receipt["flowCompleted"]); self.assertEqual(receipt["captureCount"], 0)
            report["flowCompleted"] = True; write_sidecars(directory, report, {})
            with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_swapped_source_run_nonce_simulator_or_runner_cannot_reuse_old_images(self):
        invocation, report, files = fixtures()
        for field in ("sourceSHA", "runID", "runAttempt", "nonce", "actualSimulatorUDID", "runnerBundleIdentifier", "testBundleIdentifier"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temp:
                changed = copy.deepcopy(report); changed["identity"][field] = "foreign"
                directory = Path(temp); write_sidecars(directory, changed, files)
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_truncated_corrupt_trailing_or_unindexed_png_bytes_are_rejected(self):
        raw = png()
        for changed in (raw[:-4], raw + b"tail", raw[:30] + bytes([raw[30] ^ 1]) + raw[31:]):
            with self.subTest(length=len(changed)), self.assertRaises(ValueError): m.png_dimensions(changed)
        invocation, report, files = fixtures()
        for kind in ("wrong_hash", "extra_file", "symlink"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp); changed = copy.deepcopy(report); originals = dict(files)
                if kind == "wrong_hash": originals[m.FRAME_LABELS[0] + ".png"] = png(color=99)
                write_sidecars(directory, changed, originals)
                if kind == "extra_file": (directory / "unindexed.png").write_bytes(raw)
                if kind == "symlink":
                    target = directory / (m.FRAME_LABELS[0] + ".png"); target.unlink()
                    target.symlink_to(directory / (m.FRAME_LABELS[1] + ".png"))
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_timing_readiness_or_unobserved_internal_claims_cannot_be_forged(self):
        invocation, report, files = fixtures()
        mutations = [
            lambda r: r.update(frameOrTickProgressVerified=True),
            lambda r: r["normalPresentationInternals"].update(normalFrames=2),
            lambda r: r["observations"][1].update(uptime=11.0),
            lambda r: r["observations"][0]["elements"]["duel.name.1"][0].update(label="刘泉纬 · 盘古"),
            lambda r: r["captures"][0].update(observationIndex=True),
            lambda r: r["captures"][1].update(ordinal=1),
            lambda r: r.update(writtenAtUptime=9),
        ]
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temp:
                changed = copy.deepcopy(report); mutation(changed)
                directory = Path(temp); write_sidecars(directory, changed, files)
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_structured_results_reject_skips_duplicates_old_methods_and_wrong_devices(self):
        device = {"udid": "123", "name": "owned"}
        summary = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "result": "Passed",
            "devicesAndConfigurations": [{"passedTests": 1, "failedTests": 0, "skippedTests": 0,
                "device": {"deviceId": "123", "deviceName": "owned", "modelName": "iPhone 17 Pro Max", "platform": "iOS Simulator"}}]}
        tests = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": m.CLASS_NAME + "/" + m.METHOD_NAME + "()", "result": "Passed"}]}
        m.verify_results(summary, tests, device)
        for kind in ("skip", "duplicate", "old_method", "device", "bool_count"):
            with self.subTest(kind=kind):
                s, t = copy.deepcopy(summary), copy.deepcopy(tests)
                if kind == "skip": s.update(passedTests=0, skippedTests=1)
                if kind == "duplicate": t["testNodes"].append(copy.deepcopy(t["testNodes"][0]))
                if kind == "old_method": t["testNodes"][0]["nodeIdentifier"] = "DuelSharedRootVisualCaptureTests/old()"
                if kind == "device": s["devicesAndConfigurations"][0]["device"]["deviceId"] = "other"
                if kind == "bool_count": s["passedTests"] = True
                with self.assertRaises(ValueError): m.verify_results(s, t, device)

    def test_invocation_environment_persists_in_v1_and_v2_plists(self):
        for version in (1, 2):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp); products = directory / "derived/Build/Products"; products.mkdir(parents=True)
                target = {"BlueprintName": "ArenaFlowTests", "IsUITestBundle": True, "EnvironmentVariables": {"EXISTING": "kept"}}
                value = ({"ArenaFlowTests": target, "__xctestrun_metadata__": {"FormatVersion": 1}} if version == 1 else
                         {"TestConfigurations": [{"TestTargets": [target]}], "__xctestrun_metadata__": {"FormatVersion": 2}})
                source = products / "sample.xctestrun"; source.write_bytes(plistlib.dumps(value))
                (directory / "xctestrun-path.txt").write_text(str(source))
                built = {"compiledXctestrunSHA256": m.digest(source), "runner": {"bundleIdentifier": "runner"},
                    "test": {"bundleIdentifier": "test"}, "app": {"bundleIdentifier": "com.kriswu.shiftreminder"}}
                (directory / "compiled-bundles.json").write_text(json.dumps(built))
                with patch.object(m, "work", return_value=directory), patch.dict(os.environ,
                        {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "1"}):
                    output = m.configure_invocation({"udid": "12345678-ABCD-4EF0-8123-456789ABCDEF"})
                result = plistlib.loads(output.read_bytes()); changed = m.mutable_test_targets(result)[0][1]
                self.assertEqual(changed["OnlyTestIdentifiers"], [m.CLASS_NAME + "/" + m.METHOD_NAME])
                self.assertEqual(changed["EnvironmentVariables"]["EXISTING"], "kept")
                self.assertEqual(changed["EnvironmentVariables"]["FIGHTER_CAPTURE_SOURCE_SHA"], "a" * 40)
                self.assertNotIn("FIGHTER_CAPTURE_SOURCE_SHA", m.mutable_test_targets(plistlib.loads(source.read_bytes()))[0][1]["EnvironmentVariables"])

    def test_recovery_preserves_originals_after_timeout_without_inventing_xctest_pass(self):
        invocation, report, files = fixtures()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); owned = directory / "work"; owned.mkdir()
            data = directory / "container"; original = data / "Documents" / m.SIDECAR_DIRECTORY / invocation["nonce"]
            write_sidecars(original, report, files)
            built = {"runner": {"bundleIdentifier": invocation["runnerBundleIdentifier"]},
                "test": {"bundleIdentifier": invocation["testBundleIdentifier"]},
                "app": {"bundleIdentifier": invocation["targetAppBundleIdentifier"]}, "testBundleRelativePath": "PlugIns/ArenaFlowTests.xctest"}
            (owned / "invocation.json").write_text(json.dumps(invocation)); (owned / "compiled-bundles.json").write_text(json.dumps(built))
            (owned / "ui-invoked.json").write_text('{}'); (owned / "ui-process.json").write_text('{"exitCode":124}')
            device = {"udid": invocation["simulatorUDID"]}
            bundles = [(built["runner"], {}), (built["test"], {}), (built["app"], {"ArenaCommitSHA": invocation["sourceSHA"], "FighterAssetReleaseSHA256": m.RELEASE_SHA})]
            with patch.object(m, "work", return_value=owned), patch.object(m, "identity"), patch.object(m, "run_logged", return_value=1), \
                    patch.object(m, "owned_simulator", return_value=(device, {})), patch.object(m, "simulator_container", side_effect=[directory, directory, data]), \
                    patch.object(m, "bundle_identity", side_effect=bundles), patch.dict(os.environ,
                        {"GITHUB_SHA": invocation["sourceSHA"], "GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "1"}):
                m.recover()
            self.assertTrue((owned / "sidecars-ok.txt").is_file())
            self.assertFalse((owned / "ui-ok.txt").exists())
            self.assertEqual(json.loads((owned / "ui-process.json").read_text())["exitCode"], 124)
            for name, raw in files.items(): self.assertEqual((owned / "ui-sidecars" / name).read_bytes(), raw)
            self.assertFalse(json.loads((owned / "sidecar-verification.json").read_text())["xctestPassed"])

    def test_runtime_gate_scans_full_log_and_rejects_other_invocation_times(self):
        start = datetime.datetime(2026, 11, 15, 6, 0, tzinfo=datetime.timezone.utc)
        end = start + datetime.timedelta(seconds=10)
        device = {"name": "owned", "udid": "12345678-ABCD-4EF0-8123-456789ABCDEF", "physicalDevice": False}
        events = [{"processImagePath": "/App/ShiftReminder.app/ShiftReminder", "timestamp": start.isoformat(),
                   "eventMessage": "frame started"},
                  {"processImagePath": "/App/ShiftReminder.app/ShiftReminder", "timestamp": end.isoformat(),
                   "eventMessage": m.METAL_DIAGNOSTICS["doublePresent"]}]
        with tempfile.TemporaryDirectory() as temp, patch.object(m, "simulator_name", return_value="owned"):
            path = Path(temp) / "runtime.log"; path.write_text(json.dumps(events))
            result = m.verify_runtime_log(path, collection_code=0, device=device, started=start, finished=end)
            self.assertFalse(result["knownDiagnosticsAbsent"]); self.assertEqual(result["knownDiagnosticCount"], 1)
            events[-1]["timestamp"] = (end + datetime.timedelta(minutes=1)).isoformat(); path.write_text(json.dumps(events))
            with self.assertRaises(ValueError): m.verify_runtime_log(path, collection_code=0, device=device, started=start, finished=end)

    def test_installed_code_identity_includes_debug_dylib_not_only_launcher_stub(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = Path(temp) / "ShiftReminder.app"; bundle.mkdir()
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.kriswu.shiftreminder",
                "CFBundleExecutable": "ShiftReminder"}))
            (bundle / "ShiftReminder").write_bytes(b"unchanged launcher stub")
            dylib = bundle / "ShiftReminder.debug.dylib"; dylib.write_bytes(b"compiled actual Swift code")
            built, _ = m.bundle_identity(bundle)
            dylib.write_bytes(b"different stale Swift code")
            installed, _ = m.bundle_identity(bundle)
            self.assertEqual(built["executableSHA256"], installed["executableSHA256"])
            self.assertNotEqual(built, installed)
            dylib.unlink()
            without, _ = m.bundle_identity(bundle)
            self.assertIsNone(without["debugDylib"])
            self.assertNotEqual(built, without)

    def test_failed_sealing_cleans_resources_but_keeps_the_only_original_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); owned = root / "work"; owned.mkdir()
            sidecars = owned / "ui-sidecars"; sidecars.mkdir(); original = sidecars / "original.png"; original.write_bytes(png())
            media = root / "App/Resources/FighterPrivate"; media.mkdir(parents=True); (media / "private.bin").write_bytes(b"private")
            products = owned / "derived"; products.mkdir(); (products / "build.bin").write_bytes(b"build")
            with patch.object(m, "ROOT", root), patch.object(m, "work", return_value=owned), \
                    patch.object(m, "identity"), patch.object(m, "public_summary", return_value={}):
                with self.assertRaises(m.PhaseFailure): m.cleanup()
            self.assertEqual(original.read_bytes(), png())
            self.assertFalse(media.exists()); self.assertFalse(products.exists())
            summary = json.loads((owned / "public-summary.json").read_text())
            self.assertFalse(summary["cleanupComplete"])
            self.assertFalse(summary["diagnosticsSealed"])
            self.assertTrue(summary["unsealedOriginalsRetainedPrivately"])

    def test_source_event_cannot_reselect_prior_run_or_dispatch(self):
        sha = "a" * 40
        env = {"GITHUB_SHA": sha, "GITHUB_REPOSITORY": m.REPOSITORY, "GITHUB_REF": m.BRANCH,
            "GITHUB_WORKFLOW_REF": m.REPOSITORY + "/" + m.WORKFLOW + "@" + m.BRANCH,
            "GITHUB_WORKFLOW_SHA": sha, "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "42", "GITHUB_EVENT_NAME": "push"}
        event = {"repository": {"full_name": m.REPOSITORY}, "ref": m.BRANCH, "head_commit": {"id": sha, "message": m.COMMIT_MESSAGE}}
        m.validate_event(env, event, sha)
        for key, value in (("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_EVENT_NAME", "workflow_dispatch"), ("GITHUB_REF", "refs/heads/main")):
            with self.subTest(key=key), self.assertRaises(ValueError): m.validate_event(dict(env, **{key: value}), event, sha)
        event["head_commit"]["message"] = "Verify first-submit preparation and APK signer continuation 20261115"
        with self.assertRaises(ValueError): m.validate_event(env, event, sha)


if __name__ == "__main__":
    unittest.main()
