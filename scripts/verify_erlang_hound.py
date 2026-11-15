#!/usr/bin/env python3
"""Read back the actual hound GLB and check it against original input objects."""
from __future__ import annotations
import argparse
import json
import warnings
from pathlib import Path
import numpy as np
from prepare_erlang_hound import (MODEL_BUNDLE, MODEL_SHA, MODEL, MOTION_SHA, BONES_SHA,
    BONES_NAME, PARTS, C, CI, RIGHT, checked, decode, require, sha)
from sun_triad_assets import glb_read, accessor_read, matrix, pose_world, world_poses
from sun_triad_source_bones import parse_bones_data


def verify(candidate, models, configs):
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    record = json.loads(candidate.read_bytes())
    model_path = candidate.parent / record['modelFile']['name']
    raw = checked(model_path, record['modelFile']['sha256'], 8_000_000)
    require(len(raw) == record['modelFile']['bytes'], 'Derived GLB byte count differs')
    g, binary = glb_read(model_path)
    names = {node['name']: i for i, node in enumerate(g['nodes'])}
    require(len(names) == len(g['nodes']) == 54 and 'pelvis' not in names,
            'Dog rig contains an invented human root or duplicate node')
    require(len(g['skins']) == len(g['meshes']) == len(g['animations']) == 1, 'Wrong dog asset count')
    bones = parse_bones_data(checked(configs / BONES_NAME, BONES_SHA, 10_000))
    source_raw = checked(candidate.parent / 'd15_dog_attack.original-private.bytes', MOTION_SHA, 150_000)
    arrays = decode(source_raw)
    source = arrays[0]
    require(len(arrays) == 2 and source['frame_count'] == 141 and len(source['bone_ids']) == 41,
            'Wrong original dog motion')
    animation = g['animations'][0]
    require(animation['name'] == 'd15_dog_attack' and len(animation['channels']) == 82,
            'Dog animation was lost or converted to human clips')
    columns = {bones['bones'][int(i)]: c for c, i in enumerate(source['bone_ids'])}
    channels = {}
    maximum_channel_error = 0.
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        times = accessor_read(g, binary, sampler['input'])
        require(np.array_equal(times, (np.arange(60) / 30).astype(np.float32)), 'Cropped frame clock differs')
        node, path = channel['target']['node'], channel['target']['path']
        name = g['nodes'][node]['name']
        require(name in columns and path in ('translation', 'rotation'), 'Unexpected source motion binding')
        actual = accessor_read(g, binary, sampler['output']).astype(float)
        expected = source['positions' if path == 'translation' else 'rotations'][:60, columns[name]].astype(float)
        if path == 'translation':
            expected *= [.01, .01, -.01]
            if name == 'spine_root_joint': expected[:, [0, 2]] = 0
        else:
            expected *= [-1, -1, 1, 1]
            expected /= np.linalg.norm(expected, axis=1)[:, None]
            for i in range(1, 60):
                if expected[i - 1] @ expected[i] < 0: expected[i] *= -1
        error = float(np.max(abs(actual - expected)))
        maximum_channel_error = max(maximum_channel_error, error)
        require(np.array_equal(actual, expected.astype(np.float32).astype(float)), 'Derived pose differs from original array')
        require((node, path) not in channels, 'Duplicate source channel')
        channels[node, path] = actual
    require({g['nodes'][node]['name'] for node, _ in channels} == set(columns), 'A source motion bone is missing')

    # Original mesh skin and exported inverse binds must agree in the same
    # centimeter/reflection conversion, independently of the exported receipt.
    env = UnityPy.load(checked(models / MODEL_BUNDLE, MODEL_SHA, 300_000))
    renderers = [o.read() for o in env.objects if o.type.name == 'SkinnedMeshRenderer']
    require(len(renderers) == 1, 'Ambiguous original renderer')
    renderer = renderers[0]
    mesh = renderer.m_Mesh.read()
    components = renderer.m_GameObject.read().m_Component
    binding = [c.component.deref().read_typetree() for c in components if c.component.deref().type.name == 'MonoBehaviour'][0]
    transform = [c.component.read() for c in components if c.component.deref().type.name == 'Transform'][0]
    mesh_transform = matrix([transform.m_LocalPosition.x, transform.m_LocalPosition.y, transform.m_LocalPosition.z],
                            [transform.m_LocalRotation.x, transform.m_LocalRotation.y, transform.m_LocalRotation.z, transform.m_LocalRotation.w],
                            [transform.m_LocalScale.x, transform.m_LocalScale.y, transform.m_LocalScale.z])
    mesh_space = C @ mesh_transform @ CI
    exported_bind = accessor_read(g, binary, g['skins'][0]['inverseBindMatrices'])
    maximum_bind_error = 0.
    for index, name in enumerate(binding['_bindBonesName']):
        native = mesh.m_BindPose[index]
        original = np.array([[getattr(native, f'e{y}{x}') for x in range(4)] for y in range(4)])
        expected = C @ original @ CI @ np.linalg.inv(mesh_space)
        actual = exported_bind[names[name]].reshape(4, 4).T
        error = float(np.max(abs(expected - actual)))
        maximum_bind_error = max(maximum_bind_error, error)
        require(error < 0.000001, 'Original dog inverse bind changed')
    handler = MeshHandler(mesh); handler.process()
    primitive = g['meshes'][0]['primitives'][0]
    original_vertices = np.asarray(handler.m_Vertices)[:, :3] * [.01, .01, -.01]
    expected_vertices = (np.c_[original_vertices, np.ones(len(original_vertices))] @ mesh_space.T)[:, :3]
    require(np.array_equal(accessor_read(g, binary, primitive['attributes']['POSITION']), expected_vertices.astype(np.float32)),
            'Original dog mesh vertices changed')

    _, rest, parents = world_poses(g['nodes'])
    track = record['track']
    require(track['frames'] == 60 and track['sourceEndEventTick'] == 110 and len(track['root']) == 119,
            'Physical model lifetime differs from configured animation')
    require(track['attackParts'] == {'primary': PARTS}, 'Attack part selection changed')
    edges = {e['id']: e for e in track['collisionEdges']}
    require(len(edges) == 6 and not track['hurtCapsules'], 'Invented or missing dog capsules')
    raw_root = source['positions'][:60, columns['spine_root_joint']].astype(float) * [.01, .01, -.01]
    root_parent = parents[names['spine_root_joint']]
    rest_world = pose_world(rest, parents)
    root_basis = RIGHT[:3, :3] @ rest_world[root_parent][:3, :3]
    maximum_point_error = 0.
    for tick in range(119):
        first, second, fraction = tick // 2, min(59, tick // 2 + 1), (tick % 2) / 2
        local = [value.copy() for value in rest]
        for name, column in columns.items():
            node = names[name]
            position = channels[node, 'translation'][first] * (1 - fraction) + channels[node, 'translation'][second] * fraction
            rotation = channels[node, 'rotation'][first] * (1 - fraction) + channels[node, 'rotation'][second] * fraction
            local[node] = matrix(position, rotation, g['nodes'][node]['scale'])
        world = pose_world(local, parents)
        for capsule in bones['capsules']:
            target = edges[capsule['id']]
            require(target['radiusMillimeters'] == capsule['radiusCentimeters'] * 10, 'Original capsule radius changed')
            for endpoint in ('base', 'tip'):
                vertex = capsule[endpoint]
                point = np.r_[np.asarray(vertex['localPositionCentimeters']) * [.01, .01, -.01], 1]
                expected = (RIGHT @ world[names[vertex['bone']]] @ point)[:3]
                actual = np.array(target[endpoint][tick])
                error = float(np.max(abs(actual - expected)))
                maximum_point_error = max(maximum_point_error, error)
                require(error <= .000000051, 'Collider is not the exact exported animated bone')
        expected_root = ((raw_root[first] * (1 - fraction) + raw_root[second] * fraction) - raw_root[0]) @ root_basis.T
        actual_root = np.array(track['root'][tick])
        require(np.max(abs(expected_root - actual_root)) <= .000000051, 'Separated source root displacement differs')
    return dict(schema='d15-hound-original-readback-v1', status='pass', modelSHA256=sha(raw),
                candidateSHA256=sha(candidate.read_bytes()), originalMotionSHA256=MOTION_SHA,
                sourceRigNodes=52, originalSkinBindings=50, originalAnimatedBones=41,
                rawFrames=141, croppedFrames=60, samples=119, endpointSamples=119 * 6 * 2,
                channelSamples=82 * 60, maximumFloat32ChannelError=maximum_channel_error,
                maximumInverseBindError=maximum_bind_error, maximumRoundedCapsuleError=maximum_point_error,
                sourceEndEventTick=110, nativeSceneKitExecution=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--models', type=Path, required=True)
    p.add_argument('--configs', type=Path, required=True)
    p.add_argument('--receipt', type=Path, required=True)
    a = p.parse_args()
    result = verify(a.candidate, a.models, a.configs)
    raw = json.dumps(result, indent=2, allow_nan=False).encode()
    require(not a.receipt.exists(), 'Readback receipt already exists')
    a.receipt.write_bytes(raw)
    print(raw.decode())


if __name__ == '__main__':
    main()
