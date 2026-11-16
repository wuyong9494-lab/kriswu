"""Targeted rejection/clock checks on one actually recovered private body.

Set ERLANG_RECOVERED_BODY_INPUTS to recovery-20261115 and
ERLANG_RECOVERED_BODY_CANDIDATE to the new output. Without both, these are
explicitly skipped; synthetic or missing assets cannot count as source passes.
The conversion and its complete GLB/FK readback are run separately, once.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

import numpy as np

from prepare_erlang_animated_body import (
    BOUNDARY, MIRROR_CLIP, MIRROR_ROLE, PROFILE, checked, load_configs,
    load_named, verify_clip,
)
from sun_triad_assets import glb_read


class RecoveredBodyChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        inputs, output = os.environ.get('ERLANG_RECOVERED_BODY_INPUTS'), os.environ.get('ERLANG_RECOVERED_BODY_CANDIDATE')
        if not inputs or not output:
            raise unittest.SkipTest('Actual private recovered source/candidate paths were not supplied')
        cls.inputs, cls.output = Path(inputs), Path(output)
        cls.profile = json.loads((cls.output/PROFILE).read_bytes())
        cls.receipt = json.loads((cls.output/'animated-body-receipt-private.json').read_bytes())
        model = cls.output/(cls.profile['resourceName']+'.glb')
        cls.assert_identity(model, cls.profile)
        cls.g, cls.b = glb_read(model)
        cls.names = {row['name']: row['targetNode'] for row in cls.profile['sourceBoneBindings']}
        cls.configs, _, _ = load_configs(SimpleNamespace(
            source_configs=cls.inputs/'recovered-model-configs',
            shared_bones=cls.inputs/'recovered-shared-bones'))

    @staticmethod
    def assert_identity(path, identity):
        raw = checked(path, identity['sha256'], 32_000_000)
        if len(raw) != identity['bytes']:
            raise AssertionError('Actual candidate byte count differs')

    def clip(self, role):
        name = self.profile['roles'][role]
        return next(row for row in self.profile['clips'] if row['name'] == name)

    def test_named_source_mutation_rejected_before_object_loading(self):
        path = self.inputs/'recovered-erlang-named-animations-v1/erlang-imperial-animation-named-recovered-v1.json'
        raw = bytearray(path.read_bytes())
        raw[-2] ^= 1
        with tempfile.TemporaryDirectory() as folder:
            changed = Path(folder)/path.name
            changed.write_bytes(raw)
            with self.assertRaisesRegex(ValueError, 'Pinned input differs'):
                load_named(changed)

    def test_written_head_track_tamper_rejected_from_actual_glb(self):
        clip = copy.deepcopy(self.clip('idle'))
        clip['tracks']['head'][0][0] += .01
        with self.assertRaisesRegex(ValueError, 'GLB/source FK mismatch'):
            verify_clip(self.g, self.b, clip, self.names, self.configs)

    def test_written_capsule_track_tamper_rejected_from_actual_glb(self):
        clip = copy.deepcopy(self.clip('idle'))
        clip['tracks']['hurtCapsules'][0]['tip'][0][1] += .01
        with self.assertRaisesRegex(ValueError, 'GLB/source FK mismatch'):
            verify_clip(self.g, self.b, clip, self.names, self.configs)

    def test_exact_one_key_transform_out_and_stride_one_earth(self):
        clip = self.clip('erlangTransformOut')
        self.assertEqual((clip['sourceUncroppedFrames'], clip['frames'], clip['playbackTicks'], clip['sourceEndEventTick']),
                         (62, 1, 0, 0))
        self.assertEqual(clip['sourceConfiguration']['sourceRecordIndex'], 133)
        self.assertTrue(all(len(clip['tracks'][field]) == 1
                            for field in ('head', 'pelvis', 'root', 'toeL', 'toeR', 'centerOfMass')))
        earth = self.clip('erlangEarthshaker')
        self.assertEqual(earth['sourceConfiguration']['configuration']['MidFrames'], 0)
        self.assertEqual((earth['frames'], earth['playbackTicks'], len(earth['tracks']['head'])), (111, 110, 221))
        self.assertEqual(earth['sourceConfiguration']['sourceRecordIndex'], 102)

    def test_mirror_and_incomplete_profile_are_explicit(self):
        mirrored, normal = self.clip(MIRROR_ROLE), self.clip('imperialHeavyPassive')
        self.assertEqual(mirrored['name'], MIRROR_CLIP)
        self.assertEqual(mirrored['sha256'], normal['sha256'])
        self.assertEqual(mirrored['sourceBytesBase64'], normal['sourceBytesBase64'])
        self.assertEqual((mirrored['frames'], mirrored['playbackTicks'], mirrored['sourceEndEventTick']), (71, 140, 132))
        self.assertGreater(float(np.max(abs(np.asarray(mirrored['tracks']['toeL'])-np.asarray(normal['tracks']['toeL'])))), .001)
        self.assertEqual(len(self.profile['roles']), 50)
        self.assertEqual(self.profile['recoveryBoundary'], BOUNDARY)
        self.assertFalse(self.profile['recoveryBoundary']['fullMatchProfile'])
        self.assertNotIn('ordinaryThrows', self.profile)
        self.assertNotIn('erlangRules', self.profile)


if __name__ == '__main__':
    unittest.main()
