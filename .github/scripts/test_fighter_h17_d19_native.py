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

import fighter_h17_d19_native as native


class H17D19NativeContractTests(unittest.TestCase):
    def setUp(self):
        self.rows, self.hashes = native.selected_inventory()
        self.expected = [row["identifier"] for row in self.rows]
        self.summary = {"totalTestCount": native.EXPECTED_COUNT, "passedTests": native.EXPECTED_COUNT, "failedTests": 0,
                        "skippedTests": 0, "result": "Passed"}
        self.results = {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": "Passed"}
            for name in self.expected]}]}

    def testInventoryContainsTheExactReviewedNativeSetWithoutOldCatalogAssertions(self):
        self.assertEqual(len(self.expected), 102)
        self.assertEqual(len(set(self.expected)), 102)
        self.assertEqual(sum(row["scenarioType"] == "synthetic fixture contract" for row in self.rows), 97)
        self.assertEqual(sum(row["scenarioType"] == "authenticated source release" for row in self.rows), 5)
        self.assertEqual(len(self.hashes), 9)
        self.assertTrue(all(len(name.split("/")) == 3 for name in self.expected))
        self.assertFalse(any("DuelLifecycleTests/" in name for name in self.expected))

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

    def testSuccessfulModernXCResultAcceptsFullAndUnqualifiedMethodIdentifiers(self):
        native.verify_results(self.summary, self.results, self.expected)
        short = copy.deepcopy(self.results)
        for node in short["testNodes"][0]["children"]:
            node["nodeIdentifier"] = node["nodeIdentifier"].removeprefix("SiteTests/")
        native.verify_results(self.summary, short, self.expected)

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

    def testMalformedResultTreeAndDuplicateExpectedSetCannotPass(self):
        for result in ({}, {"testNodes": None}, {"testNodes": ["test"]},
                       {"testNodes": [{"nodeType": "Test Case", "result": "Passed"}]},
                       {"testNodes": [{"nodeType": "Test Suite", "children": {}}]}):
            with self.subTest(result=result), self.assertRaises(ValueError):
                native.verify_results(self.summary, result, self.expected)
        with self.assertRaises(ValueError):
            native.verify_results(self.summary, self.results, self.expected[:-1] + [self.expected[0]])

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
                    mock.patch.object(native, "run_logged", side_effect=command), \
                    self.assertRaises(native.PhaseFailure) as caught:
                native.test()
            self.assertEqual(caught.exception.code, 65)
            self.assertEqual(calls, ["selected-native", "result-summary", "result-tests"])
            self.assertEqual(native.read_json(root / "native-process.json")["exitCode"], 65)
            self.assertFalse((root / "native-ok.txt").exists())

    def testSuccessfulProcessWithNoResultBundleCannotPass(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            root = Path(folder)
            native.write_json(root / "simulator.json", {"udid": "synthetic-device"})
            (root / "xctestrun-path.txt").write_text("synthetic.xctestrun")
            with mock.patch.object(native, "work", return_value=root), \
                    mock.patch.object(native, "verify_identity", return_value={"selectors": self.rows}), \
                    mock.patch.object(native, "run_logged", return_value=0), self.assertRaises(ValueError):
                native.test()
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

    def testCleanupRemovesPrivateAssetsProductsAndLogsButKeepsOnlyCiphertextAndSafeSummary(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.dict(os.environ, {}, clear=True):
            base = Path(folder)
            repo, work = base / "repo", base / "work"
            (repo / "App/Resources/FighterPrivate").mkdir(parents=True)
            (repo / "App/Resources/FighterPrivate/fixture.glb").write_bytes(b"synthetic asset")
            (work / "published").mkdir(parents=True)
            (work / "published/evidence.enc").write_bytes(b"synthetic ciphertext")
            (work / "derived").mkdir()
            (work / "derived/private.bin").write_bytes(b"synthetic product")
            (work / "native-build.log").write_text("synthetic private log")
            with mock.patch.object(native, "ROOT", repo), mock.patch.object(native, "work", return_value=work), \
                    mock.patch.object(native, "verify_identity", return_value={}), \
                    mock.patch.object(native, "public_summary", return_value={"nativeExactSetPassed": False}), \
                    contextlib.redirect_stdout(io.StringIO()):
                native.cleanup()
            self.assertFalse((repo / "App/Resources/FighterPrivate").exists())
            self.assertEqual({p.name for p in work.iterdir()}, {"published", "public-summary.json"})
            self.assertTrue(native.read_json(work / "public-summary.json")["cleanupComplete"])

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


    def fixture_release(self):
        members = {"Liu_Legion_Hammers.glb": b"synthetic framing-only fixture",
                   "SF3_DistinctFighters.json": b'{"synthetic":true}',
                   "SF3_FighterRelease.json": b'{"syntheticRelease":true}'}
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(members.items()): archive.writestr(name, data)
        clear = buffer.getvalue()
        # These bytes test framing/pins only; no test labels this a real GCM seal.
        cipher = bytes(len(clear) + 28)
        files = [{"file": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                 for name, data in sorted(members.items())]
        value = {"version": 1, "purpose": "h17-d19", "algorithm": "AES-256-GCM",
                 "aad": "fighter-h17-d19-v1", "keyEncoding": "base64-32",
                 "cipherLayout": "nonce12-ciphertext-tag16", "cipherBytes": len(cipher),
                 "cipherSHA256": hashlib.sha256(cipher).hexdigest(), "clearZIPBytes": len(clear),
                 "clearZIPSHA256": hashlib.sha256(clear).hexdigest(),
                 "shards": [{"file": "assets.part000.enc", "encoding": "binary", "bytes": len(cipher),
                             "sha256": hashlib.sha256(cipher).hexdigest()}],
                 "files": files, "replacements": ["Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"],
                 "releaseSHA256": next(row["sha256"] for row in files if row["file"] == "SF3_FighterRelease.json")}
        return value, clear, cipher

    def testGCMManifestRequiresExactAlgorithmAADBoundsSortedReceiptsAndReplacement(self):
        value, _, _ = self.fixture_release()
        native.validate_release_manifest(value)
        for key, wrong in (("version", True), ("algorithm", "AES-CBC"), ("aad", "different"),
                           ("keyEncoding", "hex"), ("cipherBytes", -1), ("cipherBytes", value["cipherBytes"] + 1),
                           ("clearZIPBytes", True), ("replacements", []),
                           ("replacements", ["SF3_DistinctFighters.json"]),
                           ("replacements", ["Another.glb", "Liu_Legion_Hammers.glb", "SF3_DistinctFighters.json"]),
                           ("releaseSHA256", "a" * 64)):
            candidate = copy.deepcopy(value); candidate[key] = wrong
            with self.subTest(key=key), self.assertRaises(ValueError): native.validate_release_manifest(candidate)
        for mutate in (lambda d: d.update(secret="forbidden"), lambda d: d["files"].reverse(),
                       lambda d: d["files"].append(d["files"][0]),
                       lambda d: d["files"][0].update(file="../escape.json"),
                       lambda d: d["shards"][0].update(file="assets.part001.enc")):
            candidate = copy.deepcopy(value); mutate(candidate)
            with self.assertRaises(ValueError): native.validate_release_manifest(candidate)

    def testCipherAssemblyVerifiesStoredBytesBeforeBinaryOrCanonicalBase64Decoding(self):
        value, _, cipher = self.fixture_release()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for encoding in ("binary", "base64"):
                data = cipher if encoding == "binary" else base64.b64encode(cipher)
                row = value["shards"][0]
                row.update(encoding=encoding, bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
                (root / row["file"]).write_bytes(data)
                output = root / (encoding + ".joined")
                native.assemble_cipher(value, root, output)
                self.assertEqual(output.read_bytes(), cipher)
                (root / row["file"]).write_bytes(data[:-1] + b"!")
                with self.assertRaises(ValueError): native.assemble_cipher(value, root, root / (encoding + ".bad"))
            (root / row["file"]).write_bytes(data + b"\n")
            row.update(bytes=len(data) + 1, sha256=hashlib.sha256(data + b"\n").hexdigest())
            with self.assertRaises(ValueError): native.assemble_cipher(value, root, root / "noncanonical")

    def testOverlayRejectsTamperDuplicateTraversalAndSymlinkBeforeBaselineReplacement(self):
        value, clear, _ = self.fixture_release()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            native.overlay_zip(clear, value, root / "valid")
            self.assertEqual({p.name for p in (root / "valid").iterdir()}, {r["file"] for r in value["files"]})
            with self.assertRaises(ValueError): native.overlay_zip(clear + b"!", value, root / "tampered")
            for kind in ("extra", "symlink", "digest"):
                buffer = io.BytesIO()
                with zipfile.ZipFile(buffer, "w") as archive, zipfile.ZipFile(io.BytesIO(clear)) as source:
                    for index, name in enumerate(source.namelist()):
                        info = zipfile.ZipInfo(name)
                        if kind == "symlink" and index == 0:
                            info.create_system = 3; info.external_attr = (stat.S_IFLNK | 0o777) << 16
                        data = source.read(name)
                        if kind == "digest" and index == 0: data = bytes(len(data))
                        archive.writestr(info, data)
                    if kind == "extra": archive.writestr("../escape.json", b"synthetic")
                candidate = copy.deepcopy(value); changed = buffer.getvalue()
                candidate.update(clearZIPBytes=len(changed), clearZIPSHA256=hashlib.sha256(changed).hexdigest())
                with self.subTest(kind=kind), self.assertRaises(ValueError): native.overlay_zip(changed, candidate, root / kind)
                self.assertFalse((root / "escape.json").exists())

    def fixture_attachments(self, root):
        groups = {}
        device = {"udid": "synthetic-owned-id", "name": "synthetic-owned-name"}
        for index, (label, expected) in enumerate(native.EXPECTED_ATTACHMENTS.items()):
            suffix = ".png" if expected["kind"] == "image" else ".json"
            name = f"payload-{index}{suffix}"
            (root / name).write_bytes(b"\x89PNG\r\n\x1a\nsynthetic-signature-only" if suffix == ".png" else b'{"synthetic":true}')
            item = {"exportedFileName": name,
                    "suggestedHumanReadableName": label + "_1_01234567-89ab-cdef-0123-456789abcdef" + suffix,
                    "deviceId": device["udid"], "deviceName": device["name"]}
            groups.setdefault(expected["selector"], []).append(item)
        manifest = [{"testIdentifier": selector.removeprefix("SiteTests/") + "()", "attachments": attachments}
                    for selector, attachments in groups.items()]
        native.write_json(root / "manifest.json", manifest)
        return manifest, device

    def testAttachmentsRequireAllSevenImagesAndTwoDataRecordsWithExactNativeOwnership(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); _, device = self.fixture_attachments(root)
            result = native.attachment_inventory(root, device, self.expected)
            self.assertTrue(result["exactMethodOwnership"]); self.assertEqual(result["imageCount"], 7)
            self.assertEqual(len(result["files"]), 9)

    def testWrongMethodDeviceLabelMissingRepeatedAndUnreferencedAttachmentsFail(self):
        for kind in ("method", "device", "label", "missing", "duplicate", "extra"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); manifest, device = self.fixture_attachments(root)
                item = manifest[0]["attachments"][0]
                if kind == "method": manifest[0]["testIdentifier"] = self.expected[0]
                elif kind == "device": item["deviceId"] = "some-other-simulator"
                elif kind == "label": item["suggestedHumanReadableName"] = "wrong" + item["suggestedHumanReadableName"]
                elif kind == "missing": manifest[0]["attachments"].pop()
                elif kind == "duplicate": manifest[0]["attachments"].append(copy.deepcopy(item))
                else: (root / "unreferenced.json").write_text("{}")
                native.write_json(root / "manifest.json", manifest)
                with self.assertRaises(ValueError): native.attachment_inventory(root, device, self.expected)

    def testPartialEvidenceNeverIncludesShaderAssetsRawBundlesOrSymlinkTargets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "partial.json").write_text('{"syntheticFailure":true}')
            (root / "original.metal").write_text("synthetic must not archive")
            (root / "original.glb").write_bytes(b"synthetic must not archive")
            self.assertEqual([p.name for p in native.bounded_attachment_files(root)], ["partial.json"])
            (root / "escape.json").symlink_to(root / "original.glb")
            with self.assertRaises(ValueError): native.bounded_attachment_files(root)


if __name__ == "__main__":
    unittest.main()
