#!/usr/bin/env python3
"""New identity-boundary and actual source readback checks for recovered Sword FX."""
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

import prepare_erlang_sword_effect as sword
import erlang_sword_materials as material_source
import test_erlang_sword_effect as original_checks


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


class RecoveredSwordSourceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        names = ('ERLANG_RECOVERY_SOURCE', 'ERLANG_MODEL_CANDIDATE',
                 'ERLANG_HELD_CANDIDATE', 'ERLANG_SWORD_SOURCE_CANDIDATE')
        values = [os.environ.get(name) for name in names]
        if not all(values):
            raise unittest.SkipTest('Exact private source and recovered output paths were not supplied')
        cls.source, cls.model, cls.held, cls.output = map(Path, values)
        cls.document = json.loads(gzip.decompress((cls.output / (sword.SOURCE_ONLY_NAME + '.gz')).read_bytes()))
        cls.receipt = json.loads((cls.output / 'd15-sword-effect-receipt-private.json').read_bytes())
        cls.args = SimpleNamespace(input_format='recovered-v1', profile=None, cached_materials=None,
            extra_textures=None, trail_textures=None, material_sources=None,
            model_tracks=cls.model, held_tracks=cls.held,
            settings=cls.source / 'recovered-erlang-named-animations-v1/erlang-animation-named-recovered-v1.json',
            rules=cls.source / 'recovered-erlang-trigger-sources-v1',
            decoded_splits=cls.source / 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip')

    def test_source_only_and_historical_input_identities_cannot_be_mixed(self):
        with patch.object(sword, 'model_inputs') as read:
            for key in ('profile', 'cached_materials', 'extra_textures', 'trail_textures', 'material_sources'):
                args = copy.copy(self.args); setattr(args, key, Path('unverified'))
                with self.subTest(key=key), self.assertRaises(ValueError):
                    sword.recovered_inputs(args)
            args = copy.copy(self.args); args.input_format = 'historical'
            with self.assertRaises(ValueError):
                sword.recovered_inputs(args)
            args = copy.copy(self.args); args.decoded_splits = None
            with self.assertRaises(ValueError):
                sword.recovered_inputs(args)
            read.assert_not_called()
        unused = Path('unused')
        with self.assertRaisesRegex(ValueError, 'cannot be mixed'):
            material_source.prepare_materials(unused, unused, unused, unused, unused, input_format='recovered-v1')
        with self.assertRaisesRegex(ValueError, 'cannot be mixed'):
            material_source.prepare_materials(unused, unused, unused, None, unused)

    def test_exact_model_held_and_all_typed_original_inputs_join(self):
        settings, rules, proof = sword.model_inputs(self.args)
        with patch.object(sword, 'model_inputs', return_value=(settings, rules, proof)):
            result = sword.recovered_inputs(self.args)
        self.assertEqual(result['sourceHeldReceipt']['sha256'], sword.RECOVERED_HELD_SHA)
        self.assertEqual(result['sourceHeldReceipt']['bytes'], 935_704)
        self.assertFalse(result['sourceHeldReceipt']['historicalHeldBytesRestored'])
        self.assertEqual(result['sourceModelReceipt'], result['held']['sourceCandidateReceipt'])
        altered = copy.deepcopy(proof); altered['completeOriginalTriggersVerified'] = 211.0
        with patch.object(sword, 'model_inputs', return_value=(settings, rules, altered)):
            with self.assertRaisesRegex(ValueError, 'input identities differ'):
                sword.recovered_inputs(self.args)
        with tempfile.TemporaryDirectory() as temporary:
            for key, original in (('model_tracks', self.model), ('held_tracks', self.held)):
                path = Path(temporary) / original.name
                path.write_bytes(original.read_bytes() + b'\n')
                args = copy.copy(self.args); setattr(args, key, path)
                with patch.object(sword, 'model_inputs', return_value=(settings, rules, proof)):
                    with self.subTest(key=key), self.assertRaises(ValueError):
                        sword.recovered_inputs(args)
        trigger = next(t for t in result['rules'][1447][2] if t['triggerIndex'] == 1)
        self.assertEqual(sword.source_lifecycle(self.args.rules, trigger, result['rules']), self.receipt['sourceLifecycle'])

    def test_texture_cab_raw_stream_mip_type_and_material_pointer_negatives(self):
        record = self.receipt['sourceAssetInputs']['textures'][0]
        raw, stream = Path(record['rawFile']).read_bytes(), Path(record['textureFile']).read_bytes()
        metadata = json.loads(Path(record['metadataFile']).read_bytes())
        pin = material_source.RECOVERED_TEXTURES[int(record['pathID'])]
        self.assertEqual(material_source.verified_texture_mips(raw, metadata, stream, record['externalCAB'], pin),
                         record['fullMipChain'])
        bad_type = copy.deepcopy(metadata); bad_type['m_MipCount'] = float(metadata['m_MipCount'])
        cases = [(raw, metadata, stream, 'CAB-wrong'),
                 (raw[:-1] + bytes([raw[-1] ^ 1]), metadata, stream, record['externalCAB']),
                 (raw, bad_type, stream, record['externalCAB']),
                 (raw, metadata, stream[:-1], record['externalCAB']),
                 (raw, metadata, stream[:-1] + bytes([stream[-1] ^ 1]), record['externalCAB'])]
        for args in cases:
            with self.assertRaises(ValueError):
                material_source.verified_texture_mips(*args, pin)
        cab = SimpleNamespace(name='CAB-f84b4be63f25036ecac28811c8604c97', externals=[
            SimpleNamespace(path='CAB-c8d89ff307ad393b5cf0982a245a196c'),
            SimpleNamespace(path=record['externalCAB'])])
        material = {'m_Shader': {'m_FileID': 1, 'm_PathID': 7099477430120726890},
            'm_SavedProperties': {'m_TexEnvs': [['_MainTex', {'m_Texture': {'m_FileID': 2, 'm_PathID': int(record['pathID'])}}]]}}
        material_source.verify_recovered_material_pointers(material, cab)
        material['m_SavedProperties']['m_TexEnvs'][0][1]['m_Texture']['m_FileID'] = 1
        with self.assertRaisesRegex(ValueError, 'PPtr CAB or identity'):
            material_source.verify_recovered_material_pointers(material, cab)

    def test_source_only_scope_poses_and_absent_runtime_binding(self):
        self.assertEqual(self.document['schema'], sword.SOURCE_ONLY_SCHEMA)
        self.assertTrue(self.document['sourceOnly']); self.assertFalse(self.document['runtimeBound'])
        for key in ('version', 'profileID', 'profileSHA256', 'characterSHA256', 'erlangSwordBinding', 'erlangSwordModels'):
            self.assertNotIn(key, self.document); self.assertNotIn(key, self.receipt)
        self.assertFalse((self.output / 'SF3_D15_SwordEffects.json.gz').exists())
        self.assertFalse(self.receipt['historicalRuntimeManifestBytesRestored'])
        self.assertFalse(self.document['sourceScope']['completePrefab'])
        held, model = json.loads(self.held.read_bytes()), json.loads(self.model.read_bytes())
        originals = held['models'] + [m for m in model['models'] if m['role'] == 'erlangSummon_sword']
        self.assertEqual(len(originals), len(self.document['sourceModels']))
        for row in originals:
            actual = self.document['sourceModels'][row['role']]
            self.assertEqual(actual['root'], row['bones']['magic_joint_root'])
            self.assertEqual(actual['sourceRecordIndex'], row['sourceRecordIndex'])
        rotate = self.document['sourceModels']['erlangSummon_swordRotate']
        self.assertEqual((rotate['frames'], rotate['lastTick'], len(rotate['root']), rotate['track']), (1, 0, 1, None))

    def test_actual_original_mesh_emitters_and_trail_semantics_read_back(self):
        import UnityPy
        warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        raw = (self.source / 'recovered-source-bundles' / sword.BUNDLE[0]).read_bytes()
        self.assertEqual(sha(raw), sword.BUNDLE[1])
        self.environment = UnityPy.load(raw)
        self.objects = {o.path_id: o for o in self.environment.objects}
        # Rename only this source-scope view for the existing independent raw
        # comparisons. No profile, owner or runtime binding is supplied.
        view = dict(self.document, erlangSwordScope=self.document['sourceScope'])
        with patch.object(self, 'document', view):
            original_checks.ActualSwordChecks.test_original_mesh_topology_and_explicit_partial_scope(self)
            original_checks.ActualSwordChecks.test_nine_new_emitters_keep_original_module_identity_and_particle_clocks(self)
            original_checks.ActualSwordChecks.test_two_trails_keep_source_heads_lifetimes_materials_and_gradient_keys(self)

    def test_actual_material_programs_and_fourteen_complete_texture_streams_read_back(self):
        import UnityPy
        from UnityPy.helpers import TypeTreeHelper
        from UnityPy.streams import EndianBinaryReader
        UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
        bundles = self.source / 'recovered-source-bundles'
        objects = {}
        for key, (name, length, digest) in material_source.RECOVERED_TEXTURE_BUNDLES.items():
            raw = (bundles / name).read_bytes(); self.assertEqual((len(raw), sha(raw)), (length, digest))
            objects[key] = {o.path_id: o for o in UnityPy.load(raw).objects}
        template = next(o for o in objects['local'].values() if o.type.name == 'Material')
        directory = self.output / 'material-source-private'
        binding = json.loads((directory / 'd15-sword-shader-bindings-private.json').read_bytes())
        self.assertNotIn('cachedInputReceiptSHA256', binding)
        self.assertFalse(binding['inputRecovery']['historicalCachedReceiptBytesRestored'])
        self.assertEqual({int(m['sourcePathID']) for m in binding['materials']}, set(material_source.MATERIALS))
        for item in binding['materials']:
            raw = (directory / (item['sourcePathID'] + '.raw')).read_bytes()
            self.assertEqual(sha(raw), material_source.MATERIALS[int(item['sourcePathID'])][1])
            original = TypeTreeHelper.read_typetree(template.serialized_type.node,
                EndianBinaryReader(raw, endian=template.reader.endian), byte_size=len(raw), as_dict=True)
            self.assertEqual(json.loads(json.dumps(original)), json.loads(Path(item['metadataFile']).read_bytes()))
            self.assertEqual(set(original['m_ValidKeywords']), set(item['exactMatches'][0]['keywords']))
            self.assertEqual(original['m_InvalidKeywords'], item['invalidKeywords'])
        with patch.object(original_checks, 'ARGS', SimpleNamespace(candidate=self.output, materials=directory), create=True):
            original_checks.ActualSwordChecks.test_shader_body_arithmetic_is_preserved_for_new_sword_variants(self)
        for entry in self.document['files']:
            raw = (self.output / entry['name']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (entry['bytes'], entry['sha256']))
        textures = self.receipt['sourceAssetInputs']['textures']
        self.assertEqual(len(textures), 14)
        mip_count = 0
        for record in textures:
            pid = int(record['pathID']); pin = material_source.RECOVERED_TEXTURES[pid]
            obj = objects[pin['bundle']][pid]
            self.assertEqual(obj.assets_file.name, record['externalCAB'])
            self.assertEqual(obj.get_raw_data(), Path(record['rawFile']).read_bytes())
            def restore_bytes(value):
                return bytes.fromhex(value['__unity_bytes_hex__']) if set(value) == {'__unity_bytes_hex__'} else value
            self.assertEqual(obj.read_typetree(), json.loads(Path(record['metadataFile']).read_bytes(), object_hook=restore_bytes))
            original = bytes(obj.read().get_image_data())
            self.assertEqual(original, Path(record['textureFile']).read_bytes())
            file = next(row for row in self.document['files'] if row['sha256'] == sha(original))
            self.assertEqual(original, (self.output / file['name']).read_bytes())
            offset = 0
            for level, mip in enumerate(record['fullMipChain']):
                width, height = max(1, pin['width'] >> level), max(1, pin['height'] >> level)
                size = ((width+3)//4) * ((height+3)//4) * (8 if pin['format'] == 45 else 16)
                self.assertEqual((mip['level'], mip['width'], mip['height'], mip['offset'], mip['bytes']),
                                 (level, width, height, offset, size))
                self.assertEqual(mip['sha256'], sha(original[offset:offset+size])); offset += size
            self.assertEqual(offset, len(original)); mip_count += len(record['fullMipChain'])
        self.assertEqual(mip_count, 108)


if __name__ == '__main__':
    unittest.main()
