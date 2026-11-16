#!/usr/bin/env python3
"""Actual recovered D15 skill inputs, geometry, formulas and rejection checks."""
import argparse
from collections import Counter
import copy
import gzip
import json
import math
from pathlib import Path
import re
import unittest
import warnings

import numpy as np

from recover_erlang_skill_effects import (
    EYE, EARTH, MEDITATION, SYSTEMS, MATERIAL_SCOPE, MODEL_IDENTITY, RULE_IDENTITIES,
    source_bindings, sha, PROFILE_SHA, CHARACTER_SHA,
)


class RecoveredSkillChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        warnings.filterwarnings('ignore'); UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        cls.environment = UnityPy.load(str(cls.bundle))
        cls.objects = {obj.path_id: obj for obj in cls.environment.objects}
        cls.cache = cls.recovery / 'source-inputs-private'
        cls.runtime = cls.recovery / 'runtime'
        cls.document = json.loads(gzip.decompress((cls.runtime / 'SF3_D15_SkillEffects.json.gz').read_bytes()))
        cls.receipt = json.loads((cls.recovery / 'skill-recovery-private.json').read_bytes())
        cls.inputs = json.loads((cls.cache / 'source-cache-recovery-receipt-private.json').read_bytes())
        cls.actor = json.loads(cls.profile.read_bytes())
        cls.models = json.loads(cls.model_tracks.read_bytes())
        cls.rules = {lock: json.loads((cls.rules_directory / f'd15-lock-{lock}-source-fields-private.json').read_bytes())
                     for lock in RULE_IDENTITIES}

    def test_cache_and_all_runtime_resource_identities(self):
        expected = {row['name'] for row in self.inputs['files']} | {'source-cache-recovery-receipt-private.json'}
        self.assertEqual({str(p.relative_to(self.cache)) for p in self.cache.rglob('*') if p.is_file()}, expected)
        for record in self.inputs['files']:
            raw = (self.cache / record['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (record['bytes'], record['sha256']))
        self.assertEqual({int(row['pathID']): row['sourceObjectSHA256'] for row in self.inputs['materialRecords']}, MATERIAL_SCOPE)
        self.assertEqual(len(self.document['materials']), 26)
        self.assertEqual(len(self.document['files']), 100)
        for record in self.document['files']:
            raw = (self.runtime / record['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (record['bytes'], record['sha256']))
        self.assertLess(sum(row['bytes'] for row in self.document['files']), 40_000_000)
        self.assertEqual(sha(self.profile.read_bytes()), PROFILE_SHA)
        self.assertEqual(sha(self.model_tracks.read_bytes()), MODEL_IDENTITY[1])
        self.assertEqual(self.document['characterSHA256'], CHARACTER_SHA)
        for lock, (size, digest) in RULE_IDENTITIES.items():
            raw = (self.rules_directory / f'd15-lock-{lock}-source-fields-private.json').read_bytes()
            self.assertEqual((len(raw), sha(raw)), (size, digest))

    def test_original_emitter_renderers_and_nine_exclusions(self):
        expected = {EYE: (19, 15, 4, 247, 145), EARTH: (19, 15, 4, 46, 77), MEDITATION: (9, 8, 1, 21, 41)}
        for name, (total, bound, omitted, count, lifetime) in expected.items():
            scope = self.document['erlangSkillScopes'][name]; effect = self.document['effects'][name]
            self.assertEqual((scope['sourceActiveEmitters'], len(scope['boundEmitters']), len(scope['unboundEmitters'])),
                             (total, bound, omitted))
            self.assertFalse(scope['completePrefab'])
            self.assertEqual(set(scope['boundEmitters']), set(map(str, SYSTEMS[name])))
            self.assertEqual({track['sourceParticleSystem'] for track in effect['tracks']}, set(scope['boundEmitters']))
            self.assertEqual(len(effect['tracks']), count)
            proofs = {row['sourceParticleSystem']: row for row in self.receipt['sourceEffects'][name]['boundEmitters']}
            for track in effect['tracks']:
                proof = proofs[track['sourceParticleSystem']]
                source = self.objects[int(proof['sourceParticleSystem'])]
                renderer = self.objects[int(proof['sourceRendererPathID'])]
                self.assertEqual(sha(source.get_raw_data()), proof['sourceParticleSystemSHA256'])
                self.assertEqual(sha(renderer.get_raw_data()), proof['sourceRendererSHA256'])
                original = renderer.read_typetree()
                self.assertEqual((track['sourceRenderMode'], track['sourceRenderAlignment']),
                                 (original['m_RenderMode'], original['m_RenderAlignment']))
                self.assertNotIn('loopPeriod', track)
            for proof in self.receipt['sourceEffects'][name]['unboundEmitters']:
                source = self.objects[int(proof['sourceParticleSystem'])].read_typetree()
                renderer = self.objects[int(proof['sourceRendererPathID'])].read_typetree()
                reason = proof['bindingStatus']
                if reason == 'stretched_billboard_direction_unbound':
                    self.assertEqual(renderer['m_RenderMode'], 1)
                elif reason == 'mesh_shape_has_no_source_mesh':
                    self.assertEqual(source['ShapeModule']['type'], 6)
                    self.assertEqual(source['ShapeModule']['m_Mesh'], {'m_FileID': 0, 'm_PathID': 0})
                elif reason == 'shape_birth_alignment_unbound':
                    self.assertTrue(source['ShapeModule']['alignToDirection'])
                else:
                    self.fail('Unexpected omission: ' + reason)
            binding = next(row for row in self.document['erlangSkillBindings'] if row['effect'] == name)
            self.assertEqual(binding['lifetimeTicks'], lifetime)
            self.assertEqual(lifetime, math.ceil(effect['duration'] * 60))

    def test_exact_mesh_vertices_and_winding(self):
        from UnityPy.helpers.MeshHelper import MeshHandler
        mesh_records = {int(row['pathID']): row for row in self.inputs['meshRecords']}
        checked = {}
        for name, effect in self.document['effects'].items():
            proofs = {row['sourceParticleSystem']: row for row in self.receipt['sourceEffects'][name]['boundEmitters']}
            for track in effect['tracks']:
                if track['sourceRenderMode'] != 4:
                    continue
                renderer = self.objects[int(proofs[track['sourceParticleSystem']]['sourceRendererPathID'])].read_typetree()
                pointer = renderer['m_Mesh']; pid = int(pointer['m_PathID'])
                if pid not in checked:
                    if pointer['m_FileID'] == 0:
                        handler = MeshHandler(self.objects[pid].read()); handler.process()
                        vertices = np.asarray(handler.m_Vertices)[:, :3]
                        indices = np.asarray(handler.get_triangles()[0]).reshape(-1, 3)
                    else:
                        record = mesh_records[pid]
                        with np.load(record['arraysFile'], allow_pickle=False) as arrays:
                            vertices = arrays['positions'][:, :3].copy()
                            indices = arrays['triangles0'].reshape(-1, 3).copy()
                    checked[pid] = (vertices * [1, 1, -1], indices[:, [0, 2, 1]].reshape(-1))
                vertices, indices = checked[pid]
                np.testing.assert_array_equal(np.asarray(track['geometry']['positions']).reshape(-1, 3), vertices)
                np.testing.assert_array_equal(track['geometry']['indices'], indices)
        self.assertTrue({-6622822173136016352, -2272744349922921157, -5020005211651685517}.issubset(checked))

    def test_original_source_shader_arithmetic_and_opaque_stone(self):
        def canonical(text):
            text = re.sub(r'\bfloat([234])x\1\b', r'mat\1', text)
            text = re.sub(r'\bfloat([234])\b', r'vec\1', text)
            text = text.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
            text = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', text)
            text = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', text)
            return re.sub(r'\s+', '', text)
        bindings = json.loads((self.cache / 'shader-source/h17-shader-material-bindings-private.json').read_bytes())
        for material in bindings['materials']:
            original = Path(material['exactMatches'][0]['glslFile']).read_text()
            target = self.document['materials']['m_' + material['sourcePathID']]
            program = (self.runtime / target['program']['file']).read_text()
            bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', original, re.M | re.S)
            self.assertEqual(len(bodies), 2)
            wanted = Counter(canonical(line.strip()) for body in bodies for line in body.splitlines()
                             if '=' in line and line.strip().endswith(';'))
            actual = Counter(canonical(line.strip()) for line in program.splitlines()
                             if '=' in line and line.strip().endswith(';'))
            self.assertFalse(wanted - actual, 'Original shader arithmetic missing: ' + str(wanted - actual))
            self.assertEqual(program.count('discard_fragment();'), len(re.findall(r'\bdiscard\s*;', original)))
        stone = self.document['materials']['m_-654479186809044038']
        self.assertEqual((stone['raster']['source'], stone['raster']['destination'], stone['raster']['zWrite']), (1, 0, True))
        self.assertEqual(set(stone['textures']), {'_StoneColor_Tex', '_StoneCracksNoiseScroll_Tex', '_StoneCracks_Tex', '_StoneGradient_Tex'})

    def test_clock_parent_and_costume_changes_are_rejected(self):
        bindings, _ = source_bindings(self.actor, self.models, self.rules)
        for actual in self.document['erlangSkillBindings']:
            value = actual.copy(); value.pop('lifetimeTicks')
            self.assertEqual(value, bindings[actual['effect']])
        self.assertEqual(bindings[EARTH]['shift'], [0, 0, 0])
        self.assertEqual(bindings[EARTH]['release']['offset'], [20, 0, 0])
        self.assertEqual((bindings[MEDITATION]['sourceTarget'], bindings[MEDITATION]['shift']), ('modelParent', [0, .03, 0]))
        for role, wrong_tick in (('erlangSummon_eye', 120), ('erlangSummon_earth', 40)):
            actor = copy.deepcopy(self.actor)
            next(row for row in actor['erlangRules']['releases'] if row['modelRole'] == role)['atTick'] = wrong_tick
            with self.assertRaises(ValueError):
                source_bindings(actor, self.models, self.rules)
        for kind in ('parent', 'costume'):
            rules = copy.deepcopy(self.rules)
            med = next(row for row in rules[1438]['sets'][0]['triggers'] if row['triggerIndex'] == 1)
            if kind == 'parent': med['actions'][0]['a46'][4] = 'enum65537'
            else: med['conditions'] = None
            with self.assertRaises(ValueError):
                source_bindings(self.actor, self.models, rules)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('recovery', 'bundle', 'profile', 'model-tracks', 'rules-directory'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for key, value in vars(args).items(): setattr(RecoveredSkillChecks, key, value)
    unittest.main(argv=['test_erlang_skill_recovered_input.py'], verbosity=2)
