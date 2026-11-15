#!/usr/bin/env python3
"""Small checks against the actual prepared original sword objects and poses."""
from __future__ import annotations
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest
import warnings

import numpy as np
from prepare_erlang_sword_effect import EFFECT, SYSTEMS, START_SYSTEMS, source_models
from erlang_sword_materials import MATERIALS


def sha(raw): return hashlib.sha256(raw).hexdigest()


class ActualSwordChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        warnings.filterwarnings('ignore')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        cls.document = json.loads(gzip.decompress((ARGS.candidate / 'SF3_D15_SwordEffects.json.gz').read_bytes()))
        cls.receipt = json.loads((ARGS.candidate / 'd15-sword-effect-receipt-private.json').read_bytes())
        cls.environment = UnityPy.load(str(ARGS.bundle))
        cls.objects = {o.path_id: o for o in cls.environment.objects}
        cls.profile = json.loads(ARGS.profile.read_bytes())

    def test_original_mesh_topology_and_explicit_partial_scope(self):
        from UnityPy.helpers.MeshHelper import MeshHandler
        obj = self.objects[5887294323812191014]
        self.assertEqual(sha(obj.get_raw_data()), self.receipt['sourceMeshSHA256'])
        handler = MeshHandler(obj.read()); handler.process()
        expected = np.asarray(handler.m_Vertices)[:, :3] * [1, 1, -1]
        indices = np.asarray(handler.get_triangles()[0]).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        for track in self.document['effects'][EFFECT]['tracks']:
            np.testing.assert_array_equal(np.asarray(track['geometry']['positions']).reshape(-1, 3), expected)
            np.testing.assert_array_equal(track['geometry']['indices'], indices)
        scope = self.document['erlangSwordScope']
        self.assertEqual((scope['sourceActiveEmitters'], len(scope['boundMeshEmitters']), len(scope['unboundEmitters'])), (20, 6, 14))
        self.assertFalse(scope['completePrefab'])
        self.assertEqual(set(scope['boundMeshEmitters']), set(map(str, SYSTEMS)))
        self.assertTrue(set(scope['boundMeshEmitters']).isdisjoint(scope['unboundEmitters']))
        self.assertEqual({r['sourceParticleSystem'] for r in self.receipt['unboundEmitters']}, set(scope['unboundEmitters']))

    def test_original_emission_no_hole_when_startup_finishes_or_loop_wraps(self):
        tracks = self.document['effects'][EFFECT]['tracks']
        for system in SYSTEMS:
            source = self.objects[system].read_typetree()
            self.assertEqual(source['EmissionModule']['m_BurstCount'], 1)
            self.assertEqual(source['EmissionModule']['m_Bursts'][0]['countCurve']['scalar'], 1)
            group = [t for t in tracks if t['sourceParticleSystem'] == str(system)]
            self.assertEqual(len(group), 1 if system in START_SYSTEMS else 2)
            for t in group:
                self.assertAlmostEqual(t['duration'], source['InitialModule']['startLifetime']['scalar'], places=6)
            if system not in START_SYSTEMS:
                for tick in (0, 35, 36, 59, 60, 61, 119, 120, 121, 3600):
                    alive = [t for t in group if tick / 60 >= t['delay'] and
                             (tick / 60 - t['delay']) % t['loopPeriod'] < t['duration']]
                    self.assertEqual(len(alive), 1, (system, tick))
        self.assertEqual(self.document['effects'][EFFECT]['sourceDurationOverride'], 9999.)

    def test_exact_original_poses_and_single_sample_rotate(self):
        models = source_models(self.profile, ARGS.model_tracks, ARGS.held_tracks)
        self.assertEqual(self.document['erlangSwordModels'], models)
        rotate = models['erlangSummon_swordRotate']
        self.assertEqual((rotate['frames'], rotate['lastTick'], len(rotate['root']), rotate['track']), (1, 0, 1, None))
        birth = np.asarray(models['erlangSummon_swordBirth1']['root'])
        self.assertEqual(birth[0, 12], 0)
        self.assertEqual(birth[0, 14], 0)
        self.assertGreater(np.ptp(birth[:, 13]), .28)  # actual original root bob, not a flattened rigid sword
        for role, model in models.items():
            for flat in model['root']:
                m = np.asarray(flat).reshape(4, 4).T
                np.testing.assert_allclose(m[:3, :3].T @ m[:3, :3], np.eye(3), atol=2e-6)
            if model['track'] is not None:
                self.assertEqual([t for t in self.profile['summonTracks'] if t['role'] == role], [model['track']])

    def test_mutated_collision_identity_cannot_supply_visual_pose(self):
        wrong = copy.deepcopy(self.profile)
        track = next(t for t in wrong['summonTracks'] if t['role'] == 'erlangSummon_swordBirth3')
        track['root'][0][0] += .001
        with self.assertRaisesRegex(ValueError, 'exact original sword track'):
            source_models(wrong, ARGS.model_tracks, ARGS.held_tracks)
        missing = copy.deepcopy(self.profile)
        missing['summonTracks'] = [t for t in missing['summonTracks'] if t['role'] != 'erlangSummon_swordIdle']
        with self.assertRaisesRegex(ValueError, 'exact original sword track'):
            source_models(missing, ARGS.model_tracks, ARGS.held_tracks)

    def test_material_raw_bytes_exact_variants_and_all_runtime_resources(self):
        from UnityPy.helpers import TypeTreeHelper
        from UnityPy.streams import EndianBinaryReader
        template = next(o for o in self.environment.objects if o.type.name == 'Material')
        binding = json.loads((ARGS.materials / 'd15-sword-shader-bindings-private.json').read_bytes())
        self.assertEqual({int(m['sourcePathID']) for m in binding['materials']}, set(MATERIALS))
        for m in binding['materials']:
            raw = (ARGS.materials / (m['sourcePathID'] + '.raw')).read_bytes()
            self.assertEqual(sha(raw), MATERIALS[int(m['sourcePathID'])][1])
            original = TypeTreeHelper.read_typetree(template.serialized_type.node,
                EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            self.assertEqual(json.loads(json.dumps(original)), json.loads(Path(m['metadataFile']).read_bytes()))
            self.assertEqual(set(original['m_ValidKeywords']), set(m['exactMatches'][0]['keywords']))
            match = m['exactMatches'][0]
            self.assertEqual(sha(Path(match['glslFile']).read_bytes()), match['glslSHA256'])
        for record in self.document['files']:
            raw = (ARGS.candidate / record['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (record['bytes'], record['sha256']))
        self.assertEqual(self.document['characterSHA256'], self.profile['sha256'])

    def test_shader_body_arithmetic_is_preserved_for_new_sword_variants(self):
        def canonical(text):
            text = re.sub(r'\bfloat([234])x\1\b', r'mat\1', text)
            text = re.sub(r'\bfloat([234])\b', r'vec\1', text)
            text = text.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
            text = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', text)
            text = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', text)
            return re.sub(r'\s+', '', text)
        binding = json.loads((ARGS.materials / 'd15-sword-shader-bindings-private.json').read_bytes())
        for material in binding['materials']:
            original = Path(material['exactMatches'][0]['glslFile']).read_text()
            program = self.document['materials']['m_' + material['sourcePathID']]['program']
            metal = (ARGS.candidate / program['file']).read_text()
            bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', original, re.M | re.S)
            self.assertEqual(len(bodies), 2)
            wanted = Counter(canonical(line.strip()) for body in bodies for line in body.splitlines()
                if '=' in line and line.strip().endswith(';'))
            actual = Counter(canonical(line.strip()) for line in metal.splitlines()
                if '=' in line and line.strip().endswith(';'))
            self.assertFalse(wanted - actual, f'Original shader arithmetic was removed: {wanted - actual}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('candidate', 'materials', 'bundle', 'profile', 'model-tracks', 'held-tracks'):
        parser.add_argument('--' + name, type=Path, required=True)
    ARGS, tests = parser.parse_known_args()
    unittest.main(argv=[sys.argv[0], *tests], verbosity=2)
