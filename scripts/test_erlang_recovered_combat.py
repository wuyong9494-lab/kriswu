"""Focused checks on the new original-source common-combat contract.

ERLANG_RECOVERED_COMBAT_ROOT must contain the actual contract and 62-clip
candidate. These tests do not regenerate motions or rerun the 50-clip readback.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import unittest

from recover_erlang_combat_profile import (
    EXPECTED_THROW_CLOCKS, RECOVERED_CONTRACT_SHA, THROW_KEYS,
    checked, rounded, throw_policy, verify_trigger_semantics,
)


class RecoveredCombatChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = os.environ.get('ERLANG_RECOVERED_COMBAT_ROOT')
        if not root:
            raise unittest.SkipTest('Actual private recovered combat inputs were not supplied')
        root = Path(root)
        cls.contract = json.loads(checked(
            root/'common-combat-source-contract-v1/common-combat-source-contract.json',
            RECOVERED_CONTRACT_SHA, 300_000))
        cls.profile = json.loads(checked(
            root/'erlang-recovered-combat-body-v1/SF3_Erlang_Recovered_Combat_Profile.json',
            '88e46fab47dbaa2ce5dd280ccf13b13cde406aa6813cfa42735dca98542b861a', 32_000_000))
        cls.clips = {row['name']: row for row in cls.profile['clips']}

    def test_original_contract_and_actual_six_pairs(self):
        rules = throw_policy(self.profile, self.contract)
        self.assertEqual(rules, self.profile['ordinaryThrows'])
        self.assertEqual(verify_trigger_semantics(self.contract['triggers']),
                         self.contract['throwSemantics'])
        for key, expected in zip(THROW_KEYS, EXPECTED_THROW_CLOCKS):
            motion = rules['source']['motions'][key]
            self.assertEqual(tuple(motion[field] for field in (
                'lastSampleTick', 'animationEndTick', 'uninterruptEndTick')), expected)
        # The three source damage starts remain inside both original actors'
        # AnimationEnd windows; none is padded to the other actor's duration.
        for active, passive, tick in [('backActive', 'backPassive', 54),
                                      ('forwardActive', 'forwardPassive', 92),
                                      ('panguActive', 'panguPassive', 98)]:
            records = self.contract['records']
            source = records[THROW_KEYS.index(active)]['configuration']
            attack, = [row for row in source['Intervals'] if row['Type'] == 'Attack']
            self.assertEqual((attack['Start']-1)*2, tick)
            self.assertEqual(attack['Damage']['Attack'], 'UnarmedDamage')
            self.assertLess(tick, min(rules['source']['motions'][name]['animationEndTick']
                                      for name in (active, passive)))

    def test_changed_original_policy_contract_is_rejected(self):
        changed = copy.deepcopy(self.contract)
        changed['applicationAdapter']['millimetersPerSourceUnitNumerator'] = 100
        with self.assertRaisesRegex(ValueError, 'Wrong recovered common source contract'):
            throw_policy(self.profile, changed)
        changed = copy.deepcopy(self.contract['triggers'])
        lottery = next(row for row in changed if row['setName'] == 'THROW_Simultaneous_Random')
        lottery['trigger'][-1][0]['a171'][2]['f14'][1] = 100
        with self.assertRaisesRegex(ValueError, 'complementary simultaneous lottery'):
            verify_trigger_semantics(changed)

    def test_missing_pair_and_changed_source_clock_are_rejected(self):
        changed = dict(self.profile, roles=dict(self.profile['roles']))
        del changed['roles']['ordinaryThrownForward']
        with self.assertRaisesRegex(ValueError, 'Missing actual paired role'):
            throw_policy(changed, self.contract)
        changed = dict(self.profile, clips=list(self.profile['clips']))
        index = next(i for i, row in enumerate(changed['clips']) if row['name'] == 'throw_e')
        changed['clips'][index] = dict(changed['clips'][index], sourceEndEventTick=75)
        with self.assertRaisesRegex(ValueError, 'paired clocks differ'):
            throw_policy(changed, self.contract)

    def test_policy_uses_caller_fk_not_wu_positions(self):
        # An explicitly synthetic projection checks the portable interface.
        # It is not evidence that a second actor has been converted or accepted.
        changed = dict(self.profile, id='synthetic_projection', hero='synthetic_projection',
                       clips=list(self.profile['clips']))
        index = next(i for i, row in enumerate(changed['clips']) if row['name'] == 'throw_p')
        clip = copy.deepcopy(changed['clips'][index])
        clip['tracks']['root'][1][0] += .123
        clip['tracks']['footL'][0][0] += .234
        clip['tracks']['pelvis'][0][0] -= .321
        changed['clips'][index] = clip
        result = throw_policy(changed, self.contract)['source']['motions']['backActive']
        self.assertEqual(result['rootMillimeters'][1], rounded(clip['tracks']['root'][1][0]*1000))
        self.assertEqual(result['footLeftMillimeters'], rounded(clip['tracks']['footL'][0][0]*1000))
        self.assertEqual(result['pelvisMillimeters'], rounded(clip['tracks']['pelvis'][0][0]*1000))
        self.assertNotEqual(result, self.profile['ordinaryThrows']['source']['motions']['backActive'])

    def test_actual_reactions_keep_original_configuration_and_raw_identity(self):
        expected = [(31,60,52), (35,68,60), (31,60,52), (44,86,78), (61,120,112), (48,94,86)]
        for source, clocks in zip(self.contract['records'][6:], expected):
            clip = self.clips[source['motion']['name']]
            self.assertEqual(clip['sha256'], source['motion']['sha256'])
            self.assertEqual(clip['sourceConfiguration']['configuration'], source['configuration'])
            self.assertEqual(tuple(clip[k] for k in ('frames','playbackTicks','sourceEndEventTick')), clocks)
            self.assertEqual(len(clip['tracks']['head']), 2*clip['frames']-1)
        self.assertEqual((len(self.profile['clips']), len(self.profile['roles'])), (62,59))
        self.assertTrue(self.profile['recoveryBoundary']['completeBodyMotionSet'])
        self.assertFalse(self.profile['recoveryBoundary']['fullMatchProfile'])
        self.assertNotIn('erlangRules', self.profile)


if __name__ == '__main__':
    unittest.main()
