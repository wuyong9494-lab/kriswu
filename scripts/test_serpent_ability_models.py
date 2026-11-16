#!/usr/bin/env python3
"""Original D13 model clocks, rig identity, capsules and animated-skin checks."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

import numpy as np

from prepare_serpent_ability_models import (DEFINITIONS, DOCUMENT_FILE, GLB_FILE, ORACLE_FILE,
    MODELS, PARTS, collision_tracks, interval_ticks, local_samples, playback_window,
    selected_bones, sha, source_poses, verify_document, verify_vine_glb,
    world_capsules_oracle)
from sun_triad_assets import accessor_read, glb_read


class SerpentAbilityModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = os.environ.get('SERPENT_ABILITY_MODELS_DIR')
        cls.directory = Path(directory) if directory else None
        if cls.directory:
            cls.document = json.loads((cls.directory / DOCUMENT_FILE).read_bytes())
            cls.motions = {d[4]: (cls.directory / (d[4] + '.original-private.bytes')).read_bytes()
                           for d in DEFINITIONS}

    def actual_source(self):
        if self.directory is None:
            self.skipTest('Actual private D13 ability-model output was not supplied')
        return self.document

    def config(self, **changes):
        value = dict(MidFrames=None, Looped=None, Mirrored=None,
                     FirstFrame=None, EndFrame=None, SelfEndFrame=0)
        value.update(changes)
        return value

    def test_vine_alignment_uses_its_actual_anchor_and_motion_once(self):
        rows = [dict(name='model_root', parent=None, translation=[0, 0, 0],
                     rotation=[0, 0, 0, 1], scale=[1, 1, 1]),
                dict(name='tentacle_1', parent='model_root', translation=[0, 0, 0],
                     rotation=[0, 0, 0, 1], scale=[1, 1, 1])]
        vertex = dict(bone='tentacle_1', localPositionCentimeters=[0, 0, 0])
        bones = dict(bones={400: 'tentacle_1'}, capsules=[dict(
            id='actual_tip', base=vertex, tip=vertex, radiusCentimeters=7)])
        motion = dict(bone_ids=[400], positions=np.array([[[100, 200, 0]], [[300, 400, 0]]]),
                      rotations=np.array([[[0, 0, 0, 1]], [[0, 0, 0, 1]]]))
        window = playback_window(self.config(), 2)
        worlds, roots, names, rest = source_poses(rows, bones, motion, window, ['X'], 'tentacle_1')
        self.assertEqual(roots[:, 0].tolist(), [-1., -2., -3.])
        edge = collision_tracks(worlds, roots, names, bones)[0]
        self.assertEqual(edge['base'], [[0., 2., 0.], [0., 3., 0.], [0., 4., 0.]])
        self.assertEqual(edge['radiusMillimeters'], 70)
        self.assertEqual(rest, [])
        with self.assertRaisesRegex(ValueError, 'alignment bone'):
            source_poses(rows, bones, motion, window, ['X'], 'magic_joint_root')
        broken = dict(motion, bone_ids=[401])
        with self.assertRaisesRegex(ValueError, 'Unknown or duplicate'):
            local_samples(rows, bones, broken, window, 'tentacle_1')

    def test_bloom_crop_and_vine_inclusive_attack_interval_remain_distinct(self):
        bloom = playback_window(self.config(EndFrame=6), 31)
        self.assertEqual((bloom['originalFrames'], bloom['frames'], bloom['lastSampleTick'],
                          bloom['animationEndTick']), (31, 6, 10, 10))
        vine = playback_window(self.config(), 88)
        self.assertEqual(interval_ticks(dict(Start=5, End=75), vine),
                         dict(startTick=8, endTickInclusive=149, intervalEndEventTick=150))
        self.assertEqual(vine['animationEndTick'], 174)
        for changes in ({'EndFrame': 32}, {'SelfEndFrame': -1}, {'MidFrames': 2}, {'Mirrored': True}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                playback_window(self.config(**changes), 31)

    def test_all_real_source_matrices_capsules_and_original_arrays_read_back(self):
        document = self.actual_source()
        result = verify_document(document, self.motions)
        self.assertEqual((result['models'], result['sourceTicks'], result['matrixSamples'],
                          result['capsuleEndpoints']), (5, 433, 7893, 2298))
        self.assertLess(result['maximumMatrixErrorMeters'], 1e-8)
        self.assertLess(result['maximumEndpointErrorMeters'], 3e-8)
        for receipt in document['receipts']:
            self.assertEqual(receipt['unboundMotionIDs'], [])
            self.assertEqual(receipt['declaredButUnanimatedBones'], [])
            self.assertFalse(receipt['rules']['conditionsEvaluated'])
            self.assertTrue(receipt['rules']['creationCandidates'])
            self.assertTrue(receipt['rules']['sourceTreePaths'])

    def test_invisible_rigs_and_source_mesh_identity_are_not_replaced(self):
        document = self.actual_source()
        for d, receipt in zip(DEFINITIONS, document['receipts']):
            kind = d[2]
            source = receipt['sourceModel']
            self.assertEqual(source['sourceBundleSHA256'], MODELS[kind]['sha256'])
            self.assertEqual(source['sourceMeshes'], ['m__tentacle', 'm__tentacle_crystal'] if kind == 'root' else [])
        self.assertFalse(document['runtimeBound'])
        self.assertFalse(document['boundaries']['customShaderParity'])
        self.assertFalse(document['boundaries']['separateParticleEffectsBound'])
        self.assertFalse(document['boundaries']['fullMatchProfile'])
        radii = [[edge['radiusMillimeters'] for edge in t['collisionEdges']] for t in document['summonTracks']]
        self.assertEqual(radii, [[1500], [400], [750], [70, 70, 70], [70, 70, 70]])
        for suffix in ('vine1', 'vine2'):
            source = next(r['sourceModel'] for r in document['receipts'] if r['role'] == 'serpentSummon_' + suffix)
            bones = (self.directory / 'original-sources/root-bones-private.xml').read_bytes()
            selected, omitted = selected_bones(bones, PARTS[suffix])
            self.assertEqual([c['id'] for c in selected['capsules']], PARTS[suffix])
            self.assertEqual(len(omitted), 17)
            self.assertEqual(len(source['sourceDeclarations']['bones']), 21)

    def test_real_candidate_rejects_clock_geometry_source_and_activation_mutations(self):
        document = self.actual_source()
        mutations = (
            ('capsule', lambda d: d['summonTracks'][0]['collisionEdges'][0]['base'][0].__setitem__(0, 1.)),
            ('radius', lambda d: d['summonTracks'][0]['collisionEdges'][0].__setitem__('radiusMillimeters', 100)),
            ('terminal', lambda d: d['summonTracks'][0].__setitem__('sourceEndEventTick', 40)),
            ('anchor', lambda d: d['models'][0]['origin'].__setitem__('alignmentBone', 'tentacle_1')),
            ('model', lambda d: d['receipts'][0]['sourceModel'].__setitem__('sourceBundleSHA256', '0' * 64)),
            ('activation', lambda d: d.__setitem__('runtimeBound', True)),
        )
        for name, change in mutations:
            with self.subTest(name=name):
                changed = copy.deepcopy(document)
                change(changed)
                with self.assertRaises(ValueError):
                    verify_document(changed, self.motions)
        changed_motions = dict(self.motions)
        changed_motions[DEFINITIONS[0][4]] = b'not the original compressed motion'
        with self.assertRaisesRegex(ValueError, 'motion identity'):
            verify_document(document, changed_motions)

    def test_real_vine_glb_preserves_both_animated_skins(self):
        document = self.actual_source()
        path = self.directory / GLB_FILE
        result = verify_vine_glb(path, document, self.motions)
        self.assertEqual((result['sourceMeshes'], result['sourceVertices'], result['sourceTriangles']), (2, 1086, 888))
        self.assertEqual((result['sourceTicks'], result['boneMatrixSamples'], result['skinnedVertexComparisons']),
                         (358, 7518, 388788))
        self.assertLess(result['maximumSkinErrorMeters'], 2e-5)
        g, binary = glb_read(path)
        for animation, samples in zip(g['animations'], (175, 183)):
            self.assertEqual(len(animation['channels']), 42)
            times = accessor_read(g, binary, animation['samplers'][0]['input'])
            self.assertEqual(len(times), samples)
        with tempfile.TemporaryDirectory() as tmp:
            damaged = Path(tmp) / GLB_FILE
            damaged.write_bytes(path.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, 'GLB identity'):
                verify_vine_glb(damaged, document, self.motions)

    def test_independent_world_oracle_covers_both_facings_and_adds_root_once(self):
        document = self.actual_source()
        oracle = json.loads((self.directory / ORACLE_FILE).read_bytes())
        self.assertEqual(oracle, world_capsules_oracle(document, self.motions))
        self.assertEqual(oracle['sourceModelDocumentSHA256'], sha((self.directory / DOCUMENT_FILE).read_bytes()))
        self.assertEqual(len(oracle['cases']), 38)
        self.assertEqual(sum(len(case['capsules']) for case in oracle['cases']), 78)
        tracks = {t['role']: t for t in document['summonTracks']}
        maximum = 0.
        for case in oracle['cases']:
            track = tracks[case['role']]
            tick = case['tick']
            direction = case['direction']
            birth = np.asarray(case['birthOriginMeters'])
            root_delta = track['root'][tick][0] - track['root'][0][0]
            edges = {e['id']: e for e in track['collisionEdges']}
            for capsule in case['capsules']:
                edge = edges[capsule['id']]
                self.assertAlmostEqual(capsule['radiusMeters'], edge['radiusMillimeters'] / 1000)
                for endpoint in ('base', 'tip'):
                    local = np.asarray(edge[endpoint][tick]) + [root_delta, 0, 0]
                    point = birth + local * [direction, 1, direction]
                    error = float(np.max(np.abs(point - capsule[endpoint])))
                    self.assertLess(error, 2e-8)
                    maximum = max(maximum, error)
            if case['role'] == 'serpentSummon_bloom':
                self.assertEqual(direction, -1)
                self.assertEqual(case['birthOriginMeters'], [5.3, 1.2, 0.])
            if case['role'] in ('serpentSummon_helmet', 'serpentSummon_vine1', 'serpentSummon_vine2'):
                self.assertEqual(case['birthOriginMeters'][1:], [0., 0.])
        self.assertLess(maximum, 2e-8)


if __name__ == '__main__':
    unittest.main()
