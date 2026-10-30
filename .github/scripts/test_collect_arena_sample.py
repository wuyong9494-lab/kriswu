import copy
import unittest
from collect_arena_flow import validate_scene, is_scene_attachment, validate_recording_session
from run_arena_flow import actual_test_duration
import run_arena_flow as flow
from unittest.mock import Mock, patch


class FlowEvidenceTests(unittest.TestCase):
    def scene(self):
        return dict(kind='three-hero-ui-flow', playerHero=1, map='twin_gates_sample_v1',
                    qualitySample=True, finishedNaturally=True, forcedResult=False, simulationTime=150,
                    fighters=[dict(id=i, hero=(i % 3) + 1, team=i // 3) for i in range(6)],
                    events=[dict(kind='attack', fighter=0, simulationTime=6),
                            dict(kind='super', fighter=0, simulationTime=20)])

    def test_accepts_natural_scene_with_both_actions(self):
        self.assertEqual(validate_scene(self.scene(), 1), dict(attack=1, super=1))

    def test_rejects_injected_result_and_wrong_hero(self):
        scene = self.scene()
        scene['forcedResult'] = True
        with self.assertRaises(ValueError): validate_scene(scene, 1)
        with self.assertRaises(ValueError): validate_scene(self.scene(), 2)

    def test_other_fighters_super_does_not_count_as_player_demonstration(self):
        scene = self.scene()
        scene['events'][1]['fighter'] = 3
        with self.assertRaises(ValueError): validate_scene(scene, 1)

    def test_rejects_old_roster_and_backwards_event_clock(self):
        scene = self.scene()
        scene['fighters'][2]['hero'] = 0
        with self.assertRaises(ValueError): validate_scene(scene, 1)
        scene = self.scene()
        scene['events'].reverse()
        with self.assertRaises(ValueError): validate_scene(scene, 1)

class AttachmentNames(unittest.TestCase):
    def test_xcode_export_normalization(self):
        self.assertTrue(is_scene_attachment('arena-flow-hero-2_0_F6D924E2.json', 2))
        self.assertTrue(is_scene_attachment('arena-flow-hero-2.json', 2))
        self.assertFalse(is_scene_attachment('arena-flow-hero-2_0_F6D924E2.json', 1))
        self.assertFalse(is_scene_attachment('arena-flow-hero-20_0_id.json', 2))
        self.assertFalse(is_scene_attachment('arena-flow-hero-2_0_id.png', 2))


class ContinuousRecordingTests(unittest.TestCase):
    def session(self):
        return dict(complete=True, testExit=0, recorderExit=0,
                    recordingReadyBeforeTestCommand=True, testSeconds=290.072,
                    xcodeCommandSeconds=414.446)

    def test_uses_actual_test_not_installation_and_result_processing_time(self):
        log = "Test Case '-[ArenaFlowTests.ArenaFlowTests testBarbarianLoop]' failed (290.072 seconds)."
        self.assertEqual(actual_test_duration(log, 'testBarbarianLoop'), 290.072)
        validate_recording_session(self.session(), dict(presentationSpanSeconds=350.063))

    def test_missing_or_ambiguous_test_duration_fails(self):
        line = "Test Case '-[ArenaFlowTests.ArenaFlowTests testMageLoop]' passed (400.846 seconds)."
        for log, test in [('', 'testMageLoop'), (line + '\n' + line, 'testMageLoop'),
                          (line, 'testRangerLoop')]:
            with self.assertRaises(ValueError): actual_test_duration(log, test)

    def test_failed_test_unready_recorder_or_missing_duration_cannot_pass(self):
        for key, value in [('complete', False), ('testExit', 65), ('recorderExit', 1),
                           ('recordingReadyBeforeTestCommand', False), ('testSeconds', None),
                           ('testSeconds', float('nan')), ('testSeconds', 0)]:
            session = self.session()
            session[key] = value
            with self.assertRaises(ValueError):
                validate_recording_session(session, dict(presentationSpanSeconds=350.063))

    def test_truncated_continuous_recording_still_fails(self):
        with self.assertRaises(ValueError):
            validate_recording_session(self.session(), dict(presentationSpanSeconds=280))


class XCTestFinalizationTests(unittest.TestCase):
    def test_success_does_not_interrupt_runner(self):
        runner = Mock(pid=123)
        runner.wait.return_value = 0
        with patch.object(flow.subprocess, 'Popen', return_value=runner), patch.object(flow.os, 'killpg') as kill:
            self.assertEqual(flow.run_xctest(['xcodebuild'], Mock()), 0)
            kill.assert_not_called()

    def test_timeout_flushes_result_but_remains_failure(self):
        runner = Mock(pid=123)
        runner.wait.side_effect = [flow.subprocess.TimeoutExpired('xcodebuild', 720), 0]
        with patch.object(flow.subprocess, 'Popen', return_value=runner), patch.object(flow.os, 'killpg') as kill:
            with self.assertRaises(flow.subprocess.TimeoutExpired):
                flow.run_xctest(['xcodebuild'], Mock())
            kill.assert_called_once_with(123, flow.signal.SIGINT)

    def test_stuck_finalization_is_killed_and_never_passes(self):
        runner = Mock(pid=123)
        runner.wait.side_effect = [flow.subprocess.TimeoutExpired('xcodebuild', 720),
                                  flow.subprocess.TimeoutExpired('xcodebuild', 30), -9]
        with patch.object(flow.subprocess, 'Popen', return_value=runner), patch.object(flow.os, 'killpg') as kill:
            with self.assertRaises(flow.subprocess.TimeoutExpired):
                flow.run_xctest(['xcodebuild'], Mock())
            self.assertEqual([c.args[1] for c in kill.call_args_list], [flow.signal.SIGINT, flow.signal.SIGKILL])
