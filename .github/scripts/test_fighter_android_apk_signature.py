#!/usr/bin/env python3
"""Only new APK certificate-output parsing boundaries; no SDK/APK execution.

The already authenticated apksigner log is a local fixture. Rewritten legacy
and invalid variants are synthetic strings, not new cryptographic verification.
No old check suite, download, signature tool, emulator or app is invoked.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "android_apk_signer_parser_review", Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)

CERTIFICATE = "fee5c7569efddc4ba055f78f9b43d7edd3a0f2923feba403809c6fd7dc3c0381"
STAMP = "3257d599a49d2c961a471ca9843f59d341a405884583fc087df4237b733bbd6d"
PUBLIC_KEY = "0326c49be34e2fe773f28bdf8514bece8b938f95366f92b36ef20dc8112416ac"
CERTIFICATE_LINE = "V3.0 Signer: certificate SHA-256 digest: " + CERTIFICATE


class APKSignerOutputBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raw = Path(os.environ["FIGHTER_ANDROID_REVIEW_APK_SIGNATURE_LOG"]).read_bytes()
        if len(raw) != 1840 or hashlib.sha256(raw).hexdigest() != "0ae25f3b2fa19764a46089007876a14808fb7e0fec251ce055e048a5f6429682":
            raise RuntimeError("authenticated_apksigner_log_fixture_changed")
        cls.actual = raw.decode("utf-8")

    def test_actual_versioned_signer_selects_only_the_apk_certificate(self):
        value = R.parse_apk_signature_output(self.actual, 0)
        self.assertEqual(value["certificateSHA256"], [CERTIFICATE])
        self.assertNotIn(STAMP, value["certificateSHA256"])
        self.assertNotIn(PUBLIC_KEY, value["certificateSHA256"])
        self.assertEqual(value["numberOfSigners"], 1)
        self.assertEqual(value["signerOutputFormat"], "versioned_v3_0")
        self.assertTrue(value["verifiedSchemes"]["v2"])
        self.assertTrue(value["verifiedSchemes"]["v3"])
        self.assertEqual(value["sourceStampCertificateRowsExcluded"], 1)
        self.assertFalse(value["publicKeyDigestsUsedAsCertificate"])
        self.assertFalse(value["publisherIdentityIndependentlyAuthenticated"])

    def test_reviewed_legacy_numbered_layout_retains_the_same_certificate_identity(self):
        legacy = self.actual.replace("V3.0 Signer:", "Signer #1").replace("Source Stamp Signer:", "Source Stamp Signer")
        value = R.parse_apk_signature_output(legacy, 0)
        self.assertEqual(value["certificateSHA256"], [CERTIFICATE])
        self.assertEqual(value["signerOutputFormat"], "numbered")
        self.assertEqual(value["sourceStampCertificateRowsExcluded"], 1)
        upper = legacy.replace(CERTIFICATE, CERTIFICATE.upper())
        self.assertEqual(R.parse_apk_signature_output(upper, 0)["certificateSHA256"], [CERTIFICATE])

    def test_source_stamp_or_public_key_rows_cannot_supply_the_missing_apk_certificate(self):
        variants = (
            self.actual.replace(CERTIFICATE_LINE + "\n", ""),
            self.actual.replace(CERTIFICATE_LINE, "V3.0 Signer: public key SHA-256 digest: " + CERTIFICATE),
        )
        for output in variants:
            with self.subTest(outputKind=output.count("certificate SHA-256 digest:")):
                with self.assertRaisesRegex(R.Blocked, "apk_signature_certificate_missing_or_ambiguous"):
                    R.parse_apk_signature_output(output, 0)

    def test_nonzero_process_missing_or_conflicting_verification_cannot_pass(self):
        for code in (1, -9, False, None):
            with self.subTest(exitCode=code), self.assertRaisesRegex(R.Blocked, "apk_signature_process_failed"):
                R.parse_apk_signature_output(self.actual, code)
        variants = (
            self.actual.replace("Verifies\n", ""),
            "Verifies\n" + self.actual,
            self.actual + "DOES NOT VERIFY\n",
        )
        for output in variants:
            with self.assertRaisesRegex(R.Blocked, "apk_signature_verification_statement_missing_or_ambiguous"):
                R.parse_apk_signature_output(output, 0)

    def test_single_signer_count_and_numbered_identity_are_mandatory(self):
        variants = (
            self.actual.replace("Number of signers: 1\n", ""),
            self.actual.replace("Number of signers: 1", "Number of signers: 0"),
            self.actual.replace("Number of signers: 1", "Number of signers: 2"),
            self.actual + "Number of signers: 1\n",
            self.actual.replace("V3.0 Signer:", "Signer #2"),
        )
        for output in variants:
            with self.assertRaises(R.Blocked):
                R.parse_apk_signature_output(output, 0)

    def test_duplicate_unknown_or_malformed_certificate_rows_fail_closed(self):
        variants = (
            self.actual + CERTIFICATE_LINE + "\n",
            self.actual + "Signer #1 certificate SHA-256 digest: " + CERTIFICATE + "\n",
            self.actual.replace("V3.0 Signer:", "V3.1 Signer:"),
            self.actual.replace(CERTIFICATE_LINE, CERTIFICATE_LINE[:-1]),
            self.actual.replace(CERTIFICATE_LINE, CERTIFICATE_LINE + "0"),
            self.actual.replace(CERTIFICATE_LINE, CERTIFICATE_LINE[:-1] + "g"),
            self.actual.replace(CERTIFICATE_LINE, "Unknown Signer: certificate SHA-256 digest: " + CERTIFICATE),
        )
        for output in variants:
            with self.assertRaises(R.Blocked):
                R.parse_apk_signature_output(output, 0)

    def test_real_signature_schemes_are_distinct_from_source_stamp_and_label_format(self):
        no_modern = self.actual.replace("(APK Signature Scheme v2): true", "(APK Signature Scheme v2): false")
        no_modern = no_modern.replace("(APK Signature Scheme v3): true", "(APK Signature Scheme v3): false")
        with self.assertRaisesRegex(R.Blocked, "apk_signature_modern_scheme_not_verified"):
            R.parse_apk_signature_output(no_modern, 0)
        only_v2 = self.actual.replace("(APK Signature Scheme v3): true", "(APK Signature Scheme v3): false")
        with self.assertRaisesRegex(R.Blocked, "apk_signature_versioned_signer_scheme_mismatch"):
            R.parse_apk_signature_output(only_v2, 0)
        legacy = only_v2.replace("V3.0 Signer:", "Signer #1")
        self.assertEqual(R.parse_apk_signature_output(legacy, 0)["certificateSHA256"], [CERTIFICATE])
        duplicated = self.actual + "Verified using v2 scheme (APK Signature Scheme v2): true\n"
        with self.assertRaisesRegex(R.Blocked, "apk_signature_scheme_ambiguous"):
            R.parse_apk_signature_output(duplicated, 0)
        unsupported = self.actual + "Verified using v9 scheme (APK Signature Scheme v9): true\n"
        with self.assertRaisesRegex(R.Blocked, "apk_signature_scheme_format_unsupported"):
            R.parse_apk_signature_output(unsupported, 0)


class AndroidBoundedDeadlineChanges(unittest.TestCase):
    def test_remaining_scope_and_total_lifetime_keep_distinct_deadline_causes(self):
        with patch.object(R.time, "monotonic", return_value=100), patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 600):
            self.assertEqual(R.execution_deadline(20, 107), (107, "scope"))
            self.assertEqual(R.execution_deadline(5, 110), (105, "command"))
            with self.assertRaises(R.ScopedDeadlineExpired):
                R.execution_deadline(20, 100)
            with patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 105):
                self.assertEqual(R.execution_deadline(20, 105), (105, "emulator"))
            with patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 100):
                with self.assertRaisesRegex(R.Blocked, "emulator_lifetime_bound") as caught:
                    R.execution_deadline(20, 100)
                self.assertNotIsInstance(caught.exception, R.ScopedDeadlineExpired)

    def test_boot_last_poll_uses_only_remaining_time_and_never_starts_extra_poll(self):
        clock = {"now": 179.0}
        process = Mock()
        process.poll.return_value = None
        def poll(tools, args, label, timeout, **options):
            self.assertEqual(label, "boot-poll-0")
            self.assertEqual(timeout, 1.0)
            self.assertEqual(options["deadline"], 180.0)
            clock["now"] += timeout
            return "", 0
        with patch.object(R.time, "monotonic", side_effect=lambda: clock["now"]), \
             patch.object(R.time, "sleep") as sleep, \
             patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 600), \
             patch.object(R, "adb_command", side_effect=poll) as adb:
            with self.assertRaisesRegex(R.Blocked, "emulator_boot_deadline"):
                R.wait_for_emulator_boot({}, process, 180.0)
            self.assertEqual(adb.call_count, 1)
            sleep.assert_not_called()
            self.assertEqual(clock["now"], 180.0)

    def test_observation_budget_completion_does_not_swallow_real_network_failure(self):
        clock = {"now": 0.0}
        state = {"emulator": {"monotonicStart": 0.0}}
        net = "eth0: " + "0 " * 16 + "\n"
        def adb_reply(tools, args, label, timeout, **options):
            self.assertEqual(options["deadline"], 180.0)
            return (net, 0) if label.startswith("guest-network-") else ("42\n", 0)
        def capture(tools, index, *, deadline):
            self.assertEqual(deadline, 180.0)
            clock["now"] = deadline
            raise R.ScopedDeadlineExpired("scoped_operation_deadline")
        with patch.object(R.time, "monotonic", side_effect=lambda: clock["now"]), \
             patch.object(R.time, "sleep") as sleep, patch.object(R, "save_state"), \
             patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 600), \
             patch.object(R, "adb_command", side_effect=adb_reply) as adb, \
             patch.object(R, "snapshot", side_effect=capture) as screenshot:
            R.observe_client({}, state)
            self.assertEqual(state["observation"]["stopReason"], "bounded_observation_complete")
            self.assertEqual(state["observation"]["elapsedSeconds"], 180.0)
            self.assertEqual(adb.call_count, 2)
            self.assertEqual(screenshot.call_count, 1)
            sleep.assert_not_called()
        clock["now"] = 0.0
        state = {"emulator": {"monotonicStart": 0.0}}
        exceeded = "eth0: " + str(R.MAX_GUEST_NETWORK_BYTES + 1) + " " + "0 " * 15 + "\n"
        with patch.object(R.time, "monotonic", side_effect=lambda: clock["now"]), \
             patch.object(R, "save_state"), patch.object(R, "ACTIVE_EMULATOR_DEADLINE", 600), \
             patch.object(R, "adb_command", return_value=(exceeded, 0)), \
             patch.object(R, "snapshot") as screenshot:
            with self.assertRaisesRegex(R.Blocked, "guest_network_budget") as caught:
                R.observe_client({}, state)
            self.assertNotIsInstance(caught.exception, R.ScopedDeadlineExpired)
            self.assertIsNone(state["observation"]["stopReason"])
            screenshot.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
