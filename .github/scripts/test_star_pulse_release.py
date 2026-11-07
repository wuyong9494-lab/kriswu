import copy
import json
from pathlib import Path
import unittest
import star_pulse_release as pulse
from star_journey_release import visual_policy
import arena_private_pack as pack

class PulseReleaseTests(unittest.TestCase):
    def setUp(self):
        self.request = {**pulse.IDENTITY, "source_validation": {"mode":pulse.MODE,"rules_run_id":pulse.RULE_RUN},
                        "private_resource_pack":dict(pack.JOURNEY_PACK), "private_resource_pack_transport":dict(pack.JOURNEY_TRANSPORT),"notes":pulse.NOTE}
        self.run = {"id":pulse.IDENTITY["source_run_id"],"head_sha":pulse.IDENTITY["source_sha"],"head_branch":pulse.BRANCH,
                    "event":"push","path":".github/workflows/ios.yml","run_number":569,"status":"completed","conclusion":"success"}
        self.jobs = [{"name":name,"status":"completed","conclusion":"success"} for name in ("build","core-tests-linux")]
    def test_exact_request_and_success(self):
        self.assertEqual(pack.validation_specification(self.request),self.request["source_validation"])
        pulse.validate_run(self.run,self.jobs)
        self.assertTrue(visual_policy(self.request)["deferred"])
        self.assertFalse(visual_policy(self.request)["passed"])
    def test_wrong_source_pack_rules_and_disclosure_rejected(self):
        for key,value in [("source_sha","0"*40),("build_number","570"),("source_validation",{"mode":pulse.MODE,"rules_run_id":1}),
                          ("private_resource_pack",{}),("private_resource_pack_transport",{}),("notes","")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                pack.validation_specification({**self.request,key:value})
    def test_pending_failed_skipped_and_wrong_ci_never_pass(self):
        with self.assertRaises(pulse.Pending): pulse.validate_run({**self.run,"status":"in_progress"},self.jobs)
        for key,value in [("conclusion","failure"),("head_sha","0"*40),("run_number",568),("head_branch","main")]:
            with self.assertRaises(ValueError): pulse.validate_run({**self.run,key:value},self.jobs)
        for result in ("skipped","failure",None):
            jobs=copy.deepcopy(self.jobs);jobs[0]["conclusion"]=result
            with self.assertRaises(ValueError): pulse.validate_run(self.run,jobs)
    def test_rules_must_be_exact_successful_run(self):
        run={**self.run,"id":pulse.RULE_RUN,"path":".github/workflows/star-gameplay-rules.yml"}
        jobs=[{"name":"rules","status":"completed","conclusion":"success"}]
        pulse.validate_run(run,jobs,rule=True)
        with self.assertRaises(ValueError): pulse.validate_run({**run,"id":1},jobs,rule=True)

if __name__ == '__main__': unittest.main()
