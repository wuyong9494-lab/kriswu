#!/usr/bin/env python3
"""Bounded new-helper tests. No Apple build, resource key, decryption or old suite."""
import copy
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

import fighter_shared_root_native as native


def result_fixture(selectors=native.SELECTORS):
    return (
        {"totalTestCount": len(selectors), "passedTests": len(selectors),
         "failedTests": 0, "skippedTests": 0, "result": "Passed"},
        {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "/".join(s.split("/")[1:]) + "()",
                        "result": "Passed"} for s in selectors]},
    )


def event_fixture():
    sha = "a" * 40
    environment = {
        "GITHUB_SHA": sha, "GITHUB_REPOSITORY": native.REPOSITORY, "GITHUB_REF": native.BRANCH,
        "GITHUB_WORKFLOW_REF": native.REPOSITORY + "/" + native.WORKFLOW + "@" + native.BRANCH,
        "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "123", "GITHUB_EVENT_NAME": "push",
    }
    return environment, {"ref": native.BRANCH, "head_commit": {"id": sha, "message": native.COMMIT_MESSAGE}}


class SharedRootNativeHelperTests(unittest.TestCase):
    def test_actual_reviewed_inventory_has_nine_methods_and_373_resources(self):
        legacy, base, delta = native.manifests()
        rows = native.final_inventory(base, delta, legacy.resource_records())
        self.assertEqual(len(rows), 373)
        self.assertEqual(len(native.selected_inventory()), 9)
        self.assertEqual(len(native.UI_SELECTORS), 1)
        self.assertTrue(all("/DuelTriadInstalledSourceTests/" not in s for s in native.SELECTORS))
        native.pinned(native.MODEL_TEST, native.MODEL_TEST_SHA)
        native.pinned(native.UI_TEST, native.UI_TEST_SHA)

    def test_unreviewed_baseline_collision_is_rejected_before_resource_use(self):
        legacy, base, delta = native.manifests()
        rows = legacy.resource_records()
        rows[0] = dict(rows[0], file=next(r["file"] for r in base["files"]
                                        if r["file"] not in {r["file"] for r in rows}))
        with self.assertRaises(ValueError):
            native.final_inventory(base, delta, rows)

    def test_wrong_independent_delta_pin_is_rejected(self):
        with patch.object(native, "DELTA_PACK_SHA", "0" * 64), self.assertRaises(ValueError):
            native.manifests()

    def test_native_and_ui_results_are_separate_exact_sets(self):
        for selectors in (native.SELECTORS, native.UI_SELECTORS):
            summary, data = result_fixture(selectors)
            native.verify_results(summary, data, selectors)
        summary, data = result_fixture(native.SELECTORS + native.UI_SELECTORS)
        with self.assertRaises(ValueError):
            native.verify_results(summary, data, native.SELECTORS + native.UI_SELECTORS)

    def test_completed_skipped_failed_missing_or_noninteger_counts_never_pass(self):
        baseline, data = result_fixture()
        for key, value in (("result", "Completed"), ("skippedTests", 1), ("failedTests", 1),
                           ("passedTests", 8), ("totalTestCount", 117), ("skippedTests", False)):
            with self.subTest(key=key, value=value):
                summary = dict(baseline, **{key: value})
                with self.assertRaises(ValueError):
                    native.verify_results(summary, data)
        summary = dict(baseline)
        del summary["skippedTests"]
        with self.assertRaises(ValueError):
            native.verify_results(summary, data)

    def test_duplicate_missing_extra_or_substituted_method_is_rejected(self):
        summary, original = result_fixture()
        changes = (
            original["testNodes"][:-1],
            original["testNodes"] + [original["testNodes"][0]],
            original["testNodes"][:-1] + [original["testNodes"][0]],
            original["testNodes"][:-1] + [{"nodeType": "Test Case",
                "nodeIdentifier": "OldSuite/testPreviouslyPassed()", "result": "Passed"}],
        )
        for nodes in changes:
            with self.subTest(nodes=len(nodes)), self.assertRaises(ValueError):
                native.verify_results(summary, {"testNodes": nodes})

    def test_skipped_leaf_cannot_hide_behind_successful_summary(self):
        summary, original = result_fixture()
        for status in ("Skipped", "Failed", "Not Run", "Completed", None):
            data = copy.deepcopy(original)
            data["testNodes"][-1]["result"] = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                native.verify_results(summary, data)

    def test_only_explicit_current_branch_first_attempt_trigger_is_accepted(self):
        env, event = event_fixture()
        native.validate_event(env, event, env["GITHUB_SHA"])
        manual = dict(env, GITHUB_EVENT_NAME="workflow_dispatch")
        native.validate_event(manual, {"inputs": {"source_sha": env["GITHUB_SHA"]}}, env["GITHUB_SHA"])
        for changed in (dict(env, GITHUB_RUN_ATTEMPT="2"), dict(env, GITHUB_EVENT_NAME="pull_request"),
                        dict(env, GITHUB_REF="refs/heads/main"), dict(env, GITHUB_REPOSITORY="other/repo")):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                native.validate_event(changed, event, env["GITHUB_SHA"])
        with self.assertRaises(ValueError):
            native.validate_event(manual, {"inputs": {"source_sha": "b" * 40}}, env["GITHUB_SHA"])

    def test_native_failure_code_survives_successful_result_exports(self):
        summary, data = result_fixture()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "build-ok.txt").write_text("verified fixture")
            (root / "simulator.json").write_text(json.dumps({"udid": "fixture"}))
            (root / "xctestrun-path.txt").write_text("fixture.xctestrun")
            (root / "native.xcresult").mkdir()
            (root / "native.xcresult/Info.plist").write_text("fixture")
            commands = []

            def run(command, label, timeout, **kwargs):
                commands.append(command)
                output = kwargs.get("output_name")
                if output:
                    (root / output).write_text(json.dumps(summary if output.endswith("summary.json") else data))
                    return 0
                return 65

            with patch.object(native, "work", return_value=root), patch.object(native, "identity"), \
                    patch.object(native, "no_resource_keys"), patch.object(native, "run_logged", side_effect=run):
                with self.assertRaises(native.PhaseFailure) as failed:
                    native.test()
                self.assertEqual(failed.exception.code, 65)
                with self.assertRaises(FileExistsError):
                    native.test()
            record = json.loads((root / "native-process.json").read_text())
            self.assertEqual(record["exitCode"], 65)
            self.assertEqual(record["exports"], {"summary": 0, "tests": 0})
            self.assertFalse((root / "native-ok.txt").exists())
            selectors = [s.removeprefix("-only-testing:") for s in commands[0] if s.startswith("-only-testing:")]
            self.assertEqual(tuple(selectors), native.SELECTORS)
            self.assertEqual(len(commands), 3)

    def test_resource_keys_are_removed_from_unrelated_child_processes(self):
        with tempfile.TemporaryDirectory() as folder:
            process = Mock()
            process.wait.return_value = 0
            with patch.dict(os.environ, {k: "synthetic-key-do-not-log" for k in native.KEY_NAMES}, clear=True), \
                    patch.object(native, "work", return_value=Path(folder)), \
                    patch.object(native.subprocess, "Popen", return_value=process) as start:
                native.run_logged(["fixture-command"], "fixture", 1, key_names=(native.KEY_NAMES[2],))
                passed = start.call_args.kwargs["env"]
                self.assertEqual(set(passed) & set(native.KEY_NAMES), {native.KEY_NAMES[2]})
                native.run_logged(["fixture-command"], "fixture-no-key", 1)
                self.assertFalse(set(start.call_args.kwargs["env"]) & set(native.KEY_NAMES))

    def model_attachment(self, root, device):
        label = "shared-root-installed-model-report"
        raw = {"releaseSHA256": native.RELEASE_SHA, "characters": [{}, {}], "liuVictimMotions": [{}, {}, {}]}
        (root / "fixture.json").write_text(json.dumps(raw))
        group = {"testIdentifier": native.SELECTORS[-1], "attachments": [{
            "exportedFileName": "fixture.json", "suggestedHumanReadableName": label + ".json",
            "deviceId": device["udid"], "deviceName": device["name"]}]}
        (root / "manifest.json").write_text(json.dumps([group]))
        return group

    def test_model_attachment_requires_exact_selector_and_simulator(self):
        with tempfile.TemporaryDirectory() as folder:
            root, device = Path(folder), {"udid": "fixture-device", "name": "fixture-simulator"}
            baseline = self.model_attachment(root, device)
            result = native.attachment_inventory(root, device, "native")
            self.assertTrue(result["exactMethodAndSimulatorOwnership"])
            for field, value in (("deviceId", "other-device"), ("deviceName", "other-simulator")):
                group = copy.deepcopy(baseline)
                group["attachments"][0][field] = value
                (root / "manifest.json").write_text(json.dumps([group]))
                with self.assertRaises(ValueError):
                    native.attachment_inventory(root, device, "native")
            group = copy.deepcopy(baseline)
            group["testIdentifier"] = native.SELECTORS[0]
            (root / "manifest.json").write_text(json.dumps([group]))
            with self.assertRaises(ValueError):
                native.attachment_inventory(root, device, "native")

    def test_incomplete_attachment_set_is_retained_but_not_certified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            evidence = root / "native-attachments"
            evidence.mkdir()
            (evidence / "manifest.json").write_text("[]")
            with self.assertRaises(ValueError):
                native.attachment_inventory(evidence, {"udid": "fixture", "name": "fixture"}, "native")
            with patch.object(native, "work", return_value=root):
                self.assertEqual(len(native.bounded_attachments()), 1)
            self.assertTrue((evidence / "manifest.json").is_file())

    def test_failed_ui_can_preserve_products_without_reexecuting_native(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            products = root / "derived/Build/Products"
            products.mkdir(parents=True)
            (products / "fixture.xctestrun").write_text("Synthetic non-Apple test fixture")
            (root / "native-ok.txt").write_text("synthetic exact native result")
            (root / "native-summary.json").write_text(json.dumps(result_fixture()[0]))
            (root / "xctestrun-path.txt").write_text(str(products / "fixture.xctestrun"))
            with patch.object(native, "work", return_value=root), patch.dict(os.environ, {"GITHUB_SHA": "a" * 40}):
                archive = native.reusable_ui_products()
            self.assertTrue(archive.is_file())
            receipt = json.loads((root / "ui-recovery.json").read_text())
            self.assertFalse(receipt["nativeNineReexecutionAllowed"])
            self.assertFalse(receipt["available"])  # Packaging is not encrypted publication.
            with zipfile.ZipFile(archive) as packed:
                info = json.loads(packed.read("reuse-identity.json"))
                self.assertEqual(info["uiSelectorOnly"], native.UI_SELECTORS[0])
                self.assertFalse(info["testExecutionAttemptedByRecovery"])

    def test_successful_ui_does_not_duplicate_products_into_recovery(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("native-ok.txt", "ui-ok.txt", "ui-attachments-ok.json"):
                (root / name).write_text("fixture")
            with patch.object(native, "work", return_value=root):
                self.assertIsNone(native.reusable_ui_products())
            self.assertFalse((root / "private-ui-recovery.zip").exists())

    def test_cleanup_removes_owned_plaintext_even_when_identity_check_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            run, repo = root / "run", root / "repo"
            run.mkdir()
            (run / "published").mkdir()
            (run / "published/keep.enc").write_text("synthetic ciphertext")
            (run / "private.log").write_text("synthetic private log")
            resources = repo / "App/Resources/FighterPrivate"
            resources.mkdir(parents=True)
            (resources / "fixture.wav").write_text("synthetic resource")
            (repo / "project.shared-root-native.yml").write_text("synthetic spec")
            with patch.object(native, "work", return_value=run), patch.object(native, "ROOT", repo), \
                    patch.object(native, "identity", side_effect=ValueError("synthetic integrity failure")), \
                    patch.object(native, "no_resource_keys"):
                with self.assertRaises(native.PhaseFailure):
                    native.cleanup()
            self.assertFalse(resources.exists())
            self.assertFalse((run / "private.log").exists())
            self.assertTrue((run / "published/keep.enc").is_file())
            self.assertFalse(json.loads((run / "public-summary.json").read_text())["cleanupComplete"])


if __name__ == "__main__":
    unittest.main()
