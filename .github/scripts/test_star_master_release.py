import copy
import unittest
from unittest.mock import patch
import star_master_release as master
import arena_private_pack as pack
from star_journey_release import visual_policy


class MasterReleaseTests(unittest.TestCase):
    def setUp(self):
        self.request = {**master.IDENTITY, "source_validation": {"mode": master.MODE, "rules_run_id": master.RULE_RUN,
                        "native_run_id": master.NATIVE_RUN}, "private_resource_pack": dict(pack.JOURNEY_PACK),
                        "private_resource_pack_transport": dict(pack.JOURNEY_TRANSPORT), "notes": master.NOTE}
        self.run = {"id": master.IDENTITY["source_run_id"], "head_sha": master.IDENTITY["source_sha"],
                    "head_branch": master.BRANCH, "event": "push", "path": ".github/workflows/ios.yml",
                    "run_number": int(master.IDENTITY["build_number"]), "status": "completed", "conclusion": "success"}
        self.jobs = [{"name": name, "status": "completed", "conclusion": "success"} for name in ("build", "core-tests-linux")]
        self.native = {**self.run, "id": master.NATIVE_RUN, "path": ".github/workflows/star-master-native.yml"}
        self.native_jobs = [{"name": "replay", "status": "completed", "conclusion": "success", "steps": [
            {"name": name, "status": "completed", "conclusion": "success"} for name in master.NATIVE_STEPS]}]
        self.files = [{"filename": "App/Views/TileReplayView.swift", "status": "added"},
                      {"filename": "docs/star-master-depth-2026-11-07.md", "status": "added"}]

    def test_exact_request_runs_and_private_policy(self):
        self.assertEqual(pack.validation_specification(self.request), self.request["source_validation"])
        master.validate_run(self.run, self.jobs, "source")
        master.validate_run(self.native, self.native_jobs, "native")
        master.validate_run({**self.run, "id": master.RULE_RUN, "path": ".github/workflows/star-gameplay-rules.yml"},
                            [{"name": "rules", "status": "completed", "conclusion": "success"}], "rules")
        master.validate_scope(self.files)
        policy = visual_policy(self.request)
        self.assertTrue(policy["deferred"])
        self.assertFalse(policy["passed"])
        self.assertEqual(policy["tile_native_and_ui_validation"], "success")

    def test_changed_identity_pack_or_disclosure_cannot_release(self):
        for key, value in [("source_sha", "0" * 40), ("build_number", "581"), ("source_run_id", 1),
                           ("source_validation", {"mode": master.MODE, "rules_run_id": master.RULE_RUN, "native_run_id": 42344913123}),
                           ("private_resource_pack", {}), ("private_resource_pack_transport", {}), ("notes", "")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                pack.validation_specification({**self.request, key: value})

    def test_pending_failed_cancelled_skipped_and_wrong_source_rejected(self):
        with self.assertRaises(master.Pending):
            master.validate_run({**self.run, "status": "in_progress"}, self.jobs, "source")
        for key, value in [("conclusion", "failure"), ("conclusion", "cancelled"), ("head_sha", "0" * 40),
                           ("head_branch", "main"), ("run_number", 581), ("event", "workflow_dispatch")]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                master.validate_run({**self.run, key: value}, self.jobs, "source")
        for result in ("skipped", "failure", None):
            jobs = copy.deepcopy(self.jobs); jobs[0]["conclusion"] = result
            with self.assertRaises(ValueError): master.validate_run(self.run, jobs, "source")

    def test_native_job_must_really_run_screenshots_and_interactions(self):
        for index in range(len(master.NATIVE_STEPS)):
            jobs = copy.deepcopy(self.native_jobs); jobs[0]["steps"][index]["conclusion"] = "skipped"
            with self.subTest(step=index), self.assertRaises(ValueError):
                master.validate_run(self.native, jobs, "native")
        jobs = copy.deepcopy(self.native_jobs); jobs[0]["steps"] = []
        with self.assertRaises(ValueError): master.validate_run(self.native, jobs, "native")
        with self.assertRaises(ValueError):
            master.validate_run({**self.native, "id": 42344913123}, self.native_jobs, "native")

    def test_unrelated_runtime_changes_and_incomplete_scope_rejected(self):
        for files in [[], None, self.files * 150, [{"filename": "App/Services/ArenaFaceScene.swift", "status": "modified"}],
                      [{"filename": "App/Views/TileReplayView.swift", "status": "renamed", "previous_filename": "App/ArenaVendor/private.bin"}],
                      [{"filename": "App/Views/TileReplayView.swift", "status": "removed"}]]:
            with self.subTest(files=files and files[:1]), self.assertRaises(ValueError): master.validate_scope(files)

    def test_check_requires_current_head_before_any_upload(self):
        with patch.object(master.promotion, "github", return_value={"object": {"sha": "0" * 40}}):
            with self.assertRaisesRegex(ValueError, "superseded"): master.check(self.request)


if __name__ == '__main__': unittest.main()
