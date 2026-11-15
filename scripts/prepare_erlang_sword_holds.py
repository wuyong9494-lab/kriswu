#!/usr/bin/env python3
"""Export the six original D15 sword births and held poses from cached inputs.

The already verified attack-model receipt identifies the same raw motion and
prefab. No archive scan, download, decryption, invented weapon or resampling of
the human rig is involved. Birth/idle/rotate remain separate animation states.
"""
from __future__ import annotations

import argparse
import json
import warnings
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from prepare_erlang_model_tracks import (CONFIGURATION_SHA, SETTINGS_SHA, MODELS,
    RULE_SHA, checked, decode, interval_ticks, load_model, playback_window,
    private_output, require, sha, source_poses, write_private)

CANDIDATE_SHA = '870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc'
MOTION_SHA = '0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632'
BIRTH_RULE_SHA = {
    1441: '5eeab2247dcd147384d55b687f80c9db354405fb95f35a352cec6fcba6977465',
    1442: '5820b868959e4561af5894fa18407eddde1fbdfc90565bf3b6eea040c8fb5994',
    1443: 'def3db0347d60fb0de762e6d2be2177cffcd4f06a5b2631588c9214c98cb05b4',
    1444: 'df7fbf562651b6305ce74f7a8a874881aac435ad8806e32aeae2781ac768d4d2',
    1445: '8b17eba4febbdbba895b8a65b57930a4e8645595ac70ebcf4270eb8106378f3c',
    1446: 'bc92b2a71e74f612954481e73380e9071d9ed6c133c67520ae073c221e1dd27e',
    1447: 'b669f6703066c2ae148fc27d0b15edb5ad7fcc3aaad48d02bf24105f8a183695',
}
SHIFTS = [[-75., 170., -50.], [-75., 170., 50.], [-75., 195., -50.],
          [-75., 195., 50.], [-75., 205., -15.], [-75., 225., -15.]]
CHECK_FRAMES = [5, 10, 15, 18, 21, 25, 30, 35, 40, 45, 50]
CHECK_TICKS = [8, 18, 28, 34, 40, 48, 58, 68, 78, 88, 98]


def settings_record(document, index, alias):
    rows = [r for r in document['records'] if r['sourceEntry'] == 'settings_sets_dynasty.bytes'
            and r['sourceRecordIndex'] == index and r['configuration']['Animation'] == alias]
    require(len(rows) == 1 and rows[0]['sourceSHA256'] == CONFIGURATION_SHA,
            'Sword source animation identity differs')
    return rows[0]


def rule(directory, lock):
    digest = BIRTH_RULE_SHA.get(lock, RULE_SHA.get(lock))
    require(digest is not None, 'Unpinned original sword rule')
    p = directory / f'd15-lock-{lock}-compact-private.json'
    raw = checked(p, digest, 100_000)
    return dict(lock=lock, file=p.name, sha256=sha(raw), triggers=json.loads(raw))


def window(configuration):
    c = dict(configuration)
    if c['Animation'].endswith('_Rotate'):
        require(c['FirstFrame'] is None and c['EndFrame'] == 1 and c['MidFrames'] == 0
                and c['SelfEndFrame'] == 0 and c['Looped'] is None,
                'Original one-sample rotate window differs')
        return dict(originalFrames=51, firstIndex=0, lastIndex=0, frames=1,
                    samplesPerSourceFrame=1, lastSampleTick=0, animationEndTick=0, selfEndFrames=0)
    require(c['Looped'] == (True if c['Animation'].endswith('_Idle') else None),
            'Original held-loop declaration differs')
    c['Looped'] = None
    return playback_window(c, 51)


