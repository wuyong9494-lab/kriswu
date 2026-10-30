import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import record_arena_sample as capture
from check_arena_video import validate_frames, timing_evidence


class RecordingContractTests(unittest.TestCase):
    def exercise(self, identity, recorder_failure=False, finalization_timeout=False):
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
                    if finalization_timeout and timeout == 90:
                        raise capture.subprocess.TimeoutExpired('recordVideo', timeout)
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
            if finalization_timeout:
                diagnostic = json.loads((output / 'harbor-opening.recording.json').read_text())
                self.assertEqual(diagnostic['phase'], 'finalization-timeout')
                self.assertFalse(diagnostic['mediaFinalized'])
                self.assertEqual(diagnostic['sceneEvidence']['map'], identity['map'])
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

    def test_finalization_timeout_retains_scene_without_certifying_video(self):
        error, stopped, exists = self.exercise(dict(simulationTime=6.0,
            map='twin_gates_sample_v1', rangerAsset='Ranger_FaceSample.glb', qualitySample=True), finalization_timeout=True)
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


class TimingEvidenceTests(unittest.TestCase):
    def test_packet_collision_is_reported_without_mutating_frames(self):
        frames = [dict(pts=10, pts_time='0.1'), dict(pts=10, pts_time='0.1'), dict(pts=11, pts_time='0.11')]
        original = [dict(f) for f in frames]
        packets = [dict(pts=10, dts=8, pos='100'), dict(pts=10, dts=9, pos='120')]
        report = timing_evidence(frames, packets)
        self.assertEqual(report['timingAcceptance'], 'needs-review')
        self.assertEqual(report['duplicateGroups'][0]['frameIndices'], [0, 1])
        self.assertEqual(len(report['duplicateGroups'][0]['packetEvidence']), 2)
        self.assertEqual(frames, original)

    def test_missing_pts_cannot_claim_strict_timing(self):
        report = timing_evidence([dict(best_effort_timestamp_time='1')], [])
        self.assertEqual(report['framesWithoutActualPTS'], 1)
        self.assertEqual(report['timingAcceptance'], 'needs-review')

    def test_unique_pts_have_no_collision(self):
        report = timing_evidence([dict(pts=1), dict(pts=2)], [])
        self.assertEqual(report['duplicateGroups'], [])
        self.assertEqual(report['timingAcceptance'], 'strictly-increasing')


class RecordingIsolationTests(unittest.TestCase):
    def test_traversal_restarts_only_its_dedicated_simulator(self):
        with patch.object(capture, 'stop_app') as stop, patch.object(capture, 'simctl') as sim:
            capture.prepare_recording_device('capture-device', True)
        stop.assert_called_once_with('capture-device')
        self.assertEqual([c.args for c in sim.call_args_list], [
            ('shutdown', 'capture-device'), ('boot', 'capture-device'),
            ('bootstatus', 'capture-device', '-b')])

    def test_opening_does_not_restart_simulator(self):
        with patch.object(capture, 'stop_app'), patch.object(capture, 'simctl') as sim:
            capture.prepare_recording_device('capture-device', False)
        sim.assert_not_called()

    def test_restart_failure_is_not_ignored(self):
        with patch.object(capture, 'stop_app'), patch.object(capture, 'simctl', side_effect=RuntimeError('boot failed')):
            with self.assertRaises(RuntimeError): capture.prepare_recording_device('capture-device', True)

if __name__ == '__main__': unittest.main()

