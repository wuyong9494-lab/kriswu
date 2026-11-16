#!/usr/bin/env python3
"""Recover original common paired/reaction inputs and append them to WuYong.

The contract subcommand is independent of a character rig. Its throw_policy
function consumes that contract plus each character's own source FK, so another
rig need not borrow WuYong's foot/pelvis/root positions. No historical derived
catalogue hash is forged and no old builder/release gate is altered.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path
import struct
from zipfile import ZipFile

from build_erlang_source_assets import append_motion, checked, encoded, local_source, record, sha, write_new
from erlang_source_profile import rounded, source_window
from prepare_erlang_animated_body import load_configs, verify_clip, verify_geometry_prefix
from prepare_fighter_target_motions import ARCHIVE_SHA256
from source_floorfall_audio import ANIMATION_FIELDS, Storage, compact
from sun_triad_assets import Writer, glb_read, private_output, require


SPLITS_SHA = '02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a'
ANIMATION_SPLIT_SHA = 'efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29'
TRIGGER_SPLIT_SHA = 'c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b'
SCHEMA_SHA = 'f8687443bcf2da87ff3c9f5d7c2059cb2dbe851a9a33c776655477e750b85111'
RECOVERED_CONTRACT_SHA = '04ae077c5cfb225ff0e794614bec3c15e2142285e885e45257f1e4c93f0ab79c'
SOURCES = {
    'moves_settings.bytes': (86885, 'fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b'),
    'settings_sets_dynasty.bytes': (334225, '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'),
    'settings_sets_heralds.bytes': (399607, '64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a'),
    'lock_923.bytes': (276605, 'c2fe1f2fa5b4a0a8b457de20608334d9202b959b832b72317860adf0d8c9cba2'),
    'lock_2568.bytes': (7118, '808901236e60f20fa88a8ab2d4e07246caebe99814b94ab53d4eb3c9993874b7'),
    'lock_2567.bytes': (4670, 'f163a08a77134c3cf4ec618dca553a6ce9f05b9d977b054153024322dce1a3ea'),
    'lock_945.bytes': (3485, 'd2e7990ce3fb6de2cbbf8b00853ca422edd5fd428274bffd0abc5ed167bf7dba'),
    'lock_1544.bytes': (10347, 'ec56d114b475aa7546fb056595edcb167156e458423dbb82967a02a49f9351ca'),
    'lock_1545.bytes': (9700, '073e0dc18d278aa518fa0f2dbf502b2afc77cfd3ea65c56136a4216c25a4fb42'),
}
# Legacy API role names keep paired interoperability; they do not select D19
# as a playable character or give a D15/D13 actor any D19 power.
SELECTIONS = (
    ('ordinaryThrowBack', 'moves_settings.bytes', 81, 'Throw_Simple', 'throw_p'),
    ('ordinaryThrownBack', 'moves_settings.bytes', 82, 'Throw_Passive', 'throw_e'),
    ('ordinaryThrowForward', 'moves_settings.bytes', 83, 'Throw_Forward_Active', 'throw_front_a'),
    ('ordinaryThrownForward', 'moves_settings.bytes', 84, 'Throw_Forward_Passive', 'throw_front_b'),
    ('ordinaryPanguEscape', 'settings_sets_dynasty.bytes', 248, 'D19_Unthrow', 'sven_throw_break_active'),
    ('ordinaryPanguResisted', 'settings_sets_dynasty.bytes', 249, 'D19_Unthrow_Passive', 'sven_throw_break_passive'),
    ('sourceStunIn', 'moves_settings.bytes', 87, 'Stun_In', 'h_stun_start'),
    ('sourceStunLoop', 'moves_settings.bytes', 88, 'Stun_Loop', 'h_stun_loop'),
    ('sourceStunOut', 'moves_settings.bytes', 89, 'Stun_Out', 'h_stun_end'),
    (None, 'settings_sets_heralds.bytes', 102, 'H17_Root_Spike_Passive_Start', 'h17_root_spike_passive_start'),
    (None, 'settings_sets_heralds.bytes', 103, 'H17_Root_Spike_Passive_Loop', 'h17_root_spike_passive_loop'),
    (None, 'settings_sets_heralds.bytes', 104, 'H17_Root_Spike_Passive_End', 'h17_root_spike_passive_end'),
)
THROW_KEYS = ('backActive', 'backPassive', 'forwardActive', 'forwardPassive', 'panguActive', 'panguPassive')
EXPECTED_THROW_CLOCKS = ((100, 92, 88), (82, 74, 83), (164, 156, 165),
                         (160, 152, 161), (162, 154, 146), (120, 112, 121))
TRIGGER_SELECTIONS = (
    ('lock_923.bytes', 'THROW_Simultaneous', 0),
    ('lock_923.bytes', 'THROW_Basic_Active', 0),
    ('lock_923.bytes', 'THROW_Basic_Passive', 0),
    ('lock_923.bytes', 'THROW_Forward_Passive', 0),
    ('lock_2568.bytes', 'THROW_Forward_Active', 0),
    ('lock_2567.bytes', 'THROW_Simultaneous_Random', 0),
    ('lock_945.bytes', 'ANTI_THROW', 0),
    ('lock_1544.bytes', 'SET_DYNASTY_19_1_LEVEL', 1),
    ('lock_1545.bytes', 'SET_DYNASTY_19_ENEMY_THROW', 0),
    ('lock_1545.bytes', 'SET_DYNASTY_19_ENEMY_THROW', 1),
)


def typed(value):
    kind = type(value)
    if value is None:
        return ['null']
    if kind is bool:
        return ['bool', value]
    if kind is int:
        return ['int', value]
    if kind is float:
        return ['float64', struct.pack('>d', value).hex()]
    if kind is str:
        return ['string', value]
    if kind is list:
        return ['list', [typed(item) for item in value]]
    require(kind is dict and all(type(k) is str for k in value), 'Unsupported typed source value')
    return ['dict', [[key, typed(item)] for key, item in value.items()]]


def schema_fields(path):
    schema = json.loads(checked(path, SCHEMA_SHA, 30_000))
    require(schema['nativeMethod'] == 16684 and schema['nativeExecuted'] is False,
            'Expected the recovered original animation constructor schema')
    def children(prefix):
        names = [row['name'] if not prefix else row['name'][len(prefix)+1:]
                 for row in schema['fields'] if not prefix or row['name'].startswith(prefix+'.')]
        return tuple(name.removesuffix('[]') for name in names if '.' not in name)
    fields = {key: children(prefix) for key, prefix in (
        ('animation', ''), ('interval', 'Intervals[]'), ('damage', 'Intervals[].Damage'),
        ('sound', 'Sounds[]'), ('gender', 'Sounds[].Gender'), ('floor', 'Sounds[].Floor'))}
    require(fields['animation'] == ANIMATION_FIELDS
            and [len(fields[k]) for k in fields] == [29, 28, 5, 4, 3, 4], 'Original schema fields differ')
    return fields


def name_animation(raw, fields):
    def mapping(value, kind):
        require(type(value) is list and len(value) == len(fields[kind]), 'Original field count differs')
        return dict(zip(fields[kind], copy.deepcopy(value)))
    named = mapping(raw, 'animation')
    if named['Intervals'] is not None:
        named['Intervals'] = [mapping(row, 'interval') for row in named['Intervals']]
        for row in named['Intervals']:
            if row['Damage'] is not None:
                row['Damage'] = mapping(row['Damage'], 'damage')
    if named['Sounds'] is not None:
        named['Sounds'] = [mapping(row, 'sound') for row in named['Sounds']]
        for row in named['Sounds']:
            for key in ('Gender', 'Floor'):
                if row[key] is not None:
                    row[key] = mapping(row[key], key.lower())
    # Independently reverse the actual JSON projection, preserving null/bool/
    # integer and exact binary64 values, rather than filling guessed defaults.
    parsed = json.loads(encoded(named))
    reverse = copy.deepcopy(parsed)
    if reverse['Intervals'] is not None:
        for row in reverse['Intervals']:
            if row['Damage'] is not None:
                row['Damage'] = [row['Damage'][key] for key in fields['damage']]
        reverse['Intervals'] = [[row[key] for key in fields['interval']] for row in reverse['Intervals']]
    if reverse['Sounds'] is not None:
        for row in reverse['Sounds']:
            for key in ('Gender', 'Floor'):
                if row[key] is not None:
                    row[key] = [row[key][child] for child in fields[key.lower()]]
        reverse['Sounds'] = [[row[key] for key in fields['sound']] for row in reverse['Sounds']]
    original_typed = typed(raw)
    require(typed([reverse[key] for key in fields['animation']]) == original_typed, 'Lossy original configuration projection')
    return parsed, sha(encoded(original_typed))


def member(archive, name):
    rows = [row for row in archive.infolist() if row.filename == name]
    size, digest = SOURCES[name]
    require(len(rows) == 1 and rows[0].file_size == size and not rows[0].flag_bits & 1,
            'Exact original archive member differs: '+name)
    raw = archive.read(rows[0])
    require(len(raw) == size and sha(raw) == digest, 'Original member hash differs: '+name)
    return raw


def contains(value, expected):
    if typed(value) == typed(expected):
        return True
    if isinstance(value, dict):
        return any(contains(item, expected) for item in value.values())
    if isinstance(value, list):
        return any(contains(item, expected) for item in value)
    return False


def verify_trigger_semantics(selected):
    by_name = {(row['setName'], row['triggerIndex']): row['trigger'] for row in selected}
    basic = by_name['THROW_Basic_Active', 0]
    forward = by_name['THROW_Forward_Active', 0]
    def point(owner, kind, side=None):
        return {'f17': [{'f24': [{'f74': [owner]}, kind, side]}]}
    me, enemy = 'enum65537', 'enum65538'
    distance = [point(me, 'COM'), point(enemy, 'COM'), 'op1', 'op13', 102.0, 'op21']
    front = [point(enemy, 'COM'), point(me, 'Wall', 'Front'), 'op1', 'op13', 150.0, 'op21']
    back = [point(me, 'COM'), point(enemy, 'Wall', 'Front'), 'op1', 'op13', 100.0, 'op21']
    require(contains(basic[4], distance) and contains(forward[4], distance)
            and contains(basic[4], front) and contains(forward[4], back), 'Original range/wall branch differs')
    for name, alias in [('THROW_Basic_Active', 'Throw_Simple'), ('THROW_Basic_Passive', 'Throw_Passive'),
                        ('THROW_Forward_Active', 'Throw_Forward_Active'), ('THROW_Forward_Passive', 'Throw_Forward_Passive')]:
        require(contains(by_name[name, 0][-1], {'a6': [alias, None, None]}), 'Original pairing alias differs')
    lottery = by_name['THROW_Simultaneous_Random', 0]
    require(lottery[2] == 2002 and lottery[-1] == [
        {'a171': ['Throw_Simultaneous_Random', me, {'f14': [1, 99]}, 1, None]},
        {'a171': ['Throw_Simultaneous_Random', enemy,
                  [99.0, {'f82': [{'f51': ['Me', 'Throw_Simultaneous_Random']}]}, 'op1'], 1, None]}],
        'Original complementary simultaneous lottery differs')
    disabled = by_name['ANTI_THROW', 0]
    require(disabled[3] == [{'a0': ['Throw_Forward_Passive', me]}, {'a0': ['Throw_Passive', me]}]
            and disabled[-1] == [{'a171': ['THROW_DISABLED', enemy, 1.0, 105, None]}],
            'Original passive-end disabled interval differs')
    require(contains(by_name['SET_DYNASTY_19_1_LEVEL', 1][-1], {'a6': ['D19_Unthrow', None, None]})
            and all(contains(by_name['SET_DYNASTY_19_ENEMY_THROW', i][-1],
                             {'a6': ['D19_Unthrow_Passive', None, None]}) for i in (0, 1)),
            'Original D19 interoperability pairing differs')
    return dict(maximumRangeSourceUnits=102, forwardWallThresholdSourceUnits=150,
                backWallThresholdSourceUnits=100, throwDisabledAfterVictimEndTicks=105,
                simultaneousContactPolicy='sourceComplementaryLottery')


def recover_contract(args):
    require(not args.output.exists(), 'Refuse to replace an existing source contract')
    fields = schema_fields(args.schema)
    splits = checked(args.decoded_splits, SPLITS_SHA, 20_000_000)
    with ZipFile(io.BytesIO(splits)) as archive:
        animation = archive.read('splits/split_animation_settings.bytes')
        triggers = archive.read('splits/split_battle_triggers.bytes')
    require(sha(animation) == ANIMATION_SPLIT_SHA and sha(triggers) == TRIGGER_SPLIT_SHA,
            'Exact decoded source split differs')
    archive_raw = checked(args.source_archive, ARCHIVE_SHA256, 256*1024*1024)
    with ZipFile(io.BytesIO(archive_raw)) as archive:
        motions = json.loads(archive.read('research/motion_catalog.json'))['motions']
        bundle_catalog = {row['file']: row for row in map(json.loads, archive.read('research/android_bundle_catalog.jsonl').splitlines())}
        available = set(archive.namelist())
    original_files, source_values = {}, {}
    with ZipFile(io.BytesIO(animation)) as archive:
        for name in sorted({row[1] for row in SELECTIONS}):
            raw = member(archive, name)
            reader = Storage(raw)
            source_values[name] = reader.value(reader.root)
            original_files[name] = raw
    records = []
    for role, entry, index, alias, motion_name in SELECTIONS:
        config, typed_hash = name_animation(source_values[entry][index], fields)
        require(config['Animation'] == alias and Path(config['FileName']).stem == motion_name,
                'Exact source alias does not select its motion')
        rows = [row for row in motions if row['name'] == motion_name]
        require(len(rows) == 1 and 'bundles/'+rows[0]['bundle'] in available,
                'Missing/ambiguous fully cached original motion')
        info = rows[0]
        records.append(dict(role=role, sourceEntry=entry, sourceSHA256=SOURCES[entry][1],
            sourceRecordIndex=index, configuration=config, typedRoundTripSHA256=typed_hash,
            motion={key: info[key] for key in ('name', 'bundle', 'path_id', 'bytes', 'sha256', 'frames')},
            motionBundle={key: bundle_catalog[info['bundle']][key] for key in ('file', 'bytes', 'sha256')}))
    trigger_values, selected = {}, []
    with ZipFile(io.BytesIO(triggers)) as archive:
        for entry in sorted({row[0] for row in TRIGGER_SELECTIONS}):
            raw = member(archive, entry)
            reader = Storage(raw)
            trigger_values[entry] = compact(reader.value(reader.root))
            original_files[entry] = raw
    for entry, name, index in TRIGGER_SELECTIONS:
        rows = [(i, row['TriggerSetData']) for i, row in enumerate(trigger_values[entry])
                if row['TriggerSetData'][0] == name]
        require(len(rows) == 1, 'Missing/ambiguous exact source trigger set')
        set_index, fields = rows[0]
        selected.append(dict(sourceEntry=entry, sourceSHA256=SOURCES[entry][1], setIndex=set_index,
                             setName=name, triggerIndex=index, trigger=fields[1][index]['TriggerData']))
    semantics = verify_trigger_semantics(selected)
    contract = dict(schema='recovered-common-combat-source-contract-v1', sourceVersion='1.46.0.16.16733-prod',
        sourceDecodedSplitsSHA256=SPLITS_SHA, sourceMotionArchiveSHA256=ARCHIVE_SHA256,
        sourceAnimationSchemaSHA256=SCHEMA_SHA, sourceInputs=[dict(file=name, bytes=len(raw), sha256=sha(raw))
            for name, raw in sorted(original_files.items())], records=records,
        triggers=selected, throwSemantics=semantics,
        applicationAdapter=dict(normalizedUnarmedPower=1000, millimetersPerSourceUnitNumerator=92,
            millimetersPerSourceUnitDenominator=10, geometryUnitReason='Actual actor source centimetres projected through reviewed 0.92 arena scale; explicit application units.',
            noD19CharacterActivated=True), originalValuesAndTypesPreserved=True,
        motionObjectsRead=False, motionObjectVerificationRequiredAtAppend=True,
        oldReferenceCatalogueRecreated=False, nativeOrClientExecuted=False)
    output = private_output(args.output)
    for name, raw in original_files.items():
        write_new(output/'original-sources'/name, raw)
    path = output/'common-combat-source-contract.json'
    write_new(path, encoded(contract))
    return dict(contract=record(path), motionRecords=len(records), selectedTriggers=len(selected),
                oldReferenceCatalogueRecreated=False, nativeOrClientExecuted=False)


def throw_policy(profile, contract):
    """Portable source rules using this profile's own body FK, never Wu defaults."""
    require(sha(encoded(contract)) == RECOVERED_CONTRACT_SHA
            and contract['schema'] == 'recovered-common-combat-source-contract-v1'
            and contract['sourceVersion'] == '1.46.0.16.16733-prod'
            and len(contract['records']) == 12, 'Wrong recovered common source contract')
    semantics = verify_trigger_semantics(contract['triggers'])
    require(semantics == contract['throwSemantics'], 'Recovered source semantics changed')
    clips = {clip['name']: clip for clip in profile['clips']}
    require(len(clips) == len(profile['clips']) and all(clip['tracks'].get('centerOfMass') for clip in clips.values()),
            'Every participant motion requires its own COM')
    motions = {}
    for key, source, expected in zip(THROW_KEYS, contract['records'][:6], EXPECTED_THROW_CLOCKS):
        role = source['role']
        require(profile['roles'].get(role) == source['motion']['name'], 'Missing actual paired role')
        clip = clips[profile['roles'][role]]
        require(clip['sha256'] == source['motion']['sha256']
                and clip['sourceConfiguration']['configuration'] == source['configuration'],
                'Paired motion/source configuration identity differs')
        first, last, stride = source_window(source['configuration'], source['motion']['frames'])
        require(first == 0 and stride == 2 and clip['frames'] == last-first+1
                and clip['playbackTicks'] == 2*(clip['frames']-1), 'Paired source crop/clock differs')
        uninterrupt = [row for row in source['configuration']['Intervals'] if row['Name'] == 'Uninterrupt']
        require(len(uninterrupt) == 1 and uninterrupt[0]['Start'] is None, 'Unbound paired protection interval')
        # Existing source-pair adapter closes an uncropped all-motion interval
        # on its first sample beyond the retained motion; explicit End uses F*2.
        protection_end = clip['playbackTicks']+1 if uninterrupt[0]['End'] is None else uninterrupt[0]['End']*stride
        require((clip['playbackTicks'], clip['sourceEndEventTick'], protection_end) == expected,
                'Recovered original paired clocks differ')
        tracks = clip['tracks']
        require(len(tracks['root']) == len(tracks['centerOfMass']) == clip['playbackTicks']+1,
                'Paired source sample count differs')
        root = [rounded(point[0]*1000) for point in tracks['root']]
        require(root[0] == 0 and all(-10000 <= value <= 10000 for value in root), 'Invalid actual paired root displacement')
        motions[key] = dict(role=role, sourceSHA256=clip['sha256'], lastSampleTick=clip['playbackTicks'],
            animationEndTick=clip['sourceEndEventTick'], uninterruptEndTick=protection_end,
            rootMillimeters=root, footLeftMillimeters=rounded(tracks['footL'][0][0]*1000),
            pelvisMillimeters=rounded(tracks['pelvis'][0][0]*1000))
    source = dict(motions=motions, **{k: contract['applicationAdapter'][k] for k in (
        'normalizedUnarmedPower', 'millimetersPerSourceUnitNumerator', 'millimetersPerSourceUnitDenominator')},
        **{key: value for key, value in semantics.items() if key != 'simultaneousContactPolicy'})
    return dict(id='source-common-throws-and-d19-pair-recovered-v1', basis='applicationAdaptation',
        sourceVersion=contract['sourceVersion'], sourceSHA256=sha(encoded(contract)),
        evidence=[
            'Original lock923/2568 common active/passive conditions and actual six motion/configuration pairs.',
            'Original lock2567 complementary lottery and lock945 passive-end 105-unit disable timer.',
            'Original lock1544/1545 D19 interoperability aliases; no D19 powers or playable character activated.',
            'Application power1000 and arena cm-to-mm92:10 are explicit adaptations; FK/root/foot/pelvis are from this profile.',
            'Explicit source protection ends use F*2; uncropped all-motion intervals retain the existing pair adapter last-sample+1 closure.'],
        simultaneousContactPolicy=semantics['simultaneousContactPolicy'], attempts=[], source=source)


