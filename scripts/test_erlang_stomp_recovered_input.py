#!/usr/bin/env python3
"""Scoped recovery-identity checks and one readback of the actual original assets."""
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import warnings

import prepare_erlang_stomp_effect as stomp
import test_erlang_stomp_effect as original_checks


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


class RecoveredStompChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        values = [os.environ.get(n) for n in (
            'ERLANG_RECOVERY_SOURCE', 'ERLANG_MODEL_CANDIDATE', 'ERLANG_STOMP_CANDIDATE')]
        if not all(values):
            raise unittest.SkipTest('Exact recovered private sources and source-only output were not supplied')
        cls.source, cls.model_path, cls.output = map(Path, values)
        cls.document = json.loads(gzip.decompress((cls.output / (stomp.SOURCE_ONLY_NAME + '.gz')).read_bytes()))
        cls.receipt = json.loads((cls.output / 'd15-stomp-effect-receipt-private.json').read_bytes())
        cls.args = SimpleNamespace(input_format='recovered-v1', profile=None, material_sources=None,
            model_tracks=cls.model_path,
            settings=cls.source / 'recovered-erlang-named-animations-v1/erlang-animation-named-recovered-v1.json',
            rules=cls.source / 'recovered-erlang-trigger-sources-v1',
            decoded_splits=cls.source / 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip',
            texture_bundle=cls.source / 'recovered-source-bundles' / stomp.TEXTURE_BUNDLE[0])

    def test_source_only_rejects_profile_or_material_metadata_bypass_before_read(self):
        changes = ({'profile': Path('not-a-restored-profile.json')},
                   {'material_sources': Path('unchecked-materials')},
                   {'decoded_splits': None}, {'input_format': 'recovered'},
                   {'input_format': 'historical', 'profile': Path('real-profile.json')})
        with patch.object(stomp, 'model_inputs') as read:
            for fields in changes:
                args = copy.copy(self.args)
                vars(args).update(fields)
                with self.subTest(fields=fields), self.assertRaises(ValueError):
                    stomp.recovered_inputs(args)
            read.assert_not_called()

    def test_exact_new_candidate_and_complete_typed_source_join(self):
        settings, rules, proof = stomp.model_inputs(self.args)
        with patch.object(stomp, 'model_inputs', return_value=(settings, rules, proof)):
            result = stomp.recovered_inputs(self.args)
        self.assertEqual(result['sourceCandidateReceipt']['sha256'], stomp.RECOVERED_MODEL_SHA)
        self.assertEqual(result['sourceCandidateReceipt']['bytes'], 666_196)
        self.assertFalse(result['sourceCandidateReceipt']['historicalBytesRestored'])
        self.assertEqual(result['rules'], rules[1434][2])
        changes = []
        altered = copy.deepcopy(proof)
        altered['sourceDecodedArchiveSHA256'] = '0' * 64
        changes.append(altered)
        altered = copy.deepcopy(proof)
        altered['completeOriginalTriggersVerified'] = 211.0
        changes.append(altered)
        for altered in changes:
            with patch.object(stomp, 'model_inputs', return_value=(settings, rules, altered)):
                with self.assertRaisesRegex(ValueError, 'complete source identities differ'):
                    stomp.recovered_inputs(self.args)
        with tempfile.TemporaryDirectory() as temporary:
            p = Path(temporary) / self.model_path.name
            p.write_bytes(self.model_path.read_bytes() + b'\n')
            args = copy.copy(self.args); args.model_tracks = p
            with patch.object(stomp, 'model_inputs', return_value=(settings, rules, proof)):
                with self.assertRaises(ValueError):
                    stomp.recovered_inputs(args)
        with self.assertRaisesRegex(ValueError, 'Source digest differs'):
            stomp.checked(self.model_path, stomp.MODEL_SHA, 700_000)

    def test_changed_texture_cab_bytes_stream_or_mip_type_are_rejected(self):
        record = self.receipt['sourceAssetInputs']['textures'][0]
        raw, stream = Path(record['rawFile']).read_bytes(), Path(record['textureFile']).read_bytes()
        metadata = json.loads(Path(record['metadataFile']).read_bytes())
        pin = stomp.TEXTURES[int(record['pathID'])]
        mips = stomp.checked_texture(raw, metadata, stream, record['externalCAB'], pin)
        self.assertEqual(mips, record['fullMipChain'])
        wrong_type = copy.deepcopy(metadata); wrong_type['m_MipCount'] = 10.0
        cases = [(raw, metadata, stream, 'CAB-unrelated'),
                 (bytes([raw[0] ^ 1]) + raw[1:], metadata, stream, record['externalCAB']),
                 (raw, wrong_type, stream, record['externalCAB']),
                 (raw, metadata, stream[:-1], record['externalCAB']),
                 (raw, metadata, stream[:-1] + bytes([stream[-1] ^ 1]), record['externalCAB'])]
        for case in cases:
            with self.subTest(case=(len(case[0]), len(case[2]), case[3])), self.assertRaises(ValueError):
                stomp.checked_texture(*case, pin)

    def test_independent_schema_and_filename_do_not_assert_runtime_binding(self):
        self.assertEqual(self.document['schema'], stomp.SOURCE_ONLY_SCHEMA)
        self.assertTrue(self.document['sourceOnly'])
        self.assertFalse(self.document['runtimeBound'])
        self.assertFalse(self.receipt['runtimeBound'])
        self.assertFalse(self.receipt['historicalRuntimeManifestBytesRestored'])
        for key in ('version', 'profileID', 'profileSHA256', 'characterSHA256', 'erlangModelBindings'):
            self.assertNotIn(key, self.document)
            self.assertNotIn(key, self.receipt)
        self.assertFalse((self.output / 'SF3_D15_StompEffects.json.gz').exists())
        self.assertEqual(set(self.document['sourceModels']), {stomp.ROLE})
        self.assertEqual(self.receipt['sourceCandidateReceipt'], self.document['sourceCandidateReceipt'])

    def test_actual_original_mesh_programs_textures_and_all_mips_read_back(self):
        import UnityPy
        warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        bundles = self.source / 'recovered-source-bundles'
        raw = (bundles / stomp.BUNDLE[0]).read_bytes()
        self.assertEqual(sha(raw), stomp.BUNDLE[1])
        self.objects = {o.path_id: o for o in UnityPy.load(raw).objects}
        shader_raw = (bundles / 'b77cd85962dab26b5e542811e8599be3.bin').read_bytes()
        self.assertEqual(sha(shader_raw), 'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972')
        self.shaders = {o.path_id: o for o in UnityPy.load(shader_raw).objects if o.type.name == 'Shader'}
        self.bindings = json.loads((self.output / 'material-source-private/d15-shader-material-bindings-private.json').read_bytes())
        # Reuse only the two independent original-data comparisons. Do not run
        # the old profile binder, regenerate materials, or execute native code.
        with patch.object(original_checks, 'ARGS', SimpleNamespace(candidate=self.output)):
            original_checks.ActualLegChecks.test_original_mesh_emitters_and_full_lifetime(self)
            original_checks.ActualLegChecks.test_original_shader_expressions_and_integer_uniform(self)
        texture_raw = (bundles / stomp.TEXTURE_BUNDLE[0]).read_bytes()
        self.assertEqual((len(texture_raw), sha(texture_raw)), stomp.TEXTURE_BUNDLE[1:])
        external = {o.path_id: o for o in UnityPy.load(texture_raw).objects}
        for record in self.receipt['sourceAssetInputs']['textures']:
            path_id = int(record['pathID'])
            obj = (self.objects if path_id in self.objects else external)[path_id]
            self.assertEqual(obj.assets_file.name, record['externalCAB'])
            self.assertEqual(obj.get_raw_data(), Path(record['rawFile']).read_bytes())
            def restore_bytes(value):
                return (bytes.fromhex(value['__unity_bytes_hex__'])
                        if set(value) == {'__unity_bytes_hex__'} else value)
            self.assertEqual(obj.read_typetree(), json.loads(Path(record['metadataFile']).read_bytes(),
                                                           object_hook=restore_bytes))
            original = bytes(obj.read().get_image_data())
            self.assertEqual(original, Path(record['textureFile']).read_bytes())
            data = next(f for f in self.document['files'] if f['sha256'] == sha(original))
            self.assertEqual(original, (self.output / data['name']).read_bytes())
            offset = 0
            for level, mip in enumerate(record['fullMipChain']):
                dimension = max(1, 512 >> level)
                size = ((dimension + 3) // 4) ** 2 * 16
                self.assertEqual((mip['level'], mip['width'], mip['height'], mip['offset'], mip['bytes']),
                                 (level, dimension, dimension, offset, size))
                self.assertEqual(mip['sha256'], sha(original[offset:offset + size]))
                offset += size
            self.assertEqual((len(record['fullMipChain']), offset), (10, len(original)))


if __name__ == '__main__':
    unittest.main()
