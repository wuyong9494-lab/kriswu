#!/usr/bin/env python3
"""Read back emitted D15 model tracks against retained source motion bytes.

Reconstruct source hierarchy in centimeters before conversion, independently
of the exporter's converted-local FK. Join every written capsule endpoint to
its written bone matrix and verify that core root motion is applied once.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from prepare_erlang_model_tracks import DEFINITIONS, MODELS, PARTS, SOURCE_RIGHT
from sun_triad_assets import C, CI, decode, matrix, require


def verify_document(document, motions):
    tracks = {x['role']: x for x in document['summonTracks']}
    models = {x['role']: x for x in document['models']}
    receipts = {x['role']: x for x in document['receipts']}
    roles = {'erlangSummon_' + x[1] for x in DEFINITIONS}
    require(set(tracks) == set(models) == set(receipts) == roles
            and len(document['summonTracks']) == len(document['models']) == len(document['receipts']) == len(roles),
            'Role inventory differs')
    matrices_checked = endpoints_checked = 0
    max_matrix_error = max_endpoint_error = 0.
    for record, suffix, ability, kind, alias, stem, raw_frames, crop, self_end, _ in DEFINITIONS:
        role = 'erlangSummon_' + suffix
        t, m, receipt = tracks[role], models[role], receipts[role]
        raw = motions[stem]
        original = receipt['originalMotion']
        require(hashlib.sha256(raw).hexdigest() == original['sha256'] == t['sourceSHA256']
                and len(raw) == original['bytes'], 'Retained original motion identity differs')
        require(t['boneConfigurationSHA256'] == MODELS[kind]['bonesSHA'], 'Source bone configuration differs')
        arrays = decode(raw)
        require(len(arrays) == 2 and all(a['frame_count'] == raw_frames for a in arrays), 'Original arrays differ')
        a = arrays[0]
        frames = crop or raw_frames
        samples = 2 * (frames - 1) + 1
        animation_end = max(0, 2 * (frames - 1 - (4 if self_end is None else self_end)))
        delete = 70 if suffix == 'sword' else None
        require(t['role'] == m['role'] and t['clip'] == stem and t['frames'] == frames
                and len(t['root']) == len(t['groundLift']) == samples
                and t['sourceEndEventTick'] == animation_end and t.get('sourceDeleteEventTick') == delete
                and m['sourceAnimation'] == alias and m['sourceRecordIndex'] == record
                and m['ability'] == ability and m['motion']['firstIndex'] == 0
                and m['motion']['frames'] == frames and m['motion']['lastSampleTick'] == samples - 1,
                'Cropped samples or terminal event identity differs')
        require(all(v == 0 for v in t['groundLift']), 'Source model acquired a guessed ground lift')
        source = receipt['sourceModel']
        bones = {int(k): v for k, v in source['sourceDeclarations']['bones'].items()}
        rows = source['originalPrefabHierarchy']
        row_by_name = {r['name']: r for r in rows}
        columns = {bones[int(n)]: col for col, n in enumerate(a['bone_ids']) if int(n) in bones}
        require(set(m['bones']) == set(bones.values()), 'Written source bone set differs')
        expected_unbound = [13, 31] if kind == 'ursus' else []
        require(receipt['unboundMotionIDs'] == expected_unbound, 'Unbound source IDs changed')
        axes = m['origin']['selectedAlignAxes']
        roots = np.asarray(t['root'])
        for tick in range(samples):
            i, j, fraction = tick // 2, min(tick // 2 + 1, frames - 1), tick % 2 * .5
            source_world = {}

            def world(name):
                if name in source_world:
                    return source_world[name]
                row = row_by_name[name]
                if name in columns:
                    col = columns[name]
                    p = a['positions'][i, col].astype(float) * (1 - fraction) + a['positions'][j, col].astype(float) * fraction
                    q0, q1 = a['rotations'][i, col].astype(float), a['rotations'][j, col].astype(float)
                    if q0 @ q1 < 0:
                        q1 = -q1
                    q = q0 * (1 - fraction) + q1 * fraction
                else:
                    p, q = row['translation'], row['rotation']
                local = matrix(p, q, row['scale'])
                result = world(row['parent']) @ local if row['parent'] is not None else local
                source_world[name] = result
                return result

            raw_root = (SOURCE_RIGHT @ C @ world('magic_joint_root') @ CI)[:3, 3]
            require(np.max(np.abs(roots[tick] - raw_root)) < 1e-8, 'Root motion readback differs')
            for name in bones.values():
                expected = SOURCE_RIGHT @ C @ world(name) @ CI
                for axis in axes:
                    k = 'XYZ'.index(axis)
                    expected[k, 3] -= roots[0, k]
                actual = np.asarray(m['bones'][name][tick]).reshape(4, 4).T
                error = float(np.max(np.abs(expected - actual)))
                require(error < 1e-8, 'Source rig transform readback differs')
                max_matrix_error = max(max_matrix_error, error)
                matrices_checked += 1
        edges = {x['id']: x for x in t['collisionEdges']}
        declarations = {x['id']: x for x in source['sourceDeclarations']['capsules']}
        require(set(edges) == set(declarations) == set(PARTS[suffix])
                and t['attackParts'] == {'primary': PARTS[suffix]}, 'Actual attacking parts differ')
        for part, edge in edges.items():
            definition = declarations[part]
            require(edge['radiusMillimeters'] == definition['radiusCentimeters'] * 10
                    and edge['side'] == 'right', 'Original capsule radius or slot differs')
            for endpoint in ('base', 'tip'):
                require(len(edge[endpoint]) == samples, 'Capsule sample count differs')
                vertex = definition[endpoint]
                local = C @ np.array([*vertex['localPositionCentimeters'], 1.])
                for tick in range(samples):
                    bone = np.asarray(m['bones'][vertex['bone']][tick]).reshape(4, 4).T
                    expected = (bone @ local)[:3]
                    actual = np.array(edge[endpoint][tick])
                    actual[0] += roots[tick, 0] - roots[0, 0]
                    error = float(np.max(np.abs(expected - actual)))
                    require(error < 3e-8, 'Collision and source pose do not reconstruct the same endpoint')
                    max_endpoint_error = max(max_endpoint_error, error)
                    endpoints_checked += 1
        if suffix == 'meditation':
            require(edges[PARTS[suffix][0]]['radiusMillimeters'] == 2250, 'Original explosion radius was reduced')
        if kind == 'ursus':
            require(m['origin']['sourceShiftCentimeters'] == [2000., 0., 0.], 'Source Align shift was reduced')
            lengths = np.linalg.norm(np.asarray(edges[PARTS[suffix][0]]['tip']) - edges[PARTS[suffix][0]]['base'], axis=1)
            require(np.max(np.abs(lengths - 42.)) < 1e-7, 'Original 42m source capsule was reduced')
    return dict(passed=True, models=len(roles), matrixSamples=matrices_checked, capsuleEndpoints=endpoints_checked,
                maximumMatrixErrorMeters=max_matrix_error, maximumEndpointErrorMeters=max_endpoint_error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    args = parser.parse_args()
    document = json.loads(args.candidate.read_bytes())
    motions = {stem: (args.candidate.parent / (stem + '.original-private.bytes')).read_bytes()
               for stem in {x[5] for x in DEFINITIONS}}
    print(json.dumps(verify_document(document, motions), separators=(',', ':')))


if __name__ == '__main__':
    main()