def append(args):
    require(not args.output.exists(), 'Refuse to replace an existing combat candidate')
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    require(profile['id'] == profile['hero'] == 'wuyong_erlang' and len(profile['clips']) == 50
            and 'ordinaryThrows' not in profile, 'Expected the verified 50-clip body input')
    require(args.contract_sha256 == RECOVERED_CONTRACT_SHA, 'Unreviewed recovered combat contract')
    contract = json.loads(checked(args.contract, RECOVERED_CONTRACT_SHA, 300_000))
    require(contract['sourceMotionArchiveSHA256'] == ARCHIVE_SHA256 and len(contract['records']) == 12,
            'Wrong common combat source contract')
    verify_trigger_semantics(contract['triggers'])
    configs, config_inputs, _ = load_configs(args)
    model_path = args.profile.parent/(profile['resourceName']+'.glb')
    original_model = checked(model_path, profile['sha256'], 32_000_000)
    require(len(original_model) == profile['bytes'], 'Source body model size differs')
    g, binary = glb_read(model_path)
    original = copy.deepcopy(g)
    old_clips = copy.deepcopy(profile['clips'])
    writer = Writer(); writer.g = g; writer.b = bytearray(binary[:g['buffers'][0]['byteLength']])
    old_binary = bytes(writer.b)
    names = {row['name']: row['targetNode'] for row in profile['sourceBoneBindings']}
    ids = {row['sourceID']: row['name'] for row in profile['sourceBoneBindings'] if row['sourceID'] is not None}
    require(len(names) == 80 and all(g['nodes'][index]['name'] == name for name, index in names.items()),
            'Original Wu source rig differs')
    bundles, motions, load = local_source(args)
    added = []
    for source in contract['records']:
        info = source['motion']
        matching = [row for row in motions if row['name'] == info['name'] and row['bundle'] == info['bundle']]
        require(len(matching) == 1 and all(matching[0][key] == value for key, value in info.items()),
                'Recovered motion does not match exact original catalogue')
        objects = [obj for obj in load(info['bundle']).objects if obj.path_id == info['path_id']]
        require(len(objects) == 1 and objects[0].type.name == 'TextAsset', 'Exact paired/reaction object missing')
        raw = objects[0].read().m_Script
        raw = raw.encode('utf8', 'surrogateescape') if isinstance(raw, str) else bytes(raw)
        binding = {key: source[key] for key in ('sourceEntry', 'sourceSHA256', 'sourceRecordIndex', 'configuration')}
        clip = append_motion(writer, names, ids, configs, info, raw, binding)
        require(clip['name'] not in {row['name'] for row in profile['clips']}, 'Duplicate recovered motion')
        profile['clips'].append(clip)
        if source['role'] is not None:
            require(source['role'] not in profile['roles'], 'Recovered role already bound')
            profile['roles'][source['role']] = clip['name']
        added.append(clip)
        print('APPENDED', clip['name'], clip['frames'], flush=True)
    profile['ordinaryThrows'] = throw_policy(profile, contract)
    profile['schema'] = 'erlang-recovered-combat-body-profile-v1'
    profile['recoveryBoundary'] = dict(profile['recoveryBoundary'], ordinaryThrowsIncluded=True,
        sourceStunIncluded=True, sourceRootVictimIncluded=True, completeBodyMotionSet=True,
        fullMatchProfile=False)
    profile['resourceName'] = 'WuYong_Erlang_D15_Recovered_Combat'
    g['extras'] = dict(g['extras'], schema='erlang-recovered-combat-body-v1', sourceAnimationCount=62,
                      ordinaryThrowsIncluded=True, sourceStunIncluded=True, sourceRootVictimIncluded=True,
                      completeBodyMotionSet=True)
    output = private_output(args.output)
    target = output/(profile['resourceName']+'.glb')
    profile.update(writer.save(target)); target.chmod(0o600)
    written, actual_binary = glb_read(target)
    verify_geometry_prefix(original, old_binary, written, actual_binary)
    require(written['animations'][:50] == original['animations'] and profile['clips'][:50] == old_clips
            and len(written['animations']) == len(profile['clips']) == 62, 'Existing successful body motions changed')
    readback = [verify_clip(written, actual_binary, clip, names, configs) for clip in added]
    profile_path = output/'SF3_Erlang_Recovered_Combat_Profile.json'
    write_new(profile_path, encoded(profile))
    receipt = dict(schema='erlang-recovered-common-combat-append-v1', sourceProfile=record(args.profile),
        sourceModel=record(model_path), sourceContract=record(args.contract),
        sourceBoneConfigs=config_inputs, character=record(target), profile=record(profile_path),
        originalAnimationsUnchanged=50, originalBINBytesUnchanged=len(old_binary),
        unchangedGeometryMaterialsSkinsAndPortrait=True, addedMotionCount=12,
        originalMotionBundles=[{key: bundles[name][key] for key in ('file', 'bytes', 'sha256')}
            for name in sorted({clip['bundle'] for clip in added})],
        readback=readback, comparedPoints=sum(row['comparedPoints'] for row in readback),
        headSamplesAdded=sum(row['headSamples'] for row in readback),
        maximumErrorMeters=max(row['maximumErrorMeters'] for row in readback),
        ordinaryThrowsSourceSHA256=profile['ordinaryThrows']['sourceSHA256'],
        boundaries=profile['recoveryBoundary'],
        remaining=['D15 ability/model runtime binding and actual full-profile validation.',
                   'Personal neck fit and native/visual acceptance.',
                   'New identity binding of effects/audio/companions and complete release.'])
    receipt_path = output/'combat-body-receipt-private.json'
    write_new(receipt_path, encoded(receipt))
    return dict(character=record(target), profile=record(profile_path), receipt=record(receipt_path),
                addedClips=12, totalClips=62, readbackPoints=receipt['comparedPoints'],
                maximumErrorMeters=receipt['maximumErrorMeters'], boundary=profile['recoveryBoundary'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    contract = commands.add_parser('contract')
    for name in ('decoded-splits', 'schema', 'source-archive', 'output'):
        contract.add_argument('--'+name, type=Path, required=True)
    actor = commands.add_parser('append')
    for name in ('profile', 'contract', 'source-archive', 'source-bundles', 'source-configs', 'shared-bones', 'output'):
        actor.add_argument('--'+name, type=Path, required=True)
    for name in ('profile-sha256', 'contract-sha256'):
        actor.add_argument('--'+name, required=True)
    args = parser.parse_args()
    print(json.dumps(recover_contract(args) if args.command == 'contract' else append(args), allow_nan=False))


if __name__ == '__main__':
    main()
