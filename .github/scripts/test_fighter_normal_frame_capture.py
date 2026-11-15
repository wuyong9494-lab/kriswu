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


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


def tiff(value=8, order=">"):
    return ((b"MM" if order == ">" else b"II") + struct.pack(order + "HIH", 42, 8, 1)
            + struct.pack(order + "HHI", 274, 3, 1) + struct.pack(order + "H", value) + b"\0\0"
            + struct.pack(order + "I", 0))


def xmp(value="8", *, attribute=False):
    field = ' t:Orientation="' + value + '"' if attribute else ""
    body = "" if attribute else "<t:Orientation>" + value + "</t:Orientation>"
    return (b"XML:com.adobe.xmp\0\0\0\0\0" +
            ('<r xmlns:t="http://ns.adobe.com/tiff/1.0/"' + field + '>' + body + '</r>').encode())


def png(width=4, height=2, color=64, orientation=None, xmp_packet=None, extra_chunks=()):
    metadata = (chunk(b"eXIf", tiff(orientation)) if orientation is not None else b"")
    if xmp_packet is not None: metadata += chunk(b"iTXt", xmp_packet)
    metadata += b"".join(chunk(kind, data) for kind, data in extra_chunks)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + metadata + chunk(b"IDAT", zlib.compress((b"\0" + bytes([color]) * width * 3) * height)) + chunk(b"IEND", b""))


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
            "width": 4, "height": 2, "elements": copy.deepcopy(elements)})
        raw = png(width=6, height=12, color=64 + index, orientation=8, xmp_packet=xmp())
        filename = label + ".png"; files[filename] = raw
        captures.append({"label": label, "file": filename, "phase": "capture-" + label, "ordinal": index + 1,
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "width": 6, "height": 12,
            "storedWidth": 6, "storedHeight": 12, "exifOrientation": 8,
            "displayWidth": 12, "displayHeight": 6, "displayToAXScale": 3,
            "orientationReader": "ImageIO CGImageSourceCopyPropertiesAtIndex",
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
        "normalPNGOrientationPolicy": m.PNG_ORIENTATION_POLICY,
        "normalPresentationInternals": {"status": "notObserved", **{key: None for key in
            ("normalFrames", "gameTick", "animationTick", "sourceLiveTick", "firstCommitCount", "presentationKickAttempts",
             "preparationReady", "sourceMusicReady")}}}
    report.update({key: False for key in ("observationsAndScreenshotsShareExactFrame", "xctestOutcomeIsProvidedByThisReport",
        "normalDrawableCountersVerified", "sourcePreparationSequenceVerifiedByUI", "frameOrTickProgressVerified",
        "offscreenCaptureUsed", "renderAPIsInvoked", "internalCombatStateInjected", "shadowSkillInvoked", "joystickInvoked",
        "pauseOrResumeInvoked", "otherCharacterPracticeInvoked", "audiblePlaybackVerified", "physicalDeviceVerified", "panguEquipmentActivated")})
    root_frame = {"x": 0, "y": 0, "width": 956, "height": 440}
    button = {"x": 20, "y": 80, "width": 218, "height": 60}
    other = {"x": 20, "y": 148, "width": 218, "height": 60}
    title = {"x": 40, "y": 90, "width": 55, "height": 21}
    pre = {"phase": "sun-touch-geometry", "uptime": 8.0, "snapshotSeconds": 0.25,
        "width": 956, "height": 440, "rootFrame": root_frame, "windowFrames": [root_frame], "sunTitleFrames": [title],
        "elements": {
            "duel.hero.ember": [{"label": "孙登", "value": "未选择", "enabled": True, "frame": button, "windowFrame": root_frame}],
            "duel.hero.liu": [{"label": "刘泉纬", "value": "已选择", "enabled": True, "frame": other, "windowFrame": root_frame}]}}
    report["observations"].insert(0, pre)
    for row in report["captures"]: row["observationIndex"] += 1
    report.update({"selectionTouchPolicy": "one-coordinate-touch-from-fresh-observed-geometry",
        "allowedDiagnosticCaptureLabels": list(m.DIAGNOSTIC_LABELS), "diagnosticsCountAsNormalPracticeFrames": False,
        "diagnosticCaptureErrors": [], "selectionTouch": {
            "identifier": "duel.hero.ember", "tapCount": 1, "invocationState": "returned",
            "intentPreparedAtUptime": 8.4, "observationIndex": 0, "rootFrame": root_frame,
            "windowFrame": root_frame, "buttonFrame": button, "targetFrame": title,
            "targetKind": "observed-sun-title-center", "pointInScreenCoordinates": {"x": 67.5, "y": 100.5},
            "offsetFromAppOrigin": {"x": 67.5, "y": 100.5}, "observationFinishedUptime": 8.25,
            "invokedAtUptime": 8.5, "returnedAtUptime": 8.75, "maximumObservationAgeAtInvocationSeconds": 2,
            "api": "XCUIApplication.coordinate(withNormalizedOffset:).withOffset(_:).tap()",
            "synthesizedEventTimeObserved": False, "internalSelectionStateInjected": False, "retryPerformed": False}})
    label = m.DIAGNOSTIC_LABELS[0]; raw = png(color=128); files[label + ".png"] = raw
    report["diagnosticCaptures"] = [{"label": label, "file": label + ".png", "phase": "sun-select-before-touch",
        "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "width": 4, "height": 2,
        "captureStartedUptime": 7.0, "captureFinishedUptime": 7.2,
        "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": True,
        "countsAsNormalPracticeFrame": False}]
    return invocation, report, files


def write_sidecars(directory, report, files):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / m.REPORT_FILE).write_text(json.dumps(report))
    for name, data in files.items():
        (directory / name).write_bytes(data)


