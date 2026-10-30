import copy
import unittest
from collect_arena_flow import validate_scene, is_scene_attachment


class FlowEvidenceTests(unittest.TestCase):
    def scene(self):
        return dict(kind='three-hero-ui-flow', playerHero=1, map='twin_gates_sample_v1',
                    qualitySample=True, finishedNaturally=True, forcedResult=False, simulationTime=150,
                    fighters=[dict(id=i, hero=(i % 3) + 1, team=i // 3) for i in range(6)],
                    events=[dict(kind='attack', fighter=0, simulationTime=6),
                            dict(kind='super', fighter=0, simulationTime=20)])

    def test_accepts_natural_scene_with_both_actions(self):
        self.assertEqual(validate_scene(self.scene(), 1), dict(attack=1, super=1))

    def test_rejects_injected_result_and_wrong_hero(self):
        scene = self.scene()
        scene['forcedResult'] = True
        with self.assertRaises(ValueError): validate_scene(scene, 1)
        with self.assertRaises(ValueError): validate_scene(self.scene(), 2)

    def test_other_fighters_super_does_not_count_as_player_demonstration(self):
        scene = self.scene()
        scene['events'][1]['fighter'] = 3
        with self.assertRaises(ValueError): validate_scene(scene, 1)

    def test_rejects_old_roster_and_backwards_event_clock(self):
        scene = self.scene()
        scene['fighters'][2]['hero'] = 0
        with self.assertRaises(ValueError): validate_scene(scene, 1)
        scene = self.scene()
        scene['events'].reverse()
        with self.assertRaises(ValueError): validate_scene(scene, 1)

class AttachmentNames(unittest.TestCase):
    def test_xcode_export_normalization(self):
        self.assertTrue(is_scene_attachment('arena-flow-hero-2_0_F6D924E2.json', 2))
        self.assertTrue(is_scene_attachment('arena-flow-hero-2.json', 2))
        self.assertFalse(is_scene_attachment('arena-flow-hero-2_0_F6D924E2.json', 1))
        self.assertFalse(is_scene_attachment('arena-flow-hero-20_0_id.json', 2))
        self.assertFalse(is_scene_attachment('arena-flow-hero-2_0_id.png', 2))
