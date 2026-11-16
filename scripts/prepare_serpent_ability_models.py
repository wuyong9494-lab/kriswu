#!/usr/bin/env python3
"""Recover five original D13 independent-model states from local sources.

The common and push prefabs are genuine invisible collision rigs. Only the
source root model has visible meshes. Export their real FK/capsules and the
two animated root meshes without creating replacement art, evaluating combat
conditions, modifying a playable profile, downloading, or decrypting anything.
"""
from __future__ import annotations

import argparse
import io
import json
from pathlib import Path
import warnings
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import numpy as np

from prepare_erlang_model_tracks import (SOURCE_RIGHT, checked, collision_tracks,
    interval_ticks, member, playback_window, selected_bones, sha)
from prepare_fighter_target_motions import ARCHIVE_SHA256
from prepare_serpent_named_settings import (ARCHIVE_PIN, SCHEMA_PIN, encoded,
    recover, typed)
from prepare_serpent_source_rules import original_triggers
from sun_triad_assets import (C, CI, Writer, accessor_read, decode, glb_read,
    matrix, pose_world, private_output, quaternion, require, skin_slots,
    world_poses, write_private)
from sun_triad_materials import original_material
from sun_triad_spirits import source_rig

SETTINGS_SHA = '2ff1cca279a4db9bf772c27cd847102d6887e0363905b30616ad5ed54cd4357d'
CONFIGURATION_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'
MOTION_CATALOG_SHA = '09829af10b6691124853335a3b8a2821a53c771ffeb4ec0bac97ad8eb6c6fee8'
BUNDLE_CATALOG_SHA = '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'
GLB_FILE = 'Serpent_D13_Withering_Vines.glb'
DOCUMENT_FILE = 'd13-ability-models-private.json'
ORACLE_FILE = 'world-capsules-oracle-private.json'
MODELS = {
    'common': dict(model='mgc__common_model_40', bundle='3719ae2b78ab1968e0ffdb31081cb1c0.bin',
        bytes=12407, sha256='85ee3665f55ea2d7517a9b17414e9806aa0a201782cf66eeb9bc6d725f916dc4',
        prefab='m_common_model_40', prefabID=8489236191235018747,
        bonesID=5334929850884102527,
        bonesSHA='27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7',
        configID=-4886313542822617672,
        configSHA='5caa65ff923423caaeb39dbf79c4ed7021765ac88553bd2415fead8395a3a36d'),
    'push': dict(model='mgc__islander_push', bundle='4658f30ed25625d417f2a7fd709d86f2.bin',
        bytes=5712, sha256='4fda41f0830f715bead25647b673a2c2ad3d6b2740c19d9c7f456d834c3e1afc',
        prefab='mgc_01', prefabID=217792115728160067,
        bonesID=-7430952131620596907,
        bonesSHA='ca417cf469125ab93824398d3798dc62ed3d4c8c80d248935749bfdf1ffba509',
        configID=-8066945517885713716,
        configSHA='cb0fe2babeefe68752b35cdaea107ad03f0b4dea5587b7a9c4973e5b54f11f85'),
    'root': dict(model='mgc__islander_root', bundle='50c9a6d2cebf72f31ac0bd048ab626e1.bin',
        bytes=168767, sha256='88d06624994021869c9802237afda983168212b15169cf6df6a33499f8df5a53',
        prefab='model_root', prefabID=-3774766758724423024,
        bonesID=-3125888287205982177,
        bonesSHA='87c594e1b25894402ceeac65932fe5656612638991796c4fb807edb734a5235d',
        configID=8258975589703215935,
        configSHA='9de5812b0586a858fc6aaa437e0d44c229a55fe14146479cb35793ba090842e8'),
}
# Source record, role, model, alias, original motion, full frames, crop,
# alignment bone, model-local deletion lock. All five have SelfEndFrame=0.
DEFINITIONS = (
    (57, 'helmet', 'common', 'D13_Helmet_Ability_Model_Attack', 'd13_helmet_ability_model', 22, None, 'magic_joint_root', 1387),
    (62, 'bloom', 'common', 'D13_Bloom_Enemy_Damage', 'common_model_40_attack', 31, 6, 'magic_joint_root', 1382),
    (64, 'push', 'push', 'D13_Armor_Ability_Attack_Model_Push', 'leader_ability_model_push', 11, None, 'magic_joint_root', 1385),
    (65, 'vine1', 'root', 'D13_Withering_Vine_1', 'leader_root_creep_1', 88, None, 'tentacle_1', 1386),
    (66, 'vine2', 'root', 'D13_Withering_Vine_2', 'leader_root_creep_2', 92, None, 'tentacle_1', 1386),
)
PARTS = {
    'helmet': ['Common_Model_40_Attacking_Edge_HorBig'],
    'bloom': ['Common_Model_40_Attacking_Edge'],
    'push': ['Magic_Islander_Model_Push_Attacking_Edge'],
    **{name: ['Magic_Islander_Root_Attacking_Edge_Tentacle_' + str(i) for i in (18, 19, 20)]
       for name in ('vine1', 'vine2')},
}
RULE_LOCKS = (1379, 1382, 1384, 1385, 1386, 1387, 1396)
SHIFTS = {'helmet': [160., 0., 0.], 'bloom': None, 'push': None,
          'vine1': [-250., 0., 0.], 'vine2': [-175., 0., 0.]}


def source_inputs(args):
    root = args.recovery
    path = root / 'recovered-decoded-startup/1.46.0.16.16733-prod_splits-decoded-private.zip'
    splits = checked(path, ARCHIVE_PIN[1], ARCHIVE_PIN[0])
    schema = checked(root / 'recovered-erlang-named-animations-v1/animation-schema-recovered-private.json',
                     SCHEMA_PIN[1], SCHEMA_PIN[0])
    settings_path = root / 'continued-20261116/serpent-named-settings-v1/serpent-animation-named-v1.json'
    settings_raw = checked(settings_path, SETTINGS_SHA, 60_000)
    _, recovered, _, _, _ = recover(splits, schema)
    settings = json.loads(settings_raw)
    require(typed(settings) == typed(recovered), 'D13 named settings differ from original values/types')
    all_rules, originals = original_triggers(splits)
    rules = {r['sourceLock']: r for r in all_rules if r['sourceLock'] in RULE_LOCKS}
    require(set(rules) == set(RULE_LOCKS), 'D13 original model rules are incomplete')
    return settings, rules, {name: raw for name, raw in originals.items()
                            if name in {f'lock_{i}.bytes' for i in RULE_LOCKS} | {'lockTree.bytes'}}


