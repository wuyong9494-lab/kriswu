"""Offline contracts for selection, failure handling and encrypted-only evidence.

No Swift, Xcode, private asset decryption, real device or GitHub write occurs.
The evidence cipher/wrappers are stubbed only in the archive-isolation test;
their established cryptographic implementation is not replaced in production.
"""
import base64
import contextlib
import hashlib
import stat
import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock
import zipfile

import fighter_h17_source_native as native




class H17SourceNativeContractTests(unittest.TestCase):

    def setUp(self):
        self.rows, self.hashes = native.selected_inventory()
        self.expected = [row["identifier"] for row in self.rows]
        self.summary = {"totalTestCount": native.EXPECTED_COUNT, "passedTests": native.EXPECTED_COUNT, "failedTests": 0,
                        "skippedTests": 0, "result": "Passed"}
        self.results = {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"}
            for name in self.expected]}]}


    def testOnlyNinetySevenSyntheticMethodsAreSelectedAndFiveResourceMethodsExplicitlyExcluded(self):
        self.assertEqual(len(self.expected), 97)
        self.assertEqual(len(set(self.expected)), 97)
        self.assertTrue(all(row["scenarioType"] == "synthetic fixture contract" for row in self.rows))
        excluded = native.excluded_inventory()
        self.assertEqual(len(excluded), 5)
        self.assertTrue(set(excluded).isdisjoint(self.expected))
        self.assertTrue(all("DuelTriadInstalledSourceTests/" in item for item in excluded))
        self.assertEqual(len(self.hashes), 9)
        native.verify_results(self.summary, self.results, self.expected)


    def testEventRequiresExactMessageBranchWorkflowShaAndFirstAttempt(self):
        self.assertEqual(native.BRANCH, "refs/heads/codex/fighter-visual-acceptance-20261113-1200")
        sha = "a" * 40
        env = {"GITHUB_SHA": sha, "GITHUB_REPOSITORY": native.REPOSITORY,
               "GITHUB_REF": native.BRANCH, "GITHUB_EVENT_NAME": "push", "GITHUB_RUN_ATTEMPT": "1",
               "GITHUB_WORKFLOW_REF": native.REPOSITORY + "/" + native.WORKFLOW + "@" + native.BRANCH}
        event = {"ref": native.BRANCH, "head_commit": {"id": sha, "message": native.COMMIT_MESSAGE}}
        native.validate_event(env, event, sha)
        for key, value in (("GITHUB_REF", "refs/heads/main"), ("GITHUB_EVENT_NAME", "workflow_dispatch"),
                           ("GITHUB_REF", "refs/heads/codex/fighter-pangu-native-20261114"),
                           ("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_REPOSITORY", "someone/fork"),
                           ("GITHUB_WORKFLOW_REF", "another-workflow"), ("GITHUB_SHA", "b" * 40)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                native.validate_event(dict(env, **{key: value}), event, sha)
        for message in (native.COMMIT_MESSAGE.lower(), native.COMMIT_MESSAGE + "\n", "Verify Pangu native bindings"):
            wrong = copy.deepcopy(event)
            wrong["head_commit"]["message"] = message
            with self.subTest(message=message), self.assertRaises(ValueError):
                native.validate_event(env, wrong, sha)
        wrong = copy.deepcopy(event)
        wrong["head_commit"]["id"] = "b" * 40
        with self.assertRaises(ValueError):
            native.validate_event(env, wrong, sha)


    def testZeroTestsSkippedFailuresAndNonIntegerSummaryCannotPass(self):
        for key, value in (("totalTestCount", 0), ("totalTestCount", -1), ("passedTests", 0), ("failedTests", 1),
                           ("skippedTests", 1), ("failedTests", False), ("passedTests", "96"),
                           ("result", "Failed")):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                native.verify_results(dict(self.summary, **{key: value}), self.results, self.expected)


    def testDuplicateMissingExtraOrSkippedMethodsCannotPassMatchingSummaryCounts(self):
        for kind in ("duplicate", "missing", "extra", "skipped", "failed", "unknown"):
            result = copy.deepcopy(self.results)
            nodes = result["testNodes"][0]["children"]
            if kind == "duplicate":
                nodes[-1] = copy.deepcopy(nodes[0])
            elif kind == "missing":
                nodes.pop()
            elif kind == "extra":
                nodes.append(copy.deepcopy(nodes[0]))
            elif kind in ("skipped", "failed"):
                nodes[-1]["result"] = kind.title()
            else:
                nodes[-1]["nodeIdentifier"] = "SiteTests/OtherTests/testUnexpected()"
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                native.verify_results(self.summary, result, self.expected)


    def testNativeFailureRetainsOriginalExitEvenWhenAnExporterAlsoFails(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            root = Path(folder)
            (root / "selected.xcresult").mkdir()
            (root / "selected.xcresult/Info.plist").write_text("synthetic result marker")
            native.write_json(root / "simulator.json", {"udid": "synthetic-device"})
            (root / "xctestrun-path.txt").write_text("synthetic.xctestrun")
            calls = []

            def command(_command, label, _timeout, **_kwargs):
                calls.append(label)
                return {"selected-native": 65, "result-summary": 1, "result-tests": 0}[label]

            with mock.patch.object(native, "work", return_value=root), \
                    mock.patch.object(native, "verify_identity", return_value={"selectors": self.rows}), \
                    mock.patch.object(native, "assert_no_private_resources"), \
                    mock.patch.object(native, "run_logged", side_effect=command), \
                    self.assertRaises(native.PhaseFailure) as caught:
                native.test()
            self.assertEqual(caught.exception.code, 65)
            self.assertEqual(calls, ["selected-native", "result-summary", "result-tests"])
            self.assertEqual(native.read_json(root / "native-process.json")["exitCode"], 65)
            self.assertFalse((root / "native-ok.txt").exists())


    def testResourceKeysCannotEnterBuildTestOrEvidencePhases(self):
        for name in native.KEY_NAMES:
            with self.subTest(name=name), mock.patch.dict(os.environ, {name: "synthetic-secret"}, clear=True), \
                    self.assertRaises(ValueError):
                native.no_resource_keys()


    def testFailedBuildLogEntersSealedArchiveWithoutAssetsProductsOrRawResults(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            root = Path(folder)
            (root / "native-build-stderr.log").write_text("SYNTHETIC compiler error: contract mismatch\n")
            native.write_json(root / "build-failure.json", {"phase": "build", "detail": "synthetic failure"})
            for directory in ("derived/ShiftReminder.app", "selected.xcresult", "attachments"):
                (root / directory).mkdir(parents=True)
                (root / directory / "private-content.bin").write_bytes(b"synthetic must not archive")
            (root / "attachments/partial.json").write_text('{"syntheticCapture": true}')
            public = root / "recipient.public.pem"
            public.write_text("synthetic public recipient")
            archived = {}
            envelope, visual = types.ModuleType("fighter_private_model"), types.ModuleType("fighter_visual_acceptance")

            def seal(archive, destination):
                with zipfile.ZipFile(archive) as value:
                    archived.update({name: value.read(name) for name in value.namelist()})
                destination.write_bytes(b"synthetic ciphertext; crypto is separately verified")

            envelope.seal_evidence_file = seal
            visual.EXISTING_RECIPIENT = "synthetic existing public recipient"
            visual.wrap_key = lambda _key, _public, destination: destination.write_bytes(b"synthetic wrapped key")
            output = io.StringIO()
            with mock.patch.dict(sys.modules, {"fighter_private_model": envelope, "fighter_visual_acceptance": visual}), \
                    mock.patch.object(native, "work", return_value=root), mock.patch.object(native, "RECIPIENT", public), \
                    mock.patch.object(native, "verify_identity", return_value={}), \
                    mock.patch.object(native, "public_summary", return_value={"nativeExactSetPassed": False}), \
                    mock.patch.object(native, "recipient_digest", return_value=native.RECIPIENT_SPKI_SHA256), \
                    contextlib.redirect_stdout(output):
                native.seal()
            self.assertIn(b"compiler error: contract mismatch", archived["metadata/native-build-stderr.log"])
            self.assertIn("metadata/build-failure.json", archived)
            self.assertIn("attachments/partial.json", archived)
            self.assertFalse(any("private-content" in name or name.startswith(("derived/", "selected.xcresult/"))
                                 for name in archived))
            self.assertEqual(len(list((root / "published").iterdir())), 4)
            self.assertFalse((root / "private-new-evidence.zip").exists())
            self.assertNotIn("compiler error", output.getvalue())
            self.assertNotIn("FIGHTER_LIU_MODEL_KEY", os.environ)


    def testCleanupNeverDeletesAnotherSimulatorAndStillRemovesPrivateLogs(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            base = Path(folder)
            native.write_json(base / "simulator.json", {"udid": "owned-id", "name": "owned-name"})
            (base / "private.log").write_text("synthetic private diagnostic")
            catalog = {"devices": {"iOS": [{"udid": "owned-id", "name": "someone-else", "state": "Booted"}]}}
            with mock.patch.object(native, "ROOT", base / "repo"), mock.patch.object(native, "work", return_value=base), \
                    mock.patch.object(native, "verify_identity", return_value={}), \
                    mock.patch.object(native, "public_summary", return_value={"nativeExactSetPassed": False}), \
                    mock.patch.object(native.subprocess, "check_output", return_value=json.dumps(catalog)), \
                    mock.patch.object(native, "run_logged") as commands, self.assertRaises(native.PhaseFailure):
                native.cleanup()
            commands.assert_not_called()
            self.assertFalse((base / "private.log").exists())
            self.assertFalse(native.read_json(base / "public-summary.json")["cleanupComplete"])


    def testSourceOnlyResourceGateAllowsEmptyDirectoryButRejectsMediaSymlinksAndReleaseActivation(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            root = Path(folder)
            native.assert_no_private_resources(root)
            directory = root / "App/Resources/FighterPrivate"
            directory.mkdir(parents=True)
            native.assert_no_private_resources(root)
            media = directory / "Synthetic_NotAllowed.glb"
            media.write_bytes(b"fixture")
            with self.assertRaises(ValueError): native.assert_no_private_resources(root)
            media.unlink(); directory.rmdir()
            elsewhere = root / "elsewhere"; elsewhere.mkdir()
            directory.symlink_to(elsewhere, target_is_directory=True)
            with self.assertRaises(ValueError): native.assert_no_private_resources(root)
            directory.unlink()
            pack = root / "App/Resources/arena-original-resources.arenapack"
            pack.write_bytes(b"fixture")
            with self.assertRaises(ValueError): native.assert_no_private_resources(root)
            pack.unlink()
            with mock.patch.dict(os.environ, {"FIGHTER_ASSET_RELEASE_SHA256": "a" * 64}), self.assertRaises(ValueError):
                native.assert_no_private_resources(root)

    def testWorkflowHasNoEnvironmentSecretStageOrPublicationAndUsesOneExactEntry(self):
        text = (native.ROOT / native.WORKFLOW).read_text()
        self.assertIn("contents: read", text)
        self.assertIn(native.COMMIT_MESSAGE, text)
        self.assertIn("github.run_attempt == 1", text)
        self.assertNotIn("environment:", text)
        self.assertNotIn("secrets.", text)
        self.assertNotIn("workflow_dispatch", text)
        self.assertNotIn("fighter_h17_d19_native.py", text)
        self.assertNotIn("TestFlight", text)
        for phase in ["prepare", "tools", "build", "simulator", "test", "export", "seal", "cleanup", "report"]:
            self.assertEqual(text.count("run: python3 .github/scripts/fighter_h17_source_native.py " + phase + "\n"), 1)
        self.assertNotIn(" source_native.py stage", text)
        self.assertIn("steps.prepare.outcome == 'success'", text)
        self.assertEqual(native.EXPECTED_COUNT, 97)


if __name__ == "__main__":
    unittest.main()
