#!/usr/bin/env python3
"""Only the explicitly recovered D15 input identity and lossless joins."""
import copy
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import prepare_erlang_model_tracks as model


class ErlangModelRecoveredInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get('ERLANG_RECOVERY_SOURCE')
        if not source:
            raise unittest.SkipTest('Exact recovered private source inputs were not supplied')
        cls.source = Path(source)
        cls.settings = cls.source / 'recovered-erlang-named-animations-v1/erlang-animation-named-recovered-v1.json'
        cls.rules = cls.source / 'recovered-erlang-trigger-sources-v1'
        cls.splits = cls.source / 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip'

    def args(self, **changes):
        values = dict(settings=self.settings, rules=self.rules, decoded_splits=self.splits,
                      input_format='recovered-v1')
        values.update(changes)
        return SimpleNamespace(**values)

    def test_historical_default_keeps_its_complete_pin(self):
        args = self.args()
        del args.input_format
        with self.assertRaisesRegex(ValueError, 'Source digest differs'):
            model.model_inputs(args)

    def test_unknown_format_or_missing_original_archive_fails_before_reads(self):
        with patch.object(model, 'checked') as read:
            for args in (self.args(input_format='recovered'), self.args(decoded_splits=None)):
                with self.subTest(args=args), self.assertRaises(ValueError):
                    model.model_inputs(args)
            read.assert_not_called()

    def test_changed_named_bytes_are_not_an_accepted_recovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / self.settings.name
            path.write_bytes(self.settings.read_bytes() + b'\n')
            with self.assertRaisesRegex(ValueError, 'Source digest differs'):
                model.model_inputs(self.args(settings=path))

    def test_complete_original_inputs_and_existing_semantic_gates(self):
        settings, rules, proof = model.model_inputs(self.args())
        self.assertEqual(len(settings['records']), 45)
        self.assertEqual((len(rules), proof['completeOriginalTriggersVerified']), (18, 211))
        self.assertFalse(proof['historicalNamedSettingsBytesRestored'])
        self.assertFalse(proof['historicalCompactBytesRestored'])
        for record, _, _, kind, alias, _, _, _, _, lock in model.DEFINITIONS:
            with self.subTest(record=record):
                delete, receipt = model.source_rules(self.args(), lock, alias,
                    dict(animationEndTick=92 if record == 118 else 0), record, rules)
                self.assertEqual(delete, 70 if record == 118 else None)
                self.assertNotEqual(receipt['sha256'], model.RULE_SHA[lock])
                creation = model.source_creation(self.args(), record, model.MODELS[kind]['model'], rules)
                self.assertEqual([r['triggerIndex'] for r in creation['creationTriggers']],
                                 model.CREATION[record][1])

    def test_unused_trigger_fields_types_and_set_identity_are_not_discarded(self):
        receipt = json.loads((self.rules / 'receipt-private.json').read_bytes())
        pin = next(p for p in receipt['files'] if p['lock'] == 1435)
        raw = (self.rules / pin['source']['file']).read_bytes()
        document = json.loads((self.rules / pin['projection']['file']).read_bytes())
        changes = []
        value = copy.deepcopy(document)
        value['sets'][0]['triggers'][0]['rawCompactTriggerFields'][0][0] = False
        changes.append(value)
        value = copy.deepcopy(document)
        value['sets'][0]['triggers'][0]['priority'] = 0
        changes.append(value)
        value = copy.deepcopy(document)
        value['sets'][0]['sourceSetIndex'] = False
        changes.append(value)
        value = copy.deepcopy(document)
        value['sets'][0]['sourceSetName'] += '_other'
        changes.append(value)
        value = copy.deepcopy(document)
        value['sets'][0]['triggers'][1]['rawCompactTriggerFields'].pop()
        changes.append(value)
        value = copy.deepcopy(document)
        value['sets'][0]['triggers'][1]['actions'] = []
        changes.append(value)
        for number, value in enumerate(changes):
            with self.subTest(change=number), self.assertRaisesRegex(ValueError, 'field or type'):
                model.recovered_rule_rows(raw, value, 1435, pin)

    def test_named_configuration_preserves_every_field_and_numeric_type(self):
        document = json.loads(self.settings.read_bytes())
        receipt = json.loads((self.settings.parent / 'receipt-private.json').read_bytes())
        fields = receipt['projectionFields']
        configuration = document['records'][0]['configuration']
        original = model.unnamed_configuration(configuration, fields)
        value = copy.deepcopy(configuration)
        value['Looped'] = 1  # Original is bool True; Python's ordinary equality would accept 1.
        self.assertFalse(model.same_source_value(original, model.unnamed_configuration(value, fields)))
        value = copy.deepcopy(configuration)
        value['Align'][0][0] = -0.0
        self.assertFalse(model.same_source_value(original, model.unnamed_configuration(value, fields)))
        for extra in (False, True):
            value = copy.deepcopy(configuration)
            if extra:
                value['inventedField'] = None
            else:
                del value['IgnoreWeaponMirroring']
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'missing or extra fields'):
                model.unnamed_configuration(value, fields)


if __name__ == '__main__':
    unittest.main()
