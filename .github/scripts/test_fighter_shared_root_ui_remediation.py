#!/usr/bin/env python3
"""New UI-only orchestration gates; no Apple execution, media keys or old tests."""
import copy
import datetime
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch


HELPER = Path(__file__).with_name("fighter_shared_root_native.py")
SPEC = importlib.util.spec_from_file_location("review_ui_remediation", HELPER)
ui = importlib.util.module_from_spec(SPEC)
with patch.dict(os.environ, {"FIGHTER_SHARED_ROOT_SCOPE": "ui-remediation-only"}):
    SPEC.loader.exec_module(ui)

DEVICE = {"udid": "12345678-1234-1234-1234-123456789ABC", "name": "Fighter shared root 123 attempt 1",
          "physicalDevice": False}
START = datetime.datetime(2026, 11, 15, 10, 0, 0, tzinfo=datetime.timezone.utc)
END = START + datetime.timedelta(seconds=20)
ENV = {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "a" * 40,
       "FIGHTER_SHARED_ROOT_SCOPE": "ui-remediation-only"}


def dump(path, value):
    path.write_text(json.dumps(value))


def results():
    summary = {"totalTestCount": 1, "passedTests": 1, "failedTests": 0, "skippedTests": 0,
               "result": "Passed", "devicesAndConfigurations": [{
                   "device": {"deviceId": DEVICE["udid"], "deviceName": DEVICE["name"],
                              "modelName": "iPhone 17 Pro Max", "platform": "iOS Simulator"},
                   "passedTests": 1, "failedTests": 0, "skippedTests": 0}]}
    nodes = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": ui.UI_SELECTORS[0] + "()",
                             "result": "Passed"}]}
    return summary, nodes


def runtime_rows(message="App draw cycle completed"):
    return [{"processImagePath": "/private/fixture/ShiftReminder.app/ShiftReminder",
             "timestamp": "2026-11-15 10:00:10.000000+0000", "eventMessage": message, "formatString": ""}]


def verify_log(path, code=0):
    return ui.verify_ui_runtime_log(path, collection_code=code, device=DEVICE, started=START, finished=END)


def attachment_fixture(directory, automatic=False):
    directory.mkdir()
    items, paths = [], {}
    for index, (label, (_, kind)) in enumerate(ui.EXPECTED_ATTACHMENTS["ui"].items()):
        suffix = ".png" if kind == "image" else ".json"
        path = directory / (str(index) + suffix)
        if kind == "image":
            path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR" + struct.pack(">II", 1200, 600))
        else:
            dump(path, {"expectedReleaseSHA256": ui.RELEASE_SHA, "flowCompleted": True,
                        "internalCombatStateInjected": False, "exactRootAnimationTicksObserved": False})
        paths[label] = path
        items.append({"exportedFileName": path.name, "suggestedHumanReadableName": label + suffix,
                      "deviceId": DEVICE["udid"], "deviceName": DEVICE["name"]})
    if automatic:
        for name, size in (("system-record", 0), ("automatic.mp4", 25 * 1024**2)):
            with (directory / name).open("wb") as output:
                output.truncate(size)
            items.append({"exportedFileName": name, "suggestedHumanReadableName": name})
    dump(directory / "manifest.json", [{"testIdentifier": ui.UI_SELECTORS[0] + "()", "attachments": items}])
    return paths


def altered(rows, excluded=()):
    result, changed = [], False
    for row in rows.splitlines():
        meta, name = row.split(b"\t", 1)
        if not changed and name.decode() not in excluded:
            mode, kind, _ = meta.split()
            row = b" ".join((mode, kind, b"0" * 40)) + b"\t" + name
            changed = True
        result.append(row + b"\n")
    assert changed
    return b"".join(result)


def add_record(rows, name):
    if not any(row.split(b"\t", 1)[1].decode() == name for row in rows.splitlines()):
        rows += b"100644 blob " + b"f" * 40 + b"\t" + name.encode() + b"\n"
    return rows


