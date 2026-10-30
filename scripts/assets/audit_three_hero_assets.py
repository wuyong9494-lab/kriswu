#!/usr/bin/env python3
"""Read-only minimum reuse check, using the existing GLB parser and pose sampler.

Usage: audit_three_hero_assets.py ASSET_DIRECTORY OUTPUT_JSON
This does not render iOS frames, establish upstream byte provenance, or measure FPS.
"""
import hashlib
import json
import pathlib
import sys
from gltf_contract import unsupported_features
from validate_ranger import load, sampled, stats

REQUIRED = {
    'Ranger_FaceSample': ['Ranger_Idle', 'Ranger_Run', 'Ranger_Shoot', 'Ranger_Skill', 'Hit_A', 'Death_A', 'Cheer'],
    'Barbarian': ['2H_Melee_Idle', 'Running_B', '2H_Melee_Attack_Chop', 'Jump_Full_Short', 'Hit_A', 'Death_A', 'Cheer'],
    'Mage': ['Idle', 'Running_A', 'Spellcast_Shoot', 'Spellcast_Long', 'Hit_A', 'Death_A', 'Cheer'],
}


def audit(directory):
    result = {}
    geometry = set()
    for name, actions in REQUIRED.items():
        document, accessor, binary = load(directory / (name + '.glb'))
        errors = unsupported_features(document)
        if errors:
            raise ValueError(f'{name}: unsupported importer features: {errors}')
        # Traverse every accessor, not only the selected animation's values.
        for index in range(len(document['accessors'])):
            accessor(index)
        positions = [accessor(p['attributes']['POSITION'])
                     for mesh in document['meshes'] for p in mesh['primitives']]
        fingerprint = hashlib.sha256(json.dumps(positions, separators=(',', ':')).encode()).hexdigest()
        geometry.add(fingerprint)
        clips = {a['name']: a for a in document['animations']}
        checked = {}
        for action in actions:
            clip = clips[action]
            duration = max(accessor(s['input'])[-1][0] for s in clip['samplers'])
            a, b = (sampled(document, accessor, clip, duration * t) for t in (0.2, 0.7))
            delta = max(abs(a[n][r][c] - b[n][r][c]) for n in a for r in range(4) for c in range(4))
            if duration <= 0 or delta <= 1e-6:
                raise ValueError(f'{name}/{action}: static or empty action')
            checked[action] = dict(duration=duration, channels=len(clip['channels']),
                                   poseMatrixDelta20To70Percent=delta)
        result[name] = dict(stats(document, binary), unsupported=errors, actions=checked,
                            geometrySHA256=fingerprint, meshNames=[m.get('name') for m in document['meshes']])
    if len(geometry) != 3:
        raise ValueError('The three model position streams must be distinct')
    return result


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    output = pathlib.Path(sys.argv[2])
    result = audit(pathlib.Path(sys.argv[1]))
    output.write_text(json.dumps(result, indent=2) + '\n')
    print('3 distinct models; 21 required moving actions; no importer-contract violations')
