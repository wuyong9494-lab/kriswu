#!/usr/bin/env python3
"""Offline negative probes of the closed follow-up evidence boundary.

Uses temporary synthetic manifests/PNG signatures only. No resource key,
network call, Apple build, screenshot render or workflow execution is involved.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load_scope(name):
    path = Path(__file__).with_name("fighter_visual_acceptance.py")
    spec = importlib.util.spec_from_file_location("visual_" + name.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(os.environ, {"FIGHTER_VISUAL_SCOPE": name}):
        spec.loader.exec_module(module)
    return module


FOLLOWUP = load_scope("trail-followup")
BASELINE = load_scope("baseline-11")
DEVICE = {"udid": "00112233-4455-6677-8899-AABBCCDDEEFF", "name": "Synthetic manifest device"}


class ClosedFollowupEvidenceTests(unittest.TestCase):
    def test_coverage_scope_keeps_current_presentation_resources_and_only_affected_methods(self):
        coverage = load_scope("coverage-followup")
        self.assertEqual((len(coverage.SELECTORS), len(coverage.IMAGE_LABELS), len(coverage.DATA_LABELS)), (2, 7, 0))
        self.assertEqual(coverage.SELECTED, FOLLOWUP.FOLLOWUP_SELECTED[2:])
        self.assertTrue(coverage.USES_PRESENTATION)
        self.assertIn(".github/private/fighter-presentation/manifest.json", coverage.MANIFESTS)
        self.assertEqual(len(coverage.resource_records()), 72)
        self.assertEqual(coverage.recipient_digest(coverage.RECIPIENT.read_bytes()), coverage.RECIPIENT_SPKI_SHA256)
        self.assertTrue(all(row["selector"] in coverage.SELECTORS for row in coverage.EXPECTED_ATTACHMENTS.values()))
        self.assertEqual(set(coverage.EXPECTED_ATTACHMENTS), set(coverage.IMAGE_LABELS))
        self.assertNotEqual(coverage.SCOPE["commitPrefix"], FOLLOWUP.SCOPE["commitPrefix"])

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fighter-scope-check-")
        self.root = Path(self.temporary.name)
        self.manifest = []
        for selector in FOLLOWUP.SELECTORS:
            group = {"testIdentifier": "/".join(selector.split("/")[1:]) + "()", "attachments": []}
            for label, row in FOLLOWUP.FOLLOWUP_ATTACHMENTS.items():
                if row["selector"] != selector:
                    continue
                number = sum(len(item["attachments"]) for item in self.manifest) + len(group["attachments"])
                filename = f"evidence-{number}.png"
                # Deliberately synthetic signature, not a rendered acceptance image.
                (self.root / filename).write_bytes(b"\x89PNG\r\n\x1a\nsynthetic-gate-fixture")
                group["attachments"].append({
                    "exportedFileName": filename,
                    "suggestedHumanReadableName": label + "_0_00112233-4455-6677-8899-AABBCCDDEEFF.png",
                    "deviceId": DEVICE["udid"], "deviceName": DEVICE["name"],
                })
            self.manifest.append(group)
        self.save_manifest()

    def tearDown(self):
        self.temporary.cleanup()

    def save_manifest(self):
        (self.root / "manifest.json").write_text(json.dumps(self.manifest))

    def attachments(self):
        return [attachment for group in self.manifest for attachment in group["attachments"]]

    def inventory(self):
        self.save_manifest()
        return FOLLOWUP.followup_attachment_inventory(self.root, DEVICE)

    def test_followup_is_closed_and_original_capture_keeps_its_scope(self):
        self.assertEqual((len(BASELINE.SELECTORS), len(BASELINE.IMAGE_LABELS), len(BASELINE.DATA_LABELS)), (11, 26, 3))
        self.assertEqual((len(FOLLOWUP.SELECTORS), len(FOLLOWUP.IMAGE_LABELS), len(FOLLOWUP.DATA_LABELS)), (4, 7, 0))
        self.assertNotEqual(BASELINE.SCOPE["workflow"], FOLLOWUP.SCOPE["workflow"])
        self.assertFalse(FOLLOWUP.SCOPE["commitPrefix"].startswith(BASELINE.SCOPE["commitPrefix"]))
        self.assertFalse(BASELINE.SCOPE["commitPrefix"].startswith(FOLLOWUP.SCOPE["commitPrefix"]))
        with self.assertRaises(ValueError):
            FOLLOWUP.scope_settings("SiteTests")
        with self.assertRaises(ValueError):
            load_scope("arbitrary-native-selection")

    def test_exact_manifest_binds_every_payload_to_its_method_and_device(self):
        inventory = self.inventory()
        self.assertEqual((inventory["imageCount"], inventory["fileCount"]), (7, 8))
        self.assertTrue(inventory["completeExpectedLabels"])
        self.assertTrue(inventory["exactMethodOwnership"])
        self.assertEqual(len({row["sha256"] for row in inventory["files"] if row["kind"] == "image"}), 1)
        self.assertEqual(set(inventory["imageLabels"]), set(FOLLOWUP.IMAGE_LABELS))

    def test_missing_label_is_not_satisfied_by_another_json_mention(self):
        group = next(group for group in self.manifest if group["attachments"])
        removed = group["attachments"].pop()
        (self.root / removed["exportedFileName"]).unlink()
        (self.root / "log.json").write_text(json.dumps({"message": removed["suggestedHumanReadableName"]}))
        with self.assertRaisesRegex(AssertionError, "Missing expected evidence labels"):
            self.inventory()

    def test_duplicate_exact_label_fails_even_with_distinct_files(self):
        group = next(group for group in self.manifest if group["attachments"])
        duplicate = copy.deepcopy(group["attachments"][0])
        duplicate["exportedFileName"] = "duplicate.png"
        (self.root / "duplicate.png").write_bytes((self.root / group["attachments"][0]["exportedFileName"]).read_bytes())
        group["attachments"].append(duplicate)
        with self.assertRaisesRegex(AssertionError, "repeated exact attachment label"):
            self.inventory()

    def test_extra_unreferenced_image_fails(self):
        (self.root / "unrequested.png").write_bytes(b"\x89PNG\r\n\x1a\nextra")
        with self.assertRaisesRegex(AssertionError, "Extra unreferenced attachment"):
            self.inventory()

    def test_label_cannot_be_borrowed_from_another_selected_method(self):
        groups = [group for group in self.manifest if group["attachments"]]
        groups[0]["attachments"].append(groups[1]["attachments"].pop())
        with self.assertRaisesRegex(AssertionError, "wrong selected method"):
            self.inventory()

    def test_unselected_method_and_repeated_method_fail(self):
        original = copy.deepcopy(self.manifest)
        self.manifest.append({"testIdentifier": "UnselectedTests/testOther()", "attachments": []})
        with self.assertRaisesRegex(AssertionError, "attachment method"):
            self.inventory()
        self.manifest = original + [copy.deepcopy(original[0])]
        with self.assertRaisesRegex(AssertionError, "attachment method"):
            self.inventory()

    def test_prefixed_or_suffixed_label_does_not_match(self):
        attachment = self.attachments()[0]
        original = attachment["suggestedHumanReadableName"]
        for bad in ("extra-" + original, original.replace("_0_", "-suffix_0_")):
            with self.subTest(name=bad):
                attachment["suggestedHumanReadableName"] = bad
                with self.assertRaisesRegex(AssertionError, "exact attachment label"):
                    self.inventory()

    def test_wrong_simulator_identity_fails(self):
        attachment = self.attachments()[0]
        attachment["deviceId"] = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        with self.assertRaisesRegex(AssertionError, "simulator identity"):
            self.inventory()

    def test_bad_png_symlink_and_path_traversal_fail(self):
        attachment = self.attachments()[0]
        path = self.root / attachment["exportedFileName"]
        original = path.read_bytes()
        path.write_bytes(b"not-a-png")
        with self.assertRaisesRegex(AssertionError, "Invalid PNG"):
            self.inventory()
        path.write_bytes(original)
        (self.root / "linked.png").symlink_to(path)
        with self.assertRaisesRegex(AssertionError, "Symlink"):
            self.inventory()
        (self.root / "linked.png").unlink()
        attachment["exportedFileName"] = "../evidence.png"
        with self.assertRaisesRegex(AssertionError, "Unsafe exported filename"):
            self.inventory()

    def test_native_counts_cannot_hide_skips_duplicates_or_other_tests(self):
        summary = {"totalTestCount": 4, "passedTests": 4, "failedTests": 0, "skippedTests": 0, "result": "Passed"}
        nodes = [{"nodeType": "Test Case", "nodeIdentifier": selector + "()", "result": "Passed"}
                 for selector in FOLLOWUP.SELECTORS]
        FOLLOWUP.verify_results(summary, {"testNodes": nodes})
        for bad_summary in (dict(summary, skippedTests=1), dict(summary, failedTests=1), dict(summary, totalTestCount=11)):
            with self.subTest(summary=bad_summary), self.assertRaises(AssertionError):
                FOLLOWUP.verify_results(bad_summary, {"testNodes": nodes})
        for bad_nodes in (nodes[:-1], nodes[:-1] + [nodes[0]], nodes + [{"nodeType": "Test Case", "nodeIdentifier": "Other/test()", "result": "Passed"}]):
            with self.subTest(nodes=len(bad_nodes)), self.assertRaises(AssertionError):
                FOLLOWUP.verify_results(summary, {"testNodes": bad_nodes})

    def test_missing_scope_environment_cannot_expand_prepared_followup(self):
        identity = {"scope": "trail-followup", "expectedNativeMethods": 4,
                    "selectors": [{"identifier": selector} for selector in FOLLOWUP.SELECTORS],
                    "expectedImageLabels": FOLLOWUP.IMAGE_LABELS, "expectedDataLabels": []}
        FOLLOWUP.verify_scope_identity(identity)
        with self.assertRaisesRegex(AssertionError, "Prepared visual scope mismatch"):
            BASELINE.verify_scope_identity(identity)


if __name__ == "__main__":
    unittest.main()
