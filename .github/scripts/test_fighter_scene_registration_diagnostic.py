#!/usr/bin/env python3
"""First-run offline checks for the new isolated diagnostic entry only.

All process, result and PNG fixtures below are synthetic gate inputs. They do
not execute Apple code, decode original media, acquire keys or prove pixels.
"""
import ast
import copy
import datetime
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import sys
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch
import zlib


HELPER = Path(__file__).with_name("fighter_scene_registration_diagnostic.py")
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("review_scene_registration_diagnostic", HELPER)
entry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(entry)
ENV = {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "a" * 40}
DEVICE = {"udid": "12345678-1234-1234-1234-123456789ABC", "name": "Fighter scene registration diagnostic 123 attempt 1",
          "physicalDevice": False}
START = datetime.datetime(2026, 11, 15, 10, 0, 0, tzinfo=datetime.timezone.utc)
END = START + datetime.timedelta(seconds=20)


def dump(path, value):
    path.write_text(json.dumps(value))


def results():
    return ({"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0, "result": "Passed",
             "devicesAndConfigurations": [{"device": {"deviceId": DEVICE["udid"], "deviceName": DEVICE["name"],
                "modelName": "iPhone 17 Pro Max", "platform": "iOS Simulator"},
                "passedTests": 1, "failedTests": 0, "skippedTests": 0}]},
            {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": entry.SELECTOR + "()", "result": "Passed"}]})


def png_fixture():
    def chunk(kind, raw):
        return struct.pack(">I", len(raw)) + kind + raw + struct.pack(">I", zlib.crc32(kind + raw))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 956, 440, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\0\0\0\xff" * 956) * 440)) + chunk(b"IEND", b""))


def report_fixture(images, submitted_after=0, first_projector_available=False):
    matrix = [1.0 if i % 5 == 0 else 0.0 for i in range(16)]
    last_tick = None if submitted_after == 0 else 0
    encoded = {"available": True, "tick": 0, "aspect": 956 / 440,
        "sourceCameraPosition": [0.0, 1.0, 1.0], "sourceView": matrix, "sourceProjection": matrix,
        "sourceShadowMatrix": matrix, "casterCount": 2, "triangleCount": 12, "factors": [1.0, 1.0]}
    fresh = {"created": True, "testStrongReferencePresent": True, "distinctFromActiveRenderer": True,
        "sameDevice": True, "sameScene": True, "samePointOfView": True, "delegateAbsent": True,
        "usesReverseZ": False, "autoenablesDefaultLighting": False, "isPlaying": False,
        "renderCalls": 0, "prepareCalls": 0, "snapshotCalls": 0}
    captures, samples = [], []
    for i, label in enumerate(entry.FRAME_LABELS):
        base = {"label": label, "frame": 0, "animationTick": 0, "sourceLiveTick": 0,
            "rendererRoute": "surface.captureFrame", "sourceProjectorInstalled": entry.CAPTURE_PROJECTOR_STATES[i],
            "projectorEncodedForCapture": entry.CAPTURE_PROJECTOR_STATES[i], "submittedPackets": 0,
            "activeSceneRebindCallsSoFar": entry.CAPTURE_REBIND_COUNTS[i],
            "freshRendererCreationCallsSoFar": entry.CAPTURE_FRESH_COUNTS[i], "freshAssociationCallsSoFar": entry.CAPTURE_FRESH_COUNTS[i],
            "surfaceSubmittedFrames": submitted_after, "surfaceLastSubmittedTick": last_tick,
            "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": 4}
        captures.append(dict(base, isolation=entry.CAPTURE_ISOLATION[i], pngSHA256=images[label]["sha256"],
            bytes=images[label]["bytes"], width=956, height=440, pixelsRequireReview=True, simulationAndModelCameraUnchanged=True))
        samples.append(dict(base, displayLinkCallbacks=0, sourceIntroActive=True, sourceStance="firstBirth", sourceStanceTick=0,
            weaponReady=False, branchesReady=False, fighters=[{"index": 0, "hero": "ember", "health": 1000},
                {"index": 1, "hero": "liu", "health": 1000}], sourceEffectIDs=[],
            sameActiveSurface=True, sameActiveRenderer=True, sameScene=True, samePointOfView=True,
            rendererUsesReverseZ=False, rendererAutoenablesDefaultLighting=False, rendererIsPlaying=False,
            camera={"modelWorldTransform": matrix, "presentationWorldTransform": matrix, "metalProjection": matrix,
                "model": {"exists": True, "fieldOfView": 24.0, "categoryMask": -1}, "presentation": {"exists": True}},
            lights=[{"name": "synthetic-light", "castsShadow": True}],
            sceneInventory=[{"name": "synthetic-root", "geometries": 0}],
            viewport={"pointsWidth": 956.0, "pointsHeight": 440.0, "captureWidth": 956, "captureHeight": 440,
                "drawableWidth": 2868.0, "drawableHeight": 1320.0, "viewScale": 3.0, "surfaceScale": 3.0},
            rendererFailure="", surfaceFailure="", sourcePreparationFailure="",
            modelObjectIdentityUnchanged=True, simulationInvariant=True,
            projectorLastFrame=copy.deepcopy(encoded) if i > 0 or first_projector_available else {"available": False},
            freshRenderer=copy.deepcopy(fresh) if i == 3 else {"created": False, "testStrongReferencePresent": False}))
    common = {"calls": 1, "sameActiveRendererAfter": True, "sameSceneAfter": True,
        "samePointOfViewAfter": True, "sameOriginalProjectorAfter": True}
    operations = [dict(common, order=1, operation="rebind-active-scene", beforeCaptureLabel=entry.FRAME_LABELS[1],
            afterCaptureLabel=entry.FRAME_LABELS[2], seconds=0.25, nilSceneObserved=True),
        dict(common, order=2, operation="associate-fresh-renderer", beforeCaptureLabel=entry.FRAME_LABELS[2],
            afterCaptureLabel=entry.FRAME_LABELS[3], seconds=0.5, creationCalls=1, freshRenderer=copy.deepcopy(fresh))]
    return {"schema": entry.REPORT_SCHEMA, "schemaVersion": 1, "scope": entry.SCOPE, "releaseSHA256": entry.RELEASE_SHA,
        "diagnosticCompleted": True, "lastPhase": "diagnostic-completed-pixels-pending", "elapsedSeconds": 1.0,
        "timings": [{"phase": "rebind-active-scene-once", "seconds": 0.25},
                    {"phase": "associate-fresh-renderer-once", "seconds": 0.5}], "registrationOperations": operations,
        "explicitDrawStateCalls": 1, "activeSceneRebindCalls": 1, "freshRendererCreationCalls": 1, "freshAssociationCalls": 1,
        "explicitPrepareCalls": 0, "freshRenderCalls": 0, "freshPrepareCalls": 0, "freshSnapshotCalls": 0, "snapshotCalls": 0,
        "sourceProjectorRemovedBeforeFirstExplicitDraw": True,
        "surfaceSubmittedFramesBeforeExperiment": 0, "surfaceLastSubmittedTickBeforeExperiment": None,
        "surfaceSubmittedFramesAfterExplicitDraw": submitted_after, "surfaceLastSubmittedTickAfterExplicitDraw": last_tick,
        "captureLabels": list(entry.FRAME_LABELS), "captureSourceProjectorStates": list(entry.CAPTURE_PROJECTOR_STATES),
        "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0, "stateInvariant": True, "restorationInvariant": True,
        "adjacentPNGEqualities": [images[entry.FRAME_LABELS[i]]["sha256"] == images[entry.FRAME_LABELS[i + 1]]["sha256"] for i in range(3)],
        "freshRendererUsedForCapture": False, "postFreshDetachmentCaptureTaken": False,
        "combatStateInjected": False, "liveDisplayLinkAdvancesSelected": False, "sourcePacketsExpectedZero": True,
        "sceneKitLightsChanged": False, "uiExecutionStatus": "not_selected", "physicalDeviceValidated": False,
        "liveUIValidated": False, "audiblePlaybackVerified": False, "performanceVerified": False,
        "pixels": "PENDING", "panguEquipmentActivated": False, "captureTimingIncludesGPUReadbackWait": True,
        "samples": samples, "captures": captures,
        "cleanup": {"sceneReleased": True, "surfaceReleased": True, "rendererReleased": True,
            "sourceProjectorRestoredBeforeShutdown": True, "originalSceneAndPointOfViewRestoredBeforeShutdown": True,
            "freshBindingsClearedBeforeShutdown": True, "freshTestReferenceClearedBeforeShutdown": True,
            "freshObjectDeallocationVerified": False, "activeClocksBefore": 0, "activeClocksAfter": 0}}


def attachments(directory, automatic=False):
    directory.mkdir()
    raw, items, paths, images = png_fixture(), [], {}, {}
    for index, label in enumerate(entry.FRAME_LABELS):
        path = directory / (str(index) + ".png")
        path.write_bytes(raw)
        paths[label] = path
        images[label] = {"sha256": entry.sha(raw), "bytes": len(raw), "width": 956, "height": 440}
        items.append({"exportedFileName": path.name, "suggestedHumanReadableName": label + ".png",
                      "deviceId": DEVICE["udid"], "deviceName": DEVICE["name"]})
    report = directory / "report.json"
    dump(report, report_fixture(images))
    paths[entry.REPORT_LABEL] = report
    items.append({"exportedFileName": report.name, "suggestedHumanReadableName": entry.REPORT_LABEL + ".json",
                  "deviceId": DEVICE["udid"], "deviceName": DEVICE["name"]})
    if automatic:
        (directory / "system-record").write_bytes(b"")
        with (directory / "automatic.mp4").open("wb") as output:
            output.truncate(25 * 1024**2)
        items.extend({"exportedFileName": name, "suggestedHumanReadableName": name} for name in ("system-record", "automatic.mp4"))
    dump(directory / "manifest.json", [{"testIdentifier": entry.SELECTOR + "()", "attachments": items}])
    return paths, images


def runtime_rows(message="Synthetic App diagnostic log record"):
    return [{"processImagePath": "/private/fixture/ShiftReminder.app/ShiftReminder",
             "timestamp": "2026-11-15 10:00:10.000000+0000", "eventMessage": message}]


def verify_log(path, code=0):
    return entry.verify_runtime_log(path, collection_code=code, device=DEVICE, started=START, finished=END)


def add_record(rows, name):
    if not any(row.split(b"\t", 1)[1].decode() == name for row in rows.splitlines()):
        rows += b"100644 blob " + b"f" * 40 + b"\t" + name.encode() + b"\n"
    return rows


def changed_retained_record(rows, excluded):
    output, changed = [], False
    for row in rows.splitlines():
        meta, name = row.split(b"\t", 1)
        if not changed and name.decode() not in excluded:
            mode, kind, _ = meta.split()
            row = b" ".join((mode, kind, b"0" * 40)) + b"\t" + name
            changed = True
        output.append(row + b"\n")
    assert changed
    return b"".join(output)


class SceneRegistrationDiagnosticTests(unittest.TestCase):
    def test_selection_is_exactly_the_new_native_method_and_history_is_not_current(self):
        inventory = entry.selected_inventory()
        self.assertEqual([row["identifier"] for row in inventory], [entry.SELECTOR])
        self.assertEqual(entry.SELECTORS, (entry.SELECTOR,))
        self.assertEqual(inventory[0]["sourceSHA256"], entry.SWIFT_TEST_SHA)
        prior = entry.preserved_prior_evidence()
        self.assertEqual([row["passedMethods"] for row in prior], [117, 5, 6, 1, 1, 1])
        self.assertEqual(prior[-3]["pixels"], "FAILED")
        self.assertEqual(prior[-2]["productionPixels"], "NOT_VERIFIED")
        self.assertEqual(prior[-1]["pixels"], "FAILED")
        self.assertTrue(all(row["selectedAgain"] is False and row["countsBelongToCurrentRun"] is False for row in prior))
        self.assertNotIn("ArenaFlowTests", entry.SELECTOR)

    def test_push_attempt_commit_repository_and_workflow_identity_are_exact(self):
        environment = dict(ENV, GITHUB_REPOSITORY=entry.REPOSITORY, GITHUB_REF=entry.BRANCH,
            GITHUB_WORKFLOW_REF=entry.REPOSITORY + "/" + entry.WORKFLOW + "@" + entry.BRANCH,
            GITHUB_WORKFLOW_SHA=ENV["GITHUB_SHA"], GITHUB_EVENT_NAME="push")
        event = {"repository": {"full_name": entry.REPOSITORY}, "ref": entry.BRANCH,
                 "head_commit": {"id": ENV["GITHUB_SHA"], "message": entry.COMMIT_MESSAGE}}
        entry.validate_event(environment, event, ENV["GITHUB_SHA"])
        for change in ({"GITHUB_RUN_ATTEMPT": "2"}, {"GITHUB_EVENT_NAME": "workflow_dispatch"},
                       {"GITHUB_WORKFLOW_SHA": "b" * 40}, {"GITHUB_REPOSITORY": "another/repo"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                entry.validate_event(dict(environment, **change), event, ENV["GITHUB_SHA"])
        for change in ({"deleted": True}, {"head_commit": dict(event["head_commit"], message=entry.COMMIT_MESSAGE + "\n")},
                       {"repository": {"full_name": "another/repo"}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                entry.validate_event(environment, dict(event, **change), ENV["GITHUB_SHA"])

    def test_source_baseline_allows_only_one_new_swift_and_three_independent_ci_files(self):
        self.assertEqual(entry.SOURCE_BASELINE, "4bd85374273b39f61724342b7e1d72631ab2042d")
        rows = [subprocess.check_output(["git", "ls-tree", "-r", "HEAD", path], cwd=entry.ROOT)
                for path in ("Tests", ".github/scripts", ".github/workflows")]
        rows[0] = add_record(rows[0], entry.SWIFT_TEST)
        rows[1] = add_record(add_record(rows[1], entry.HELPER), entry.CHECKS)
        rows[2] = add_record(rows[2], entry.WORKFLOW)
        entry.validate_source_trees(entry.REVIEWED_ENTRIES, *rows)
        exclusions = ({entry.SWIFT_TEST}, {entry.HELPER, entry.CHECKS}, {entry.WORKFLOW})
        for index in range(3):
            changed = list(rows)
            changed[index] = changed_retained_record(rows[index], exclusions[index])
            with self.subTest(index=index), self.assertRaises(ValueError):
                entry.validate_source_trees(entry.REVIEWED_ENTRIES, *changed)
        with self.assertRaises(ValueError):
            entry.validate_source_trees(dict(entry.REVIEWED_ENTRIES, App="0" * 40), *rows)
        with self.assertRaises(ValueError):
            entry.retained_tree_digest(rows[0], {"Tests/SiteTests/Missing.swift"})

    def test_final_review_pins_and_one_field_normalization_bind_all_other_workflow_bytes(self):
        actual = entry.digest(HELPER)
        with patch.dict(os.environ, {"EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256": actual}):
            entry.pin_sources()
        source = (entry.ROOT / entry.WORKFLOW).read_bytes()
        normalized, value = entry.normalized_workflow(source)
        self.assertEqual(value, actual)
        self.assertEqual(entry.sha(normalized), entry.WORKFLOW_CANONICAL_SHA)
        changed = source.replace(b"timeout-minutes: 15", b"timeout-minutes: 16", 1)
        self.assertNotEqual(entry.sha(entry.normalized_workflow(changed)[0]), entry.WORKFLOW_CANONICAL_SHA)
        for malformed in (source + b"# EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256\n",
                          source.replace(b"      EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER", b"    EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER")):
            with self.assertRaises(ValueError):
                entry.normalized_workflow(malformed)
        with patch.dict(os.environ, {"EXPECTED_SCENE_REGISTRATION_DIAGNOSTIC_HELPER_SHA256": "0" * 64}), self.assertRaises(ValueError):
            entry.pin_sources()

    def test_old_helper_reuse_is_byte_pinned_and_never_calls_or_replaces_old_scope_operations(self):
        shared = entry.resource_tools()
        self.assertEqual(entry.digest(Path(shared.__file__)), entry.RESOURCE_TOOLS_SHA)
        tree = ast.parse(HELPER.read_text())
        forbidden = {"identity", "prepare", "source_gate", "validate_event", "stage", "build", "test", "ui", "export", "seal", "cleanup", "report"}
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                if node.func.value.id in {"shared", "_resource_module", "legacy"}:
                    self.assertNotIn(node.func.attr, forbidden)
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                self.assertFalse(any(isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name)
                    and target.value.id in {"shared", "_resource_module", "legacy"} for target in targets))
        with patch.dict(os.environ, {"FIGHTER_SHARED_ROOT_SCOPE": "initial-nine"}), self.assertRaises(ValueError):
            entry.resource_tools()

    def test_failed_native_process_keeps_exit_code_exports_and_no_success_marker(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            (directory / "build-ok.txt").write_text("fixture")
            (directory / "xctestrun-path.txt").write_text("fixture.xctestrun")
            (directory / "native.xcresult").mkdir()
            (directory / "native.xcresult/Info.plist").write_text("fixture")
            dump(directory / "simulator.json", DEVICE)
            commands = []

            def run(command, label, *args, **kwargs):
                commands.append(label)
                if kwargs.get("output_name"):
                    dump(directory / kwargs["output_name"], {"actualFailure": "synthetic"})
                return 65 if label == "selected-native" else 0

            with patch.object(entry, "work", return_value=directory), patch.object(entry, "identity"), \
                    patch.object(entry, "no_resource_keys"), patch.object(entry, "run_logged", side_effect=run):
                with self.assertRaises(entry.PhaseFailure) as error:
                    entry.execute_native()
            self.assertEqual(error.exception.code, 65)
            self.assertEqual(len(commands), 3)
            self.assertFalse((directory / "native-ok.txt").exists())
            self.assertEqual(json.loads((directory / "native-process.json").read_text())["exports"], {"summary": 0, "tests": 0})

    def test_result_gate_rejects_empty_skip_duplicate_wrong_method_or_foreign_device(self):
        summary, nodes = results()
        entry.verify_results(summary, nodes, DEVICE)
        for change in ({"totalTestCount": 0}, {"passedTests": True}, {"skippedTests": 1}, {"result": "Completed"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                entry.verify_results(dict(summary, **change), nodes, DEVICE)
        for changed in ({"testNodes": []}, {"testNodes": nodes["testNodes"] * 2},
                        {"testNodes": [dict(nodes["testNodes"][0], nodeIdentifier="SiteTests/OldTest/testOld")]}):
            with self.assertRaises(ValueError):
                entry.verify_results(summary, changed, DEVICE)
        wrong = copy.deepcopy(summary)
        wrong["devicesAndConfigurations"][0]["device"]["deviceId"] = "foreign"
        with self.assertRaises(ValueError):
            entry.verify_results(wrong, nodes, DEVICE)

    def test_required_attachment_missing_owner_device_duplicate_or_empty_is_rejected(self):
        for defect in ("missing", "owner", "device", "duplicate", "empty"):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder) / "attachments"
                paths, _ = attachments(directory)
                manifest = json.loads((directory / "manifest.json").read_text())
                if defect == "missing":
                    paths[entry.FRAME_LABELS[0]].unlink()
                elif defect == "empty":
                    paths[entry.FRAME_LABELS[0]].write_bytes(b"")
                elif defect == "owner":
                    manifest[0]["testIdentifier"] = "SiteTests/Old/testOld"
                elif defect == "device":
                    manifest[0]["attachments"][0]["deviceId"] = "foreign"
                else:
                    manifest[0]["attachments"].append(manifest[0]["attachments"][0])
                dump(directory / "manifest.json", manifest)
                with self.assertRaises(ValueError):
                    entry.attachment_inventory(directory, DEVICE)

    def test_full_log_counts_known_drawable_errors_before_any_archived_tail(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            path = Path(folder) / "runtime.log"
            rows = runtime_rows(entry.METAL_DIAGNOSTICS["doublePresent"])
            rows += runtime_rows(entry.METAL_DIAGNOSTICS["textureAfterPresent"])
            rows += runtime_rows("x" * (2 * 1024**2))
            dump(path, rows)
            receipt = verify_log(path)
            self.assertEqual(receipt["knownDiagnosticCounts"], {"doublePresent": 1, "textureAfterPresent": 1})
            self.assertFalse(receipt["knownDiagnosticsAbsent"])
            self.assertTrue(receipt["sealedTextTailOnly"])

    def test_resource_keys_are_absent_outside_stage_and_child_forwarding_is_minimal(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {key: "synthetic-fixture" for key in entry.KEY_NAMES}):
            with self.assertRaises(ValueError):
                entry.no_resource_keys()
            process = types.SimpleNamespace(wait=lambda timeout: 0)
            with patch.object(entry, "work", return_value=Path(folder)), patch.object(entry.subprocess, "Popen", return_value=process) as popen:
                entry.run_logged(["synthetic-command"], "synthetic", 1, key_names=(entry.KEY_NAMES[1],))
                forwarded = popen.call_args.kwargs["env"]
                self.assertIn(entry.KEY_NAMES[1], forwarded)
                self.assertNotIn(entry.KEY_NAMES[0], forwarded)
                self.assertNotIn(entry.KEY_NAMES[2], forwarded)
                with self.assertRaises(ValueError):
                    entry.run_logged(["synthetic-command"], "synthetic2", 1, key_names=("UNKNOWN_KEY",))

    def test_summary_and_report_never_turn_ui_zero_or_diagnostic_pixels_into_pass(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            directory = Path(folder)
            dump(directory / "identity.json", {"sourceSHA": ENV["GITHUB_SHA"], "runID": "123", "attempt": "1"})
            with patch.object(entry, "work", return_value=directory), patch.object(entry, "no_resource_keys"), patch("builtins.print"), \
                    patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": ""}):
                summary = entry.public_summary()
                self.assertEqual(summary["expectedUIMethods"], 0)
                self.assertEqual(summary["uiExecutionStatus"], "not_selected")
                self.assertFalse(summary["uiExactMethodPassed"])
                self.assertNotIn("uiObservedCounts", summary)
                for key in ("resourcesAuthenticated", "compiled373ResourcesVerified", "nativeExactMethodPassed", "uiArtifactsAbsent",
                            "exactDiagnosticCaptureSetVerified", "sealedDiagnosticCaptureSetComplete", "runtimeDiagnosticGatePassed",
                            "diagnosticsSealed", "cleanupComplete", "registrationSequenceVerified"):
                    summary[key] = True
                for field, expected in (("originalRendererRebindCallCount", 1), ("freshRendererCreateCount", 1),
                        ("freshRendererAssociationCallCount", 1), ("freshRendererRenderCallCount", 0),
                        ("prepareCallCount", 0), ("snapshotCallCount", 0)):
                    summary[field] = expected
                dump(directory / "public-summary.json", summary)
                entry.report()
                for change in ({"sealedDiagnosticCaptureSetComplete": False}, {"runtimeDiagnosticGatePassed": False},
                               {"uiArtifactsAbsent": False}, {"uiExactMethodPassed": True}, {"pixels": "PASS"},
                               {"uiObservedCounts": {"totalTestCount": 0, "result": "Passed"}}, {"cleanupComplete": False},
                               {"registrationSequenceVerified": False}, {"registrationSequenceVerified": None},
                               {"originalRendererRebindCallCount": None}, {"freshRendererCreateCount": 0},
                               {"freshRendererAssociationCallCount": False}, {"freshRendererRenderCallCount": 1},
                               {"prepareCallCount": 1}, {"snapshotCallCount": 1}):
                    dump(directory / "public-summary.json", dict(summary, **change))
                    with self.subTest(change=change), self.assertRaises(ValueError):
                        entry.report()
                dump(directory / "ui-summary.json", {"totalTestCount": 0, "result": "Passed"})
                self.assertFalse(entry.public_summary()["uiArtifactsAbsent"])

    def test_workflow_is_push_only_one_native_and_stage_only_secrets_with_sealed_failure_cleanup(self):
        source = (entry.ROOT / entry.WORKFLOW).read_text()
        self.assertIn(entry.COMMIT_MESSAGE, source)
        self.assertNotIn("workflow_dispatch", source)
        self.assertNotIn("fighter_shared_root_native.py", source)
        self.assertNotIn("fighter_scene_registration_diagnostic.py ui", source)
        self.assertEqual(source.count("fighter_scene_registration_diagnostic.py test"), 1)
        self.assertIn("environment: fighter-private-assets", source)
        self.assertIn("cancel-in-progress: false", source)
        stage = source.split("      - name: Authenticate", 1)[1].split("      - name: Build", 1)[0]
        for key in entry.KEY_NAMES:
            self.assertEqual(stage.count("${{ secrets." + key + " }}"), 1)
            self.assertEqual(source.count("${{ secrets." + key + " }}"), 1)
        self.assertIn("steps.seal.outcome == 'success'", source)
        self.assertIn("fighter_scene_registration_diagnostic.py cleanup", source)
        self.assertNotIn("ui-recovery", source)

    def test_one_native_method_runs_once_without_retry_flags_and_original_limit_is_retained(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            summary, nodes = results()
            (directory / "build-ok.txt").write_text("fixture")
            (directory / "xctestrun-path.txt").write_text("fixture.xctestrun")
            (directory / "native.xcresult").mkdir()
            (directory / "native.xcresult/Info.plist").write_text("fixture")
            dump(directory / "simulator.json", DEVICE)
            commands = []

            def run(command, label, timeout, **kwargs):
                commands.append((command, timeout))
                if kwargs.get("output_name"):
                    dump(directory / kwargs["output_name"], summary if kwargs["output_name"].endswith("summary.json") else nodes)
                return 0

            with patch.object(entry, "work", return_value=directory), patch.object(entry, "identity"), \
                    patch.object(entry, "no_resource_keys"), patch.object(entry, "run_logged", side_effect=run), patch("builtins.print"):
                entry.execute_native()
                with self.assertRaises(FileExistsError):
                    entry.execute_native()
            command, timeout = commands[0]
            self.assertEqual([part for part in command if part.startswith("-only-testing:")], ["-only-testing:" + entry.SELECTOR])
            self.assertEqual(timeout, 720)
            for flag in ("-test-iterations", "-retry-tests-on-failure", "-run-tests-until-failure"):
                self.assertNotIn(flag, command)
            self.assertEqual(len(commands), 3)
            self.assertFalse(any(path.name.startswith("ui") for path in directory.iterdir()))

    def test_manifest_and_five_required_files_are_sealed_before_automatic_budget(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "native-attachments"
            attachments(directory)
            for index in range(300):
                (directory / ("000-auto-" + str(index) + ".txt")).write_text("synthetic automatic record")
            receipt = entry.attachment_inventory(directory, DEVICE)
            dump(Path(folder) / "attachments-ok.json", receipt)
            with patch.object(entry, "work", return_value=Path(folder)):
                selected = entry.bounded_attachments()
            names = {path.name for path, _ in selected}
            self.assertIn("manifest.json", names)
            self.assertTrue({row["file"] for row in receipt["files"]} <= names)
            self.assertEqual(len(selected), 256)
            policy = json.loads((Path(folder) / "attachment-seal-policy.json").read_text())
            self.assertTrue(policy["completeValidatedMandatorySetSealed"])
            self.assertGreater(policy["omittedFileCount"], 0)

    def test_runtime_log_requires_complete_nonempty_owned_interval_and_success(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            path = Path(folder) / "runtime.log"
            dump(path, runtime_rows())
            self.assertTrue(verify_log(path)["knownDiagnosticsAbsent"])
            with self.assertRaises(ValueError):
                verify_log(path, 1)
            for value in ("", "[]", "{}", "{broken", json.dumps([{}]),
                          json.dumps([dict(runtime_rows()[0], timestamp="2026-11-15 09:59:00+0000")])):
                path.write_text(value)
                with self.subTest(value=value[:60]), self.assertRaises(ValueError):
                    verify_log(path)








    def test_registration_order_and_cold_surface_boundary_are_exact_without_forcing_a_drawable(self):
        images = {label: {"sha256": "a" * 64, "bytes": 100, "width": 956, "height": 440} for label in entry.FRAME_LABELS}
        for submitted in (0, 1):
            with self.subTest(submitted=submitted):
                observed = entry.validate_report(report_fixture(images, submitted_after=submitted), images)
                self.assertTrue(observed["registrationSequenceVerified"])
                self.assertEqual(observed["surfaceSubmittedFramesAfterExplicitDraw"], submitted)
        valid = report_fixture(images)
        for field, changed in (("surfaceSubmittedFramesBeforeExperiment", 1), ("surfaceSubmittedFramesBeforeExperiment", False),
                ("surfaceSubmittedFramesAfterExplicitDraw", False), ("sourceProjectorRemovedBeforeFirstExplicitDraw", False),
                ("explicitDrawStateCalls", 2), ("activeSceneRebindCalls", 2), ("freshRendererCreationCalls", 0),
                ("freshAssociationCalls", 2), ("simulationAdvanceCalls", 1), ("expectedSimulationFrames", [False])):
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(dict(valid, **{field: changed}), images)
        for collection, index, field, changed in (("captures", 0, "sourceProjectorInstalled", True),
                ("samples", 0, "projectorEncodedForCapture", True), ("samples", 1, "sourceProjectorInstalled", False),
                ("captures", 1, "activeSceneRebindCallsSoFar", 1), ("samples", 2, "activeSceneRebindCallsSoFar", 0),
                ("samples", 2, "freshRendererCreationCallsSoFar", 1), ("captures", 3, "freshAssociationCallsSoFar", 0),
                ("samples", 0, "displayLinkCallbacks", 1), ("captures", 2, "surfaceSubmittedFrames", 1),
                ("samples", 3, "surfaceLastSubmittedTick", 0), ("samples", 3, "sameActiveRenderer", False)):
            bad = copy.deepcopy(valid); bad[collection][index][field] = changed
            with self.subTest(collection=collection, field=field), self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); del bad["surfaceLastSubmittedTickBeforeExperiment"]
        with self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["registrationOperations"].reverse()
        with self.assertRaises(ValueError): entry.validate_report(bad, images)

    def test_rebind_and_fresh_association_are_observed_once_without_render_prepare_or_arc_claims(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "native-attachments"
            _, images = attachments(directory)
            receipt = entry.attachment_inventory(directory, DEVICE)
            self.assertEqual(len(receipt["files"]), 5)
            self.assertTrue(receipt["registrationObservations"]["registrationSequenceVerified"])
            self.assertEqual(receipt["registrationObservations"]["freshRendererRenderCalls"], 0)
        valid = report_fixture(images)
        for field in ("explicitPrepareCalls", "freshRenderCalls", "freshPrepareCalls", "freshSnapshotCalls", "snapshotCalls"):
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(dict(valid, **{field: 1}), images)
        for field in ("freshRendererUsedForCapture", "postFreshDetachmentCaptureTaken", "sceneKitLightsChanged"):
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(dict(valid, **{field: True}), images)
        for index, field, changed in ((0, "nilSceneObserved", False), (0, "calls", True),
                (0, "sameSceneAfter", False), (1, "creationCalls", 2), (1, "beforeCaptureLabel", entry.FRAME_LABELS[0])):
            bad = copy.deepcopy(valid); bad["registrationOperations"][index][field] = changed
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(bad, images)
        for field, changed in (("renderCalls", 1), ("prepareCalls", 1), ("snapshotCalls", 1),
                ("distinctFromActiveRenderer", False), ("sameDevice", False), ("sameScene", False), ("delegateAbsent", False)):
            bad = copy.deepcopy(valid); bad["samples"][3]["freshRenderer"][field] = changed
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["samples"][1]["freshRenderer"] = copy.deepcopy(bad["samples"][3]["freshRenderer"])
        with self.assertRaises(ValueError): entry.validate_report(bad, images)
        for field, changed in (("freshBindingsClearedBeforeShutdown", False), ("freshTestReferenceClearedBeforeShutdown", False),
                ("originalSceneAndPointOfViewRestoredBeforeShutdown", False), ("freshObjectDeallocationVerified", True)):
            bad = copy.deepcopy(valid); bad["cleanup"][field] = changed
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["timings"].append(dict(bad["timings"][0]))
        with self.assertRaises(ValueError): entry.validate_report(bad, images)

    def test_original_png_differences_and_optional_first_projector_metadata_remain_observations(self):
        images = {label: {"sha256": str(i) * 64, "bytes": 100, "width": 956, "height": 440}
                  for i, label in enumerate(entry.FRAME_LABELS)}
        for available in (False, True):
            valid = report_fixture(images, first_projector_available=available)
            self.assertEqual(valid["adjacentPNGEqualities"], [False, False, False])
            self.assertTrue(entry.validate_report(valid, images)["registrationSequenceVerified"])
        valid = report_fixture(images)
        valid["samples"][2]["camera"]["presentationWorldTransform"] = [2.0] * 16
        entry.validate_report(valid, images)
        for changed in ([True, False, False], [0, False, False], [False, False]):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                entry.validate_report(dict(valid, adjacentPNGEqualities=changed), images)
        for field, changed in (("pngSHA256", "a" * 64), ("bytes", 1), ("width", 955), ("pixelsRequireReview", False)):
            bad = copy.deepcopy(valid); bad["captures"][2][field] = changed
            with self.subTest(field=field), self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["samples"][1]["projectorLastFrame"] = {"available": False}
        with self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["samples"][2]["projectorLastFrame"]["triangleCount"] += 1
        with self.assertRaises(ValueError): entry.validate_report(bad, images)
        bad = copy.deepcopy(valid); bad["samples"][2]["camera"]["model"]["fieldOfView"] = 25.0
        with self.assertRaises(ValueError): entry.validate_report(bad, images)
        with self.assertRaises(ValueError): entry.validate_report(dict(valid, pixels="PASS"), images)


if __name__ == "__main__":
    unittest.main()
