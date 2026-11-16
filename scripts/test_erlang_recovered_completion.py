"""Independent private-input checks for recovered D15 portrait and original sound.

Set FIGHTER_ERLANG_RECOVERY_ROOT to the previous session and
FIGHTER_ERLANG_WORK_ROOT to the new private work-products directory.
"""
import copy
import io
import json
import os
from pathlib import Path
import unittest
import wave
import gzip

import numpy as np

from bind_erlang_personal_neck import RECOVERED_PROFILE_SHA, validate_input
from build_erlang_source_assets import sha
from recover_erlang_source_audio import (
    COMMON_RECEIPT_SHA, FLOOR_RECEIPT_SHA, RECOVERED_AUDIO_SHA, NECK_PROFILE_SHA,
    NECK_CHARACTER_SHA, bind_events, source_events, verify_historical_markers,
)
from sun_triad_assets import accessor_read, glb_read
from bind_erlang_recovered_effects import INPUTS as FX_INPUTS, join as join_fx


class RecoveredErlangCompletionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        old = os.getenv('FIGHTER_ERLANG_RECOVERY_ROOT')
        work = os.getenv('FIGHTER_ERLANG_WORK_ROOT')
        if not old or not work:
            raise unittest.SkipTest('Real authenticated recovery inputs are required')
        cls.old = Path(old); cls.work = Path(work)
        cls.prior_path = cls.old/'work-products/erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json'
        cls.prior = json.loads(cls.prior_path.read_bytes())
        cls.next_path = cls.work/'erlang-neck-v1/SF3_Erlang_Profile.json'
        cls.next = json.loads(cls.next_path.read_bytes())
        cls.g0, cls.b0 = glb_read(cls.prior_path.parent/(cls.prior['resourceName']+'.glb'))
        cls.g1, cls.b1 = glb_read(cls.next_path.parent/(cls.next['resourceName']+'.glb'))
        cls.audio_path = cls.work/'erlang-audio-recovered-v1/SF3_Erlang_Recovered_Source_Audio.json'
        cls.audio = json.loads(cls.audio_path.read_bytes())
        cls.common = json.loads(Path(__file__).with_name('erlang_source_audio_receipt_20261115.json').read_bytes())
        cls.floor = json.loads(Path(__file__).with_name('erlang_palace_floor_audio_receipt_20261115.json').read_bytes())

    def test_prior_body_binary_and_all_62_motion_records_preserved(self):
        self.assertEqual(sha(self.prior_path.read_bytes()), RECOVERED_PROFILE_SHA)
        self.assertEqual(sha(self.next_path.read_bytes()), NECK_PROFILE_SHA)
        self.assertEqual(self.next['sha256'], NECK_CHARACTER_SHA)
        count = self.g0['buffers'][0]['byteLength']
        self.assertEqual(self.b1[:count], self.b0[:count])
        self.assertEqual(self.g1['animations'], self.g0['animations'])
        self.assertEqual(len(self.g1['animations']), 62)
        for field in ('clips', 'roles', 'ordinaryThrows', 'combatRules', 'erlangRules', 'summonTracks'):
            self.assertEqual(self.next[field], self.prior[field])
        self.assertEqual(self.g1['skins'], self.g0['skins'])

    def test_original_portrait_and_all_embedded_textures_preserved(self):
        p0 = next(n for n in self.g0['nodes'] if n.get('name') == 'WuYong_Personal_Head')
        p1 = next(n for n in self.g1['nodes'] if n.get('name') == 'WuYong_Personal_Head')
        self.assertEqual(p1, p0)
        self.assertEqual(self.g1['meshes'][p1['mesh']], self.g0['meshes'][p0['mesh']])
        primitive = self.g0['meshes'][p0['mesh']]['primitives'][0]
        self.assertEqual(self.g0['accessors'][primitive['attributes']['POSITION']]['count'], 59878)
        for field in ('images', 'textures', 'samplers'):
            self.assertEqual(self.g1[field], self.g0[field])
        for index in [*primitive['attributes'].values(), primitive['indices']]:
            np.testing.assert_array_equal(accessor_read(self.g0, self.b0, index), accessor_read(self.g1, self.b1, index))

    def test_neck_has_one_real_skin_and_two_normalized_source_joints(self):
        node = next(n for n in self.g1['nodes'] if n.get('name') == 'Personal_Neck_Bridge')
        self.assertEqual(node['skin'], 0)
        mesh = self.g1['meshes'][node['mesh']]
        self.assertEqual(mesh['extras'], dict(generatedPersonalFitting=True, originalSF3Geometry=False))
        primitive = mesh['primitives'][0]
        points = accessor_read(self.g1, self.b1, primitive['attributes']['POSITION'])
        joints = accessor_read(self.g1, self.b1, primitive['attributes']['JOINTS_0'])
        weights = accessor_read(self.g1, self.b1, primitive['attributes']['WEIGHTS_0'])
        self.assertEqual(len(points), 226)
        self.assertEqual(len(accessor_read(self.g1, self.b1, primitive['indices'])), 448*3)
        self.assertTrue(np.isfinite(points).all() and np.isfinite(weights).all() and (weights >= 0).all())
        np.testing.assert_allclose(weights.sum(axis=1), 1, atol=1e-7)
        names = {self.g1['nodes'][self.g1['skins'][0]['joints'][slot]]['name'] for slot in joints[weights > 0].tolist()}
        self.assertEqual(names, {'head', 'neck'})
        self.assertTrue(self.next['recoveryBoundary']['personalNeckBridgeIncluded'])
        self.assertFalse(self.next['recoveryBoundary']['productionActivation'])

    def test_recovered_neck_requires_exact_candidate_and_explicit_entry(self):
        with self.assertRaises(ValueError):
            validate_input(self.prior, RECOVERED_PROFILE_SHA, False)
        with self.assertRaises(ValueError):
            validate_input(self.prior, '0'*64, True)
        tampered = copy.deepcopy(self.prior); tampered['recoveryBoundary']['personalNeckBridgeIncluded'] = True
        with self.assertRaises(ValueError):
            validate_input(tampered, RECOVERED_PROFILE_SHA, True)

    def test_all_82_original_pcm_and_sample_hashes_match_historical_oracles(self):
        self.assertEqual(sha(self.audio_path.read_bytes()), RECOVERED_AUDIO_SHA)
        expected = {f['name']: f for f in self.common['files'] + self.floor['inputs']}
        self.assertEqual(len(expected), 82)
        self.assertEqual({f['name'] for f in self.audio['files']}, set(expected))
        total = 0
        for f in self.audio['files']:
            raw = (self.audio_path.parent/f['name']).read_bytes(); total += len(raw)
            self.assertEqual(sha(raw), expected[f['name']]['sha256'])
            self.assertEqual(len(raw), expected[f['name']]['bytes'])
            with wave.open(io.BytesIO(raw)) as wav:
                samples = wav.readframes(wav.getnframes()+1)
                self.assertEqual(wav.getframerate(), expected[f['name']]['sampleRate'])
                self.assertEqual(wav.getnchannels(), expected[f['name']]['channels'])
                self.assertEqual(wav.getnframes(), expected[f['name']]['sampleFrames'])
                self.assertEqual(sha(samples), expected[f['name']]['pcmSHA256'])
        self.assertEqual(total, 7074406)

    def test_source_events_rederive_exact_historical_clocks_and_weighted_choices(self):
        named = json.loads((self.old/'recovery/unpacked/RiftDuel_Recovery_Checkpoint_20261115/recovered-erlang-named-animations-v1/erlang-imperial-animation-named-recovered-v1.json').read_bytes())
        expected = source_events(self.prior, named)
        actual = copy.deepcopy(self.audio['events'])
        for event in actual:
            for choice in event['choices']:
                choice.pop('file')
        self.assertEqual(actual, expected)
        markers = bind_events(self.next, self.audio['events'])
        verify_historical_markers(markers, self.common, self.floor)
        step = next(m for m in markers if m['role'] == 'walkForward' and m['route'] == 'Floor.Stone')
        self.assertEqual((step['sourceFrame'], step['sourceTick'], step['duration']), (10, 20, 40))
        self.assertEqual(step['files'][1], step['files'][2])
        self.assertNotEqual(step['files'][0], step['files'][1])

    def test_changed_sound_origin_and_invented_model_clock_rejected(self):
        events = copy.deepcopy(self.audio['events'])
        events[0]['sourceFrame'] -= 1
        with self.assertRaises(ValueError):
            bind_events(self.next, events)
        tampered = copy.deepcopy(self.next)
        track = next(t for t in tampered['summonTracks'] if t['role'] == 'erlangSummon_swordBirth1')
        track['sourceSHA256'] = '0'*64
        markers = bind_events(tampered, self.audio['events'])
        with self.assertRaises(ValueError):
            verify_historical_markers(markers, self.common, self.floor)

    def test_runtime_manifest_pins_current_profile_and_keeps_unplayed_explosion(self):
        path = self.work/'erlang-audio-runtime-v5/SF3_Erlang_Audio.json'
        runtime = json.loads(path.read_bytes())
        self.assertEqual(runtime['schemaVersion'], 5)
        self.assertEqual(runtime['sourceAudioManifestSHA256'], RECOVERED_AUDIO_SHA)
        self.assertEqual(runtime['profileSHA256'], NECK_PROFILE_SHA)
        self.assertEqual(runtime['characterSHA256'], NECK_CHARACTER_SHA)
        self.assertEqual(len(runtime['markers']), 119)
        self.assertEqual(runtime['pendingModels'], [])
        self.assertEqual(runtime['deferredTriggers'], self.common['unplayedInputs'])
        self.assertFalse(runtime['triggerSounds'][0]['loop'])
        self.assertFalse(runtime['runtimePlaybackObserved'])
        self.assertFalse(runtime['historicalPrivateManifestBytesRestored'])

    def test_effect_bindings_preserve_original_samples_resources_and_unbound_scope(self):
        for kind, pin in FX_INPUTS.items():
            original = self.old/'recovery/unpacked/RiftDuel_Recovery_Checkpoint_20261115/continued-20261116'/pin['directory']
            source = json.loads(gzip.decompress((original/pin['file']).read_bytes()))
            directory = self.work/'erlang-fx-runtime-v1'/kind
            output = json.loads(gzip.decompress((directory/(pin['output']+'.gz')).read_bytes()))
            self.assertEqual(output['characterSHA256'], self.next['sha256'])
            for field in ('effects', 'files', 'materials'):
                self.assertEqual(output[field], source[field])
            for f in source['files']:
                self.assertEqual((directory/f['name']).read_bytes(), (original/f['name']).read_bytes())
                self.assertEqual(sha((directory/f['name']).read_bytes()), f['sha256'])
            if kind == 'sword':
                self.assertEqual(output['erlangSwordScope'], source['sourceScope'])
                self.assertFalse(output['erlangSwordScope']['completePrefab'])
                self.assertEqual(len(output['erlangSwordScope']['unboundEmitters']), 3)
                self.assertIsNone(output['erlangSwordModels']['erlangSummon_swordRotate']['track'])

    def test_effect_binding_refuses_different_collision_clock_or_erased_missing_emitters(self):
        pin = FX_INPUTS['sword']
        original = self.old/'recovery/unpacked/RiftDuel_Recovery_Checkpoint_20261115/continued-20261116'/pin['directory']
        source = json.loads(gzip.decompress((original/pin['file']).read_bytes()))
        receipt = json.loads((original/pin['receipt']).read_bytes())
        changed = copy.deepcopy(self.next)
        next(t for t in changed['summonTracks'] if t['role'] == 'erlangSummon_sword')['root'].pop()
        with self.assertRaises(ValueError):
            join_fx('sword', source, receipt, changed)
        source['sourceScope']['completePrefab'] = True
        with self.assertRaises(ValueError):
            join_fx('sword', source, receipt, self.next)


if __name__ == '__main__':
    unittest.main()
