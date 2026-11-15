#!/usr/bin/env python3
"""Focused checks of one actual private Avatar source-only export; no GPU/build."""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import unittest

from prepare_erlang_avatar_material import (PROGRAM_SHA, TEXTURES, etc2_mip_ranges,
                                           material_values, source_metal)

ARGS = None


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(expression):
    expression = re.sub(r'\bfloat([234])x\1\b', r'mat\1', expression)
    expression = re.sub(r'\bfloat([234])\b', r'vec\1', expression)
    expression = expression.replace('rsqrt(', 'inversesqrt(').replace('o.position', 'gl_Position')
    expression = re.sub(r'\b[oi]\.(vs_\w+)\b', r'\1', expression)
    expression = re.sub(r'(\w+)\.sample\(\1Sampler,\s*', r'texture(\1,', expression)
    return re.sub(r'\s+', '', expression)


class AvatarSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ARGS.candidate / 'avatar-normal-source-only.json').read_text())
        cls.source = Path(cls.manifest['exactVariant']['glslFile']).read_bytes()
        cls.metal = (ARGS.candidate / cls.manifest['program']['file']).read_text()
        cls.material = json.loads((ARGS.candidate / 'normal-avatar.material.json').read_text())

    def test_every_original_arithmetic_assignment_and_source_vertex_interface(self):
        self.assertEqual(sha(self.source), PROGRAM_SHA)
        bodies = re.findall(r'void main\(\)\s*\{(.*?)^\}', self.source.decode(), re.M | re.S)
        self.assertEqual(len(bodies), 2)
        wanted = Counter(canonical(line.strip()) for body in bodies for line in body.splitlines()
                         if '=' in line and line.strip().endswith(';'))
        actual = Counter(canonical(line.strip()) for line in self.metal.splitlines()
                         if '=' in line and line.strip().endswith(';'))
        self.assertFalse(wanted - actual, f'Original arithmetic was lost: {wanted - actual}')
        self.assertIn('float4 in_POSITION0 = a.position;', self.metal)
        self.assertIn('float3 in_NORMAL0 = a.normal.xyz;', self.metal)
        self.assertIn('float4 in_TANGENT0 = a.tangent;', self.metal)
        self.assertIn('float4 in_COLOR0 = a.color;', self.metal)
        self.assertNotIn('triad_texcoord', self.metal)
        self.assertNotIn('u.data[27]', self.metal)
        self.assertIn('u_xlat1.w = 1.0;', self.metal)
        self.assertRegex(self.metal, r'int _Invert = int\(u\.data\[\d+\]\.x\);')

    def test_all_eleven_original_mips_and_small_block_tails_are_retained(self):
        self.assertEqual(self.manifest['originalMipCount'], 11)
        total = 0
        for slot, expected in TEXTURES.items():
            texture = self.manifest['textures'][slot]
            stream = (ARGS.candidate / texture['originalStream']['file']).read_bytes()
            self.assertEqual((len(stream), sha(stream)), (expected['dataBytes'], expected['dataSHA']))
            self.assertEqual(len(texture['mips']), expected['mips'])
            cursor = 0
            for index, mip in enumerate(texture['mips']):
                self.assertEqual((mip['level'], mip['offset']), (index, cursor))
                self.assertEqual((mip['width'], mip['height']), (max(1, 512 >> index),) * 2)
                part = stream[cursor:cursor+mip['bytes']]
                self.assertEqual(sha(part), mip['compressedSHA256'])
                rgba = (ARGS.candidate / mip['rgba']['file']).read_bytes()
                self.assertEqual(len(rgba), mip['width'] * mip['height'] * 4)
                self.assertEqual(sha(rgba), mip['rgba']['sha256'])
                cursor += mip['bytes']
            self.assertEqual(cursor, len(stream))
            total += len(texture['mips'])
        self.assertEqual(total, 11)
        tail = self.manifest['textures']['_MainTex']['mips'][-3:]
        self.assertEqual([(m['width'], m['bytes']) for m in tail], [(4, 16), (2, 16), (1, 16)])

    def test_source_white_default_raster_and_nonruntime_status_remain_explicit(self):
        default = self.manifest['textures']['_MainTex2']
        self.assertIsNone(default['sourcePathID'])
        self.assertEqual(default['sourceKind'], 'shader-declared-white-default')
        self.assertEqual((ARGS.candidate / default['rgba']['file']).read_bytes(), bytes([255])*4)
        self.assertEqual(self.manifest['raster'], dict(queue=3000, sourceBlend=5, destinationBlend=10,
            cull=0, zWrite=False, zTest=4, lighting=False))
        self.assertFalse(self.manifest['runtimeBound'])
        self.assertFalse(self.manifest['genericFadeAdded'])
        self.assertEqual(self.manifest['validation']['appleCompilation'], 'not-run')
        self.assertEqual(self.manifest['validation']['runtimeGPU'], 'not-run')
        self.assertEqual(self.manifest['compilePreparation']['status'], 'prepared-not-executed')

    def test_changed_original_program_is_rejected_before_translation(self):
        changed = bytearray(self.source)
        changed[10] ^= 1
        with self.assertRaisesRegex(ValueError, 'Unreviewed original Avatar program'):
            source_metal(bytes(changed))

    def test_missing_extra_and_invalid_mip_data_are_rejected(self):
        self.assertEqual([m['bytes'] for m in etc2_mip_ranges(512, 512, 10, 349552)],
                         [262144, 65536, 16384, 4096, 1024, 256, 64, 16, 16, 16])
        for count, size in [(10, 349551), (10, 349553), (9, 349552), (11, 349552)]:
            with self.subTest(count=count, size=size), self.assertRaises(ValueError):
                etc2_mip_ranges(512, 512, count, size)
        with self.assertRaises(ValueError):
            etc2_mip_ranges(True, 512, 1, 262144)

    def test_fractional_integer_uniform_is_not_silently_truncated(self):
        changed = copy.deepcopy(self.material)
        floats = dict(changed['m_SavedProperties']['m_Floats'])
        floats['_Invert'] = 0.5
        changed['m_SavedProperties']['m_Floats'] = list(floats.items())
        with self.assertRaisesRegex(ValueError, 'integer uniform is fractional'):
            material_values(changed, self.manifest['program']['materialUniforms'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    ARGS = parser.parse_args()
    unittest.main(argv=['test_erlang_avatar_material.py'], verbosity=2)
