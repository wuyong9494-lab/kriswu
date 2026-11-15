#!/usr/bin/env python3
"""Narrow checks against actual original laser objects and the final actor."""
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
from prepare_erlang_skill_effects import EFFECT, ROLE, SYSTEMS, MESH_SYSTEMS, BILLBOARD_SYSTEMS, source_binding
from erlang_skill_effect_materials import LASER_MATERIALS


def sha(raw): return hashlib.sha256(raw).hexdigest()


class ActualSkillEffectChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        warnings.filterwarnings('ignore')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        cls.document = json.loads(gzip.decompress((ARGS.candidate / 'SF3_D15_SkillEffects.json.gz').read_bytes()))
        cls.receipt = json.loads((ARGS.candidate / 'd15-skill-effects-receipt-private.json').read_bytes())
        cls.environment = UnityPy.load(str(ARGS.bundle))
        cls.objects = {o.path_id: o for o in cls.environment.objects}
        cls.profile = json.loads(ARGS.profile.read_bytes())

    def test_original_fifteen_emitters_have_explicit_four_layer_gap(self):
        scope = self.document['erlangSkillScopes'][EFFECT]
        tracks = self.document['effects'][EFFECT]['tracks']
        self.assertEqual((scope['sourceActiveEmitters'], len(scope['boundEmitters']), len(scope['unboundEmitters'])), (19, 15, 4))
        self.assertEqual(set(scope['boundEmitters']), set(map(str, SYSTEMS)))
        self.assertEqual(set(t['sourceParticleSystem'] for t in tracks), set(scope['boundEmitters']))
        self.assertEqual(len(tracks), 247)
        self.assertFalse(scope['completePrefab'])
        self.assertFalse(scope['sourceMirroredVariantBound'])
        self.assertFalse(scope['separateGroundPrefabBound'])
        for row in self.receipt['unboundEmitters']:
            renderer = self.objects[int(row['sourceRendererPathID'])].read_typetree()
            self.assertEqual(renderer['m_RenderMode'], 1)
            self.assertEqual(row['bindingStatus'], 'stretched_billboard_direction_unbound')
        for track in tracks:
            if int(track['sourceParticleSystem']) in MESH_SYSTEMS:
                self.assertEqual((track['sourceRenderMode'], track['sourceRenderAlignment']), (4, 2))
                self.assertIn('geometry', track)
            else:
                self.assertIn(int(track['sourceParticleSystem']), BILLBOARD_SYSTEMS)
                self.assertEqual((track['sourceRenderMode'], track['sourceRenderAlignment']), (0, 0))
                self.assertNotIn('geometry', track)
                self.assertNotIn('orientations', track)

    def test_original_mesh_geometry_including_recovered_spiral(self):
        from UnityPy.helpers.MeshHelper import MeshHandler
        local = self.objects[-8586395260392917980]
        handler = MeshHandler(local.read()); handler.process()
        expected_local = np.asarray(handler.m_Vertices)[:, :3] * [1, 1, -1]
        expected_indices = np.asarray(handler.get_triangles()[0]).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        proof = json.loads(ARGS.mesh_inputs.read_bytes())['records'][0]
        self.assertEqual(sha(Path(proof['rawFile']).read_bytes()), '476d50be9a7fc74eae8ca77ba85d38afa82945e02b98d7bf0ab4d837dd31b48c')
        with np.load(proof['arraysFile'], allow_pickle=False) as original:
            expected_spiral = original['positions'][:, :3] * [1, 1, -1]
            spiral_indices = original['triangles0'].reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        lightning = {-818232598598915642, -4037953332193531450}
        for track in self.document['effects'][EFFECT]['tracks']:
            if 'geometry' not in track: continue
            spiral = int(track['sourceParticleSystem']) in lightning
            np.testing.assert_array_equal(np.asarray(track['geometry']['positions']).reshape(-1, 3), expected_spiral if spiral else expected_local)
            np.testing.assert_array_equal(track['geometry']['indices'], spiral_indices if spiral else expected_indices)

    def test_interval122_head_follow_and_reject_changed_clock_or_model(self):
        binding, proof = source_binding(self.profile, ARGS.model_tracks, ARGS.rules / 'd15-lock-1432-compact-private.json')
        actual = self.document['erlangSkillBindings'][0].copy(); actual.pop('lifetimeTicks')
        self.assertEqual(actual, binding)
        self.assertEqual((binding['bone'], binding['attachToLocal'], binding['follow']), ('head', True, [1, 1, 1]))
        self.assertEqual(binding['release']['atTick'], (binding['sourceIntervalStart'] - 1) * 2)
        self.assertEqual(binding['release']['anchor'], 'head.x')
        self.assertEqual(proof['sourceCreateTrigger']['events'], proof['sourceEffectTrigger']['events'])
        wrong = copy.deepcopy(self.profile)
        next(r for r in wrong['erlangRules']['releases'] if r['modelRole'] == ROLE)['atTick'] = 120
        with self.assertRaisesRegex(ValueError, 'Runtime eye release'):
            source_binding(wrong, ARGS.model_tracks, ARGS.rules / 'd15-lock-1432-compact-private.json')
        wrong = copy.deepcopy(self.profile)
        next(t for t in wrong['summonTracks'] if t['role'] == ROLE)['root'][0][1] += .01
        with self.assertRaisesRegex(ValueError, 'exact original eye model track'):
            source_binding(wrong, ARGS.model_tracks, ARGS.rules / 'd15-lock-1432-compact-private.json')

    def test_original_particle_lifetime_and_runtime_resource_bounds(self):
        effect = self.document['effects'][EFFECT]; binding = self.document['erlangSkillBindings'][0]
        self.assertEqual(binding['lifetimeTicks'], 145)
        self.assertEqual(binding['sourceModelEndTick'], 122)
        self.assertGreater(effect['duration'], 144 / 60)
        self.assertLessEqual(effect['duration'], 145 / 60)
        self.assertEqual(effect['duration'], max(t['delay'] + t['duration'] for t in effect['tracks']))
        self.assertTrue(any(t['delay'] < 123 / 60 < t['delay'] + t['duration'] for t in effect['tracks']))
        self.assertTrue(all('loopPeriod' not in t for t in effect['tracks']))
        self.assertLess(sum(len(t['frames']) for t in effect['tracks']), 1_000_000)
        self.assertLess(sum(len(t.get('geometry', {}).get('positions', [])) // 3 for t in effect['tracks']), 600_000)
        for record in self.document['files']:
            raw = (ARGS.candidate / record['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (record['bytes'], record['sha256']))

    def test_exact_material_variants_do_not_activate_stale_invalid_keywords(self):
        import UnityPy
        from UnityPy.helpers import TypeTreeHelper
        from UnityPy.streams import EndianBinaryReader
        template = next(o for o in self.environment.objects if o.type.name == 'Material')
        bindings = json.loads((ARGS.materials / 'd15-skill-shader-bindings-private.json').read_bytes())
        shaders = {o.path_id: o for o in UnityPy.load(str(ARGS.shader_bundle)).objects if o.type.name == 'Shader'}
        self.assertEqual({int(m['sourcePathID']) for m in bindings['materials']}, set(LASER_MATERIALS))
        for m in bindings['materials']:
            raw = (ARGS.materials / (m['sourcePathID'] + '.raw')).read_bytes()
            self.assertEqual(sha(raw), LASER_MATERIALS[int(m['sourcePathID'])][1])
            material = TypeTreeHelper.read_typetree(template.serialized_type.node,
                EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            self.assertEqual(json.loads(json.dumps(material)), json.loads(Path(m['metadataFile']).read_bytes()))
            self.assertEqual(set(material['m_ValidKeywords']), set(m['exactMatches'][0]['keywords']))
            shader = next(s for s in bindings['shaders'] if s['pathID'] == m['shaderPathID'])
            original_shader = shaders[int(shader['pathID'])]
            self.assertEqual(sha(original_shader.get_raw_data()), shader['sourceObjectSHA256'])
            keywords = original_shader.read_typetree()['m_ParsedForm']['m_KeywordNames']
            self.assertTrue(set(material['m_InvalidKeywords']).isdisjoint(keywords))
            actual = self.document['materials']['m_' + m['sourcePathID']]
            self.assertEqual(actual['sourceMaterialSHA256'], sha(raw))
            self.assertEqual(set(actual['keywords']), set(material['m_ValidKeywords']))

    def test_new_seven_shader_programs_retain_original_body_arithmetic(self):
        def canonical(text):
            text = re.sub(r'\bfloat([234])x\1\b', r'mat\1', text)
            text = re.sub(r'\bfloat([234])\b', r'vec\1', text)
            text = text.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
            text = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', text)
            text = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', text)
            return re.sub(r'\s+', '', text)
        binding = json.loads((ARGS.materials / 'd15-skill-shader-bindings-private.json').read_bytes())
        for material in binding['materials']:
            original = Path(material['exactMatches'][0]['glslFile']).read_text()
            program = self.document['materials']['m_' + material['sourcePathID']]['program']
            metal = (ARGS.candidate / program['file']).read_text()
            bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', original, re.M | re.S)
            self.assertEqual(len(bodies), 2)
            wanted = Counter(canonical(line.strip()) for body in bodies for line in body.splitlines() if '=' in line and line.strip().endswith(';'))
            actual = Counter(canonical(line.strip()) for line in metal.splitlines() if '=' in line and line.strip().endswith(';'))
            self.assertFalse(wanted - actual, f'Original shader arithmetic removed: {wanted - actual}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('candidate', 'materials', 'bundle', 'shader-bundle', 'profile', 'model-tracks', 'rules', 'mesh-inputs'):
        parser.add_argument('--' + name, type=Path, required=True)
    ARGS, tests = parser.parse_known_args()
    unittest.main(argv=[sys.argv[0], *tests], verbosity=2)
