#!/usr/bin/env python3
"""Recover original D13 PCM and bind the six ordinary-action sound identifiers.

Local, authenticated source bundles only. No resampling, gain, trimming or
invented sound substitute. Unused dedicated clips stay explicitly unbound.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout, redirect_stderr
import hashlib
import io
import json
from pathlib import Path
import re
from zipfile import ZipFile

from build_erlang_source_assets import checked, write_new
from check_serpent_action_source import PROFILE_SHA, NAMED_SHA, checked_json, markers
from check_serpent_state_source import RECEIPT_SHA, documents, require, trigger
from prepare_erlang_source_audio import pcm_properties, CATALOG_SHA, PREFIX
from prepare_serpent_named_settings import encoded
from sun_triad_assets import private_output

DEDICATED = 'aa8bb75ef585ba1ed52e58f09a0acdbf.bin'
SHARED = 'shadow_moves/mind_throw/mind_throw_whoosh_1'
SOUNDS = {
    'set_d13/poison_energy_cast': False,
    SHARED: False,
    'set_d13/poison_energy_hit_hiss': False,
    'set_d13/poison_rain_bottle': False,
    'set_d13/poison_rain_sequence-02': True,
    'set_d13/poison_rain_out': False,
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def prepare(args):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    profile = checked_json(args.profile, PROFILE_SHA)
    named = checked_json(args.named, NAMED_SHA)
    docs = documents(args.source, (1379, 1400, 1403))
    motions = markers(profile, named, docs)
    expected = {
        'poison': [(36, SHARED), (180, SHARED), (20, 'set_d13/poison_energy_cast')],
        'bottle': [(46, 'set_d13/poison_rain_bottle')],
    }
    body_events = []
    for motion in motions:
        actual = [(s['tick'], s['name'].split('@')[0]) for s in motion['sounds']]
        require(actual == expected[motion['action']], 'Ordinary source sound markers changed')
        for tick, sound in actual:
            body_events.append(dict(action=motion['action'], alias=motion['alias'],
                clip=motion['clipName'], sourceMotionSHA256=motion['clipSHA256'],
                tick=tick, identifier=sound+'@Battle@Movement'))
    triggers = []
    for lock, index, sound, stop, loop in (
        (1379, 7, 'set_d13/poison_energy_hit_hiss', False, False),
        (1403, 1, 'set_d13/poison_rain_sequence-02', False, True),
        (1403, 3, 'set_d13/poison_rain_sequence-02', False, True),
        (1403, 10, 'set_d13/poison_rain_sequence-02', True, False),
        (1403, 10, 'set_d13/poison_rain_out', False, False),
        (1403, 16, 'set_d13/poison_rain_sequence-02', True, False),
        (1403, 16, 'set_d13/poison_rain_out', False, False),
    ):
        identifier = sound+'@Battle@Movement'
        exact = {'a195': [[identifier]]} if stop else {'a111': [[identifier], True if loop else None, None]}
        require(exact in trigger(docs, lock, index)['actions'], 'Actual source sound trigger changed')
        triggers.append(dict(lock=lock, sourceSet=0, trigger=index, identifier=identifier,
                             stop=stop, loop=loop))
    with ZipFile(args.catalog_archive) as archive:
        raw = archive.read('research/android_bundle_catalog.jsonl')
    require(len(raw) == 9_100_700 and sha(raw) == CATALOG_SHA, 'Source catalog changed')
    rows = [json.loads(line) for line in raw.splitlines()]
    dedicated = next(r for r in rows if r['file'] == DEDICATED)
    paths = {p['path'] for p in dedicated['paths']}
    require(len(paths) == 13 and all(p.startswith(PREFIX+'set_d13/') for p in paths),
            'Dedicated source clip collection changed')
    paths.add(PREFIX+SHARED+'.wav')
    selected = {}
    for row in rows:
        for entry in row['paths']:
            if entry['path'] in paths:
                require(entry['path'] not in selected and entry['file_id'] == 0, 'Ambiguous source object')
                selected[entry['path']] = row, entry
    require(set(selected) == paths, 'Missing source sound object')
    require(not args.output.exists(), 'Use a fresh private audio directory')
    output = private_output(args.output)
    environments, files = {}, []
    for source_path in sorted(paths):
        row, entry = selected[source_path]
        if row['file'] not in environments:
            candidates = [p/row['file'] for p in args.bundle_directory if (p/row['file']).is_file()]
            require(candidates, 'Missing exact source audio bundle '+row['file'])
            raw = checked(candidates[0], row['sha256'], 1_000_000)
            require(len(raw) == row['bytes'], 'Source audio bundle size changed')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                env = UnityPy.load(raw)
            environments[row['file']] = dict(env.container)
        pointer = environments[row['file']][source_path]
        obj = pointer.deref()
        require(obj.type.name == 'AudioClip' and obj.path_id == entry['path_id'], 'Wrong AudioClip identity')
        clip = pointer.read()
        r = clip.m_Resource
        raw = get_resource_data(r.m_Source, clip.object_reader.assets_file, r.m_Offset, r.m_Size)
        require(0 < len(raw) <= 4_000_000, 'Encoded audio size out of bounds')
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            samples = clip.samples
        require(len(samples) == 1, 'Ambiguous source PCM decode')
        filename, pcm = next(iter(samples.items()))
        require(filename.endswith('.wav'), 'Expected WAV output')
        props = pcm_properties(pcm, clip)
        name = 'SF3Serpent_'+re.sub('[^A-Za-z0-9_]+', '_', clip.m_Name)[:70]+'_'+props['sha256'][:12]+'.wav'
        write_new(output/name, pcm)
        files.append(dict(name=name, **props, sourcePath=source_path, sourceName=clip.m_Name,
            sourcePathID=str(obj.path_id), sourceBundle=row['file'], sourceBundleSHA256=row['sha256'],
            sourceObjectSHA256=sha(obj.get_raw_data()), encodedSHA256=sha(raw), encodedBytes=len(raw)))
    by_source = {f['sourcePath']: f for f in files}
    sounds = [dict(identifier=k+'@Battle@Movement', file=by_source[PREFIX+k+'.wav']['name'],
                   loop=loop) for k, loop in SOUNDS.items()]
    bound = {s['file'] for s in sounds}
    document = dict(schema='d13-ordinary-source-audio-v1', profileID='liu_serpent',
        sourceProfileSHA256=PROFILE_SHA, sourceNamedSHA256=NAMED_SHA,
        sourceReceiptSHA256=RECEIPT_SHA, sourceCatalogSHA256=CATALOG_SHA,
        sourceAudioVersion='Android Xiaomi 1.45.3', characterSHA256=profile['sha256'],
        files=files, sounds=sounds, bodyMarkers=body_events, triggerSources=triggers,
        unbound=[dict(file=f['name'], reason='outside-ordinary-poison-and-bottle-path')
                 for f in files if f['name'] not in bound],
        dedicatedSourceClips=13, sharedSourceClips=1, normalApplicationPlaybackObserved=False)
    raw = encoded(document)
    write_new(output/'SF3_Serpent_Audio.json', raw)
    return dict(files=len(files), boundIdentifiers=len(sounds), markerOccurrences=len(body_events),
        sourceTriggerOperations=len(triggers), pcmBytes=sum(f['bytes'] for f in files),
        manifestBytes=len(raw), manifestSHA256=sha(raw), output=str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'named', 'source', 'catalog-archive', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--bundle-directory', type=Path, action='append', required=True)
    print(json.dumps(prepare(parser.parse_args())))