def verify_source_contract(document):
    """Validate the new state/slot contract, without treating holds as attacks."""
    poses = document['models']
    require(len(poses) == 8 and len(document['summonTracks']) == 7, 'Missing held state or invented rotate sample')
    require([p['slot'] for p in poses[:6]] == list(range(1, 7)), 'Birth slot order differs')
    for index, p in enumerate(poses[:6]):
        require(p['role'] == f'erlangSummon_swordBirth{index + 1}'
                and p['sourceRecordIndex'] == 110 + index
                and p['sourceAnimation'] == f'D15_Hovering_Sword_Model_Birth_{index + 1}'
                and p['origin']['sourceShiftCentimeters'] == SHIFTS[index]
                and p['origin']['selectedAlignAxes'] == ['X', 'Z']
                and p['motion']['animationEndTick'] == 92
                and p['sourceLooped'] is None, 'Birth slot pose identity differs')
        require([e['sourceFrame'] for e in p['sourceChecks']] == CHECK_FRAMES
                and [e['intervalStartTick'] for e in p['sourceChecks']] == CHECK_TICKS
                and p['sourceChecks'][-1]['beforeAnimationEnd'] is False,
                'Source interval event clock differs from the sound clock')
        require(p['sourceSounds'] == [{'Frame': 1, 'Common': ['set_d15/d15_swords_appear@Battle@Movement'],
                                     'Gender': None, 'Floor': None}], 'Birth sound identity differs')
    rotate = next(p for p in poses if p['role'] == 'erlangSummon_swordRotate')
    idle = next(p for p in poses if p['role'] == 'erlangSummon_swordIdle')
    require(rotate['motion']['frames'] == 1 and rotate['motion']['lastSampleTick'] == 0
            and all(len(v) == 1 for v in rotate['bones'].values()), 'Static rotate pose was stretched')
    require(idle['sourceLooped'] is True and idle['origin']['sourceAlign'][5] == ['Me', 'Pivot', None]
            and idle['origin']['selectedAlignAxes'] == ['X', 'Y', 'Z'], 'Held idle anchoring differs')
    for track in document['summonTracks']:
        require(track['collisionEdges'] == [] and track['hurtCapsules'] == [] and track['attackParts'] == {}
                and track['frames'] == 51 and len(track['root']) == 101
                and 'sourceDeleteEventTick' not in track, 'Held sword acquired a fake hitbox or deletion')
    common = next(r for r in document['rules'] if r['lock'] == 1449)['triggers']
    by_id = {t['triggerIndex']: t for t in common}
    require(by_id[8]['priority'] == 403 and by_id[9]['priority'] == 402
            and {'a6': ['D15_Hovering_Sword_Model_Idle', None, None]} in by_id[9]['actions']
            and by_id[10]['events'] == [{'a44': ['enum65539', 'SET_D15_SWORD_ATTACK_START']}]
            and by_id[10]['actions'] == [{'a6': ['D15_Hovering_Sword_Model_Attack', None, None]}],
            'Held rotation/idle/release event chain differs')


