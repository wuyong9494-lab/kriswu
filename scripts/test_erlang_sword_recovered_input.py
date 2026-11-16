#!/usr/bin/env python3
"""Narrow checks for joining recovered held-sword inputs without changing old pins."""
import copy
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from prepare_erlang_model_tracks import model_inputs
import prepare_erlang_sword_holds as held


class RecoveredSwordInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get('ERLANG_RECOVERY_SOURCE')
        candidate = os.environ.get('ERLANG_MODEL_CANDIDATE')
        if not source or not candidate:
            raise unittest.SkipTest('Exact recovered private source/model inputs were not supplied')
        cls.source, cls.candidate = Path(source), Path(candidate)
        cls.proof = json.loads(cls.candidate.read_bytes())['inputRecovery']

    def test_explicit_format_cannot_mix_recovered_and_historical_proofs(self):
        with patch.object(held, 'checked') as read:
            for name, proof in (('historical', self.proof), ('recovered-v1', None), ('recovered', self.proof)):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    held.model_candidate_input(self.candidate, name, proof)
            read.assert_not_called()
        with self.assertRaisesRegex(ValueError, 'Source digest differs'):
            held.model_candidate_input(self.candidate)

    def test_actual_receipt_records_new_model_identity(self):
        document, receipt = held.model_candidate_input(self.candidate, 'recovered-v1', self.proof)
        self.assertEqual(receipt['sha256'], held.RECOVERED_CANDIDATE_SHA)
        self.assertEqual(receipt['bytes'], 666_196)
        self.assertNotEqual(receipt['sha256'], receipt['historicalModelCandidateSHA256'])
        self.assertFalse(receipt['historicalModelCandidateBytesRestored'])
        self.assertEqual(document['inputRecovery'], self.proof)

    def test_changed_candidate_and_original_motion_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / self.candidate.name
            path.write_bytes(self.candidate.read_bytes() + b'\n')
            with self.assertRaisesRegex(ValueError, 'Source digest differs'):
                held.model_candidate_input(path, 'recovered-v1', self.proof)
            path = Path(temporary) / 'd15_hovering_sword.original-private.bytes'
            raw = (self.candidate.parent / path.name).read_bytes()
            path.write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
            with self.assertRaisesRegex(ValueError, 'Source digest differs'):
                held.checked(path, held.MOTION_SHA, 7000)

    def test_complete_model_source_join_rejects_mixed_input_identity(self):
        changes = []
        value = copy.deepcopy(self.proof)
        value['sourceDecodedArchiveSHA256'] = '0' * 64
        changes.append(value)
        value = copy.deepcopy(self.proof)
        value['settings']['sha256'] = held.SETTINGS_SHA
        changes.append(value)
        value = copy.deepcopy(self.proof)
        value['ruleInputs'][-1]['source']['sha256'] = '0' * 64
        changes.append(value)
        value = copy.deepcopy(self.proof)
        value['completeOriginalTriggersVerified'] = 211.0
        changes.append(value)
        for index, value in enumerate(changes):
            with self.subTest(change=index), self.assertRaisesRegex(ValueError, 'input identities differ'):
                held.model_candidate_input(self.candidate, 'recovered-v1', value)

    def test_verified_rule_tuples_and_historical_size_limit_remain_separate(self):
        args = SimpleNamespace(input_format='recovered-v1',
            settings=self.source / 'recovered-erlang-named-animations-v1/erlang-animation-named-recovered-v1.json',
            rules=self.source / 'recovered-erlang-trigger-sources-v1',
            decoded_splits=self.source / 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip')
        _, rules, proof = model_inputs(args)
        self.assertEqual(proof, self.proof)
        for lock in [1440, *range(1441, 1448), 1449]:
            result = held.recovered_rule(rules, lock)
            self.assertEqual(result['lock'], lock)
            self.assertEqual(result['triggers'], rules[lock][2])
        self.assertEqual(len(rules[1449][1]), 116_621)
        value = dict(rules)
        path, raw, rows = value[1441]
        changed = json.loads(raw)
        changed['oldCompactSHA256'] = held.BIRTH_RULE_SHA[1442]
        value[1441] = path, json.dumps(changed).encode(), rows
        with self.assertRaisesRegex(ValueError, 'Historical sword rule identity'):
            held.recovered_rule(value, 1441)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'd15-lock-1449-compact-private.json').write_bytes(b' ' * 100_001)
            with self.assertRaisesRegex(ValueError, 'oversized local source'):
                held.rule(directory, 1449)


if __name__ == '__main__':
    unittest.main()
