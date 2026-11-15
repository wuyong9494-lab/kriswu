#!/usr/bin/env python3
"""Build WuYong's D15 actor from exact local source objects and the supplied head.

Source media, decoded configuration, and outputs stay outside the repository.
No network, credentials, gameplay execution, or release activation is used.
The original rig, skin weights, source arrays, and half-frame geometry are
retained; the personal head fit and portable material lighting are explicit
presentation adaptations. Model-only and dog motions are never mapped to people.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import io
import json
import math
import os
from pathlib import Path
import warnings
import wave
import xml.etree.ElementTree as ET
from zipfile import ZipFile
import zlib

import numpy as np

from prepare_fighter_target_motions import ARCHIVE_SHA256
from sun_triad_assets import (C, CI, RIGHT, Writer, accessor_read, capsule_point,
    decode, glb_read, matrix, pose_world, private_output, quaternion, require,
    skin_slots, world_poses)
from sun_triad_materials import material_descriptor
from erlang_source_materials import erlang_material
from erlang_source_profile import (SETTINGS_SHA, REFERENCE_CATALOG_SHA, THROW_ROLES,
    combat_rules, ordinary_throws, source_record, source_window, source_end_event_tick)
from sun_triad_source_bones import capsule_binding, merge_bone_ids, parse_bones_data

ID = 'wuyong_erlang'
RESOURCE = 'WuYong_Erlang_D15'
PROFILE_FILE = 'SF3_Erlang_Profile.json'
HEAD_SHA = '279b7d840bbb99550f82e3c283a5a6e58753e7793be225259621f2dfc2a75cd0'
BODY = '21459e232b8ef3f21ee744adf72717f6.bin'
WEAPON = 'e76bb58980e9e1aa0f9ca0c4b20c0d93.bin'
ACTOR = '00a21255143c2e6368ba9b34e6914d68.bin'
D15 = '2a784bc550bc06541a38a4c1c53b69f3.bin'
AUDIO = '1bc6a2c0e4f0c2f6733e35f02938f8cd.bin'
SPEAR = 'baccadc1bc62c24fcf83246b63fd6c17.bin'
COMMON = 'b9e97e35ddb64ed98261b3baf00829ab.bin'
BLOCK = '31933298c272144ad1b1ddcc1138f4fc.bin'
HIT = '1b0a132a449bc2947a2a326ff30ff33d.bin'
GET_UP = 'f14dba6afd191c841028a9b716c42d78.bin'
MOVE = 'de993aec2876a1160f1a63f0b0a77794.bin'
KICK = 'bb618fd5e61e52d9759e70f2e581b00d.bin'
HOUND = '9893dca6e10355eb9c3c79d1613f08b1.bin'
BODY_MESHES = ('arm__agl_44_m', 'arm__agl_44_m_tie', 'arm__agl_44_m_tie_back',
               'arm__agl_44_m_tie_stripes_down', 'arm__agl_44_m_tie_stripes_up',
               'arm__agl_44_m_tie_tabard')
MODEL_ONLY = {'d15_dog_attack', 'd15_hovering_sword', 'd15_avatara_laser_model',
              'd15_avatara_ult_swords_model'}
SHARED_ABSENT_WEAPON_TRACKS = {
    'l18_player_fly_start': {200,201,202,203,260,261,262,263,264,265,266,267},
    'l18_player_fly_end': {200,201,202,203,260,261,262,263,264,265,266,267},
    **{n:{200,201,202,230,231,232,260,261,262,263,264,265,266,267}
       for n in ('h17_trans_start','h17_trans_loop','h17_trans_end')},
}
CONFIGS = {
    'base': ('ipa-553-bones.textasset.clear-private', '0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455'),
    'fullBody': ('ipa-608-bones.textasset.clear-private', '5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8'),
    'weapon': ('e76bb58980e9e1aa0f9ca0c4b20c0d93_-8622739084404858189_bones.clear-private.xml',
               '3e768ac7e6a76a30d7eb530428ffb56617da5dd921701f7b284b65231c69fe9c'),
}
ROLE_INPUTS = {
    'idle': ('spear_stance_idle', SPEAR), 'enter': ('spear_stance_birth', SPEAR),
    'walkForward': ('staff_step_forward', SPEAR), 'walkBackward': ('staff_step_back', SPEAR),
    'guard': ('b_polearm_mid_block', BLOCK), 'crouch': ('m_low_stance_idle', COMMON),
    'jump': ('m_agl_jump_up', MOVE), 'hit': ('h_chest_short_fast', HIT),
    'knockdown': ('h_hit_head_fall', HIT), 'getUp': ('m_agl_stand_up_back_forward', GET_UP),
    'victory': ('spear_win', SPEAR), 'weapon1': ('imperial_spear_slash_1', SPEAR),
    'weapon2': ('imperial_spear_slash_2', SPEAR), 'heavy': ('imperial_spear_heavy_slash', SPEAR),
    'weaponForward': ('imperial_spear_super_1_slash_1', SPEAR), 'weaponUp': ('imperial_spear_upper_slash', SPEAR),
    'weaponDown': ('imperial_spear_low_slash', SPEAR), 'weaponBack': ('imperial_spear_spinning_slash', SPEAR),
    'weaponForward2': ('imperial_spear_super_1_slash_2', SPEAR),
    'weaponForward3': ('imperial_spear_super_1_slash_3', SPEAR),
    'imperialHeavyActive': ('imperial_spear_heavy_slash_active', SPEAR),
    'imperialHeavyPassive': ('imperial_spear_heavy_slash_passive', SPEAR),
    'kick': ('k_agl_kick_1', KICK), 'kickForward': ('k_agl_front_kick', KICK),
    'kickUp': ('k_agl_upper_kick', KICK), 'kickDown': ('k_agl_low_1', KICK),
    'kickBack': ('k_agl_spinning_kick', KICK), 'kickJump': ('k_agl_jump_up', KICK),
    'kickJumpForward': ('k_agl_jump_front_up', KICK),
    'erlangAxe': ('d15_avatara_axe_slash', D15), 'erlangEye': ('d15_avatara_laser', D15),
    'erlangEarthshaker': ('d15_avatara_spear_earthshake', D15), 'erlangStep': ('d15_avatara_stomp', D15),
    'erlangMeditationStart': ('d15_meditation_start', D15), 'erlangMeditationLoop': ('d15_meditation_loop', D15),
    'erlangMeditationEnd': ('d15_meditation_end', D15), 'erlangAvatarStance': ('d15_stance', D15),
    'erlangAvatarBirth': ('d15_stance_birth', D15), 'erlangAvatarIdle': ('d15_stance_idle', D15),
    'erlangTransform': ('d15_transform_4lvl', D15), 'erlangTransformMirror': ('d15_transform_4lvl_mirror', D15),
    'erlangJudgment': ('d15_transform_ult', D15),
    'erlangHound': ('d13_helmet_ability', HOUND),
    'erlangTransform2Start': ('l18_player_fly_start', HOUND),
    'erlangTransform2End': ('l18_player_fly_end', HOUND),
    'erlangHypnosisIn': ('h17_trans_start', HOUND),
    'erlangHypnosisLoop': ('h17_trans_loop', HOUND),
    'erlangHypnosisOut': ('h17_trans_end', HOUND),
    'erlangTransformOut': ('staff_idle', SPEAR),
}
COMBO_LINKS = [
    dict(from_='imperial_spear_slash_1', to='imperial_spear_slash_2', sourceFrame=35),
    dict(from_='imperial_spear_super_1_slash_1', to='imperial_spear_super_1_slash_2', sourceFrame=15),
    dict(from_='imperial_spear_super_1_slash_2', to='imperial_spear_super_1_slash_3', sourceFrame=37),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as f:
        f.write(raw)


def record(path):
    raw = path.read_bytes()
    return dict(file=path.name, bytes=len(raw), sha256=sha(raw))


def checked(path, expected, maximum=32_000_000):
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum,
            'Input must be a bounded regular file: ' + path.name)
    raw = path.read_bytes()
    require(sha(raw) == expected, 'Pinned input differs: ' + path.name)
    return raw


def local_source(args):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use the reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    archive = ZipFile(io.BytesIO(checked(args.source_archive, ARCHIVE_SHA256, 256 * 1024 * 1024)))
    rows = [json.loads(x) for x in archive.read('research/android_bundle_catalog.jsonl').splitlines()]
    require(len(rows) == 2205 and len({x['file'] for x in rows}) == 2205, 'Catalog identity differs')
    bundles = {x['file']: x for x in rows}
    motions = json.loads(archive.read('research/motion_catalog.json'))['motions']
    cache = {}

    def load(name):
        if name not in cache:
            path = args.source_bundles / name
            raw = path.read_bytes() if path.exists() else archive.read('bundles/' + name)
            pin = bundles[name]
            require(len(raw) == pin['bytes'] and sha(raw) == pin['sha256'], 'Source bundle differs: ' + name)
            cache[name] = UnityPy.load(raw)
        return cache[name]
    return bundles, motions, load


def source_actor_rows(environment):
    matches = [(p, o) for p, o in environment.container.items() if p.endswith('/skeleton.prefab')]
    require(len(matches) == 1, 'Source actor prefab is missing or ambiguous')
    game = matches[0][1].read()
    transforms = [c.component.read() for c in game.m_Component if c.component.type.name == 'Transform']
    require(len(transforms) == 1, 'Actor Transform differs')
    rows = []
    walk_transform(transforms[0], None, rows)
    require(len(rows) == 64 and len({r['name'] for r in rows}) == 64, 'Expected original 64-node actor')
    return rows


def walk_transform(t, parent, rows):
    name = t.m_GameObject.read().m_Name
    rows.append(dict(name=name, parent=parent,
        translation=[t.m_LocalPosition.x, t.m_LocalPosition.y, t.m_LocalPosition.z],
        rotation=[t.m_LocalRotation.x, t.m_LocalRotation.y, t.m_LocalRotation.z, t.m_LocalRotation.w],
        scale=[t.m_LocalScale.x, t.m_LocalScale.y, t.m_LocalScale.z]))
    for child in t.m_Children:
        walk_transform(child.read(), name, rows)


def weapon_rows(environment, base):
    rows, receipts = [], []
    for path, pointer in sorted(environment.container.items()):
        if '/m/prefabs/' not in path:
            continue
        game = pointer.read()
        transforms, data = [], []
        for c in game.m_Component:
            ref = c.component
            if ref.type.name == 'Transform':
                transforms.append(ref.read())
            elif ref.type.name == 'MonoBehaviour':
                value = ref.read_typetree()
                if '_parentName' in value:
                    data.append(value)
        require(len(transforms) == len(data) == 1 and data[0]['_additionalPart'] == 1,
                'Original weapon attachment contract differs')
        parent = data[0]['_parentName']
        require(parent in {'weapon_l', 'weapon_r'}, 'Spear attachment parent differs')
        start = len(rows)
        walk_transform(transforms[0], parent, rows)
        receipts.append(dict(sourcePrefab=path, parent=parent, root=rows[start]['name'], nodes=len(rows)-start))
    require(len(receipts) == 2 and len({r['name'] for r in base+rows}) == len(base)+len(rows),
            'Original spear hierarchy differs')
    return rows, receipts


def copy_head(writer, head_path, names, worlds):
    """Bind supplied portrait geometry rigidly to the real original head bone.

    Its origin is fitted to the source head bind point; its +Z front is rotated
    into the source actor's -Z front. Placement is an explicit adaptation, not
    recovered source skinning or a claim that the supplied mesh has a neck.
    Its local vertex/UV/index arrays and encoded images remain unchanged.
    """
    checked(head_path, HEAD_SHA, 8_000_000)
    old, binary = glb_read(head_path)
    require(len(old['nodes']) == len(old['meshes']) == 1 and not old.get('skins')
            and not old.get('animations') and set(old['nodes'][0]) == {'mesh', 'name'},
            'Expected the supplied unrigged portrait, never the two-bone test rig')
    material_offset = len(writer.g['materials'])
    image_offset, texture_offset, sampler_offset = len(writer.g['images']), len(writer.g['textures']), len(writer.g['samplers'])
    for item in old.get('samplers', []):
        writer.g['samplers'].append(copy.deepcopy(item))
    for image in old.get('images', []):
        require('uri' not in image, 'Portrait image must be embedded')
        view = old['bufferViews'][image['bufferView']]
        raw = binary[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']]
        writer.g['images'].append(dict(image, bufferView=writer.block(raw)))
    for item in old.get('textures', []):
        value = dict(item, source=item['source']+image_offset)
        if 'sampler' in value:
            value['sampler'] += sampler_offset
        writer.g['textures'].append(value)
    for material in old['materials']:
        value = copy.deepcopy(material)
        def remap(obj):
            if isinstance(obj, dict):
                for key, item in obj.items():
                    if key.endswith('Texture') and isinstance(item, dict) and 'index' in item:
                        item['index'] += texture_offset
                    else:
                        remap(item)
            elif isinstance(obj, list):
                for item in obj:
                    remap(item)
        remap(value)
        writer.g['materials'].append(value)
    primitives = []
    for original in old['meshes'][0]['primitives']:
        p = copy.deepcopy(original)
        for name, index in original['attributes'].items():
            info = old['accessors'][index]
            p['attributes'][name] = writer.acc(accessor_read(old, binary, index), info['type'], info['componentType'])
        p['indices'] = writer.acc(accessor_read(old, binary, original['indices']), 'SCALAR', old['accessors'][original['indices']]['componentType'])
        p['material'] += material_offset
        primitives.append(p)
    mesh_index = len(writer.g['meshes'])
    writer.g['meshes'].append(dict(name='WuYong_Personal_Head', primitives=primitives))
    # Preserve original unskinned portrait arrays; a single real bone parent
    # supplies rigid head motion. This is not the diagnostic BodyReference rig.
    placement = np.eye(4)
    placement[:3, :3] = np.diag([-1., 1., -1.])
    placement[:3, 3] = worlds[names['head']][:3, 3]
    local = np.linalg.inv(worlds[names['head']]) @ placement
    index = len(writer.g['nodes'])
    writer.g['nodes'].append(dict(name='WuYong_Personal_Head', mesh=mesh_index,
        translation=local[:3, 3].tolist(), rotation=quaternion(local[:3, :3]).tolist(), scale=[1, 1, 1]))
    writer.g['nodes'][names['head']].setdefault('children', []).append(index)
    return dict(sourceFile=head_path.name, sourceSHA256=HEAD_SHA, sourceRigUsed=False,
                vertexUVIndexArraysPreserved=True, encodedImagesPreserved=True,
                binding='rigid child of original head', placementWorldMatrix=placement.tolist())


def build_geometry(args, bundles, load, configs):
    from UnityPy.helpers.MeshHelper import MeshHandler
    base = source_actor_rows(load(ACTOR))
    extra, attachment = weapon_rows(load(WEAPON), base)
    rows = base + extra
    names = {r['name']: i for i, r in enumerate(rows)}
    paths, hashes = {}, {}
    for row in rows:
        path = row['name'] if row['parent'] in (None, 'skeleton') else paths[row['parent']] + '/' + row['name']
        paths[row['name']] = path
        key = zlib.crc32(path.encode())
        require(key not in hashes, 'Original bone-path CRC collision')
        hashes[key] = names[row['name']]
    selected = []
    renderers = {}
    for bundle in (BODY, WEAPON):
        for obj in load(bundle).objects:
            if obj.type.name == 'Mesh':
                mesh = obj.read()
                if mesh.m_Name in BODY_MESHES or mesh.m_Name == 'wpn__agl_spear_01_01__l':
                    selected.append(mesh)
            elif obj.type.name == 'SkinnedMeshRenderer':
                renderer = obj.read()
                renderers[renderer.m_GameObject.read().m_Name] = renderer
    selected.sort(key=lambda m: (list(BODY_MESHES)+['wpn__agl_spear_01_01__l']).index(m.m_Name))
    require(len(selected) == 7 and len({m.m_Name for m in selected}) == 7, 'Exact six male armor parts and primary left spear required')
    world_bind, mesh_data, mapping = {}, {}, []
    disagreement = 0.
    for mesh in selected:
        h = MeshHandler(mesh); h.process()
        weights, ids = np.asarray(h.m_BoneWeights, float), np.asarray(h.m_BoneIndices, int)
        require(len(mesh.m_BindPose) == len(mesh.m_BoneNameHashes), 'Skin bind/hash count differs')
        require(all(key in hashes for key in mesh.m_BoneNameHashes), 'Unmatched original skin path hash')
        remap = np.array([hashes[key] for key in mesh.m_BoneNameHashes])
        used = set(ids[weights > 1e-7].tolist())
        for j, (key, bind) in enumerate(zip(mesh.m_BoneNameHashes, mesh.m_BindPose)):
            if j not in used:
                continue
            i = hashes[key]
            raw = np.array([[getattr(bind, f'e{y}{x}') for x in range(4)] for y in range(4)])
            world = np.linalg.inv(C @ raw @ CI)
            if i in world_bind:
                disagreement = max(disagreement, float(np.max(abs(world-world_bind[i]))))
            else:
                world_bind[i] = world
        mesh_data[mesh.m_Name] = (h, weights, remap[ids])
        mapping.append(dict(mesh=mesh.m_Name, matchedPaths=[paths[rows[hashes[key]]['name']] for key in mesh.m_BoneNameHashes]))
    require(disagreement < .001, 'Original shared bind matrices disagree')
    writer = Writer(); writer.g['asset']['generator'] = 'Verified original D15 actor and supplied WuYong portrait'
    worlds = {}
    for i, row in enumerate(rows):
        parent = names.get(row['parent'])
        p = worlds[parent] if parent is not None else np.eye(4)
        source = C @ matrix(row['translation'], row['rotation'], row['scale']) @ CI
        world = world_bind.get(i, p @ source)
        local = np.linalg.inv(p) @ world
        scale = np.linalg.norm(local[:3, :3], axis=0)
        node = dict(name=row['name'], translation=local[:3, 3].tolist(),
                    rotation=quaternion(local[:3, :3]/scale).tolist(), scale=scale.tolist())
        children = [j for j, value in enumerate(rows) if value['parent'] == row['name']]
        if children:
            node['children'] = children
        writer.g['nodes'].append(node); worlds[i] = world
    writer.g['skins'].append(dict(name='Original D15 equipment skin', joints=list(range(len(rows))),
        skeleton=names['skeleton'], inverseBindMatrices=writer.acc([np.linalg.inv(worlds[i]).T.reshape(16) for i in range(len(rows))], 'MAT4')))
    mesh_nodes, material_cache = [], {}
    counts = dict(sourceVertices=0, sourceTriangles=0)
    for mesh in selected:
        h, weights, joints = mesh_data[mesh.m_Name]
        positions = np.asarray(h.m_Vertices, float)[:, :3] * [.01, .01, -.01]
        normals = np.asarray(h.m_Normals, float)[:, :3] * [1, 1, -1]
        uv = np.asarray(h.m_UV0, float)[:, :2]; uv[:, 1] = 1-uv[:, 1]
        joints, weights = skin_slots(joints, weights)
        attributes = dict(POSITION=writer.acc(positions, 'VEC3'), NORMAL=writer.acc(normals, 'VEC3'),
            TEXCOORD_0=writer.acc(uv, 'VEC2'), JOINTS_0=writer.acc(joints, 'VEC4', 5123), WEIGHTS_0=writer.acc(weights, 'VEC4'))
        renderer = renderers[mesh.m_Name]; primitives = []
        for j, triangles in enumerate(h.get_triangles()):
            indices = np.asarray(triangles, np.uint32).reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
            if not len(indices):
                continue
            material = erlang_material(writer, renderer.m_Materials[min(j, len(renderer.m_Materials)-1)].read(), material_cache)
            primitives.append(dict(attributes=attributes, indices=writer.acc(indices, 'SCALAR', 5125), material=material))
            counts['sourceTriangles'] += len(indices)//3
        mesh_index = len(writer.g['meshes'])
        writer.g['meshes'].append(dict(name=mesh.m_Name, primitives=primitives))
        mesh_nodes.append(len(writer.g['nodes']))
        writer.g['nodes'].append(dict(name=mesh.m_Name, mesh=mesh_index, skin=0))
        counts['sourceVertices'] += len(positions)
    head = copy_head(writer, args.head, names, worlds)
    outer = len(writer.g['nodes'])
    writer.g['nodes'].append(dict(name='SF3_Actor_Meters', children=[0]+mesh_nodes,
        scale=[.92]*3, rotation=[0, -float(np.sqrt(.5)), 0, float(np.sqrt(.5))]))
    writer.g['scenes'][0]['nodes'] = [outer]
    bone_ids = {key: value for key, value in merge_bone_ids(*configs.values()).items() if value in names}
    bindings = [dict(name=row['name'], parent=row['parent'], path=paths[row['name']], targetNode=names[row['name']],
                sourceID=next((key for key, value in bone_ids.items() if value == row['name']), None)) for row in rows]
    return writer, names, bone_ids, dict(originalBoneBindings=bindings, sourceSkinHashMappings=mapping,
        sourceAttachments=attachment, personalPortrait=head, maximumSharedBindMatrixDifference=disagreement,
        counts=counts, originalActorNodeCount=64, originalAttachmentNodeCount=len(extra))


def motion_rows(motions, roles=None):
    chosen = []
    for name, bundle in dict.fromkeys((roles or ROLE_INPUTS).values()):
        rows = [r for r in motions if r['name'] == name and r['bundle'] == bundle]
        require(len(rows) == 1 and name not in MODEL_ONLY, 'Missing or ambiguous exact actor motion: ' + name)
        chosen.append(rows[0])
    return chosen


def append_motion(writer, names, bone_ids, configs, info, raw, configuration=None,
                  mirror_rules=None, export_name=None):
    require(len(raw) == info['bytes'] and sha(raw) == info['sha256'], 'Original motion identity differs')
    arrays = decode(raw); motion = arrays[0]; frames = motion['frame_count']
    require(len(arrays) == 2 and frames == info['frames'] and frames >= 2,
            'Source motion dimensions differ')
    absent = set(map(int,motion['bone_ids']))-set(bone_ids)
    require(absent == SHARED_ABSENT_WEAPON_TRACKS.get(info['name'], set()),
            'Unbound original actor motion track')
    require(set(configs['base']['bones']) <= set(map(int,motion['bone_ids'])),
            'Shared source projection must retain every original body track')
    require(info['name'] not in MODEL_ONLY, 'Model-only or dog motion cannot enter the actor')
    first, last, stride = (0, frames-1, 2) if configuration is None else source_window(configuration['configuration'], frames)
    source_frames = frames
    motion = dict(motion, positions=motion['positions'][first:last+1], rotations=motion['rotations'][first:last+1])
    frames = last-first+1
    source_window_frames=frames
    static_hold=frames==1
    if static_hold:
        require(configuration['configuration']['Animation']=='D15_Avatara_Transform_Out'
                and first==last==0 and configuration['configuration']['SelfEndFrame']==0,
                'Only the exact source Transform_Out may use the source static pose')
    columns = {bone_ids[int(key)]: j for j, key in enumerate(motion['bone_ids']) if int(key) in bone_ids}
    g = writer.g; rest_world, rest, parents = world_poses(g['nodes'])
    basis = RIGHT[:3, :3] @ rest_world[parents[names['pelvis']]][:3, :3]
    if mirror_rules is not None:
        from source_body_mirroring import sample_source_motion, mirror_source_samples
        require(stride == 2 and configuration['configuration']['Mirrored'] == -1,
                'Only the reviewed source toggle-mirror motion is supported')
        source_p,source_q=sample_source_motion(arrays[0],first,last)
        p,q=mirror_source_samples(source_p,source_q,columns,g['nodes'],names,mirror_rules)
        motion=dict(motion,positions=p,rotations=q)
    export_frames = 2*frames-1 if mirror_rules is not None else frames
    export_rate = 60 if mirror_rules is not None else 30
    name = export_name or info['name']
    animation = dict(name=name, samplers=[], channels=[], extras=dict(sourceSHA256=info['sha256'],
        sourceFrames=source_frames, sourceFirstIndex=first, sourceLastIndex=last,
        sourceFrameStride=stride, sourceFPS=None, exportFramesPerSecond=export_rate, simulationHz=60,
        sourceArraysRetained=True, targetAbsentSourceWeaponTrackIDs=sorted(absent),
        sourceWindowFrames=source_window_frames,sourceStaticPose=static_hold,
        sourceMirrorApplied=mirror_rules is not None,
        horizontalPelvisSeparatedIntoRootTrack=True))
    times = writer.acc(np.arange(export_frames)/export_rate, 'SCALAR')
    positions, rotations = {}, {}
    for bone, column in columns.items():
        p = motion['positions'][:, column].astype(float) * [.01, .01, -.01]
        if bone == 'pelvis':
            p[:, [0, 2]] = 0
        q = motion['rotations'][:, column].astype(float) * [-1, -1, 1, 1]
        q /= np.linalg.norm(q, axis=1)[:, None]
        for i in range(1, len(q)):
            if q[i-1] @ q[i] < 0:
                q[i] *= -1
        positions[bone], rotations[bone] = p.astype(np.float32).astype(float), q.astype(np.float32).astype(float)
        for kind, values, width in [('translation', p, 'VEC3'), ('rotation', q, 'VEC4')]:
            sampler = len(animation['samplers'])
            animation['samplers'].append(dict(input=times, output=writer.acc(values, width), interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=sampler, target=dict(node=names[bone], path=kind)))
    g['animations'].append(animation)
    raw_roots = motion['positions'][:, columns['pelvis']].astype(float) * [.01, .01, -.01]
    root_delta = (raw_roots-raw_roots[0]) @ basis.T
    attacks = configs['weapon']['capsules']
    hurts = configs['fullBody']['capsules']
    require({c['id'] for c in attacks} == {'Spear_Attacking_Edge_l','Spear_Attacking_Edge_r'}
            and len(hurts) == 15, 'Original source capsule inventory differs')
    primary = next(c for c in attacks if c['id'] == 'Spear_Attacking_Edge_l')
    masses = configs['base'].get('masses', {})
    weighted = [(names[name], weight) for name, weight in masses.items() if weight > 0]
    weighted.sort()
    require(len(weighted) == 58 and abs(sum(w for _,w in weighted)-67.2) < 1e-8,
            'Exact original actor mass table required')
    markers = []
    for side in ('l', 'r'):
        foot, toe = names['foot_'+side], names['toe_'+side]
        a, b = rest_world[foot][:3, 3], rest_world[toe][:3, 3]
        for x in (min(a[0], b[0])-.055, max(a[0], b[0])+.055):
            for z in (min(a[2], b[2])-.055, max(a[2], b[2])+.055):
                markers.append((foot, np.linalg.inv(rest_world[foot]) @ [x, -.02, z, 1]))
    tracks = {key: [] for key in ('root', 'handL', 'handR', 'footL', 'footR', 'toeL', 'toeR', 'pelvis', 'head', 'weaponBaseL', 'weaponTipL', 'weaponBaseR', 'weaponTipR')}
    tracks.update(samplesPerSourceFrame=2, groundLift=[], centerOfMass=[])
    edges = [dict(**capsule_binding(c, 'attack'), base=[], tip=[]) for c in attacks]
    hurt_shapes = [dict(**capsule_binding(c, 'hurt'), base=[], tip=[]) for c in hurts]
    for sample in range(2*frames-1):
        if mirror_rules is not None:
            a=b=sample;fraction=0
        else:
            a = sample//2; b = min(frames-1, a+1); fraction = (sample%2)/2
        local = [value.copy() for value in rest]
        for bone in columns:
            p = positions[bone][a]*(1-fraction)+positions[bone][b]*fraction
            q = rotations[bone][a]*(1-fraction)+rotations[bone][b]*fraction
            local[names[bone]] = matrix(p, q, g['nodes'][names[bone]].get('scale', [1, 1, 1]))
        world = pose_world(local, parents)
        tracks['root'].append(root_delta[a]*(1-fraction)+root_delta[b]*fraction)
        for label, bone in [('handL', 'hand_l'), ('handR', 'hand_r'), ('footL', 'foot_l'), ('footR', 'foot_r'), ('toeL', 'toe_l'), ('toeR', 'toe_r'), ('pelvis', 'pelvis'), ('head', 'head')]:
            tracks[label].append((RIGHT @ world[names[bone]][:, 3])[:3])
        for side, suffix in [('l','L'),('r','R')]:
            capsule = next(c for c in attacks if c['id'] == 'Spear_Attacking_Edge_'+side)
            for end, label in [('base', 'weaponBase'+suffix), ('tip', 'weaponTip'+suffix)]:
                tracks[label].append(capsule_point(capsule[end], world, names))
        accumulator, total = np.zeros(3, dtype=np.float32), np.float32(0)
        for node, weight in weighted:
            weight = np.float32(weight)
            point = np.asarray((RIGHT @ world[node][:, 3])[:3], dtype=np.float32)
            accumulator = np.asarray(accumulator + point*weight, dtype=np.float32)
            total = np.float32(total+weight)
        tracks['centerOfMass'].append(accumulator/total)
        for capsule, destination in zip(attacks+hurts, edges+hurt_shapes):
            for end in ('base', 'tip'):
                destination[end].append(capsule_point(capsule[end], world, names))
        low = min((world[foot] @ marker)[1] for foot, marker in markers)
        tracks['groundLift'].append(float(max(0., -.035-low)))
    tracks = {key: np.round(value, 7).tolist() if isinstance(value, list) else value for key, value in tracks.items()}
    for capsule in edges+hurt_shapes:
        for end in ('base', 'tip'):
            capsule[end] = np.round(capsule[end], 7).tolist()
    tracks.update(collisionEdges=edges, hurtCapsules=hurt_shapes)
    require(len(tracks['root']) == 2*frames-1 and max(tracks['groundLift']) <= 2,
            'Source pose exceeds the runtime geometry bound')
    return dict(name=name, frames=frames, sourceUncroppedFrames=source_frames,
        sourceFirstIndex=first, sourceLastIndex=last, playbackTicks=(frames-1)*stride,
        sourceWindowFrames=source_window_frames,sourceStaticPose=static_hold,
        sourceEndEventTick=None if configuration is None else source_end_event_tick(configuration['configuration'], source_frames),
        targetAbsentSourceWeaponTrackIDs=sorted(absent),
        sourceMirrorApplied=mirror_rules is not None,
        sourceConfiguration=configuration, sha256=info['sha256'], bundle=info['bundle'],
        sourcePathID=str(info['path_id']), sourceBytesBase64=base64.b64encode(raw).decode(),
        sourceArrayCount=2, sourceBoneIDs=[int(key) for key in motion['bone_ids']], tracks=tracks)


def build(args):
    require(not args.output.exists(), 'Refuse to overwrite an existing candidate')
    output = private_output(args.output)
    bundles, motions, load = local_source(args)
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    reference_document = json.loads(checked(args.reference_catalog, REFERENCE_CATALOG_SHA, 40_000_000))
    reference = next(p for p in reference_document['profiles'] if p['id'] == 'sun_triad')
    roles = dict(ROLE_INPUTS)
    for role in THROW_ROLES:
        clip = next(c for c in reference['clips'] if c['name'] == reference['roles'][role])
        rows = [r for r in motions if r['name'] == clip['name'] and r['sha256'] == clip['sha256']]
        require(len(rows) == 1, 'Verified paired motion is unavailable')
        roles[role] = (clip['name'], rows[0]['bundle'])
    configs = {}
    for kind, (name, pin) in CONFIGS.items():
        folder = args.source_configs if kind == 'weapon' else args.shared_bones
        configs[kind] = parse_bones_data(checked(folder/name, pin, 1_000_000))
        if kind == 'base':
            root = ET.fromstring(checked(folder/name, pin, 1_000_000))
            configs[kind]['masses'] = {b.get('Name'):float(b.get('Mass','0')) for b in root.findall('./Bones/Bone')}
    writer, names, bone_ids, audit = build_geometry(args, bundles, load, configs)
    clips = []
    for info in motion_rows(motions, roles):
        matches = [o for o in load(info['bundle']).objects if o.path_id == info['path_id']]
        require(len(matches) == 1 and matches[0].type.name == 'TextAsset', 'Original motion object is missing')
        source = matches[0].read().m_Script
        raw = source.encode('utf8', 'surrogateescape') if isinstance(source, str) else bytes(source)
        is_throw = info['name'] in {roles[r][0] for r in THROW_ROLES}
        configuration = None if is_throw else source_record(settings, info['name'])
        clips.append(append_motion(writer, names, bone_ids, configs, info, raw, configuration))
        print('CLIP', info['name'], info['frames'], flush=True)
    writer.g['extras'] = dict(id=ID, bodyID='arm__agl_44', weaponID='wpn__agl_spear_01_01',
        sourceSkinPreserved=True, sourceActorNodeCount=64, sourceBodyBundle=BODY,
        sourceWeaponBundle=WEAPON, personalPortraitSHA256=HEAD_SHA,
        horizontalPelvisZeroed=True, exportFramesPerSecond=30,
        sourceGameTimingFromConfiguration=True, customShaderParity=False)
    model = output/(RESOURCE+'.glb')
    result = writer.save(model); model.chmod(0o600)
    profile = dict(id=ID, hero=ID, faction='Dynasty', resourceName=RESOURCE, **result,
        bodyID='arm__agl_44', weaponID='wpn__agl_spear_01_01', activeWeaponSides=['left','right'],
        roles={key: value[0] for key, value in roles.items()}, clips=clips,
        comboLinks=[{'from':c['from_'],'to':c['to'],'sourceFrame':c['sourceFrame']} for c in COMBO_LINKS],
        sourceSkinNodeCount=len(audit['originalBoneBindings']),
        sourceBoneBindings=audit['originalBoneBindings'],
        weaponLandmarks={'left': dict(sourceCapsule='Spear_Attacking_Edge_l',
            **{key: next(c for c in configs['weapon']['capsules'] if c['id']=='Spear_Attacking_Edge_l')[key] for key in ('base','tip')})})
    profile['combatRules'], attacks = combat_rules(profile, settings)
    profile['ordinaryThrows'] = ordinary_throws(profile, reference)
    if args.erlang_rules:
        rules = json.loads(args.erlang_rules.read_text())
        require(rules.get('sourceVersion') == '1.46.0.16.16733-prod', 'D15 runtime source version differs')
        profile['erlangRules'] = rules
    write_new(output/PROFILE_FILE, encoded(profile))
    audit.update(id=ID, character=record(model), profile=record(output/PROFILE_FILE),
        sourceBundles=[{key: bundles[name][key] for key in ('file','bytes','sha256')} for name in sorted({BODY,WEAPON,ACTOR}|{r['bundle'] for r in motion_rows(motions, roles)})],
        sourceSettingsSHA256=SETTINGS_SHA, sourceThrowReferenceSHA256=REFERENCE_CATALOG_SHA,
        originalPhysicalAttackBindings=attacks,
        sourceBoneConfigs={key:dict(file=value[0],sha256=value[1]) for key,value in CONFIGS.items()},
        clips=[{key:c[key] for key in ('name','frames','sha256','bundle','sourcePathID')} for c in clips],
        modelOnlyMotions=[{key:r[key] for key in ('name','frames','sha256','bundle','path_id')} for r in motions if r['bundle']==D15 and r['name'] in MODEL_ONLY],
        materials=[material_descriptor(m, writer.g) for m in writer.g['materials']],
        caveats=['Personal portrait placement is a new explicit fit; it is not the missing dot full-body GLB.',
                 'Portable material lighting is not original shader parity.',
                 'Both source spear capsule sides are available; only the primary unmirrored spear mesh is displayed.',
                 'Imperial heavy PostHit paired response requires separate runtime binding; it is not an ordinary combo.',
                 'D15 gameplay and audio are separately source-bound; this builder alone does not establish native gameplay acceptance.'])
    write_new(output/(RESOURCE+'_provenance-private.json'), encoded(audit))
    return dict(id=ID, character=record(model), profile=record(output/PROFILE_FILE), clips=len(clips),
                sourceHumanD15Clips=sum(c['bundle']==D15 for c in clips), sourceModelOnlyMotions=len(audit['modelOnlyMotions']),
                nodes=len(writer.g['nodes']), meshes=len(writer.g['meshes']))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source-archive','source-bundles','source-configs','shared-bones','head','settings','reference-catalog','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--erlang-rules', type=Path)
    print(json.dumps(build(parser.parse_args())))


if __name__ == '__main__':
    main()
