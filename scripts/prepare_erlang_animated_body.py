#!/usr/bin/env python3
"""Recover D15 body animations on the authenticated static WuYong geometry.

This independent source-only entry does not change the historical actor builder,
its 302-file release gate, or its missing paired-throw reference catalogue. The
output has real source poses and collision tracks, but is not a match/release
profile: throw, Stun/root-victim, neck-fit and ability/model binding remain
separate work. No network, original-program execution or production activation.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np

from build_erlang_source_assets import (
    COMBO_LINKS, CONFIGS, ID, ROLE_INPUTS, append_motion, checked, encoded,
    local_source, motion_rows, record, sha, write_new,
)
from erlang_source_profile import combat_rules, source_end_event_tick, source_record, source_window
from prepare_fighter_target_motions import ARCHIVE_SHA256
from source_body_mirroring import body_rules
from sun_triad_assets import (
    RIGHT, Writer, accessor_read, capsule_point, glb_read, matrix, pose_world,
    private_output, require, world_poses,
)
from sun_triad_source_bones import merge_bone_ids, parse_bones_data


STATIC_SHA = 'fe02e7c96d99905e70af712cfd0b52bea1d6d3b732f07eb44bbe5fe6b8182f39'
STATIC_RECEIPT_SHA = 'ded6bbc5d5fb98a5a6ae8b245d6a4aa984283668921401de4a1145e0ddad326c'
NAMED_SHA = '12704648d0fd60929d1bba47a0fe6cd1eb0f3aafd36b7504b8819f57f5bddb08'
NAMED_RECEIPT_SHA = '22541c12e95558c4e1a0a09e4b67ecb817ffde512ad41ea079a285fe0e9acd27'
ROUND_TRIP_SHA = '0ea3ac6849d8d5c9f7f1ee2a679b89807f6b68a09ad9bfef45632692861f1777'
SOURCE_PINS = {
    'moves_settings.bytes': (86885, 'fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b'),
    'settings_blocks.bytes': (84383, 'ecad88aefa412f8972d508ee63ab916190065f8a0c9dcc8bb8a2c7d8f716b091'),
    'settings_hits.bytes': (64690, 'd6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a'),
    'settings_sets_dynasty.bytes': (334225, '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'),
    'settings_style_imperial_spear.bytes': (39345, 'fb54e61b150349f0a02735ee8354ed6fe21a4263862dd6162e0123583705e8b0'),
    'settings_style_kicks.bytes': (109275, '15318c7a03085ea91c7010ab41a9407d820505666dea02880e1779f38bfa34cf'),
}
MIRROR_ROLE = 'imperialHeavyPassiveMirrored'
MIRROR_CLIP = 'imperial_spear_heavy_slash_passive_mirrored'
RESOURCE = 'WuYong_Erlang_D15_Animated_Source'
PROFILE = 'SF3_Erlang_Animation_Source_Profile.json'
POINT_FIELDS = {
    'handL': 'hand_l', 'handR': 'hand_r', 'footL': 'foot_l', 'footR': 'foot_r',
    'toeL': 'toe_l', 'toeR': 'toe_r', 'pelvis': 'pelvis', 'head': 'head',
}
BOUNDARY = dict(sourceOnly=True, runtimeBound=False, fullMatchProfile=False,
    historicalBodyIdentityRestored=False, historicalReferenceCatalogReconstructed=False,
    ordinaryThrowsIncluded=False, sourceStunIncluded=False, sourceRootVictimIncluded=False,
    personalNeckBridgeIncluded=False, abilityRuntimeRulesIncluded=False,
    summonModelTracksIncluded=False, audioBound=False, sourceShaderParity=False,
    nativeRenderingVerified=False, productionActivation=False, uploadedToTestFlight=False)


def load_named(settings):
    document = json.loads(checked(settings, NAMED_SHA, 1_000_000))
    require(document['schema'] == 'recovered-erlang-named-animation-source-v1'
            and document['originalValuesAndTypesPreserved'] is True
            and document['existingBuilderPinsChanged'] is False
            and len(document['records']) == 82, 'Recovered named source contract differs')
    evidence = []
    for name, digest in [('receipt-private.json', NAMED_RECEIPT_SHA),
                         ('record-round-trip-audit-private.json', ROUND_TRIP_SHA)]:
        path = settings.parent / name
        checked(path, digest, 100_000)
        evidence.append(record(path))
    for name, (size, digest) in SOURCE_PINS.items():
        path = settings.parent / 'original-sources' / name
        require(len(checked(path, digest, 500_000)) == size, 'Original configuration size differs')
        evidence.append(record(path))
    keys = [(row['sourceEntry'], row['sourceRecordIndex']) for row in document['records']]
    require(len(set(keys)) == 82 and all(row['sourceSHA256'] == SOURCE_PINS[row['sourceEntry']][1]
            for row in document['records']), 'Original configuration identity differs')
    return document, evidence


def load_geometry(model, receipt_path, configs):
    raw = checked(model, STATIC_SHA, 16_000_000)
    receipt = json.loads(checked(receipt_path, STATIC_RECEIPT_SHA, 100_000))
    require(receipt['schema'] == 'erlang-static-source-geometry-receipt-v1'
            and receipt['sourceArchiveSHA256'] == ARCHIVE_SHA256
            and receipt['model'] == dict(file=model.name, bytes=len(raw), sha256=STATIC_SHA),
            'Static geometry receipt does not bind this model')
    g, binary = glb_read(model)
    require(not g.get('animations') and len(g['nodes']) == 89 and len(g['meshes']) == 8
            and len(g['skins']) == 1 and len(g['skins'][0]['joints']) == 80,
            'Expected the authenticated static source rig')
    bindings = receipt['geometry']['originalBoneBindings']
    names = {row['name']: row['targetNode'] for row in bindings}
    require(len(names) == len(bindings) == 80 and set(names.values()) == set(range(80))
            and all(g['nodes'][node]['name'] == name for name, node in names.items()),
            'Static source bone mapping differs')
    ids = {key: value for key, value in merge_bone_ids(*configs.values()).items() if value in names}
    require(ids == {row['sourceID']: row['name'] for row in bindings if row['sourceID'] is not None},
            'Static source IDs do not match the original bone documents')
    writer = Writer()
    writer.g = copy.deepcopy(g)
    writer.b = bytearray(binary[:g['buffers'][0]['byteLength']])
    return writer, names, ids, bindings, g, bytes(writer.b)


def verify_geometry_prefix(original, original_binary, actual, binary):
    require(binary[:len(original_binary)] == original_binary, 'Original static BIN bytes changed')
    for key in ('nodes', 'meshes', 'skins', 'materials', 'textures', 'images', 'samplers', 'scenes'):
        require(actual[key] == original[key], 'Original static geometry changed: ' + key)
    for key in ('accessors', 'bufferViews'):
        require(actual[key][:len(original[key])] == original[key], 'Original static records changed: ' + key)


def verify_clip(model, binary, clip, names, configs):
    """Recompute written GLB poses, COM and all original capsule endpoints."""
    animations = [row for row in model['animations'] if row['name'] == clip['name']]
    require(len(animations) == 1, 'Missing or duplicate animation')
    animation = animations[0]
    require(animation['extras']['sourceSHA256'] == clip['sha256'], 'GLB motion identity differs')
    require(sha(base64.b64decode(clip['sourceBytesBase64'], validate=True)) == clip['sha256'],
            'Retained original TextAsset bytes differ')
    config = clip['sourceConfiguration']['configuration']
    first, last, stride = source_window(config, clip['sourceUncroppedFrames'])
    require(clip['frames'] == last-first+1 and clip['sourceFirstIndex'] == first
            and clip['sourceLastIndex'] == last and clip['playbackTicks'] == (last-first)*stride
            and clip['sourceEndEventTick'] == source_end_event_tick(config, clip['sourceUncroppedFrames']),
            'Source animation crop or event clock differs')
    static = first == last
    if static:
        require(clip['name'] == 'staff_idle' and config['Animation'] == 'D15_Avatara_Transform_Out'
                and first == last == clip['playbackTicks'] == clip['sourceEndEventTick'] == 0
                and clip['sha256'] == '72da7978875aa9b288933add7c045cdc417938a6f9887a55d0e0efddcf7123e1',
                'Only the exact original one-key TransformOut is supported')
    mirror = clip['sourceMirrorApplied']
    rate = 60 if mirror else 30
    keys = 2*clip['frames']-1 if mirror else clip['frames']
    curves = {}
    for channel in animation['channels']:
        key = channel['target']['node'], channel['target']['path']
        require(key not in curves and key[1] in ('translation', 'rotation'), 'Unexpected GLB channel')
        sampler = animation['samplers'][channel['sampler']]
        times = accessor_read(model, binary, sampler['input']).reshape(-1)
        values = accessor_read(model, binary, sampler['output']).astype(float)
        require(sampler['interpolation'] == 'LINEAR' and len(times) == len(values) == keys
                and np.max(abs(times-np.arange(keys)/rate)) < 5e-7
                and np.isfinite(values).all(), 'Written source keys or time grid differ')
        curves[key] = values
    source_ids = {key: value for key, value in merge_bone_ids(*configs.values()).items() if value in names}
    expected_nodes = {names[source_ids[key]] for key in clip['sourceBoneIDs'] if key in source_ids}
    require(set(curves) == {(node, kind) for node in expected_nodes for kind in ('translation', 'rotation')},
            'Written GLB omits an original mapped bone')
    rest_world, rest, parents = world_poses(model['nodes'])
    weighted = sorted((names[name], weight) for name, weight in configs['base']['masses'].items() if weight > 0)
    shapes = clip['tracks']['collisionEdges'] + clip['tracks']['hurtCapsules']
    capsules = configs['weapon']['capsules'] + configs['fullBody']['capsules']
    require(len(shapes) == len(capsules) == 17 and len(weighted) == 58, 'Original physics inventory differs')
    sample_count = 2*clip['frames']-1
    for field in (*POINT_FIELDS, 'root', 'centerOfMass', 'groundLift',
                  'weaponBaseL', 'weaponTipL', 'weaponBaseR', 'weaponTipR'):
        require(len(clip['tracks'][field]) == sample_count, 'Missing source sample: ' + field)
    maximum, points = 0., 0

    def compare(expected, actual):
        nonlocal maximum, points
        error = float(np.max(abs(np.asarray(expected)-np.asarray(actual))))
        require(np.isfinite(error) and error < 2e-6, 'Written GLB/source FK mismatch')
        maximum = max(maximum, error)
        points += 1

    markers = []
    for side in ('l', 'r'):
        foot, toe = names['foot_'+side], names['toe_'+side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0])-.055, max(a[0], b[0])+.055):
            for z in (min(a[2], b[2])-.055, max(a[2], b[2])+.055):
                markers.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    for tick in range(sample_count):
        a, b, fraction = (tick, tick, 0) if mirror else (tick//2, min(clip['frames']-1, tick//2+1), (tick%2)/2)
        local = [value.copy() for value in rest]
        for node in expected_nodes:
            p = curves[node, 'translation'][a]*(1-fraction)+curves[node, 'translation'][b]*fraction
            q = curves[node, 'rotation'][a]*(1-fraction)+curves[node, 'rotation'][b]*fraction
            local[node] = matrix(p, q, model['nodes'][node].get('scale', [1, 1, 1]))
        world = pose_world(local, parents)
        for field, bone in POINT_FIELDS.items():
            compare((RIGHT @ world[names[bone]][:, 3])[:3], clip['tracks'][field][tick])
        accumulator, total = np.zeros(3, dtype=np.float32), np.float32(0)
        for node, mass in weighted:
            mass = np.float32(mass)
            accumulator = np.asarray(accumulator + np.asarray((RIGHT @ world[node][:, 3])[:3], dtype=np.float32)*mass,
                                     dtype=np.float32)
            total = np.float32(total+mass)
        compare(accumulator/total, clip['tracks']['centerOfMass'][tick])
        for capsule, shape in zip(capsules, shapes):
            require(capsule['id'] == shape['id'], 'Original capsule order/identity differs')
            for end in ('base', 'tip'):
                require(len(shape[end]) == sample_count, 'Missing capsule sample')
                point = capsule_point(capsule[end], world, names)
                compare(point, shape[end][tick])
                if capsule['id'].startswith('Spear_Attacking_Edge_'):
                    suffix = capsule['id'][-1].upper()
                    compare(point, clip['tracks'][('weaponBase' if end == 'base' else 'weaponTip')+suffix][tick])
        low = min((world[foot] @ marker)[1] for foot, marker in markers)
        compare(max(0., -.035-low), clip['tracks']['groundLift'][tick])
    return dict(clip=clip['name'], samples=sample_count, comparedPoints=points,
                maximumErrorMeters=maximum, headSamples=sample_count,
                sourceStaticPose=static, sourceMirrorApplied=mirror,
                sourceStride=stride, playbackTicks=clip['playbackTicks'])


def load_configs(args):
    configs, inputs, base_raw = {}, [], None
    for kind, (name, digest) in CONFIGS.items():
        path = (args.source_configs if kind == 'weapon' else args.shared_bones) / name
        raw = checked(path, digest, 1_000_000)
        configs[kind] = parse_bones_data(raw)
        if kind == 'base':
            base_raw = raw
            configs[kind]['masses'] = {b.get('Name'): float(b.get('Mass', '0')) for b in ET.fromstring(raw).findall('./Bones/Bone')}
        inputs.append(dict(kind=kind, **record(path)))
    return configs, inputs, base_raw


def build(args):
    require(not args.output.exists(), 'Refuse to replace an existing candidate')
    settings, settings_evidence = load_named(args.settings)
    configs, config_inputs, base_raw = load_configs(args)
    writer, names, ids, bindings, static, static_binary = load_geometry(args.geometry, args.geometry_receipt, configs)
    bundles, motions, load = local_source(args)
    selected = motion_rows(motions)
    require(len(ROLE_INPUTS) == len(selected) == 49, 'Reviewed body role inventory changed')
    source_objects = {}
    # Authenticate every selected object/config before exporting any file.
    for info in selected:
        source_record(settings, info['name'])
        matches = [obj for obj in load(info['bundle']).objects if obj.path_id == info['path_id']]
        require(len(matches) == 1 and matches[0].type.name == 'TextAsset', 'Exact source motion object is missing')
        source = matches[0].read().m_Script
        raw = source.encode('utf8', 'surrogateescape') if isinstance(source, str) else bytes(source)
        require(len(raw) == info['bytes'] and sha(raw) == info['sha256'], 'Exact source motion bytes differ')
        source_objects[info['name']] = raw
    clips = []
    for info in selected:
        clips.append(append_motion(writer, names, ids, configs, info, source_objects[info['name']],
                                   source_record(settings, info['name'])))
        print('RECOVERED', info['name'], clips[-1]['frames'], flush=True)
    mirror_rows = [row for row in settings['records'] if row['sourceEntry'] == 'settings_style_imperial_spear.bytes'
                   and row['sourceRecordIndex'] == 10]
    require(len(mirror_rows) == 1 and mirror_rows[0]['configuration']['Animation'] == 'Imperial_Spear_Heavy_Slash_Passive_Mirror'
            and mirror_rows[0]['configuration']['Mirrored'] == -1, 'Exact original mirror alias differs')
    info = next(row for row in selected if row['name'] == 'imperial_spear_heavy_slash_passive')
    clips.append(append_motion(writer, names, ids, configs, info, source_objects[info['name']],
                              mirror_rows[0], mirror_rules=body_rules(base_raw), export_name=MIRROR_CLIP))
    roles = {role: value[0] for role, value in ROLE_INPUTS.items()}
    roles[MIRROR_ROLE] = MIRROR_CLIP
    writer.g['asset']['generator'] = 'Authenticated recovered WuYong body animation source'
    writer.g['extras'] = dict(writer.g.get('extras', {}), schema='erlang-recovered-body-animations-v1',
        **BOUNDARY, recoveredNamedSourceSHA256=NAMED_SHA, sourceAnimationCount=50,
        humanAnimationsIncluded=True)
    profile = dict(schema='erlang-recovered-body-animation-profile-v1', id=ID, hero=ID,
        faction='Dynasty', resourceName=RESOURCE, bodyID='arm__agl_44', weaponID='wpn__agl_spear_01_01',
        activeWeaponSides=['left', 'right'], roles=roles, clips=clips,
        sourceSkinNodeCount=80, sourceBoneBindings=bindings,
        comboLinks=[{'from':row['from_'], 'to':row['to'], 'sourceFrame':row['sourceFrame']} for row in COMBO_LINKS],
        recoveryBoundary=BOUNDARY)
    profile['combatRules'], attacks = combat_rules(profile, settings)
    output = private_output(args.output)
    model_path = output / (RESOURCE+'.glb')
    profile.update(writer.save(model_path)); model_path.chmod(0o600)
    written, binary = glb_read(model_path)
    verify_geometry_prefix(static, static_binary, written, binary)
    require(len(written['animations']) == len(clips) == len(roles) == 50, 'Animated output inventory differs')
    readback = [verify_clip(written, binary, clip, names, configs) for clip in clips]
    mirror, normal = clips[-1], next(c for c in clips if c['name'] == 'imperial_spear_heavy_slash_passive')
    mirror_difference = float(np.max(abs(np.asarray(mirror['tracks']['toeL'])-np.asarray(normal['tracks']['toeL']))))
    require(mirror_difference > .001, 'Mirrored passive is an unmodified duplicate')
    write_new(output / PROFILE, encoded(profile))
    receipt = dict(schema='erlang-recovered-body-animation-receipt-v1',
        character=record(model_path), profile=record(output/PROFILE),
        sourceStaticGeometry=record(args.geometry), sourceStaticReceipt=record(args.geometry_receipt),
        sourceArchiveSHA256=ARCHIVE_SHA256, sourceNamed=record(args.settings),
        sourceNamedEvidence=settings_evidence, sourceBoneConfigs=config_inputs,
        sourceBundles=[{key: bundles[name][key] for key in ('file', 'bytes', 'sha256')}
                       for name in sorted({row['bundle'] for row in selected})],
        motions=[{key: row[key] for key in ('name', 'bundle', 'path_id', 'bytes', 'sha256', 'frames')} for row in selected],
        originalSourceObjects=49, originalBodyRoles=49, sourceMirrorVariants=1,
        unchangedStaticBinaryBytes=len(static_binary), unchangedGeometryMaterialsSkinsAndPortrait=True,
        sourcePhysicalAttackBindings=attacks, readback=readback,
        maximumErrorMeters=max(row['maximumErrorMeters'] for row in readback),
        comparedPoints=sum(row['comparedPoints'] for row in readback),
        headSamples=sum(row['headSamples'] for row in readback),
        maximumMirroredToeDifferenceMeters=mirror_difference,
        boundaries=BOUNDARY,
        remainingInputsAndBindings=[
            'Authenticated six-role paired-throw reference policy/catalogue and Wu-specific paired geometry.',
            'Separate original Stun/root-victim additions, with their exact source configurations.',
            'Explicit personal neck bridge and pose/render acceptance; portrait arrays remain unchanged.',
            'D15 ability/model rules, companion/effect/audio bindings to this new profile identity.',
            '302-file release closure, current App identity and native/GPU acceptance; none bypassed.'])
    receipt_path = output/'animated-body-receipt-private.json'
    write_new(receipt_path, encoded(receipt))
    return dict(character=record(model_path), profile=record(output/PROFILE), receipt=record(receipt_path),
                clips=50, readbackPoints=receipt['comparedPoints'], headSamples=receipt['headSamples'],
                maximumErrorMeters=receipt['maximumErrorMeters'], boundary=BOUNDARY)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-archive', 'source-bundles', 'source-configs', 'shared-bones',
                 'settings', 'geometry', 'geometry-receipt', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
