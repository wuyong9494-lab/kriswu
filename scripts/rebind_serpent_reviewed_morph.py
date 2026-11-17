#!/usr/bin/env python3
"""Bind the reviewed H17 victory operation to the actual D13 actor.

Only an isolated manifest, unchanged mask and provenance receipt are written. The GLB, original
bundles, owner catalog, release, mask, UVs, weights and animation bytes are never
modified. Source material objects are read from existing authenticated bundles;
the source trigger and Helmet/Armor/base-model override are inherited from the
independently pinned, validated H17 template, not reconstructed from missing raw
lock values. This does not claim native rendering or a complete D13 skill kit.

Requires the already reviewed UnityPy 1.25.4 and the repository's numpy helpers.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import warnings
from zipfile import ZipFile

from build_sun_triad_release import validate_morph_document
from sun_triad_assets import accessor_read, glb_read, require


PROFILE_SHA = 'ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53'
CHARACTER_SHA = 'f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70'
OWNER_SHA = '7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a'
OWNER_CATALOG_SHA = '77f7dd57c512aed3091fbedf8815ea5c6fc4b80725e9785cb2953bce2a47b6f4'
TEMPLATE_SHA = '563fc2ee9eabcf2b9dd82049ff61cc5c1be1c74ebcd2614180878ed4701f046b'
CATALOG_SHA = '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'
ITEMS_SHA = '745b6e2b81bf2cfd5ac5b9bc03daad3590df05629ff8e7ec6f9578ea47cb1270'
ENUMS_SHA = 'a25d99614c2ad6ce5ea816a99112e8ffbec616870b251dd5684d05a1a6ad6ecd'
MANIFEST_NAME = 'SF3_H17_SerpentMorph.json'
BUNDLE_PREFIX = 'continued-20261116/serpent-original-bundles-v1/'
BUNDLES = {
    '33f20d1e8d0d3b0593bd9563d6a6b8f3.bin': (1925946,
        '3e0100bd0c65759be4beb639b67150cb117fdc6b129e1785cd8fcaf6e806dde0'),
    '509ae228a7ddaa97d6a92331cb989b7b.bin': (189246,
        '993cd59c754c90dcc5dff46c6929b87b6e59de7acbac072c981f430d6d68a648'),
    'adec8ebcda70a8d831c9872b12ac1272.bin': (455947,
        '9a7f69be76751c7626bd8b7940f20bdb3beb1dc6b8c65c65fa37fa77e58cf1cc'),
}
MATERIALS = {
    'mat_arm__agl_41_base': ('33f20d1e8d0d3b0593bd9563d6a6b8f3.bin',
        'arm__agl_41', 2, -3421429627078980096, 2588,
        '0f471c40444f90fd22a40a5b61c0488d6de8e66ec93600fb202d308cd6d26711'),
    'mat_arm__agl_41_tie_base': ('33f20d1e8d0d3b0593bd9563d6a6b8f3.bin',
        'arm__agl_41', 2, -6575793965177864509, 2592,
        '2dab8edb4b821cc37be04d44beddea099192df5261d5451d8de6cde45c7edd26'),
    'mat_helm__agl_41_base': ('adec8ebcda70a8d831c9872b12ac1272.bin',
        'helm__agl_41', 1, 882679246480386282, 2592,
        'b40420c61052f467ef0663cb67883b673ba8766ea905017978a81dbb0cf14f28'),
    'mat_wpn__shuangou_01_04_base': ('509ae228a7ddaa97d6a92331cb989b7b.bin',
        'wpn__shuangou_01_04', 3, -7211095366403513463, 2596,
        'a7c962a188229279c34c47c7e1b599661b69b2b5f28e40506f56df5b34b1a503'),
}
PERSONAL = {'Liu_Neck_Skin', 'tripo_mat_c4757646'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def record(path):
    raw = path.read_bytes()
    return dict(name=path.name, bytes=len(raw), sha256=digest(raw))


def checked(path, expected, maximum):
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum,
            'Missing, linked or oversized input: ' + path.name)
    raw = path.read_bytes()
    require(digest(raw) == expected, 'Pinned input differs: ' + path.name)
    return raw


def member(archive, name, expected, maximum):
    matches = [entry for entry in archive.infolist() if entry.filename == name]
    require(len(matches) == 1 and 0 < matches[0].file_size <= maximum,
            'Missing, duplicate or oversized source entry: ' + name)
    raw = archive.read(matches[0])
    require(digest(raw) == expected, 'Pinned source entry differs: ' + name)
    return raw


def source_materials(args):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    rows = [json.loads(line) for line in checked(args.source_catalog, CATALOG_SHA, 10_000_000).splitlines()]
    catalog = {row['file']: row for row in rows}
    require(len(catalog) == len(rows), 'Duplicate original bundle catalog entry')
    result = {}
    with ZipFile(args.bundle_archive) as archive:
        for filename, (count, expected) in BUNDLES.items():
            raw = member(archive, BUNDLE_PREFIX + filename, expected, count)
            require(len(raw) == count and catalog[filename]['bytes'] == count and
                    catalog[filename]['sha256'] == expected, 'Original bundle identity differs')
            environment = UnityPy.load(raw)
            for name, (bundle, stem, item_type, path_id, size, object_sha) in MATERIALS.items():
                if filename != bundle:
                    continue
                source_path = ('assets/gamedata/resources/content/items/models/top100/' +
                               stem + '/m/materials/' + name + '.mat')
                require([p for p in catalog[filename]['paths'] if p['path'] == source_path] ==
                        [dict(path=source_path, file_id=0, path_id=path_id)], 'Source material path differs')
                objects = [obj for obj in environment.objects if obj.type.name == 'Material' and obj.path_id == path_id]
                require(len(objects) == 1, 'Source material object is ambiguous')
                reader = objects[0]; material = reader.read(); material_raw = reader.get_raw_data()
                require(len(material_raw) == size and digest(material_raw) == object_sha and
                        material.m_Name == name and material.m_Shader.m_PathID == 8133545925718130986,
                        'Source material bytes or shader differ')
                floats = dict(material.m_SavedProperties.m_Floats)
                colors = {k: [v.r, v.g, v.b, v.a] for k, v in material.m_SavedProperties.m_Colors}
                masks = [v for k, v in material.m_SavedProperties.m_TexEnvs if k == '_MorphMask']
                require(len(masks) == 1, 'Source MorphMask property is ambiguous')
                mask = masks[0]
                require(mask.m_Texture.m_FileID == 2 and mask.m_Texture.m_PathID == 3396178089779778423 and
                        [mask.m_Scale.x, mask.m_Scale.y] == [1, 1] and
                        [mask.m_Offset.x, mask.m_Offset.y] == [0, 0] and
                        floats['_Alpha'] == floats['_MorphCutoff'] == 1,
                        'Original mask, alpha or cutoff differs')
                result[name] = dict(sourceItemType=item_type, sourceBundle=filename,
                    sourceBundleSHA256=expected, sourcePath=source_path, sourcePathID=str(path_id),
                    sourceObjectBytes=size, sourceObjectSHA256=object_sha,
                    sourceMorphDefaults=dict(tile=floats['_MorphMaskTile'], edgeSize=floats['_EdgeSize'],
                        edgeStart=colors['_EdgeColorStart'], edgeEnd=colors['_EdgeColorEnd']))
    require(set(result) == set(MATERIALS), 'Incomplete D13 source material inventory')
    return result


def item_classes(path):
    with ZipFile(path) as archive:
        items = member(archive, 'scripts/features/items/entities/items.js', ITEMS_SHA, 4_000_000).decode()
        enums = member(archive, 'scripts/common/enums.js', ENUMS_SHA, 64_000).decode()
    records = []
    for key, item_id, model, kind, value in [
        ('ARM_AGL_41', 22029, 'arm__agl_41', 'ARMOR', 2),
        ('HLM_AGL_41', 23028, 'helm__agl_41', 'HELMET', 1),
        ('WPN_SHUANGOU_01_04', 21024, 'wpn__shuangou_01_04', 'WEAPON', 3),
    ]:
        require(f'ITEMTYPE[ITEMTYPE["{kind}"]={value}]="{kind}"' in enums, 'Source item enumeration differs')
        found = re.findall(r'\b' + re.escape(key) + r':\{[^{}]*\}', items)
        require(len(found) == 1 and f'ID:{item_id},' in found[0] and
                f'Model:"Top100/{model}"' in found[0] and f'ItemType:ITEMTYPE.{kind}' in found[0],
                'Source D13 item classification differs')
        records.append(dict(name=key, id=item_id, model='Top100/' + model,
                            itemType=value, recordSHA256=digest(found[0].encode())))
    return records


def inspect_geometry(g, binary, originals):
    import numpy as np
    names = [m.get('name') for m in g['materials']]
    require(len(names) == len(set(names)) == 6 and set(names) == set(MATERIALS) | PERSONAL,
            'Actual D13 material inventory differs')
    require(len(g['skins']) == 1 and len(g['skins'][0]['joints']) == 80 and len(g['animations']) == 66,
            'Pinned actor skin or animation inventory differs')
    for material in g['materials']:
        name = material['name']
        if name in PERSONAL:
            continue
        extra = material['extras']; defaults = originals[name]['sourceMorphDefaults']
        require(extra['sourceMaterial'] == name and
                extra['sourceFloats']['_MorphMaskTile'] == defaults['tile'] and
                extra['sourceFloats']['_EdgeSize'] == defaults['edgeSize'] and
                extra['sourceColors']['_EdgeColorStart'] == defaults['edgeStart'] and
                extra['sourceColors']['_EdgeColorEnd'] == defaults['edgeEnd'] and
                extra['sourceTextureBindings']['_MorphMask']['sourceFileID'] == 2 and
                extra['sourceTextureBindings']['_MorphMask']['sourcePathID'] == '3396178089779778423',
                'Actor material differs from authenticated original defaults')
    used, geometry = set(), []
    for mesh in g['meshes']:
        for index, primitive in enumerate(mesh['primitives']):
            attrs = primitive['attributes']; name = names[primitive['material']]
            require(primitive.get('mode', 4) == 4, 'Non-triangle target geometry')
            position = accessor_read(g, binary, attrs['POSITION'])
            indices = accessor_read(g, binary, primitive['indices']).reshape(-1)
            require(position.ndim == 2 and position.shape[1] == 3 and len(position) > 0 and
                    np.isfinite(position).all() and len(indices) > 0 and len(indices) % 3 == 0 and
                    int(indices.min()) >= 0 and int(indices.max()) < len(position), 'Invalid actual geometry')
            has_uv = 'TEXCOORD_0' in attrs
            require(has_uv or (mesh['name'] == 'Liu_Neck_Bridge' and name == 'Liu_Neck_Skin'),
                    'Unreviewed geometry without actual UV')
            if has_uv:
                uv = accessor_read(g, binary, attrs['TEXCOORD_0'])
                require(uv.shape == (len(position), 2) and np.isfinite(uv).all(), 'Invalid actual UV')
            else:
                material = g['materials'][primitive['material']]
                require(not any(k.endswith('Texture') for k in material) and
                        not any(k.endswith('Texture') for k in material['pbrMetallicRoughness']) and
                        len(material['pbrMetallicRoughness']['baseColorFactor']) == 4,
                        'Constant-origin adapter requires the existing untextured neck')
            geometry.append(dict(mesh=mesh['name'], primitive=index, material=name,
                vertices=len(position), triangles=len(indices)//3, authoredUV=has_uv,
                constantSourceMaskOrigin=not has_uv))
            used.add(name)
    require(used == set(names) and len(geometry) == 9 and
            sum(not row['authoredUV'] for row in geometry) == 1, 'Incomplete target renderer coverage')
    return geometry


def validate_candidate(document, template, target, materials):
    require(document['version'] == 2 and document['ownerProfileID'] == 'sun_triad' and
            document['ownerCharacterSHA256'] == OWNER_SHA and document['targetProfileID'] == 'liu_serpent' and
            document['targetCharacterSHA256'] == CHARACTER_SHA == target['sha256'], 'Candidate actor identity differs')
    for key in ('sourceConfigurationSHA256', 'trigger', 'mask', 'projectedShadow'):
        require(document[key] == template[key], 'Candidate changed reviewed source behavior: ' + key)
    require(document['materials'] == materials and len(materials) == 6 and
            {m['name'] for m in materials} == set(MATERIALS) | PERSONAL, 'Incomplete candidate materials')
    for row in materials:
        kind = None if row['name'] in PERSONAL else MATERIALS[row['name']][2]
        require(row['sourceItemType'] == kind and row['actorBaseGeometry'] == (kind is None),
                'Candidate source item type differs')
        for key, expected in [('tile', .1 if kind == 3 else .2), ('edgeSize', .1)]:
            require(type(row[key]) in (int, float) and math.isfinite(row[key]) and
                    abs(row[key] - expected) <= 1e-7, 'Candidate morph parameters differ')
        for key, expected in [('edgeStart', [0, 26/255, 146/255, 1] if kind == 3 else [0, 0, 0, 1]),
                              ('edgeEnd', [0, 237/255, 244/255, 1] if kind == 3 else [0, 87/255, 96/255, 1])]:
            require(len(row[key]) == 4 and all(math.isfinite(a) and abs(a-b) <= 1e-7
                    for a, b in zip(row[key], expected)), 'Candidate morph color differs')


def prepare(args):
    require(not args.output.exists(), 'Refuse to replace an existing candidate directory')
    repository = Path(__file__).resolve().parents[1]
    require(not args.output.resolve().is_relative_to(repository), 'Private candidate must remain outside the checkout')
    target = json.loads(checked(args.target_profile, PROFILE_SHA, 24_000_000))
    require(target['id'] == 'liu_serpent' and target['hero'] == 'liu' and
            target['bodyID'] == 'arm__agl_41' and target['helmetID'] == 'helm__agl_41' and
            target['weaponID'] == 'wpn__shuangou_01_04' and target['rangedID'] == 'rng__bottle_01_02' and
            target['resourceName'] == 'Liu_KingOfSerpents_D13_Recovered_Combat' and
            target['bytes'] == 15561412 and target['sha256'] == CHARACTER_SHA, 'D13 profile identity differs')
    actor_path = args.target_profile.parent / (target['resourceName'] + '.glb')
    actor_raw = checked(actor_path, CHARACTER_SHA, target['bytes'])
    require(len(actor_raw) == target['bytes'], 'D13 character length differs')
    catalog = json.loads(checked(args.owner_catalog, OWNER_CATALOG_SHA, 36_000_000))
    owner = next(p for p in catalog['profiles'] if p['id'] == 'sun_triad')
    legacy = next(p for p in catalog['profiles'] if p['id'] == 'liu_hammers')
    require(owner['sha256'] == OWNER_SHA, 'Reviewed owner container differs')
    template = json.loads(checked(args.source_morph, TEMPLATE_SHA, 256_000))
    validate_morph_document(template, owner, legacy)
    mask_path = args.source_morph.parent / template['mask']['file']
    mask_raw = checked(mask_path, template['mask']['sha256'], template['mask']['bytes'])
    require(len(mask_raw) == template['mask']['bytes'], 'Mask length differs')
    originals = source_materials(args); items = item_classes(args.decoded_scripts)
    g, binary = glb_read(actor_path); geometry = inspect_geometry(g, binary, originals)
    override = {k: next(row for row in template['materials'] if row['sourceItemType'] == 2)[k]
                for k in ('tile', 'edgeSize', 'edgeStart', 'edgeEnd')}
    materials = []
    for material in g['materials']:
        name = material['name']; kind = None if name in PERSONAL else originals[name]['sourceItemType']
        parameters = originals[name]['sourceMorphDefaults'] if kind == 3 else override
        materials.append(dict(name=name, sourceItemType=kind, actorBaseGeometry=kind is None, **parameters))
    document = copy.deepcopy(template)
    document.update(targetProfileID=target['id'], targetCharacterSHA256=target['sha256'], materials=materials)
    document['evidence'] = [
        'H17 final-victory trigger, original mask, projected shadow, and Helmet/Armor/base-model overrides are inherited unchanged from the separately pinned reviewed H17 template. Missing raw lock values are not reconstructed.',
        'The four original D13 male Material objects are verified by exact bundle SHA, catalog path, PathID, raw-object SHA, source shader, mask reference, and serialized defaults. Source item records classify helmet as ItemType1, armor/tie as ItemType2, and Shuangou as ItemType3.',
        'All six actual target materials and nine actual primitives are covered. Helmet, armor, tie, and the explicit personal head/neck base geometry receive the reviewed non-Weapon override. Shuangou retains its own serialized source defaults.',
        'The existing untextured Liu_Neck_Skin has no UV. It uses the reviewed constant source-mask origin adapter; no UV, weights, geometry, textures, or any of the 66 animations are changed.',
        'This manifest binds H17 victory to the liu_serpent D13 actor; it does not reuse liu_hammers appearance or Wu materials. Native Metal installation, full hide/reset/cancellation, selected-pair identity, and signed device acceptance remain unverified.'
    ]
    validate_candidate(document, template, target, materials)
    args.output.mkdir(parents=True)
    output_path = args.output / MANIFEST_NAME
    raw = (json.dumps(document, indent=2, ensure_ascii=False) + '\n').encode()
    with output_path.open('xb') as stream:
        stream.write(raw)
    with (args.output / template['mask']['file']).open('xb') as stream:
        stream.write(mask_raw)
    # Independent disk readback, plus a second target digest: neither source nor
    # output mutation may turn the construction result into an accepted receipt.
    reread = json.loads(output_path.read_bytes())
    validate_candidate(reread, template, target, materials)
    require(record(args.output / template['mask']['file']) == record(mask_path), 'Copied source mask differs')
    require(digest(actor_path.read_bytes()) == CHARACTER_SHA, 'Original actor changed during generation')
    proof = dict(schema='d13-reviewed-victory-morph-candidate-v1', status='isolated-verified-inputs-native-unverified',
        manifest=record(output_path), mask=record(mask_path), sourceTemplate=record(args.source_morph),
        ownerCatalog=record(args.owner_catalog), ownerProfileID=owner['id'], ownerCharacterSHA256=OWNER_SHA,
        targetProfile=record(args.target_profile), targetCharacter=record(actor_path), targetProfileID=target['id'],
        sourceBundleCatalogSHA256=CATALOG_SHA, sourceItemsSHA256=ITEMS_SHA, sourceEnumsSHA256=ENUMS_SHA,
        sourceMaterials=originals, sourceItemRecords=items, materialBindings=materials,
        actualGeometry=geometry, actualSkinJointCount=80, actualAnimationCount=66,
        originalGLBModified=False, addedUV=False, changedWeights=False, changedAnimationBytes=False,
        sourceRules='inherited from exact reviewed template; no new raw lock decode',
        nativeRendered=False, productionReady=False, uploaded=False,
        independentReadbackValidated=True)
    with (args.output / 'serpent-morph-provenance-private.json').open('x') as stream:
        json.dump(proof, stream, indent=2, ensure_ascii=False); stream.write('\n')
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('target-profile', 'owner-catalog', 'source-morph', 'source-catalog',
                 'bundle-archive', 'decoded-scripts', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    proof = prepare(parser.parse_args())
    print(json.dumps({key: proof[key] for key in ('status', 'manifest', 'targetProfileID',
        'originalGLBModified', 'independentReadbackValidated', 'nativeRendered', 'productionReady')}))


if __name__ == '__main__':
    main()
