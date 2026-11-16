#!/usr/bin/env python3
"""Export D15 independent model motion and original collision parts offline.

These source prefabs contain a small magic rig, not humanoid geometry. Their
actual visual effects are separate assets. This exports the rig poses and
collision tracks without manufacturing a visible body or scaling it to a
fighter. Source animation end, explicit deletion, and complete samples remain
separate. All source inputs are already recovered files; no network or keys.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import warnings
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

import numpy as np

from sun_triad_assets import C, CI, decode, matrix, pose_world, private_output, require, write_private
from sun_triad_source_bones import parse_bones_data
from sun_triad_spirits import source_rig
from source_floorfall_audio import ANIMATION_FIELDS, Storage, compact

SETTINGS_SHA = '030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa'
RECOVERED_SETTINGS_SHA = '259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6'
RECOVERED_SETTINGS_RECEIPT_SHA = '22541c12e95558c4e1a0a09e4b67ecb817ffde512ad41ea079a285fe0e9acd27'
RECOVERED_RULE_RECEIPT_SHA = '44aa107032803aa8b4ef93a969cc971165fbe9cd63f81774dc1ee21615401ede'
RECOVERED_ARCHIVE_SHA = '02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a'
RECOVERED_ANIMATION_SPLIT_SHA = 'efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29'
RECOVERED_BATTLE_SPLIT_SHA = 'c3941a009cf87916ba076915b77bf308c33e7a00b9cdbd618bb353b5a6f7651b'
RECOVERED_LOCKS = (1432, 1434, 1435, 1436, 1437, 1438, 1440, 1441, 1442,
                   1443, 1444, 1445, 1446, 1447, 1449, 1454, 1466, 1467)
CONFIGURATION_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'
MOTION_CATALOG_SHA = '09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8'
BUNDLE_CATALOG_SHA = '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'
D15_BUNDLE = '2a784bc550bc06541a38a4c1c53b69f3.bin'
SOURCE_RIGHT = np.diag([-1., 1., -1., 1.])
MODELS = {
    'common': dict(model='mgc__common_model_40', bundle='3719ae2b78ab1968e0ffdb31081cb1c0.bin',
        sha256='85ee3665f55ea2d7517a9b17414e9806aa0a201782cf66eeb9bc6d725f916dc4',
        prefab='m_common_model_40', bonesID=5334929850884102527,
        bonesSHA='27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7',
        configID=-4886313542822617672,
        configSHA='5caa65ff923423caaeb39dbf79c4ed7021765ac88553bd2415fead8395a3a36d'),
    'ursus': dict(model='mgc__ursus_light', bundle='58c0a34ada130c42c96420a338dbc6d2.bin',
        sha256='493634cd97dfac969020b9109c587128e8add454b78906b1216a6f304dbf0e01',
        prefab='mgc_01', bonesID=-8171738680468735794,
        bonesSHA='f413e98e29154fc9e5d81d6affe595d510e9f6a0f7f483dfb6d4fb47c4470276',
        configID=1358292119173053941,
        configSHA='4095ba7676a406f434b9524162a9a1560801690aa8f5ac3ecac798eef2386ec5'),
    'sword': dict(model='shd__dual_swords_slash', bundle='07616fc0483dda7b7d17b0ead26c97c0.bin',
        sha256='4d76a18e2b553ffa512a9a51362526cb73c2171435da78cf774c646196e6fda5',
        prefab='mgc_01', bonesID=293704173139025132,
        bonesSHA='1c95bf3e07766302cf8eccdf207cb4b7bb02d89bd39fd702540f62c9ce5be0e4',
        configID=972618900332301321,
        configSHA='e841a2857c525e410e402b53fd4596b1b1d390889a79badbb2548f0d6018cc38'),
}
# record, runtime role, ability, source model, alias, file stem, raw/crop frames,
# SelfEndFrame, source Birth/AnimationEnd lock. None means the native default 4.
DEFINITIONS = [
    (100, 'stomp', 'stomp', 'common', 'D15_Avatara_Leg_Model', 'common_model_40_attack', 31, 10, 0, 1434),
    (103, 'earth', 'earth', 'ursus', 'D15_Avatara_Spear_Down_Model_Attack', 's_agl_helm_bullet', 68, 16, None, 1436),
    (105, 'eye', 'eye', 'common', 'D15_Avatara_Laser_Model', 'd15_avatara_laser_model', 71, 66, None, 1435),
    (106, 'meditation', 'meditate', 'common', 'D15_Meditation_Explosion_Model_Attack_Damage', 'common_model_40_attack', 31, None, None, 1438),
    (118, 'sword', 'swords', 'sword', 'D15_Hovering_Sword_Model_Attack', 'd15_hovering_sword', 51, None, None, 1449),
    (128, 'judgement', 'judgement', 'common', 'D15_Avatara_Ult_Model', 'd15_avatara_ult_swords_model', 92, 33, 0, 1467),
    (132, 'aftershock', 'axe', 'ursus', 'D15_Avatara_Axe_Ground_Model_Attack', 's_agl_helm_bullet', 68, None, None, 1466),
]
PARTS = {
    'stomp': ['Common_Model_40_Attacking_Edge_Big'],
    'earth': ['Ursus_attacking_edge_horizontal'],
    'eye': ['Magic_attacking_edge_4'],
    'meditation': ['Common_Model_40_Attacking_Edge_Huge'],
    'sword': ['Shadow_attacking_edge_D15'],
    'judgement': ['Magic_attacking_edge_5'],
    'aftershock': ['Ursus_attacking_edge_horizontal'],
}
RULE_SHA = {
    1432: '15742b977cfda9fbb8205d428f19e25e385372f4ea4bf3ccd3007309fb879032',
    1434: '2eaad4cb82efc0687809a8fe1b544e3f2c988bbd4566c8638e5515507fa5532d',
    1435: '2bce2d8f03ec4cb28595a76b7ba652bbc9bde006cc414831c0e4e43bd8cce660',
    1436: '00381732a386c860b37fd95794c2e532debaa47227248abc30e64778c2688eb6',
    1437: '7ce37a41aa674a7e427d34e0e541d6f2c8f8a3d78eb5d70e665df3b67b9829f4',
    1438: 'ca1c9ac11aa6f9f762e440cdcf4aa73935f0918f1832a2bf69ab36f340712a0d',
    1440: '86544ef9604c5d2a25a688e8c8b967b4351e47daffcdc12ac5a01faad7fcb0ab',
    1449: '7bfe440232530de537c61b57b4d3ea957feb7174c117ddf2dfd714b7bd105935',
    1454: 'a42c2d2a5a069f99a835998c2ff65627677dcaac73037fb4f1564e20a4493212',
    1466: 'a5d268d82acdbd565572e47c3947b3f3a0e7bac867091fc0e987b2cc939a7674',
    1467: 'b0cc5a156cc9b4e0703ff3d67fa5fdac44a966446678ca0600b2211fa7b9cac0',
}
CREATION = {
    100: (1432, [46]), 103: (1432, [68]), 105: (1432, [50]),
    106: (1437, [3, 4]), 118: (1440, [5, 6, 7, 8, 9, 10]),
    128: (1454, [11]), 132: (1454, [42]),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked(path, digest, maximum):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            'Missing or oversized local source: ' + path.name)
    raw = path.read_bytes()
    require(sha(raw) == digest, 'Source digest differs: ' + path.name)
    return raw


def member(archive, name, maximum, digest=None):
    matches = [i for i in archive.infolist() if i.filename == name]
    require(len(matches) == 1 and matches[0].file_size <= maximum, 'Missing or oversized archive member: ' + name)
    raw = archive.read(matches[0])
    require(digest is None or sha(raw) == digest, 'Archive member digest differs: ' + name)
    return raw


def same_source_value(a, b):
    """JSON equality must not merge bool/int or lose a source float's bits."""
    if type(a) is not type(b):
        return False
    if type(a) is float:
        return struct.pack('>d', a) == struct.pack('>d', b)
    if type(a) is list:
        return len(a) == len(b) and all(same_source_value(x, y) for x, y in zip(a, b))
    if type(a) is dict:
        return a.keys() == b.keys() and all(same_source_value(a[k], b[k]) for k in a)
    return a is None or type(a) in (str, bool, int) and a == b


