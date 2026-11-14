#!/usr/bin/env python3
"""Only new fixed-scope gates; mocks Apple execution and never uses asset keys."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


HELPER = Path(__file__).with_name("fighter_shared_root_native.py")


def load_scope(scope):
    spec = importlib.util.spec_from_file_location("review_" + scope.replace("-", "_"), HELPER)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(os.environ, {"FIGHTER_SHARED_ROOT_SCOPE": scope}):
        spec.loader.exec_module(module)
    return module


native = load_scope("material-followup-six")
initial = load_scope("initial-nine")


def results(selectors):
    return ({"totalTestCount": len(selectors), "passedTests": len(selectors),
             "failedTests": 0, "skippedTests": 0, "result": "Passed"},
            {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "/".join(s.split("/")[1:]) + "()",
                            "result": "Passed"} for s in selectors]})


def mutate_record(rows, excluded):
    output = []
    changed = False
    for row in rows.splitlines():
        meta, name = row.split(b"\t", 1)
        if not changed and name.decode() not in excluded:
            mode, kind, _ = meta.split()
            row = b" ".join((mode, kind, b"0" * 40)) + b"\t" + name
            changed = True
        output.append(row + b"\n")
    assert changed
    return b"".join(output)


class SharedRootMaterialFollowupTests(unittest.TestCase):
    def test_fixed_six_selectors_exclude_five_prior_passes_and_preserve_initial_history(self):
        self.assertEqual(len(initial.selected_inventory()), 9)
        self.assertEqual(len(native.selected_inventory()), 6)
        self.assertEqual(len(native.UI_SELECTORS), 1)
        self.assertEqual(initial.UI_SELECTORS, native.UI_SELECTORS)
        failed_four = set(initial.SELECTORS) - set(initial.PREVIOUS_PASSED_SELECTORS)
        new_two = {"SiteTests/DuelTriadRuntimeUniformTests/" + method for method in native.UNIFORM_METHODS}
        self.assertEqual(set(native.SELECTORS), failed_four | new_two)
        self.assertFalse(set(native.SELECTORS) & set(initial.PREVIOUS_PASSED_SELECTORS))
        self.assertEqual(native.EXPECTED_ATTACHMENTS["native"]["shared-root-installed-model-report"][0],
                         native.MODEL_SELECTOR)
        self.assertEqual(native.RELEASE_SHA, initial.RELEASE_SHA)
        self.assertEqual(native.DEPENDENCY_PINS, initial.DEPENDENCY_PINS)

    def test_scope_cannot_use_original_workflow_another_message_or_unknown_selector_config(self):
        source = "a" * 40
        environment = {"FIGHTER_SHARED_ROOT_SCOPE": native.SCOPE, "GITHUB_SHA": source,
            "GITHUB_REPOSITORY": native.REPOSITORY, "GITHUB_REF": native.BRANCH,
            "GITHUB_WORKFLOW_REF": native.REPOSITORY + "/" + native.WORKFLOW + "@" + native.BRANCH,
            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "123", "GITHUB_EVENT_NAME": "push"}
        event = {"ref": native.BRANCH, "head_commit": {"id": source, "message": native.COMMIT_MESSAGE}}
        native.validate_event(environment, event, source)
        for change in ({"FIGHTER_SHARED_ROOT_SCOPE": initial.SCOPE}, {"GITHUB_RUN_ATTEMPT": "2"},
                       {"GITHUB_WORKFLOW_REF": native.REPOSITORY + "/" + initial.WORKFLOW + "@" + native.BRANCH}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                native.validate_event(dict(environment, **change), event, source)
        bad = copy.deepcopy(event)
        bad["head_commit"]["message"] = initial.COMMIT_MESSAGE
        with self.assertRaises(ValueError):
            native.validate_event(environment, bad, source)
        with self.assertRaises(ValueError):
            load_scope("any-tests")

    def test_only_reviewed_material_and_one_new_test_may_differ_from_the_prior_trees(self):
        entries = {name: value for name, value in native.REVIEWED_ENTRIES.items() if name != "App"}
        app = subprocess.check_output(["git", "ls-tree", "-r", "HEAD", "App"], cwd=native.ROOT)
        tests = subprocess.check_output(["git", "ls-tree", "-r", "HEAD", "Tests"], cwd=native.ROOT)
        # Model an eventual commit that adds the reviewed test; do not stage or
        # create a commit in this lightweight source-gate check.
        names = {line.split(b"\t", 1)[1].decode() for line in tests.splitlines()}
        if native.UNIFORM_TEST not in names:
            tests += b"100644 blob " + b"f" * 40 + b"\t" + native.UNIFORM_TEST.encode() + b"\n"
        native.validate_source_trees(entries, tests, app)
        with self.assertRaises(ValueError):
            native.validate_source_trees(entries, tests, mutate_record(app, {native.MATERIAL_SOURCE}))
        with self.assertRaises(ValueError):
            native.validate_source_trees(entries, mutate_record(tests, native.reviewed_test_pins()), app)
        with self.assertRaises(ValueError):
            native.validate_source_trees(dict(entries, Sources="0" * 40), tests, app)
        without_new = b"".join(line + b"\n" for line in tests.splitlines()
                                if line.split(b"\t", 1)[1].decode() != native.UNIFORM_TEST)
        with self.assertRaises(ValueError):
            native.validate_source_trees(entries, without_new, app)

    def test_material_and_new_test_require_final_exact_reviewed_byte_pins(self):
        native.pin_scope_sources()
        for field in ("MATERIAL_SOURCE_SHA", "UNIFORM_TEST_SHA"):
            for value in ("PENDING_REVIEW", "0" * 64):
                with self.subTest(field=field, value=value), patch.object(native, field, value), \
                        self.assertRaises(ValueError):
                    native.pin_scope_sources()

    def test_six_exact_passes_cannot_hide_skip_duplicate_or_reexecution_of_prior_contract(self):
        summary, data = results(native.SELECTORS)
        native.verify_results(summary, data)
        for key, value in (("totalTestCount", 9), ("passedTests", 5), ("skippedTests", 1), ("result", "Completed")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                native.verify_results(dict(summary, **{key: value}), data)
        for replacement in (data["testNodes"][0], {"nodeType": "Test Case", "result": "Passed",
                "nodeIdentifier": "/".join(native.PREVIOUS_PASSED_SELECTORS[0].split("/")[1:]) + "()"}):
            changed = copy.deepcopy(data)
            changed["testNodes"][-1] = replacement
            with self.assertRaises(ValueError):
                native.verify_results(summary, changed)
        old_summary, old_data = results(initial.SELECTORS)
        with self.assertRaises(ValueError):
            native.verify_results(old_summary, old_data, initial.SELECTORS)

    def test_commands_select_six_and_ui_once_without_retry_or_longer_timeouts(self):
        for ui, selectors in ((False, native.SELECTORS), (True, native.UI_SELECTORS)):
            with self.subTest(ui=ui), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder)
                phase = "ui" if ui else "native"
                summary, data = results(selectors)
                (directory / "build-ok.txt").write_text("synthetic verified build")
                (directory / "simulator.json").write_text(json.dumps({"udid": "fixture"}))
                (directory / "xctestrun-path.txt").write_text("fixture.xctestrun")
                (directory / (phase + ".xcresult")).mkdir()
                (directory / (phase + ".xcresult/Info.plist")).write_text("fixture")
                commands = []

                def run(command, label, timeout, **kwargs):
                    commands.append((command, timeout))
                    output = kwargs.get("output_name")
                    if output:
                        (directory / output).write_text(json.dumps(summary if output.endswith("summary.json") else data))
                    return 0

                with patch.object(native, "work", return_value=directory), patch.object(native, "identity"), \
                        patch.object(native, "no_resource_keys"), patch.object(native, "run_logged", side_effect=run), \
                        patch("builtins.print"):
                    native.execute_tests(ui=ui)
                    with self.assertRaises(FileExistsError):
                        native.execute_tests(ui=ui)
                command, timeout = commands[0]
                self.assertEqual(tuple(arg.removeprefix("-only-testing:") for arg in command
                                       if arg.startswith("-only-testing:")), selectors)
                self.assertEqual(timeout, 360 if ui else 720)
                for flag in ("-test-iterations", "-retry-tests-on-failure", "-run-tests-until-failure"):
                    self.assertNotIn(flag, command)
                self.assertEqual(len(commands), 3)

    def test_public_summary_keeps_five_historical_passes_outside_current_six_counts(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            (directory / "identity.json").write_text(json.dumps({"sourceSHA": "a" * 40, "runID": "123", "attempt": "1"}))
            with patch.object(native, "work", return_value=directory):
                result = native.public_summary()
        self.assertEqual(result["expectedNativeMethods"], 6)
        self.assertEqual(result["methodScope"], {"installedAudio": 3, "syntheticContracts": 0,
                                              "installedModels": 1, "runtimeUniformRegressions": 2})
        self.assertNotIn("nativeObservedCounts", result)
        self.assertFalse(result["nativeExactSetPassed"])
        evidence = result["preservedPriorEvidence"][0]
        self.assertEqual(evidence["runID"], "43644209347")
        self.assertEqual(evidence["passedMethods"], 5)
        self.assertFalse(evidence["selectedAgain"])
        self.assertFalse(evidence["countsBelongToCurrentRun"])

    def test_new_workflow_has_bound_scope_and_preserves_stage_only_secrets_and_budgets(self):
        previous = (native.ROOT / initial.WORKFLOW).read_text()
        current = (native.ROOT / native.WORKFLOW).read_text()
        self.assertEqual(native.digest(native.ROOT / initial.WORKFLOW),
                         "fcd92bc797d97f892d8fc26a94f28b0d49ca94ab1a87014f6bade2bc70be0fdb")
        self.assertIn("FIGHTER_SHARED_ROOT_SCOPE: material-followup-six", current)
        self.assertIn(native.COMMIT_MESSAGE, current)
        self.assertNotIn(initial.COMMIT_MESSAGE, current)
        self.assertEqual([line.strip() for line in previous.splitlines() if "timeout-minutes:" in line],
                         [line.strip() for line in current.splitlines() if "timeout-minutes:" in line])
        stage = current.split("      - name: Authenticate", 1)[1].split("      - name: Build", 1)[0]
        for key in native.KEY_NAMES:
            self.assertEqual(stage.count("${{ secrets." + key + " }}"), 1)
            self.assertEqual(current.count("${{ secrets." + key + " }}"), 1)
        self.assertIn("cancel-in-progress: false", current)
        self.assertIn("environment: fighter-private-assets", current)
        self.assertIn("steps.seal.outcome == 'success'", current)
        self.assertIn("fighter_shared_root_native.py cleanup", current)


if __name__ == "__main__":
    unittest.main()
