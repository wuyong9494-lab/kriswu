#!/usr/bin/env python3
"""New scoped checks against the actual original leg assets; no build or network."""
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest
import warnings

import numpy as np

from bind_erlang_stomp_effect import bind, verify_resources
from erlang_effect_materials import MATERIALS, prepare_materials, selected_program

ARGS = None


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


class ActualLegChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        cls.document = json.loads(gzip.decompress((ARGS.candidate / 'SF3_D15_StompEffects.json.gz').read_bytes()))
        cls.receipt_raw = (ARGS.candidate / 'd15-stomp-effect-receipt-private.json').read_bytes()
        cls.receipt = json.loads(cls.receipt_raw)
        cls.bindings = json.loads((ARGS.materials / 'd15-shader-material-bindings-private.json').read_text())
        cls.objects = {o.path_id: o for o in UnityPy.load(ARGS.bundle.read_bytes()).objects}
        cls.shaders = {o.path_id: o for o in UnityPy.load(ARGS.shader_bundle.read_bytes()).objects if o.type.name == 'Shader'}

    def test_original_mesh_emitters_and_full_lifetime(self):
        from UnityPy.helpers.MeshHelper import MeshHandler
        effect = self.document['effects']['D15_fx_big_leg']
        self.assertEqual(len(effect['tracks']), 3)
        self.assertEqual({int(t['sourceParticleSystem']) for t in effect['tracks']},
            {-929469514926225548, 6055453625588746100, -1006497375095126156})
        mesh = MeshHandler(self.objects[-6222684053069387964].read())
        mesh.process()
        original = np.asarray(mesh.m_Vertices)[:, :3]
        faces = np.asarray(mesh.get_triangles()[0]).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        self.assertEqual(len(original), 685)
        for track in effect['tracks']:
            system = self.objects[int(track['sourceParticleSystem'])]
            source = system.read_typetree()
            proof = next(p for p in self.receipt['sourceEmitters'] if p['sourceParticleSystem'] == track['sourceParticleSystem'])
            self.assertEqual(sha(system.get_raw_data()), proof['sourceParticleSystemSHA256'])
            np.testing.assert_array_equal(np.asarray(track['geometry']['positions']).reshape(-1, 3), original * [1, 1, -1])
            np.testing.assert_array_equal(track['geometry']['indices'], faces)
            self.assertAlmostEqual(track['duration'], source['InitialModule']['startLifetime']['scalar'], places=6)
            self.assertEqual(track['duration'], 1.4)
            self.assertEqual(track['delay'], 0)
            self.assertNotIn('loopPeriod', track)
            self.assertGreater(track['duration'], 18 / 60)
            self.assertGreater(track['frames'][0][10], 0)
            self.assertEqual(track['frames'][-1][10], 0)
        verify_resources(self.document, ARGS.candidate)

    def test_original_shader_expressions_and_integer_uniform(self):
        def canonical(text):
            text = re.sub(r'\bfloat([234])x\1\b', r'mat\1', text)
            text = re.sub(r'\bfloat([234])\b', r'vec\1', text)
            text = text.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
            text = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', text)
            text = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', text)
            return re.sub(r'\s+', '', text)
        programs = self.document['materials']
        self.assertEqual(len(programs), 3)
        for binding in self.bindings['materials']:
            self.assertEqual(binding['sourceObjectSHA256'], MATERIALS[int(binding['sourcePathID'])][1])
            shader = self.shaders[int(binding['shaderPathID'])]
            shader_record = next(s for s in self.bindings['shaders'] if s['pathID'] == binding['shaderPathID'])
            self.assertEqual(sha(shader.get_raw_data()), shader_record['sourceObjectSHA256'])
            original = Path(binding['exactMatches'][0]['glslFile']).read_text()
            self.assertEqual(sha(original.encode()), binding['exactMatches'][0]['glslSHA256'])
            material = programs['m_' + binding['sourcePathID']]
            self.assertEqual(set(material['keywords']), set(binding['exactMatches'][0]['keywords']))
            metal = (ARGS.candidate / material['program']['file']).read_text()
            # Independently compare every original shader-body assignment.
            # Only shader interface prefixes, vector names and sample calls
            # are normalized; arithmetic and swizzles remain exact.
            bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', original, re.M | re.S)
            self.assertEqual(len(bodies), 2)
            wanted = Counter(canonical(line.strip()) for body in bodies for line in body.splitlines()
                             if '=' in line and line.strip().endswith(';'))
            actual = Counter(canonical(line.strip()) for line in metal.splitlines()
                             if '=' in line and line.strip().endswith(';'))
            self.assertFalse(wanted - actual, f'Original shader expression was removed: {wanted - actual}')
            if binding['sourceName'] == 'mtl_freshnel_premltpl':
                self.assertRegex(original, r'uniform\s+int _Invert;')
                self.assertIn('int _Invert = int(u.data[39].x);', metal)
                self.assertEqual(material['floats']['_Invert'], 1)
                self.assertEqual(material['raster']['source'], 1)
                self.assertEqual(material['raster']['destination'], 10)

    def test_wrong_keyword_and_changed_resource_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'unique exact keyword'):
                selected_program(self.shaders[8709495073532153010], ['NOT_AN_ORIGINAL_D15_KEYWORD'], root)
            resource = next(f for f in self.document['files'] if f['name'].endswith('.metal'))
            (root / resource['name']).write_bytes(b'invented replacement')
            changed = copy.deepcopy(self.document)
            changed['files'] = [resource]
            with self.assertRaisesRegex(ValueError, 'resource changed'):
                verify_resources(changed, root)

    def test_final_profile_rebind_changes_only_identity(self):
        profile_raw = ARGS.profile.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'bound'
            bind(ARGS.candidate, sha(self.receipt_raw), ARGS.profile, sha(profile_raw), output)
            actual = json.loads(gzip.decompress((output / 'SF3_D15_StompEffects.json.gz').read_bytes()))
            expected = copy.deepcopy(self.document)
            expected['characterSHA256'] = json.loads(profile_raw)['sha256']
            self.assertEqual(actual, expected)
            for file in self.document['files']:
                self.assertEqual((output / file['name']).read_bytes(), (ARGS.candidate / file['name']).read_bytes())
            bad_profile = json.loads(profile_raw)
            next(t for t in bad_profile['summonTracks'] if t['role'] == 'erlangSummon_stomp')['sourceEndEventTick'] = 17
            p = Path(temporary) / 'bad-profile.json'
            p.write_text(json.dumps(bad_profile))
            with self.assertRaisesRegex(ValueError, 'exact independently sampled'):
                bind(ARGS.candidate, sha(self.receipt_raw), p, sha(p.read_bytes()), Path(temporary) / 'invalid')

    def test_complete_material_preparation_matches_verified_programs(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, program_file, additional = prepare_materials(ARGS.bundle.parent, ARGS.archive,
                ARGS.shader_bundle, Path(temporary) / 'materials')
            fresh = json.loads(program_file.read_text())['materials']
            self.assertEqual(len(fresh), 3)
            for item in fresh:
                current = self.document['materials']['m_' + item['sourceMaterialPathID']]
                self.assertEqual(item['program'], current['program'])
                self.assertEqual(item['raster'], current['raster'])
                self.assertEqual((program_file.parent / item['program']['file']).read_bytes(),
                    (ARGS.candidate / item['program']['file']).read_bytes())
            records = json.loads(additional.read_text())['records']
            self.assertEqual([r['pathID'] for r in records], ['-2244836283075552378'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('candidate', 'materials', 'bundle', 'shader-bundle', 'profile', 'archive'):
        parser.add_argument('--' + name, type=Path, required=True)
    ARGS, remaining = parser.parse_known_args()
    unittest.main(argv=[__file__, *remaining])