def unnamed_configuration(configuration, fields):
    """Reverse the pinned native-16684 naming, including every nested field."""
    def ordered(value, kind):
        require(type(value) is dict and set(value) == set(fields[kind]),
                'Recovered named configuration has missing or extra fields')
        return [value[k] for k in fields[kind]]

    result = ordered(configuration, 'animation')
    if configuration['Intervals'] is not None:
        require(type(configuration['Intervals']) is list, 'Recovered interval list type differs')
        intervals = []
        for interval in configuration['Intervals']:
            row = ordered(interval, 'interval')
            if interval['Damage'] is not None:
                row[fields['interval'].index('Damage')] = ordered(interval['Damage'], 'damage')
            intervals.append(row)
        result[fields['animation'].index('Intervals')] = intervals
    if configuration['Sounds'] is not None:
        require(type(configuration['Sounds']) is list, 'Recovered sound list type differs')
        sounds = []
        for sound in configuration['Sounds']:
            row = ordered(sound, 'sound')
            for key in ('Gender', 'Floor'):
                if sound[key] is not None:
                    row[fields['sound'].index(key)] = ordered(sound[key], key.lower())
            sounds.append(row)
        result[fields['animation'].index('Sounds')] = sounds
    return result


def recovered_rule_rows(payload, document, lock, pin):
    require(type(lock) is int and document['schema'] == 'restored-d15-original-trigger-fields-v1'
            and type(document['sourceLock']) is int and document['sourceLock'] == lock
            and document['oldCompactBytesRestored'] is False
            and same_source_value(document['source'], pin['source'])
            and len(payload) == pin['source']['bytes'] and sha(payload) == pin['source']['sha256'],
            'Recovered original lock identity differs')
    if lock in RULE_SHA:
        require(document['oldCompactSHA256'] == pin['expectedOldCompactSHA256'] == RULE_SHA[lock],
                'Historical lock identity was replaced')
    storage = Storage(payload)
    values = storage.value(storage.root)
    require(type(values) is list, 'Original trigger-set list type differs')
    sets = []
    for index, value in enumerate(values):
        require(type(value) is dict and value['kind'] == 'TriggerSetData'
                and type(value['fields']) is list and len(value['fields']) == 2,
                'Original trigger-set shape differs')
        name, triggers = value['fields']
        require(type(name) is str and type(triggers) is list, 'Original trigger-set fields differ')
        rows = []
        for trigger_index, trigger in enumerate(triggers):
            require(type(trigger) is dict and trigger['kind'] == 'TriggerData'
                    and type(trigger['fields']) is list and len(trigger['fields']) == 6,
                    'Original complete trigger shape differs')
            fields = trigger['fields']
            rows.append(dict(triggerIndex=trigger_index, priority=compact(fields[2]),
                events=compact(fields[3]), conditions=compact(fields[4]), actions=compact(fields[5]),
                rawCompactTriggerFields=compact(fields)))
        sets.append(dict(sourceSetIndex=index, sourceSetName=name, triggers=rows))
    require(same_source_value(document['sets'], sets)
            and same_source_value(pin['sourceSets'], [dict(index=s['sourceSetIndex'],
                name=s['sourceSetName'], triggers=len(s['triggers'])) for s in sets]),
            'Recovered trigger projection changed an original field or type')
    require(len(sets) == 1, 'Recovered model requires the single reviewed original trigger set')
    return sets[0]['triggers']


