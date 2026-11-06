import copy
import unittest

import arena_private_pack as private_pack
from star_journey_release import KNOWN_VALIDATION_NOTE, visual_policy


class DirectBetaVisualPolicyTests(unittest.TestCase):
    def setUp(self):
        self.request = {
            **private_pack.JOURNEY_RELEASE,
            "source_validation": {"mode": private_pack.JOURNEY_DIRECT_MODE,
                                  "native_run_id": private_pack.JOURNEY_NATIVE_RUN},
            "private_resource_pack": dict(private_pack.JOURNEY_PACK),
            "private_resource_pack_transport": dict(private_pack.JOURNEY_TRANSPORT),
            "notes": private_pack.JOURNEY_DEVICE_NOTE + private_pack.JOURNEY_DIRECT_NOTE + KNOWN_VALIDATION_NOTE,
        }

    def test_direct_beta_keeps_actual_failure_and_exact_provenance(self):
        result = visual_policy(self.request)
        self.assertTrue(result["deferred"])
        self.assertFalse(result["passed"])
        self.assertEqual(result["previous_actual_result"]["failedTests"], 1)
        self.assertEqual(result["previous_actual_result"]["job_id"], 127936581405)
        self.assertEqual(result["private_resource_pack"], private_pack.JOURNEY_PACK)

    def test_strict_and_other_releases_still_require_rendering(self):
        strict = copy.deepcopy(self.request)
        strict["source_validation"]["mode"] = private_pack.JOURNEY_MODE
        strict["notes"] = private_pack.JOURNEY_DEVICE_NOTE
        self.assertEqual(visual_policy(strict), {"deferred": False})
        self.assertEqual(visual_policy({}), {"deferred": False})

    def test_missing_disclosure_changed_build_source_or_pack_cannot_defer(self):
        for key, value in (
            ("notes", private_pack.JOURNEY_DEVICE_NOTE + private_pack.JOURNEY_DIRECT_NOTE),
            ("build_number", "568"), ("source_sha", "0" * 40),
            ("private_resource_pack", {**private_pack.JOURNEY_PACK, "sha256": "0" * 64}),
            ("private_resource_pack_transport", {**private_pack.JOURNEY_TRANSPORT, "bytes": 1}),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                visual_policy({**self.request, key: value})


if __name__ == "__main__":
    unittest.main()
