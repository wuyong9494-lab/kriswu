#!/usr/bin/env python3
"""Focused source readback and admission checks for the new D13 projection."""
import json
import os
from pathlib import Path
import struct
import unittest

from prepare_serpent_named_settings import (AnimationProjection, ARCHIVE_PIN, SCHEMA_PIN,
    SOURCES, encoded, pinned, recover, sha, typed)
from source_floorfall_audio import Storage


class SerpentNamedSettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = Path(os.environ['SERPENT_NAMED_INPUTS'])
        cls.schema = Path(os.environ['SERPENT_ANIMATION_SCHEMA']).read_bytes()
        cls.projection = AnimationProjection(cls.schema)
        cls.document = json.loads((cls.output/'serpent-shuangou-animation-named-v1.json').read_bytes())

    def test_actual_454_records_join_exact_original_rows(self):
        rows = self.document['records']
        self.assertEqual(len(rows), 454)
        keys = [(r['sourceEntry'], r['sourceRecordIndex']) for r in rows]
        self.assertEqual(len(set(keys)), 454)
        for entry, (size, digest, count) in SOURCES.items():
            raw = (self.output/'original-sources'/entry).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (size, digest))
            reader = Storage(raw)
            self.assertEqual(reader.pos, len(raw))
            original = reader.value(reader.root)
            self.assertEqual(len(original), count)
            selected = [r for r in rows if r['sourceEntry'] == entry]
            expected = list(range(52, 71)) if entry == 'settings_sets_dynasty.bytes' else list(range(count))
            self.assertEqual([r['sourceRecordIndex'] for r in selected], expected)
            for r in selected:
                self.assertEqual(r['sourceSHA256'], digest)
                self.assertEqual(typed(self.projection.unnamed(r['configuration'])),
                                 typed(original[r['sourceRecordIndex']]))
        self.assertTrue(self.document['sourceOnly'])
        self.assertFalse(self.document['runtimeBound'])
        self.assertFalse(self.document['defaultsApplied'])

    def test_actual_crops_and_nulls_are_not_replaced_by_d15_defaults(self):
        d13 = {r['sourceRecordIndex']: r['configuration'] for r in self.document['records']
               if r['sourceEntry'] == 'settings_sets_dynasty.bytes'}
        self.assertEqual(d13[68]['Animation'], 'D13_Bottle_Throw_Model')
        self.assertEqual((d13[68]['FirstFrame'], d13[68]['EndFrame']), (5, 30))
        self.assertEqual(d13[59]['EndFrame'], 5)
        self.assertIsNone(d13[55]['FirstFrame'])
        self.assertIsNone(d13[55]['EndFrame'])
        self.assertIsNone(d13[55]['MidFrames'])
        self.assertFalse(any(r['Animation'].startswith('D15_') for r in d13.values()))

    def test_wrong_schema_and_archive_fail_before_zip_or_output(self):
        with self.assertRaisesRegex(ValueError, 'native schema receipt identity'):
            AnimationProjection(self.schema + b' ')
        with self.assertRaisesRegex(ValueError, 'decoded archive identity'):
            recover(b'not a ZIP', self.schema)
        with self.assertRaisesRegex(ValueError, 'identity'):
            pinned(b'x' * ARCHIVE_PIN[0], ARCHIVE_PIN, 'decoded archive')

    def test_type_and_float_bits_survive_json_roundtrip(self):
        values = [None, True, 1, 1.0, -0.0, {'kind': 'Enum', 'value': 65537},
                  struct.unpack('<f', bytes.fromhex('cdcccc3d'))[0]]
        self.assertEqual(typed(values), typed(json.loads(encoded(values))))
        self.assertNotEqual(typed(True), typed(1))
        self.assertNotEqual(typed(1), typed(1.0))
        self.assertNotEqual(typed(0.0), typed(-0.0))
        with self.assertRaisesRegex(ValueError, 'field count'):
            self.projection.named([None] * 28)


if __name__ == '__main__':
    unittest.main()
