#!/usr/bin/env python3
"""Focused checks of new D13 original rules and literal-only collection input."""
import json
import os
from pathlib import Path
import unittest

from prepare_serpent_named_settings import encoded, sha, typed
from prepare_serpent_source_rules import (DEDICATED_LOCKS, LOCKS, SHARED_LOCKS, STYLE_LOCKS,
    Literal, original_levels, original_triggers, tree_paths)
from source_floorfall_audio import Storage, compact


class SerpentSourceRulesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['SERPENT_RULE_INPUTS'])
        cls.records = [json.loads((cls.root/f'serpent-lock-{lock}-source-v1.json').read_bytes()) for lock in LOCKS]

    def test_all_actual_trigger_fields_join_original_storage(self):
        triggers = 0
        for row in self.records:
            raw = (self.root/'original-sources'/row['sourceFile']).read_bytes()
            self.assertEqual((len(raw), sha(raw)), (row['sourceBytes'], row['sourceSHA256']))
            reader = Storage(raw)
            original = reader.value(reader.root)
            rebuilt = []
            for source_set in row['sets']:
                rebuilt_triggers = []
                for trigger in source_set['triggers']:
                    fields = trigger['rawSourceFields']
                    self.assertEqual(len(fields), 6)
                    self.assertEqual(compact(fields), trigger['rawCompactTriggerFields'])
                    self.assertEqual(compact(fields[3:]), [trigger[k] for k in ('events','conditions','actions')])
                    rebuilt_triggers.append(dict(kind='TriggerData', fields=fields))
                    triggers += 1
                rebuilt.append(dict(kind='TriggerSetData', fields=[source_set['sourceSetName'], rebuilt_triggers]))
            self.assertEqual(typed(original), typed(rebuilt))
            self.assertEqual(sha(encoded(typed(original))), row['sourceTypedValueSHA256'])
            self.assertTrue(row['sourceOnly'])
            self.assertFalse(row['runtimeBound'])
        self.assertEqual(triggers, 295)

    def test_actual_ancestor_gates_and_repeated_paths_are_preserved(self):
        reader = Storage((self.root/'original-sources/lockTree.bytes').read_bytes())
        paths = tree_paths(reader.value(reader.root))
        self.assertEqual(set(paths), set(LOCKS))
        for row in self.records:
            self.assertEqual(row['sourceTreePaths'], paths[row['sourceLock']])
        self.assertGreater(len(paths[1374]), 1)
        self.assertGreater(len(paths[1406]), 1)
        self.assertNotIn(1373, paths)  # Adjacent original lock belongs to D12.
        self.assertEqual((len(DEDICATED_LOCKS), len(STYLE_LOCKS), len(SHARED_LOCKS)), (35,12,4))

    def test_actual_levels_remain_unmerged_and_fake_values_uninterpreted(self):
        doc = json.loads((self.root/'serpent-original-levels-v1.json').read_bytes())
        levels = Literal(doc['sourceLiteral']).parse()
        self.assertEqual(levels, doc['levels'])
        self.assertEqual(list(levels), [str(i) for i in range(1, 9)])
        self.assertIn('D13_POISON_BOMB', levels['6']['specialAbility']['attributes'])
        self.assertEqual(levels['8']['specialAbility']['attributes']['D13_8_LEVEL']['Duration'], 600)
        self.assertNotIn('D13_DEFAULT_ABILITY', levels['6']['specialAbility']['attributes'])
        self.assertTrue(doc['levelsAreOriginalEntriesNotAccumulated'])
        self.assertTrue(doc['fakeValueFieldsAreNotInterpreted'])
        self.assertFalse(doc['javascriptExecuted'])

    def test_reject_expressions_duplicates_nonfinite_and_wrong_archives(self):
        for text in ('{x: f()}', '{x:1+2}', '{x:1,x:2}', '{x:1e999}', '{x:foo}', '{};run()'):
            with self.subTest(text=text), self.assertRaises(ValueError): Literal(text).parse()
        self.assertEqual(Literal('{1:{x:"brace } and quote \\"",y:[true,null,-.5]}}'.replace('-.5','-0.5')).parse(),
                         {'1': {'x': 'brace } and quote "', 'y': [True, None, -0.5]}})
        with self.assertRaisesRegex(ValueError, 'identity'): original_levels(b'not original')
        with self.assertRaisesRegex(ValueError, 'identity'): original_triggers(b'not original')


if __name__ == '__main__':
    unittest.main()
