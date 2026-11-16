"""Focused regression checks using the actual recovered D13 and D15 outputs."""
from __future__ import annotations
import copy
import json
import os
from pathlib import Path
import unittest

from extend_erlang_model_runtime_rules import append_held_swords
from recover_erlang_runtime_profile import INPUTS, checked, join, validate_bindings
from recover_erlang_combat_profile import RECOVERED_CONTRACT_SHA, throw_policy
from bind_serpent_physical_combat import LOCKS, bind, combo_bindings
from prepare_serpent_animated_body import NAMED_SHA


class RecoveredFighterBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = os.environ.get('FIGHTER_RECOVERY_ROOT')
        products = os.environ.get('FIGHTER_RECOVERED_PROFILE_ROOT')
        if not root or not products:
            raise unittest.SkipTest('Actual recovered private inputs were not supplied')
        cls.root, cls.products = Path(root), Path(products)
        cls.inputs = {key: json.loads(checked(cls.root/path, digest, maximum))
                      for key, (path, digest, maximum) in INPUTS.items()}
        cls.wu = json.loads((cls.products/'erlang-runtime-v3/SF3_Erlang_Recovered_Runtime_Profile.json').read_bytes())
        cls.liu = json.loads((cls.products/'serpent-combat-v1/SF3_Serpent_Recovered_Combat_Profile.json').read_bytes())

    def test_bound_runtime_preserves_original_actor_and_paired_data(self):
        expected, evidence = join(*(self.inputs[k] for k in ('body','named','hound','models','held')))
        self.assertEqual(expected, self.wu)
        self.assertEqual(self.wu['clips'], self.inputs['body']['clips'])
        self.assertEqual(self.wu['ordinaryThrows'], self.inputs['body']['ordinaryThrows'])
        self.assertEqual(len(self.wu['summonTracks']), 15)
        self.assertEqual(len(evidence['models']['dynamicEvents']), 2)

    def test_missing_capsule_and_late_release_are_rejected(self):
        broken = copy.deepcopy(self.wu)
        broken['erlangRules']['attacks'][0]['parts'] = ['invented_contact']
        with self.assertRaisesRegex(ValueError, 'geometry is not bound'):
            validate_bindings(broken)
        broken = copy.deepcopy(self.wu)
        broken['erlangRules']['releases'][0]['atTick'] = 36_000
        with self.assertRaisesRegex(ValueError, 'Release follows body end'):
            validate_bindings(broken)

    def test_launched_sword_lifetime_is_not_the_held_sword_lifetime(self):
        tracks = {t['role']: t for t in self.wu['summonTracks']}
        self.assertEqual(tracks['erlangSummon_sword']['sourceDeleteEventTick'], 70)
        for slot in range(1, 7):
            self.assertIsNone(tracks[f'erlangSummon_swordBirth{slot}'].get('sourceDeleteEventTick'))
        broken = copy.deepcopy(self.wu)
        sword = next(a for a in broken['erlangRules']['attacks'] if a['modelRole'] == 'erlangSummon_sword')
        sword['endTick'] = 71
        with self.assertRaisesRegex(ValueError, 'exceeds source lifetime'):
            validate_bindings(broken)

    def test_changed_held_candidate_cannot_be_joined(self):
        changed = copy.deepcopy(self.inputs['held'])
        changed['models'][0]['origin']['sourceShiftCentimeters'][0] += 1
        with self.assertRaisesRegex(ValueError, 'held source identity differs'):
            append_held_swords({}, {}, changed, recovered=True)

    def test_serpent_pairing_uses_original_hooks_and_reaction_clocks(self):
        contract = json.loads(checked(self.root/'continued-20261116/common-combat-source-contract-v1/common-combat-source-contract.json',
                                      RECOVERED_CONTRACT_SHA, 300_000))
        self.assertEqual(throw_policy(self.liu, contract), self.liu['ordinaryThrows'])
        clips = {c['name']: c for c in self.liu['clips']}
        for name, end in [('h_stun_start', 52), ('h_stun_loop', 60), ('h_stun_end', 52),
                          ('h17_root_spike_passive_start', 78), ('h17_root_spike_passive_loop', 112),
                          ('h17_root_spike_passive_end', 86)]:
            self.assertEqual(clips[name]['sourceEndEventTick'], end)
            self.assertEqual(len(clips[name]['tracks']['collisionEdges']), 4)
        receipt = json.loads((self.products/'serpent-combat-v1/combat-body-receipt-private.json').read_bytes())
        self.assertEqual(receipt['comparedValues'], 69760)
        self.assertLess(receipt['maximumErrorMeters'], 2e-6)
        self.assertTrue(receipt['unchangedGeometryMaterialsSkinsAndPersonalPortrait'])

    def serpent_inputs(self):
        root = self.root/'continued-20261116'
        named = json.loads(checked(root/'serpent-named-settings-v1/serpent-shuangou-animation-named-v1.json',
                                   NAMED_SHA, 2_000_000))
        locks = {lock: json.loads(checked(root/f'serpent-trigger-source-v1/serpent-lock-{lock}-source-v1.json',
                                         pins[0], 2_000_000)) for lock, pins in LOCKS.items()}
        return named, locks

    def test_serpent_physical_bindings_preserve_all_source_poses_and_damage_boundaries(self):
        named, locks = self.serpent_inputs()
        profile, evidence = bind(self.liu, named, locks)
        actual = json.loads((self.products/'serpent-physical-v1/SF3_Serpent_Physical_Combat_Profile.json').read_bytes())
        self.assertEqual(profile, actual)
        self.assertEqual(profile['clips'], self.liu['clips'])
        self.assertEqual(profile['ordinaryThrows'], self.liu['ordinaryThrows'])
        self.assertEqual([l['sourceFrame'] for l in profile['comboLinks']], [14,24,33,45,21,22,41,62])
        self.assertEqual(len(evidence['contacts']), 48)
        self.assertEqual(profile['combatRules']['basis'], 'applicationAdaptation')
        self.assertEqual(set(evidence['withheldGenericSkillRoles']), {'shadow','ranged'})
        self.assertFalse(profile['recoveryBoundary']['abilityRulesBound'])

    def test_serpent_nonzero_destination_shift_is_not_silently_treated_as_zero(self):
        _, locks = self.serpent_inputs()
        body = copy.deepcopy(self.liu)
        clip = next(c for c in body['clips'] if c['name'] == 'shuangou_slash_2')
        clip['sourceConfiguration']['configuration']['Transitions'][0][0] = 1
        with self.assertRaisesRegex(ValueError, 'Unbound destination frame shift'):
            combo_bindings(body, locks)


if __name__ == '__main__':
    unittest.main()
