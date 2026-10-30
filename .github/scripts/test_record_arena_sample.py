import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import record_arena_sample as capture
from check_arena_video import validate_frames


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


class TraversalEvidenceTests(unittest.TestCase):
    def fixture(self):
        trace = [dict(time=i * .1, x=2.5, y=10.5) for i in range(80)]
        trace[40].update(x=5.5, y=9.45)
        return dict(captureTraversal=True, routeComplete=True, routeTrace=trace)

    def test_completed_route_requires_both_wall_and_grass_positions(self):
        evidence = self.fixture()
        capture.validate_traversal(evidence)
        evidence['routeTrace'][40]['y'] = 10.5
        with self.assertRaises(RuntimeError): capture.validate_traversal(evidence)

    def test_stalled_route_cannot_pass(self):
        evidence = self.fixture()
        evidence['routeComplete'] = False
        with self.assertRaises(RuntimeError): capture.validate_traversal(evidence)

    def test_nonmonotonic_trace_cannot_pass(self):
        evidence = self.fixture()
        evidence['routeTrace'][40]['time'] = 0
        with self.assertRaises(RuntimeError): capture.validate_traversal(evidence)


class PresentationTimestampTests(unittest.TestCase):
    def frames(self):
        return [dict(pts_time=str(i / 10), best_effort_timestamp_time=str(i / 10), width=1320, height=2868) for i in range(80)]

    def test_duplicate_pts_does_not_use_backward_guessed_time(self):
        frames = self.frames()
        frames[21].update(pts_time='2.0', best_effort_timestamp_time='-0.4')
        span, duplicates = validate_frames(frames)
        self.assertEqual(duplicates, 1)
        self.assertAlmostEqual(span, 7.9)

    def test_actual_backward_presentation_time_is_rejected(self):
        frames = self.frames()
        frames[21]['pts_time'] = '1.9'
        with self.assertRaises(RuntimeError): validate_frames(frames)

    def test_nan_presentation_time_is_rejected(self):
        frames = self.frames()
        frames[21]['pts_time'] = 'nan'
        with self.assertRaises(RuntimeError): validate_frames(frames)


if __name__ == '__main__': unittest.main()