def model_inputs(args):
    """Historical pins remain the default; recovery is a separate full identity."""
    input_format = getattr(args, 'input_format', 'historical')
    require(input_format in ('historical', 'recovered-v1'), 'Unknown model input format')
    if input_format == 'historical':
        return json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000)), None, None
    require(getattr(args, 'decoded_splits', None) is not None, 'Recovered inputs require the original decoded splits')
    raw = checked(args.settings, RECOVERED_SETTINGS_SHA, 200_000)
    settings = json.loads(raw)
    settings_receipt = json.loads(checked(args.settings.parent / 'receipt-private.json',
                                         RECOVERED_SETTINGS_RECEIPT_SHA, 30_000))
    rule_receipt = json.loads(checked(args.rules / 'receipt-private.json', RECOVERED_RULE_RECEIPT_SHA, 20_000))
    require(settings['schema'] == 'recovered-erlang-named-animation-source-v1'
            and settings['suppliedClientVersion'] == '1.46.1'
            and settings['packagedConfigurationVersion'] == '1.46.0.16.16733-prod'
            and settings['sourceDecodedArchiveSHA256'] == RECOVERED_ARCHIVE_SHA
            and settings['sourceAnimationSplitSHA256'] == RECOVERED_ANIMATION_SPLIT_SHA
            and type(settings['nativeSchemaMethod']) is int and settings['nativeSchemaMethod'] == 16684
            and settings['nativeSchemaCodeSHA256'] == settings_receipt['nativeSchema']['codeSHA256']
            and settings['originalValuesAndTypesPreserved'] is True
            and settings['existingBuilderPinsChanged'] is False,
            'Recovered named-settings identity differs')
    fields = settings_receipt['projectionFields']
    require(tuple(fields['animation']) == ANIMATION_FIELDS
            and [len(fields[k]) for k in ('animation', 'interval', 'damage', 'sound', 'gender', 'floor')]
                == [29, 28, 5, 4, 3, 4], 'Recovered native schema differs')
    rows = settings['records']
    require(type(rows) is list and len(rows) == 45
            and [r['sourceRecordIndex'] for r in rows] == list(range(89, 134))
            and all(type(r['sourceRecordIndex']) is int and r['sourceEntry'] == 'settings_sets_dynasty.bytes'
                    and r['sourceSHA256'] == CONFIGURATION_SHA for r in rows),
            'Expected the complete 45 original D15 records')
    require(rule_receipt['schema'] == 'bounded-erlang-rule-source-recovery-v1'
            and rule_receipt['decodedArchiveSHA256'] == RECOVERED_ARCHIVE_SHA
            and rule_receipt['split'] == 'splits/split_battle_triggers.bytes'
            and rule_receipt['splitSHA256'] == RECOVERED_BATTLE_SPLIT_SHA
            and [r['lock'] for r in rule_receipt['files']] == list(RECOVERED_LOCKS),
            'Recovered original rule receipt differs')
    archive_raw = checked(args.decoded_splits, RECOVERED_ARCHIVE_SHA, 17_325_877)
    with ZipFile(io.BytesIO(archive_raw)) as archive:
        animation = member(archive, 'splits/split_animation_settings.bytes', 1_110_598,
                           RECOVERED_ANIMATION_SPLIT_SHA)
        battle = member(archive, 'splits/split_battle_triggers.bytes', 16_429_699, RECOVERED_BATTLE_SPLIT_SHA)
    with ZipFile(io.BytesIO(animation)) as archive:
        dynasty = member(archive, 'settings_sets_dynasty.bytes', 334_225, CONFIGURATION_SHA)
    storage = Storage(dynasty)
    original = storage.value(storage.root)
    require(type(original) is list and len(original) == 295, 'Original dynasty record inventory differs')
    for row in rows:
        require(same_source_value(unnamed_configuration(row['configuration'], fields),
                                  original[row['sourceRecordIndex']]),
                'Recovered naming changed an original configuration field or type')
    rule_inputs = {}
    with ZipFile(io.BytesIO(battle)) as archive:
        for pin in rule_receipt['files']:
            lock = pin['lock']
            require(type(lock) is int and pin['source']['file'] == f'lock_{lock}.bytes'
                    and pin['projection']['file'] == f'd15-lock-{lock}-source-fields-private.json',
                    'Recovered rule filename identity differs')
            payload = member(archive, pin['source']['file'], 50_000, pin['source']['sha256'])
            require(archive.getinfo(pin['source']['file']).CRC == pin['sourceCRC32'], 'Original lock CRC differs')
            require(checked(args.rules / pin['source']['file'], pin['source']['sha256'], 50_000) == payload,
                    'Recovered lock differs from the original archive member')
            path = args.rules / pin['projection']['file']
            projection = checked(path, pin['projection']['sha256'], 500_000)
            require(len(projection) == pin['projection']['bytes'], 'Recovered projection length differs')
            rule_inputs[lock] = (path, projection, recovered_rule_rows(payload, json.loads(projection), lock, pin))
    recovery = dict(format=input_format, settings=dict(file=args.settings.name, bytes=len(raw), sha256=sha(raw)),
        namedSettingsReceiptSHA256=RECOVERED_SETTINGS_RECEIPT_SHA, rulesReceiptSHA256=RECOVERED_RULE_RECEIPT_SHA,
        sourceDecodedArchiveSHA256=RECOVERED_ARCHIVE_SHA, sourceAnimationSplitSHA256=RECOVERED_ANIMATION_SPLIT_SHA,
        sourceBattleSplitSHA256=RECOVERED_BATTLE_SPLIT_SHA, completeNamedRecordsVerified=45,
        completeOriginalLocksVerified=18, completeOriginalTriggersVerified=sum(len(r[2]) for r in rule_inputs.values()),
        ruleInputs=[dict(lock=r['lock'], source=r['source'], projection=r['projection']) for r in rule_receipt['files']],
        historicalNamedSettingsSHA256=SETTINGS_SHA, historicalNamedSettingsBytesRestored=False,
        historicalCompactBytesRestored=False, sourceOnly=True, nativeOrAppExecuted=False)
    return settings, rule_inputs, recovery