def build(args):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    prior = json.loads(checked(args.model_candidate, CANDIDATE_SHA, 700_000))
    attack = next(r for r in prior['receipts'] if r['role'] == 'erlangSummon_sword')
    motion_identity = attack['originalMotion']
    require(motion_identity['sha256'] == MOTION_SHA and motion_identity['bytes'] == 6182
            and motion_identity['frames'] == 51, 'Reviewed sword motion receipt differs')
    raw = checked(args.model_candidate.parent / 'd15_hovering_sword.original-private.bytes', MOTION_SHA, 7000)
    arrays = decode(raw)
    require(len(arrays) == 2 and all(a['frame_count'] == 51 for a in arrays), 'Source sword motion arrays differ')
    motion = arrays[0]
    require([int(n) for n in motion['bone_ids']] == [400, 402, 401, 403, 404], 'Source sword rig IDs differ')
    rows, bones, model_receipt = load_model('sword', SimpleNamespace(additional=args.additional), [])
    rules = [rule(args.rules, n) for n in [1440, *range(1441, 1448), 1449]]
    models, tracks = [], []
    for index in range(110, 118):
        slot = index - 109 if index < 116 else None
        suffix = f'Birth_{slot}' if slot else 'Rotate' if index == 116 else 'Idle'
        alias = 'D15_Hovering_Sword_Model_' + suffix
        role = 'erlangSummon_sword' + (f'Birth{slot}' if slot else suffix)
        setting = settings_record(settings, index, alias)
        c, w = setting['configuration'], window(setting['configuration'])
        require(c['FileName'] == 'unique_moves/sets_d15/d15_hovering_sword.bin'
                and c['Align'][6] == [None, 'Nodes', 'magic_joint_root']
                and c['SetDirection'] == [None, None, ['Parent', 'Nodes', 'pelvis'],
                                         ['Parent', 'Wall', 'Front'], None, None], 'Source sword origin/direction differs')
        worlds, roots, names, unbound, rest_only = source_poses(rows, bones, motion, w, c['Align'][4])
        require(unbound == [] and rest_only == ['weapon_l', 'weapon_r'], 'Unbound sword rig channels')
        matrices = {name: [np.round(frame[node].T.reshape(-1), 9).tolist() for frame in worlds]
                    for name, node in names.items() if name in bones['bones'].values()}
        checks = [dict(sourceFrame=i['Start'], intervalStartTick=interval_ticks(i, w)['startTick'],
                       beforeAnimationEnd=interval_ticks(i, w)['startTick'] <= w['animationEndTick'])
                  for i in c['Intervals'] if i['Name'] == 'D15_Sword_Check']
        model = dict(role=role, ability='swords', slot=slot, sourceAnimation=alias,
            sourceRecordIndex=index, sourceConfigurationSHA256=CONFIGURATION_SHA,
            sourceFile=c['FileName'], motion=w, sourceLooped=c['Looped'], bones=matrices,
            origin=dict(sourceAlign=c['Align'], sourceSetDirection=c['SetDirection'],
                sourceShiftCentimeters=c['Align'][3], selectedAlignAxes=c['Align'][4],
                initialRootMeters=roots[0].tolist(), sourceRightRotation='Ry(pi)', modelScale=1),
            sourceSounds=c['Sounds'], sourceChecks=checks, sourceConfiguration=setting)
        models.append(model)
        if slot:
            birth = next(r for r in rules if r['lock'] == 1440 + slot)['triggers']
            require(len(birth) == 1 and birth[0]['events'] == [{'a2': ['enum65537']}]
                    and birth[0]['actions'] == [{'a6': [alias, None, None]}], 'Source birth model dispatch differs')
        if w['frames'] > 1:
            tracks.append(dict(role=role, clip='d15_hovering_sword', frames=51,
                sourceSHA256=MOTION_SHA, sourceBundle=motion_identity['bundle'],
                root=np.round(roots, 9).tolist(), groundLift=[0.] * len(roots),
                boneConfigurationSHA256=MODELS['sword']['bonesSHA'],
                collisionEdges=[], hurtCapsules=[], attackParts={}, sourceEndEventTick=w['animationEndTick']))
    document = dict(schema='original-d15-sword-held-poses-v1', sourceConfigurationSHA256=CONFIGURATION_SHA,
        modelCandidateSHA256=CANDIDATE_SHA, sourceMotion=motion_identity, sourceModel=model_receipt,
        summonTracks=tracks, models=models, rules=rules,
        coordinateContract=prior['coordinateContract'],
        lifecycle=dict(birthEndAction='D15_Hovering_Sword_Model_Idle',
            sourceCheckUnits='IntervalStart=max(0, sourceFrame-1)*2; sounds use sourceFrame*2 independently.',
            releaseEvent='Parent SET_D15_SWORD_ATTACK_START VariableDestruction',
            releaseAction='D15_Hovering_Sword_Model_Attack',
            rotationPriorityOrder=[403, 402], attackDeleteEventTick=70),
        boundaries=[
            'These are independent original source poses and events, not a rendered sword substitute.',
            'Birth AnimationEnd transitions to Idle; it is not a DeleteModel event. Core must preserve model identity across states.',
            'Rotate is a single original sample at tick zero; no second frame is manufactured for a generic track validator.',
            'Source Idle is Looped. The native loop wrap and same-tick event commit order are not inferred from its End threshold.',
            'Hold pursuit remains the source lock1449 check/velocity rules. The source pose alone does not prove runtime following.',
            'Align axes select owner coordinates; the source Shift is not transformed by RIGHT a second time.'])
    verify_source_contract(document)
    output = private_output(args.output)
    require(not any(output.iterdir()), 'Sword held output must be empty')
    data = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    name = 'd15-sword-held-candidate-private.json'
    write_private(output / name, data)
    print(json.dumps(dict(file=name, bytes=len(data), sha256=sha(data), birthSlots=6,
                         models=len(models), tracks=len(tracks), originalRotateSamples=1)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('settings', 'model-candidate', 'additional', 'rules', 'output'):
        p.add_argument('--' + n, required=True, type=Path)
    build(p.parse_args())


if __name__ == '__main__':
    main()
