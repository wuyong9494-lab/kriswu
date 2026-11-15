#!/usr/bin/env python3
"""Six new ABI-selection boundaries; synthetic text and mocked ADB only.

No APK, emulator, SDK command, native library, network request or prior success
suite is executed. Package-dump layout follows Android 11 Settings.java.
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
    "android_install_abi_delta", Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


def package_dump(primary="armeabi-v7a"):
    return "\n".join((
        "Activity Resolver Table:", "  synthetic resolver entries", "", "Packages:",
        "  Package [com.nekki.shadowfight3] (abc123):", "    userId=10167",
        "    codePath=/data/app/synthetic/com.nekki.shadowfight3",
        "    legacyNativeLibraryDir=/data/app/synthetic/com.nekki.shadowfight3/lib",
        "    primaryCpuAbi="+primary, "    secondaryCpuAbi=null",
        "    versionCode=19221 minSdk=26 targetSdk=36", "    User 0: installed=true", ""))


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory() as directory:
        run = Path(directory)/"owned-run"
        (run/"downloads").mkdir(parents=True)
        (run/"evidence").mkdir()
        apk = run/"downloads/19221.apk"
        apk.write_bytes(b"synthetic upstream-verified APK placeholder; never installed")
        state = {"executed":{"apkDownloads":1, "emulatorBoots":1, "apkInstalls":0, "apkLaunches":0},
            "gates":{"apkABICompatible":True, "apkInstalled":False, "normalLaunchObserved":False},
            "deviceProperties":{"ro.product.cpu.abilist32":"x86,armeabi-v7a,armeabi"},
            "apk":{"sha256":R.APK_RECEIVED_SHA256, "nativeLibraries":{"arm64-v8a":24,"armeabi-v7a":24}}}
        with patch.object(R, "work", return_value=run):
            yield run, apk, state


def process_evidence(label, output, exit_code=0):
    raw = output.encode()
    (R.evidence()/(label+".log")).write_bytes(raw)
    R.write_json(R.evidence()/(label+"-process.json"), {"exitCode":exit_code,
        "elapsedSeconds":0.001, "bytes":len(raw), "sha256":hashlib.sha256(raw).hexdigest()})
    return output, exit_code


class InstallABISelectionDelta(unittest.TestCase):
    def test_unsupported_or_unverified_variant_stops_before_install_or_launch(self):
        for invalid in ("guest_abi", "apk_library", "apk_identity", "compatibility_gate"):
            with self.subTest(invalid=invalid), fixture() as (run, apk, state):
                if invalid == "guest_abi":
                    state["deviceProperties"]["ro.product.cpu.abilist32"] = "x86"
                elif invalid == "apk_library":
                    state["apk"]["nativeLibraries"]["armeabi-v7a"] = 0
                elif invalid == "apk_identity":
                    state["apk"]["sha256"] = "0" * 64
                else:
                    state["gates"]["apkABICompatible"] = False
                with patch.object(R, "adb_command") as command:
                    with self.assertRaisesRegex(R.Blocked, "installed_abi_requested_variant_unavailable"):
                        R.launch({}, apk, state)
                command.assert_not_called()
                self.assertEqual(state["executed"]["apkInstalls"], 0)
                self.assertEqual(state["executed"]["apkLaunches"], 0)
                self.assertFalse(state["gates"]["apkInstalled"])
                receipt = json.loads((run/"evidence/installed-package-abi-selection.json").read_text())
                self.assertEqual(receipt["phase"], "failed")
                self.assertEqual(receipt["installAttempts"], 0)
                self.assertEqual(receipt["inspectionAttempts"], 0)
                self.assertFalse(receipt["installedABIConfirmed"])

    def test_failed_install_preserves_failure_receipt_without_inspection_or_launch(self):
        with fixture() as (run, apk, state):
            def adb(tools, args, label, timeout, **kwargs):
                self.assertEqual(label, "official-apk-install")
                process_evidence(label, "Failure [INSTALL_FAILED_NO_MATCHING_ABIS]\n", 1)
                raise R.Blocked("command_failed_official-apk-install")
            with patch.object(R, "adb_command", side_effect=adb) as command:
                with self.assertRaisesRegex(R.Blocked, "command_failed_official-apk-install"):
                    R.launch({}, apk, state)
            self.assertEqual(command.call_count, 1)
            self.assertEqual(state["executed"]["apkInstalls"], 1)
            self.assertEqual(state["executed"]["apkLaunches"], 0)
            self.assertFalse(state["gates"]["apkInstalled"])
            receipt = json.loads((run/"evidence/installed-package-abi-selection.json").read_text())
            self.assertEqual(receipt["phase"], "failed")
            self.assertEqual(receipt["installProcess"]["exitCode"], 1)
            self.assertEqual(receipt["inspectionAttempts"], 0)
            self.assertFalse(receipt["installSucceeded"])
            self.assertFalse(receipt["installedABIConfirmed"])

    def test_exact_target_v7a_is_installation_evidence_and_legacy_path_is_not_relabelled(self):
        value = R.inspect_installed_package_abi(package_dump(), 0)
        self.assertTrue(value["installedABIConfirmed"])
        self.assertEqual(value["packageName"], R.PACKAGE)
        self.assertEqual(value["primaryCpuAbi"], "armeabi-v7a")
        self.assertIsNone(value["secondaryCpuAbi"])
        self.assertEqual(value["fieldOccurrences"]["secondaryCpuAbi"], 1)
        self.assertEqual(value["legacyNativeLibraryDir"], "/data/app/synthetic/com.nekki.shadowfight3/lib")
        self.assertIsNone(value["nativeLibraryDir"])
        self.assertEqual(value["nativeLibraryDirBasis"], "not_reported")
        explicitly_reported = package_dump().replace("    primaryCpuAbi=", "    nativeLibraryDir=/data/app/synthetic/lib/arm\n    primaryCpuAbi=")
        self.assertEqual(R.inspect_installed_package_abi(explicitly_reported, 0)["nativeLibraryDir"],
                         "/data/app/synthetic/lib/arm")

    def test_missing_conflicting_foreign_64bit_and_unsuccessful_dumps_cannot_authorize_launch(self):
        original = package_dump()
        variants = [
            (package_dump("arm64-v8a"), 0),
            (package_dump("null"), 0),
            (original.replace("    primaryCpuAbi=armeabi-v7a\n", ""), 0),
            (original.replace("    primaryCpuAbi=armeabi-v7a", "    primaryCpuAbi=armeabi-v7a\n    primaryCpuAbi=arm64-v8a"), 0),
            (original.replace("    primaryCpuAbi=armeabi-v7a", "    primaryCpuAbi=armeabi-v7a\n    primaryCpuAbi=armeabi-v7a"), 0),
            (original.replace("com.nekki.shadowfight3", "com.example.foreign"), 0),
            (original+"  Package [com.nekki.shadowfight3] (def456):\n    primaryCpuAbi=armeabi-v7a\n", 0),
            (original.replace("Packages:", "Hidden system packages:"), 0),
            (original.replace("    primaryCpuAbi=armeabi-v7a", "      primaryCpuAbi=armeabi-v7a"), 0),
            (original, 1), (original, False),
        ]
        for text, code in variants:
            with self.subTest(exitCode=code, text=text):
                value = R.inspect_installed_package_abi(text, code)
                self.assertFalse(value["installedABIConfirmed"])
                self.assertIsInstance(value["failureReason"], str)
        wrong = R.inspect_installed_package_abi(package_dump("arm64-v8a"), 0)
        self.assertEqual(wrong["primaryCpuAbi"], "arm64-v8a")

    def test_successful_install_survives_ignored_override_or_inspection_error_without_any_launch(self):
        for inspection_failure in (False, True):
            with self.subTest(inspectionFailure=inspection_failure), fixture() as (run, apk, state):
                def adb(tools, args, label, timeout, **kwargs):
                    if label == "official-apk-install":
                        return process_evidence(label, "Performing Streamed Install\nSuccess\n")
                    self.assertEqual(label, "installed-package-abi")
                    self.assertTrue(json.loads((run/"evidence/result.json").read_text())["gates"]["apkInstalled"])
                    if inspection_failure:
                        process_evidence(label, "synthetic inspection error\n", 1)
                        raise R.Blocked("command_failed_installed-package-abi")
                    return process_evidence(label, package_dump("arm64-v8a"))
                with patch.object(R, "adb_command", side_effect=adb) as command, \
                        patch.object(R, "observe_client") as observe, patch.object(R, "collect_cache") as cache:
                    with self.assertRaises(R.Blocked):
                        R.launch({}, apk, state)
                self.assertEqual([call.args[2] for call in command.call_args_list],
                                 ["official-apk-install", "installed-package-abi"])
                observe.assert_not_called()
                cache.assert_not_called()
                self.assertTrue(state["gates"]["apkInstalled"])
                self.assertFalse(state["gates"]["normalLaunchObserved"])
                self.assertEqual(state["executed"]["apkInstalls"], 1)
                self.assertEqual(state["executed"]["apkLaunches"], 0)
                receipt = json.loads((run/"evidence/installed-package-abi-selection.json").read_text())
                self.assertEqual(receipt, state["installedABISelection"])
                self.assertTrue(receipt["installSucceeded"])
                self.assertFalse(receipt["installedABIConfirmed"])
                self.assertFalse(receipt["runtimeABIConfirmed"])
                self.assertEqual(receipt["phase"], "failed")
                self.assertEqual(receipt["installProcess"]["exitCode"], 0)
                self.assertEqual(receipt["inspectionProcess"]["exitCode"], 1 if inspection_failure else 0)
                self.assertEqual(receipt["launchesBefore"], receipt["launchesAfter"])
                if not inspection_failure:
                    self.assertEqual(receipt["observedPackage"]["primaryCpuAbi"], "arm64-v8a")

    def test_one_verified_v7a_install_precedes_one_normal_activity_launch_without_runtime_abi_claim(self):
        with fixture() as (run, apk, state):
            def adb(tools, args, label, timeout, **kwargs):
                responses = {"official-apk-install":"Success\n", "installed-package-abi":package_dump(),
                    "main-activity-resolver":R.PACKAGE+"/com.unity3d.player.UnityPlayerActivity\n",
                    "official-app-start":"Status: ok\n"}
                self.assertIn(label, responses)
                if label in ("main-activity-resolver", "official-app-start"):
                    self.assertTrue(state["installedABISelection"]["installedABIConfirmed"])
                return process_evidence(label, responses[label])
            with patch.object(R, "adb_command", side_effect=adb) as command, \
                    patch.object(R, "observe_client") as observe, patch.object(R, "collect_cache") as cache:
                R.launch({}, apk, state)
                self.assertEqual(command.call_args_list[0].args,
                    ({}, ["install", "--abi", "armeabi-v7a", str(apk)], "official-apk-install", 90))
                self.assertEqual(command.call_args_list[1].args,
                    ({}, ["shell", "dumpsys", "package", R.PACKAGE], "installed-package-abi", 20))
                self.assertEqual([call.args[2] for call in command.call_args_list],
                    ["official-apk-install", "installed-package-abi", "main-activity-resolver", "official-app-start"])
                observe.assert_called_once_with({}, state)
                cache.assert_called_once_with({}, state)
                with self.assertRaisesRegex(R.Blocked, "installed_abi_selection_already_attempted"):
                    R.install_official_apk_for_abi({}, apk, state)
                self.assertEqual(command.call_count, 4)
            self.assertEqual(state["executed"]["apkInstalls"], 1)
            self.assertEqual(state["executed"]["apkLaunches"], 1)
            self.assertTrue(state["gates"]["normalLaunchObserved"])
            receipt = state["installedABISelection"]
            self.assertTrue(receipt["installedABIConfirmed"])
            self.assertEqual(receipt["phase"], "installed_abi_verified")
            self.assertEqual(receipt["launchesBefore"], 0)
            self.assertEqual(receipt["launchesAfter"], 0)
            self.assertFalse(receipt["runtimeABIConfirmed"])
            summary = R.installed_abi_summary(receipt)
            self.assertEqual(summary["primaryCpuAbi"], "armeabi-v7a")
            self.assertFalse(summary["runtimeABIConfirmed"])
            self.assertFalse(summary["nativeLibraryDirReported"])
            self.assertTrue(summary["legacyNativeLibraryDirReported"])
            self.assertNotIn("/data/app/", json.dumps(summary))


if __name__ == "__main__":
    unittest.main(verbosity=2)