class NormalFrameEvidenceTests(unittest.TestCase):
    def test_embedded_orientation_defines_display_axes_at_the_owned_screen_scale(self):
        observed = {"width": 4, "height": 2}
        for orientation in (1, 3, 6, 8):
            with self.subTest(orientation=orientation):
                width, height = (6, 12) if orientation in (6, 8) else (12, 6)
                raw = png(width=width, height=height, orientation=orientation,
                          xmp_packet=xmp(str(orientation), attribute=orientation == 6))
                original = bytes(raw)
                result = m.png_display_geometry(raw, observed)
                self.assertEqual((result["storedWidth"], result["storedHeight"]), (width, height))
                self.assertEqual((result["displayWidth"], result["displayHeight"]), (12, 6))
                self.assertEqual(result["exifOrientation"], orientation)
                self.assertEqual(result["xmpOrientation"], orientation)
                self.assertEqual(result["displayToAXScale"], 3)
                self.assertEqual(raw, original)
        self.assertEqual(m.tiff_orientation(tiff(8, "<")), 8)
        self.assertEqual(m.tiff_orientation(tiff(8, ">")), 8)

    def test_portrait_storage_requires_explicit_unambiguous_matching_metadata(self):
        cases = {
            "missing_exif": png(width=6, height=12, xmp_packet=xmp()),
            "no_axis_swap_authority": png(width=6, height=12, orientation=1),
            "mirrored_orientation": png(width=6, height=12, orientation=7),
            "conflicting_xmp": png(width=6, height=12, orientation=8, xmp_packet=xmp("6")),
            "duplicate_exif": png(width=6, height=12, orientation=8, extra_chunks=((b"eXIf", tiff()),)),
            "duplicate_xmp": png(width=6, height=12, orientation=8, xmp_packet=xmp(),
                                 extra_chunks=((b"iTXt", xmp()),)),
            "compressed_xmp": png(width=6, height=12, orientation=8,
                                  xmp_packet=xmp().replace(b"xmp\0\0\0", b"xmp\0\1\0", 1)),
            "duplicate_xmp_tag": png(width=6, height=12, orientation=8,
                xmp_packet=xmp().replace(b"</r>", b"<t:Orientation>8</t:Orientation></r>")),
            "xmp_entity": png(width=6, height=12, orientation=8,
                xmp_packet=xmp().replace(b"<r ", b'<!DOCTYPE r [<!ENTITY q "8">]><r ', 1)),
            "wrong_two_axis_scale": png(width=6, height=15, orientation=8),
        }
        for name, raw in cases.items():
            with self.subTest(case=name), self.assertRaises(ValueError):
                m.png_display_geometry(raw, {"width": 4, "height": 2})

    def test_tiff_orientation_rejects_truncated_escaping_or_ambiguous_ifd(self):
        original = tiff()
        changed = []
        for offset, value in ((2, b"\0+"), (4, struct.pack(">I", 1000)),
                              (8, struct.pack(">H", 65)), (12, struct.pack(">H", 4)),
                              (14, struct.pack(">I", 2)), (22, struct.pack(">I", 8))):
            raw = bytearray(original); raw[offset:offset + len(value)] = value; changed.append(bytes(raw))
        duplicate = original[:8] + struct.pack(">H", 2) + original[10:22] * 2 + b"\0" * 4
        changed.extend((original[:-1], original[:8], duplicate, b"Exif\0\0" + original, b"M" * 65537))
        for raw in changed:
            with self.subTest(length=len(raw)), self.assertRaises(ValueError): m.tiff_orientation(raw)

    def test_normal_capture_receipt_cannot_change_display_geometry_or_hide_capture_phase(self):
        invocation, report, files = fixtures()
        mutations = [
            {"storedWidth": 12}, {"displayHeight": 12}, {"exifOrientation": 6},
            {"displayToAXScale": 2}, {"phase": "sun-practice-ready"},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temp:
                changed = copy.deepcopy(report); changed["captures"][0].update(mutation)
                directory = Path(temp); write_sidecars(directory, changed, files)
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_ready_observation_without_a_saved_frame_remains_a_partial_ui_observation(self):
        invocation, report, files = fixtures()
        report.update(captures=[], flowCompleted=False, phase="capture-" + m.FRAME_LABELS[0],
                      failurePhase="capture-" + m.FRAME_LABELS[0])
        files = {name: raw for name, raw in files.items() if name.startswith(m.DIAGNOSTIC_LABELS[0])}
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, files)
            result = m.verify_sidecars(directory, invocation)
            self.assertTrue(result["uiVisibleReadinessObserved"])
            self.assertEqual(result["captureCount"], 0)
            self.assertFalse(result["flowCompleted"])
            self.assertFalse(result["xctestPassed"])
            self.assertEqual(result["normalPresentationInternals"], "notObserved")
            self.assertEqual(result["visualReview"], "PENDING")

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
        report.update({"captures": [], "observations": [], "flowCompleted": False, "phase": "launch", "failurePhase": None,
            "selectionTouch": None, "diagnosticCaptures": []})
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
            lambda r: r["observations"][2].update(uptime=11.0),
            lambda r: r["observations"][1]["elements"]["duel.name.1"][0].update(label="刘泉纬 · 盘古"),
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

    def test_touch_geometry_rejects_stale_overlapping_foreign_or_unobserved_points(self):
        invocation, report, files = fixtures()
        mutations = [
            lambda r: r["selectionTouch"].update(invokedAtUptime=10.5),
            lambda r: r["selectionTouch"].update(tapCount=2),
            lambda r: r["selectionTouch"]["pointInScreenCoordinates"].update(x=600),
            lambda r: r["selectionTouch"]["offsetFromAppOrigin"].update(x=66),
            lambda r: r["observations"][0]["elements"]["duel.hero.liu"][0]["frame"].update(y=80),
            lambda r: r["observations"][0]["elements"]["duel.hero.ember"].append(
                copy.deepcopy(r["observations"][0]["elements"]["duel.hero.ember"][0])),
            lambda r: r["selectionTouch"].update(targetKind="invented-coordinate"),
            lambda r: r["selectionTouch"].update(synthesizedEventTimeObserved=True),
        ]
        for index, change in enumerate(mutations):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temp:
                changed = copy.deepcopy(report); change(changed)
                directory = Path(temp); write_sidecars(directory, changed, files)
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_failure_diagnostic_is_preserved_but_never_counts_as_normal_practice(self):
        invocation, report, files = fixtures()
        report.update({"captures": [], "observations": report["observations"][:1], "flowCompleted": False,
            "phase": "sun-selected", "failurePhase": "sun-selected"})
        files = {name: raw for name, raw in files.items() if name.startswith(m.DIAGNOSTIC_LABELS[0])}
        label = m.DIAGNOSTIC_LABELS[1]; raw = png(width=2, height=4); files[label + ".png"] = raw
        report["diagnosticCaptures"].append({"label": label, "file": label + ".png", "phase": "sun-selected",
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "width": 2, "height": 4,
            "captureStartedUptime": 11, "captureFinishedUptime": 11.5,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": True,
            "countsAsNormalPracticeFrame": False})
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, files)
            result = m.verify_sidecars(directory, invocation)
            self.assertEqual(result["captureCount"], 0); self.assertEqual(result["diagnosticCaptureCount"], 2)
            self.assertFalse(result["flowCompleted"]); self.assertFalse(result["uiVisibleReadinessObserved"])
            self.assertFalse(result["diagnosticsCountAsNormalPracticeFrames"])
            self.assertEqual(result["diagnosticCaptures"][-1]["height"], 4)
            # A PNG already saved before a report-write failure remains a
            # success receipt; classifying it as unavailable is contradictory.
            report["diagnosticCaptureErrors"] = [{"label": label, "error": "normal-window-capture-unavailable"}]
            write_sidecars(directory, report, files)
            with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)
            report["diagnosticCaptureErrors"] = []
            report["diagnosticCaptures"][-1]["countsAsNormalPracticeFrame"] = True
            write_sidecars(directory, report, files)
            with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)

    def test_slow_intent_write_preserves_zero_calls_and_rejects_a_late_invocation(self):
        invocation, report, files = fixtures()
        report.update({"captures": [], "observations": report["observations"][:1], "flowCompleted": False,
            "phase": "sun-touch-geometry", "failurePhase": "sun-touch-geometry", "writtenAtUptime": 12})
        files = {name: raw for name, raw in files.items() if name.startswith(m.DIAGNOSTIC_LABELS[0])}
        touch = report["selectionTouch"]
        touch.update(tapCount=0, invocationState="intent", invokedAtUptime=None, returnedAtUptime=None)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, files)
            receipt = m.verify_sidecars(directory, invocation)["selectionTouch"]
            self.assertEqual(receipt["tapCount"], 0)
            self.assertFalse(receipt["invoked"]); self.assertFalse(receipt["returned"])
            for mutation in ({"tapCount": 1}, {"invocationState": "returned", "returnedAtUptime": 11},
                             {"tapCount": 1, "invocationState": "called", "invokedAtUptime": 11}):
                changed = copy.deepcopy(report); changed["selectionTouch"].update(mutation)
                write_sidecars(directory, changed, files)
                with self.assertRaises(ValueError): m.verify_sidecars(directory, invocation)
            # A call made while fresh may be interrupted before returning. Keep
            # its known call count, but do not promote it to a completed flow.
            touch.update(tapCount=1, invocationState="called", invokedAtUptime=8.5)
            write_sidecars(directory, report, files)
            receipt = m.verify_sidecars(directory, invocation)["selectionTouch"]
            self.assertTrue(receipt["invoked"]); self.assertFalse(receipt["returned"])

    def test_geometry_accepts_only_the_observed_button_center_when_title_is_absent(self):
        invocation, report, files = fixtures()
        report["observations"][0]["sunTitleFrames"] = []
        touch = report["selectionTouch"]
        touch.update(targetKind="observed-button-center", targetFrame=copy.deepcopy(touch["buttonFrame"]),
            pointInScreenCoordinates={"x": 129, "y": 110}, offsetFromAppOrigin={"x": 129, "y": 110})
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); write_sidecars(directory, report, files)
            result = m.verify_sidecars(directory, invocation)
            self.assertEqual(result["selectionTouch"]["targetKind"], "observed-button-center")
            self.assertEqual(result["selectionTouch"]["tapCount"], 1)
            self.assertFalse(result["selectionTouch"]["retryPerformed"])

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
