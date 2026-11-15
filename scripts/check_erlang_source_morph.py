#!/usr/bin/env python3
"""Read the actual five-material candidate; exercise only new Wu boundaries."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from build_erlang_source_assets import checked
from prepare_erlang_source_morph import CHARACTER_SHA, MATERIALS, material_bindings
from sun_triad_assets import glb_read, require


def check(args):
    document = json.loads(checked(args.manifest, args.manifest_sha256, 256_000))
    proof = json.loads(args.manifest.with_name('erlang-morph-provenance-private.json').read_bytes())
    checked(args.character, CHARACTER_SHA, 48_000_000)
    g, _ = glb_read(args.character)
    materials, geometry = material_bindings(g, proof['sourceMaterials'], proof['sourceArmorOverride'])
    require(materials == document['materials'] and geometry == proof['actualGeometry'] and
            document['targetProfileID'] == 'wuyong_erlang' and document['targetCharacterSHA256'] == CHARACTER_SHA,
            'Actual source/renderer material closure differs')
    require(len(materials) == 5 and len(geometry) == 9 and set(proof['sourceMaterials']) == set(MATERIALS),
            'Actual source material or renderer is missing')
    by_name = {m['name']: m for m in materials}
    weapon = by_name['mat_wpn__agl_spear_01_01_base']
    require(weapon['sourceItemType'] == 3 and not weapon['actorBaseGeometry'] and weapon['tile'] < .11 and
            weapon['edgeStart'][2] > .57 and by_name['mat_arm__agl_44_base']['tile'] == .2,
            'Weapon borrowed the armor override')
    require(all(by_name[n]['sourceItemType'] is None and by_name[n]['actorBaseGeometry']
                for n in ('Material.001', 'Personal_Neck_Bridge_Derived_Skin')),
            'Personal geometry invented an equipment type')
    mask = document['mask']
    checked(args.manifest.parent / mask['file'], mask['sha256'], mask['bytes'])
    print('PASS actual 3 male source material objects / 5 target materials / 9 renderers and untouched mask')

    def rejected(mutator):
        changed = copy.deepcopy(g); mutator(changed)
        try:
            material_bindings(changed, proof['sourceMaterials'], proof['sourceArmorOverride'])
        except (ValueError, AssertionError, RuntimeError):
            return True
        return False

    def wrong_default(changed):
        material = next(m for m in changed['materials'] if m['name'] == 'mat_wpn__agl_spear_01_01_base')
        material['extras']['sourceFloats']['_MorphMaskTile'] = .2
    require(rejected(wrong_default), 'Character with a substituted source weapon default was accepted')
    print('PASS actual weapon default mutation rejected; armor parameters cannot replace original spear parameters')

    def unknown_no_uv(changed):
        primitive = next(m for m in changed['meshes'] if m['name'] == 'WuYong_Personal_Head')['primitives'][0]
        del primitive['attributes']['TEXCOORD_0']
    require(rejected(unknown_no_uv), 'No-UV exception leaked to the original portrait')
    def unknown_material(changed):
        changed['materials'][-1]['name'] = 'Unreviewed_Neck_Skin'
    require(rejected(unknown_material), 'Unknown no-UV material borrowed the bridge exception')
    print('PASS portrait UV omission and an unreviewed neck material are rejected')
    print('3 new actual candidate checks passed; no native, GPU or game execution')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--character', type=Path, required=True)
    check(parser.parse_args())


if __name__ == '__main__':
    main()
