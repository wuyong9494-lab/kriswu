#!/usr/bin/env python3
"""Verify every actual BrawlerLook mapping against its bundled rig and equipment.

This reads the Swift mappings instead of maintaining a second roster. It checks
real clips, animated poses, attachment parents, and resource provenance. It does
not render SceneKit frames or establish on-device animation/visual acceptance.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct

from gltf_contract import unsupported_features
from validate_ranger import sampled, worlds

ROOT = Path(__file__).resolve().parents[2]


def calls(text, name):
    """Read a balanced constructor call, ignoring punctuation inside strings."""
    result = []
    for match in re.finditer(r'\b' + re.escape(name) + r'\(', text):
        start = match.end()
        depth, quoted, escaped = 1, False, False
        for index in range(start, len(text)):
            char = text[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char == '(':
                depth += 1
            elif char == ')':
                depth -= 1
                if depth == 0:
                    result.append(text[start:index])
                    break
        else:
            raise AssertionError(f'Unclosed {name} constructor')
    return result


def load(path):
    raw = path.read_bytes()
    if path.suffix == '.glb':
        assert raw[:4] == b'glTF' and struct.unpack_from('<I', raw, 8)[0] == len(raw)
        count = struct.unpack_from('<I', raw, 12)[0]
        document = json.loads(raw[20:20 + count])
        buffers = [raw[28 + count:]]
    else:
        document = json.loads(raw)
        buffers = [(path.parent / item['uri']).read_bytes() for item in document['buffers']]
    assert not unsupported_features(document), f'Importer contract: {path.name}'

    def accessor(index):
        item = document['accessors'][index]
        view = document['bufferViews'][item['bufferView']]
        widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
        types = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
                 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
        fmt, size = types[item['componentType']]
        width = widths[item['type']]
        stride = view.get('byteStride', width * size)
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        data = buffers[view['buffer']]
        values = [list(struct.unpack_from('<' + fmt * width, data, offset + row * stride))
                  for row in range(item['count'])]
        assert all(math.isfinite(value) for row in values for value in row)
        return values

    for index in range(len(document.get('accessors', []))):
        accessor(index)
    return document, accessor, raw


def audit(source_root=None):
    code = (ROOT / 'App/Views/ArenaModels.swift').read_text()
    body = code.split('static func of(', 1)[1].split('static func baseTint', 1)[0]
    cases = list(re.finditer(r'^        case \.([a-z]+):', body, re.M))
    core = (ROOT / 'Sources/ShiftCore/Arena.swift').read_text()
    enum_body = core.split('public enum Brawler:', 1)[1].split('public var name:', 1)[0]
    roster = set()
    for line in re.findall(r'^    case ([^\n]+)', enum_body, re.M):
        roster.update(part.strip() for part in line.split(','))
    assert {case.group(1) for case in cases} == roster and len(roster) == 13
    recipes = {item['file']: item for item in json.loads(
        (ROOT / 'scripts/assets/vendor_heroes.json').read_text())}
    originals = json.loads((ROOT / 'art/vendor/manifest.json').read_text())
    provenance = {(pack['id'], file['path']): file['sha256']
                  for pack in originals['packs'] for file in pack['files']}
    loaded = {}
    source_fallbacks = set()

    def resource(filename):
        if filename in loaded:
            return loaded[filename]
        path = next((folder / filename for folder in [ROOT / 'App/Arena3D', ROOT / 'App/ArenaVendor']
                     if (folder / filename).is_file()), None)
        if path is None and source_root is not None and filename in recipes:
            recipe = recipes[filename]
            path = source_root / recipe['pack'] / recipe['source']
            assert hashlib.sha256(path.read_bytes()).hexdigest() == provenance[(recipe['pack'], recipe['source'])]
            source_fallbacks.add(filename)
        assert path is not None, f'Missing runtime model {filename}'
        loaded[filename] = load(path)
        return loaded[filename]

    heroes = []
    animation_checks = 0
    for number, case in enumerate(cases):
        end = cases[number + 1].start() if number + 1 < len(cases) else len(body)
        section = body[case.end():end]
        configurations = []
        for expression in calls(section, 'BrawlerLook'):
            filenames = re.findall(r'"([^\"]+\.glb)"', expression.split(', hidden:', 1)[0])
            assert len(filenames) == 1, f'Ambiguous model for {case.group(1)}'
            filename = filenames[0]
            document, accessor, raw = resource(filename)
            nodes = {node.get('name'): index for index, node in enumerate(document['nodes'])}
            if filename == 'Ranger_FaceSample.glb':
                muzzle = worlds(document)[nodes['muzzle']]
                for constant, axis in [('rangerMuzzleHeight', 1), ('rangerMuzzleReach', 2)]:
                    expected = float(re.search(r'static let ' + constant + r': Float = ([0-9.]+)', code).group(1))
                    assert abs(muzzle[axis][3] - expected) < 0.0001, (filename, constant, muzzle[axis][3])
            parents = {child: parent for parent, node in enumerate(document['nodes'])
                       for child in node.get('children', [])}
            hidden_expression = expression.split('hidden: [', 1)[1].split(']', 1)[0]
            hidden = re.findall(r'"([^\"]+)"', hidden_expression)
            assert all(name in nodes for name in hidden), (case.group(1), 'unknown hidden mesh', hidden)
            actions = set(re.findall(r'(?:idle|run|clip): "([^\"]+)"', expression))
            actions.update(['Death_A', 'Cheer', 'Hit_A', '1H_Ranged_Reload'])
            animations = {clip['name']: clip for clip in document.get('animations', [])}
            assert actions <= animations.keys(), (case.group(1), actions - animations.keys())
            checked_clips = {}
            for action in sorted(actions):
                clip = animations[action]
                assert clip['channels'] and clip['samplers']
                duration = max(accessor(sampler['input'])[-1][0] for sampler in clip['samplers'])
                assert duration > 0
                for fraction in (0, 0.2, 0.7, 1):
                    poses = sampled(document, accessor, clip, duration * fraction)
                    assert all(math.isfinite(value) for matrix in poses.values()
                               for row in matrix for value in row)
                checked_clips[action] = duration
                animation_checks += 1
            equipment = []
            for weapon in calls(expression, 'Weapon'):
                file = re.search(r'file: "([^\"]+)"', weapon).group(1)
                bone = re.search(r'bone: "([^\"]+)"', weapon).group(1)
                assert bone in nodes, (case.group(1), 'missing equipment socket', bone)
                held, held_accessor, _ = resource(file)
                assert held.get('meshes'), f'Empty equipment: {file}'
                replacement = re.search(r'replacing: "([^\"]+)"', weapon)
                binding = dict(file=file, bone=bone)
                if replacement:
                    name = replacement.group(1)
                    assert name in nodes and name in hidden
                    assert parents[nodes[name]] == nodes[bone], (file, 'wrong source parent', name, bone)
                    authored = document['nodes'][nodes[name]]
                    assert 'mesh' in authored
                    embedded_positions = [value for primitive in document['meshes'][authored['mesh']]['primitives']
                                          for value in accessor(primitive['attributes']['POSITION'])]
                    replacement_positions = [value for mesh in held['meshes'] for primitive in mesh['primitives']
                                             for value in held_accessor(primitive['attributes']['POSITION'])]
                    embedded_bounds = [[fn(value[axis] for value in embedded_positions) for axis in range(3)]
                                       for fn in (min, max)]
                    replacement_bounds = [[fn(value[axis] for value in replacement_positions) for axis in range(3)]
                                          for fn in (min, max)]
                    bounds_error = max(abs(a - b) for first, second in zip(embedded_bounds, replacement_bounds)
                                       for a, b in zip(first, second))
                    assert bounds_error < 0.0001, (file, 'geometry origin/scale changed', bounds_error)
                    # The reusable asset's root has no extra transform: its geometry
                    # can reuse this exact embedded node's local TRS without offsets.
                    for scene in held.get('scenes', []):
                        for root in scene['nodes']:
                            node = held['nodes'][root]
                            assert node.get('translation', [0, 0, 0]) == [0, 0, 0]
                            assert node.get('rotation', [0, 0, 0, 1]) == [0, 0, 0, 1]
                            assert node.get('scale', [1, 1, 1]) == [1, 1, 1]
                    binding.update(replaces=name, geometryBoundsMaximumDifference=bounds_error, authoredTransform={
                        key: authored[key] for key in ['translation', 'rotation', 'scale', 'matrix'] if key in authored})
                equipment.append(binding)
            configurations.append(dict(file=filename, sha256=hashlib.sha256(raw).hexdigest(),
                                       joints=len(document['skins'][0]['joints']),
                                       clips=checked_clips, hidden=hidden, equipment=equipment))
        assert configurations, f'Unconfigured hero: {case.group(1)}'
        heroes.append(dict(hero=case.group(1), configurations=configurations))
    return dict(heroCount=len(heroes), checkedAnimationBindings=animation_checks,
                sourceFallbacks=sorted(source_fallbacks), heroes=heroes,
                scope='Offline rig/animation/attachment/resource configuration; no rendered or device acceptance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, help='Allow source recipe checking before runtime generation')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = audit(args.source_root)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['heroCount', 'checkedAnimationBindings', 'sourceFallbacks']}))
