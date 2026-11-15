#!/usr/bin/env python3
"""Append the three cached original Stun motions to the verified WuYong rig.

No archive extraction or media download is performed. Existing geometry,
materials, skins, personal portrait/neck fit, animations and BIN bytes are
preserved, then the new GLB channels are read back against every FK sample.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np

from append_cached_stun_motions import BUNDLE, MOTIONS, validate_stun_append
from build_erlang_source_assets import CONFIGS, append_motion, checked, encoded, record, write_new
from sun_triad_assets import RIGHT, Writer, accessor_read, capsule_point, glb_read, matrix, pose_world, private_output, require, world_poses
from sun_triad_source_bones import parse_bones_data


SETTINGS_SHA = "742a807523b97a58aefffa5d14dbc35eb7c39b4f9e4c5b026f27788f623d4835"
MOVES_SHA = "fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b"


def verify_new_channels(model, profile, names, configs, motions=MOTIONS):
    g, binary = glb_read(model)
    _, rest, parents = world_poses(g['nodes'])
    weighted = sorted((names[name], mass) for name, mass in configs['base']['masses'].items() if mass > 0)
    capsules = configs['weapon']['capsules'] + configs['fullBody']['capsules']
    maximum, points, samples = 0., 0, 0

    def compare(actual, expected):
        nonlocal maximum, points
        error = float(np.max(np.abs(np.asarray(actual) - np.asarray(expected))))
        require(np.isfinite(error) and error < 2e-6, 'New GLB/source FK mismatch')
        maximum = max(maximum, error); points += 1

    for motion in motions:
        clip = next(c for c in profile['clips'] if c['name'] == motion['name'])
        animation = next(a for a in g['animations'] if a['name'] == motion['name'])
        curves = {}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            times = accessor_read(g, binary, sampler['input']).reshape(-1)
            require(sampler['interpolation'] == 'LINEAR' and len(times) == motion['frames']
                    and np.max(np.abs(times - np.arange(motion['frames']) / 30)) < 2e-7,
                    'Original Stun key count or time differs')
            key = channel['target']['node'], channel['target']['path']
            require(key not in curves, 'Duplicate Stun GLB channel')
            curves[key] = accessor_read(g, binary, sampler['output'])
        require(len(curves) == 116, 'Expected all 58 original body bones')
        tracks = clip['tracks']; shapes = tracks['collisionEdges'] + tracks['hurtCapsules']
        require(len(shapes) == len(capsules) == 17, 'Original source collision inventory differs')
        for tick in range(2 * motion['frames'] - 1):
            a, b = tick // 2, min(motion['frames'] - 1, tick // 2 + 1)
            fraction = (tick % 2) / 2
            local = [value.copy() for value in rest]
            for node, path in curves:
                if path != 'translation':
                    continue
                position = curves[node, 'translation'][a] * (1 - fraction) + curves[node, 'translation'][b] * fraction
                rotation = curves[node, 'rotation'][a] * (1 - fraction) + curves[node, 'rotation'][b] * fraction
                local[node] = matrix(position, rotation, g['nodes'][node].get('scale', [1, 1, 1]))
            world = pose_world(local, parents)
            for label, bone in [('handL', 'hand_l'), ('handR', 'hand_r'), ('footL', 'foot_l'),
                                ('footR', 'foot_r'), ('toeL', 'toe_l'), ('toeR', 'toe_r'),
                                ('pelvis', 'pelvis'), ('head', 'head')]:
                compare((RIGHT @ world[names[bone]][:, 3])[:3], tracks[label][tick])
            accumulator, total = np.zeros(3, dtype=np.float32), np.float32(0)
            for node, mass in weighted:
                mass = np.float32(mass)
                point = np.asarray((RIGHT @ world[node][:, 3])[:3], dtype=np.float32)
                accumulator = np.asarray(accumulator + point * mass, dtype=np.float32)
                total = np.float32(total + mass)
            compare(accumulator / total, tracks['centerOfMass'][tick])
            for capsule, shape in zip(capsules, shapes):
                require(capsule['id'] == shape['id'], 'Source capsule identity differs')
                for end in ('base', 'tip'):
                    compare(capsule_point(capsule[end], world, names), shape[end][tick])
            samples += 1
    require(samples == sum(2 * motion['frames'] - 1 for motion in motions), 'Unexpected source sample inventory')
    return dict(clips=3, sourceSamples=samples, comparedPoints=points,
                maximumErrorMeters=maximum, nativeRendered=False)


def append(args):
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    require(profile['id'] == 'wuyong_erlang' and len(profile['clips']) == 56
            and all(m['role'] not in profile['roles'] for m in MOTIONS),
            'Expected the verified 56-clip WuYong candidate without Stun')
    model = args.profile.parent / (profile['resourceName'] + '.glb')
    old_bytes = checked(model, profile['sha256'], 48_000_000)
    g, binary = glb_read(model); before = copy.deepcopy(g)
    writer = Writer(); writer.g = g; writer.b = bytearray(binary[:g['buffers'][0]['byteLength']])
    old_clips = copy.deepcopy(profile['clips'])
    configs = {}
    for kind, (name, digest) in CONFIGS.items():
        folder = args.source_configs if kind == 'weapon' else args.shared_bones
        raw = checked(folder / name, digest, 1_000_000)
        configs[kind] = parse_bones_data(raw)
        if kind == 'base':
            configs[kind]['masses'] = {n.get('Name'): float(n.get('Mass', '0'))
                                      for n in ET.fromstring(raw).findall('./Bones/Bone')}
    names = {r['name']: r['targetNode'] for r in profile['sourceBoneBindings']}
    ids = {r['sourceID']: r['name'] for r in profile['sourceBoneBindings'] if r['sourceID'] is not None}
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    additions = []
    for index, motion in enumerate(MOTIONS, 87):
        rows = [r for r in settings['records'] if r['sourceEntry'] == 'moves_settings.bytes'
                and r['sourceRecordIndex'] == index]
        require(len(rows) == 1 and rows[0]['sourceSHA256'] == MOVES_SHA,
                'Exact source Stun configuration missing')
        config = rows[0]; c = config['configuration']
        require(c['FileName'] == 'hits/' + motion['name'] + '.bin'
                and all(c[k] is None for k in ('FirstFrame', 'EndFrame', 'SelfEndFrame', 'MidFrames', 'Sounds')),
                'Original shared Stun timing or audio differs')
        raw = checked(args.original_motions / (motion['name'] + '.bytes'), motion['sha256'], 100_000)
        clip = append_motion(writer, names, ids, configs, dict(motion, bundle=BUNDLE), raw, config)
        require(clip['frames'] == motion['frames'] and clip['playbackTicks'] == 2 * (motion['frames'] - 1)
                and clip['sourceEndEventTick'] == 2 * (motion['frames'] - 5), 'Stun clock differs')
        profile['clips'].append(clip); profile['roles'][motion['role']] = motion['name']
        additions.append(dict(role=motion['role'], clip=motion['name'], sourceRecordIndex=index,
                              frames=clip['frames'], playbackTicks=clip['playbackTicks'],
                              sourceEndEventTick=clip['sourceEndEventTick'], sourceSHA256=motion['sha256'],
                              sourceSounds=None))
    require(profile['clips'][:56] == old_clips and g['animations'][:56] == before['animations'],
            'Existing source clips changed')
    require(not args.output.exists(), 'Refuse to replace an existing candidate')
    output = private_output(args.output); profile.update(writer.save(output / model.name))
    validate_stun_append(old_bytes, (output / model.name).read_bytes(), 56)
    verification = verify_new_channels(output / model.name, profile, names, configs)
    write_new(output / 'SF3_Erlang_Profile.json', encoded(profile))
    receipt = dict(schema='erlang-original-stun-append-v1', sourceProfile=record(args.profile),
                   profile=record(output / 'SF3_Erlang_Profile.json'), character=record(output / model.name),
                   additions=additions, unchangedAnimations=56, unchangedGeometryMaterialsAndSkins=True,
                   unchangedPersonalPortraitAndNeckFit=True, usedOnlyCachedSourceMotions=True,
                   readback=verification)
    write_new(output / 'erlang-stun-append-private.json', encoded(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('profile', 'original-motions', 'settings', 'source-configs', 'shared-bones', 'output'):
        parser.add_argument('--' + field, type=Path, required=True)
    parser.add_argument('--profile-sha256', required=True)
    print(json.dumps(append(parser.parse_args())))


if __name__ == '__main__':
    main()
