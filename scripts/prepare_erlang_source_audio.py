#!/usr/bin/env python3
"""Recover exact local D15 audio and Common/Male source marker bindings.

No network or credentials are used. Existing authenticated PCM is reused;
other source AudioClips are decoded once without gain, resampling or trimming.
This produces private inputs, not a claim that the application played them.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout, redirect_stderr
import hashlib
import io
import json
import math
import re
from pathlib import Path
import wave
from zipfile import ZipFile

from build_erlang_source_assets import checked, write_new, encoded
from erlang_source_profile import SETTINGS_SHA
from sun_triad_assets import require, private_output

PREFIX = 'assets/gamedata/resources/audio/sounds/'
CATALOG_SHA = '2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055'
DEDICATED_BUNDLE = '1bc6a2c0e4f0c2f6733e35f02938f8cd.bin'
REUSED_INVENTORIES = {
    'h17-context-audio-inventory-private.json': '06a0b02587c55106b851f33aad1a7b10a480e5fad846d26c17a0510351974736',
    'h17-common-context-audio-inventory-private.json': 'b1557aafc28213d6e2ed9aa975473c2649b94e48a10ced20da07bce6eab43bef',
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def marker_bindings(settings):
    events, paths = [], set()
    for record in settings['records']:
        c = record['configuration']
        if not c['Animation'].startswith('D15_'):
            continue
        stride = (1 if c['MidFrames'] is None else c['MidFrames'])+1
        first = 0 if c['FirstFrame'] is None else max(0, c['FirstFrame']-1)
        for index, event in enumerate(c['Sounds'] or []):
            frame = event['Frame']
            require(type(frame) is int, 'Source sound Frame is not an integer')
            for route, alternatives in [('Common', event['Common']), ('Male', (event['Gender'] or {}).get('Male'))]:
                if not alternatives:
                    continue
                choices = []
                for identifier in alternatives:
                    fields = identifier.split('@')
                    require(len(fields) == 3 and fields[0] and fields[1] == 'Battle'
                            and fields[2] in ('Movement','Voice','WeaponAndArmor'), 'Unbound original sound route')
                    path = PREFIX+fields[0].lower()+'.wav'
                    require('..' not in path.split('/') and '\\' not in path, 'Unsafe source sound path')
                    paths.add(path)
                    choices.append(dict(identifier=identifier, sourcePath=path, bus=fields[1], mixerGroup=fields[2]))
                events.append(dict(animationAlias=c['Animation'], sourceMotion=c['FileName'],
                    sourceEntry=record['sourceEntry'], sourceSHA256=record['sourceSHA256'],
                    sourceRecordIndex=record['sourceRecordIndex'], markerIndex=index, route=route,
                    rawFrame=frame, sourceFrame=max(0,frame), sourceFirstIndex=first,
                    sourceFrameStride=stride, sourceTick=(max(0,frame)-first)*stride,
                    choices=choices))
    require(len(events) == 29 and len(paths) == 26, 'Pinned D15 Common/Male marker scope differs')
    return events, paths


def pcm_properties(raw, clip):
    require(0 < len(raw) <= 4_000_000, 'PCM file is outside the accepted bound')
    with wave.open(io.BytesIO(raw), 'rb') as wav:
        rate, channels, frames, width = wav.getframerate(), wav.getnchannels(), wav.getnframes(), wav.getsampwidth()
        require(wav.getcomptype() == 'NONE' and width == 2 and channels in (1,2)
                and 8000 <= rate <= 192000 and 0 < frames <= 30*rate, 'Expected bounded original PCM16')
        samples = wav.readframes(frames+1)
        require(len(samples) == frames*channels*width and not wav.readframes(1), 'Truncated source PCM')
    require(rate == clip.m_Frequency and channels == clip.m_Channels and math.isfinite(clip.m_Length)
            and abs(frames/rate-clip.m_Length) < 2/rate, 'PCM differs from source AudioClip format/duration')
    return dict(bytes=len(raw), sha256=sha(raw), sampleRate=rate, channels=channels,
                sampleFrames=frames, sampleWidth=width, pcmSHA256=sha(samples))


def prepare(args):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    events, wanted = marker_bindings(settings)
    with ZipFile(args.catalog_archive) as archive:
        catalog = archive.read('research/android_bundle_catalog.jsonl')
    require(len(catalog) == 9_100_700 and sha(catalog) == CATALOG_SHA, 'Original complete catalog differs')
    rows = [json.loads(line) for line in catalog.splitlines()]
    dedicated = next(r for r in rows if r['file'] == DEDICATED_BUNDLE)
    dedicated_paths = {p['path'] for p in dedicated['paths'] if p['path'].startswith(PREFIX+'set_d15/')}
    require(len(dedicated_paths) == 14, 'Exact D15 dedicated AudioClip collection differs')
    wanted |= dedicated_paths
    by_path = {}
    for bundle in rows:
        for item in bundle['paths']:
            path = item['path'].lower()
            if path in wanted:
                require(path not in by_path and item['file_id'] == 0, 'Ambiguous source sound')
                by_path[path] = (bundle, item)
    require(set(by_path) == wanted, 'A planned original sound is absent from the reviewed catalog')
    reused = {}
    for file in args.reviewed_pcm:
        require(file.name in REUSED_INVENTORIES, 'Unreviewed source PCM receipt')
        document = json.loads(checked(file, REUSED_INVENTORIES[file.name], 1_000_000))
        for row in document['files']:
            if row['sourcePath'] in wanted:
                require(row['sourcePath'] not in reused, 'Duplicate source PCM provenance')
                reused[row['sourcePath']] = (row, file.parent, dict(file=file.name, sha256=REUSED_INVENTORIES[file.name]))
    require(not args.output.exists(), 'Refuse to overwrite already prepared PCM')
    output = private_output(args.output)
    environments, files = {}, []
    for source in sorted(wanted):
        bundle, item = by_path[source]; name = bundle['file']
        if name not in environments:
            paths = [folder/name for folder in args.bundle_directory if (folder/name).is_file()]
            require(paths, 'Missing exact source sound bundle '+name)
            raw = checked(paths[0], bundle['sha256'], 16_000_000)
            require(len(raw) == bundle['bytes'], 'Source bundle size differs')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                env = UnityPy.load(raw)
            containers = {p.lower():ref for p,ref in env.container.items()}
            require(len(containers) == len(env.container), 'Duplicate source container path')
            environments[name] = containers
        pointer = environments[name][source]; obj = pointer.deref()
        require(obj.type.name == 'AudioClip' and obj.path_id == item['path_id'], 'AudioClip identity differs')
        clip = pointer.read(); r = clip.m_Resource
        raw = get_resource_data(r.m_Source, clip.object_reader.assets_file, r.m_Offset, r.m_Size)
        require(0 < len(raw) <= 4_000_000, 'Encoded AudioClip exceeds its bound')
        identity = dict(sourcePath=source, sourcePathID=str(obj.path_id), sourceName=clip.m_Name,
            sourceBundle=name, sourceBundleSHA256=bundle['sha256'], sourceObjectSHA256=sha(obj.get_raw_data()),
            encodedSHA256=sha(raw), encodedBytes=len(raw))
        reuse = source in reused
        if reuse:
            old, parent, provenance = reused[source]
            require(all(old.get(k) == v for k,v in identity.items()), 'PCM belongs to a different original object')
            pcm = checked(parent/old['name'], old['sha256'], 4_000_000)
            props = pcm_properties(pcm, clip)
            require(all(old.get(k) == props[k] for k in ('bytes','sampleRate','channels','sampleFrames','sampleWidth')),
                    'Existing PCM receipt format differs')
            filename = old['name']
        else:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                samples = clip.samples
            require(len(samples) == 1, 'Decoder returned ambiguous original samples')
            original, pcm = next(iter(samples.items()))
            require(original.endswith('.wav'), 'Decoder did not return WAV')
            props = pcm_properties(pcm, clip)
            filename = 'SF3Erlang_'+re.sub('[^A-Za-z0-9_]+','_',clip.m_Name)[:70]+'_'+props['sha256'][:12]+'.wav'
            provenance = dict(decoder='UnityPy AudioClip.samples / original frequency and channels; no gain or resampling')
        require(Path(filename).name == filename, 'Unsafe PCM filename')
        write_new(output/filename, pcm)
        result = dict(name=filename, **props, **identity, reusedExistingPCM=reuse, provenance=provenance)
        write_new(output/(filename+'.source-private.json'), encoded(result))
        files.append(result)
        print(json.dumps(dict(sourceName=clip.m_Name, reusedExistingPCM=reuse, bytes=props['bytes'], sha256=props['sha256'])),flush=True)
    file_map = {r['sourcePath']:r['name'] for r in files}
    for event in events:
        for choice in event['choices']:
            choice['file'] = file_map[choice['sourcePath']]
    manifest = dict(schemaVersion=1, ownerProfileID='wuyong_erlang',
        sourceConfigurationVersion='1.46.0.16.16733-prod',
        sourceConfigurationSHA256='3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701',
        sourceAudioVersion='Android Xiaomi 1.45.3', catalogSHA256=CATALOG_SHA,
        files=files, events=events, dedicatedOriginalAudioClips=14,
        scope='D15 original dedicated AudioClips plus all Common/Male markers in the45 D15 animation aliases; trigger clocks and Floor/Female/Monkey routes are separate.',
        rawFrameRule='max(0, Frame), no subtraction; crop offset and native MidFrames+1 retained',
        runtimeAudioBindingCreated=False, normalApplicationPlaybackObserved=False)
    write_new(output/'SF3_Erlang_Audio.json', encoded(manifest))
    return dict(output=str(output), files=len(files), dedicatedOriginalAudioClips=14,
                markerGroups=len(events), reusedPCM=sum(r['reusedExistingPCM'] for r in files),
                newlyDecodedPCM=sum(not r['reusedExistingPCM'] for r in files),
                manifestSHA256=sha((output/'SF3_Erlang_Audio.json').read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('settings','catalog-archive','output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--bundle-directory', type=Path, action='append', required=True)
    parser.add_argument('--reviewed-pcm', type=Path, action='append', required=True)
    print(json.dumps(prepare(parser.parse_args())))


if __name__ == '__main__':
    main()