def rule_input(args, lock, recovered=None):
    if recovered is not None:
        require(lock in recovered, 'Original recovered lock was not verified')
        return recovered[lock]
    path = args.rules / f'd15-lock-{lock}-compact-private.json'
    raw = checked(path, RULE_SHA[lock], 200_000)
    return path, raw, json.loads(raw)


def playback_window(c, raw_frames):
    require(c['MidFrames'] is None and c['Looped'] is None and c['Mirrored'] is None,
            'Only the reviewed ordinary unmirrored model clock is supported')
    first = max(1, c['FirstFrame'] or 1) - 1
    end = (c['EndFrame'] if c['EndFrame'] is not None else raw_frames) - 1
    self_end = 4 if c['SelfEndFrame'] is None else c['SelfEndFrame']
    require(0 <= first < end < raw_frames and isinstance(self_end, int) and self_end >= 0,
            'Invalid source model playback window')
    frames = end - first + 1
    return dict(originalFrames=raw_frames, firstIndex=first, lastIndex=end, frames=frames,
                samplesPerSourceFrame=2, lastSampleTick=2 * (frames - 1),
                animationEndTick=max(0, 2 * (end - self_end - first)), selfEndFrames=self_end)


def interval_ticks(interval, window):
    # 39602: positive Start/End become index - 1. 39191 IntervalEnd fires only
    # once floor(position) > EndIndex. Thus its event is one source frame after
    # the inclusive interval, not the same formula as IntervalStart.
    first = window['firstIndex']
    start_index = max(0, (interval['Start'] or 1) - 1)
    end_index = window['lastIndex'] if interval['End'] is None else max(0, interval['End'] - 1)
    require(start_index <= end_index, 'Inverted source interval')
    return dict(startTick=max(0, 2 * (start_index - first)),
                endTickInclusive=2 * (end_index - first + 1) - 1,
                intervalEndEventTick=2 * (end_index - first + 1))


