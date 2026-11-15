#!/usr/bin/env python3
"""Focused checks of an actual private six-material export; no decoding or GPU."""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
from types import SimpleNamespace
import unittest
from unittest import mock

import prepare_erlang_unbound_materials as source

ARGS = None


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(line):
    line = re.sub(r'\bfloat([234])x\1\b', r'mat\1', line)
    line = re.sub(r'\bfloat([234])\b', r'vec\1', line)
    line = line.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
    line = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', line)
    line = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', line)
    return re.sub(r'\s+', '', line)


class UnboundMaterialChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = ARGS.candidate.resolve()
        cls.manifest = json.loads((cls.candidate / 'erlang-unbound-materials-source-only.json').read_text())

    def test_all_six_original_program_bodies_retain_their_arithmetic(self):
        self.assertEqual(len(self.manifest['materials']), 6)
        for item in self.manifest['materials']:
            with self.subTest(material=item['sourcePathID']):
                expected = source.MATERIALS[int(item['sourcePathID'])]
                original = Path(item['exactVariant']['glslFile']).read_bytes()
                self.assertEqual(digest(original), expected['variant'][-1])
                self.assertEqual(item['conversion']['status'], 'exported-source-only')
                program = item['conversion']['program']
                metal = (self.candidate / item['directory'] / program['file']).read_bytes()
                self.assertEqual((len(metal), digest(metal)), (program['bytes'], program['sha256']))
                bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', original.decode(), re.M | re.S)
                self.assertEqual(len(bodies), 2)
                wanted = Counter(canonical(line) for body in bodies for line in body.splitlines()
                                 if '=' in line and line.strip().endswith(';'))
                actual = Counter(canonical(line) for line in metal.decode().splitlines()
                                 if '=' in line and line.strip().endswith(';'))
                self.assertFalse(wanted - actual, f'Original arithmetic was lost: {wanted - actual}')
                self.assertEqual(set(program['textures']), set(expected['textures']))
                self.assertEqual(item['sourceShaderSHA256'], source.SHADERS[expected['shaderID']])
                self.assertFalse(item['conversion']['runtimeBound'])

    def test_all_ten_original_streams_and_eighty_one_mips_are_preserved(self):
        self.assertEqual(len(self.manifest['textures']), 10)
        count = 0
        for item in self.manifest['textures']:
            expected = source.TEXTURES[int(item['sourcePathID'])]
            directory = self.candidate / item['directory']
            raw_object = (directory / item['sourceObject']['file']).read_bytes()
            self.assertEqual(digest(raw_object), expected['rawSHA256'])
            stream = (directory / item['sourceStream']['file']).read_bytes()
            self.assertEqual((len(stream), digest(stream)), (expected['streamBytes'], expected['streamSHA256']))
            self.assertEqual(len(item['mips']), expected['mips'])
            cursor = 0
            for number, level in enumerate(item['mips']):
                self.assertEqual((level['level'], level['offset']), (number, cursor))
                self.assertEqual((level['width'], level['height']),
                    (max(1, expected['width'] >> number), max(1, expected['height'] >> number)))
                part = stream[cursor:cursor+level['bytes']]
                self.assertEqual(digest(part), level['compressedSHA256'])
                rgba = (directory / level['rgba']['file']).read_bytes()
                self.assertEqual(len(rgba), level['width'] * level['height'] * 4)
                self.assertEqual(digest(rgba), level['rgba']['sha256'])
                if expected['format'] == 45:
                    self.assertEqual(set(rgba[3::4]), {255})
                cursor += level['bytes']
            self.assertEqual(cursor, len(stream))
            count += len(item['mips'])
        self.assertEqual(count, 81)

    def test_changed_keyword_variant_and_cross_cab_reference_are_rejected(self):
        item = self.manifest['materials'][0]
        expected = source.MATERIALS[int(item['sourcePathID'])]
        material = json.loads((self.candidate / item['directory'] / 'source-material.json').read_text())
        changed = copy.deepcopy(material)
        changed['m_ValidKeywords'].append('_UNREVIEWED_VARIANT')
        with self.assertRaisesRegex(ValueError, 'name or keywords'):
            source.validate_material(changed, expected)
        for field, replacement in [('blobIndex', -1), ('glslSHA256', '0' * 64)]:
            variant = dict(item['exactVariant'], **{field: replacement})
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'exact keyword program'):
                source.validate_variant(variant, expected['variant'])
        owner = SimpleNamespace(assets_file=SimpleNamespace(name='CAB-owner',
            externals=[SimpleNamespace(path='archive:/CAB-source/CAB-source')]))
        target = SimpleNamespace(path_id=-3539672900455825089, assets_file=SimpleNamespace(name='CAB-other'))
        with self.assertRaisesRegex(ValueError, 'reference CAB'):
            source.require_reference(owner, {'m_FileID': 1, 'm_PathID': target.path_id}, target)

    def test_rectangular_and_rgb_small_block_tails_reject_truncation_or_extension(self):
        self.assertEqual([m['bytes'] for m in source.mip_ranges(256, 64, 9, 47, 21904)],
                         [16384, 4096, 1024, 256, 64, 32, 16, 16, 16])
        self.assertEqual([m['bytes'] for m in source.mip_ranges(1024, 1024, 11, 45, 699064)],
                         [524288, 131072, 32768, 8192, 2048, 512, 128, 32, 8, 8, 8])
        for args in [(256, 64, 9, 47, 21903), (256, 64, 9, 47, 21905),
                     (1024, 1024, 10, 45, 699064), (1024, 1024, 11, 45, 699063),
                     (256, 64, 9, 46, 21904), (True, 64, 7, 47, 256)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                source.mip_ranges(*args)

    def test_adapter_and_late_uniform_failures_stay_explicitly_unsupported(self):
        item = self.manifest['materials'][0]
        directory = self.candidate / item['directory']
        binding = json.loads((directory / 'exact-source-binding.json').read_text())
        material = json.loads((directory / 'source-material.json').read_text())
        with mock.patch.object(source, 'translate', side_effect=ValueError('unsupported original state')):
            result = source.translate_material(binding, directory, material)
        self.assertEqual(result['status'], 'unsupported')
        self.assertFalse(result['runtimeBound'])
        self.assertNotIn('program', result)
        changed = copy.deepcopy(material)
        changed['m_SavedProperties']['m_Floats'] = [v for v in changed['m_SavedProperties']['m_Floats']
                                                   if v[0] != '_Transparent']
        patch = dict(item['conversion'], projectColorSpace=0, projectAnisotropicFiltering=0)
        with mock.patch.object(source, 'translate', return_value={'materials': [patch]}):
            result = source.translate_material(binding, directory, changed)
        self.assertEqual(result['status'], 'unsupported')
        self.assertFalse(result['runtimeBound'])
        self.assertNotIn('program', result)

    def test_inventory_and_nonruntime_project_boundaries_remain_honest(self):
        manifest = self.manifest
        self.assertEqual((manifest['status'], manifest['exportedMaterialCount'], manifest['unsupportedMaterialCount']),
                         ('exported-source-only', 6, 0))
        self.assertFalse(manifest['runtimeBound'])
        self.assertFalse(manifest['completeParticleEffects'])
        self.assertFalse(manifest['parser']['originalUnityEngineVersionVerified'])
        for key in ('appleCompilation', 'runtimeGPU', 'particleSampling', 'nativeClient'):
            self.assertEqual(manifest['validation'][key], 'not-run')
        context = manifest['sourceProjectContext']
        self.assertFalse(context['playerCompleteTypeTreeRead'])
        self.assertFalse(context['runtimeQualitySelectionVerified'])
        self.assertEqual(context['verifiedColorSpaceField'],
                         dict(name='m_ActiveColorSpace', offset=256, bytes=4, value=0))
        self.assertEqual(context['serializedDefaultQuality'], 0)
        self.assertGreater(len(set(q['anisotropicTextures'] for q in context['qualityLevels'])), 1)
        observed = set()
        for item in manifest['resources']:
            path = self.candidate / item['file']
            self.assertIn(self.candidate, path.resolve().parents)
            raw = path.read_bytes()
            self.assertEqual((len(raw), digest(raw)), (item['bytes'], item['sha256']))
            self.assertNotIn(item['file'], observed)
            observed.add(item['file'])
        self.assertEqual(observed, {str(p.relative_to(self.candidate)) for p in self.candidate.rglob('*')
                                   if p.is_file() and p.name != 'erlang-unbound-materials-source-only.json'})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    ARGS = parser.parse_args()
    unittest.main(argv=['test_erlang_unbound_materials.py'], verbosity=2)
