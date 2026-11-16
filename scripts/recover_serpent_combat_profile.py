#!/usr/bin/env python3
"""Append the verified common paired/reaction motions on Liu's actual D13 rig.

The existing 54 animations and geometry are immutable input. Shared raw motion
bytes are sampled against the original Shuangou bones and four hook capsules;
no exported D15 pose, collision track or model is copied to Liu.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from build_erlang_source_assets import checked, encoded, local_source, record, sha, write_new
from build_serpent_source_geometry import BONES, ID, load_bones
from prepare_erlang_animated_body import verify_geometry_prefix
from prepare_serpent_animated_body import append_motion, verify_clip
from recover_erlang_combat_profile import RECOVERED_CONTRACT_SHA, throw_policy, verify_trigger_semantics
from sun_triad_assets import Writer, glb_read, private_output, require

BODY_PROFILE_SHA = 'e0a4d94a15651a189c14c350f3d6820cef2ca0ad40348ffa9de39df19557afce'
BODY_MODEL_SHA = '7d47a59c85832a671de191988b95258fd7cdf85b783e5ceb34aa05aba3c4882e'
RESOURCE = 'Liu_KingOfSerpents_D13_Recovered_Combat'
PROFILE = 'SF3_Serpent_Recovered_Combat_Profile.json'


def source_configs(directory, shared):
    configs = load_bones(directory, shared)
    configs.pop('ranged')
    raw = checked(shared/BONES['base'][0], BONES['base'][1], 10_000)
    configs['base']['masses'] = {b.get('Name'): float(b.get('Mass', '0'))
                               for b in ET.fromstring(raw).findall('./Bones/Bone')}
    return configs


def build(args):
    require(not args.output.exists(), 'Use a fresh private combat output')
    profile = json.loads(checked(args.profile, BODY_PROFILE_SHA, 24_000_000))
    require(profile['id'] == ID and profile['hero'] == 'liu'
            and profile['weaponID'] == 'wpn__shuangou_01_04'
            and profile['sha256'] == BODY_MODEL_SHA and len(profile['clips']) == 54
            and 'ordinaryThrows' not in profile, 'Expected the actual D13 body candidate')
    contract = json.loads(checked(args.contract, RECOVERED_CONTRACT_SHA, 300_000))
    verify_trigger_semantics(contract['triggers'])
    model_path = args.profile.parent/(profile['resourceName']+'.glb')
    require(len(checked(model_path, BODY_MODEL_SHA, 20_000_000)) == profile['bytes'],
            'Original D13 body byte count differs')
    model, binary = glb_read(model_path)
    original = copy.deepcopy(model)
    old_clips = copy.deepcopy(profile['clips'])
    writer = Writer()
    writer.g = model
    writer.b = bytearray(binary[:model['buffers'][0]['byteLength']])
    old_binary = bytes(writer.b)
    names = {r['name']: r['targetNode'] for r in profile['sourceBoneBindings']}
    ids = {r['sourceID']: r['name'] for r in profile['sourceBoneBindings'] if r['sourceID'] is not None}
    require(len(names) == 80 and len(model['nodes']) == 90
            and all(model['nodes'][index]['name'] == name for name, index in names.items()),
            'Original D13 rig differs')
    configs = source_configs(args.source_configs, args.shared_bones)
    bundles, motions, load = local_source(args)
    added = []
    for source in contract['records']:
        info = source['motion']
        matches = [m for m in motions if m['name'] == info['name'] and m['bundle'] == info['bundle']]
        require(len(matches) == 1 and all(matches[0][key] == value for key, value in info.items()),
                'Common motion original catalog identity differs')
        objects = [o for o in load(info['bundle']).objects if o.path_id == info['path_id']]
        require(len(objects) == 1 and objects[0].type.name == 'TextAsset', 'Original motion object missing')
        raw = objects[0].read().m_Script
        raw = raw.encode('utf8', 'surrogateescape') if isinstance(raw, str) else bytes(raw)
        binding = {k: source[k] for k in ('sourceEntry', 'sourceSHA256', 'sourceRecordIndex', 'configuration')}
        require(info['name'] not in {c['name'] for c in profile['clips']}, 'Duplicate common motion')
        clip = append_motion(writer, names, ids, configs, info, raw, binding, info['name'])
        profile['clips'].append(clip)
        if source['role'] is not None:
            require(source['role'] not in profile['roles'], 'Duplicate common role')
            profile['roles'][source['role']] = clip['name']
        added.append(clip)
        print('APPENDED_D13', clip['name'], clip['frames'], flush=True)
    require(len(added) == 12, 'Incomplete common combat source contract')
    profile['ordinaryThrows'] = throw_policy(profile, contract)
    profile['schema'] = 'serpent-recovered-combat-body-profile-v1'
    profile['resourceName'] = RESOURCE
    profile['recoveryBoundary'] = dict(profile['recoveryBoundary'], ordinaryThrowsIncluded=True,
        sourceStunIncluded=True, sourceRootVictimIncluded=True, fullMatchProfile=False)
    model['extras'].update(schema='serpent-recovered-combat-body-v1', sourceAnimationCount=66,
                          ordinaryThrowsIncluded=True, sourceStunIncluded=True, sourceRootVictimIncluded=True)
    output = private_output(args.output)
    target = output/(RESOURCE+'.glb')
    profile.update(writer.save(target))
    target.chmod(0o600)
    actual, actual_binary = glb_read(target)
    verify_geometry_prefix(original, old_binary, actual, actual_binary)
    require(actual['animations'][:54] == original['animations'] and profile['clips'][:54] == old_clips
            and len(actual['animations']) == len(profile['clips']) == 66,
            'Successful original D13 motions changed')
    readback = [verify_clip(actual, actual_binary, c, names, ids, configs) for c in added]
    profile_path = output/PROFILE
    write_new(profile_path, encoded(profile))
    receipt = dict(schema='serpent-recovered-common-combat-append-v1',
        inputProfile=record(args.profile), inputModel=record(model_path), contract=record(args.contract),
        character=record(target), profile=record(profile_path),
        unchangedOriginalAnimations=54, unchangedOriginalBINBytes=len(old_binary),
        unchangedGeometryMaterialsSkinsAndPersonalPortrait=True, ownOriginalRig=True,
        attackCapsules=[c['id'] for c in configs['weapon']['capsules']],
        addedMotionCount=12, totalMotionCount=66, readback=readback,
        comparedValues=sum(r['comparedValues'] for r in readback),
        maximumErrorMeters=max(r['maximumErrorMeters'] for r in readback),
        originalMotionBundles=[{key: bundles[name][key] for key in ('file', 'bytes', 'sha256')}
            for name in sorted({c['bundle'] for c in added})], boundaries=profile['recoveryBoundary'])
    write_new(output/'combat-body-receipt-private.json', encoded(receipt))
    return {k: receipt[k] for k in ('character', 'profile', 'addedMotionCount', 'totalMotionCount',
                                    'comparedValues', 'maximumErrorMeters', 'boundaries')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'contract', 'source-archive', 'source-bundles', 'source-configs', 'shared-bones', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