def selected_bones(raw, selected):
    """Keep exact requested parts; do not guess unrelated unresolved vertices."""
    require(len(raw) <= 100_000 and b'<!DOCTYPE' not in raw.upper() and b'<!ENTITY' not in raw.upper(),
            'Invalid source BonesData XML')
    root = ET.fromstring(raw)
    capsules = root.findall('./Capsules/Capsule')
    kept = [x for x in capsules if x.get('Name') in selected]
    require(len(kept) == len(selected) and {x.get('Name') for x in kept} == set(selected),
            'Selected source collision part is missing or ambiguous')
    vertices = {x.get('Vertex1') for x in kept} | {x.get('Vertex2') for x in kept}
    subset = ET.Element('BonesData')
    subset.append(root.find('Bones'))
    vs, cs = ET.SubElement(subset, 'Vertexes'), ET.SubElement(subset, 'Capsules')
    for v in root.findall('./Vertexes/Vertex'):
        if v.get('Name') in vertices:
            vs.append(v)
    cs.extend(kept)
    result = parse_bones_data(ET.tostring(subset))
    excluded = [dict(x.attrib) for x in capsules if x not in kept]
    return result, excluded


def source_poses(rows, bones, motion, window, align_axes):
    """Exact local FK, ordinary linear interpolation, then source RIGHT facing."""
    names = {r['name']: i for i, r in enumerate(rows)}
    require(len(names) == len(rows) and set(bones['bones'].values()).issubset(names), 'Source rig binding is incomplete')
    require(all(np.allclose(r['scale'], [1., 1., 1.], atol=1e-7, rtol=0) for r in rows),
            'Model scale needs explicit per-sample capsule support')
    parents = {i: names[r['parent']] for i, r in enumerate(rows) if r['parent'] is not None}
    rest = [C @ matrix(r['translation'], r['rotation'], r['scale']) @ CI for r in rows]
    columns = {bones['bones'][int(n)]: j for j, n in enumerate(motion['bone_ids']) if int(n) in bones['bones']}
    require('magic_joint_root' in columns, 'Source model root channel is missing')
    unbound = [int(n) for n in motion['bone_ids'] if int(n) not in bones['bones']]
    require(set(align_axes).issubset({'X', 'Y', 'Z'}) and len(set(align_axes)) == len(align_axes), 'Unsupported Align axes')
    worlds = []
    for tick in range(window['lastSampleTick'] + 1):
        i = window['firstIndex'] + tick // 2
        j = min(i + 1, window['lastIndex'])
        f = tick % 2 * .5
        local = [m.copy() for m in rest]
        for name, col in columns.items():
            position = motion['positions'][i, col].astype(float) * (1 - f) + motion['positions'][j, col].astype(float) * f
            a = motion['rotations'][i, col].astype(float)
            b = motion['rotations'][j, col].astype(float)
            if a @ b < 0:
                b = -b
            local[names[name]] = C @ matrix(position, a * (1 - f) + b * f, rows[names[name]]['scale']) @ CI
        worlds.append([SOURCE_RIGHT @ m for m in pose_world(local, parents)])
    root_index = names['magic_joint_root']
    roots = np.array([w[root_index][:3, 3] for w in worlds])
    # Initial source Align removes only the requested coordinates. Movement
    # afterwards remains in the model. Core extracts horizontal movement once.
    for frame in worlds:
        for m in frame:
            for axis in align_axes:
                k = 'XYZ'.index(axis)
                m[k, 3] -= roots[0, k]
    return worlds, roots, names, unbound, sorted(set(bones['bones'].values()) - set(columns))


