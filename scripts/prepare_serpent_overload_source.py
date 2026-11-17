#!/usr/bin/env python3
"""Recover D13's exact Overload body clip into a private, inactive candidate.

Reads only authenticated members of existing local archives. The full source
alias, container path, PathID, bytes and SHA-256 must agree. No network, keys,
existing-resource overwrite, release pin change or runtime activation occurs.
This closes body-source availability, not Bloom gameplay or native acceptance.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path
import stat
import struct
import warnings
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import numpy as np

from build_erlang_source_assets import encoded, record, sha, write_new
from build_serpent_source_geometry import BONES, load_bones
from erlang_source_profile import source_end_event_tick, source_window
from prepare_erlang_animated_body import verify_geometry_prefix
from prepare_serpent_animated_body import append_motion, resolve_original, verify_clip
from prepare_serpent_named_settings import AnimationProjection, member, pinned, typed
from source_floorfall_audio import Storage, compact
from sun_triad_assets import Writer, decode, glb_read, require, validate_container
from sun_triad_source_bones import merge_bone_ids

REPOSITORY = Path(__file__).resolve().parents[1]
ALIAS = 'Set_Legion_3_Shadow_Form_In'
SOURCE_PATH = 'unique_moves/sets/sets_moth_roar.bin'
CONTAINER = 'assets/gamedata/resources/content/animations/binaries/unique_moves/sets/sets_moth_roar.bytes'
BUNDLE = '9893dca6e10355eb9c3c79d1613f08b1.bin'
PATH_ID = 3582625690775438110
MOTION = 'sets_moth_roar'
OUTPUT_MODEL = 'Liu_KingOfSerpents_D13_Overload_Source.glb'
PINS = {
    'splits': (17325877, '02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a'),
    'animationSplit': (1110598, 'efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29'),
    'battleSplit': (16429699, 'c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b'),
    'overloadLock': (26106, '7af8a563d7738511bbc7eac9e3f325732ddb56c0a1b61dce36c9128b0bdb2e8f'),
    'schema': (11577, 'f8687443bcf2da87ff3c9f5d7c2059cb2dbe851a9a33c776655477e750b85111'),
    'settings': (335308, '0ce568c982adbba7b157cf5a5c72922e3f889b4cdaf1bac95c03f8ec38e979bf'),
    'geometry': (6117296, 'b9d2b7a9696dc5a500bc3d51678e2133c80075d077d82d5b218a3cd4584e26c1'),
    'geometryReceipt': (28174, '84bf812a3802978f90d9224add871fb5435478e72a75420be5935b31f4a9dd03'),
    'motionCatalog': (3008671, '09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8'),
    'bundleCatalog': (9100700, '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'),
    'bundle': (14681877, 'd6f2efe8ce772b953f610583ab5fb8963fb27abcccfec4b3aeccce8be973dd42'),
    'motion': (75442, '95494d2fb96b2642a89b3c9c14e389eb922fc81377fcd6edca837255ea26f40c'),
}
CHECKPOINT_MEMBERS = {
    'splits': 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip',
    'schema': 'recovered-erlang-named-animations-v1/animation-schema-recovered-private.json',
    'geometry': 'continued-20261116/serpent-static-geometry-v1/Liu_KingOfSerpents_D13_Static_Source.glb',
    'geometryReceipt': 'continued-20261116/serpent-static-geometry-v1/receipt-private.json',
}
BOUNDARY = dict(sourceOnly=True, runtimeBound=False, abilityRulesBound=False,
    productionActivated=False, nativeRenderingVerified=False, originalGameExecuted=False,
    networkBytes=0, decryptionPerformed=False, uploadedObjects=0, testFlightUploaded=False)


def checked_member(archive, name, pin):
    return pinned(member(archive, name, pin[0]), pin, name)


def regular_archive(path):
    path = Path(path)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), 'Use a regular local archive')
    return ZipFile(path)


def source_configuration(splits, schema):
    pinned(splits, PINS['splits'], 'decoded splits')
    pinned(schema, PINS['schema'], 'native field schema')
    with ZipFile(io.BytesIO(splits)) as archive:
        split = checked_member(archive, 'splits/split_animation_settings.bytes', PINS['animationSplit'])
    with ZipFile(io.BytesIO(split)) as archive:
        raw = checked_member(archive, 'settings_sets_legion.bytes', PINS['settings'])
    reader = Storage(raw)
    rows = reader.value(reader.root)
    require(reader.pos == len(raw) and type(rows) is list, 'Unconsumed or invalid animation source')
    require([i for i, row in enumerate(rows) if type(row) is list and row and row[0] == ALIAS] == [12],
            'Original alias is missing, duplicated, or moved')
    projection = AnimationProjection(schema)
    config = projection.named(rows[12])
    reparsed = json.loads(encoded(config))
    require(typed(rows[12]) == typed(projection.unnamed(reparsed)), 'Lossy source field projection')
    validate_configuration(reparsed)
    source = dict(sourceEntry='settings_sets_legion.bytes', sourceSHA256=PINS['settings'][1],
        sourceRecordIndex=12, configuration=reparsed)
    return source, dict(sourceTypedValueSHA256=sha(encoded(typed(rows[12]))),
        roundTripTypedValueSHA256=sha(encoded(typed(projection.unnamed(reparsed)))),
        namedConfigurationSHA256=sha(encoded(reparsed)), allOriginalFieldsAndTypesPreserved=True)


def validate_configuration(config):
    require(config['Animation'] == ALIAS and config['FileName'] == SOURCE_PATH,
            'D13 Overload alias must resolve to its exact original path')
    require(all(config[key] is None for key in ('FirstFrame', 'EndFrame', 'MidFrames', 'SelfEndFrame', 'Mirrored')),
            'Unreviewed Overload crop, clock, or mirroring')
    markers = {r['Name']: (r['Start'], r['End']) for r in config['Intervals']}
    require(len(markers) == 7 and markers['D13_Bloom_Overload_Effect'] == (8, 8)
            and markers['D13_Bloom_Overload'] == (28, 28), 'Original Overload marker identity differs')


def source_invocation(splits):
    """Verify that D13 really requests this shared original body alias."""
    pinned(splits, PINS['splits'], 'decoded splits')
    with ZipFile(io.BytesIO(splits)) as archive:
        raw = checked_member(archive, 'splits/split_battle_triggers.bytes', PINS['battleSplit'])
    with ZipFile(io.BytesIO(raw)) as archive:
        raw = checked_member(archive, 'lock_1389.bytes', PINS['overloadLock'])
    reader = Storage(raw)
    rows = reader.value(reader.root)
    require(reader.pos == len(raw), 'Unconsumed original trigger bytes')
    trigger = rows[0]['fields'][1][14]
    require(trigger['kind'] == 'TriggerData' and len(trigger['fields']) == 6,
            'Original D13 invocation layout differs')
    fields = compact(trigger['fields'])
    require(fields[2] == 402 and fields[5][-1] == {'a6': [ALIAS, None, None]},
            'D13 no longer invokes the exact original body alias')
    require(fields[3] == [{'a17': ['enum65537', 'Uninterrupt']},
                         {'a1': ['STANCE_IDLE', 'enum65537']},
                         {'a44': ['enum65537', 'SET_DYNASTY_13_BLOOM_CHECK']}],
            'Original D13 invocation event gate differs')
    require(fields[5][0] == {'a171': ['SET_D13_BLOOM_OVERLOAD', 'enum65537', 1.0, None, True]},
            'Original overload state-write ordering differs')
    return dict(sourceFile='lock_1389.bytes', bytes=len(raw), sha256=sha(raw),
        sourceSetIndex=0, sourceTriggerIndex=14, sourcePriority=402,
        sourceTypedTriggerSHA256=sha(encoded(typed(trigger))),
        originalAlias=ALIAS, sourceActionCode='a6', sourceEventCodes=['a17', 'a1', 'a44'],
        stateWriteBeforeBodyAnimation=True, sourceConditionsRetainedByPinnedOriginal=True,
        invocationGateImplemented=False, intervalEventDispatchImplemented=False,
        caution='Full Bloom value is not the separate IntervalStart D13_Bloom_Overload event in trigger16.')


def read_motion(archive_path, source):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    with regular_archive(archive_path) as archive:
        motions = json.loads(checked_member(archive, 'research/motion_catalog.json', PINS['motionCatalog']))['motions']
        catalog_raw = checked_member(archive, 'research/android_bundle_catalog.jsonl', PINS['bundleCatalog'])
        bundles = [json.loads(line) for line in catalog_raw.splitlines() if line.strip()]
        selected = [r for r in motions if r['name'] == MOTION]
        selected_bundles = [r for r in bundles if r['file'] == BUNDLE]
        require(len(selected) == len(selected_bundles) == 1, 'Ambiguous original catalog identity')
        info, bundle_info = selected[0], selected_bundles[0]
        require((info['bundle'], info['path_id'], info['bytes'], info['sha256'], info['frames'], info['arrays'])
                == (BUNDLE, PATH_ID, *PINS['motion'], 54, 2), 'Original motion catalog pin differs')
        require((bundle_info['bytes'], bundle_info['sha256']) == PINS['bundle'], 'Original bundle pin differs')
        paths = [r for r in bundle_info['paths'] if r['path'] == CONTAINER]
        require(len(paths) == 1 and (paths[0]['file_id'], paths[0]['path_id']) == (0, PATH_ID),
                'Original full container path and PathID disagree')
        bundle = checked_member(archive, 'bundles/' + BUNDLE, PINS['bundle'])
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', category=Warning)
        environment = UnityPy.load(bundle)
    require(CONTAINER in environment.container and environment.container[CONTAINER].m_PathID == PATH_ID,
            'Actual source bundle lacks the exact original object')
    actual, raw = resolve_original(source, selected, lambda name: environment if name == BUNDLE else None)
    pinned(raw, PINS['motion'], 'Overload body motion')
    arrays = decode(raw)
    require(len(arrays) == 2 and arrays[0]['frame_count'] == 54, 'Original two-array layout differs')
    for array in arrays:
        require(np.isfinite(array['positions']).all() and np.isfinite(array['rotations']).all()
                and np.all(np.linalg.norm(array['rotations'], axis=-1) > 0), 'Invalid original motion values')
    return actual, raw, [dict(frames=a['frame_count'], boneTracks=len(a['bone_ids'])) for a in arrays]


def build(args):
    output = args.output.resolve()
    require(not output.exists() and output != REPOSITORY and REPOSITORY not in output.parents,
            'Use a new private output directory outside the repository')
    inputs, bones = {}, {}
    with regular_archive(args.checkpoint) as archive:
        for key, name in CHECKPOINT_MEMBERS.items():
            inputs[key] = checked_member(archive, name, PINS[key])
        for kind, (name, digest) in BONES.items():
            parent = 'recovered-shared-bones/' if kind in ('base', 'fullBody') else 'continued-20261116/serpent-source-inputs-v1/'
            raw = member(archive, parent + name, 100000)
            require(sha(raw) == digest, 'Original bone configuration pin differs')
            require(b'<!DOCTYPE' not in raw and b'<!ENTITY' not in raw, 'External XML is unsupported')
            bones[name] = raw
    source, projection = source_configuration(inputs['splits'], inputs['schema'])
    invocation = source_invocation(inputs['splits'])
    info, raw, array_summary = read_motion(args.motions, source)
    receipt = json.loads(inputs['geometryReceipt'])
    require(receipt['character']['sha256'] == PINS['geometry'][1], 'D13 source geometry receipt differs')
    output.mkdir(parents=True, mode=0o700)
    originals = output / 'original-sources'
    originals.mkdir(mode=0o700)
    for name, value in bones.items():
        write_new(originals / name, value)
    static_path = originals / 'D13-static.glb'
    write_new(static_path, inputs['geometry'])
    static, binary = glb_read(static_path)
    require(struct.unpack_from('<4sII', inputs['geometry']) == (b'glTF', 2, len(inputs['geometry'])),
            'Original GLB header differs')
    require(len(static['nodes']) == 90 and len(static['skins'][0]['joints']) == 80 and not static['animations'],
            'Original D13 static rig differs')
    validate_container(static, binary[:static['buffers'][0]['byteLength']])
    writer = Writer()
    writer.g = copy.deepcopy(static)
    writer.b = bytearray(binary[:static['buffers'][0]['byteLength']])
    original_binary = bytes(writer.b)
    bindings = receipt['originalBoneBindings']
    names = {r['name']: r['targetNode'] for r in bindings}
    configs = load_bones(originals, originals)
    configs.pop('ranged')
    configs['base']['masses'] = {b.get('Name'): float(b.get('Mass', '0'))
        for b in ET.fromstring(bones[BONES['base'][0]]).findall('./Bones/Bone')}
    ids = {i: n for i, n in merge_bone_ids(*configs.values()).items() if n in names}
    require(ids == {r['sourceID']: r['name'] for r in bindings if r['sourceID'] is not None},
            'Original D13 bone mapping differs')
    clip = append_motion(writer, names, ids, configs, info, raw, source, MOTION)
    writer.g['asset']['generator'] = 'D13 exact Overload source candidate; inactive'
    writer.g['extras'].update(**BOUNDARY, sourceAnimationCount=1, sourceAlias=ALIAS)
    model = output / OUTPUT_MODEL
    writer.save(model)
    model.chmod(0o600)
    actual, actual_binary = glb_read(model)
    verify_geometry_prefix(static, original_binary, actual, actual_binary)
    readback = verify_clip(actual, actual_binary, clip, names, ids, configs)
    first, last, stride = source_window(source['configuration'], info['frames'])
    events = [dict(name=r['Name'], sourceStart=r['Start'], sourceEnd=r['End'],
        intervalStartTick=max(0, ((r['Start'] or 1)-1-first) * stride))
        for r in source['configuration']['Intervals']]
    profile = dict(schema='d13-overload-source-clip-candidate-v1', id='liu_serpent', hero='liu',
        sourceBoneBindings=bindings, sourceSkinNodeCount=80, clips=[clip], recoveryBoundary=BOUNDARY)
    write_new(output / 'D13_Overload_Source_Profile.json', encoded(profile))
    report = dict(schema='d13-overload-source-verification-v1', hero='刘泉纬', profileID='liu_serpent',
        originalAlias=ALIAS, originalFileName=SOURCE_PATH, originalContainerPath=CONTAINER,
        originalBundle=BUNDLE, sourcePathID=str(PATH_ID), sourceRecordIndex=12,
        inputPins={key: dict(bytes=value[0], sha256=value[1]) for key, value in PINS.items()},
        projection=projection, sourceInvocation=invocation,
        sourceArrays=array_summary, sourceBoneTracks=len(clip['sourceBoneIDs']),
        glTFHeader=dict(magic='glTF', version=2, declaredLength=model.stat().st_size),
        sourceSkinJoints=80, candidateAnimations=1, sourceFrames=54,
        sourceFirstIndex=first, sourceLastIndex=last, sourceFrameStride=stride,
        lastSampleTick=clip['playbackTicks'], sourceEndEventTick=source_end_event_tick(source['configuration'], 54),
        events=events, sourceFKReadback=readback, unchangedOriginalGeometryMaterialsSkinAndPersonalPortrait=True,
        products=[record(model), record(output / 'D13_Overload_Source_Profile.json')],
        acceptedRuntimeProfileUnchanged=True, acceptedRuntimeClipCount=66,
        blockedBy=['Not bound into the authenticated production actor/profile and related media pins.',
            'Automatic full-Bloom transition and native interval-event dispatch remain unverified.',
            'Bloom model contact, MagicPower/BodyDefense and final Hit pipeline remain incomplete.',
            'Original Align/SetDirection/WeaponSwitch and interrupt behavior require native regression.',
            'No simulator, device, multiplayer or rendering evidence produced by this source compiler.'],
        boundary=BOUNDARY)
    write_new(output / 'verification-public.json', encoded(report))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--motions', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    report = build(parser.parse_args())
    print(json.dumps(dict(products=report['products'], readback=report['sourceFKReadback'],
        sourceFrames=report['sourceFrames'], sourceEndEventTick=report['sourceEndEventTick'],
        boundary=report['boundary']), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
