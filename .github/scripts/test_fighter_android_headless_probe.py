#!/usr/bin/env python3
"""New headless-probe boundaries only; no SDK, apt, emulator, APK or network.

Temporary files and command/process records below are synthetic. They do not
claim that the real installed emulator or its shared libraries have executed.
"""
from contextlib import contextmanager, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "android_headless_probe_delta", Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)

COUNTERS = {key:0 for key in ("apkDownloads", "emulatorBoots", "apkInstalls", "apkLaunches")}
HEADLESS = "emulator/qemu/linux-x86_64/qemu-system-x86_64-headless"


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory() as directory:
        run = Path(directory)/"owned-run"
        sdk_root = run/"sdk"
        launcher = sdk_root/"emulator/emulator"
        member = sdk_root/HEADLESS
        for path in (launcher, member):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic executable fixture\n" + path.name.encode())
            path.chmod(0o700)
        (run/"evidence").mkdir()
        sdk = {"private_sdk_root":str(sdk_root), "emulator_path":str(launcher)}
        state = {"executed":dict(COUNTERS), "gates":{"sdkInstalled":True}}
        with patch.object(R, "work", return_value=run), \
                patch.object(R, "android_env", return_value={"SYNTHETIC_ENV":"headless"}):
            yield run, sdk, state, member


def fake_process(exit_code):
    """Write a bounded synthetic command receipt, never start a child process."""
    raw = b"synthetic emulator result\n"
    (R.evidence()/"emulator-version.log").write_bytes(raw)
    process = {"exitCode":exit_code, "elapsedSeconds":0.001,
               "bytes":len(raw), "sha256":hashlib.sha256(raw).hexdigest()}
    R.write_json(R.evidence()/"emulator-version-process.json", process)
    return raw.decode(), exit_code