def collision_tracks(worlds, roots, names, bones):
    edges = []
    for capsule in bones['capsules']:
        radius = capsule['radiusCentimeters'] * 10
        require(radius == round(radius) and 0 < radius <= 5000, 'Non-integral or unsupported source radius')
        record = dict(id=capsule['id'], side='right', radiusMillimeters=round(radius), base=[], tip=[])
        for tick, world in enumerate(worlds):
            for endpoint in ('base', 'tip'):
                v = capsule[endpoint]
                point = (world[names[v['bone']]] @ C @ np.array([*v['localPositionCentimeters'], 1.]))[:3]
                point[0] -= roots[tick, 0] - roots[0, 0]
                record[endpoint].append(np.round(point, 9).tolist())
        edges.append(record)
    return edges


def load_model(kind, args, selected):
    import UnityPy
    d = MODELS[kind]
    if kind == 'common':
        directory, configs = args.models, args.common_configs
        bone_name = f"{Path(d['bundle']).stem}_{d['bonesID']}_bones.textasset-private.clear-private"
        config_name = f"{Path(d['bundle']).stem}_{d['configID']}_config.textasset-private.clear-private"
    else:
        directory, configs = args.additional / 'source-bundles', args.additional / 'source-configs'
        bone_name = f"{Path(d['bundle']).stem}_{d['bonesID']}_bones.clear-private.xml"
        config_name = f"{Path(d['bundle']).stem}_{d['configID']}_config.clear-private.xml"
    raw = checked(directory / d['bundle'], d['sha256'], 20_000)
    bone_raw = checked(configs / bone_name, d['bonesSHA'], 100_000)
    config_raw = checked(configs / config_name, d['configSHA'], 5_000)
    config = ET.fromstring(config_raw)
    require(config.tag == 'ModelObject' and len(config.findall('./Prefabs/Prefab')) == 1
            and config.find('./Prefabs/Prefab').get('Name').lower() == d['prefab'], 'Source prefab configuration differs')
    environment = UnityPy.load(raw)
    prefix = f"assets/gamedata/resources/content/items/models/{d['model']}/m/"
    path = prefix + 'prefabs/' + d['prefab'] + '.prefab'
    require(environment.container[prefix + 'bones.xml'].path_id == d['bonesID']
            and environment.container[prefix + 'config.xml'].path_id == d['configID'], 'Source XML object identity differs')
    rows = source_rig(environment.container[path])
    bones, excluded = selected_bones(bone_raw, selected)
    return rows, bones, dict(sourceModel=d['model'], sourceBundle=d['bundle'],
        sourceBundleSHA256=d['sha256'], sourcePrefab=path, sourcePrefabPathID=str(environment.container[path].path_id),
        sourceBonesSHA256=d['bonesSHA'], sourceBonesPathID=str(d['bonesID']),
        sourceConfigurationSHA256=d['configSHA'], sourceConfigurationPathID=str(d['configID']),
        originalPrefabHierarchy=rows, sourceDeclarations=bones, excludedUnrequestedCapsules=excluded,
        excludedPolicy='Unrequested source parts are not emitted; unresolved unrelated equipment vertices are never invented.')


def source_rules(args, lock, alias, window, record, recovered=None):
    path, raw, rows = rule_input(args, lock, recovered)
    # The independent models delete on AnimationEnd except the hovering sword:
    # its named destroy IntervalEnd is earlier and has its own source event.
    if record == 118:
        deletes = [r for r in rows if r['triggerIndex'] == 12]
        require(len(deletes) == 1 and {'a17': ['enum65537', 'D15_Sword_Destroy']} in deletes[0]['events']
                and {'a50': [None, None]} in deletes[0]['actions'], 'Original sword deletion trigger changed')
        delete = 70
    else:
        deletes = [r for r in rows if {'a0': [alias, 'enum65537']} in (r['events'] or [])
                   and {'a50': [None, None]} in (r['actions'] or [])]
        require(len(deletes) == 1, 'Original model deletion is missing or ambiguous')
        delete = None
    return delete, dict(file=path.name, sha256=sha(raw), lock=lock,
                        deletionTriggers=deletes, sourceAnimationEndTick=window['animationEndTick'],
                        sourceDeleteEventTick=delete)


def source_creation(args, record, model, recovered=None):
    lock, indices = CREATION[record]
    path, raw, all_rows = rule_input(args, lock, recovered)
    rows = [r for r in all_rows if r['triggerIndex'] in indices]
    require(len(rows) == len(indices), 'Source creation trigger is missing')
    for row in rows:
        actions = [a['a45'] for a in row['actions'] if 'a45' in a]
        require(len(actions) == 1 and actions[0][3] == 1 and actions[0][15][7] == model,
                'Source CreateModel identity or scale differs')
    return dict(file=path.name, sha256=sha(raw), lock=lock, creationTriggers=rows)


