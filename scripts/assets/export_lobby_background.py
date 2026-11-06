#!/usr/bin/env python3
"""Export a private source background with complete offscreen blend proofs.

The caller supplies the exact App viewport. This is a runtime conversion, not
visual acceptance against the original client. Unknown visible blends fail.
"""
import argparse
import bisect
import json
import math
from pathlib import Path

from export_source_interface import export
from source_flash import SourceFlash, require


IDENTITY = (1, 0, 0, 1, 0, 0)


def append(a, b):
    return (a[0]*b[0]+a[1]*b[2], a[0]*b[1]+a[1]*b[3],
            a[2]*b[0]+a[3]*b[2], a[2]*b[1]+a[3]*b[3],
            a[0]*b[4]+a[1]*b[5]+a[4], a[2]*b[4]+a[3]*b[5]+a[5])


def certify_background(scene, name, source_rect, canvas_size):
    """Retain every source object; exclude only proven offscreen blend 64 nodes."""
    require(len(source_rect) == 4 and all(math.isfinite(v) and abs(v) <= 1e6 for v in source_rect)
            and 0 < source_rect[2]-source_rect[0] <= 8192
            and 0 < source_rect[3]-source_rect[1] <= 8192, 'Invalid viewport')
    require(len(canvas_size) == 2 and all(isinstance(v, int) and 1 <= v <= 4096 for v in canvas_size),
            'Invalid canvas size')
    require(name in scene['exports'] and not scene['exclusions'], 'Unexpected export or existing exclusions')
    objects = scene['objects']
    ends = {}
    for key, item in objects.items():
        require('textField' not in item, 'Background requires an explicit text binding')
        if 'frameCount' in item:
            total = 0; values = []
            for group in item['frames']:
                require(group['repeat'] > 0, 'Invalid frame repetition')
                total += group['repeat']; values.append(total)
            require(total == item['frameCount'] and total > 0, 'Frame count mismatch')
            ends[key] = values

    def elements(key, frame):
        item = objects[key]
        if 'frameCount' not in item:
            return []
        return item['frames'][bisect.bisect_right(ends[key], frame % item['frameCount'])]['elements']

    def matrix(index):
        return IDENTITY if index == -1 else scene['matrices'][index]

    def period(key, stack=frozenset()):
        require(key not in stack and len(stack) < 48 and key in objects, 'Missing/cyclic proof object')
        item = objects[key]; result = 1
        if 'frameCount' in item:
            require(item['fps'] == 60, 'Proof requires exact 60 FPS descendant clocks')
            result = item['frameCount']
        for child in item.get('children', []):
            result = math.lcm(result, period(str(child['objectID']), stack | {key}))
            require(result <= 36000, 'Complete clock period exceeds proof budget')
        return result

    def bounds(key, transform, frame):
        item = objects[key]; points = []
        a,b,c,d,tx,ty = transform
        for command in item['commands']:
            points += [(a*v[0]+b*v[1]+tx, c*v[0]+d*v[1]+ty) for v in command['vertices']]
        boxes = []
        if points:
            boxes.append((min(p[0] for p in points), min(p[1] for p in points),
                          max(p[0] for p in points), max(p[1] for p in points)))
        for e in elements(key, frame):
            box = bounds(str(item['children'][e[0]]['objectID']), append(transform, matrix(e[1])), frame)
            if box is not None:
                boxes.append(box)
        return None if not boxes else (min(b[0] for b in boxes), min(b[1] for b in boxes),
                                       max(b[2] for b in boxes), max(b[3] for b in boxes))

    proofs = {}
    reachable_unknown = set()
    def inspect(key, transform, stationary, stack=frozenset()):
        require(key not in stack and len(stack) < 48 and key in objects, 'Missing/cyclic background object')
        item = objects[key]
        stationary = stationary and item.get('frameCount', 1) == 1
        children = item.get('children', [])
        # Visit declared edges as well as frame zero. An unused unknown child
        # cannot be certified just because today's initial frame omits it.
        for index, child in enumerate(children):
            target = str(child['objectID'])
            unsupported = child['blendMode'] not in (0, 3, 4, 8)
            if unsupported:
                reachable_unknown.add((key, index))
                require(child['blendMode'] == 64 and stationary, 'Unsupported visible blend or moving proof ancestor')
            occurrences = [e for e in elements(key, 0) if e[0] == index]
            if unsupported:
                require(occurrences, 'Unknown blend has no certifiable frame-zero instance')
            if not occurrences:
                # Search other states for unknown descendants, without allowing
                # an exclusion under a moving ancestor.
                inspect(target, transform, False, stack | {key})
            for e in occurrences:
                child_transform = append(transform, matrix(e[1]))
                if unsupported:
                    count = period(target)
                    for frame in range(count):
                        box = bounds(target, child_transform, frame)
                        require(box is not None and all(math.isfinite(v) for v in box), 'Empty/invalid proof geometry')
                        require(box[2]+2 <= source_rect[0] or box[0]-2 >= source_rect[2]
                                or box[3]+2 <= source_rect[1] or box[1]-2 >= source_rect[3],
                                'Unknown blend enters viewport during its complete timeline')
                    proof_id = f'offscreen-{key}-{index}'
                    proofs[proof_id] = {'id':proof_id, 'kind':'complete_timeline_outside_viewport',
                        'exportName':name, 'sourceSCSHA256':scene['sourceSCSHA256'], 'parentObjectID':int(key),
                        'childIndex':index, 'objectID':child['objectID'], 'blendMode':64,
                        'sourceRect':list(source_rect), 'margin':2, 'fps':60, 'periodFrames':count}
                inspect(target, child_transform, stationary, stack | {key})

    inspect(str(scene['exports'][name]['objectID']), IDENTITY, True)
    require(len(proofs) == len(reachable_unknown) and len(proofs) <= 128, 'Incomplete proof coverage')
    # Publish only after every occurrence and every descendant clock passes.
    for proof in proofs.values():
        objects[str(proof['parentObjectID'])]['children'][proof['childIndex']]['excludedByProof'] = proof['id']
    scene['sourceRect'] = list(source_rect)
    scene['canvasSize'] = list(canvas_size)
    scene['exclusions'] = list(proofs.values())
    scene['exports'][name]['status'] = 'ready'
    return scene


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--export', dest='export_name', required=True)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--source-rect', nargs=4, type=float, required=True)
    parser.add_argument('--canvas-size', nargs=2, type=int, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    require(not args.output.resolve().is_relative_to(repo), 'Private output must be outside the public checkout')
    require(args.prefix and all(p and not p.startswith('.') for p in args.prefix.split('/'))
            and not any(c in args.prefix for c in '\\:%'), 'Invalid output prefix')
    scene = export(SourceFlash(args.source), [args.export_name], args.output, args.prefix)
    certify_background(scene, args.export_name, args.source_rect, args.canvas_size)
    path = args.output/args.prefix/'scene.json'
    temporary = path.with_suffix('.partial')
    temporary.write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')))
    temporary.replace(path)
    print(json.dumps({'export':args.export_name, 'objects':len(scene['objects']),
                      'atlases':len(scene['textures']), 'complete_timeline_proofs':len(scene['exclusions'])}))


if __name__ == '__main__':
    main()
