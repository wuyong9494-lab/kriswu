#!/usr/bin/env python3
"""Synthetic checks for source effect attachment, timing and model coordinates."""
import copy
import unittest
import numpy as np
from sun_triad_center_of_mass import mass_declarations, ordered_mass_bindings
from sun_triad_effect_bindings import effect_action, qualifiers
from sun_triad_effect_model_tracks import right_facing_samples, core_capsule_from_fx


class SourceEffectActionTests(unittest.TestCase):
    def record(self, conditions=None):
        return dict(lock=1, setIndex=2, triggerIndex=3, conditions=conditions or [])

    def test_local_rotation_follows_even_when_translation_follow_is_zero(self):
        fields = ['source_effect', False, 'source_bone', None, None, 1, False,
                  True, None, None, True, [0., 0., 0.], None, None, None, None]
        result = effect_action(self.record(), {'a46': fields}, 0)
        self.assertTrue(result['attachToLocal'])
        self.assertTrue(result['follow'])
        self.assertEqual(result['sourceFollow'], [0., 0., 0.])
        self.assertTrue(result['looped'])

    def test_stop_frames_use_simulation_ticks_without_animation_stride(self):
        result = effect_action(self.record(), {'a49': ['source_effect', None, 15, False, False]}, 0)
        self.assertEqual(result['stopFrames'], 15)
        self.assertEqual(result['action'], 'stop')

    def test_quality_and_mirror_conditions_remain_separate(self):
        source = [{'Not': {'expr': [{'f171': ['low']}, 1., 'op22']}},
                  {'Not': {'expr': [{'f65': [{'f74': ['enum65537']}]}, 1., 'op22']}}]
        self.assertEqual(qualifiers(source),
                         dict(sourceExcludedQualities=['low'], sourceMirrorPose=False))
        with self.assertRaisesRegex(ValueError, 'Mirror condition'):
            qualifiers([{'expr': [{'f65': [{'f74': ['enum65538']}]}, 1., 'op22']}])

    def test_nonzero_source_shift_cannot_silently_disappear(self):
        fields = ['source_effect', False, None, None, None, 1, False,
                  False, None, None, False, None, None, [1., 0., 0.], None, None]
        with self.assertRaisesRegex(ValueError, 'shift'):
            effect_action(self.record(), {'a46': fields}, 0)


class SourceIndependentModelTests(unittest.TestCase):
    def test_root_motion_reconstructs_fx_without_person_scale_or_double_offset(self):
        original = []
        for x in [-2., -5.]:
            root = np.eye(4)
            root[:3, 3] = [x, 1., -.25]
            tip = root.copy()
            tip[0, 3] -= 2.
            original.append([root, tip])
        snapshot = copy.deepcopy(original)
        fx, root = right_facing_samples(original, 0)
        np.testing.assert_allclose(root, [[2., 1., .25], [5., 1., .25]])
        record = dict(id='source_capsule', radiusMillimeters=1600,
                      base=[pose[0][:3, 3].tolist() for pose in fx],
                      tip=[pose[1][:3, 3].tolist() for pose in fx])
        core = core_capsule_from_fx(record, root)
        np.testing.assert_allclose(core['base'], [[0., 1., .25]] * 2)
        np.testing.assert_allclose(core['tip'], [[2., 1., .25]] * 2)
        rebuilt = np.array(core['tip'])
        rebuilt[:, 0] += root[:, 0] - root[0, 0]
        np.testing.assert_allclose(rebuilt, record['tip'])
        np.testing.assert_allclose(original, snapshot)


class SourceMassTests(unittest.TestCase):
    def test_missing_mass_is_zero_and_mirror_rule_does_not_change_mass(self):
        raw = b'''<BonesData><Bones><Bone Name="root" ID="0" Mass="5"/>
            <Bone Name="weapon" ID="200"/></Bones><Mirroring>
            <Bone Name="root" ID="999" Mass="20"/></Mirroring></BonesData>'''
        result = mass_declarations(raw)
        self.assertEqual(result[0]['mass'], 5.)
        self.assertEqual(result[200]['mass'], 0.)
        self.assertNotIn(999, result)

    def test_mass_accumulation_uses_child_order_not_xml_or_node_index_order(self):
        raw = b'''<BonesData><Bones><Bone Name="last" ID="2" Mass=".2"/>
            <Bone Name="root" ID="0" Mass="5"/>
            <Bone Name="first" ID="1" Mass=".1"/></Bones></BonesData>'''
        nodes = [dict(name='root', children=[2, 1]), dict(name='last'), dict(name='first')]
        bindings = [dict(name='last', targetNode=1, sourceID=2),
                    dict(name='root', targetNode=0, sourceID=0),
                    dict(name='first', targetNode=2, sourceID=1)]
        result = ordered_mass_bindings(bindings, nodes, [mass_declarations(raw)])
        self.assertEqual([row['name'] for row in result], ['root', 'first', 'last'])
        bad = copy.deepcopy(bindings)
        bad[0]['sourceID'] = 17
        with self.assertRaisesRegex(ValueError, 'missing'):
            ordered_mass_bindings(bad, nodes, [mass_declarations(raw)])


if __name__ == '__main__':
    unittest.main()
