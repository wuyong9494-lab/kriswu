#!/usr/bin/env python3
"""Private-input integrity checks for Xu Xiao's actual D20 source preparation."""
import copy
import json
import os
from pathlib import Path
import unittest

from prepare_xuxiao_founder_source import (
    ANIMATION_PINS, DEDICATED, GLOVES, HEAD_PIN, LOCKS, MODELS, SLOTS,
    AnimationProjection, Storage, animations, catalog_inventory, encoded,
    levels_and_equipment, lock_paths, sha, typed,
)


class XuXiaoFounderSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = os.environ.get('FIGHTER_XUXIAO_SOURCE_ROOT')
        if not root:
            raise unittest.SkipTest('Authenticated Xu Xiao D20 private source inputs are not staged')
        cls.root = Path(root)
        cls.receipt = cls.read('receipt-private.json')
        cls.levels = cls.read('xuxiao-original-equipment-levels-v1.json')
        cls.motion = cls.read('xuxiao-original-animation-inputs-v1.json')
        cls.triggers = cls.read('xuxiao-original-trigger-inputs-v1.json')
        cls.inventory = cls.read('xuxiao-required-resources-v1.json')

    @classmethod
    def read(cls, name):
        return json.loads((cls.root / name).read_text())

    def test_actual_written_products_retain_their_full_identity(self):
        for item in self.receipt['products']:
            raw = (self.root / item['file']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (item['bytes'], item['sha256']))
        self.assertEqual(self.receipt['personalHeadSHA256'], HEAD_PIN[1])
        self.assertFalse(self.receipt['headReprocessed'])
        self.assertFalse(self.receipt['personalHeadCopied'])

    def test_original_equipment_alternatives_and_levels_are_not_flattened(self):
        self.assertEqual(self.levels['equipmentSlots'], [list(slot) for slot in SLOTS])
        self.assertEqual([r['model'] for r in self.levels['equipment']], list(MODELS))
        self.assertEqual([r['slot'] for r in self.levels['equipment']], [0, 0, 1, 2, 3])
        self.assertEqual(list(self.levels['levels']), ['1', '2', '3', '4', '5', '6'])
        self.assertIn('ELEMENT_ARCHIVE', self.levels['levels']['2']['specialAbility']['attributes'])
        self.assertNotIn('ELEMENT_ARCHIVE', self.levels['levels']['3']['specialAbility']['attributes'])
        self.assertEqual(self.levels['levels']['6']['specialAbility']['attributes']['D20_6_LEVEL']['Cooldown'], 1.3)
        self.assertFalse(self.levels['fakeValueFieldsInterpreted'])

    def test_every_named_animation_reconstructs_original_values_and_types(self):
        projection = AnimationProjection((self.root / 'original-sources/animation-schema-private.json').read_bytes())
        source = {}
        for name, pin in ANIMATION_PINS.items():
            raw = (self.root / 'original-sources' / name).read_bytes()
            self.assertEqual((len(raw), sha(raw)), pin)
            reader = Storage(raw)
            source[name] = reader.value(reader.root)
        self.assertEqual(len(self.motion['records']), 58)
        for row in self.motion['records']:
            original = source[row['sourceEntry']][row['sourceRecordIndex']]
            restored = projection.unnamed(row['configuration'])
            self.assertEqual(typed(original), typed(restored))
            self.assertEqual(sha(encoded(typed(original))), row['originalTypedValueSHA256'])
        aliases = {r['configuration']['Animation']: r['configuration'] for r in self.motion['records']}
        self.assertEqual(aliases['Shadow_Imperial_Gloves']['FileName'], 'unique_moves/sets_D18/D18_upper.bin')
        self.assertEqual(aliases['D20_Missile']['FileName'], 'unique_moves/sets_h21/H21_black_hole_cast.bin')
        self.assertNotEqual(aliases['D20_Upper_Attack_Cast'], aliases['D20_Upper_Defense_Cast'])

    def test_original_trigger_order_all_six_fields_and_every_ancestor_survive(self):
        raw = (self.root / 'original-sources/lockTree.bytes').read_bytes()
        reader = Storage(raw)
        paths = lock_paths(reader.value(reader.root))
        self.assertEqual(sum(map(len, paths.values())), 107)
        self.assertEqual([r['sourceLock'] for r in self.triggers['records']], list(LOCKS))
        for row in self.triggers['records']:
            reader = Storage((self.root / 'original-sources' / row['sourceFile']).read_bytes())
            original = reader.value(reader.root)
            self.assertEqual(row['sourceTreePaths'], paths[row['sourceLock']])
            self.assertEqual(len(row['sets']), len(original))
            self.assertEqual(sha(encoded(typed(original))), row['originalTypedValueSHA256'])
            for index, source_set in enumerate(original):
                output = row['sets'][index]
                self.assertEqual(output['sourceSetName'], source_set['fields'][0])
                self.assertEqual(len(output['triggers']), len(source_set['fields'][1]))
                for trigger_index, trigger in enumerate(source_set['fields'][1]):
                    actual = output['triggers'][trigger_index]
                    self.assertEqual(actual['triggerIndex'], trigger_index)
                    self.assertEqual(typed(actual['rawSourceFields']), typed(trigger['fields']))
        self.assertEqual(len([r for r in self.triggers['records'] if r['sourceLock'] in DEDICATED]), 28)
        self.assertEqual(self.receipt['triggerRecords'], 407)

    def test_missing_source_media_never_becomes_an_activated_costume(self):
        self.assertEqual(self.inventory['missingEquipment'], list(MODELS))
        self.assertEqual(len(self.inventory['motions']), 48)
        self.assertEqual(len(self.inventory['missingMotionFiles']), 37)
        matched = [r for r in self.inventory['motions'] if r['sourceBundles']]
        self.assertEqual(len(matched), 11)
        self.assertTrue(self.inventory['catalogMatchesAreNotPhysicalByteVerification'])
        for document in [self.receipt, self.levels, self.motion, self.triggers, self.inventory]:
            self.assertTrue(document['sourceOnly'])
            for key in ('runtimeBound', 'productionActivated', 'nativeAcceptance', 'deviceAcceptance', 'testFlightUploaded'):
                self.assertFalse(document[key])

    def test_changed_archive_or_missing_original_gate_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'identity differs'):
            levels_and_equipment(b'not the source archive')
        with self.assertRaisesRegex(ValueError, 'identity differs'):
            animations(b'changed splits', b'changed schema')
        with self.assertRaisesRegex(ValueError, 'identity differs'):
            catalog_inventory(b'{}\n', [], [])
        reader = Storage((self.root / 'original-sources/lockTree.bytes').read_bytes())
        tree = copy.deepcopy(reader.value(reader.root))
        def remove(node):
            if node['fields'][2] == 'lock_1572.bytes':
                node['fields'][2] = None
            for child in node['fields'][0] or []:
                remove(child)
        remove(tree)
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            lock_paths(tree)


if __name__ == '__main__':
    unittest.main()
