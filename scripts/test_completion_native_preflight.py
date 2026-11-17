#!/usr/bin/env python3
"""Safety-boundary tests for the offline preflight, using synthetic temp inputs.

These tests do not run Swift, Xcode, a simulator, workflows, staging or network.
Synthetic plists/resources/GET receipts test validation mechanics only. They
are not resource-loading evidence, real GitHub evidence or native test passes.
Run: python3 -I -B -S scripts/test_completion_native_preflight.py
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import plistlib
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("completion_native_preflight", HERE / "completion_native_preflight.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic-completion-preflight-")
        self.root = Path(self.temporary.name).resolve()

    def tearDown(self):
        self.temporary.cleanup()

    def put(self, name, data=b"synthetic fixture bytes"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def row(self, name, data):
        return {"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    def rejection(self, code, action):
        with self.assertRaises(P.CheckError) as error:
            action()
        self.assertEqual(error.exception.code, code)

    def fake_bundle(self, path, identifier):
        path.mkdir(parents=True, exist_ok=True)
        # A minimal synthetic header, deliberately not an executable program.
        kind = 8 if path.suffix == ".xctest" else 2
        (path / "FixtureBinary").write_bytes(struct.pack("<8I", 0xfeedfacf, 0x0100000c, 0, kind, 1, 8, 0, 0) + b"SYNTHETI")
        (path / "FixtureBinary").chmod(0o700)
        (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier, "CFBundleExecutable": "FixtureBinary"}))
        return path

    def fake_native_plan(self):
        derived = self.root / "DerivedData"
        products = derived / "Build/Products"
        app = self.fake_bundle(products / "Debug-iphonesimulator/ShiftReminder.app", "com.kriswu.shiftreminder")
        test = self.fake_bundle(app / "PlugIns/SiteTests.xctest", "com.kriswu.shiftreminder.sitetests")
        target = {"BlueprintName": "SiteTests", "TestHostPath": "__TESTROOT__/Debug-iphonesimulator/ShiftReminder.app",
                  "TestBundlePath": "__TESTHOST__/PlugIns/SiteTests.xctest", "IsUITestBundle": False,
                  "TestingEnvironmentVariables": {"DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphonesimulator"}}
        path = products / "ShiftReminder.xctestrun"
        data = {"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": [{"IsEnabled": True, "TestTargets": [target]}]}
        path.write_bytes(plistlib.dumps(data))
        selectors = ["SiteTests/FixtureTests/testFixture"]
        return derived, app, test, target, path, data, selectors

    def test_fixed_production_plan_and_540_plus_one_inventory(self):
        plan, inventory = P.metadata(HERE.parent)
        self.assertEqual((len(plan["nativeSelectors"]), len(plan["uiSelectors"])), (27, 1))
        self.assertEqual(len(inventory["compiledFiles"]), 541)
        self.assertEqual(sum(r["bytes"] for r in inventory["compiledFiles"]), 311221653)

    def test_cli_has_no_pin_override_secret_network_or_execution_switch(self):
        destinations = {action.dest for action in P.parser()._actions}
        self.assertTrue(destinations.isdisjoint({"plan_sha256", "inventory_sha256", "key", "secret", "run", "skip", "workflow", "upload"}))

    def test_json_rejects_duplicate_keys_and_nonfinite_values(self):
        self.rejection("duplicate-json-key", lambda: P.json_bytes(b'{"a":1,"a":2}'))
        self.rejection("json-number", lambda: P.json_bytes(b'{"a":NaN}'))

    def test_plist_rejects_duplicate_keys(self):
        path = self.put("duplicates.plist", b'<?xml version="1.0"?><plist version="1.0"><dict><key>a</key><string>x</string><key>a</key><string>y</string></dict></plist>')
        self.rejection("duplicate-plist-key", lambda: P.checked_plist(path))

    def test_snapshot_requires_exact_size_and_hash(self):
        path = self.put("safe.bin", b"verified")
        self.assertEqual(P.snapshot(path, maximum=100, size=8)["bytes"], 8)
        self.rejection("file-size", lambda: P.snapshot(path, maximum=100, size=7))
        self.rejection("file-hash", lambda: P.snapshot(path, maximum=100, sha256="0" * 64))

    def test_snapshot_rejects_file_and_parent_symlinks(self):
        real = self.put("real/input.bin")
        self.root.joinpath("link.bin").symlink_to(real)
        self.root.joinpath("linked").symlink_to(real.parent, target_is_directory=True)
        self.rejection("symlink", lambda: P.snapshot(self.root / "link.bin", maximum=100))
        self.rejection("symlink", lambda: P.snapshot(self.root / "linked/input.bin", maximum=100))

    def test_snapshot_detects_same_length_mutation_during_read(self):
        path = self.put("changing.bin", b"before")
        original_read = os.read
        mutated = False
        def change(fd, count):
            nonlocal mutated
            result = original_read(fd, count)
            if result and not mutated:
                mutated = True
                path.write_bytes(b"after!")
            return result
        with mock.patch.object(P.os, "read", side_effect=change):
            self.rejection("file-race", lambda: P.snapshot(path, maximum=100))

    def test_inventory_rejects_traversal_duplicates_bool_size_and_unsorted_names(self):
        good = self.row("A.json", b"a")
        for bad, code in (({**good, "name": "../a"}, "inventory-name"),
                          ({**good, "bytes": True}, "inventory-size"),
                          ({**good, "sha256": "A" * 64}, "inventory-hash")):
            self.rejection(code, lambda bad=bad: P.checked_rows([bad]))
        self.rejection("inventory-order", lambda: P.checked_rows([good, good]))
        self.rejection("inventory-order", lambda: P.checked_rows([self.row("Z.json", b"z"), good]))

    def test_synthetic_resource_closure_rejects_missing_extra_and_changed_bytes(self):
        directory = self.root / "assets"
        path = self.put("assets/A.json", b"a")
        rows = [self.row("A.json", b"a")]
        self.assertEqual(P.flat_resources(directory, rows)["verifiedFiles"], 1)
        extra = self.put("assets/extra.key", b"not-a-real-key")
        with mock.patch.object(P, "snapshot", side_effect=AssertionError("must reject closure before reading any file")):
            self.rejection("resource-closure", lambda: P.flat_resources(directory, rows))
        extra.unlink()
        path.write_bytes(b"b")
        self.rejection("file-hash", lambda: P.flat_resources(directory, rows))
        path.unlink()
        self.rejection("resource-closure", lambda: P.flat_resources(directory, rows))

    def test_valid_external_resource_bytes_do_not_claim_project_installation(self):
        repo = self.root / "repo"
        self.rejection("installation-pending", lambda: P.installation_check(repo, self.root / "external"))
        self.assertTrue(P.installation_check(repo, repo / P.RESOURCE_RELATIVE)["mappedToProject"])

    def test_selector_lexing_ignores_comment_strings_nested_functions_and_other_classes(self):
        source = '''
        /* class Fake: XCTestCase { func testFake() {} } /* nested */ */
        class First: XCTestCase {
          let raw = #"func testFalse() {}"#
          let multi = """ class False: XCTestCase { func testNo() {} } """
          func testOne() throws { func testNested() {} }
        }
        class Second: XCTestCase { func testTwo() {} }
        class Ordinary { func testNotXCTest() {} }
        extension First { func testExtended() {} }
        '''
        self.assertEqual(P.declared_tests(source), {("First", "testOne"), ("First", "testExtended"), ("Second", "testTwo")})

    def test_selector_missing_or_renamed_method_fails(self):
        source = {"tests": {"Tests/SiteTests/Test.swift": "class Fixture: XCTestCase { func testOne() {} }"}}
        plan = {"nativeSelectors": ["SiteTests/Fixture/testMissing"], "uiSelectors": []}
        self.rejection("missing-selector", lambda: P.selectors_check(plan, source))

    def test_xcodegen_cannot_silently_compile_non_swift_input_outside_source_closure(self):
        self.put("App/Verified.swift", b"struct Verified {}")
        unreviewed = self.put("App/Unreviewed.m", b"synthetic extra compile input")
        self.rejection("unsupported-compile-input", lambda: P.swift_files(self.root, "App"))
        unreviewed.unlink()
        self.put("App/Resources/FighterPrivate/SF3H17FX_fixture.metal", b"synthetic copied resource; separate inventory still required")
        self.assertEqual(P.swift_files(self.root, "App"), ["App/Verified.swift"])

    def test_readonly_subprocess_allowlist_rejects_actions_and_extra_arguments(self):
        for argv in (["git", "push"], ["/usr/bin/git", "checkout", "main"],
                     ["/usr/bin/xcodebuild", "build"], ["/usr/bin/xcodebuild", "-version", "build"],
                     ["/usr/bin/xcrun", "simctl", "boot", "anything"]):
            with mock.patch.object(P.subprocess, "run", side_effect=AssertionError("must not execute")):
                self.rejection("command-not-allowed", lambda argv=argv: P.readonly_command(argv))

    def test_linux_never_accepts_synthetic_apple_capability(self):
        with mock.patch.object(P.platform, "system", return_value="Linux"), mock.patch.object(P, "readonly_command", side_effect=AssertionError("no Apple probe on Linux")):
            self.rejection("apple-host-unavailable", lambda: P.host_check("anything", None))

    def test_host_parser_requires_exact_xcode_runtime_and_device_type(self):
        udid = "00000000-1111-2222-3333-444444444444"
        runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        devices = {"runtimes": [{"identifier": runtime, "version": "26.5", "isAvailable": True}],
                   "devices": {runtime: [{"udid": udid, "deviceTypeIdentifier": P.SIMULATOR_TYPE, "isAvailable": True, "state": "Shutdown"}]}}
        self.assertEqual(P.parse_host("Xcode 26.6\nBuild version 17F1\n", devices, udid)["deviceUDID"], udid)
        self.rejection("xcode-version", lambda: P.parse_host("Xcode 26.5\nBuild version 17F1\n", devices, udid))
        wrong = copy.deepcopy(devices)
        wrong["devices"][runtime][0]["deviceTypeIdentifier"] = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
        self.rejection("simulator-device", lambda: P.parse_host("Xcode 26.6\nBuild version 17F1\n", wrong, udid))

    def test_capture_absence_blocks_without_requesting_a_new_workflow(self):
        self.rejection("capture-run-missing", lambda: P.capture_check(None, None, None, "a" * 40))

    def test_synthetic_capture_receipt_cannot_change_commit_attempt_or_external_hash(self):
        value = {"id": 12345, "run_attempt": 1, "head_sha": "a" * 40, "head_branch": P.BRANCH,
                 "repository": {"full_name": P.REPOSITORY}, "html_url": "https://github.com/" + P.REPOSITORY + "/actions/runs/12345",
                 "status": "completed", "conclusion": "skipped"}
        path = self.put("synthetic-GET.json", json.dumps(value).encode())
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        result = P.capture_check("12345", path, checksum, "a" * 40)
        self.assertFalse(result["testResultInherited"])
        self.assertEqual(result["runConclusion"], "skipped")
        self.rejection("capture-run-identity", lambda: P.capture_check("12345", path, checksum, "b" * 40))
        self.rejection("file-hash", lambda: P.capture_check("12345", path, "0" * 64, "a" * 40))
        value["run_attempt"] = 2
        path.write_bytes(json.dumps(value).encode())
        self.rejection("capture-run-identity", lambda: P.capture_check("12345", path, hashlib.sha256(path.read_bytes()).hexdigest(), "a" * 40))

    def test_synthetic_app_resources_reject_duplicate_and_unlisted_private_objects(self):
        app = self.root / "App.app"
        row = self.row("SF3_fixture.json", b"a")
        self.put("App.app/SF3_fixture.json", b"a")
        self.assertEqual(P.app_resources(app, [row])["verifiedFiles"], 1)
        duplicate = self.put("App.app/nested/SF3_fixture.json", b"a")
        self.rejection("compiled-resource-closure", lambda: P.app_resources(app, [row]))
        duplicate.unlink()
        self.put("App.app/SF3_unlisted.json", b"a")
        self.rejection("unlisted-app-resource", lambda: P.app_resources(app, [row]))

    def test_unique_hashed_app_resources_cannot_be_scattered_outside_loader_base(self):
        app = self.root / "App.app"
        rows = [self.row("SF3_A.json", b"a"), self.row("SF3_B.json", b"b")]
        self.put("App.app/SF3_A.json", b"a")
        self.put("App.app/unloaded/SF3_B.json", b"b")
        self.rejection("compiled-resource-location", lambda: P.app_resources(app, rows))

    def test_app_rejects_packaged_key_material_without_reading_it(self):
        app = self.root / "App.app"
        rows = [self.row("SF3_A.json", b"a")]
        self.put("App.app/SF3_A.json", b"a")
        self.put("App.app/fixture.pem", b"synthetic forbidden packaging")
        with mock.patch.object(P, "snapshot", side_effect=AssertionError("must reject filename before reading any bytes")):
            self.rejection("private-material-in-app", lambda: P.app_resources(app, rows))

    def test_synthetic_native_xctestrun_has_one_host_and_no_skip(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        result = P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived)
        self.assertEqual(result["skipCount"], 0)
        target["SkipTestIdentifiers"] = ["FixtureTests/testFixture"]
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-skip", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))

    def test_executable_host_form_is_blocked_without_inventing_testhost_expansion(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        target["TestHostPath"] += "/FixtureBinary"
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-host-layout", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))
        target["TestHostPath"] = target["TestHostPath"].removesuffix("/FixtureBinary")
        target["TestBundlePath"] = "__TESTROOT__/Debug-iphonesimulator/ShiftReminder.app"
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-bundle-layout", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))

    def test_bundle_rejects_plain_text_wrong_macho_kind_and_nonexecutable_mode(self):
        app = self.fake_bundle(self.root / "Fixture.app", "com.example.synthetic")
        executable = app / "FixtureBinary"
        executable.write_bytes(b"ordinary text cannot be a compiled App")
        self.rejection("macho-header", lambda: P.bundle_identity(app, "com.example.synthetic"))
        executable.write_bytes(struct.pack("<8I", 0xfeedfacf, 0x0100000c, 0, 8, 1, 8, 0, 0) + b"SYNTHETI")
        self.rejection("macho-header", lambda: P.bundle_identity(app, "com.example.synthetic"))
        executable.chmod(0o600)
        self.rejection("executable-permission", lambda: P.bundle_identity(app, "com.example.synthetic"))

    def test_xctestrun_rejects_nested_skip_wrong_host_and_path_escape(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        data["TestConfigurations"][0]["SkipTestIdentifiers"] = ["FixtureTests/testFixture"]
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-skip", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))
        self.rejection("xctestrun-path", lambda: P.plan_path("__TESTROOT__/../../outside", path.parent, derived))
        self.rejection("xctestrun-escape", lambda: P.plan_path(str(self.put("outside")), path.parent, derived))

    def test_xctestrun_rejects_partial_only_selection_and_disabled_configuration(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        target["OnlyTestIdentifiers"] = ["FixtureTests/testOther"]
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-selection", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))
        data["TestConfigurations"][0]["IsEnabled"] = False
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-configuration", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))

    def test_xctestrun_rejects_destination_artifacts_and_missing_format_metadata(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        target["UseDestinationArtifacts"] = True
        path.write_bytes(plistlib.dumps(data))
        self.rejection("destination-artifacts", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))
        del target["UseDestinationArtifacts"]
        del data["__xctestrun_metadata__"]
        path.write_bytes(plistlib.dumps(data))
        self.rejection("xctestrun-format", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))

    def test_testing_environment_is_required_and_cannot_override_bundle_or_capture(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        kw = dict(target_name="SiteTests", selectors=selectors, app=app, derived_data=derived)
        del target["TestingEnvironmentVariables"]
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-environment", lambda: P.xctestrun_check(path, **kw))
        target["TestingEnvironmentVariables"] = {"SERPENT_MORPH_DIRECTORY": "/synthetic/other-assets"}
        path.write_bytes(plistlib.dumps(data))
        self.rejection("resource-environment-override", lambda: P.xctestrun_check(path, **kw))
        target["TestingEnvironmentVariables"] = {"FIGHTER_CAPTURE_RUN_ID": "12345"}
        target["EnvironmentVariables"] = {"FIGHTER_CAPTURE_RUN_ID": "54321"}
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-environment-conflict", lambda: P.xctestrun_check(path, **kw))

    def test_testing_environment_injection_must_target_the_verified_bundle(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        target["TestingEnvironmentVariables"]["XCInjectBundle"] = "__TESTHOST__"
        path.write_bytes(plistlib.dumps(data))
        self.rejection("test-injection-target", lambda: P.xctestrun_check(path, target_name="SiteTests", selectors=selectors, app=app, derived_data=derived))

    def test_synthetic_ui_plan_requires_existing_receipt_and_exact_capture_environment(self):
        derived, app, test, target, path, data, selectors = self.fake_native_plan()
        products = derived / "Build/Products"
        runner = self.fake_bundle(products / "Debug-iphonesimulator/ArenaFlowTests-Runner.app", "com.kriswu.shiftreminder.arenaflowtests.xctrunner")
        self.fake_bundle(runner / "PlugIns/ArenaFlowTests.xctest", "com.kriswu.shiftreminder.arenaflowtests")
        target.update({"BlueprintName": "ArenaFlowTests", "IsUITestBundle": True,
                       "TestHostPath": "__TESTROOT__/Debug-iphonesimulator/ArenaFlowTests-Runner.app",
                       "TestBundlePath": "__TESTHOST__/PlugIns/ArenaFlowTests.xctest",
                       "UITargetAppPath": "__TESTROOT__/Debug-iphonesimulator/ShiftReminder.app"})
        path.write_bytes(plistlib.dumps(data))
        kw = dict(target_name="ArenaFlowTests", selectors=["ArenaFlowTests/Fixture/testFixture"], app=app, derived_data=derived)
        self.rejection("capture-run-missing", lambda: P.xctestrun_check(path, **kw))
        capture = {"environment": {"FIGHTER_CAPTURE_SOURCE_SHA": "a" * 40, "FIGHTER_CAPTURE_RUN_ID": "12345", "FIGHTER_CAPTURE_RUN_ATTEMPT": "1"}}
        self.rejection("capture-plan", lambda: P.xctestrun_check(path, capture=capture, **kw))
        target["EnvironmentVariables"] = capture["environment"]
        path.write_bytes(plistlib.dumps(data))
        self.assertEqual(P.xctestrun_check(path, capture=capture, **kw)["selectedCount"], 1)

    def test_reviewed_build_commands_share_derived_data_have_fixed_pins_and_no_execution(self):
        host = {"xcodegen": "/synthetic/xcodegen", "developerDirectory": None}
        commands = P.build_commands(self.root / "repo", self.root / "DerivedData", host)
        self.assertEqual(len(commands), 3)
        for command in commands[1:]:
            argv = command["argv"]
            self.assertEqual(argv[:2], ["/usr/bin/env", "-i"])
            self.assertIn("build-for-testing", argv)
            self.assertIn("CODE_SIGNING_ALLOWED=NO", argv)
            self.assertIn("FIGHTER_ASSET_RELEASE_SHA256=" + P.RELEASE_SHA256, argv)
            self.assertIn("FIGHTER_XUXIAO_PROFILE_SHA256=", argv)
            self.assertEqual(argv[argv.index("-derivedDataPath") + 1], str(self.root / "DerivedData"))
        self.rejection("derived-data-overlap", lambda: P.build_commands(self.root, self.root / "derived", host))

    def test_test_commands_are_review_only_and_existing_results_block_repetition(self):
        derived = self.root / "DerivedData"
        derived.mkdir()
        host = {"developerDirectory": None, "deviceUDID": "00000000-1111-2222-3333-444444444444"}
        plan = {"nativeSelectors": ["SiteTests/Fixture/testFixture"], "uiSelectors": ["ArenaFlowTests/Fixture/testFixture"]}
        native, ui = {"path": "/synthetic/native.xctestrun"}, {"path": "/synthetic/ui.xctestrun"}
        commands = P.test_commands(self.root / "repo", derived, host, native, ui, plan)
        self.assertEqual(len(commands), 2)
        self.assertFalse(any(c["executed"] for c in commands))
        self.assertTrue(all(c["requiredResult"]["skipped"] == 0 for c in commands))
        (derived / "completion-native.xcresult").mkdir()
        self.rejection("result-already-exists", lambda: P.test_commands(self.root / "repo", derived, host, native, ui, plan))


if __name__ == "__main__":
    unittest.main(verbosity=2)
