#!/usr/bin/env python3
"""Convert the authenticated D15 hound on its own source rig, entirely offline.

Inputs are already recovered private bundles and decoded XML. The original
141-frame motion is retained as evidence; the configured playback is frames
1 through 60. No source media is written inside the repository. The result is
an independently bindable companion, never a humanoid animation substitute.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import warnings
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np

from sun_triad_assets import (C, CI, RIGHT, Writer, accessor_read, decode, glb_read,
                             matrix, pose_world, private_output, quaternion,
                             require, skin_slots, world_poses, write_private,
                             capsule_point)
from sun_triad_materials import original_material, material_descriptor
from sun_triad_source_bones import parse_bones_data
from sun_triad_spirits import source_rig

MODEL = 'mgc__d15_dog'
ROLE = 'erlangSummon_hound'
CLIP = 'd15_dog_attack'
MODEL_BUNDLE = '9d5fd54b70a5568f2cdc1f204770f78d.bin'
MODEL_SHA = '2cbb991e2d8ece154c56d95e776d3be2ac72c6d09df5c09d5413cdaf1fe4dea8'
MOTION_BUNDLE = '2a784bc550bc06541a38a4c1c53b69f3.bin'
MOTION_BUNDLE_SHA = '093b534cd7c509cf393b531e1dfc5f12f91e7a113c0153bf40bfe6bcdb5c5e6b'
MOTION_PATH_ID = 7057222478336785206
MOTION_SHA = '6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712'
BONES_NAME = '9d5fd54b70a5568f2cdc1f204770f78d_1561239813228986013_bones.clear-private.xml'
BONES_SHA = '72f0791d0bd777caa31d7616feee71e737ccc67aa40f4827c49b1203f639c82d'
CONFIG_NAME = '9d5fd54b70a5568f2cdc1f204770f78d_-3764057698382726492_config.clear-private.xml'
CONFIG_SHA = '067a8a8560b317c42d4c6e8cbbd5d619c66a7f619ac5f99db8f807e55c1030a0'
SETTINGS_SHA = '030ca65a96c38e1c335507c2d17c9570716e29510f85305a8e4d905fc179beaa'
RECOVERED_SETTINGS_SHA = '259db85e76a7bb4175d3fc037012f0fa53e6c04eb8d9a08ba7b27ea66d6f4bb6'
RECOVERED_ARCHIVE_SHA = '02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a'
RECOVERED_ANIMATION_SPLIT_SHA = 'efe3e5d48819adc1106302dacb2b9e94352d5b6735e79a7018a546b19531ab29'
SOURCE_CONFIGURATION_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'
PARTS = ['Dog_Head_Attacking_Edge', 'Dog_Body_Attacking_Edge',
         'Dog_Front_Attacking_Edge_l', 'Dog_Front_Attacking_Edge_r']
CENTRAL_PARTS = {'Dog_Head_Attacking_Edge', 'Dog_Body_Attacking_Edge'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked(path, digest, maximum):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            'Missing or oversized source: ' + path.name)
    raw = path.read_bytes()
    require(sha(raw) == digest, 'Source integrity mismatch: ' + path.name)
    return raw


def source_configuration(raw):
    document = json.loads(raw)
    records = [row for row in document['records']
               if row['configuration']['Animation'] == 'D15_Ability_Dog_Attack_Model']
    require(len(records) == 1, 'Ambiguous original hound animation')
    row = records[0]
    require(row['sourceEntry'] == 'settings_sets_dynasty.bytes'
            and row['sourceRecordIndex'] == 93
            and row['sourceSHA256'] == SOURCE_CONFIGURATION_SHA,
            'Wrong source hound configuration')
    c = row['configuration']
    require(c['FileName'] == 'unique_moves/sets_d15/d15_dog_attack.bin'
            and c['FirstFrame'] is None and c['EndFrame'] == 60
            and c['MidFrames'] is None and c['BlendingFrames'] == 0
            and c['SelfEndFrame'] is None and c['Looped'] is None,
            'Unsupported source hound playback window')
    attacks = [i for i in c['Intervals'] if i['Type'] == 'Attack']
    require(len(attacks) == 1 and attacks[0]['Start'] == 12 and attacks[0]['End'] == 34
            and attacks[0]['AttackingParts'] == PARTS,
            'Original hound attack window or parts differ')
    require(c['Align'] == [[0., 0., 0.], None, None, [0., 0., 0.], ['X'],
                          ['Parent', 'Nodes', 'pelvis'], [None, 'Nodes', 'spine_root_joint']],
            'Original hound X-only anchor differs')
    return row


def settings_input(path, settings_format='historical'):
    require(settings_format in ('historical', 'recovered-d15-v1'), 'Unknown named-settings format')
    recovered = settings_format == 'recovered-d15-v1'
    raw = checked(path, RECOVERED_SETTINGS_SHA if recovered else SETTINGS_SHA, 4_000_000)
    recovery = None
    if recovered:
        document = json.loads(raw)
        require(document['schema'] == 'recovered-erlang-named-animation-source-v1'
                and document['suppliedClientVersion'] == '1.46.1'
                and document['packagedConfigurationVersion'] == '1.46.0.16.16733-prod'
                and document['sourceDecodedArchiveSHA256'] == RECOVERED_ARCHIVE_SHA
                and document['sourceAnimationSplitSHA256'] == RECOVERED_ANIMATION_SPLIT_SHA
                and document['nativeSchemaMethod'] == 16684
                and document['originalValuesAndTypesPreserved'] is True
                and document['existingBuilderPinsChanged'] is False,
                'Recovered named-settings source identity differs')
        rows = document['records']
        require(len(rows) == 45 and [row['sourceRecordIndex'] for row in rows] == list(range(89, 134))
                and all(type(row['sourceRecordIndex']) is int
                        and row['sourceEntry'] == 'settings_sets_dynasty.bytes'
                        and row['sourceSHA256'] == SOURCE_CONFIGURATION_SHA for row in rows),
                'Expected the exact 45 original D15 records')
        recovery = dict(format=settings_format, file=path.name, bytes=len(raw), sha256=sha(raw),
            records=45, sourceRecordIndices=list(range(89, 134)),
            historicalNamedSettingsSHA256=SETTINGS_SHA, historicalNamedSettingsBytesRestored=False,
            sourceDecodedArchiveSHA256=RECOVERED_ARCHIVE_SHA,
            sourceAnimationSplitSHA256=RECOVERED_ANIMATION_SPLIT_SHA,
            nativeSchemaMethod=16684, nativeSchemaCodeSHA256=document['nativeSchemaCodeSHA256'])
    # Both input identities retain the same complete record-93 source checks.
    return source_configuration(raw), recovery


def playback_window(configuration, raw_frames):
    require(raw_frames == 141, 'Original hound frame count differs')
    require(configuration['FirstFrame'] is None and configuration['EndFrame'] == 60
            and configuration['MidFrames'] is None and configuration['SelfEndFrame'] is None,
            'Hound source clock differs')
    # Native default MidFrames=1 adds one interpolation tick per source frame.
    # FirstFrame is one based; the native default SelfEndFrame is four.
    return dict(sourceFrames=141, firstSourceFrame=1, lastSourceFrame=60,
                frames=60, samplesPerSourceFrame=2, lastSampleTick=118,
                endEventTick=110, exportFramesPerSecond=30)


def edge_definition(capsule):
    radius = capsule['radiusCentimeters'] * 10
    require(radius == round(radius) and 1 <= radius <= 2000,
            'Unsupported original hound radius')
    name = capsule['id']
    require(name.endswith(('_l', '_r')) or name in CENTRAL_PARTS,
            'Unknown original hound capsule side')
    # Existing edge wire format has two side slots. Central source capsules are
    # not mirrored weapon copies: right is their stable serialization slot only.
    side = 'left' if name.endswith('_l') else 'right'
    return dict(id=name, side=side, radiusMillimeters=round(radius), base=[], tip=[])


def sample_tracks(document, binary, bones, frames):
    names = {n['name']: i for i, n in enumerate(document['nodes'])}
    _, rest, parents = world_poses(document['nodes'])
    require(len(document['animations']) == 1, 'Unexpected companion clip count')
    animation = document['animations'][0]
    channels = []
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        values = accessor_read(document, binary, sampler['output']).astype(float)
        require(len(values) == frames and sampler['interpolation'] == 'LINEAR',
                'Original hound samples changed')
        channels.append((channel['target']['node'], channel['target']['path'], values))
    capsules = bones['capsules']
    edges = [edge_definition(c) for c in capsules]
    for tick in range(2 * frames - 1):
        first, second = tick // 2, min(frames - 1, tick // 2 + 1)
        fraction = (tick % 2) * .5
        values = {}
        for node, path, array in channels:
            a, b = array[first], array[second]
            if path == 'rotation' and a @ b < 0:
                b = -b
            values.setdefault(node, {})[path] = a * (1 - fraction) + b * fraction
        local = [m.copy() for m in rest]
        for node, fields in values.items():
            source = document['nodes'][node]
            local[node] = matrix(fields.get('translation', source.get('translation', [0, 0, 0])),
                                 fields.get('rotation', source.get('rotation', [0, 0, 0, 1])),
                                 source.get('scale', [1, 1, 1]))
        world = pose_world(local, parents)
        for source, target in zip(capsules, edges):
            for endpoint in ('base', 'tip'):
                target[endpoint].append(np.round(capsule_point(source[endpoint], world, names), 7).tolist())
    return edges


def build(args):
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    model_raw = checked(args.models / MODEL_BUNDLE, MODEL_SHA, 300_000)
    motion_bundle = checked(args.motions / MOTION_BUNDLE, MOTION_BUNDLE_SHA, 2_000_000)
    bone_raw = checked(args.configs / BONES_NAME, BONES_SHA, 10_000)
    model_config_raw = checked(args.configs / CONFIG_NAME, CONFIG_SHA, 1_000)
    source, settings_recovery = settings_input(args.settings, getattr(args, 'settings_format', 'historical'))
    bones = parse_bones_data(bone_raw)
    require(len(bones['bones']) == 50 and len(bones['capsules']) == 6,
            'Original hound BonesData changed')
    require(set(PARTS).issubset({c['id'] for c in bones['capsules']}), 'Missing source hound part')
    config = ET.fromstring(model_config_raw)
    require(config.tag == 'ModelObject' and config.get('Name') == MODEL
            and [x.attrib for x in config.findall('./Prefabs/Prefab')] == [{'Name': MODEL}]
            and [x.attrib for x in config.findall('./Meshes/Mesh')] == [{'Name': MODEL}],
            'Original hound model activation changed')
    environment = UnityPy.load(model_raw)
    prefix = 'assets/gamedata/resources/content/items/models/' + MODEL + '/m/'
    prefab = environment.container[prefix + 'prefabs/' + MODEL + '.prefab']
    rows = source_rig(prefab)
    names = {r['name']: i for i, r in enumerate(rows)}
    require(len(rows) == 52 and set(bones['bones'].values()).issubset(names),
            'Original hound rig is incomplete')
    mesh_prefab = environment.container[prefix + 'meshes/' + MODEL + '.prefab']
    components = mesh_prefab.read().m_Component
    renderers = [x.component.read() for x in components if x.component.deref().type.name == 'SkinnedMeshRenderer']
    bindings = [(x.component.path_id, x.component.deref().read_typetree()) for x in components
                if x.component.deref().type.name == 'MonoBehaviour']
    bindings = [(pid, data) for pid, data in bindings if '_bindBonesName' in data]
    transforms = [x.component.read() for x in components if x.component.deref().type.name == 'Transform']
    require(len(renderers) == len(bindings) == len(transforms) == 1, 'Ambiguous source hound skin')
    renderer = renderers[0]
    binding_id, binding = bindings[0]
    bound_names = binding['_bindBonesName']
    require(binding['_rootBoneName'] == 'spine_root_joint' and len(bound_names) == 50
            and len(set(bound_names)) == 50 and set(bound_names) == set(bones['bones'].values())
            and binding['cullMode'] == 0, 'Original hound skin binding differs')
    transform = transforms[0]
    source_mesh_matrix = matrix([transform.m_LocalPosition.x, transform.m_LocalPosition.y, transform.m_LocalPosition.z],
                                [transform.m_LocalRotation.x, transform.m_LocalRotation.y, transform.m_LocalRotation.z, transform.m_LocalRotation.w],
                                [transform.m_LocalScale.x, transform.m_LocalScale.y, transform.m_LocalScale.z])
    mesh_space = C @ source_mesh_matrix @ CI
    mesh = renderer.m_Mesh.read()
    require(len(mesh.m_BindPose) == len(mesh.m_BoneNameHashes) == 50, 'Original hound bind matrix count differs')
    handler = MeshHandler(mesh)
    handler.process()
    indices = np.asarray(handler.m_BoneIndices, dtype=int)
    weights = np.asarray(handler.m_BoneWeights, dtype=float)
    require(indices.min() >= 0 and indices.max() < len(bound_names), 'Invalid source hound skin index')
    mapping = np.array([names[name] for name in bound_names])
    joints, weights = skin_slots(mapping[indices], weights)
    world_bind = {}
    for index, name in enumerate(bound_names):
        source_bind = mesh.m_BindPose[index]
        bind = np.array([[getattr(source_bind, f'e{y}{x}') for x in range(4)] for y in range(4)])
        world_bind[names[name]] = mesh_space @ np.linalg.inv(C @ bind @ CI)
    writer = Writer()
    g = writer.g
    g['asset']['generator'] = 'Authenticated original D15 hound private exporter'
    worlds = {}
    for index, row in enumerate(rows):
        parent = names.get(row['parent'])
        previous = worlds[parent] if parent is not None else np.eye(4)
        world = world_bind.get(index, previous @ C @ matrix(row['translation'], row['rotation'], row['scale']) @ CI)
        local = np.linalg.inv(previous) @ world
        scale = np.linalg.norm(local[:3, :3], axis=0)
        node = dict(name=row['name'], translation=local[:3, 3].tolist(),
                    rotation=quaternion(local[:3, :3] / scale).tolist(), scale=scale.tolist())
        children = [i for i, r in enumerate(rows) if r['parent'] == row['name']]
        if children:
            node['children'] = children
        g['nodes'].append(node)
        worlds[index] = world
    g['skins'].append(dict(name='Original D15 hound rig', joints=list(range(len(rows))), skeleton=0,
                          inverseBindMatrices=writer.acc([np.linalg.inv(worlds[i]).T.reshape(16) for i in range(len(rows))], 'MAT4')))
    vertices = np.asarray(handler.m_Vertices)[:, :3] * [.01, .01, -.01]
    vertices = (np.c_[vertices, np.ones(len(vertices))] @ mesh_space.T)[:, :3]
    normals = (np.asarray(handler.m_Normals)[:, :3] * [1, 1, -1]) @ np.linalg.inv(mesh_space[:3, :3])
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    uv = np.asarray(handler.m_UV0)[:, :2].copy()
    uv[:, 1] = 1 - uv[:, 1]
    attributes = dict(POSITION=writer.acc(vertices, 'VEC3'), NORMAL=writer.acc(normals, 'VEC3'),
                      TEXCOORD_0=writer.acc(uv, 'VEC2'), JOINTS_0=writer.acc(joints, 'VEC4', 5123),
                      WEIGHTS_0=writer.acc(weights, 'VEC4'))
    primitives, cache = [], {}
    require(len(renderer.m_Materials) == 1, 'Unexpected hound material count')
    for triangles in handler.get_triangles():
        triangle_indices = np.asarray(triangles, dtype=np.uint32).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
        require(len(triangle_indices) > 0, 'Empty source hound mesh')
        material = original_material(writer, renderer.m_Materials[0].read(), cache, double_sided_override=True)
        primitives.append(dict(attributes=attributes, indices=writer.acc(triangle_indices, 'SCALAR', 5125), material=material))
    g['meshes'].append(dict(name=MODEL, primitives=primitives))
    mesh_node = len(g['nodes'])
    g['nodes'].append(dict(name=MODEL + '_source_geometry', mesh=0, skin=0))
    outer = len(g['nodes'])
    g['nodes'].append(dict(name='SF3_Actor_Meters', children=[0, mesh_node], scale=[1, 1, 1],
                           rotation=[0, -float(np.sqrt(.5)), 0, float(np.sqrt(.5))]))
    g['scenes'][0]['nodes'] = [outer]
    rest_world, _, parents = world_poses(g['nodes'])
    root_node = names['spine_root_joint']
    basis = RIGHT[:3, :3] @ rest_world[parents[root_node]][:3, :3]
    source_environment = UnityPy.load(motion_bundle)
    source_objects = [o for o in source_environment.objects if o.path_id == MOTION_PATH_ID]
    require(len(source_objects) == 1 and source_objects[0].type.name == 'TextAsset', 'Missing original hound motion object')
    value = source_objects[0].read().m_Script
    motion_raw = value.encode('utf8', 'surrogateescape') if isinstance(value, str) else bytes(value)
    require(len(motion_raw) == 138950 and sha(motion_raw) == MOTION_SHA, 'Original hound motion integrity mismatch')
    arrays = decode(motion_raw)
    require(len(arrays) == 2 and all(a['frame_count'] == 141 for a in arrays), 'Original hound arrays differ')
    motion = arrays[0]
    window = playback_window(source['configuration'], motion['frame_count'])
    columns = {bones['bones'][int(i)]: column for column, i in enumerate(motion['bone_ids'])}
    require(len(columns) == 41 and 'spine_root_joint' in columns and set(columns).issubset(names),
            'Original hound motion IDs do not resolve to the hound rig')
    frames = window['frames']
    times = writer.acc(np.arange(frames) / 30., 'SCALAR')
    animation = dict(name=CLIP, channels=[], samplers=[], extras=dict(sourceSHA256=MOTION_SHA,
                    sourceArrayCount=2, sourceFrames=141, sourceFirstFrame=1, sourceEndFrame=60,
                    sourceMidFrames=1, sourceFrameStride=2, sourceFPS=30, simulationHz=60,
                    horizontalRootSeparated=True))
    for name, column in columns.items():
        position = motion['positions'][:frames, column].astype(float) * [.01, .01, -.01]
        if name == 'spine_root_joint':
            position[:, [0, 2]] = 0
        rotation = motion['rotations'][:frames, column].astype(float) * [-1, -1, 1, 1]
        rotation /= np.linalg.norm(rotation, axis=1)[:, None]
        for frame in range(1, frames):
            if rotation[frame - 1] @ rotation[frame] < 0:
                rotation[frame] *= -1
        for path, data, kind in [('translation', position, 'VEC3'), ('rotation', rotation, 'VEC4')]:
            index = len(animation['samplers'])
            animation['samplers'].append(dict(input=times, output=writer.acc(data, kind), interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=index, target=dict(node=names[name], path=path)))
    g['animations'].append(animation)
    raw_root = motion['positions'][:frames, columns['spine_root_joint']].astype(float) * [.01, .01, -.01]
    root_delta = (raw_root - raw_root[0]) @ basis.T
    roots = [root_delta[t // 2] * (1 - (t % 2) / 2) + root_delta[min(frames - 1, t // 2 + 1)] * ((t % 2) / 2)
             for t in range(2 * frames - 1)]
    g['extras'] = dict(sourceModel=MODEL, sourceBundle=MODEL_BUNDLE, sourceMotionBundle=MOTION_BUNDLE,
                       sourceSkinPreserved=True, sourceScale=1, rootBone='spine_root_joint',
                       rootHorizontalTranslationAppliedSeparately=True,
                       sourceFirstFrame=1, sourceEndFrame=60, originalMotionFrames=141,
                       materialAdapter='Original baseline palette; source custom lighting, timed SetSkinColor and morph shader are not claimed equivalent.')
    output = private_output(args.output)
    require(not output.exists() or not any(output.iterdir()), 'Candidate directory must be empty')
    output.mkdir(parents=True, exist_ok=True)
    model_path = output / 'SF3WE_D15_Hound.glb'
    model_file = dict(name=model_path.name, **writer.save(model_path))
    # Read the emitted float32 GLB for physics samples, so rendering and damage
    # use the same imported pose and interpolation rather than separate math.
    document, binary = glb_read(model_path)
    edges = sample_tracks(document, binary, bones, frames)
    root_points = np.round(roots, 7).tolist()
    track = dict(role=ROLE, clip=CLIP, frames=frames, sourceSHA256=MOTION_SHA, sourceBundle=MOTION_BUNDLE,
                 root=root_points, groundLift=[0.] * len(roots), boneConfigurationSHA256=BONES_SHA,
                 collisionEdges=edges, hurtCapsules=[], attackParts={'primary': PARTS}, sourceEndEventTick=110)
    attack_source = next(i for i in source['configuration']['Intervals'] if i['Type'] == 'Attack')
    attack = dict(id='d15_hound_source_93', ability='hound', role='erlangHound', modelRole=ROLE,
                  sourceConfigurationSHA256=SOURCE_CONFIGURATION_SHA, sourceRecordIndex=93,
                  startTick=22, endTick=67, parts=PARTS, damageKind='shadow', baseDamageBps=1500,
                  unblockable=True, knocksDown=True,
                  impact=dict(distanceMillimeters=200, durationTicks=10, launchVelocityMillimetersPerTick=0,
                              gravityMillimetersPerTickSquared=18), hitStopTicks=2)
    record = dict(schema='original-d15-hound-candidate-v1', role=ROLE, sourceModel=MODEL,
                  modelFile=model_file, materials=[material_descriptor(m) for m in g['materials']],
                  skinRoots=[], rootBone='spine_root_joint', motion=window, track=track, attackBinding=attack,
                  releaseBinding=dict(id='d15_hound_release', ability='hound', ownerRole='erlangHound', atTick=8,
                                      modelRole=ROLE, anchor='pelvis.x', offset=[0, 0, 0], minimumLevel=2),
                  originalMotion=dict(bytes=len(motion_raw), sha256=MOTION_SHA, bundle=MOTION_BUNDLE,
                                      bundleSHA256=MOTION_BUNDLE_SHA, pathID=str(MOTION_PATH_ID), arrays=2, frames=141,
                                      boneIDs=[int(i) for i in motion['bone_ids']]),
                  sourceModelBundle=dict(file=MODEL_BUNDLE, bytes=len(model_raw), sha256=MODEL_SHA),
                  sourceModelConfig=dict(file=CONFIG_NAME, bytes=len(model_config_raw), sha256=CONFIG_SHA),
                  sourceBones=dict(file=BONES_NAME, bytes=len(bone_raw), sha256=BONES_SHA),
                  sourceConfiguration=source, sourceSkinDataPathID=str(binding_id),
                  sourceSkinBoneNames=bound_names, sourceRigNodes=rows,
                  sourceSkinBindMatrices=[[[getattr(m, f'e{y}{x}') for x in range(4)] for y in range(4)] for m in mesh.m_BindPose],
                  sourceMeshTransform=source_mesh_matrix.tolist(),
                  sourceMotionBindings=[dict(sourceID=int(i), bone=bones['bones'][int(i)], targetNode=names[bones['bones'][int(i)]]) for i in motion['bone_ids']],
                  sourceAttack=attack_source,
                  origin=dict(anchor='Parent.Nodes.pelvis', axes=['X'], alignedBone='spine_root_joint',
                              offset=[0, 0, 0], direction=['Parent.Nodes.pelvis', 'Parent.Wall.Front'],
                              modelScale=1, verticalAnchor='owner model origin; not animated pelvis height'),
                  visibility=dict(hideStartTick=0, hideEndTick=55, fadeOutTicks=10, fadeInTicks=15,
                                  source='lock_1433 D15_Dog_Hide IntervalStart/IntervalEnd'),
                  adapterBoundaries=[
                      'Original Scale=1 is preserved; no humanoid 0.92 visual scale is copied to this dog.',
                      'Source root horizontal displacement is separated once; authored vertical motion remains in the rig. No guessed floor lift is added.',
                      'Central head/body capsule side=right is an existing wire slot, not a source right-hand assertion.',
                      'Source MagicPower 0.15000000596046448 maps to shadow/1500 bps. Health normalization remains the arena rule profile.',
                      'Impact 200mm over 10 ticks, gravity18 and hit-stop2 reuse the explicit legacy heavy arena response, not original Impulse units.',
                      'Original custom shader/lighting and animated SetSkinColor/morph are not claimed visually equivalent.',
                      'Character digest and final release binding are supplied only by the assembly step.'])
    if settings_recovery is not None:
        record['settingsInputRecovery'] = settings_recovery
    write_private(output / 'd15-hound-candidate-private.json', json.dumps(record, separators=(',', ':'), allow_nan=False).encode())
    write_private(output / 'd15_dog_attack.original-private.bytes', motion_raw)
    print(json.dumps(dict(model=model_file, candidateSHA256=sha((output / 'd15-hound-candidate-private.json').read_bytes()),
                          rawFrames=141, playbackFrames=frames, samples=len(roots), rigNodes=len(rows),
                          boneBindings=len(bound_names), motionTracks=len(columns), capsules=len(edges),
                          activeParts=PARTS, endEventTick=window['endEventTick']), separators=(',', ':')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--motions', type=Path, required=True)
    parser.add_argument('--configs', type=Path, required=True)
    parser.add_argument('--settings', type=Path, required=True)
    parser.add_argument('--settings-format', choices=('historical', 'recovered-d15-v1'), default='historical',
                        help='Select one complete pinned input identity; historical remains the default.')
    parser.add_argument('--output', type=Path, required=True)
    build(parser.parse_args())


if __name__ == '__main__':
    main()
