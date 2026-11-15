#!/usr/bin/env python3
"""New focused checks for actual D15 hound FX and animated world velocity."""
import argparse
import copy
import gzip
import hashlib
import json
import math
import unittest
import warnings
from pathlib import Path

import numpy as np

from prepare_erlang_hound_effects import BUNDLE, HOUND_GLB_SHA, HoundAttachmentPose
from bind_erlang_hound_effects import bind
from sun_triad_particles import Particle, sample_particle


def rotation_z(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, -s, 0.], [s, c, 0.], [0., 0., 1.]])


class HoundEffectChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
        raw = cls.bundle.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == BUNDLE[1]
        environment = UnityPy.load(raw)
        cls.source = next(o for o in environment.objects if o.path_id == -6343630985371488807).read_typetree()
        source = cls.source
        cls.renderer = next(o for o in environment.objects if o.type.name == 'ParticleSystemRenderer'
            and o.read_typetree()['m_GameObject']['m_PathID'] == source['m_GameObject']['m_PathID']).read_typetree()

    def isolated_wind(self, rotation):
        # Keep the actual source y=50cm/s and simulationSpeed=.5. Disable
        # independent shape/startSpeed/drag only for an exact direction oracle.
        source = copy.deepcopy(self.source)
        source['ShapeModule']['enabled'] = False
        source['InitialModule']['startSpeed'] = copy.deepcopy(source['VelocityModule']['x'])
        source['ClampVelocityModule']['enabled'] = False
        source['RotationModule']['enabled'] = False
        particle = Particle(source, 'd15-world-wind-oracle', 0, 0)
        transform = np.diag([4., 1., 1., 1.])
        data, _ = sample_particle(source, self.renderer, transform, [4., 1., 1.], particle,
                                  parent_rotation_at=rotation, sample_until=.4)
        return np.asarray(data['frames'][-1][1:4]) * [1., 1., -1.]

    def test_world_up_stays_up_through_rotated_nonuniform_emitter(self):
        rotation = rotation_z(math.pi / 2)
        legacy = rotation @ self.isolated_wind(None)
        corrected = rotation @ self.isolated_wind(lambda _: rotation)
        self.assertGreater(np.linalg.norm(legacy - [0., 10., 0.]), 10)
        self.assertLess(np.max(abs(corrected - [0., 10., 0.])), 1e-6)
        print('Measured static-prefab projection:', legacy.tolist(),
              '; animated source projection:', corrected.tolist())

    def test_dynamic_local_attachment_uses_each_actual_projection(self):
        omega, duration, speed = 1.2, .4, 25.
        actual = rotation_z(omega * duration) @ self.isolated_wind(lambda t: rotation_z(omega * t))
        integral = np.array([speed * (1 - math.cos(omega * duration)) / omega,
                             speed * math.sin(omega * duration) / omega, 0.])
        expected = rotation_z(omega * duration) @ integral
        self.assertLess(np.max(abs(actual - expected)), .001)
        original = HoundAttachmentPose(self.hound)
        for tick in (0., 30., 70., 110.):
            rotation = original.source_rotation(tick)
            world = rotation @ self.isolated_wind(lambda _: rotation)
            self.assertLess(np.max(abs(world - [0., 10., 0.])), 1e-6)

    def test_actual_export_identity_files_and_bounded_model_clock(self):
        receipt = json.loads((self.candidate / 'd15-hound-fx-receipt-private.json').read_bytes())
        raw = (self.candidate / receipt['effectsFile']['name']).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), receipt['effectsFile']['sha256'])
        self.assertEqual(len(raw), receipt['effectsFile']['bytes'])
        document = json.loads(gzip.decompress(raw))
        self.assertEqual(receipt['houndPoseGLBSHA256'], HOUND_GLB_SHA)
        self.assertEqual(receipt['observableModelEndTick'], 110)
        self.assertEqual(len(receipt['sourceEmitters']), 9)
        self.assertEqual(len(document['effects']), 2)
        self.assertEqual(len(document['materials']), 6)
        self.assertEqual(document['bindings'], [])
        self.assertEqual(document['markers'], [])
        for record in document['files']:
            content = (self.candidate / record['name']).read_bytes()
            self.assertEqual(len(content), record['bytes'])
            self.assertEqual(hashlib.sha256(content).hexdigest(), record['sha256'])
        for t in document['effects']['D15_dog_smoke(spine_root_joint)']['tracks']:
            self.assertLess(t['delay'], 110 / 60)
            self.assertLessEqual(t['delay'] + t['duration'], 110 / 60 + 0.000001)
            self.assertTrue(t.get('loopPeriod') is None or t['loopPeriod'] > 110 / 60)

    def test_final_profile_binding_changes_metadata_only(self):
        receipt = json.loads((self.candidate / 'd15-hound-fx-receipt-private.json').read_bytes())
        document = json.loads((self.candidate / 'SF3_D15_Effects.json').read_bytes())
        profile = dict(id='wuyong_erlang', sha256='a' * 64, summonTracks=[receipt['houndTrack']])
        actual = bind(document, receipt, profile)
        self.assertEqual(actual['characterSHA256'], profile['sha256'])
        actual['characterSHA256'] = document['characterSHA256']
        self.assertEqual(actual, document)
        profile['summonTracks'] = copy.deepcopy(profile['summonTracks'])
        profile['summonTracks'][0]['root'][10][0] += .01
        with self.assertRaises(ValueError): bind(document, receipt, profile)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('bundle', 'hound', 'candidate'):
        p.add_argument('--' + n, required=True, type=Path)
    p.add_argument('--method', help='Run one newly affected method without repeating the others.')
    a = p.parse_args()
    HoundEffectChecks.bundle, HoundEffectChecks.hound, HoundEffectChecks.candidate = a.bundle, a.hound, a.candidate
    unittest.main(argv=['test_erlang_hound_effects.py'] + ([f'HoundEffectChecks.{a.method}'] if a.method else []), verbosity=2)
