#!/usr/bin/env python3
"""Build/check the shipped configuration inventory from actual production code.

No gameplay is simulated here. The inventory pins every current hero, released
map, effect profile, UI selection and soundtrack so archive verification cannot
mistake an old 28-file subset for the completed configuration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from audit_hero_configuration import audit, calls

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'App/ArenaVendor/arena-asset-configuration.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    vendor_file = ROOT / 'App/ArenaVendor/arena-vendor-runtime.json'
    vendor = json.loads(vendor_file.read_text())
    names = {item['file'] for item in vendor['files']}
    source = json.loads((ROOT / 'art/vendor/manifest.json').read_text())
    heroes = audit()
    assert not heroes['sourceFallbacks'], 'Hero configuration must resolve shipped files'
    roster = {item['hero'] for item in heroes['heroes']}
    assert len(roster) == 13

    map_code = (ROOT / 'Sources/ShiftCore/ArenaMaps.swift').read_text()
    originals = re.search(r'public static let all: \[ArenaMap\] = \[(.*?)\]', map_code, re.S)[1]
    original_ids = re.findall(r'\b[a-zA-Z]+\b', originals)
    expanded = re.search(r'public static let expandedMaps: \[ArenaMap\] = \[(.*?)\]', map_code, re.S)[1]
    expanded_ids = [item + '_expanded_v2' for item in re.findall(r'\b[a-zA-Z]+\b', expanded)]
    twin = re.search(r'ArenaMap\(id: "([^"]+)"', (ROOT / 'Sources/ShiftCore/ArenaSampleMap.swift').read_text())[1]
    map_ids = original_ids + expanded_ids + [twin]
    palette_code = (ROOT / 'App/Views/ArenaMapAssets.swift').read_text()
    palette_ids = re.findall(r'^        "([^"]+)": make\(', palette_code, re.M)
    assert set(palette_ids) == set(original_ids + [twin])
    assert len(map_ids) == len(set(map_ids)) == 22
    map_resources = sorted(set(re.findall(r'"(vendor_[^"\n]+\.glb)"', palette_code)))
    assert set(map_resources) <= names

    effect_code = (ROOT / 'App/Views/ArenaEffectAssets.swift').read_text()
    effects = []
    for hero, attack, special, trail in re.findall(
            r'case \.([a-z]+): return Profile\(attack: \.([a-z]+), special: \.([a-z]+), trail: \.([a-z]+)\)', effect_code):
        effects.append(dict(hero=hero, attack=attack, special=special, trail=trail))
    assert {item['hero'] for item in effects} == roster
    styles = set()
    for item in effects:
        styles.update([item['attack'], item['special'], item['trail']])
    for style in styles:
        file = f'vendor_{style}_01.png' if style in ('spark', 'smoke') else f'vendor_effect_{style}.png'
        assert file in names, f'Missing assigned effect: {file}'
    gadget_code = (ROOT / 'Sources/ShiftCore/ArenaSkills.swift').read_text()
    gadget_body = gadget_code.split('public enum Gadget:', 1)[1].split('public var name:', 1)[0]
    gadgets = set()
    for line in re.findall(r'^    case ([^\n]+)', gadget_body, re.M):
        gadgets.update(part.strip() for part in line.split(','))
    assigned_gadgets = set(re.findall(r'\.([a-z]+)\?', effect_code))
    assert gadgets == assigned_gadgets and len(gadgets) == 9

    icon_manifest = json.loads((ROOT / 'art/lobby/icons/manifest.json').read_text())
    lobby_code = (ROOT / 'App/Views/ArenaLobbyArt.swift').read_text()
    icons = [item['asset'] for item in icon_manifest['icons']]
    assert len(icons) == 11 and all(f'"{name}"' in lobby_code for name in icons)
    for name in icons:
        contents = json.loads((ROOT / f'App/Assets.xcassets/{name}.imageset/Contents.json').read_text())
        for item in contents['images']:
            if item.get('filename'):
                assert (ROOT / f'App/Assets.xcassets/{name}.imageset' / item['filename']).is_file()

    themes = []
    for stage in ('lobby', 'battle', 'win', 'lose'):
        path = ROOT / f'App/ArenaSounds/arena_theme_{stage}.m4a'
        themes.append(dict(stage=stage, file=path.name, sha256=sha(path), bytes=path.stat().st_size))
    canonical = ROOT / 'App/Arena3D/Ranger_FaceSample.glb'
    config_code = ['App/Views/ArenaModels.swift', 'App/Views/ArenaAvatar.swift',
                   'App/Views/ArenaMapAssets.swift', 'App/Views/ArenaEffectAssets.swift',
                   'App/Views/ArenaInterfaceAssets.swift', 'App/Services/ArenaSound.swift',
                   'App/Services/ArenaEffectMixer.swift']
    return dict(schemaVersion=1,
                scope='Complete assignments for the existing 13 heroes, 22 maps, 9 gadgets, interface and four music stages; alternate source formats remain archived',
                sourcePackCount=source['packCount'], sourceFileCount=source['fileCount'],
                vendorRuntimeFileCount=len(names), vendorRuntimeBytes=sum(item['bytes'] for item in vendor['files']),
                vendorManifestSHA256=sha(vendor_file),
                canonicalRanger=dict(file=canonical.name, sha256=sha(canonical)),
                heroes=heroes['heroes'], checkedAnimationBindings=heroes['checkedAnimationBindings'],
                mapIDs=map_ids, mapPaletteIDs=palette_ids, mapResources=map_resources,
                mapBudgets=dict(importedWallInstances=24, borderInstances=10, interiorDetailInstances=16),
                effectProfiles=effects, gadgetEffects=sorted(gadgets),
                interfaceImages=sorted(item['file'] for item in vendor['files'] if item['usage'].startswith(('ui.', 'menu.', 'lobby.')) and item['file'].endswith('.png')),
                existingLobbyIcons=icons, themeMusic=themes,
                audioFiles=sorted(item['file'] for item in vendor['files'] if item['file'].endswith('.wav')),
                configurationSources={path: sha(ROOT / path) for path in config_code},
                fullGameplayValidation='deferred at owner request')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = build()
    data = (json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()
    if args.check:
        assert OUTPUT.read_bytes() == data, 'Shipped asset configuration is stale; regenerate it'
    else:
        OUTPUT.write_bytes(data)
    print(json.dumps(dict(heroes=len(result['heroes']), maps=len(result['mapIDs']),
                         gadgets=len(result['gadgetEffects']), effects=len(result['effectProfiles']),
                         themeMusic=len(result['themeMusic']), runtimeFiles=result['vendorRuntimeFileCount'],
                         sha256=hashlib.sha256(data).hexdigest())))


if __name__ == '__main__':
    main()