def load_model(kind, args, selected):
    import UnityPy
    d = MODELS[kind]
    if kind == 'common':
        bundles = args.recovery / 'recovered-source-bundles'
        configs = args.recovery / 'recovered-model-configs'
    else:
        bundles = args.recovery / 'continued-20261116/serpent-model-bundles-v1'
        configs = args.model_inputs
    raw = checked(bundles / d['bundle'], d['sha256'], d['bytes'])
    stem = Path(d['bundle']).stem
    bone_raw = checked(configs / f"{stem}_{d['bonesID']}_bones.clear-private.xml", d['bonesSHA'], 20_000)
    config_raw = checked(configs / f"{stem}_{d['configID']}_config.clear-private.xml", d['configSHA'], 5_000)
    require(b'<!DOCTYPE' not in config_raw.upper() and b'<!ENTITY' not in config_raw.upper(),
            'Unsupported ModelObject declaration')
    config = ET.fromstring(config_raw)
    require(config.tag == 'ModelObject' and len(config.findall('./Prefabs/Prefab')) == 1
            and config.find('./Prefabs/Prefab').get('Name').lower() == d['prefab'],
            'Original D13 prefab configuration differs')
    environment = UnityPy.load(raw)
    prefix = f"assets/gamedata/resources/content/items/models/{d['model']}/m/"
    prefab = prefix + 'prefabs/' + d['prefab'] + '.prefab'
    require(environment.container[prefix + 'bones.xml'].path_id == d['bonesID']
            and environment.container[prefix + 'config.xml'].path_id == d['configID']
            and environment.container[prefab].path_id == d['prefabID'],
            'Original model object identity differs')
    rows = source_rig(environment.container[prefab])
    bones, excluded = selected_bones(bone_raw, selected)
    mesh_names = [x.get('Name') for x in config.findall('./Meshes/Mesh')]
    require(mesh_names == (['m__tentacle', 'm__tentacle_crystal'] if kind == 'root' else []),
            'Source mesh inventory differs; invisible rigs must remain invisible')
    audit = dict(sourceModel=d['model'], sourceBundle=d['bundle'], sourceBundleSHA256=d['sha256'],
        sourceBundleBytes=len(raw), sourcePrefab=prefab, sourcePrefabPathID=str(d['prefabID']),
        sourceBonesSHA256=d['bonesSHA'], sourceBonesPathID=str(d['bonesID']),
        sourceConfigurationSHA256=d['configSHA'], sourceConfigurationPathID=str(d['configID']),
        originalPrefabHierarchy=rows, sourceDeclarations=bones,
        excludedUnrequestedCapsules=excluded, sourceMeshes=mesh_names,
        sourceModelConfiguration=config_raw.decode('utf-8-sig'))
    return rows, bones, environment, config, audit, bone_raw, config_raw


def local_samples(rows, bones, motion, window, anchor):
    """Retain the model hierarchy and the native ordinary half-frame samples."""
    names = {r['name']: i for i, r in enumerate(rows)}
    require(len(names) == len(rows) and set(bones['bones'].values()).issubset(names),
            'Model rig binding is incomplete')
    require(all(np.allclose(r['scale'], [1., 1., 1.], atol=1e-7, rtol=0) for r in rows),
            'Non-unit source rig scale needs a separate collision adapter')
    ids = [int(i) for i in motion['bone_ids']]
    require(len(ids) == len(set(ids)) and set(ids).issubset(bones['bones']),
            'Unknown or duplicate model motion bone')
    columns = {bones['bones'][n]: i for i, n in enumerate(ids)}
    require(anchor in columns, 'Source model alignment bone channel is missing')
    rest = [C @ matrix(r['translation'], r['rotation'], r['scale']) @ CI for r in rows]
    samples = []
    for tick in range(window['lastSampleTick'] + 1):
        i = window['firstIndex'] + tick // 2
        j = min(i + 1, window['lastIndex'])
        f = tick % 2 * .5
        local = [m.copy() for m in rest]
        for name, col in columns.items():
            p = motion['positions'][i, col].astype(float) * (1 - f) + motion['positions'][j, col].astype(float) * f
            a = motion['rotations'][i, col].astype(float)
            b = motion['rotations'][j, col].astype(float)
            if a @ b < 0:
                b = -b
            q = a * (1 - f) + b * f
            require(np.isfinite(p).all() and np.isfinite(q).all() and np.linalg.norm(q) > .1,
                    'Invalid original model transform')
            local[names[name]] = C @ matrix(p, q, rows[names[name]]['scale']) @ CI
        samples.append(local)
    return samples, names, sorted(set(bones['bones'].values()) - set(columns))


def source_poses(rows, bones, motion, window, align_axes, anchor):
    local, names, rest_only = local_samples(rows, bones, motion, window, anchor)
    require(set(align_axes).issubset({'X', 'Y', 'Z'}) and len(set(align_axes)) == len(align_axes),
            'Unsupported source Align axes')
    parents = {i: names[r['parent']] for i, r in enumerate(rows) if r['parent'] is not None}
    worlds = [SOURCE_RIGHT @ pose_world(sample, parents) for sample in local]
    roots = np.array([w[names[anchor]][:3, 3].copy() for w in worlds])
    for frame in worlds:
        for m in frame:
            for axis in align_axes:
                k = 'XYZ'.index(axis)
                m[k, 3] -= roots[0, k]
    return worlds, roots, names, rest_only


