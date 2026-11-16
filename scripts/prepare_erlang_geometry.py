#!/usr/bin/env python3
"""Recover the exact local WuYong equipment geometry as a separate static input.

This reuses the existing source-pinned geometry builder. It deliberately emits
no character profile, motion catalogue, runtime rules, or release candidate.
The personal portrait fit and portable material adaptation remain explicit.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from build_erlang_source_assets import (
    ACTOR, BODY, CONFIGS, HEAD_SHA, WEAPON, build_geometry, checked, encoded,
    local_source, record, write_new,
)
from prepare_fighter_target_motions import ARCHIVE_SHA256
from sun_triad_assets import accessor_read, glb_read, private_output, require
from sun_triad_source_bones import parse_bones_data


def image_bytes(document, binary, image):
    require('uri' not in image, 'Expected an embedded image')
    view = document['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    return binary[start:start + view['byteLength']]


def readback(model, head, expected_nodes):
    """Inspect the written binary, including the supplied portrait's arrays."""
    document, binary = glb_read(model)
    original, source_binary = glb_read(head)
    require(not document.get('animations'), 'Static geometry contains animation')
    require(len(document['skins']) == 1 and len(document['meshes']) == 8,
            'Expected seven equipment meshes and the supplied portrait')
    require(len(document['skins'][0]['joints']) == expected_nodes,
            'Original equipment skeleton count differs')
    parents = {}
    for index, node in enumerate(document['nodes']):
        for child in node.get('children', []):
            require(child not in parents, 'Geometry contains multiple parents')
            parents[child] = index
    portraits = [(i, n) for i, n in enumerate(document['nodes'])
                 if n['name'] == 'WuYong_Personal_Head']
    require(len(portraits) == 1, 'Personal portrait node is missing or ambiguous')
    index, node = portraits[0]
    require('skin' not in node and document['nodes'][parents[index]]['name'] == 'head',
            'Personal portrait must remain an unskinned child of the source head')
    primitives = document['meshes'][node['mesh']]['primitives']
    source_primitives = original['meshes'][0]['primitives']
    require(len(primitives) == len(source_primitives), 'Portrait primitive count differs')
    arrays = 0
    vertices = 0
    for actual, source in zip(primitives, source_primitives):
        require(set(actual['attributes']) == set(source['attributes']),
                'Portrait attributes changed')
        for key, source_index in source['attributes'].items():
            expected = accessor_read(original, source_binary, source_index)
            observed = accessor_read(document, binary, actual['attributes'][key])
            require(expected.dtype == observed.dtype and np.array_equal(expected, observed),
                    'Portrait array changed: ' + key)
            arrays += 1
        require(np.array_equal(accessor_read(original, source_binary, source['indices']),
                               accessor_read(document, binary, actual['indices'])),
                'Portrait indices changed')
        arrays += 1
        vertices += document['accessors'][actual['attributes']['POSITION']]['count']
    original_images = [image_bytes(original, source_binary, i) for i in original['images']]
    actual_images = [image_bytes(document, binary, i) for i in document['images']]
    require(all(actual_images.count(raw) >= original_images.count(raw) for raw in original_images),
            'Portrait encoded image bytes changed')
    renderers = []
    for index, node in enumerate(document['nodes']):
        if 'mesh' not in node:
            continue
        mesh = document['meshes'][node['mesh']]
        renderers.append(dict(node=index, name=node['name'], mesh=mesh['name'],
            skin=node.get('skin'), parent=document['nodes'][parents[index]]['name'],
            materialNames=[document['materials'][p['material']]['name'] for p in mesh['primitives']]))
    return dict(status='pass', nodes=len(document['nodes']), meshes=len(document['meshes']),
        skins=len(document['skins']), skinJoints=expected_nodes, animations=0,
        personalHeadVertices=vertices, personalHeadArraysChecked=arrays,
        personalHeadImagesByteIdentical=len(original_images), renderers=renderers,
        headPrefixMatches=[r['name'] for r in renderers if r['name'].startswith('head_')],
        nativeSceneKitExecuted=False)


def build(args):
    require(not args.output.exists(), 'Refuse to overwrite an existing candidate')
    bundles, _, load = local_source(args)
    configs = {}
    inputs = []
    for kind, (name, pin) in CONFIGS.items():
        folder = args.source_configs if kind == 'weapon' else args.shared_bones
        path = folder / name
        configs[kind] = parse_bones_data(checked(path, pin, 1_000_000))
        inputs.append(dict(kind=kind, **record(path)))
    checked(args.head, HEAD_SHA, 8_000_000)
    writer, names, _, audit = build_geometry(args, bundles, load, configs)
    writer.g['asset']['generator'] = 'Verified WuYong D15 static source geometry'
    writer.g['extras'] = dict(schema='erlang-static-source-geometry-v1', sourceOnly=True,
        runtimeBound=False, personalPortraitSHA256=HEAD_SHA, customShaderParity=False,
        humanAnimationsIncluded=False, fullCharacterCandidate=False)
    output = private_output(args.output)
    model = output / 'WuYong_Erlang_D15_Static_Source.glb'
    writer.save(model)
    model.chmod(0o600)
    verified = readback(model, args.head, len(names))
    receipt = dict(schema='erlang-static-source-geometry-receipt-v1', model=record(model),
        sourceArchiveSHA256=ARCHIVE_SHA256, sourceBoneConfigs=inputs,
        sourceBundles=[{key: bundles[name][key] for key in ('file', 'bytes', 'sha256')}
                       for name in (ACTOR, BODY, WEAPON)],
        geometry=audit, readback=verified,
        boundary=dict(sourceOnly=True, runtimeBound=False, profilesWritten=0,
            animationsWritten=0, referenceCatalogReconstructed=False,
            historicalBodyIdentityRestored=False, nativeRenderingVerified=False,
            shaderParityVerified=False, personalPortraitFitIsAdaptation=True,
            sourceMaterialPaletteWithPortableLighting=True,
            productionActivation=False, signed=False, uploadedToTestFlight=False))
    receipt_path = output / 'geometry-source-receipt-private.json'
    write_new(receipt_path, encoded(receipt))
    return dict(model=record(model), receipt=record(receipt_path), readback=verified,
                runtimeBound=False, fullCharacterCandidate=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-archive', 'source-bundles', 'source-configs', 'shared-bones', 'head', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    import json
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
