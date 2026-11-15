#!/usr/bin/env python3
"""Targeted model-clock, XML selection, and root-motion regression checks."""
import copy
import json
import os
from pathlib import Path
import unittest

import numpy as np

from prepare_erlang_model_tracks import (collision_tracks, interval_ticks, playback_window,
                                         selected_bones, source_poses)
from verify_erlang_model_tracks import verify_document


class ErlangModelTrackTests(unittest.TestCase):
    def config(self, **changes):
        value = dict(MidFrames=None, Looped=None, Mirrored=None, FirstFrame=None, EndFrame=None, SelfEndFrame=None)
        value.update(changes)
        return value

    def test_shared_raw_motion_has_distinct_crop_and_end_event(self):
        stomp = playback_window(self.config(EndFrame=10, SelfEndFrame=0), 31)
        explosion = playback_window(self.config(), 31)
        self.assertEqual((stomp['frames'], stomp['lastSampleTick'], stomp['animationEndTick']), (10, 18, 18))
        self.assertEqual((explosion['frames'], explosion['lastSampleTick'], explosion['animationEndTick']), (31, 60, 52))
        for change in ({'EndFrame': 32}, {'FirstFrame': 31}, {'Mirrored': True}, {'MidFrames': 0}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                playback_window(self.config(**change), 31)

    def test_sword_destroy_end_is_not_interval_start_or_animation_end(self):
        window = playback_window(self.config(), 51)
        ticks = interval_ticks(dict(Start=None, End=35), window)
        self.assertEqual(ticks, dict(startTick=0, endTickInclusive=69, intervalEndEventTick=70))
        self.assertEqual(window['animationEndTick'], 92)
        self.assertEqual(interval_ticks(dict(Start=12, End=34), window),
                         dict(startTick=22, endTickInclusive=67, intervalEndEventTick=68))

    def test_selected_original_part_does_not_invent_unrelated_equipment_bones(self):
        xml = b'''<BonesData><Bones><Bone Name="magic_joint_root" ID="400"/></Bones><Vertexes>
          <Vertex Name="p" BoneName="magic_joint_root" LocalPosition="0 0 0"/>
          <Vertex Name="unrelated" BoneName="missing_human_weapon" LocalPosition="0 0 0"/>
          </Vertexes><Capsules><Capsule Name="huge" Vertex1="p" Vertex2="p" Radius="225"/>
          <Capsule Name="legacy" Vertex1="unrelated" Vertex2="unrelated" Radius="10"/>
          <Capsule Name="legacy" Vertex1="unrelated" Vertex2="unrelated" Radius="10"/>
          </Capsules></BonesData>'''
        bones, excluded = selected_bones(xml, ['huge'])
        self.assertEqual(bones['capsules'][0]['radiusCentimeters'], 225)
        self.assertEqual(len(excluded), 2)
        for selected in (['legacy'], ['missing']):
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                selected_bones(xml, selected)

    def test_alignment_and_horizontal_motion_are_each_applied_once(self):
        rows = [dict(name='magic_joint_root', parent=None, translation=[0, 0, 0], rotation=[0, 0, 0, 1], scale=[1, 1, 1])]
        bones = dict(bones={400: 'magic_joint_root'}, capsules=[dict(id='center', radiusCentimeters=225,
                     base=dict(bone='magic_joint_root', localPositionCentimeters=[0, 0, 0]),
                     tip=dict(bone='magic_joint_root', localPositionCentimeters=[100, 0, 0]))])
        motion = dict(bone_ids=[400], positions=np.array([[[100, 200, 0]], [[300, 400, 0]]]),
                      rotations=np.array([[[0, 0, 0, 1]], [[0, 0, 0, 1]]]))
        window = playback_window(self.config(SelfEndFrame=0), 2)
        worlds, roots, names, unbound, _ = source_poses(rows, bones, motion, window, ['X', 'Y'])
        edge = collision_tracks(worlds, roots, names, bones)[0]
        self.assertEqual(roots[:, 0].tolist(), [-1., -2., -3.])
        self.assertEqual(edge['radiusMillimeters'], 2250)
        self.assertEqual(edge['base'], [[0., 0., 0.], [0., 1., 0.], [0., 2., 0.]])
        self.assertEqual(edge['tip'], [[-1., 0., 0.], [-1., 1., 0.], [-1., 2., 0.]])
        self.assertEqual(unbound, [])

    def test_actual_candidate_roundtrip_and_geometry_corruption(self):
        path = os.environ.get('ERLANG_MODEL_CANDIDATE')
        if not path:
            self.skipTest('Actual private source candidate was not supplied')
        p = Path(path)
        document = json.loads(p.read_bytes())
        motions = {t['clip']: (p.parent / (t['clip'] + '.original-private.bytes')).read_bytes()
                   for t in document['summonTracks']}
        result = verify_document(document, motions)
        print(json.dumps(result, separators=(',', ':')), flush=True)
        self.assertEqual(result['models'], 7)
        self.assertGreater(result['matrixSamples'], 2900)
        changed = copy.deepcopy(document)
        changed['summonTracks'][0]['collisionEdges'][0]['base'][5][0] += .01
        with self.assertRaisesRegex(ValueError, 'same endpoint'):
            verify_document(changed, motions)
        changed = copy.deepcopy(document)
        sword = next(t for t in changed['summonTracks'] if t['role'] == 'erlangSummon_sword')
        sword['sourceEndEventTick'] = 70
        with self.assertRaisesRegex(ValueError, 'terminal event'):
            verify_document(changed, motions)


if __name__ == '__main__':
    unittest.main()