def model_rules(rules, alias, kind, lock):
    rows = [dict(sourceSetIndex=s['sourceSetIndex'], **r)
            for s in rules[lock]['sets'] for r in s['triggers']]
    births = [r for r in rows if {'a2': ['enum65537']} in (r['events'] or [])
              and {'a6': [alias, None, None]} in (r['actions'] or [])]
    deletes = [r for r in rows if {'a0': [alias, 'enum65537']} in (r['events'] or [])
               and {'a50': [None, None]} in (r['actions'] or [])]
    require(len(births) == len(deletes) == 1, 'Original model birth/deletion route differs')
    creations = []
    for source_lock, document in rules.items():
        for source_set in document['sets']:
            for row in source_set['triggers']:
                for action in row['actions'] or []:
                    create = action.get('a45')
                    if create is not None and create[15][7] == MODELS[kind]['model']:
                        require(create[3] == 1, 'Original model creation scale differs')
                        creations.append(dict(sourceLock=source_lock, sourceSetIndex=source_set['sourceSetIndex'],
                            triggerIndex=row['triggerIndex'], original=row,
                            sourceTreePaths=document['sourceTreePaths']))
    require(bool(creations), 'Original model CreateModel route is missing')
    return dict(sourceLock=lock, sourceLockSHA256=rules[lock]['sourceSHA256'],
        sourceTreePaths=rules[lock]['sourceTreePaths'], birthTriggers=births,
        deletionTriggers=deletes, creationCandidates=creations, conditionsEvaluated=False,
        boundary='Shared-model creations retain their original tags and conditions; these are not unconditional spawns.')


def export_vines(path, environment, config, rows, bones, motions, windows):
    """Preserve both real meshes, source skin lanes/binds and 60 Hz key poses."""
    from UnityPy.helpers.MeshHelper import MeshHandler
    writer = Writer()
    g = writer.g
    g['asset']['generator'] = 'Verified original D13 independent root model exporter'
    g['extras'] = dict(sourceOnly=True, runtimeBound=False, customShaderParity=False,
        coordinates='Unity centimeters reflected in Z and converted to meters; no facing, Align, or fighter scale.',
        sampling='Exact ordinary 60 Hz ticks; interpolation between ticks is not asserted as source-native.')
    initial, names, _ = local_samples(rows, bones, motions['vine1'], windows['vine1'], 'tentacle_1')
    for i, row in enumerate(rows):
        local = initial[0][i]
        node = dict(name=row['name'], translation=local[:3, 3].tolist(),
                    rotation=quaternion(local[:3, :3]).tolist(), scale=[1., 1., 1.])
        children = [j for j, r in enumerate(rows) if r['parent'] == row['name']]
        if children:
            node['children'] = children
        g['nodes'].append(node)
    g['scenes'][0]['nodes'] = [i for i, row in enumerate(rows) if row['parent'] is None]
    prefix = 'assets/gamedata/resources/content/items/models/mgc__islander_root/m/'
    mesh_receipts, reference_meshes, material_cache = [], [], {}
    for item in config.findall('./Meshes/Mesh'):
        name = item.get('Name')
        pointer = environment.container[prefix + 'meshes/' + name + '.prefab']
        game = pointer.read()
        renderers = [c.component.read() for c in game.m_Component
                     if c.component.deref().type.name == 'SkinnedMeshRenderer']
        bindings = [c.component.deref().read_typetree() for c in game.m_Component
                    if c.component.deref().type.name == 'MonoBehaviour']
        bindings = [b for b in bindings if '_bindBonesName' in b]
        transforms = [c.component.read() for c in game.m_Component
                      if c.component.deref().type.name == 'Transform']
        require(len(renderers) == len(bindings) == len(transforms) == 1, 'Ambiguous original root mesh components')
        renderer, binding, transform = renderers[0], bindings[0], transforms[0]
        source_transform = matrix([transform.m_LocalPosition.x, transform.m_LocalPosition.y, transform.m_LocalPosition.z],
            [transform.m_LocalRotation.x, transform.m_LocalRotation.y, transform.m_LocalRotation.z, transform.m_LocalRotation.w],
            [transform.m_LocalScale.x, transform.m_LocalScale.y, transform.m_LocalScale.z])
        require(np.max(np.abs(source_transform - np.eye(4))) < 1e-8,
                'Nonidentity root mesh transform needs an explicit source adapter')
        mesh = renderer.m_Mesh.read()
        handler = MeshHandler(mesh)
        handler.process()
        bound = binding['_bindBonesName']
        require(len(bound) == len(mesh.m_BindPose) == len(mesh.m_BoneNameHashes)
                and len(set(bound)) == len(bound) and set(bound).issubset(names),
                'Original ordered SkinData bone binding differs')
        inverse = [C @ np.array([[getattr(b, f'e{y}{x}') for x in range(4)] for y in range(4)]) @ CI
                   for b in mesh.m_BindPose]
        indices = np.asarray(handler.m_BoneIndices, dtype=np.int64)
        original_weights = np.asarray(handler.m_BoneWeights, dtype=float)
        require(indices.shape == original_weights.shape and indices.shape[1] == 4
                and np.min(indices) >= 0 and np.max(indices) < len(bound),
                'Original root mesh skin lane layout differs')
        joints, weights = skin_slots(indices, original_weights)
        p = np.asarray(handler.m_Vertices, dtype=float)[:, :3] * [.01, .01, -.01]
        n = np.asarray(handler.m_Normals, dtype=float)[:, :3] * [1., 1., -1.]
        uv = np.asarray(handler.m_UV0, dtype=float)[:, :2]
        uv[:, 1] = 1 - uv[:, 1]
        require(p.shape == n.shape and uv.shape == (len(p), 2), 'Original root mesh vertex streams differ')
        attributes = dict(POSITION=writer.acc(p, 'VEC3'), NORMAL=writer.acc(n, 'VEC3'),
            TEXCOORD_0=writer.acc(uv, 'VEC2'), JOINTS_0=writer.acc(joints, 'VEC4', 5123),
            WEIGHTS_0=writer.acc(weights, 'VEC4'))
        triangles = handler.get_triangles()
        require(len(triangles) == len(renderer.m_Materials) == 1, 'Root source submesh materials differ')
        material_index = original_material(writer, renderer.m_Materials[0].read(), material_cache,
                                           double_sided_override=binding['cullMode'] == 0)
        faces = np.asarray(triangles[0], np.uint32).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        mesh_index = len(g['meshes'])
        g['meshes'].append(dict(name=name, primitives=[dict(attributes=attributes,
            indices=writer.acc(faces, 'SCALAR', 5125), material=material_index)]))
        skin_index = len(g['skins'])
        g['skins'].append(dict(name=name + '_original_skin', joints=[names[n] for n in bound],
            skeleton=names[binding['_rootBoneName']],
            inverseBindMatrices=writer.acc([m.T.reshape(16) for m in inverse], 'MAT4')))
        mesh_node = len(g['nodes'])
        g['nodes'].append(dict(name=name, mesh=mesh_index, skin=skin_index,
                              extras=dict(sourceForceGlow=item.get('ForceGlow'), customShaderParity=False)))
        g['scenes'][0]['nodes'].append(mesh_node)
        mesh_receipts.append(dict(name=name, sourcePrefabPathID=str(pointer.path_id),
            vertices=len(p), triangles=len(faces) // 3, originalBindingNames=bound,
            originalBoneHashes=list(mesh.m_BoneNameHashes), sourceRootBone=binding['_rootBoneName'],
            sourceSkinData=binding, sourceModelMeshAttributes=dict(item.attrib),
            maximumWeightNormalization=float(np.max(np.abs(weights - original_weights)))))
        reference_meshes.append(dict(name=name, positions=p.tolist(), joints=joints.tolist(),
            weights=weights.tolist(), originalWeights=original_weights.tolist(),
            inverseBindMatrices=[m.tolist() for m in inverse], sourceBindingNames=bound))
    for definition in DEFINITIONS:
        _, role, kind, alias, _, _, _, anchor, _ = definition
        if kind != 'root':
            continue
        samples, _, _ = local_samples(rows, bones, motions[role], windows[role], anchor)
        times = writer.acc(np.arange(len(samples), dtype=float) / 60, 'SCALAR')
        animation = dict(name=alias, channels=[], samplers=[], extras=dict(
            sourceFrames=windows[role]['originalFrames'], samplesPerSourceFrame=2,
            exportFramesPerSecond=60, sourceEndEventTick=windows[role]['animationEndTick']))
        for name in bones['bones'].values():
            node = names[name]
            positions = np.asarray([m[node][:3, 3] for m in samples])
            rotations = np.asarray([quaternion(m[node][:3, :3]) for m in samples])
            for i in range(1, len(rotations)):
                if rotations[i - 1] @ rotations[i] < 0:
                    rotations[i] *= -1
            for key, values, width in (('translation', positions, 'VEC3'), ('rotation', rotations, 'VEC4')):
                sampler = len(animation['samplers'])
                animation['samplers'].append(dict(input=times, output=writer.acc(values, width), interpolation='LINEAR'))
                animation['channels'].append(dict(sampler=sampler, target=dict(node=node, path=key)))
        g['animations'].append(animation)
    result = writer.save(path)
    path.chmod(0o600)
    return dict(file=path.name, **result, meshes=mesh_receipts,
                referenceMeshes=reference_meshes, customShaderParity=False)