def build(args):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    settings, recovered_rules, input_recovery = model_inputs(args)
    output = private_output(args.output)
    require(not output.exists() or not any(output.iterdir()), 'Candidate directory must be empty')
    tracks, models, receipts = [], [], []
    raw_motions, environments = {}, {}
    with ZipFile(args.archive) as archive:
        catalog = json.loads(member(archive, 'research/motion_catalog.json', 3_100_000, MOTION_CATALOG_SHA))
        bundles = [json.loads(x) for x in member(archive, 'research/android_bundle_catalog.jsonl', 9_200_000, BUNDLE_CATALOG_SHA).splitlines()]
        bundle_catalog = {x['file']: x for x in bundles}
        for record, suffix, ability, kind, alias, stem, raw_frames, end_frame, self_end, lock in DEFINITIONS:
            role = 'erlangSummon_' + suffix
            matches = [r for r in settings['records'] if r['sourceEntry'] == 'settings_sets_dynasty.bytes'
                       and r['sourceRecordIndex'] == record and r['configuration']['Animation'] == alias]
            require(len(matches) == 1 and matches[0]['sourceSHA256'] == CONFIGURATION_SHA, 'Source animation identity differs')
            setting = matches[0]
            c = setting['configuration']
            require(Path(c['FileName']).stem == stem and c['FirstFrame'] is None
                    and c['EndFrame'] == end_frame and c['SelfEndFrame'] == self_end,
                    'Reviewed model crop or end event changed')
            require(all(i['Type'] in (None, 'Attack', 'NoWallRepulsion') and i['ScaleBone'] is None
                        for i in c['Intervals']), 'Additional source model interval needs an explicit adapter')
            matches = [m for m in catalog['motions'] if m['name'] == stem]
            require(len(matches) == 1, 'Original motion catalog identity is ambiguous')
            m = matches[0]
            require(m['frames'] == raw_frames and m['arrays'] == 2, 'Original model motion frame count differs')
            if stem not in raw_motions:
                bundle = m['bundle']
                bc = bundle_catalog[bundle]
                if bundle not in environments:
                    if bundle == D15_BUNDLE:
                        b = checked(args.d15_motions / bundle, bc['sha256'], 2_000_000)
                    else:
                        b = member(archive, 'bundles/' + bundle, 2_000_000, bc['sha256'])
                    environments[bundle] = UnityPy.load(b)
                found = [o for o in environments[bundle].objects if o.path_id == m['path_id']]
                require(len(found) == 1 and found[0].type.name == 'TextAsset', 'Original model motion object is absent')
                text = found[0].read().m_Script
                raw = text.encode('utf8', 'surrogateescape') if isinstance(text, str) else bytes(text)
                require(len(raw) == m['bytes'] and sha(raw) == m['sha256'], 'Original model motion bytes differ')
                raw_motions[stem] = raw
            arrays = decode(raw_motions[stem])
            require(len(arrays) == 2 and all(a['frame_count'] == raw_frames for a in arrays), 'Original motion arrays differ')
            motion = arrays[0]
            require([int(x) for x in motion['bone_ids']] == m['bone_ids'], 'Original motion bone inventory differs')
            window = playback_window(c, raw_frames)
            attacks = [i for i in c['Intervals'] if i['Type'] == 'Attack']
            parts = sorted({p for i in attacks for p in i['AttackingParts']})
            require(parts == sorted(PARTS[suffix]), 'Original attack part contract differs')
            rows, bones, model_receipt = load_model(kind, args, parts)
            align = c['Align']
            require(len(align) == 7 and align[6] == [None, 'Nodes', 'magic_joint_root'], 'Unexpected model Align target')
            worlds, roots, names, unbound, rest_only = source_poses(rows, bones, motion, window, align[4])
            require(unbound == ([13, 31] if kind == 'ursus' else []), 'Unexpected unbound motion ID')
            delete, rule_receipt = source_rules(args, lock, alias, window, record, recovered_rules)
            if record == 118:
                destroy = [i for i in c['Intervals'] if i['Name'] == 'D15_Sword_Destroy']
                require(len(destroy) == 1 and destroy[0]['End'] == 35
                        and interval_ticks(destroy[0], window)['intervalEndEventTick'] == delete,
                        'Sword destroy event clock changed')
            lifetime = min(window['animationEndTick'], window['lastSampleTick'],
                           delete if delete is not None else window['lastSampleTick'])
            track = dict(role=role, clip=stem, frames=window['frames'], sourceSHA256=m['sha256'],
                sourceBundle=m['bundle'], root=np.round(roots, 9).tolist(),
                groundLift=[0.] * len(roots), boneConfigurationSHA256=MODELS[kind]['bonesSHA'],
                collisionEdges=collision_tracks(worlds, roots, names, bones), hurtCapsules=[],
                attackParts={'primary': parts}, sourceEndEventTick=window['animationEndTick'])
            if delete is not None:
                track['sourceDeleteEventTick'] = delete
            tracks.append(track)
            transforms = {name: [np.round(w[index].T.reshape(-1), 9).tolist() for w in worlds]
                          for name, index in names.items() if name in bones['bones'].values()}
            source_attacks = []
            for index, attack in enumerate(attacks):
                ticks = interval_ticks(attack, window)
                end = min(lifetime, ticks['endTickInclusive'])
                effective = dict(startTick=ticks['startTick'], endTick=end) if ticks['startTick'] <= end else None
                source_attacks.append(dict(index=index, original=attack, native=ticks, effective=effective))
            models.append(dict(role=role, ability=ability, sourceAnimation=alias, sourceRecordIndex=record,
                sourceConfigurationSHA256=CONFIGURATION_SHA, sourceFile=c['FileName'], motion=window,
                sourceEndEventTick=window['animationEndTick'], sourceDeleteEventTick=delete,
                effectiveLastTick=lifetime, sourceModel=MODELS[kind]['model'], bones=transforms,
                sourceAttackIntervals=source_attacks,
                origin=dict(sourceAlign=align, sourceSetDirection=c['SetDirection'], modelScale=1,
                    sourceRightRotation='Ry(pi)', selectedAlignAxes=align[4],
                    initialAlignedRootMeters=roots[0].tolist(), sourceShiftCentimeters=align[3],
                    runtimeRule='Apply source target/axes/Shift at birth; these poses remove initial aligned coordinates only. Apply current root X displacement once.'),
                sourceSounds=c['Sounds'], sourceIntervals=c['Intervals']))
            receipts.append(dict(role=role, sourceConfiguration=setting, sourceModel=model_receipt,
                originalMotion=dict(m, bundleSHA256=bundle_catalog[m['bundle']]['sha256']),
                unboundMotionIDs=unbound, declaredButUnanimatedBones=rest_only, deletion=rule_receipt,
                creation=source_creation(args, record, MODELS[kind]['model'], recovered_rules)))
    output.mkdir(parents=True, exist_ok=True)
    document = dict(schema='original-d15-independent-model-tracks-v1', sourceConfigurationSHA256=CONFIGURATION_SHA,
        summonTracks=tracks, models=models, receipts=receipts,
        coordinateContract='Source model FK in meters, Unity Z reflection and original RIGHT Ry(pi); no humanoid .92 scale or -90-degree visual basis. Source Align axes are removed at birth; core collision X removes current root displacement once. Side right is a stable wire slot for central model capsules, not a handedness assertion.',
        boundaries=[
            'This file supplies real source model poses and collisions, not their separate particle/mesh FX.',
            'Original full motion bytes, cropped samples, AnimationEnd and named deletion events remain distinct.',
            'Damage, status, actor origin binding and release conditions are built by the combat adapter from these source records; no guessed HP or release offset is filled here.',
            'Ordinary interpolation only; native slow-motion second-array behavior is not replaced by invented resampling.',
            'The final event sample is retained by the existing arena adapter; removal occurs on the next live tick. Native display-commit ordering is not claimed equivalent.'])
    if input_recovery is not None:
        document['inputRecovery'] = input_recovery
    name = 'd15-model-tracks-candidate-private.json'
    write_private(output / name, json.dumps(document, separators=(',', ':'), allow_nan=False).encode())
    for stem, raw in raw_motions.items():
        write_private(output / (stem + '.original-private.bytes'), raw)
    print(json.dumps(dict(file=name, bytes=(output / name).stat().st_size, sha256=sha((output / name).read_bytes()),
        models=[dict(role=m['role'], frames=m['motion']['frames'], firstIndex=m['motion']['firstIndex'],
                     lastSample=m['motion']['lastSampleTick'], animationEnd=m['sourceEndEventTick'],
                     deletion=m['sourceDeleteEventTick'], effectiveLast=m['effectiveLastTick']) for m in models]), separators=(',', ':')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('archive', 'd15-motions', 'models', 'common-configs', 'additional', 'settings', 'rules', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--input-format', choices=('historical', 'recovered-v1'), default='historical',
                        help='Explicit recovered source identity; historical complete pins remain the default.')
    parser.add_argument('--decoded-splits', type=Path,
                        help='Original byte-pinned decoded splits, required only for recovered-v1.')
    build(parser.parse_args())


if __name__ == '__main__':
    main()
