#!/usr/bin/env python3
"""Six new Unity-canvas boundary checks; local text and mocked ADB only.

No SDK/APK/emulator command, network call, input event or prior success suite is
executed. The one marker line is the format observed in run 43686859870.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "android_terms_boundary_delta", Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
PID = 5123
MARKER = "11-15 06:47:50.045  5123  5203 W Banzai  : SendLog Terms of use not confirm!\n"


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory() as directory:
        run = Path(directory)/"owned-run"
        (run/"evidence").mkdir(parents=True)
        state = {"emulator":{"monotonicStart":100.0},
                 "executed":{"apkDownloads":1, "emulatorBoots":1, "apkInstalls":1, "apkLaunches":1}}
        with patch.object(R, "work", return_value=run), \
                patch.object(R.time, "monotonic", return_value=100.0), \
                patch.object(R, "ACTIVE_EMULATOR_DEADLINE", None):
            yield run, state


def command_evidence(label, output, code=0):
    raw = output.encode()
    (R.evidence()/(label+".log")).write_bytes(raw)
    R.write_json(R.evidence()/(label+"-process.json"), {"exitCode":code,
        "elapsedSeconds":0.001, "bytes":len(raw), "sha256":hashlib.sha256(raw).hexdigest(),
        "scopeDeadlineProvided":True, "deadlineBasis":"command", "deadlineReached":False,
        "scopeDeadlineExpired":False})
    return output, code


class TermsBoundaryDelta(unittest.TestCase):
    def test_observed_marker_requires_valid_fields_and_the_exact_app_pid(self):
        marker = R.unconfirmed_terms_marker("--------- beginning of main\n"+MARKER, PID)
        self.assertEqual(marker, {"lineNumber":2, "guestTimestamp":"11-15 06:47:50.045",
            "pid":PID, "tid":5203, "priority":"W", "tag":"Banzai",
            "message":"SendLog Terms of use not confirm!"})
        self.assertEqual(R.unique_package_pid("5123\n", 0), PID)
        for output, code in (("5123 5124\n",0), ("5123\n5123\n",0), ("0\n",0),
                             ("2147483648\n",0), ("5123\n",1), ("5123\n",False)):
            with self.subTest(output=output, code=code):
                self.assertIsNone(R.unique_package_pid(output, code))

    def test_foreign_quoted_malformed_and_oversized_logs_cannot_report_terms(self):
        variants = [MARKER.replace("5123", "1000"), MARKER.replace("Banzai", "System"),
                    MARKER.replace(" W ", " I "), MARKER.replace("5203", "0"),
                    MARKER.replace("11-15", "13-40"), MARKER.replace("06:47:50", "25:47:50"),
                    "quoted: "+MARKER, MARKER.rstrip()+" ignored\n",
                    "Terms of use not confirm!\n", MARKER+"\x00",
                    MARKER+"x"*R.MAX_TERMS_LOG_BYTES]
        for log in variants:
            with self.subTest(prefix=log[:100]):
                self.assertIsNone(R.unconfirmed_terms_marker(log, PID))
        self.assertIsNone(R.unconfirmed_terms_marker(MARKER, True))
        self.assertIsNone(R.unconfirmed_terms_marker(MARKER, 0))

    def test_changed_ambiguous_absent_pid_or_failed_logcat_cannot_report_terms(self):
        cases = [("5124\n",0,0), ("5123 5124\n",0,0), ("5123\n5123\n",0,0),
                 ("",1,0), ("5123\n",0,1)]
        for after, after_code, log_code in cases:
            with self.subTest(after=after, logCode=log_code), fixture():
                command_evidence("app-pid-0", "5123\n")
                def adb(tools, args, label, timeout, **kwargs):
                    self.assertEqual(kwargs["deadline"], 280.0)
                    if label == "terms-logcat-0":
                        self.assertEqual(args, ["logcat", "--pid=5123", "-d", "-v", "threadtime"])
                        self.assertEqual(kwargs["maximum"], R.MAX_TERMS_LOG_BYTES)
                        return command_evidence(label, MARKER, log_code)
                    self.assertEqual(label, "terms-pid-after-0")
                    self.assertEqual(args, ["shell", "pidof", R.PACKAGE])
                    return command_evidence(label, after, after_code)
                with patch.object(R, "adb_command", side_effect=adb) as command:
                    self.assertIsNone(R.observe_unconfirmed_terms({}, PID, 0, deadline=280.0))
                self.assertEqual(command.call_count, 2)

    def test_canvas_boundary_stops_first_sample_without_input_or_later_sleep(self):
        with fixture() as (run, state):
            def adb(tools, args, label, timeout, **kwargs):
                self.assertEqual(kwargs["deadline"], 280.0)
                expected = {"guest-network-0":["shell","cat","/proc/net/dev"],
                            "app-pid-0":["shell","pidof",R.PACKAGE],
                            "terms-logcat-0":["logcat","--pid=5123","-d","-v","threadtime"],
                            "terms-pid-after-0":["shell","pidof",R.PACKAGE]}
                self.assertIn(label, expected)
                self.assertEqual(args, expected[label])
                output = MARKER if label == "terms-logcat-0" else "5123\n"
                if label == "guest-network-0":
                    output = "lo: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0\n"
                return command_evidence(label, output)
            with patch.object(R, "adb_command", side_effect=adb) as command, \
                    patch.object(R, "snapshot", return_value=None) as snapshot, \
                    patch.object(R.time, "sleep", side_effect=AssertionError("must stop before sleep")):
                R.observe_client({}, state)
            self.assertEqual(command.call_count, 4)
            snapshot.assert_called_once_with({}, 0, deadline=280.0)
            self.assertEqual(state["observation"]["stopReason"], "new_terms_or_privacy_prompt")
            boundary = state["observation"]["unacceptedTermsBoundary"]
            self.assertTrue(boundary["sameUniquePackagePIDBeforeAndAfter"])
            self.assertEqual(boundary["marker"]["pid"], PID)
            self.assertEqual(boundary["inputActions"], 0)
            self.assertFalse(boundary["termsAccepted"])
            for row in boundary["evidence"]:
                raw = (run/"evidence"/row["file"]).read_bytes()
                receipt = json.loads((run/"evidence"/row["processReceipt"]).read_text())
                self.assertEqual(row["bytes"], len(raw))
                self.assertEqual(row["sha256"], hashlib.sha256(raw).hexdigest())
                self.assertEqual(receipt["sha256"], row["sha256"])
            self.assertEqual(state["executed"], {"apkDownloads":1,"emulatorBoots":1,"apkInstalls":1,"apkLaunches":1})
            saved = json.loads((run/"evidence/result.json").read_text())
            self.assertEqual(saved["observation"], state["observation"])

    def test_deadline_before_second_pid_read_cannot_turn_marker_into_boundary(self):
        with fixture() as (_, state):
            def adb(tools, args, label, timeout, **kwargs):
                self.assertEqual(kwargs["deadline"], 280.0)
                if label == "terms-pid-after-0":
                    raise R.ScopedDeadlineExpired("scoped_operation_deadline")
                if label == "terms-logcat-0":
                    return command_evidence(label, MARKER)
                if label == "app-pid-0":
                    return command_evidence(label, "5123\n")
                self.assertEqual(label, "guest-network-0")
                return command_evidence(label, "lo: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
            with patch.object(R, "adb_command", side_effect=adb) as command, \
                    patch.object(R, "snapshot", return_value=None), \
                    patch.object(R.time, "sleep", side_effect=AssertionError("must not extend deadline")):
                R.observe_client({}, state)
            self.assertEqual(command.call_count, 4)
            self.assertEqual(state["observation"]["stopReason"], "bounded_observation_complete")
            self.assertNotIn("unacceptedTermsBoundary", state["observation"])
            self.assertEqual(state["observation"]["limitSeconds"], 180)

    def test_existing_xml_boundary_does_not_start_the_fallback_probe(self):
        with fixture() as (_, state):
            def adb(tools, args, label, timeout, **kwargs):
                if label == "app-pid-0":
                    return command_evidence(label, "5123\n")
                self.assertEqual(label, "guest-network-0")
                return command_evidence(label, "lo: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
            with patch.object(R, "adb_command", side_effect=adb) as command, \
                    patch.object(R, "snapshot", return_value="new_terms_or_privacy_prompt"), \
                    patch.object(R, "observe_unconfirmed_terms") as fallback, \
                    patch.object(R.time, "sleep", side_effect=AssertionError("must stop before sleep")):
                R.observe_client({}, state)
            self.assertEqual(command.call_count, 2)
            fallback.assert_not_called()
            self.assertEqual(state["observation"]["stopReason"], "new_terms_or_privacy_prompt")
            self.assertNotIn("unacceptedTermsBoundary", state["observation"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