def build(args):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'Use an empty private output directory')
    settings, rules, rule_originals = source_inputs(args)
    archive_raw = checked(args.source_archive, ARCHIVE_SHA256, 190_482_427)
    tracks, models, receipts, raw_motions, decoded_motions, windows = [], [], [], {}, {}, {}
    source_xml = {}
    root_export = None
    with ZipFile(io.BytesIO(archive_raw)) as archive:
        catalog = json.loads(member(archive, 'research/motion_catalog.json', 3_100_000, MOTION_CATALOG_SHA))
        bundle_rows = [json.loads(line) for line in member(archive, 'research/android_bundle_catalog.jsonl',
                      9_200_000, BUNDLE_CATALOG_SHA).splitlines()]
        bundles = {r['file']: r for r in bundle_rows}
        environments = {}
        for record, suffix, kind, alias, stem, raw_frames, crop, anchor, lock in DEFINITIONS:
            matches = [r for r in settings['records'] if r['sourceRecordIndex'] == record]
            require(len(matches) == 1 and matches[0]['sourceSHA256'] == CONFIGURATION_SHA,
                    'Original D13 record identity differs')
            setting = matches[0]
            c = setting['configuration']
            require(c['Animation'] == alias and Path(c['FileName']).stem == stem
                    and c['FirstFrame'] is None and c['EndFrame'] == crop and c['SelfEndFrame'] == 0,
                    'Original D13 motion crop or terminal clock differs')
            require(all(i['Type'] in (None, 'NoWallRepulsion', 'Attack') and i['ScaleBone'] is None
                        for i in c['Intervals']), 'Additional original model interval needs a separate adapter')
            matches = [m for m in catalog['motions'] if m['name'] == stem]
            require(len(matches) == 1 and matches[0]['frames'] == raw_frames and matches[0]['arrays'] == 2,
                    'Original model motion catalog identity differs')
            m = matches[0]
            bundle = m['bundle']
            if bundle not in environments:
                raw = member(archive, 'bundles/' + bundle, 16_000_000, bundles[bundle]['sha256'])
                require(len(raw) == bundles[bundle]['bytes'], 'Original motion bundle length differs')
                environments[bundle] = UnityPy.load(raw)
            matches = [o for o in environments[bundle].objects if o.path_id == m['path_id']]
            require(len(matches) == 1 and matches[0].type.name == 'TextAsset', 'Original motion object is absent')
            text = matches[0].read().m_Script
            raw = text.encode('utf-8', 'surrogateescape') if isinstance(text, str) else bytes(text)
            require(len(raw) == m['bytes'] and sha(raw) == m['sha256'], 'Original model motion bytes differ')
            arrays = decode(raw)
            require(len(arrays) == 2 and all(a['frame_count'] == raw_frames for a in arrays)
                    and [int(i) for i in arrays[0]['bone_ids']] == m['bone_ids'], 'Original model arrays differ')
            motion = arrays[0]
            raw_motions[stem] = raw
            decoded_motions[suffix] = motion
            window = playback_window(c, raw_frames)
            windows[suffix] = window
            attacks = [i for i in c['Intervals'] if i['Type'] == 'Attack']
            parts = sorted({p for i in attacks for p in i['AttackingParts']})
            require(parts == sorted(PARTS[suffix]), 'Original attacking part inventory differs')
            rows, bones, environment, config, model_audit, bone_raw, config_raw = load_model(kind, args, parts)
            source_xml[kind + '-bones-private.xml'] = bone_raw
            source_xml[kind + '-config-private.xml'] = config_raw
            align = c['Align']
            axes = ['X', 'Y'] if suffix in ('bloom', 'push') else ['X']
            require(len(align) == 7 and align[6] == [None, 'Nodes', anchor] and align[4] == axes
                    and typed(align[3]) == typed(SHIFTS[suffix]), 'Original Align bone, axes or offset differs')
            worlds, roots, names, rest_only = source_poses(rows, bones, motion, window, axes, anchor)
            role = 'serpentSummon_' + suffix
            tracks.append(dict(role=role, clip=stem, frames=window['frames'], sourceSHA256=m['sha256'],
                sourceBundle=bundle, root=np.round(roots, 9).tolist(), groundLift=[0.] * len(roots),
                boneConfigurationSHA256=MODELS[kind]['bonesSHA'],
                collisionEdges=collision_tracks(worlds, roots, names, bones), hurtCapsules=[],
                attackParts={'primary': PARTS[suffix]}, sourceEndEventTick=window['animationEndTick']))
            native_attacks = []
            for index, attack in enumerate(attacks):
                ticks = interval_ticks(attack, window)
                final = min(window['animationEndTick'], ticks['endTickInclusive'])
                effective = dict(startTick=ticks['startTick'], endTick=final) if ticks['startTick'] <= final else None
                native_attacks.append(dict(index=index, original=attack, native=ticks, effective=effective))
            models.append(dict(role=role, sourceAnimation=alias, sourceRecordIndex=record,
                sourceModel=MODELS[kind]['model'], sourceConfigurationSHA256=CONFIGURATION_SHA,
                sourceFile=c['FileName'], motion=window, sourceEndEventTick=window['animationEndTick'],
                sourceDeleteEventTick=window['animationEndTick'], effectiveLastTick=window['animationEndTick'],
                bones={name: [np.round(w[index].T.reshape(-1), 9).tolist() for w in worlds]
                       for name, index in names.items() if name in bones['bones'].values()},
                sourceAttackIntervals=native_attacks, sourceIntervals=c['Intervals'], sourceSounds=c['Sounds'],
                origin=dict(sourceAlign=align, sourceSetDirection=c['SetDirection'], modelScale=1,
                    alignmentBone=anchor, canonicalSourceRightRotation='Ry(pi)', selectedAlignAxes=axes,
                    initialAlignedRootMeters=roots[0].tolist(), sourceShiftCentimeters=align[3],
                    runtimeRule='Apply original target, SetDirection and Shift at birth; add current root X displacement once.')))
            receipts.append(dict(role=role, sourceConfiguration=setting, sourceModel=model_audit,
                originalMotion=dict(m, bundleSHA256=bundles[bundle]['sha256']),
                declaredButUnanimatedBones=rest_only, unboundMotionIDs=[],
                rules=model_rules(rules, alias, kind, lock)))
            if kind == 'root':
                root_export = environment, config, rows, bones
    require(root_export is not None, 'Original vine model was not recovered')
    (output / 'original-sources').mkdir(mode=0o700)
    vine = export_vines(output / GLB_FILE, *root_export, decoded_motions, windows)
    document = dict(schema='original-d13-independent-ability-models-v1', sourceOnly=True, runtimeBound=False,
        sourceArchiveSHA256=ARCHIVE_SHA256, sourceDecodedArchiveSHA256=ARCHIVE_PIN[1],
        sourceNamedSettingsSHA256=SETTINGS_SHA, sourceConfigurationSHA256=CONFIGURATION_SHA,
        summonTracks=tracks, models=models, receipts=receipts, vineGeometry=vine,
        sourceRules=[rules[i] for i in RULE_LOCKS],
        coordinateContract='Model FK in actual meters with Unity Z reflection and canonical source RIGHT Ry(pi). No humanoid scale or visual basis. Requested Align coordinates are removed only at birth. Collision X removes current root displacement, which the arena must add once. Capsule side right is a wire slot, not handedness.',
        boundaries=dict(fullMatchProfile=False, appOrReleaseActivated=False, conditionsEvaluated=False,
            damageOrStatusConverted=False, customShaderParity=False, separateParticleEffectsBound=False,
            commonAndPushAreSourceInvisibleRigs=True, ordinaryFirstArrayOnly=True,
            secondaryOriginalArraysRetained=True, terminalDisplayCommitOrderingVerified=False))
    write_private(output / DOCUMENT_FILE, encoded(document))
    for name, raw in {**source_xml, **rule_originals}.items():
        write_private(output / 'original-sources' / name, raw)
    for stem, raw in raw_motions.items():
        write_private(output / (stem + '.original-private.bytes'), raw)
    # Read the serialized JSON and GLB back, rather than verifying pre-write objects.
    saved = json.loads((output / DOCUMENT_FILE).read_bytes())
    verification = verify_document(saved, raw_motions)
    verification['vineGLB'] = verify_vine_glb(output / GLB_FILE, saved, raw_motions)
    write_private(output / 'readback-private.json', encoded(verification))
    write_private(output / ORACLE_FILE, encoded(world_capsules_oracle(saved, raw_motions)))
    products = [dict(file=str(p.relative_to(output)), bytes=p.stat().st_size, sha256=sha(p.read_bytes()))
                for p in sorted(output.rglob('*')) if p.is_file()]
    receipt = dict(schema='d13-independent-ability-model-receipt-v1', sourceOnly=True, runtimeBound=False,
        sourceArchiveSHA256=ARCHIVE_SHA256, sourceDecodedArchiveSHA256=ARCHIVE_PIN[1],
        sourceNamedSettingsSHA256=SETTINGS_SHA, sourceConfigurationSHA256=CONFIGURATION_SHA,
        sourceModels=list(MODELS.values()), originalMotionRecords=[r['originalMotion'] for r in receipts],
        modelStates=len(models), sourceMeshes=2, sourceVertices=1086, sourceTriangles=888,
        originalSettingsRoundTripVerified=19, selectedSourceRuleLocks=list(RULE_LOCKS),
        verification=verification, products=products, networkBytes=0, decryptionPerformed=False,
        nativeOrAppExecuted=False, gameplayOrReleaseActivated=False)
    write_private(output / 'receipt-private.json', encoded(receipt))
    return receipt


