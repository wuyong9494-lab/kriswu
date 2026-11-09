import copy
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib
from prepare_star_simulator import capture_ready, selection, valid_png, wait_for_boot


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0\0\0\0\xff")) + chunk(b"IEND", b""))


class SimulatorSelectionTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {
            "devicetypes": [{"name": "iPhone 17 Pro Max", "identifier": "exact-model"},
                            {"name": "iPhone 17", "identifier": "other-model"}],
            "runtimes": [{"identifier": "runtime.iOS-26-2", "version": "26.2", "isAvailable": True},
                         {"identifier": "runtime.iOS-26-10", "version": "26.10", "isAvailable": True},
                         {"identifier": "runtime.iOS-27", "version": "27.0", "isAvailable": False},
                         {"identifier": "runtime.watchOS-27", "version": "27.0", "isAvailable": True}],
        }

    def testSelectsExactModelAndNumericallyNewestAvailableIOS(self):
        self.assertEqual(selection(self.catalog), ("exact-model", "runtime.iOS-26-10"))

    def testCannotSubstituteAnotherPhoneOrUnavailableRuntime(self):
        missing_model = copy.deepcopy(self.catalog)
        missing_model["devicetypes"].pop(0)
        unavailable = copy.deepcopy(self.catalog)
        for runtime in unavailable["runtimes"]:
            runtime["isAvailable"] = False
        for catalog in (missing_model, unavailable, {}):
            with self.subTest(catalog=catalog), self.assertRaises(ValueError):
                selection(catalog)

    def testOldIOSAndAmbiguousModelDoNotQualify(self):
        old = copy.deepcopy(self.catalog)
        old["runtimes"] = [{"identifier": "runtime.iOS-18-6", "version": "18.6", "isAvailable": True}]
        duplicate = copy.deepcopy(self.catalog)
        duplicate["devicetypes"].append(dict(duplicate["devicetypes"][0]))
        for catalog in (old, duplicate):
            with self.assertRaises(ValueError):
                selection(catalog)


class SimulatorDisplayTests(unittest.TestCase):
    def testIncompleteOrCorruptScreenshotsCannotPass(self):
        image = png()
        self.assertTrue(valid_png(image))
        for data in (b"", image[:24], image[:-1], image + b"extra", image[:-5] + b"wrong"):
            self.assertFalse(valid_png(data))

    @patch("prepare_star_simulator.time.sleep")
    def testColdDisplayTimeoutRequiresANewSuccessfulCapture(self, sleep):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / "ready.png"
            calls = []
            def run(command, **kwargs):
                self.assertFalse(destination.exists())
                calls.append(command)
                destination.write_bytes(png())
                if len(calls) == 1:
                    raise subprocess.TimeoutExpired(command, 45)
                return subprocess.CompletedProcess(command, 0)
            with patch("prepare_star_simulator.subprocess.run", side_effect=run):
                capture_ready("exact-device", destination)
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[1][3], "exact-device")
            self.assertTrue(valid_png(destination.read_bytes()))
            sleep.assert_called_once_with(2)

    @patch("prepare_star_simulator.time.sleep")
    def testAllFailedAttemptsBlockAcceptanceAndRemoveStaleImage(self, sleep):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / "ready.png"
            destination.write_bytes(png())
            with patch("prepare_star_simulator.subprocess.run",
                       side_effect=subprocess.TimeoutExpired("screenshot", 45)) as run:
                with self.assertRaises(RuntimeError):
                    capture_ready("exact-device", destination)
                self.assertEqual(run.call_count, 3)
            self.assertFalse(destination.exists())


class SimulatorBootTests(unittest.TestCase):
    def catalog(self, state="Booted", available=True, udid="target"):
        return json.dumps({"devices": {"runtime": [
            {"udid": udid, "state": state, "isAvailable": available}]}}).encode()

    @patch("prepare_star_simulator.subprocess.check_output")
    @patch("prepare_star_simulator.subprocess.run")
    def testSuccessfulBootDoesNotRetryOrInspect(self, run, inspect):
        wait_for_boot("target")
        run.assert_called_once_with(["xcrun", "simctl", "bootstatus", "target", "-b"],
                                    check=True, timeout=240)
        inspect.assert_not_called()

    @patch("prepare_star_simulator.subprocess.check_output")
    @patch("prepare_star_simulator.subprocess.run")
    def testColdBootWaitsOnceMoreOnExactStillBootingDevice(self, run, inspect):
        run.side_effect = [subprocess.TimeoutExpired("bootstatus", 240), None]
        inspect.return_value = self.catalog()
        wait_for_boot("target", retry_cold_boot=True)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0].args, run.call_args_list[1].args)
        self.assertEqual(run.call_args_list[1].kwargs, {"check": True, "timeout": 180})

    @patch("prepare_star_simulator.subprocess.check_output")
    @patch("prepare_star_simulator.subprocess.run")
    def testSecondTimeoutRemainsFailure(self, run, inspect):
        run.side_effect = subprocess.TimeoutExpired("bootstatus", 240)
        inspect.return_value = self.catalog()
        with self.assertRaises(subprocess.TimeoutExpired):
            wait_for_boot("target", retry_cold_boot=True)
        self.assertEqual(run.call_count, 2)

    def testMissingShutdownOrUnavailableTargetCannotBeSubstituted(self):
        for data in [self.catalog(state="Shutdown"), self.catalog(available=False),
                     self.catalog(udid="another-device"), b'{"devices": {}}']:
            with self.subTest(data=data), patch("prepare_star_simulator.subprocess.run",
                    side_effect=subprocess.TimeoutExpired("bootstatus", 240)) as run, \
                    patch("prepare_star_simulator.subprocess.check_output", return_value=data):
                with self.assertRaises(RuntimeError):
                    wait_for_boot("target", retry_cold_boot=True)
                self.assertEqual(run.call_count, 1)

    @patch("prepare_star_simulator.subprocess.check_output")
    @patch("prepare_star_simulator.subprocess.run")
    def testNonTimeoutBootFailureIsNotRetried(self, run, inspect):
        run.side_effect = subprocess.CalledProcessError(1, "bootstatus")
        with self.assertRaises(subprocess.CalledProcessError):
            wait_for_boot("target", retry_cold_boot=True)
        run.assert_called_once()
        inspect.assert_not_called()


    @patch("prepare_star_simulator.subprocess.check_output")
    @patch("prepare_star_simulator.subprocess.run")
    def testDefaultKeepsExistingSharedWorkflowBudget(self, run, inspect):
        run.side_effect = subprocess.TimeoutExpired("bootstatus", 240)
        with self.assertRaises(subprocess.TimeoutExpired):
            wait_for_boot("target")
        run.assert_called_once()
        inspect.assert_not_called()
