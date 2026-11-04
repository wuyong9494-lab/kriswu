#!/usr/bin/env python3
"""Audit complete Probe7 artifacts, then score status text strictly offline.

All paths and run identities are explicit/overridable. No OCR, image processing,
repository writes, record deduplication, vocabulary injection, or transcript repair.
Truth is not opened unless source, execution, image and result integrity all pass.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

HERE = Path(__file__).resolve().parent
ROWS = (1, 4, 7, 10, 13, 16, 19, 22)
PAIRS = ((1, 4), (7, 10), (13, 16), (19, 22))
SCALES, MODES = (1, 3), ('min10', 'min0')
IMAGE_IDS = {f'row-{r}-headerCapped-{s}x': (r, s) for r in ROWS for s in SCALES}
REQUEST_IDS = {f'{i}-{m}': (i, r, s, m) for i, (r, s) in IMAGE_IDS.items() for m in MODES}
METHODS = {f'testCells{a:02d}And{b:02d}': (a, b) for a, b in PAIRS}
PHOTO_SHA = 'd6c7d3c30672244ae5b8713061d3cb7d4fff4996f27e193c58eabb128434ffba'
GEOMETRY_SHA = 'd2107acbde65dc3a0446debea2097efd836c53c13608929d1f79b8d783254a37'
BASELINE_SHA = '6607596938a46be6b8167d89c64c2ce053222ec01f6e5fedf00c8c0bc71f78d3'
GENERATOR_SHA = '4ba4337f6a0904d2b7f853b629f8c5a5b5839a433abea260f4e62be66ab8783f'
PHOTO_SOURCE = 'f2fd46fee3295cc4cb06b930ea2e74b047d7c753'
PROBE_BASE = 'cbfa12a2bad062fbe209b410605bee0d97156974'
BASELINE_RUNTIME = '02f088526a38ca5602c90fa0dec9db73b4cc7b8c'
AUTO_POLICY = 'unchanged API default, matching Probe6 configuration'
REQUEST_KINDS = {'requestStart', 'requestEnd', 'requestError', 'observation', 'candidate',
                 'characterBounds', 'characterBoundsEnd'}
KINDS = REQUEST_KINDS | {'methodStart', 'methodEnd', 'attachmentsSaved', 'baseCrop', 'prepared'}
METHOD_RE = re.compile(r"Test Case '(.*?)' (started|passed|failed)(?: \(([\d.]+) seconds\))?")
NAME_RE = re.compile(r'PlanReaderStatusProbe7Tests[ .]+(test\w+)\]?')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def json_loads(text):
    return json.loads(text, parse_constant=lambda s: (_ for _ in ()).throw(ValueError(f'Nonfinite JSON: {s}')))


def read_json(path):
    return json_loads(Path(path).read_bytes().decode('utf-8'))


def finite(v):
    return type(v) in (int, float) and math.isfinite(v)


def valid_box(v):
    return isinstance(v, list) and len(v) == 4 and all(map(finite, v)) and v[2] >= 0 and v[3] >= 0


def close(a, b, tolerance=1e-7):
    if isinstance(b, dict):
        return isinstance(a, dict) and set(a) == set(b) and all(close(a[k], v, tolerance) for k, v in b.items())
    if isinstance(b, (list, tuple)):
        return isinstance(a, (list, tuple)) and len(a) == len(b) and all(close(x, y, tolerance) for x, y in zip(a, b))
    if type(b) in (int, float):
        return finite(a) and abs(a - b) <= tolerance
    return type(a) is type(b) and a == b


def of(records, kind):
    return [r for r in records if r['value'].get('kind') == kind]


class Audit:
    def __init__(self):
        self.errors, self.warnings = [], []

    def check(self, ok, scope, message):
        if not ok:
            self.errors.append({'scope': scope, 'message': message})
        return bool(ok)

    def fields(self, value, expected, scope, tolerance=0):
        for key, target in expected.items():
            self.check(close(value.get(key), target, tolerance), scope, f'Unexpected {key}')

    def one(self, records, kind, scope):
        found = of(records, kind)
        self.check(len(found) == 1, scope, f'Expected one {kind}; found {len(found)}')
        return found[0] if len(found) == 1 else None


def read_events(log, audit):
    events, tests = [], []
    lines = log.read_bytes().decode('utf-8').splitlines()
    for number, line in enumerate(lines, 1):
        match = METHOD_RE.search(line)
        if match:
            full, event, seconds = match.groups(); name = NAME_RE.search(full)
            audit.check(name is not None, f'line:{number}', f'Unexpected XCTest case: {full}')
            tests.append({'line': number, 'name': name[1] if name else full, 'event': event,
                          'seconds': float(seconds) if seconds else None})
        if 'OCRPROBE7|' not in line:
            continue
        try:
            value = json_loads(line.split('OCRPROBE7|', 1)[1])
            if not isinstance(value, dict):
                raise ValueError('Native record is not an object')
            audit.check(value.get('kind') in KINDS, f'line:{number}', 'Unknown record kind')
            events.append({'line': number, 'value': value})
        except ValueError as e:
            audit.check(False, f'line:{number}', str(e))
    audit.check(bool(events), 'log', 'No OCRPROBE7 records')
    audit.check(sum(line.strip() == '** TEST SUCCEEDED **' for line in lines) == 1, 'log',
                'Expected one native success sentinel; canonical artifact only, no workflow replay')
    audit.check(not any('** TEST FAILED **' in line for line in lines), 'log', 'Native failure sentinel present')
    for name in METHODS:
        group = [r for r in tests if r['name'] == name]
        audit.check([r['event'] for r in group] == ['started', 'passed'], name,
                    'XCTest must start/pass exactly once; no silent deduplication')
    audit.check(all(r['name'] in METHODS for r in tests), 'methods', 'Unexpected test method')
    return events, tests


def provenance(args, source, run, job_document, audit):
    audit.fields(source, {'schemaVersion': 1, 'scope': 'independent-diagnostic', 'probe': 7,
        'probeBaseCommit': PROBE_BASE, 'workflowSHA': args.workflow_commit,
        'triggerSHA': args.expected_commit, 'expectedSourceSHA': args.expected_commit,
        'testedSourceSHA': args.expected_commit, 'embeddedBuildIdentitySHA': args.expected_commit,
        'testedSourceTree': args.expected_tree, 'testTarget': 'SiteTests/PlanReaderStatusProbe7Tests',
        'expectedTestMethods': 4, 'expectedOCRRequests': 32, 'expectedPreparedImages': 16,
        'fixtures': ['status_probe_web_photo'], 'fixtureSHA256': PHOTO_SHA,
        'geometrySHA256': GEOMETRY_SHA, 'rows': list(ROWS), 'geometry': 'headerCapped',
        'scales': list(SCALES), 'minimumHeightModes': list(MODES), 'requestRevision': 3}, 'sourceManifest')
    audit.check(str(source.get('runID')) == str(args.run_id) and str(source.get('runAttempt')) == str(args.attempt),
                'sourceManifest', 'Run/attempt mismatch')
    audit.fields(run, {'id': args.run_id, 'head_sha': args.expected_commit, 'run_attempt': args.attempt,
                      'status': 'completed', 'conclusion': 'success'}, 'runMetadata')
    jobs = job_document.get('jobs', [job_document])
    matches = [j for j in jobs if j.get('id') == args.job_id]
    audit.check(len(matches) == 1, 'jobMetadata', 'Expected one matching current-attempt job')
    job = matches[0] if len(matches) == 1 else {}
    audit.fields(job, {'id': args.job_id, 'run_id': args.run_id, 'run_attempt': args.attempt,
                      'head_sha': args.expected_commit, 'status': 'completed', 'conclusion': 'success'}, 'jobMetadata')
    return job


def methods_and_order(events, tests, commit, geometry, audit):
    methods, active, request = [], None, None
    for r in events:
        v = r['value']; kind = v.get('kind')
        if kind == 'methodStart':
            audit.check(active is None, 'methods', 'Overlapping methods')
            active = {'start': r, 'records': []}; methods.append(active)
        if kind != 'attachmentsSaved':
            audit.check(active is not None, f'line:{r["line"]}', 'Record outside method')
            if active:
                active['records'].append(r)
        if kind == 'requestStart':
            audit.check(request is None, 'requests', 'Overlapping OCR requests'); request = v.get('requestID')
        elif kind == 'requestEnd':
            audit.check(request == v.get('requestID'), 'requests', 'Mismatched request end'); request = None
        elif kind in ('baseCrop', 'prepared', 'methodEnd', 'attachmentsSaved'):
            audit.check(request is None, f'line:{r["line"]}', 'Image/method boundary during active OCR request')
        elif kind in REQUEST_KINDS:
            audit.check(request == v.get('requestID'), f'line:{r["line"]}', 'Result outside its active request')
        if kind == 'methodEnd':
            if active:
                active['end'] = r
            active = None
    audit.check(active is None and request is None, 'methods', 'Unclosed method/request')
    audit.check(len(methods) == 4 and Counter(tuple(m['start']['value'].get('rows', [])) for m in methods) == Counter(PAIRS),
                'methods', 'Expected exactly four fixed row pairs')
    attachments = of(events, 'attachmentsSaved')
    audit.check(len(attachments) == 4 and Counter(tuple(r['value'].get('rows', [])) for r in attachments) == Counter(PAIRS),
                'attachments', 'Expected four unique fixed attachment groups')
    result = []
    for m in methods:
        start = m['start']; value = start['value']; rows = value.get('rows', []); scope = f'method:{rows}'
        audit.fields(value, {'scope': 'independent-diagnostic', 'fixture': 'status_probe_web_photo',
            'sourceSHA256': PHOTO_SHA, 'photoSourceCommit': PHOTO_SOURCE,
            'photoSourcePath': 'Tests/SiteTests/OCRSamples/web_photo.jpg', 'probeBaseCommit': PROBE_BASE,
            'runtimeCommit': commit, 'geometrySHA256': GEOMETRY_SHA, 'geometryProvenance': geometry['recording'],
            'geometry': 'headerCapped', 'scales': list(SCALES), 'photoSize': [4032, 3024],
            'minimumHeightModes': list(MODES), 'expectedRequests': 8, 'expectedPrepared': 4,
            'totalProbeRequests': 32, 'totalPrepared': 16, 'requestRevision': 3, 'allowanceSeconds': 180}, scope)
        audit.check(isinstance(value.get('supportedRevisions'), list) and 3 in value['supportedRevisions'], scope, 'Revision 3 unsupported')
        audit.check(isinstance(value.get('os'), str) and bool(value['os']), scope, 'Runtime OS missing')
        images = {i for i, (row, _) in IMAGE_IDS.items() if row in rows}
        requests = {i for i, (_, row, _, _) in REQUEST_IDS.items() if row in rows}
        audit.check(Counter(r['value'].get('imageID') for r in of(m['records'], 'prepared')) == Counter(images), scope, 'Image selection/count mismatch')
        audit.check(Counter(r['value'].get('requestID') for r in of(m['records'], 'requestStart')) == Counter(requests), scope, 'Request selection/count mismatch')
        audit.check(Counter(r['value'].get('row') for r in of(m['records'], 'baseCrop')) == Counter(rows), scope, 'Base row selection mismatch')
        end = m.get('end'); audit.check(end is not None, scope, 'Missing methodEnd')
        if end:
            audit.fields(end['value'], {'rows': rows, 'requests': 8, 'prepared': 4,
                         'imageIDs': sorted(images), 'requestIDs': sorted(requests)}, scope)
        found = [r for r in attachments if r['value'].get('rows') == rows]
        if len(found) == 1:
            r = found[0]; audit.check(r['value'].get('count') == 4, scope, 'Attachment count mismatch')
            audit.check(Counter(r['value'].get('imageIDs', [])) == Counter(images), scope, 'Attachment IDs mismatch')
            audit.check(Counter(r['value'].get('pngNames', [])) == Counter(f'probe7-{i}.png' for i in images), scope, 'Attachment names mismatch')
            if end:
                audit.check(r['line'] > end['line'], scope, 'Attachment record precedes methodEnd')
            name = next((n for n, pair in METHODS.items() if list(pair) == rows), None)
            bounds = [t for t in tests if t['name'] == name]
            if len(bounds) == 2:
                audit.check(bounds[0]['line'] < start['line'] < r['line'] < bounds[1]['line'], scope, 'Records outside XCTest boundaries')
        result.append({'start': start, 'end': end, 'rows': rows})
    return result


def images_and_pngs(args, events, geometry, baseline, proof, audit):
    geometry_rows = {r['row']: r for r in geometry['rows']}
    bases, images = {}, {}
    audit.check(Counter(r['value'].get('row') for r in of(events, 'baseCrop')) == Counter(ROWS), 'crops', 'Expected eight unique B base crops')
    audit.check(Counter(r['value'].get('imageID') for r in of(events, 'prepared')) == Counter(IMAGE_IDS.keys()), 'images', 'Expected 16 unique prepared images')
    proof_error_start = len(audit.errors)
    audit.fields(proof, {'log_sha256': sha(args.log), 'expected_attachments': 16, 'verified_attachments': 16,
                        'missing': [], 'object_errors': [], 'duplicate_log_attachment_records': 0}, 'PNG extraction report')
    audit.check(proof.get('extractor_sha256') == sha(args.extractor), 'PNG extraction report', 'Extractor source digest mismatch')
    attachments = proof.get('attachments', [])
    audit.check(Counter(r.get('imageID') for r in attachments) == Counter(IMAGE_IDS.keys()), 'PNG extraction report', 'Expected 16 unique proof imageIDs')
    expected_names = {f'probe7-{i}.png' for i in IMAGE_IDS}
    audit.check({p.name for p in args.png_dir.glob('probe7-*.png')} == expected_names, 'PNG directory', 'Named PNG set mismatch')
    proof_integrity_ok = len(audit.errors) == proof_error_start
    for row in ROWS:
        r = audit.one([r for r in of(events, 'baseCrop') if r['value'].get('row') == row], 'baseCrop', f'row:{row}')
        if not r:
            continue
        expected = geometry_rows[row]['crops']['headerCapped']; old = baseline[f'row-{row}-headerCapped-1x']['baseCrop']
        audit.fields(r['value'], {'geometry': 'headerCapped', 'cellRegion': expected['region'],
            'sourceCorners': expected['cornersTopLeft'], 'sourceCoordinates': 'source-pixels-top-left',
            'sourceCornerOrder': ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'],
            'rectifiedExtentCoordinates': 'CoreImage-pixels-bottom-left', 'colorManagement': 'CoreImage-default',
            'baseCropSize': old['baseCropSize'], 'rectifiedExtent': old['rectifiedExtent']}, f'row:{row}', 1e-7)
        audit.check(close(r['value'].get('cellRegion'), expected['region'], 1e-12), f'row:{row}', 'Normalized crop region differs')
        bases[row] = r
    for image_id, (row, scale) in IMAGE_IDS.items():
        before = len(audit.errors)
        r = audit.one([r for r in of(events, 'prepared') if r['value'].get('imageID') == image_id], 'prepared', image_id)
        old, base = baseline[image_id], bases.get(row)
        if not r:
            images[image_id] = {'imageID': image_id, 'complete': False}; continue
        value = r['value']
        audit.fields(value, {'row': row, 'geometry': 'headerCapped', 'scale': scale,
            'baseCropSize': old['baseCrop']['baseCropSize'], 'size': old['size'],
            'pixelHashScope': 'CGImage-dataProvider-bytes', 'pngName': f'probe7-{image_id}.png',
            'requestIDs': [f'{image_id}-{m}' for m in MODES]}, image_id)
        for key in ('pngSHA256', 'pixelSHA256'):
            audit.check(isinstance(value.get(key), str) and re.fullmatch('[0-9a-f]{64}', value[key]) is not None, image_id, f'Invalid {key}')
        for key in ('bitsPerComponent', 'bitsPerPixel', 'bytesPerRow', 'alphaInfo', 'bitmapInfo'):
            audit.check(type(value.get(key)) is int and value[key] >= 0, image_id, f'Invalid {key}')
        audit.check(value.get('colorSpaceName') is None or isinstance(value.get('colorSpaceName'), str), image_id, 'Invalid color-space name')
        audit.check(value.get('colorSpaceModel') is None or type(value.get('colorSpaceModel')) is int, image_id, 'Invalid color-space model')
        audit.check('colorSpaceName' in value and 'colorSpaceModel' in value, image_id, 'Color-space metadata missing')
        if base:
            audit.check(base['line'] < r['line'], image_id, 'Prepared image precedes base crop')
            audit.check(value.get('size') == [n * scale for n in base['value']['baseCropSize']], image_id, 'Scale size mismatch')
        audit.check(value.get('pngSHA256') == old['pngSHA256'] and value.get('pngBytes') == old['pngBytes'], image_id, 'PNG hash/bytes differ from Probe6 B baseline')
        if value.get('pixelSHA256') != old['pixelSHA256']:
            audit.warnings.append({'scope': image_id, 'message': 'CG provider hash differs; it includes layout/padding. PNG equality is audited separately.'})
        found = [x for x in attachments if x.get('imageID') == image_id]
        audit.check(len(found) == 1, image_id, 'Expected exactly one CRC proof entry')
        actual, proof_entry = None, found[0] if len(found) == 1 else None
        if proof_entry:
            audit.fields(proof_entry, {'pngName': f'probe7-{image_id}.png', 'row': row, 'geometry': 'headerCapped', 'scale': scale,
                'baseCropSize': old['baseCrop']['baseCropSize'], 'size': old['size'], 'width': old['size'][0], 'height': old['size'][1],
                'sha256': value.get('pngSHA256'), 'bytes': value.get('pngBytes'), 'allCRCVerified': True,
                'sha256_verified': True, 'reencoded': False}, image_id)
            audit.check(type(proof_entry.get('crc_validated_chunks')) is int and proof_entry['crc_validated_chunks'] >= 3, image_id, 'Missing verified chunk count')
        path = args.png_dir / f'probe7-{image_id}.png'
        try:
            data = path.read_bytes(); digest = hashlib.sha256(data).hexdigest()
            is_png = len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR'
            size = list(struct.unpack('>II', data[16:24])) if is_png else None
            audit.check(is_png and size == old['size'], image_id, 'Actual PNG signature/IHDR differs')
            audit.check(digest == old['pngSHA256'] == value.get('pngSHA256'), image_id, 'Actual PNG bytes differ from baseline/native log')
            audit.check(len(data) == old['pngBytes'] == value.get('pngBytes'), image_id, 'Actual PNG length differs')
            if proof_entry:
                audit.check(digest == proof_entry.get('sha256') and len(data) == proof_entry.get('bytes'), image_id, 'Actual bytes differ from CRC proof')
                # Original absolute paths are provenance, not a portability constraint.
                # The original bytes, digest, length, dimensions and file name bind
                # a relocated PNG to the CRC-verified attachment without reencoding.
                audit.check(Path(proof_entry.get('output', '')).name == path.name, image_id, 'CRC proof output file name differs')
            actual = {'path': str(path), 'sha256': digest, 'bytes': len(data), 'IHDRSize': size,
                      'rawBytesIndependentlyRehashed': True, 'CRCProofEntry': proof_entry,
                      'CRCProofOriginalOutputPath': proof_entry.get('output') if proof_entry else None}
        except OSError as error:
            audit.check(False, image_id, str(error))
        images[image_id] = {'imageID': image_id, 'row': row, 'scale': scale, 'complete': True,
            'localIntegrityOK': len(audit.errors) == before, 'errors': audit.errors[before:], 'prepared': r,
            'independentPNGVerified': proof_integrity_ok and len(audit.errors) == before and actual is not None,
            'baseCrop': base, 'actualPNG': actual, 'probe6PNGHash': old['pngSHA256'],
            'sameProviderHashAsProbe6': value.get('pixelSHA256') == old['pixelSHA256'],
            'probe6Candidates': old['baselineCandidates']}
    return bases, images


def pixel_box(box, size, scale=1):
    if not valid_box(box):
        return None
    x, y, width, height = box
    return [x * size[0] / scale, (1 - y - height) * size[1] / scale,
            width * size[0] / scale, height * size[1] / scale]


def character_bounds(records, top, index, size, scope, audit):
    chars = [r for r in of(records, 'characterBounds') if r['value'].get('observation') == index]
    ends = [r for r in of(records, 'characterBoundsEnd') if r['value'].get('observation') == index]
    if top is None:
        audit.check(not chars and not ends, scope, 'Character bounds without rank-1 candidate')
    else:
        audit.check(len(ends) == 1, scope, 'Expected one characterBoundsEnd')
        audit.check([r['value'].get('characterIndex') for r in chars] == list(range(len(chars))), scope, 'Character indices differ')
    groups = defaultdict(list)
    for r in chars:
        v = r['value']; audit.fields(v, {'rank': 1, 'unit': 'Swift-Character', 'coordinates': 'prepared-normalized-bottom-left'}, scope)
        audit.check(isinstance(v.get('raw'), str) and bool(v['raw']), scope, 'Empty/invalid native Character')
        audit.check(v.get('result') in ('returned', 'missing', 'error'), scope, 'Unknown character bounds result')
        audit.check('box' in v and (v['box'] is None or valid_box(v['box'])), scope, 'Invalid character rectangle')
        if v.get('result') in ('missing', 'error'):
            audit.check(v.get('box') is None, scope, 'Missing/error box must remain null')
        if v.get('result') == 'error':
            audit.check(isinstance(v.get('error'), str), scope, 'Missing bounds error text')
        if valid_box(v.get('box')):
            groups[tuple(v['box'])].append({'characterIndex': v.get('characterIndex'), 'raw': v.get('raw')})
        if top:
            audit.check(r['line'] > top['line'], scope, 'Character bounds precede top candidate')
    if top and len(ends) == 1:
        end = ends[0]['value']; count = end.get('characters')
        audit.fields(end, {'rank': 1, 'limit': 64}, scope)
        audit.check(type(count) is int and count >= 0, scope, 'Invalid native Character count')
        if type(count) is int and count >= 0:
            audit.check(end.get('logged') == min(count, 64) == len(chars) and end.get('truncated') == (count > 64), scope, 'Character count/truncation mismatch')
        units = [r['value'].get('raw') for r in chars]; text = top['value'].get('raw')
        if isinstance(text, str) and all(isinstance(u, str) for u in units):
            joined = ''.join(units)
            audit.check(text.startswith(joined) if end.get('truncated') else text == joined, scope, 'Characters do not reconstruct raw candidate')
        audit.check(ends[0]['line'] > max([top['line'], *[r['line'] for r in chars]]), scope, 'Character end order mismatch')
    return {'records': chars, 'endRecords': ends, 'loggedCharacters': len(chars),
        'nullBoxes': sum(r['value'].get('box') is None for r in chars),
        'sharedBoxGroups': [{'box': list(b), 'characters': c} for b, c in groups.items() if len(c) > 1],
        'preparedPixelsTopLeft': [{'characterIndex': r['value'].get('characterIndex'), 'raw': r['value'].get('raw'),
            'result': r['value'].get('result'), 'box': pixel_box(r['value'].get('box'), size)} for r in chars],
        'policy': 'Preserve returned/shared/nil/error rectangles; no inferred segmentation'}


def requests_and_results(events, images, baseline, audit):
    groups = defaultdict(list)
    for r in events:
        v = r['value']
        if v.get('kind') in REQUEST_KINDS:
            groups[v.get('requestID')].append(r)
        else:
            audit.check('requestID' not in v, f'line:{r["line"]}', 'Unexpected requestID on non-request event')
    audit.check(set(groups) == set(REQUEST_IDS), 'requests', 'Expected exactly 32 fixed request IDs')
    result = []
    for request_id, (image_id, row, scale, mode) in REQUEST_IDS.items():
        before = len(audit.errors); records = groups[request_id]; image = images[image_id]
        start = audit.one(records, 'requestStart', request_id); end = audit.one(records, 'requestEnd', request_id)
        prepared = image.get('prepared'); expected_size = baseline[image_id]['size']
        obs, candidates = of(records, 'observation'), of(records, 'candidate')
        audit.check(not of(records, 'requestError'), request_id, 'Native OCR requestError')
        for r in records:
            audit.check(r['value'].get('imageID') == image_id, request_id, 'Result imageID differs')
        if start:
            v = start['value']; base_size = baseline[image_id]['baseCrop']['baseCropSize']
            minimum = struct.unpack('f', struct.pack('f', 10 / base_size[1]))[0] if mode == 'min10' else 0.0
            audit.fields(v, {'row': row, 'geometry': 'headerCapped', 'scale': scale, 'minimumHeightMode': mode,
                'level': 'accurate', 'languages': ['zh-Hans', 'en-US'], 'automaticLanguagePolicy': AUTO_POLICY,
                'languageCorrection': False, 'customWords': [], 'requestRevision': 3, 'orientation': 'up',
                'topCandidates': 3, 'baseCropSize': base_size, 'size': expected_size,
                'configuredMinHeight': minimum, 'normalizedMinHeight': minimum}, request_id)
            audit.check(type(v.get('automaticallyDetectsLanguage')) is bool, request_id, 'Missing actual automatic-language getter')
            audit.check(isinstance(v.get('supportedLanguages'), list) and all(l in v['supportedLanguages'] for l in ['zh-Hans', 'en-US']), request_id, 'Requested languages unsupported')
            audit.check(close(v.get('effectiveMinPixels'), minimum * expected_size[1], 1e-10), request_id, 'Effective minimum pixels differ')
            if prepared:
                audit.check(prepared['line'] < start['line'], request_id, 'Request precedes prepared image')
                for key in ('pngSHA256', 'pixelSHA256'):
                    audit.check(v.get(key) == prepared['value'].get(key), request_id, f'Request {key} differs from shared image')
        if end:
            audit.fields(end['value'], {'observations': len(obs), 'candidates': len(candidates)}, request_id)
            audit.check(finite(end['value'].get('seconds')) and end['value']['seconds'] >= 0, request_id, 'Invalid request duration')
        if start and end:
            audit.check(start['line'] < end['line'], request_id, 'Request boundaries out of order')
            for r in records:
                if r['value'].get('kind') not in ('requestStart', 'requestEnd'):
                    audit.check(start['line'] < r['line'] < end['line'], request_id, 'Result outside request boundaries')
        indices = [r['value'].get('index') for r in obs]
        audit.check(indices == list(range(len(obs))), request_id, 'Observation indices missing/repeated/out of order')
        for r in candidates + of(records, 'characterBounds') + of(records, 'characterBoundsEnd'):
            audit.check(r['value'].get('observation') in indices, request_id, 'Candidate/character has no observation')
        details = []
        for observation in obs:
            v = observation['value']; index = v.get('index'); scope = f'{request_id}/obs:{index}'
            audit.check('box' in v and (v['box'] is None or valid_box(v['box'])), scope, 'Invalid observation rectangle')
            audit.check(v.get('coordinates') == 'prepared-normalized-bottom-left', scope, 'Observation coordinates differ')
            found = [c for c in candidates if c['value'].get('observation') == index]
            audit.check(v.get('candidates') == len(found) and len(found) <= 3, scope, 'Per-observation candidate count differs')
            audit.check([c['value'].get('rank') for c in found] == list(range(1, len(found) + 1)), scope, 'Candidate ranks missing/repeated/out of order')
            for c in found:
                cv = c['value']; audit.check(isinstance(cv.get('raw'), str), scope, 'Non-string raw candidate')
                audit.check(finite(cv.get('confidence')) and 0 <= cv['confidence'] <= 1, scope, 'Invalid confidence')
                audit.check(c['line'] > observation['line'], scope, 'Candidate precedes observation')
            top = next((c for c in found if c['value'].get('rank') == 1), None)
            chars = character_bounds(records, top, index, expected_size, scope, audit)
            details.append({'observation': observation, 'candidates': found, 'characters': chars,
                'preparedPixelsTopLeft': pixel_box(v.get('box'), expected_size),
                'basePixelsTopLeft': pixel_box(v.get('box'), expected_size, scale)})
        result.append({'requestID': request_id, 'imageID': image_id, 'row': row, 'geometry': 'headerCapped',
            'scale': scale, 'minimumHeightMode': mode, 'complete': bool(start and end and prepared),
            'localIntegrityOK': len(audit.errors) == before, 'errors': audit.errors[before:],
            'requestStart': start, 'requestEnd': end, 'observations': details,
            'counts': {'observations': len(obs), 'candidates': len(candidates)}})
    automatic = [r['requestStart']['value'].get('automaticallyDetectsLanguage') for r in result if r['requestStart']]
    audit.check(len(automatic) == 32 and all(type(v) is bool for v in automatic) and len(set(automatic)) == 1,
                'settings', 'Untouched automatic-language getter differs or is missing; no historical default is assumed')
    return result, automatic


def offline_score(cells, truth_path):
    truth = read_json(truth_path)
    expected_metadata = {'schemaVersion': 1, 'photoSHA256': PHOTO_SHA, 'geometrySHA256': GEOMETRY_SHA,
                         'sourceCommit': PHOTO_SOURCE, 'generatorSHA256': GENERATOR_SHA, 'selectedRows': list(ROWS)}
    if any(truth.get(k) != v for k, v in expected_metadata.items()):
        raise ValueError('Offline truth provenance/selection mismatch')
    mapping = truth.get('expectedStatusByRow', {})
    if set(mapping) != {str(r) for r in ROWS} or not all(isinstance(v, str) and v for v in mapping.values()):
        raise ValueError('Offline truth must contain exactly eight nonempty statuses')
    for cell in cells:
        expected = mapping[str(cell['row'])]; matches = []
        for observation in cell['observations']:
            for c in observation['candidates']:
                v = c['value']; raw = v['raw']
                matches.append({'observation': v['observation'], 'rank': v['rank'], 'line': c['line'], 'raw': raw,
                    'exact': raw == expected, 'whitespaceExact': ''.join(raw.split()) == expected,
                    'literalFullWordSubstring': expected in raw})
        top, lower = [[m for m in matches if m['rank'] in ranks] for ranks in [(1,), (2, 3)]]
        exact = any(m['exact'] for m in top); norm = any(m['whitespaceExact'] for m in top)
        substring = any(m['literalFullWordSubstring'] for m in top)
        cell['offlineScore'] = {'expected': expected, 'candidateMatches': matches,
            'top1Exact': exact, 'top1WhitespaceOnlyAdditional': norm and not exact,
            'top1ExactOrWhitespace': norm, 'top1LiteralFullWordSubstring': substring,
            'top1SubstringWithoutExactOrWhitespace': substring and not norm,
            'rank2or3ExactOnlyAdditional': not exact and any(m['exact'] for m in lower),
            'rank2or3WhitespaceOnlyAdditional': not norm and any(m['whitespaceExact'] for m in lower),
            'rank2or3LiteralFullWordSubstring': any(m['literalFullWordSubstring'] for m in lower)}
    return truth


def combinations(cells, valid):
    result = []
    for scale in SCALES:
        for mode in MODES:
            group = [r for r in cells if r['scale'] == scale and r['minimumHeightMode'] == mode]
            counts = None
            if valid:
                keys = [k for k in group[0]['offlineScore'] if k not in ('expected', 'candidateMatches')]
                counts = {k: sum(r['offlineScore'][k] for r in group) for k in keys}
            result.append({'scale': scale, 'minimumHeightMode': mode, 'fixedDenominator': 8,
                'completeRequests': sum(r['complete'] for r in group),
                'observations': sum(r['counts']['observations'] for r in group),
                'candidates': sum(r['counts']['candidates'] for r in group), 'publishedRateValid': valid,
                'counts': counts, 'top1ExactRate': counts['top1Exact'] / 8 if valid else None,
                'top1ExactOrWhitespaceRate': counts['top1ExactOrWhitespace'] / 8 if valid else None,
                'substringOrLowerRankIsAccuracy': False})
    return result


def row_comparisons(cells, baseline):
    by_id = {r['requestID']: r for r in cells}; result = []
    for image_id, (row, scale) in IMAGE_IDS.items():
        a, b = [by_id[f'{image_id}-{m}'] for m in MODES]
        raw = lambda r: [c['value'] for o in r['observations'] for c in o['candidates']]
        signature = lambda values: [(v.get('observation'), v.get('rank'), v.get('raw')) for v in values]
        old, av, bv = baseline[image_id]['baselineCandidates'], raw(a), raw(b)
        result.append({'imageID': image_id, 'row': row, 'scale': scale, 'probe6Candidates': old,
            'min10Candidates': av, 'min0Candidates': bv,
            'min10RawChangedFromProbe6': signature(old) != signature(av),
            'rawChangedWithMinimumHeight': signature(av) != signature(bv),
            'min10ObservationBasePixels': [o['basePixelsTopLeft'] for o in a['observations']],
            'min0ObservationBasePixels': [o['basePixelsTopLeft'] for o in b['observations']],
            'min10Score': a.get('offlineScore'), 'min0Score': b.get('offlineScore')})
    return result


def run(args):
    for name in ('expected_commit', 'expected_tree', 'workflow_commit'):
        if not re.fullmatch('[0-9a-f]{40}', getattr(args, name)):
            raise ValueError(f'--{name.replace("_", "-")} must be an exact 40-character SHA')
    if min(args.run_id, args.job_id, args.attempt) < 1:
        raise ValueError('Run/job/attempt must be positive')
    if args.png_report is None:
        args.png_report = args.png_dir / 'extraction-report.json'
    files = {'canonicalLog': args.log, 'sourceManifest': args.source_manifest, 'runMetadata': args.run_metadata,
             'jobMetadata': args.job_metadata, 'pngExtractionReport': args.png_report, 'extractorSource': args.extractor,
             'baseline': args.baseline, 'geometry': args.geometry, 'analysisScript': Path(__file__)}
    for name, p in files.items():
        if not p.is_file():
            raise ValueError(f'Missing {name}: {p}')
    if sha(args.baseline) != BASELINE_SHA or sha(args.geometry) != GEOMETRY_SHA:
        raise ValueError('Frozen baseline/geometry digest differs')
    baseline_document, geometry = read_json(args.baseline), read_json(args.geometry)
    baseline = {r['requestID']: r for r in baseline_document['images']}
    if set(baseline) != set(IMAGE_IDS) or baseline_document['sourceProbeRuntimeCommit'] != BASELINE_RUNTIME:
        raise ValueError('Frozen baseline provenance/selection differs')
    source, metadata, job_document, proof = map(read_json, (args.source_manifest, args.run_metadata, args.job_metadata, args.png_report))
    audit = Audit(); job = provenance(args, source, metadata, job_document, audit)
    events, tests = read_events(args.log, audit)
    methods = methods_and_order(events, tests, args.expected_commit, geometry, audit)
    bases, images = images_and_pngs(args, events, geometry, baseline, proof, audit)
    cells, automatic = requests_and_results(events, images, baseline, audit)
    truth, truth_read_attempted = None, False
    # No read, hash, or parse of status truth occurs before this integrity gate.
    if not audit.errors:
        truth_read_attempted = True
        try:
            truth = offline_score(cells, args.truth)
            files['offlineTruth'] = args.truth
        except (OSError, ValueError, KeyError, TypeError) as e:
            audit.check(False, 'offlineTruth', str(e))
    valid = not audit.errors and truth is not None
    chars = [o['characters'] for r in cells for o in r['observations']]
    summary = {'schemaVersion': 2, 'scope': 'Independent public-fixture Probe7 diagnostic; not product acceptance',
        'sourceCommit': args.expected_commit, 'sourceTree': args.expected_tree, 'workflowCommit': args.workflow_commit,
        'runID': args.run_id, 'jobID': args.job_id, 'attempt': args.attempt, 'canonicalLogSHA256': sha(args.log),
        'integrity': {'finalConclusionEligible': valid, 'overallOK': not audit.errors, 'errors': audit.errors,
                      'warnings': audit.warnings, 'truthRead': truth is not None,
                      'truthReadAttempted': truth_read_attempted, 'truthValidated': truth is not None},
        'counts': {'methods': len(methods), 'baseCrops': len(bases), 'preparedImages': len(of(events, 'prepared')),
                   'requestStarts': len(of(events, 'requestStart')), 'requestEnds': len(of(events, 'requestEnd')),
                   'completeRequests': sum(r['complete'] for r in cells), 'expectedRequests': 32,
                   'verifiedOriginalPNGs': sum(r.get('independentPNGVerified', False) for r in images.values()),
                   'systemRequestsExpected': 0},
        'combinations': combinations(cells, valid), 'methods': methods, 'xctests': tests,
        'automaticLanguageGetterValues': sorted(set(v for v in automatic if type(v) is bool)),
        'characterBounds': {'logged': sum(c['loggedCharacters'] for c in chars),
                            'nil': sum(c['nullBoxes'] for c in chars),
                            'sharedGroups': sum(len(c['sharedBoxGroups']) for c in chars)},
        'scoringPolicy': {'denominator': 'Eight fixed rows per scale/minimum-height pair, never filtered to observed rows',
            'top1': 'Entire expected status in any one rank-1 observation; at most one success per request',
            'whitespace': 'Unicode whitespace deletion only; additional count excludes exact matches',
            'substring': 'Complete expected word inside larger text is diagnostic only, never accuracy',
            'lowerRanks': 'Ranks 2/3 retained and counted separately; never rescue top1 accuracy',
            'noRepair': 'No joining observations, substitution, NFKC, simplified/traditional conversion, fuzzy matching or dictionary rescue',
            'failedIntegrity': 'A failed pre-scoring integrity check prevents opening status truth; failed truth validation also leaves counts/rates null'},
        'limitations': ['Generator-derived frozen geometry, not measured Build495 OCR boxes',
            'minimumTextHeight=0 does not prove that every internal Vision resize is disabled',
            'CG provider hash includes layout/padding and is separate from PNG byte identity',
            'Shared/nil/error character rectangles are preserved; pixel coordinates do not invent segmentation',
            'XCTest pass is execution evidence, not OCR correctness']}
    manifest = {'generatedUTC': datetime.now(timezone.utc).isoformat(),
        'inputs': {k: {'path': str(p), 'sha256': sha(p), 'bytes': p.stat().st_size} for k, p in files.items()},
        'sourceManifest': source, 'runMetadata': metadata, 'jobMetadata': job,
        'truthReadStage': 'Only after source, execution, geometry, PNG bytes/proof, request, candidate and character integrity pass',
        'truthBasis': truth.get('basis') if truth else None, 'doesNotModifyImagesRepositoriesOrTruth': True}
    args.out.mkdir(parents=True, exist_ok=True)
    for name, value in [('summary.json', summary), ('manifest.json', manifest), ('images.json', list(images.values())),
                        ('cell_requests.json', cells), ('row_comparison.json', row_comparisons(cells, baseline))]:
        dump(args.out / name, value)
    with (args.out / 'events.jsonl').open('w') as stream:
        for event in events:
            stream.write(json.dumps(event, ensure_ascii=False, allow_nan=False) + '\n')
    lines = [f'Probe7 full evidence gate: {"PASS" if valid else "FAIL"}; errors={len(audit.errors)}',
             f'Source {args.expected_commit}; run {args.run_id}; attempt {args.attempt}; job {args.job_id}',
             f'Methods {len(methods)}/4; images {len(of(events, "prepared"))}/16; complete requests {sum(r["complete"] for r in cells)}/32',
             f'Original PNG byte/IHDR/CRC-report gate: {summary["counts"]["verifiedOriginalPNGs"]}/16']
    if valid:
        for combo in summary['combinations']:
            c = combo['counts']
            lines.append(f'{combo["scale"]}x {combo["minimumHeightMode"]}: exact {c["top1Exact"]}/8; whitespace-only +{c["top1WhitespaceOnlyAdditional"]}/8; substring diagnostic {c["top1LiteralFullWordSubstring"]}/8; rank2/3 exact-only +{c["rank2or3ExactOnlyAdditional"]}/8')
    else:
        lines.append('No accepted OCR score: integrity failed; offline status truth was not used for a published rate.')
    lines.append('Independent diagnostic; test execution passing is separate from OCR correctness.')
    (args.out / 'summary.txt').write_text('\n'.join(lines) + '\n'); print('\n'.join(lines))
    return 0 if valid else 2


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for flag in ('expected-commit', 'expected-tree', 'workflow-commit'):
        p.add_argument('--' + flag, required=True)
    for flag in ('run-id', 'job-id', 'attempt'):
        p.add_argument('--' + flag, required=True, type=int)
    for flag in ('log', 'source-manifest', 'run-metadata', 'job-metadata', 'png-dir'):
        p.add_argument('--' + flag, required=True, type=Path)
    p.add_argument('--png-report', type=Path, help='Defaults to PNG_DIR/extraction-report.json')
    p.add_argument('--extractor', type=Path, default=HERE / 'tools/extract_xcresult_png.py')
    p.add_argument('--baseline', type=Path, default=HERE / 'probe6_b_baseline.json')
    p.add_argument('--geometry', type=Path, default=HERE.parent / 'status-cell-geometry/status_cell_probe_geometry.json')
    p.add_argument('--truth', type=Path, default=HERE.parent / 'status-probe6/offline_truth.json')
    p.add_argument('--out', type=Path, default=HERE / 'analysis')
    args = p.parse_args()
    try:
        return run(args)
    except (OSError, ValueError, TypeError, KeyError, struct.error) as e:
        print(f'Probe7 analysis stopped without an accepted score: {e}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