def verify_document(document, motions):
    """Independent centimeter-space FK and capsule readback at every tick."""
    require(document['schema'] == 'original-d13-independent-ability-models-v1'
            and document['sourceOnly'] is True and document['runtimeBound'] is False,
            'An incomplete source candidate must not claim runtime activation')
    tracks = {r['role']: r for r in document['summonTracks']}
    models = {r['role']: r for r in document['models']}
    receipts = {r['role']: r for r in document['receipts']}
    roles = {'serpentSummon_' + d[1] for d in DEFINITIONS}
    require(set(tracks) == set(models) == set(receipts) == roles
            and len(document['summonTracks']) == len(document['models']) == len(document['receipts']) == len(roles),
            'Independent source model inventory differs')
    matrix_count = endpoint_count = 0
    max_matrix_error = max_endpoint_error = 0.
    for record, suffix, kind, alias, stem, raw_frames, crop, anchor, lock in DEFINITIONS:
        role = 'serpentSummon_' + suffix
        t, m, r = tracks[role], models[role], receipts[role]
        raw = motions[stem]
        require(sha(raw) == r['originalMotion']['sha256'] == t['sourceSHA256']
                and len(raw) == r['originalMotion']['bytes'], 'Retained original motion identity differs')
        arrays = decode(raw)
        require(len(arrays) == 2 and all(a['frame_count'] == raw_frames for a in arrays), 'Original arrays differ')
        a = arrays[0]
        frames = crop or raw_frames
        samples = 2 * frames - 1
        require(t['frames'] == frames and t['clip'] == stem and len(t['root']) == len(t['groundLift']) == samples
                and t['sourceEndEventTick'] == m['sourceEndEventTick'] == m['sourceDeleteEventTick'] == samples - 1
                and m['sourceAnimation'] == alias and m['sourceRecordIndex'] == record
                and m['origin']['alignmentBone'] == anchor and m['motion']['frames'] == frames,
                'Cropped model clock, source anchor or deletion event differs')
        require(all(v == 0 for v in t['groundLift']), 'Independent model acquired a guessed floor correction')
        source = r['sourceModel']
        require(source['sourceBundleSHA256'] == MODELS[kind]['sha256']
                and source['sourceBonesSHA256'] == t['boneConfigurationSHA256'] == MODELS[kind]['bonesSHA'],
                'Original model bundle or bone identity differs')
        declarations = source['sourceDeclarations']
        bone_ids = {int(k): v for k, v in declarations['bones'].items()}
        rows = {row['name']: row for row in source['originalPrefabHierarchy']}
        columns = {bone_ids[int(n)]: col for col, n in enumerate(a['bone_ids'])}
        require(set(m['bones']) == set(bone_ids.values()), 'Written source bone set differs')
        axes = m['origin']['selectedAlignAxes']
        expected_axes = ['X', 'Y'] if suffix in ('bloom', 'push') else ['X']
        require(axes == expected_axes and typed(m['origin']['sourceShiftCentimeters']) == typed(SHIFTS[suffix]),
                'Source Align axes or offset changed')
        roots = np.asarray(t['root'])
        for tick in range(samples):
            i, j, f = tick // 2, min(tick // 2 + 1, frames - 1), tick % 2 * .5
            cache = {}
            def world(name):
                if name not in cache:
                    row = rows[name]
                    if name in columns:
                        col = columns[name]
                        p = a['positions'][i, col].astype(float) * (1 - f) + a['positions'][j, col].astype(float) * f
                        q0, q1 = a['rotations'][i, col].astype(float), a['rotations'][j, col].astype(float)
                        if q0 @ q1 < 0:
                            q1 = -q1
                        q = q0 * (1 - f) + q1 * f
                    else:
                        p, q = row['translation'], row['rotation']
                    local = matrix(p, q, row['scale'])
                    cache[name] = world(row['parent']) @ local if row['parent'] is not None else local
                return cache[name]
            raw_root = (SOURCE_RIGHT @ C @ world(anchor) @ CI)[:3, 3]
            require(np.max(np.abs(roots[tick] - raw_root)) < 1e-8, 'Source root motion readback differs')
            for name in bone_ids.values():
                expected = SOURCE_RIGHT @ C @ world(name) @ CI
                for axis in axes:
                    k = 'XYZ'.index(axis)
                    expected[k, 3] -= roots[0, k]
                actual = np.asarray(m['bones'][name][tick]).reshape(4, 4).T
                error = float(np.max(np.abs(expected - actual)))
                require(error < 1e-8, 'Source model FK readback differs')
                max_matrix_error = max(max_matrix_error, error)
                matrix_count += 1
        edges = {edge['id']: edge for edge in t['collisionEdges']}
        capsules = {capsule['id']: capsule for capsule in declarations['capsules']}
        require(set(edges) == set(capsules) == set(PARTS[suffix])
                and t['attackParts'] == {'primary': PARTS[suffix]}, 'Source attacking parts changed')
        for part, edge in edges.items():
            capsule = capsules[part]
            require(edge['radiusMillimeters'] == capsule['radiusCentimeters'] * 10 and edge['side'] == 'right',
                    'Original capsule radius or wire slot differs')
            for endpoint in ('base', 'tip'):
                require(len(edge[endpoint]) == samples, 'Capsule sample count differs')
                vertex = capsule[endpoint]
                local = C @ np.array([*vertex['localPositionCentimeters'], 1.])
                for tick in range(samples):
                    bone = np.asarray(m['bones'][vertex['bone']][tick]).reshape(4, 4).T
                    expected = (bone @ local)[:3]
                    actual = np.array(edge[endpoint][tick])
                    actual[0] += roots[tick, 0] - roots[0, 0]
                    error = float(np.max(np.abs(expected - actual)))
                    require(error < 3e-8, 'Collision and FK do not reconstruct the same endpoint')
                    max_endpoint_error = max(max_endpoint_error, error)
                    endpoint_count += 1
        attack = m['sourceAttackIntervals']
        expected_start, expected_end = (8, 149) if kind == 'root' else (0, samples - 1)
        require(len(attack) == 1 and attack[0]['effective'] == dict(startTick=expected_start, endTick=expected_end),
                'Source attack interval differs from cropped model lifetime')
        require(r['rules']['sourceLock'] == lock and r['rules']['conditionsEvaluated'] is False,
                'Source model deletion gate identity differs')
    return dict(passed=True, models=len(roles), sourceTicks=433, matrixSamples=matrix_count,
        capsuleEndpoints=endpoint_count, maximumMatrixErrorMeters=max_matrix_error,
        maximumEndpointErrorMeters=max_endpoint_error)


