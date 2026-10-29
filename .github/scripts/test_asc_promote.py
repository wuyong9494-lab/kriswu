import copy
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import asc_promote as promotion


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.request = {"source_sha": "a" * 40, "build_number": "399", "source_run_id": 123,
                        "bundle_id": "com.kriswu.shiftreminder", "version": "1.2", "notes": "Test",
                        "ranger_sha256": hashlib.sha256(b"ranger").hexdigest()}
        self.run = {"head_sha": "a" * 40, "run_number": 399, "path": ".github/workflows/ios.yml",
                    "status": "completed", "conclusion": "success"}
        self.jobs = [{"name": n, "conclusion": "success"} for n in ("build", "core-tests-linux", "arena-look")]

    def test_accepts_only_matching_completed_ci(self):
        promotion.validate_source(self.request, self.run, self.jobs)
        for key, value in (("head_sha", "b" * 40), ("run_number", 400), ("conclusion", "failure"),
                           ("status", "in_progress"), ("path", "other.yml")):
            with self.subTest(key=key), self.assertRaises(AssertionError):
                promotion.validate_source(self.request, dict(self.run, **{key: value}), self.jobs)

    def test_rejects_missing_or_skipped_source_checks(self):
        for index in range(3):
            jobs = copy.deepcopy(self.jobs)
            jobs[index]["conclusion"] = "skipped"
            with self.assertRaises(AssertionError):
                promotion.validate_source(self.request, self.run, jobs)
        with self.assertRaises(AssertionError):
            promotion.validate_source(self.request, self.run, self.jobs[:2])

    def test_415_capture_exception_keeps_compile_and_regression_gates(self):
        request = dict(self.request, build_number="415", source_run_id=40871120791,
                       source_sha="7d4c9c2f9fa77e2c9d1f124ec8910e2a57b926cf", skip_visual_capture=True)
        run = dict(self.run, head_sha=request["source_sha"], run_number=415, status="in_progress", conclusion=None)
        jobs = copy.deepcopy(self.jobs)
        jobs[2].update(conclusion=None, steps=[{"name": n, "conclusion": "success"} for n in (
            "Set up job", "Run actions/checkout@v5", "选用最新的 Xcode（26 或更新）", "生成 Xcode 工程",
            "编译模拟器版本", "角色动画回归测试")])
        promotion.validate_source(request, run, jobs)
        for index in range(2):
            bad = copy.deepcopy(jobs); bad[index]["conclusion"] = "failure"
            with self.assertRaises(AssertionError): promotion.validate_source(request, run, bad)
        for index in range(6):
            bad = copy.deepcopy(jobs); bad[2]["steps"][index]["conclusion"] = "failure"
            with self.assertRaises(AssertionError): promotion.validate_source(request, run, bad)
        with self.assertRaises(AssertionError):
            promotion.validate_source(dict(request, build_number="416"), dict(run, run_number=416), jobs)
        with self.assertRaises(AssertionError):
            promotion.validate_source(request, dict(run, conclusion="cancelled"), jobs)
        with self.assertRaises(AssertionError):
            promotion.validate_source(request, run, jobs + [{"name": "site-tests", "conclusion": "failure"}])

    def test_existing_build_is_found_without_uploading(self):
        build = {"id": "existing", "relationships": {"preReleaseVersion": {"data": {"id": "v"}}}}
        response = {"data": [build], "included": [{"type": "preReleaseVersions", "id": "v",
                                                  "attributes": {"version": "1.2"}}]}
        with patch.object(promotion, "call", side_effect=[{"data": [{"id": "app"}]}, response]) as call:
            self.assertEqual(promotion.find_build(self.request)["id"], "existing")
            self.assertTrue(all(args.args[0] == "GET" for args in call.call_args_list))
        response["included"][0]["attributes"]["version"] = "1.3"
        with patch.object(promotion, "call", side_effect=[{"data": [{"id": "app"}]}, response]):
            with self.assertRaises(AssertionError):
                promotion.find_build(self.request)

    def test_absent_build_allows_promotion(self):
        with patch.object(promotion, "call", side_effect=[{"data": [{"id": "app"}]}, {"data": []}]):
            self.assertIsNone(promotion.find_build(self.request))

    def test_archive_detects_wrong_number_identity_and_asset(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp)
            app = archive / "Products/Applications/ShiftReminder.app"
            widget = app / "PlugIns/ShiftWidget.appex"
            widget.mkdir(parents=True)
            info = {"CFBundleIdentifier": self.request["bundle_id"], "CFBundleVersion": "399",
                    "CFBundleShortVersionString": "1.2", "ArenaCommitSHA": "a" * 40}
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            (widget / "Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": "399"}))
            (app / "Ranger_Original.glb").write_bytes(b"ranger")
            with patch.object(promotion, "save_report"):
                promotion.verify_archive(self.request, archive)
            for key, value in (("CFBundleVersion", "400"), ("ArenaCommitSHA", "b" * 40)):
                (app / "Info.plist").write_bytes(plistlib.dumps(dict(info, **{key: value})))
                with self.assertRaises(AssertionError):
                    promotion.verify_archive(self.request, archive)
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            (widget / "Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": "400"}))
            with self.assertRaises(AssertionError):
                promotion.verify_archive(self.request, archive)
            (widget / "Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": "399"}))
            (app / "Ranger_Original.glb").write_bytes(b"wrong model")
            with self.assertRaises(AssertionError):
                promotion.verify_archive(self.request, archive)

    def test_invalid_apple_build_is_not_reported_as_success(self):
        with patch.object(promotion, "find_build", return_value={"id": "b", "attributes": {"processingState": "INVALID"}}), \
             patch.object(promotion, "save_report"):
            with self.assertRaises(RuntimeError):
                promotion.finish(self.request, False)


if __name__ == "__main__":
    unittest.main()
