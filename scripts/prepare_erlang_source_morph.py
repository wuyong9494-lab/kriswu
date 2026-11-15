#!/usr/bin/env python3
"""Bind source H17 victory morph to the actual Wu D15 target materials.

Reads only exact cached material objects/configuration and the reviewed actor.
No textures, motions or sounds are decoded; no GLB is written or modified.
Original media and generated runtime manifests must remain outside git.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import warnings
from zipfile import ZipFile

from build_erlang_source_assets import checked, encoded, record, write_new
from build_sun_triad_release import validate_morph_document
from sun_triad_assets import glb_read, private_output, require

CHARACTER_SHA = 'debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd'
CATALOG_SHA = '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'
ITEMS_SHA = '745b6e2b81bf2cfd5ac5b9bc03daad3590df05629ff8e7ec6f9578ea47cb1270'
ENUMS_SHA = 'a25d99614c2ad6ce5ea816a99112e8ffbec616870b251dd5684d05a1a6ad6ecd'
LOCK_VALUES_SHA = '7366f31066b2ea972d61373c8aabfaf025c4fe77c1d42fe8f5603f10c09e095f'
BODY = '21459e232b8ef3f21ee744adf72717f6.bin'
WEAPON = 'e76bb58980e9e1aa0f9ca0c4b20c0d93.bin'
BUNDLES = {
    BODY: (3640386, 'af28425ecbadd094ee460d94086eccd7a165246e0def9627e25730697b5c3e4f'),
    WEAPON: (147455, 'bc2be58ee4769b03b088154104b1cf68b3e6307a5a12307a46d003aab3a82b40'),
}
MATERIALS = {
    'mat_arm__agl_44_base': (BODY, 'arm__agl_44', -6011031156837743352,
        'a69988afe5bc9954b4415f0dc29b9f09bf598df667fe716d8e2ebb505b7352c9'),
    'mat_arm__agl_44_tie_base': (BODY, 'arm__agl_44', -8673216404374002239,
        '66f86a5cb638da93726672c6ed24ec5b805a9721550c790d2fe7c6a95f7d082b'),
    'mat_wpn__agl_spear_01_01_base': (WEAPON, 'wpn__agl_spear_01_01', 4191842072599981697,
        '30e8fdedc23a82dfa6f93769f3c7b71222bf0ef2bf02ebfe455266366f28643e'),
}
PERSONAL = {'Material.001', 'Personal_Neck_Bridge_Derived_Skin'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def zip_member(archive, name, expected, maximum):
    info = archive.getinfo(name)
    require(0 < info.file_size <= maximum, 'Source entry exceeds its bound')
    raw = archive.read(info)
    require(digest(raw) == expected, 'Source entry identity differs: ' + name)
    return raw


def source_materials(bundles, catalog):
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use the already reviewed UnityPy version')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = {}
    for filename, (count, expected) in BUNDLES.items():
        raw = checked(bundles / filename, expected, count)
        require(len(raw) == count, 'Cached source bundle size differs')
        row = catalog[filename]
        require(row['bytes'] == count and row['sha256'] == expected, 'Original catalog bundle differs')
        env = UnityPy.load(raw)
        for name, (bundle, stem, path_id, object_sha) in MATERIALS.items():
            if bundle != filename:
                continue
            path = f'assets/gamedata/resources/content/items/models/top100/{stem}/m/materials/{name}.mat'
            require([p for p in row['paths'] if p['path'] == path] ==
                    [dict(path=path, file_id=0, path_id=path_id)], 'Exact male material catalog path differs')
            readers = [o for o in env.objects if o.path_id == path_id and o.type.name == 'Material']
            require(len(readers) == 1, 'Exact source material object is ambiguous')
            reader = readers[0]; material = reader.read(); object_raw = reader.get_raw_data()
            require(material.m_Name == name and digest(object_raw) == object_sha and
                    material.m_Shader.m_PathID == 8133545925718130986, 'Original material identity differs')
            floats = dict(material.m_SavedProperties.m_Floats)
            colors = {k: [v.r, v.g, v.b, v.a] for k, v in material.m_SavedProperties.m_Colors}
            masks = [v for k, v in material.m_SavedProperties.m_TexEnvs if k == '_MorphMask']
            require(len(masks) == 1, 'Original MorphMask property is ambiguous')
            mask = masks[0]
            require(mask.m_Texture.m_FileID == 2 and mask.m_Texture.m_PathID == 3396178089779778423 and
                    [mask.m_Scale.x, mask.m_Scale.y] == [1, 1] and
                    [mask.m_Offset.x, mask.m_Offset.y] == [0, 0], 'Original MorphMask binding differs')
            output[name] = dict(sourceItemType=3 if bundle == WEAPON else 2,
                sourceBundle=filename, sourceBundleSHA256=expected, sourcePath=path,
                sourcePathID=str(path_id), sourceCAB=reader.assets_file.name,
                sourceObjectBytes=len(object_raw), sourceObjectSHA256=object_sha,
                sourceMorphDefaults=dict(tile=floats['_MorphMaskTile'], edgeSize=floats['_EdgeSize'],
                    edgeStart=colors['_EdgeColorStart'], edgeEnd=colors['_EdgeColorEnd']),
                sourceAlpha=floats['_Alpha'], sourceCutoff=floats['_MorphCutoff'],
                sourceMaskPathID='3396178089779778423')
    require(set(output) == set(MATERIALS), 'Incomplete original D15 materials')
    return output


def source_rules(values, scripts):
    raw = checked(values, LOCK_VALUES_SHA, 256_000)
    data = json.loads(raw)
    require(data[0]['fields'][0] == 'SET_HERALDS_17_STANCE_WIN', 'Source trigger set differs')
    trigger = data[0]['fields'][1][12]['fields']
    require(trigger[3] == [dict(kind='NamedData', id=18,
                value=[dict(kind='Enum', value=65537), 'H17_Win_FX_Start'])] and
            'H17_Stance_Win' in json.dumps(trigger[4]), 'Original final victory event differs')
    actions = trigger[5]
    require([a['id'] for a in actions] == [86, 154, 154] and
            actions[0]['value'] == [dict(kind='Enum', value=65538), True, 140, None, None, None],
            'Original enemy HideModel differs')
    overrides = {}
    for action in actions[1:]:
        target, kind, tile, size, start, end = action['value']
        require(target == dict(kind='Enum', value=65538), 'Morph override is not for the enemy')
        overrides[kind['value']] = dict(tile=tile, edgeSize=size, edgeStart=start, edgeEnd=end)
    require(set(overrides) == {1, 2} and overrides[1] == overrides[2],
            'Weapon must retain original defaults; only Helmet/Armor receive these overrides')
    with ZipFile(scripts) as archive:
        items = zip_member(archive, 'scripts/features/items/entities/items.js', ITEMS_SHA, 4_000_000).decode()
        enums = zip_member(archive, 'scripts/common/enums.js', ENUMS_SHA, 64_000).decode()
    for name, value in [('HELMET', 1), ('ARMOR', 2), ('WEAPON', 3)]:
        require(f'ITEMTYPE[ITEMTYPE["{name}"]={value}]="{name}"' in enums, 'Original item enumeration differs')
    records = []
    for key, item_id, model, kind in [('ARM_AGL_44', 22045, 'arm__agl_44', 'ARMOR'),
                                   ('WPN_IMPERIAL_SPEAR_01_01', 21056, 'wpn__agl_spear_01_01', 'WEAPON')]:
        matches = re.findall(r'\b' + re.escape(key) + r':\{[^{}]*\}', items)
        require(len(matches) == 1, 'Exact item record is ambiguous')
        entry = matches[0]
        require(f'ID:{item_id},' in entry and f'Model:"Top100/{model}"' in entry and
                f'ItemType:ITEMTYPE.{kind}' in entry, 'Original D15 item classification differs')
        records.append(dict(name=key, id=item_id, model='Top100/' + model,
            itemType=2 if kind == 'ARMOR' else 3, recordSHA256=digest(entry.encode())))
    return overrides[2], records


def material_bindings(g, originals, override):
    materials = g['materials']; names = [m.get('name') for m in materials]
    require(len(names) == 5 and len(set(names)) == 5 and set(names) == set(MATERIALS) | PERSONAL,
            'Actual Wu material inventory differs')
    rows = []
    for material in materials:
        name = material['name']; base = name in PERSONAL
        if not base:
            original = originals[name]; extra = material['extras']; defaults = original['sourceMorphDefaults']
            require(extra['sourceMaterial'] == name and
                    extra['sourceFloats']['_MorphMaskTile'] == defaults['tile'] and
                    extra['sourceFloats']['_EdgeSize'] == defaults['edgeSize'] and
                    extra['sourceColors']['_EdgeColorStart'] == defaults['edgeStart'] and
                    extra['sourceColors']['_EdgeColorEnd'] == defaults['edgeEnd'] and
                    extra['sourceTextureBindings']['_MorphMask']['sourcePathID'] == original['sourceMaskPathID'] and
                    original['sourceAlpha'] == original['sourceCutoff'] == 1,
                    'Actual character lost its exact original morph defaults')
        item_type = None if base else originals[name]['sourceItemType']
        parameters = originals[name]['sourceMorphDefaults'] if item_type == 3 else override
        rows.append(dict(name=name, sourceItemType=item_type, actorBaseGeometry=base, **parameters))
    geometry = []
    used = set()
    for mesh in g['meshes']:
        for primitive in mesh['primitives']:
            name = names[primitive['material']]; attributes = primitive['attributes']
            has_uv = 'TEXCOORD_0' in attributes
            require(has_uv or (mesh['name'] == 'Personal_Neck_Bridge' and
                    name == 'Personal_Neck_Bridge_Derived_Skin'), 'Unexpected target geometry without UV')
            require(has_uv == (name != 'Personal_Neck_Bridge_Derived_Skin'), 'Bridge UV contract changed')
            count = g['accessors'][attributes['POSITION']]['count']
            geometry.append(dict(mesh=mesh['name'], material=name, vertices=count, authoredUV=has_uv))
            used.add(name)
    require(used == set(names) and len(geometry) == 9 and
            next(x for x in geometry if x['mesh'] == 'WuYong_Personal_Head')['vertices'] == 59_878 and
            next(x for x in geometry if x['mesh'] == 'Personal_Neck_Bridge')['vertices'] == 226,
            'Actual portrait or bridge inventory changed')
    return rows, geometry


def prepare(args):
    target = json.loads(checked(args.target_profile, args.target_profile_sha256, 48_000_000))
    require(target['id'] == target['hero'] == 'wuyong_erlang' and target['bodyID'] == 'arm__agl_44' and
            target['weaponID'] == 'wpn__agl_spear_01_01' and target['sha256'] == CHARACTER_SHA,
            'Exact reviewed target identity differs')
    model = args.target_profile.parent / (target['resourceName'] + '.glb')
    model_raw = checked(model, CHARACTER_SHA, 48_000_000)
    require(len(model_raw) == target['bytes'], 'Target character size differs')
    g, _ = glb_read(model)
    catalog = json.loads(checked(args.owner_catalog, args.owner_catalog_sha256, 48_000_000))
    owner = next(p for p in catalog['profiles'] if p['id'] == 'sun_triad')
    liu = next(p for p in catalog['profiles'] if p['id'] == 'liu_hammers')
    template = json.loads(checked(args.source_morph, args.source_morph_sha256, 256_000))
    validate_morph_document(template, owner, liu)
    mask = checked(args.source_morph.parent / template['mask']['file'], template['mask']['sha256'], 32_768)
    require(len(mask) == 32_768, 'Original morph texture size differs')
    with ZipFile(args.source_archive) as archive:
        raw = zip_member(archive, 'research/android_bundle_catalog.jsonl', CATALOG_SHA, 10_000_000)
    bundles = {r['file']: r for r in map(json.loads, raw.splitlines())}
    originals = source_materials(args.bundles, bundles)
    override, items = source_rules(args.lock_values, args.decoded_scripts)
    materials, geometry = material_bindings(g, originals, override)
    document = copy.deepcopy(template)
    document.update(targetProfileID=target['id'], targetCharacterSHA256=target['sha256'], materials=materials)
    document['evidence'] = [template['evidence'][i] for i in (0, 1, 2, 4)] + [
        'Exact male D15 ARM_AGL_44(ItemType2) body/tie and WPN_IMPERIAL_SPEAR_01_01(ItemType3) spear material objects were read from their authenticated original bundles. Armor receives t12 overrides; spear retains its own serialized defaults.',
        'All five actual target material names and nine renderers are covered. The 59878-vertex personal head and 226-vertex generated Personal_Neck_Bridge use the explicit actor-base branch; neither is assigned a fictional source equipment type.',
        'The original no-UV bridge stays unmodified. Its constant-color material uses the existing authenticated GPU sample at source mask UV zero; no portrait or bridge UV is invented.',
    ]
    require(not args.output.exists(), 'Refuse to replace a source morph candidate')
    output = private_output(args.output)
    write_new(output / 'SF3_H17_WuMorph.json', encoded(document))
    write_new(output / template['mask']['file'], mask)
    proof = dict(schemaVersion=1, manifest=record(output / 'SF3_H17_WuMorph.json'),
        mask=record(output / template['mask']['file']), ownerProfileID=owner['id'], ownerCharacterSHA256=owner['sha256'],
        targetProfileID=target['id'], targetCharacterSHA256=target['sha256'], targetProfile=record(args.target_profile),
        originalCatalogSHA256=CATALOG_SHA, sourceMaterials=originals,
        sourceItemConfiguration=dict(entry='scripts/features/items/entities/items.js', sha256=ITEMS_SHA,
            enumsSHA256=ENUMS_SHA, records=items), sourceLockValuesSHA256=LOCK_VALUES_SHA,
        sourceArmorOverride=override, materials=materials, actualGeometry=geometry,
        originalGLBModified=False, texturesDecodedAgain=False, nativeMorphObserved=False)
    write_new(output / 'erlang-morph-provenance-private.json', encoded(proof))
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('target-profile', 'owner-catalog', 'source-morph', 'source-archive', 'bundles',
                 'lock-values', 'decoded-scripts', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('target-profile-sha256', 'owner-catalog-sha256', 'source-morph-sha256'):
        parser.add_argument('--' + name, required=True)
    proof = prepare(parser.parse_args())
    print(json.dumps({k: proof[k] for k in ('manifest', 'ownerProfileID', 'targetProfileID',
        'targetCharacterSHA256', 'originalGLBModified', 'texturesDecodedAgain', 'nativeMorphObserved')}))


if __name__ == '__main__':
    main()
