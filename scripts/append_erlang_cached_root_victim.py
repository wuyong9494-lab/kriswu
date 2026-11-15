#!/usr/bin/env python3
"""Bind original H17 root-victim poses to WuYong's own rig and capsules."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from append_cached_root_victim_motions import BUNDLE, MOTIONS
from append_erlang_cached_stun import verify_new_channels
from build_erlang_source_assets import CONFIGS, append_motion, checked, encoded, record, write_new
from stage_h17_shared_root_release import glb_chunks
from sun_triad_assets import Writer, glb_read, private_output, require
from sun_triad_source_bones import parse_bones_data


SETTINGS_SHA = 'ca4e897298b183818559a1a117f2ba24d529d8cb3f34cd0f10e9225cb49b7ae2'
SOURCE_SHA = '64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a'


def append(args):
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    require(profile['id'] == 'wuyong_erlang' and len(profile['clips']) == 59
            and not any(c['name'] in {m['name'] for m in MOTIONS} for c in profile['clips']),
            'Expected the authenticated 59-clip WuYong candidate')
    model = args.profile.parent / (profile['resourceName'] + '.glb')
    old_model = checked(model, profile['sha256'], 48_000_000)
    g, binary = glb_read(model); writer = Writer(); writer.g = g
    writer.b = bytearray(binary[:g['buffers'][0]['byteLength']])
    old_clips = copy.deepcopy(profile['clips'])
    configs = {}
    for kind, (name, digest) in CONFIGS.items():
        folder = args.source_configs if kind == 'weapon' else args.shared_bones
        raw = checked(folder / name, digest, 1_000_000); configs[kind] = parse_bones_data(raw)
        if kind == 'base':
            configs[kind]['masses'] = {n.get('Name'): float(n.get('Mass', '0'))
                                      for n in ET.fromstring(raw).findall('./Bones/Bone')}
    names = {r['name']: r['targetNode'] for r in profile['sourceBoneBindings']}
    ids = {r['sourceID']: r['name'] for r in profile['sourceBoneBindings'] if r['sourceID'] is not None}
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 1_000_000))
    additions = []
    for index, motion in enumerate(MOTIONS, 102):
        rows = [r for r in settings['records'] if r['sourceEntry'] == 'settings_sets_heralds.bytes'
                and r['sourceRecordIndex'] == index]
        require(len(rows) == 1 and rows[0]['sourceSHA256'] == SOURCE_SHA, 'Source root-victim configuration missing')
        configuration = rows[0]; c = configuration['configuration']
        require(c['FileName'] == 'unique_moves/sets/' + motion['name'] + '.bin'
                and all(c[key] is None for key in ('FirstFrame', 'EndFrame', 'SelfEndFrame', 'MidFrames', 'Sounds')),
                'Source root-victim timing or sound differs')
        raw = checked(args.original_motions / (motion['name'] + '.bytes'), motion['sha256'], 128_000)
        clip = append_motion(writer, names, ids, configs, dict(motion, bundle=BUNDLE), raw, configuration)
        require(clip['frames'] == motion['frames'] and clip['playbackTicks'] == 2 * (motion['frames'] - 1)
                and clip['sourceEndEventTick'] == 2 * (motion['frames'] - 5), 'Root-victim source clock differs')
        profile['clips'].append(clip)
        additions.append(dict(clip=clip['name'], sourceRecordIndex=index, frames=clip['frames'],
                              playbackTicks=clip['playbackTicks'], sourceEndEventTick=clip['sourceEndEventTick'],
                              sourceSHA256=motion['sha256'], sourceSounds=None))
    require(profile['clips'][:59] == old_clips, 'Previously accepted source clips changed')
    require(not args.output.exists(), 'Refuse to replace a candidate'); output = private_output(args.output)
    profile.update(writer.save(output / model.name))
    old, _, old_binary = glb_chunks(old_model)
    new, _, new_binary = glb_chunks((output / model.name).read_bytes())
    require(set(old) == set(new) and len(new_binary) > len(old_binary)
            and new_binary[:len(old_binary)] == old_binary, 'Existing GLB/BIN prefix changed')
    for key in old:
        if key in {'animations', 'accessors', 'bufferViews'}:
            require(new[key][:len(old[key])] == old[key], 'Existing GLB records changed')
        elif key != 'buffers':
            require(old[key] == new[key], 'Existing geometry/material/skin changed')
    require(len(new['animations']) == 62 and [a['name'] for a in new['animations'][59:]] == [m['name'] for m in MOTIONS],
            'Only the three original root-victim animations may be appended')
    readback = verify_new_channels(output / model.name, profile, names, configs, motions=MOTIONS)
    write_new(output / 'SF3_Erlang_Profile.json', encoded(profile))
    receipt = dict(schema='erlang-original-root-victim-append-v1', sourceProfile=record(args.profile),
                   profile=record(output / 'SF3_Erlang_Profile.json'), character=record(output / model.name),
                   sourceConfiguration=record(args.settings), additions=additions, unchangedAnimations=59,
                   unchangedGeometryMaterialsAndSkins=True, usedOnlyCachedSourceMotions=True, readback=readback)
    write_new(output / 'erlang-root-victim-append-private.json', encoded(receipt)); return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('profile', 'original-motions', 'settings', 'source-configs', 'shared-bones', 'output'):
        parser.add_argument('--' + field, type=Path, required=True)
    parser.add_argument('--profile-sha256', required=True)
    print(json.dumps(append(parser.parse_args())))


if __name__ == '__main__':
    main()
