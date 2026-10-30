import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('capture', pathlib.Path(__file__).with_name('capture_arena_sample.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)

class CaptureIdentityTests(unittest.TestCase):
    def run_capture(self, scene, wrong_map=False):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            (base / 'Documents').mkdir()
            output = base / 'shots'
            calls = []
            def simctl(*args, **kwargs):
                calls.append(args)
                if args[0] == 'get_app_container':
                    return str(base)
                if args[0] == 'launch':
                    target = float(args[args.index('-arena.snapshotTime') + 1])
                    evidence = {'simulationTime': target, 'rangerAsset': 'Ranger_FaceSample.glb',
                                'qualitySample': True,
                                'map': 'canyon' if wrong_map or scene == 'canyon' else 'twin_gates_sample_v1'}
                    (base / 'Documents/arena-capture-ready.json').write_text(json.dumps(evidence))
                return ''
            with patch.object(capture.sys, 'argv', ['capture', 'device', str(output), scene]), \
                 patch.object(capture, 'simctl', side_effect=simctl), patch.object(capture.time, 'sleep'):
                if wrong_map:
                    with self.assertRaises(AssertionError):
                        capture.main()
                else:
                    capture.main()
                    records = list(output.glob('*.json'))
                    self.assertEqual(len(records), 2)
                    self.assertTrue(all(json.loads(p.read_text())['qualitySample'] for p in records))
            screenshots = [call for call in calls if call[:3] == ('io', 'device', 'screenshot')]
            self.assertEqual(len(screenshots), 0 if wrong_map else 2)
            screen = 'arenaHarborBenchmark' if scene == 'harbor' else 'arenaSampleBenchmark'
            self.assertTrue(all(screen in call for call in calls if call[0] == 'launch'))

    def test_each_scene_exports_two_identity_checked_frames(self):
        for scene in ['canyon', 'harbor']:
            with self.subTest(scene=scene):
                self.run_capture(scene)

    def test_menu_capture_waits_for_sample_model_and_records_both_pages(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            (base / 'Documents').mkdir()
            output = base / 'shots'
            output.mkdir()
            calls = []
            def simctl(*args, **kwargs):
                calls.append(args)
                if args[0] == 'launch':
                    page = 1 if 'arenaSampleMapReview' in args else 0
                    (base / 'Documents/arena-sample-menu-ready.json').write_text(json.dumps(
                        {'scene': 'sampleReview', 'page': page, 'width': 720, 'height': 300, 'map': 'twin_gates_sample_v1'}))
                    (base / 'Documents/arena-capture-ready.json').write_text(json.dumps(
                        {'asset': 'Ranger_FaceSample.glb', 'qualitySample': True}))
                return ''
            def finish_layout(delay):
                if delay == 2:
                    marker = base / 'Documents/arena-capture-ready.json'
                    model = json.loads(marker.read_text())
                    model['viewHeight'] = 173
                    marker.write_text(json.dumps(model))
            with patch.object(capture, 'simctl', side_effect=simctl), patch.object(capture.time, 'sleep', side_effect=finish_layout):
                capture.capture_menus('device', output, base)
            hero = json.loads((output / 'sample-hero.json').read_text())
            self.assertEqual(hero['model']['asset'], 'Ranger_FaceSample.glb')
            self.assertEqual(hero['model']['viewHeight'], 173, 'Record the model after final layout, not its first ready size')
            self.assertEqual(json.loads((output / 'sample-map.json').read_text())['page'], 1)
            self.assertEqual(len([x for x in calls if x[0] == 'io']), 2)

    def test_menu_rejects_original_model_before_screenshot(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            (base / 'Documents').mkdir()
            output = base / 'shots'
            output.mkdir()
            calls = []
            def simctl(*args, **kwargs):
                calls.append(args)
                if args[0] == 'launch':
                    (base / 'Documents/arena-sample-menu-ready.json').write_text(json.dumps(
                        {'scene': 'sampleReview', 'page': 0, 'width': 720, 'height': 300, 'map': 'twin_gates_sample_v1'}))
                    (base / 'Documents/arena-capture-ready.json').write_text(json.dumps(
                        {'asset': 'Ranger_Original.glb', 'qualitySample': False}))
                return ''
            with patch.object(capture, 'simctl', side_effect=simctl), \
                 patch.object(capture.time, 'sleep'), patch.object(capture.time, 'monotonic', side_effect=[0, 1, 121]):
                with self.assertRaises(SystemExit):
                    capture.capture_menus('device', output, base)
            shots = [x for x in calls if x[0] == 'io']
            self.assertEqual(len(shots), 1)
            self.assertTrue(shots[0][-1].endswith('failed-page-0.png'))
            self.assertFalse((output / 'sample-hero.json').exists())

    def test_menu_rejects_wrong_map_or_zero_height(self):
        for fields in [{'map': 'canyon'}, {'height': 0}]:
            with self.subTest(fields=fields), tempfile.TemporaryDirectory() as directory:
                base = pathlib.Path(directory)
                (base / 'Documents').mkdir()
                output = base / 'shots'
                output.mkdir()
                def simctl(*args, **kwargs):
                    if args[0] == 'launch':
                        evidence = {'scene': 'sampleReview', 'page': 0, 'width': 720,
                                    'height': 300, 'map': 'twin_gates_sample_v1', **fields}
                        (base / 'Documents/arena-sample-menu-ready.json').write_text(json.dumps(evidence))
                        (base / 'Documents/arena-capture-ready.json').write_text(json.dumps(
                            {'asset': 'Ranger_FaceSample.glb', 'qualitySample': True}))
                    return ''
                with patch.object(capture, 'simctl', side_effect=simctl), \
                     patch.object(capture.time, 'sleep'), patch.object(capture.time, 'monotonic', side_effect=[0, 1, 121]):
                    with self.assertRaises(SystemExit):
                        capture.capture_menus('device', output, base)
                self.assertFalse((output / 'sample-hero.json').exists())
                self.assertTrue((output / 'failed-page-0.json').exists())

    def test_stop_timeout_restarts_only_the_requested_device(self):
        with patch.object(capture, 'simctl', side_effect=[capture.subprocess.TimeoutExpired('terminate', 20), '', '', '']) as command:
            capture.stop_app('device')
        self.assertEqual([c.args for c in command.call_args_list], [
            ('terminate', 'device', capture.APP_ID), ('shutdown', 'device'),
            ('boot', 'device'), ('bootstatus', 'device', '-b')])
        self.assertEqual([c.kwargs['timeout'] for c in command.call_args_list], [20, 30, 90, 120])

    def test_failed_recovery_and_launch_timeouts_remain_failures(self):
        with patch.object(capture, 'simctl', side_effect=[capture.subprocess.TimeoutExpired('terminate', 20), capture.subprocess.TimeoutExpired('shutdown', 30)]):
            with self.assertRaises(capture.subprocess.TimeoutExpired):
                capture.stop_app('device')
        with patch.object(capture.subprocess, 'run', side_effect=capture.subprocess.TimeoutExpired('launch', 150)):
            with self.assertRaises(capture.subprocess.TimeoutExpired):
                capture.simctl('launch', 'device', capture.APP_ID)

    def test_old_map_is_rejected_before_harbor_screenshot(self):
        self.run_capture('harbor', wrong_map=True)

if __name__ == '__main__':
    unittest.main()