class SharedRootUIRemediationTests(unittest.TestCase):
    def test_native_execution_and_empty_results_are_rejected_before_any_side_effect(self):
        self.assertEqual(ui.EXPECTED_COUNT, 0)
        self.assertEqual(ui.SELECTORS, ())
        self.assertEqual(ui.selected_inventory(), [])
        self.assertEqual(set(ui.METHOD_SCOPE.values()), {0})
        with patch.object(ui, "identity") as identity, patch.object(ui, "run_logged") as run:
            with self.assertRaisesRegex(ValueError, "prohibited"):
                ui.test()
            identity.assert_not_called()
            run.assert_not_called()
        with self.assertRaises(ValueError):
            ui.verify_results({"totalTestCount": 0, "passedTests": 0, "failedTests": 0,
                               "skippedTests": 0, "result": "Passed"}, {"testNodes": []}, ())
        prior = ui.preserved_prior_evidence()
        self.assertEqual([(row["runID"], row["passedMethods"]) for row in prior],
                         [("43644209347", 5), ("43647414701", 6)])
        self.assertTrue(all(row["selectedAgain"] is False and row["countsBelongToCurrentRun"] is False for row in prior))

    def test_push_identity_is_exact_and_dispatch_repeated_attempt_or_stale_workflow_cannot_run(self):
        environment = dict(ENV, GITHUB_REPOSITORY=ui.REPOSITORY, GITHUB_REF=ui.BRANCH,
                           GITHUB_WORKFLOW_REF=ui.REPOSITORY + "/" + ui.WORKFLOW + "@" + ui.BRANCH,
                           GITHUB_WORKFLOW_SHA=ENV["GITHUB_SHA"], GITHUB_EVENT_NAME="push")
        event = {"repository": {"full_name": ui.REPOSITORY}, "ref": ui.BRANCH,
                 "head_commit": {"id": ENV["GITHUB_SHA"], "message": ui.COMMIT_MESSAGE}}
        ui.validate_event(environment, event, ENV["GITHUB_SHA"])
        for change in ({"GITHUB_EVENT_NAME": "workflow_dispatch"}, {"GITHUB_RUN_ATTEMPT": "2"},
                       {"GITHUB_WORKFLOW_SHA": "b" * 40}, {"FIGHTER_SHARED_ROOT_SCOPE": "material-followup-six"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                ui.validate_event(dict(environment, **change), event, ENV["GITHUB_SHA"])
        wrong = copy.deepcopy(event)
        wrong["head_commit"]["message"] += "\n"
        with self.assertRaises(ValueError):
            ui.validate_event(environment, wrong, ENV["GITHUB_SHA"])

    def test_source_gate_allows_only_three_app_files_one_ui_file_and_two_new_ci_files(self):
        self.assertEqual(ui.SOURCE_BASELINE, "5afd8195e2f611ab2e7c37f5096a4251a4616ee9")
        entries = {name: value for name, value in ui.REVIEWED_ENTRIES.items() if name != "App"}
        entries["scripts"] = ui.UI_SCRIPTS_TREE
        rows = [subprocess.check_output(["git", "ls-tree", "-r", "HEAD", path], cwd=ui.ROOT)
                for path in ("Tests", "App", ".github/scripts", ".github/workflows")]
        rows[1] = add_record(rows[1], "App/Services/DuelTriadSurfaceFrameDriver.swift")
        rows[2] = add_record(rows[2], ui.UI_SCOPE_TEST)
        rows[3] = add_record(rows[3], ui.WORKFLOW)
        ui.validate_source_trees(entries, *rows)
        exceptions = ({ui.UI_TEST}, ui.UI_APP_PINS,
                      {".github/scripts/fighter_shared_root_native.py", ui.UI_SCOPE_TEST}, {ui.WORKFLOW})
        for index in range(4):
            changed = list(rows)
            changed[index] = altered(changed[index], exceptions[index])
            with self.subTest(tree=index), self.assertRaises(ValueError):
                ui.validate_source_trees(entries, *changed)
        missing = list(rows)
        missing[1] = b"".join(row + b"\n" for row in rows[1].splitlines()
                              if not row.endswith(b"\tApp/Services/DuelTriadSurfaceFrameDriver.swift"))
        with self.assertRaises(ValueError):
            ui.validate_source_trees(entries, *missing)
        with self.assertRaises(ValueError):
            ui.validate_source_trees(dict(entries, Sources="0" * 40), *rows)

    def test_final_pins_and_exact_single_workflow_normalization_cannot_mask_other_bytes(self):
        helper_sha = ui.digest(HELPER)
        with patch.dict(os.environ, {"EXPECTED_SHARED_ROOT_UI_HELPER_SHA256": helper_sha}):
            ui.pin_scope_sources()
        source = (ui.ROOT / ui.WORKFLOW).read_bytes()
        normalized, actual = ui.normalized_ui_workflow(source)
        self.assertEqual(actual, helper_sha)
        self.assertEqual(ui.sha(normalized), ui.UI_WORKFLOW_CANONICAL_SHA)
        changed = source.replace(b"timeout-minutes: 8", b"timeout-minutes: 9", 1)
        self.assertNotEqual(ui.sha(ui.normalized_ui_workflow(changed)[0]), ui.UI_WORKFLOW_CANONICAL_SHA)
        for malformed in (source + b"# EXPECTED_SHARED_ROOT_UI_HELPER_SHA256\n",
                          source.replace(b"      EXPECTED_SHARED_ROOT_UI_HELPER", b"    EXPECTED_SHARED_ROOT_UI_HELPER")):
            with self.assertRaises(ValueError):
                ui.normalized_ui_workflow(malformed)
        with patch.dict(os.environ, {"EXPECTED_SHARED_ROOT_UI_HELPER_SHA256": "0" * 64}), self.assertRaises(ValueError):
            ui.pin_ui_ci_sources()

    def test_build_uses_existing_arenaflow_and_rejects_any_native_test_bundle(self):
        original = (ui.ROOT / "project.yml").read_bytes()
        for native_bundle in (False, True):
            with self.subTest(native_bundle=native_bundle), tempfile.TemporaryDirectory() as folder:
                root, directory = Path(folder), Path(folder) / "run"
                directory.mkdir()
                (root / "project.yml").write_bytes(original)
                (directory / "stage-ok.json").write_text("{}")
                dump(directory / "expected-resources.json", [])
                products = directory / "derived/Build/Products"
                app = products / "Debug-iphonesimulator/ShiftReminder.app"
                app.mkdir(parents=True)
                (products / "ArenaFlowTests.xctest").mkdir()
                if native_bundle:
                    (products / "SiteTests.xctest").mkdir()
                (products / "fixture.xctestrun").write_bytes(plistlib.dumps({"testTargets": [{
                    "BlueprintName": "ArenaFlowTests", "IsUITestBundle": True}]}))
                (app / "Info.plist").write_bytes(plistlib.dumps({"FighterAssetReleaseSHA256": ui.RELEASE_SHA,
                    "ArenaCommitSHA": ENV["GITHUB_SHA"], "CFBundleIdentifier": "com.kriswu.shiftreminder"}))
                commands = []
                with patch.object(ui, "ROOT", root), patch.object(ui, "work", return_value=directory), \
                        patch.object(ui, "identity"), patch.object(ui, "no_resource_keys"), \
                        patch.object(ui, "dependencies", return_value=types.SimpleNamespace(test_targets=lambda p: p["testTargets"])), \
                        patch.object(ui, "audit_resources"), patch.object(ui, "run_logged", side_effect=lambda cmd, *a, **k: commands.append(cmd)), \
                        patch.dict(os.environ, ENV), patch("builtins.print"):
                    if native_bundle:
                        with self.assertRaisesRegex(ValueError, "native test bundle"):
                            ui.build()
                    else:
                        ui.build()
                build = [cmd for cmd in commands if cmd[0] == "xcodebuild"][0]
                self.assertEqual(build[1], "build-for-testing")
                self.assertEqual(build[build.index("-scheme") + 1], "ArenaFlow")
                self.assertNotIn("SiteTests", " ".join(build))
                self.assertIn(["xcodegen", "generate"], commands)
                self.assertEqual((root / "project.yml").read_bytes(), original)
                self.assertFalse((root / "project.shared-root-native.yml").exists())

    def test_ui_invocation_selects_one_method_once_without_retry_or_timeout_increase(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            summary, nodes = results()
            (directory / "build-ok.txt").write_text("fixture")
            dump(directory / "simulator.json", DEVICE)
            (directory / "xctestrun-path.txt").write_text("fixture.xctestrun")
            (directory / "ui.xcresult").mkdir()
            (directory / "ui.xcresult/Info.plist").write_text("fixture")
            commands = []

            def run(command, label, timeout, **kwargs):
                commands.append((command, timeout))
                if kwargs.get("output_name"):
                    dump(directory / kwargs["output_name"], summary if kwargs["output_name"].endswith("summary.json") else nodes)
                return 0

            with patch.object(ui, "work", return_value=directory), patch.object(ui, "identity"), \
                    patch.object(ui, "no_resource_keys"), patch.object(ui, "run_logged", side_effect=run), patch("builtins.print"):
                ui.execute_tests(ui=True)
                with self.assertRaises(FileExistsError):
                    ui.execute_tests(ui=True)
            command, timeout = commands[0]
            self.assertEqual(tuple(item.removeprefix("-only-testing:") for item in command
                                   if item.startswith("-only-testing:")), ui.UI_SELECTORS)
            self.assertEqual(timeout, 360)
            for forbidden in ("-test-iterations", "-retry-tests-on-failure", "-run-tests-until-failure"):
                self.assertNotIn(forbidden, command)
            self.assertEqual(len(commands), 3)

    def test_exact_ui_result_rejects_skipped_duplicate_wrong_method_and_other_device(self):
        summary, nodes = results()
        ui.verify_results(summary, nodes, ui.UI_SELECTORS)
        ui.verify_ui_result_device(summary, DEVICE)
        for change in ({"skippedTests": 1}, {"passedTests": 0}, {"result": "Completed"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                ui.verify_results(dict(summary, **change), nodes, ui.UI_SELECTORS)
        for changed in ({"testNodes": nodes["testNodes"] * 2},
                        {"testNodes": [dict(nodes["testNodes"][0], nodeIdentifier=ui.MODEL_SELECTOR)]}):
            with self.assertRaises(ValueError):
                ui.verify_results(summary, changed, ui.UI_SELECTORS)
        changed = copy.deepcopy(summary)
        changed["devicesAndConfigurations"][0]["device"]["deviceId"] = "other"
        with self.assertRaises(ValueError):
            ui.verify_ui_result_device(changed, DEVICE)

    def test_required_attachments_accept_bounded_empty_system_records_and_omitted_video(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "ui-attachments"
            attachment_fixture(directory, automatic=True)
            receipt = ui.attachment_inventory(directory, DEVICE, "ui")
            self.assertEqual(len(receipt["files"]), 7)
            self.assertTrue(receipt["completeExpectedLabels"])
            self.assertEqual(receipt["unknownAutomaticAttachments"], 2)
            self.assertEqual(receipt["omittedVideoCount"], 1)
            self.assertTrue(all(row["countsAsCoverage"] is False for row in receipt["automaticDiagnostics"]))
            with patch.object(ui, "work", return_value=Path(folder)):
                selected = ui.bounded_attachments()
            self.assertEqual(len(selected), 8)  # Six images, observations, manifest.
            policy = json.loads((Path(folder) / "attachment-seal-policy.json").read_text())
            self.assertEqual(policy["omittedFileCount"], 2)
            self.assertFalse(policy["mandatoryValidationPassed"])

    def test_mandatory_attachment_missing_wrong_owner_empty_or_oversized_never_passes(self):
        for defect in ("missing", "owner", "device", "empty", "oversized", "incomplete"):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder) / "attachments"
                paths = attachment_fixture(directory)
                first = paths["shared-root-ui-sun-lobby"]
                if defect == "missing":
                    first.unlink()
                elif defect in ("owner", "device"):
                    manifest = json.loads((directory / "manifest.json").read_text())
                    if defect == "owner":
                        manifest[0]["testIdentifier"] = ui.MODEL_SELECTOR
                    else:
                        manifest[0]["attachments"][0]["deviceId"] = "another-device"
                    dump(directory / "manifest.json", manifest)
                elif defect in ("empty", "oversized"):
                    with first.open("wb") as output:
                        output.truncate(0 if defect == "empty" else 25 * 1024**2)
                else:
                    dump(paths["shared-root-ui-observations"], {"expectedReleaseSHA256": ui.RELEASE_SHA,
                        "flowCompleted": False, "internalCombatStateInjected": False, "exactRootAnimationTicksObserved": False})
                with self.assertRaises(ValueError):
                    ui.attachment_inventory(directory, DEVICE, "ui")

    def test_sealing_prioritizes_manifest_and_validated_mandatory_set_over_automatic_files(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / "ui-attachments"
            attachment_fixture(directory)
            for index in range(300):
                (directory / ("000-automatic-" + str(index) + ".txt")).write_text("automatic diagnostic")
            receipt = ui.attachment_inventory(directory, DEVICE, "ui")
            dump(Path(folder) / "ui-attachments-ok.json", receipt)
            with patch.object(ui, "work", return_value=Path(folder)):
                selected = ui.bounded_attachments()
            names = {path.name for path, _ in selected}
            self.assertIn("manifest.json", names)
            self.assertTrue({row["file"] for row in receipt["files"]} <= names)
            self.assertEqual(len(selected), 256)
            policy = json.loads((Path(folder) / "attachment-seal-policy.json").read_text())
            self.assertTrue(policy["completeValidatedMandatorySetSealed"])
            self.assertGreater(policy["omittedFileCount"], 0)

    def test_attachment_structural_symlink_single_and_aggregate_bounds_are_strict(self):
        for defect in ("symlink", "single", "aggregate"):
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder) / "attachments"
                paths = attachment_fixture(directory)
                if defect == "symlink":
                    (directory / "automatic").symlink_to(paths["shared-root-ui-sun-lobby"])
                else:
                    for index in range(1 if defect == "single" else 3):
                        with (directory / (str(index) + "-automatic.mp4")).open("wb") as output:
                            output.truncate((129 if defect == "single" else 90) * 1024**2)
                with self.assertRaises(ValueError):
                    ui.attachment_inventory(directory, DEVICE, "ui")

    def test_full_runtime_log_requires_success_nonempty_valid_json_and_owned_app_entries(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            path = Path(folder) / "runtime.log"
            dump(path, runtime_rows())
            receipt = verify_log(path)
            self.assertTrue(receipt["knownDiagnosticsAbsent"])
            self.assertEqual(receipt["appEntries"], 1)
            self.assertFalse(receipt["sealedTextTailOnly"])
            with self.assertRaises(ValueError):
                verify_log(path, 1)
            for contents in ("", "[]", "{broken", "{}", json.dumps([{}]),
                             json.dumps([dict(runtime_rows()[0], timestamp="2026-11-15 09:59:00+0000")])):
                path.write_text(contents)
                with self.subTest(contents=contents[:50]), self.assertRaises(ValueError):
                    verify_log(path)

    def test_complete_log_scan_detects_both_drawable_errors_even_before_the_sealed_tail(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            path = Path(folder) / "runtime.log"
            rows = runtime_rows(ui.DRAWABLE_DIAGNOSTICS["doublePresent"])
            rows += runtime_rows(ui.DRAWABLE_DIAGNOSTICS["textureAfterPresent"])
            rows += runtime_rows("x" * (2 * 1024**2))
            dump(path, rows)
            receipt = verify_log(path)
            self.assertFalse(receipt["knownDiagnosticsAbsent"])
            self.assertEqual(receipt["knownDiagnosticCount"], 2)
            self.assertEqual(receipt["knownDiagnosticCounts"], {"doublePresent": 1, "textureAfterPresent": 1})
            self.assertTrue(receipt["sealedTextTailOnly"])

    def test_runtime_collection_uses_full_interval_and_known_error_cannot_create_success_marker(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            directory = Path(folder)
            dump(directory / "simulator.json", DEVICE)
            commands = []

            def run(command, *args, **kwargs):
                commands.append(command)
                dump(directory / "ui-runtime-log.log", runtime_rows(ui.DRAWABLE_DIAGNOSTICS["doublePresent"]))
                return 0

            with patch.object(ui, "work", return_value=directory), patch.object(ui, "run_logged", side_effect=run), \
                    patch.object(ui.subprocess, "check_output", return_value=json.dumps({"devices": {"runtime": [DEVICE]}})):
                with self.assertRaisesRegex(ValueError, "Known drawable"):
                    ui.collect_ui_runtime_diagnostics(START, END)
            self.assertIn("--start", commands[0])
            self.assertIn("--end", commands[0])
            self.assertNotIn("--last", commands[0])
            self.assertEqual(commands[0][3], DEVICE["udid"])
            self.assertFalse((directory / "ui-runtime-ok.txt").exists())
            self.assertEqual(json.loads((directory / "ui-runtime-diagnostics.json").read_text())["knownDiagnosticCount"], 1)

    def test_public_summary_keeps_native_not_selected_and_refuses_unexpected_native_artifacts(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, ENV):
            directory = Path(folder)
            dump(directory / "identity.json", {"sourceSHA": ENV["GITHUB_SHA"], "runID": "123", "attempt": "1"})
            dump(directory / "simulator.json", DEVICE)
            dump(directory / "ui-runtime-log.log", runtime_rows())
            dump(directory / "ui-runtime-diagnostics.json", verify_log(directory / "ui-runtime-log.log"))
            (directory / "ui-runtime-ok.txt").write_text(ui.UI_RUNTIME_OK)
            (directory / "native-build.log").write_text("Application build, no native tests")
            with patch.object(ui, "work", return_value=directory):
                summary = ui.public_summary()
                self.assertTrue(summary["uiRuntimeDiagnosticGatePassed"])
                self.assertTrue(summary["nativeArtifactsAbsent"])
                self.assertEqual(summary["nativeExecutionStatus"], "not_selected")
                self.assertFalse(summary["nativeExactSetPassed"])
                self.assertNotIn("nativeObservedCounts", summary)
                self.assertNotIn("nativeProcess", summary)
                self.assertEqual(summary["simulatorVisualReview"], "PENDING")
                self.assertIsNone(ui.reusable_ui_products())
                dump(directory / "native-summary.json", {"totalTestCount": 0, "result": "Passed"})
                summary = ui.public_summary()
                self.assertFalse(summary["nativeArtifactsAbsent"])
                self.assertNotIn("nativeObservedCounts", summary)

    def test_report_requires_ui_evidence_runtime_cleanup_and_native_absence_without_zero_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            dump(directory / "identity.json", {"sourceSHA": ENV["GITHUB_SHA"], "runID": "123", "attempt": "1"})
            with patch.object(ui, "work", return_value=directory), patch.object(ui, "no_resource_keys"), \
                    patch("builtins.print"), patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": ""}):
                summary = ui.public_summary()
                for key in ("resourcesAuthenticated", "compiled373ResourcesVerified", "uiExactMethodPassed",
                            "uiExactCaptureSetVerified", "uiRuntimeDiagnosticGatePassed", "uiSealedCaptureSetComplete",
                            "diagnosticsSealed", "cleanupComplete"):
                    summary[key] = True
                dump(directory / "public-summary.json", summary)
                ui.report()
                for change in ({"uiExactCaptureSetVerified": False}, {"uiRuntimeDiagnosticGatePassed": False},
                               {"uiSealedCaptureSetComplete": False},
                               {"nativeArtifactsAbsent": False}, {"nativeExactSetPassed": True},
                               {"nativeObservedCounts": {"totalTestCount": 0, "result": "Passed"}},
                               {"cleanupComplete": False}):
                    dump(directory / "public-summary.json", dict(summary, **change))
                    with self.subTest(change=change), self.assertRaises(ValueError):
                        ui.report()

    def test_workflow_has_only_failed_ui_scope_and_stage_only_resource_keys(self):
        source = (ui.ROOT / ui.WORKFLOW).read_text()
        self.assertIn("FIGHTER_SHARED_ROOT_SCOPE: ui-remediation-only", source)
        self.assertIn(ui.COMMIT_MESSAGE, source)
        self.assertNotIn("workflow_dispatch", source)
        self.assertNotIn("fighter_shared_root_native.py test", source)
        self.assertNotIn("ui-recovery.enc", source)
        self.assertIn("environment: fighter-private-assets", source)
        self.assertIn("cancel-in-progress: false", source)
        stage = source.split("      - name: Authenticate", 1)[1].split("      - name: Build", 1)[0]
        for key in ui.KEY_NAMES:
            self.assertEqual(stage.count("${{ secrets." + key + " }}"), 1)
            self.assertEqual(source.count("${{ secrets." + key + " }}"), 1)
        ui_step = source.split("      - name: Execute", 1)[1].split("      - name: Capture", 1)[0]
        self.assertIn("timeout-minutes: 8", ui_step)
        self.assertIn("steps.seal.outcome == 'success'", source)
        self.assertIn("fighter_shared_root_native.py cleanup", source)


if __name__ == "__main__":
    unittest.main()