def verify_vine_glb(path, document, motions):
    """Compare written GLB skeleton and skin to original arrays and bind poses."""
    require(sha(path.read_bytes()) == document['vineGeometry']['sha256'], 'Vine GLB identity differs')
    g, binary = glb_read(path)
    require(len(g['meshes']) == 2 and len(g['skins']) == 2 and len(g['animations']) == 2,
            'Original vine mesh/animation inventory differs')
    _, rest, parents = world_poses(g['nodes'])
    names = {n['name']: i for i, n in enumerate(g['nodes'])}
    reference_meshes = []
    for source in document['vineGeometry']['referenceMeshes']:
        node = g['nodes'][names[source['name']]]
        skin = g['skins'][node['skin']]
        require(skin['joints'] == [names[n] for n in source['sourceBindingNames']], 'Source ordered skin binding differs')
        attributes = g['meshes'][node['mesh']]['primitives'][0]['attributes']
        positions = accessor_read(g, binary, attributes['POSITION'])
        indices = accessor_read(g, binary, attributes['JOINTS_0'])
        weights = accessor_read(g, binary, attributes['WEIGHTS_0'])
        inverse = accessor_read(g, binary, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        require(np.array_equal(indices, source['joints']) and np.max(np.abs(weights - source['weights'])) < 1e-7,
                'Original root mesh skin lanes changed')
        require(np.max(np.abs(positions - source['positions'])) < 1e-6
                and np.max(np.abs(inverse - source['inverseBindMatrices'])) < 1e-6,
                'Original root mesh vertices or inverse binds changed')
        reference_meshes.append((source, positions, indices, weights, inverse, skin['joints']))
    matrix_count = vertex_count = 0
    max_matrix_error = max_skin_error = 0.
    for animation in g['animations']:
        definition = next(d for d in DEFINITIONS if d[3] == animation['name'])
        _, suffix, _, _, stem, frames, _, _, _ = definition
        receipt = next(r for r in document['receipts'] if r['role'] == 'serpentSummon_' + suffix)
        original = decode(motions[stem])[0]
        rows = receipt['sourceModel']['originalPrefabHierarchy']
        bone_ids = {int(k): v for k, v in receipt['sourceModel']['sourceDeclarations']['bones'].items()}
        columns = {bone_ids[int(n)]: col for col, n in enumerate(original['bone_ids'])}
        samples = 2 * frames - 1
        require(len(animation['channels']) == 42, 'Missing original root bone channels')
        channels = {}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            times = accessor_read(g, binary, sampler['input'])
            require(times.shape == (samples,) and np.max(np.abs(times - np.arange(samples) / 60)) < 3e-7,
                    'Vine GLB does not preserve exact ordinary half-frame keys')
            channels[(channel['target']['node'], channel['target']['path'])] = accessor_read(g, binary, sampler['output'])
        for tick in range(samples):
            i, j, f = tick // 2, min(tick // 2 + 1, frames - 1), tick % 2 * .5
            actual_local = [m.copy() for m in rest]
            expected_local = [m.copy() for m in rest]
            for row in rows:
                name = row['name']
                node = names[name]
                if name in columns:
                    col = columns[name]
                    p = original['positions'][i, col].astype(float) * (1 - f) + original['positions'][j, col].astype(float) * f
                    q0, q1 = original['rotations'][i, col].astype(float), original['rotations'][j, col].astype(float)
                    if q0 @ q1 < 0:
                        q1 = -q1
                    q = q0 * (1 - f) + q1 * f
                    actual_local[node] = matrix(channels[(node, 'translation')][tick], channels[(node, 'rotation')][tick], [1, 1, 1])
                else:
                    p, q = row['translation'], row['rotation']
                expected_local[node] = C @ matrix(p, q, row['scale']) @ CI
            expected, actual = pose_world(expected_local, parents), pose_world(actual_local, parents)
            for name in columns:
                error = float(np.max(np.abs(expected[names[name]] - actual[names[name]])))
                require(error < 2e-5, 'Written GLB FK differs from original source arrays')
                max_matrix_error = max(max_matrix_error, error)
                matrix_count += 1
            for source, positions, indices, weights, inverse, joints in reference_meshes:
                source_p = np.c_[source['positions'], np.ones(len(positions))]
                written_p = np.c_[positions, np.ones(len(positions))]
                expected_p = np.zeros((len(positions), 3))
                actual_p = np.zeros_like(expected_p)
                source_inverse = np.asarray(source['inverseBindMatrices'])
                source_weights = np.asarray(source['weights'])
                for lane in range(4):
                    for slot in np.unique(indices[:, lane]):
                        mask = indices[:, lane] == slot
                        source_result = (expected[joints[slot]] @ source_inverse[slot] @ source_p[mask].T).T[:, :3]
                        written_result = (actual[joints[slot]] @ inverse[slot] @ written_p[mask].T).T[:, :3]
                        expected_p[mask] += source_result * source_weights[mask, lane, None]
                        actual_p[mask] += written_result * weights[mask, lane, None]
                error = float(np.max(np.abs(expected_p - actual_p)))
                require(error < 2e-5, 'Written root skin differs from original vertices, weights or inverse binds')
                max_skin_error = max(max_skin_error, error)
                vertex_count += len(positions)
    return dict(passed=True, animations=2, sourceTicks=358, boneMatrixSamples=matrix_count,
        skinnedVertexComparisons=vertex_count, maximumMatrixErrorMeters=max_matrix_error,
        maximumSkinErrorMeters=max_skin_error, sourceMeshes=2, sourceVertices=1086,
        sourceTriangles=888, customShaderParity=False)


def world_capsules_oracle(document, motions):
    """Small Swift oracle from original centimeter FK, never exported edges.

    Actor positions here are already source meters. Source RIGHT is the
    canonical orientation. Resolve SetDirection first, apply Align on exactly
    its authored axes and rotate both X and Z when direction is negative.
    """
    owner = np.array([3.5, 1.1, .2])
    enemy = np.array([5.3, 1.2, -.1])
    cases = []
    for record, suffix, kind, alias, stem, raw_frames, crop, anchor, _ in DEFINITIONS:
        role = 'serpentSummon_' + suffix
        receipt = next(r for r in document['receipts'] if r['role'] == role)
        raw = motions[stem]
        require(sha(raw) == receipt['originalMotion']['sha256'], 'Oracle original motion identity differs')
        original = decode(raw)[0]
        frames = crop or raw_frames
        last = 2 * frames - 2
        attack_start, attack_end = (8, 149) if kind == 'root' else (0, last)
        ticks = sorted({0, attack_start, (attack_start + attack_end) // 2, attack_end, last})
        source = receipt['sourceModel']
        rows = {r['name']: r for r in source['originalPrefabHierarchy']}
        declarations = source['sourceDeclarations']
        bone_ids = {int(k): v for k, v in declarations['bones'].items()}
        columns = {bone_ids[int(n)]: col for col, n in enumerate(original['bone_ids'])}
        c = receipt['sourceConfiguration']['configuration']
        axes = c['Align'][4]
        def original_world(tick):
            i, j, f = tick // 2, min(tick // 2 + 1, frames - 1), tick % 2 * .5
            cache = {}
            def world(name):
                if name not in cache:
                    row = rows[name]
                    if name in columns:
                        col = columns[name]
                        p = original['positions'][i, col].astype(float) * (1 - f) + original['positions'][j, col].astype(float) * f
                        q0, q1 = original['rotations'][i, col].astype(float), original['rotations'][j, col].astype(float)
                        if q0 @ q1 < 0:
                            q1 = -q1
                        q = q0 * (1 - f) + q1 * f
                    else:
                        p, q = row['translation'], row['rotation']
                    local = matrix(p, q, row['scale'])
                    cache[name] = world(row['parent']) @ local if row['parent'] is not None else local
                return cache[name]
            for name in rows:
                world(name)
            return cache
        initial = (SOURCE_RIGHT @ C @ original_world(0)[anchor])[:3, 3]
        for requested_direction in (1, -1):
            direction = -1 if suffix == 'bloom' else requested_direction
            # Shift is a source local offset, not an actor's vertical/depth origin.
            target = enemy if suffix in ('bloom', 'push') else owner
            shift = np.asarray(c['Align'][3] or [0., 0., 0.]) * .01
            rotation = np.diag([direction, 1., direction])
            birth = np.zeros(3)
            for axis in axes:
                k = 'XYZ'.index(axis)
                birth[k] = target[k] + (rotation @ shift)[k]
            for tick in ticks:
                worlds = original_world(tick)
                capsules = []
                for capsule in declarations['capsules']:
                    endpoints = {}
                    for endpoint in ('base', 'tip'):
                        vertex = capsule[endpoint]
                        # Source FK and XML endpoint are multiplied in centimeters
                        # before conversion. No track-root decomposition is reused.
                        point = (SOURCE_RIGHT @ C @ worlds[vertex['bone']]
                                 @ np.array([*vertex['localPositionCentimeters'], 1.]))[:3]
                        for axis in axes:
                            k = 'XYZ'.index(axis)
                            point[k] -= initial[k]
                        endpoints[endpoint] = np.round(birth + rotation @ point, 12).tolist()
                    capsules.append(dict(id=capsule['id'], radiusMeters=capsule['radiusCentimeters'] * .01,
                                         **endpoints))
                cases.append(dict(role=role, sourceRecordIndex=record, sourceAnimation=alias,
                    requestedDirection=requested_direction, direction=direction, tick=tick,
                    attackActive=attack_start <= tick <= attack_end,
                    birthOriginMeters=birth.tolist(), capsules=capsules))
    return dict(schema='d13-world-capsules-source-oracle-v1', sourceOnly=True, runtimeBound=False,
        sourceModelDocumentSHA256=sha(encoded(document)), sourceArchiveSHA256=ARCHIVE_SHA256,
        ownerPelvisMeters=owner.tolist(), enemyPelvisMeters=enemy.tolist(), cases=cases,
        oracleMethod='Independent original compressed arrays -> centimeter-space prefab FK -> original BonesData endpoint -> C and canonical RIGHT -> exact initial Align axes -> resolved facing and birth offset.',
        coordinateContract='Source meters, no actor .92 scale. Left turns X and Z. Bloom always DirectionLeft. No owner/target Z offset, and no owner Y offset for helmet or vines. Current root displacement is present exactly once in the original FK.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-archive', 'recovery', 'model-inputs', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    receipt = build(args)
    print(json.dumps(dict(output=str(args.output), models=receipt['modelStates'],
        verification=receipt['verification'], receiptSHA256=sha((args.output / 'receipt-private.json').read_bytes())),
        separators=(',', ':')))


if __name__ == '__main__':
    main()
