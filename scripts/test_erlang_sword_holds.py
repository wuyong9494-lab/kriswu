#!/usr/bin/env python3
"""Focused checks for the actual original D15 held-sword candidate."""
import argparse
import copy
import json
import unittest
from pathlib import Path

import numpy as np

from prepare_erlang_sword_holds import MOTION_SHA, checked, decode, verify_source_contract
from sun_triad_assets import C, CI, matrix


def verify_source_poses(document, raw):
    source = decode(raw)[0]
    receipt = document['sourceModel']
    rows = receipt['originalPrefabHierarchy']
    declarations = receipt['sourceDeclarations']['bones']
    columns = {declarations[str(int(identifier))]: i for i, identifier in enumerate(source['bone_ids'])}
    right = np.diag([-1., 1., -1., 1.])
    world_frames = {}
    for frame in (0, 23, 50):
        world = {}
        for row in rows:
            name = row['name']
            if name in columns:
                column = columns[name]
                local = matrix(source['positions'][frame, column], source['rotations'][frame, column], row['scale'])
            else:
                local = matrix(row['translation'], row['rotation'], row['scale'])
            world[name] = local if row['parent'] is None else world[row['parent']] @ local
        world_frames[frame] = {name: right @ C @ value @ CI for name, value in world.items()}
    for model in document['models']:
        first = world_frames[0]['magic_joint_root'][:3, 3]
        for frame in ((0,) if model['motion']['frames'] == 1 else (0, 23, 50)):
            for name, values in model['bones'].items():
                expected = world_frames[frame][name].copy()
                for axis in model['origin']['selectedAlignAxes']:
                    k = 'XYZ'.index(axis)
                    expected[k, 3] -= first[k]
                actual = np.asarray(values[frame * 2]).reshape(4, 4).T
                if np.max(abs(actual - expected)) > 0.00000002:
                    raise ValueError('Held source pose differs from raw unconverted FK')


class SwordHeldChecks(unittest.TestCase):
    def test_actual_slot_contract_and_independent_raw_fk(self):
        verify_source_contract(self.document)
        verify_source_poses(self.document, self.raw)
        changed = copy.deepcopy(self.document)
        changed['models'][3]['bones']['weapon_r'][46][12] += 0.001
        with self.assertRaises(ValueError):
            verify_source_poses(changed, self.raw)

    def test_distinct_slot_and_interval_clock_tampering_reject(self):
        for mutate in (
            lambda d: d['models'][1]['origin'].__setitem__('sourceShiftCentimeters', [-75., 170., -50.]),
            lambda d: d['models'][0]['sourceChecks'][0].__setitem__('intervalStartTick', 10),
            lambda d: d['models'][0].__setitem__('role', 'erlangSummon_sword'),
        ):
            changed = copy.deepcopy(self.document); mutate(changed)
            with self.assertRaises(ValueError): verify_source_contract(changed)

    def test_static_rotate_and_nonattack_lifecycle_not_fabricated(self):
        for mutate in (
            lambda d: d['models'][6]['motion'].__setitem__('frames', 2),
            lambda d: d['summonTracks'][0].__setitem__('sourceDeleteEventTick', 92),
            lambda d: d['summonTracks'][0].__setitem__('attackParts', {'primary': ['Shadow_attacking_edge_D15']}),
        ):
            changed = copy.deepcopy(self.document); mutate(changed)
            with self.assertRaises(ValueError): verify_source_contract(changed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--motion', required=True, type=Path)
    args = parser.parse_args()
    SwordHeldChecks.document = json.loads(args.candidate.read_bytes())
    SwordHeldChecks.raw = checked(args.motion, MOTION_SHA, 7000)
    unittest.main(argv=['test_erlang_sword_holds.py'], verbosity=2)
