import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import record_arena_sample as capture


class RecordingContractTests(unittest.TestCase):
    def exercise(self, identity, recorder_failure=False):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'Documents').mkdir()
            output = root / 'capture'
            class Recorder:
                pid = 987654
                returncode = None
                interrupted = False
                def poll(self): return self.returncode
                def send_signal(self, value): self.interrupted = True
                def wait(self, timeout):
                    self.returncode = 1 if recorder_failure else 0
                    return self.returncode
            recorder = Recorder()
            def spawn(args, **kwargs):
                pathlib.Path(args[-1]).write_bytes(b'fixture' * 200)
                return recorder
            def sim(*args, **kwargs):
                if args[0] == 'get_app_container': return str(root)
                if args[0] == 'launch':
                    (root / 'Documents/arena-capture-ready.json').write_text(json.dumps(identity))
                return ''
            with patch.object(sys, 'argv', ['record', 'test-device', str(output)]), \
                 patch.object(capture, 'stop_app'), patch.object(capture, 'simctl', side_effect=sim), \
                 patch.object(capture.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(capture.time, 'sleep'), \
                 patch.object(capture.os, 'killpg', side_effect=lambda pid, value: recorder.send_signal(value)):
                error = None
                try: capture.main()
                except (AssertionError, RuntimeError) as caught: error = caught
            return error, recorder.interrupted, (output / 'harbor-opening.json').exists()

    def test_only_verified_recording_receives_identity_record(self):
        error, stopped, exists = self.exercise(dict(simulationTime=6.0,
            map='twin_gates_sample_v1', rangerAsset='Ranger_FaceSample.glb', qualitySample=True))
        self.assertIsNone(error)
        self.assertTrue(stopped)
        self.assertTrue(exists)

    def test_wrong_map_is_stopped_and_not_certified(self):
        error, stopped, exists = self.exercise(dict(simulationTime=6.0,
            map='canyon', rangerAsset='Ranger_FaceSample.glb', qualitySample=True))
        self.assertIsInstance(error, AssertionError)
        self.assertTrue(stopped)
        self.assertFalse(exists)

    def test_failed_recorder_is_not_certified(self):
        error, stopped, exists = self.exercise(dict(simulationTime=6.0,
            map='twin_gates_sample_v1', rangerAsset='Ranger_FaceSample.glb', qualitySample=True), True)
        self.assertIsInstance(error, RuntimeError)
        self.assertTrue(stopped)
        self.assertFalse(exists)


if __name__ == '__main__': unittest.main()
