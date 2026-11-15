#!/usr/bin/env python3
"""Small source-contract checks; no downloads, client, native build or keys."""
import copy
import unittest

from prepare_erlang_hound import playback_window, edge_definition, PARTS
from bind_erlang_hound import document


class ErlangHoundTests(unittest.TestCase):
    def test_raw_frames_cannot_replace_configured_window(self):
        c = dict(FirstFrame=None, EndFrame=60, MidFrames=None, SelfEndFrame=None)
        result = playback_window(c, 141)
        self.assertEqual((result['frames'], result['lastSampleTick'], result['endEventTick']), (60, 118, 110))
        for change in ({'EndFrame': 141}, {'FirstFrame': 2}, {'MidFrames': 0}, {'SelfEndFrame': 0}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                playback_window(dict(c, **change), 141)
        with self.assertRaises(ValueError):
            playback_window(c, 60)

    def test_central_capsule_slot_does_not_accept_unknown_parts(self):
        for name, radius in [('Dog_Head_Attacking_Edge', 20), ('Dog_Body_Attacking_Edge', 10),
                             ('Dog_Front_Attacking_Edge_l', 12), ('Dog_Front_Attacking_Edge_r', 12)]:
            value = edge_definition(dict(id=name, radiusCentimeters=radius))
            self.assertEqual(value['radiusMillimeters'], radius * 10)
            self.assertEqual(value['side'], 'left' if name.endswith('_l') else 'right')
        with self.assertRaises(ValueError):
            edge_definition(dict(id='Guessed_Head_Edge', radiusCentimeters=20))
        with self.assertRaises(ValueError):
            edge_definition(dict(id=PARTS[0], radiusCentimeters=20.05))

    def test_manifest_requires_same_current_track_not_matching_name_only(self):
        from prepare_erlang_hound import BONES_SHA, MOTION_SHA, ROLE
        track = dict(role=ROLE, sourceSHA256=MOTION_SHA, boneConfigurationSHA256=BONES_SHA,
                     sourceEndEventTick=110, frames=60, root=[[0, 0, 0]] * 119,
                     attackParts={'primary': PARTS})
        candidate = dict(schema='original-d15-hound-candidate-v1', track=track,
                         sourceModel='mgc__d15_dog', rootBone='spine_root_joint', modelFile={}, materials=[])
        profile = dict(id='wuyong_erlang', sha256='a' * 64, summonTracks=[copy.deepcopy(track)])
        self.assertEqual(document(candidate, profile)['models'][0]['originalMotionFrames'], 141)
        profile['summonTracks'][0]['root'][17] = [.1, 0, 0]
        with self.assertRaises(ValueError):
            document(candidate, profile)
        for change in ({'sourceEndEventTick': 118}, {'frames': 141}, {'sourceSHA256': 'b' * 64}):
            altered = copy.deepcopy(candidate)
            altered['track'].update(change)
            with self.assertRaises(ValueError):
                document(altered, dict(profile, summonTracks=[altered['track']]))


if __name__ == '__main__':
    unittest.main()
