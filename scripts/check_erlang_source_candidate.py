#!/usr/bin/env python3
"""Read back the actual private actor without decoding any source motion again.

Checks the untouched supplied portrait, the generated bridge's skin contract,
the original 55 clips, and the real one-key TransformOut GLB animation/FK.
This is an offline asset check, not native rendering or gameplay acceptance.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path

import numpy as np

from sun_triad_assets import accessor_read, glb_read, require, world_poses

PORTRAIT_SHA = '279b7d840bbb99550f82e3c283a5a6e58753e7793be225259621f2dfc2a75cd0'
STATIC_SHA = '72da7978875aa9b288933add7c045cdc417938a6f9887a55d0e0efddcf7123e1'
MIRROR_GLB_SHA = 'f0906ee8b6e484ed8037e424e140774399fd833d63bca29ff175811f60a08ec7'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def checked(path, expected, maximum):
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum,
            'Input is not a bounded regular file')
    data = path.read_bytes()
    require(digest(data) == expected, 'Input digest differs: ' + path.name)
    return data


def image_hashes(g, binary):
    result = []
    for image in g['images']:
        require('uri' not in image, 'External image is not self contained')
        view = g['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        result.append(digest(binary[start:start + view['byteLength']]))
    return result


def check(args):
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    model = args.profile.parent / (profile['resourceName'] + '.glb')
    raw = checked(model, profile['sha256'], 48_000_000)
    require(len(raw) == profile['bytes'] and profile['id'] == 'wuyong_erlang', 'Actor identity differs')
    g, b = glb_read(model)
    checked(args.portrait, PORTRAIT_SHA, 8_000_000)
    old, original = glb_read(args.portrait)
    portraits = [n for n in g['nodes'] if n.get('name') == 'WuYong_Personal_Head']
    require(len(portraits) == 1 and 'skin' not in portraits[0], 'Original portrait parenting differs')
    actual = g['meshes'][portraits[0]['mesh']]['primitives']
    expected = old['meshes'][0]['primitives']
    require(len(actual) == len(expected) == 1, 'Portrait primitive inventory differs')
    for key, source in expected[0]['attributes'].items():
        target = actual[0]['attributes'][key]
        require(all(old['accessors'][source][field] == g['accessors'][target][field]
                    for field in ('componentType', 'type', 'count')), 'Portrait accessor format changed')
        require(accessor_read(old, original, source).tobytes() == accessor_read(g, b, target).tobytes(),
                'Original portrait attribute bytes changed: ' + key)
    require(old['accessors'][expected[0]['attributes']['POSITION']]['count'] == 59_878,
            'Supplied original portrait vertex count differs')
    require(accessor_read(old, original, expected[0]['indices']).tobytes() ==
            accessor_read(g, b, actual[0]['indices']).tobytes(), 'Original portrait indices changed')
    require(set(image_hashes(old, original)) <= set(image_hashes(g, b)), 'Original portrait image bytes changed')
    print('PASS all 59,878 supplied portrait vertices, normals, UVs, indices and original image bytes preserved')

    checked(args.mirror_glb, MIRROR_GLB_SHA, 48_000_000)
    prior, previous = glb_read(args.mirror_glb)
    prior_bytes = prior['buffers'][0]['byteLength']
    require(b[:prior_bytes] == previous[:prior_bytes], 'Original source binary prefix was modified')
    require(g['animations'][:55] == prior['animations'] and len(prior['animations']) == 55,
            'The previously verified source animations changed')
    require(g['skins'] == prior['skins'] and len(g['skins']) == 1, 'Original source skin was modified')
    print('PASS all 55 preceding source animations and original embedded binary data unchanged')

    bridges = [n for n in g['nodes'] if n.get('name') == 'Personal_Neck_Bridge']
    require(len(bridges) == 1 and bridges[0]['skin'] == 0, 'Generated bridge must share the original actor skin')
    mesh = g['meshes'][bridges[0]['mesh']]
    require(mesh['extras'] == dict(generatedPersonalFitting=True, originalSF3Geometry=False),
            'Generated bridge is not labelled as an adaptation')
    primitive = mesh['primitives'][0]
    positions = accessor_read(g, b, primitive['attributes']['POSITION'])
    joints = accessor_read(g, b, primitive['attributes']['JOINTS_0'])
    weights = accessor_read(g, b, primitive['attributes']['WEIGHTS_0'])
    source_slots = {i for i, node in enumerate(g['skins'][0]['joints']) if g['nodes'][node]['name'] in ('head', 'neck')}
    require(len(positions) == 226 and np.isfinite(positions).all(), 'Generated bridge geometry differs')
    require(set(joints[weights > 0].tolist()) == source_slots and len(source_slots) == 2,
            'Generated bridge weights do not use exactly the real head/neck joints')
    require(np.isfinite(weights).all() and (weights >= 0).all() and
            np.max(np.abs(weights.sum(axis=1) - 1)) < 1e-6, 'Invalid generated bridge skin weights')
    print('PASS separate generated bridge, unchanged original skin and normalized source head/neck weights')

    name = profile['roles']['erlangTransformOut']
    clips = [c for c in profile['clips'] if c['name'] == name]
    require(len(profile['clips']) == len(g['animations']) == 56 and len(clips) == 1, 'Actor clip inventory differs')
    clip = clips[0]
    require(clip['frames'] == clip['sourceWindowFrames'] == 1 and clip['sourceUncroppedFrames'] == 62 and
            clip['sourceFirstIndex'] == clip['sourceLastIndex'] == clip['playbackTicks'] == clip['sourceEndEventTick'] == 0,
            'TransformOut duplicated a sample or invented duration')
    require(clip['sha256'] == STATIC_SHA and digest(base64.b64decode(clip['sourceBytesBase64'], validate=True)) == STATIC_SHA,
            'TransformOut original source motion differs')
    require(clip['bundle'] == 'baccadc1bc62c24fcf83246b63fd6c17.bin' and
            clip['sourceConfiguration']['sourceRecordIndex'] == 133 and len(clip['tracks']['hurtCapsules']) == 15,
            'TransformOut original configuration or geometry differs')
    animation = g['animations'][-1]
    require(animation['name'] == name and animation['extras']['sourceStaticPose'] is True,
            'Static animation does not match the profile')
    pose = copy.deepcopy(g['nodes'])
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        times = accessor_read(g, b, sampler['input'])
        values = accessor_read(g, b, sampler['output'])
        require(len(times) == len(values) == 1 and times.flat[0] == 0,
                'Static GLB animation contains invented time or duplicate keys')
        pose[channel['target']['node']][channel['target']['path']] = values[0].tolist()
    world, _, _ = world_poses(pose)
    names = {n['name']: i for i, n in enumerate(pose)}
    # The arena is the source actor rotated -90 degrees around its Y axis.
    # Recompute from the stored GLB keys, independently of source decoding.
    arena = np.array([[0., 0., -1., 0.], [0., 1., 0., 0.], [1., 0., 0., 0.], [0., 0., 0., 1.]])
    for field, bone in [('head', 'head'), ('pelvis', 'pelvis'), ('toeL', 'toe_l'), ('toeR', 'toe_r')]:
        values = clip['tracks'][field]
        require(len(values) == 1 and np.max(np.abs(np.asarray(values[0]) - (arena @ world[names[bone]][:, 3])[:3])) < 1e-6,
                'Static landmark differs from the actual stored GLB pose: ' + field)
    require(len(clip['tracks']['root']) == len(clip['tracks']['centerOfMass']) == 1,
            'Static root or centre-of-mass sample was duplicated')
    require(sum(len(c['tracks']['head']) for c in profile['clips']) == 6_556 and
            all(len(c['tracks']['head']) == 2 * c['frames'] - 1 for c in profile['clips']), 'Head landmark inventory differs')
    print('PASS true one-key TransformOut and actual GLB head/pelvis/toe FK; complete 6,556 head samples')
    print('4 actual private source-candidate checks passed; no source media decoded and no native run')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('profile', 'portrait', 'mirror-glb'):
        p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--profile-sha256', required=True)
    check(p.parse_args())


if __name__ == '__main__':
    main()