class HeadlessProbeDelta(unittest.TestCase):
    def test_success_uses_one_mode_matched_probe_and_does_not_count_a_boot(self):
        with fixture() as (run, sdk, state, member):
            with patch.object(R, "command", side_effect=lambda *a, **k:fake_process(0)) as command:
                R.probe_headless_runtime(sdk, state)
                command.assert_called_once_with(
                    [Path(sdk["emulator_path"]), "-no-window", "-no-audio", "-version"],
                    "emulator-version", 30, env={"SYNTHETIC_ENV":"headless"})
                with self.assertRaisesRegex(R.Blocked, "headless_runtime_probe_already_attempted"):
                    R.probe_headless_runtime(sdk, state)
                self.assertEqual(command.call_count, 1)
            receipt = json.loads((run/"evidence/emulator-headless-probe.json").read_text())
            self.assertEqual(receipt, state["headlessRuntimeProbe"])
            self.assertTrue(receipt["passed"])
            self.assertEqual(receipt["phase"], "passed")
            self.assertEqual(receipt["probeAttempts"], 1)
            self.assertTrue(receipt["processStarted"])
            self.assertEqual(receipt["exitCode"], 0)
            self.assertEqual(receipt["headlessMember"]["relativePath"], HEADLESS)
            self.assertEqual(receipt["headlessMember"]["sha256"], hashlib.sha256(member.read_bytes()).hexdigest())
            self.assertEqual(receipt["headlessMember"]["bytes"], member.stat().st_size)
            self.assertTrue(receipt["sdkRootOwned"])
            self.assertFalse(receipt["countsAsEmulatorBoot"])
            self.assertFalse(receipt["librarySearchPathOverridden"])
            self.assertEqual(receipt["hostPackagesInstalled"], 0)
            self.assertEqual(receipt["countersBefore"], COUNTERS)
            self.assertEqual(receipt["countersAfter"], COUNTERS)
            self.assertEqual(state["executed"], COUNTERS)

    def test_missing_link_nonfile_nonexecutable_or_foreign_member_never_invokes_a_probe(self):
        for variant in ("missing", "symlink", "directory", "nonexecutable", "foreign_launcher"):
            with self.subTest(variant=variant), fixture() as (run, sdk, state, member):
                if variant == "foreign_launcher":
                    sdk["emulator_path"] = str(run/"foreign-emulator")
                elif variant == "nonexecutable":
                    member.chmod(0o600)
                else:
                    member.unlink()
                    if variant == "directory":
                        member.mkdir()
                    elif variant == "symlink":
                        outside = run/"foreign-member"
                        outside.write_bytes(b"synthetic foreign executable")
                        outside.chmod(0o700)
                        member.symlink_to(outside)
                with patch.object(R, "command") as command, self.assertRaises(R.Blocked):
                    R.probe_headless_runtime(sdk, state)
                command.assert_not_called()
                receipt = state["headlessRuntimeProbe"]
                self.assertFalse(receipt["passed"])
                self.assertEqual(receipt["phase"], "failed")
                self.assertEqual(receipt["probeAttempts"], 0)
                self.assertFalse(receipt["processStarted"])
                self.assertIsNone(receipt["exitCode"])
                self.assertEqual(receipt["countersAfter"], COUNTERS)

    def test_failed_probe_preserves_real_exit_or_unverified_pre_process_boundary(self):
        for exit_code in (127, None):
            with self.subTest(exitCode=exit_code), fixture() as (run, sdk, state, member):
                def fail(*args, **kwargs):
                    if exit_code is None:
                        (R.evidence()/"emulator-version.log").write_bytes(b"")
                    else:
                        fake_process(exit_code)
                    raise R.Blocked("synthetic_probe_failure")
                with patch.object(R, "command", side_effect=fail) as command, \
                        self.assertRaisesRegex(R.Blocked, "synthetic_probe_failure"):
                    R.probe_headless_runtime(sdk, state)
                command.assert_called_once()
                receipt = json.loads((run/"evidence/emulator-headless-probe.json").read_text())
                self.assertEqual(receipt["phase"], "failed")
                self.assertFalse(receipt["passed"])
                self.assertEqual(receipt["probeAttempts"], 1)
                self.assertEqual(receipt["exitCode"], exit_code)
                self.assertIs(receipt["processStarted"], True if exit_code is not None else None)
                self.assertEqual(receipt["phaseFailure"], "synthetic_probe_failure")
                self.assertEqual(receipt["countersBefore"], receipt["countersAfter"])
                self.assertEqual(state["executed"], COUNTERS)

    def test_failed_member_gate_stops_real_orchestration_before_apk_kvm_and_boot(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)/"owned-run"
            def synthetic_install(*args):
                launcher = run/"sdk/emulator/emulator"
                launcher.parent.mkdir(parents=True)
                launcher.write_bytes(b"synthetic launcher; headless member deliberately absent")
                launcher.chmod(0o700)
                return {"private_sdk_root":str(run/"sdk"), "emulator_path":str(launcher),
                    "receipt":{"licenseAcceptedForExactText":True, "installedExactPackagesVerified":True}}
            installed = Mock(side_effect=synthetic_install)
            cleanup = {"emulatorStopped":True, "adbStopped":True, "kvmRestored":True, "errors":[]}
            with patch.object(R, "admit"), patch.object(R, "work", return_value=run), \
                    patch.object(R, "tools_inventory", return_value={}), \
                    patch.object(R.importlib, "import_module", return_value=SimpleNamespace(install=installed)), \
                    patch.object(R, "license_acceptance_summary", side_effect=lambda receipt=None:{"approvedTermsAccepted":bool(receipt)}), \
                    patch.object(R, "merge_sdk_progress"), patch.object(R, "stop_owned", return_value=cleanup), \
                    patch.object(R, "command") as command, patch.object(R, "download_apk_once") as download, \
                    patch.object(R, "verify_apk") as verify, patch.object(R, "prepare_kvm") as kvm, \
                    patch.object(R, "start_emulator") as boot, patch.object(R, "launch") as launch, \
                    patch.dict(R.os.environ, {"GITHUB_SHA":"a"*40, "GITHUB_RUN_ID":"12345", "GITHUB_STEP_SUMMARY":""}), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(R.run(), 1)
            installed.assert_called_once()
            for operation in (command, download, verify, kvm, boot, launch):
                operation.assert_not_called()
            result = json.loads((run/"evidence/result.json").read_text())
            self.assertTrue(result["gates"]["sdkInstalled"])
            self.assertEqual(result["failureReason"], "headless_probe_headlessMember_missing")
            self.assertEqual(result["headlessRuntimeProbe"]["probeAttempts"], 0)
            self.assertEqual(result["executed"], COUNTERS)
            public = json.loads((run/"evidence/public-summary.json").read_text())
            self.assertEqual(public["headlessRuntimeProbe"], result["headlessRuntimeProbe"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
