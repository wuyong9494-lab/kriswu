#!/usr/bin/env python3
"""Recover exact ordinary/shared Wu source sounds, reusing authenticated PCM.

The admitted actor's actual source configurations select the inputs. Original
Common/Male routes and clocks survive unchanged; no generic weapon sound is
substituted. This is local input preparation, not playback or a release.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stderr, redirect_stdout
import copy
import io
import json
from pathlib import Path
import re
from zipfile import ZipFile

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from erlang_source_profile import SETTINGS_SHA, source_window
from prepare_erlang_source_audio import CATALOG_SHA, PREFIX, pcm_properties
from prepare_pangu_source_audio_inputs import (ANIMATION_FIELDS, named_sound,
    SETTINGS_VALUES_SHA256, SETTINGS_VALUES_BYTES, SETTINGS_SOURCE_SHA256)
from sun_triad_assets import private_output, require

D15_INPUT_SHA = '01649a542d8a20cbe66e9e1bee831201c3c70cdd4200c6f0b1b23c66e88aa9fd'
PANGU_PLAN_SHA = 'd9ec224b8cd84f7ad340ae00de396fb2911b73fd28a68022df6506b9cf34eba0'
PANGU_LOCATIONS_SHA = '0b377585ede12e5a9eeeb595ef637177677fe3755a51df20d712bf6af947b9b9'
REVIEWED = {
    'h17-context-audio-inventory-private.json': ('06a0b02587c55106b851f33aad1a7b10a480e5fad846d26c17a0510351974736', 'files'),
    'h17-common-context-audio-inventory-private.json': ('b1557aafc28213d6e2ed9aa975473c2649b94e48a10ced20da07bce6eab43bef', 'files'),
    'h17-ordinary-throw-audio-inventory-private.json': ('dae39f463fdd9e39e513ebe90102ec74be45faa71cf0328c96437e5f281ed908', 'records'),
}
THROWS = {
    'ordinaryThrowBack': ('moves_settings.bytes', 81, 'Throw_Simple'),
    'ordinaryThrownBack': ('moves_settings.bytes', 82, 'Throw_Passive'),
    'ordinaryThrowForward': ('moves_settings.bytes', 83, 'Throw_Forward_Active'),
    'ordinaryThrownForward': ('moves_settings.bytes', 84, 'Throw_Forward_Passive'),
    'ordinaryPanguEscape': ('settings_sets_dynasty.bytes', 248, 'D19_Unthrow'),
    'ordinaryPanguResisted': ('settings_sets_dynasty.bytes', 249, 'D19_Unthrow_Passive'),
}


def source_events(profile, settings, dynasty):
    by_record = {(r['sourceEntry'], r['sourceRecordIndex']): r for r in settings['records']}
    require(len(by_record) == len(settings['records']), 'Ambiguous source configuration record')
    # These two source throw aliases are absent from the D15-only named subset.
    # Read exactly their already-decoded source records; no decryption occurs.
    for index in (248, 249):
        row = dynasty[index]
        require(isinstance(row, list) and len(row) == len(ANIMATION_FIELDS), 'Source animation schema differs')
        c = dict(zip(ANIMATION_FIELDS, copy.deepcopy(row)))
        c['Sounds'] = None if c['Sounds'] is None else [named_sound(v) for v in c['Sounds']]
        by_record['settings_sets_dynasty.bytes', index] = dict(sourceEntry='settings_sets_dynasty.bytes',
            sourceRecordIndex=index, sourceSHA256=SETTINGS_SOURCE_SHA256, configuration=c)
    roles = {name: role for role, name in profile['roles'].items()}
    require(len(roles) == len(profile['roles']), 'Expected one admitted role per source actor clip')
    events, scope, configurations = [], [], {}
    for clip in profile['clips']:
        role = roles[clip['name']]
        source = clip.get('sourceConfiguration')
        if source is None:
            require(role in THROWS, 'Unidentified actor source configuration')
            entry, index, alias = THROWS[role]
            source = by_record[entry, index]
            require(source['configuration']['Animation'] == alias, 'Original paired alias differs')
        else:
            require(source == by_record.get((source['sourceEntry'], source['sourceRecordIndex'])),
                    'Actor configuration differs from its original named record')
        c = source['configuration']
        if c['Animation'].startswith('D15_'):
            continue  # Authenticated separately by the original D15 input.
        first, last, stride = source_window(c, clip['sourceUncroppedFrames'])
        require((first, last) == (clip['sourceFirstIndex'], clip['sourceLastIndex']) and
                clip['frames'] == last - first + 1 and clip['playbackTicks'] == (last - first) * stride,
                'Ordinary sound would use a different crop or playback clock')
        stem = Path(c['FileName']).stem
        require(stem == clip['name'] or (role == 'imperialHeavyPassiveMirrored' and
                stem == 'imperial_spear_heavy_slash_passive'), 'Source sound belongs to another motion file')
        entry = source['sourceEntry']
        require(entry not in configurations or configurations[entry] == source['sourceSHA256'],
                'Conflicting source configuration bytes')
        configurations[entry] = source['sourceSHA256']
        groups = 0
        for index, sound in enumerate(c['Sounds'] or []):
            raw_frame = sound['Frame']
            require(type(raw_frame) is int, 'Sound Frame needs its actual source value')
            frame = max(0, raw_frame)
            for route, alternatives in [('Common', sound['Common']), ('Male', (sound['Gender'] or {}).get('Male'))]:
                if not alternatives:
                    continue
                tick = (frame - first) * stride
                require(0 <= tick <= clip['playbackTicks'], 'Original sound marker is outside the admitted source window')
                choices = []
                for identifier in alternatives:
                    fields = identifier.split('@')
                    require(len(fields) == 3 and fields[1] == 'Battle' and fields[2] in ('Voice', 'Movement', 'WeaponAndArmor')
                            and re.fullmatch(r'[A-Za-z0-9_./-]+', fields[0]) is not None
                            and all(p not in ('', '.', '..') for p in fields[0].split('/')), 'Unbound source sound route')
                    choices.append(dict(identifier=identifier, sourcePath=PREFIX + fields[0].lower() + '.wav',
                        bus=fields[1], mixerGroup=fields[2]))
                events.append(dict(id=f"ordinary_{sha(entry.encode())[:8]}_{source['sourceRecordIndex']}_{index}_{route}",
                    animationAlias=c['Animation'], sourceMotion=c['FileName'], sourceEntry=entry,
                    sourceSHA256=source['sourceSHA256'], sourceRecordIndex=source['sourceRecordIndex'],
                    markerIndex=index, route=route, rawFrame=raw_frame, sourceFrame=frame, sourceFirstIndex=first,
                    sourceFrameStride=stride, sourceTick=tick, sourceFrames=clip['frames'], duration=clip['playbackTicks'],
                    clip=clip['name'], role=role, sourceMotionSHA256=clip['sha256'], choices=choices))
                groups += 1
        scope.append(dict(role=role, clip=clip['name'], animationAlias=c['Animation'], sourceEntry=entry,
            sourceRecordIndex=source['sourceRecordIndex'], sourceMotionSHA256=clip['sha256'], groups=groups,
            fileName=c['FileName'], sourceBundle=clip['bundle'], sourcePathID=clip['sourcePathID']))
    require(len({e['id'] for e in events}) == len(events) == 69, 'Admitted ordinary/shared marker inventory differs')
    return events, scope, configurations


def reviewed_pcm(args, wanted):
    available, receipts = {}, []

    def add(row, parent, receipt):
        source = row['sourcePath']
        if source not in wanted:
            return
        if source in available:
            old = available[source][0]
            require(all(old[k] == row[k] for k in ('bytes', 'sha256', 'sourceObjectSHA256', 'encodedSHA256')),
                    'Existing PCM snapshots disagree')
        else:
            available[source] = row, parent, receipt

    d15 = json.loads(checked(args.d15_input, D15_INPUT_SHA, 512_000))
    receipt = record(args.d15_input); receipts.append(receipt)
    for row in d15['files']:
        add(row, args.d15_input.parent, receipt)
    for path in args.reviewed_pcm:
        require(path.name in REVIEWED, 'Unreviewed PCM inventory')
        pin, field = REVIEWED[path.name]
        d = json.loads(checked(path, pin, 1_000_000)); receipt = record(path); receipts.append(receipt)
        for row in d[field]:
            add(row, path.parent, receipt)
    plan = json.loads(checked(args.pangu_plan, PANGU_PLAN_SHA, 150_000))
    loc = json.loads(checked(args.pangu_locations, PANGU_LOCATIONS_SHA, 100_000))
    locations = {f['sourcePath']: f for f in loc['files']}
    require(len(locations) == len(loc['files']) == 32, 'Prepared shared PCM location inventory differs')
    receipt = record(args.pangu_plan); receipts.extend([receipt, record(args.pangu_locations)])
    for source in plan['inputs']:
        path = source['sourcePath']
        if path not in wanted or source.get('status') != 'verified-local-pcm':
            continue
        pcm, verified, location = source['pcm'], source['verifiedSource'], locations[path]
        require(location['bytes'] == pcm['bytes'] and location['sha256'] == pcm['sha256'] and
                Path(location['path']).name == pcm['name'], 'Prepared shared PCM location differs')
        row = {k: pcm[k] for k in ('name', 'bytes', 'sha256', 'sampleRate', 'channels', 'sampleFrames', 'sampleWidth')}
        row.update(sourcePath=path, sourceName=verified['sourceName'], sourcePathID=verified['pathID'],
            sourceBundle=verified['bundle'], sourceBundleSHA256=verified['bundleSHA256'],
            sourceObjectSHA256=verified['objectSHA256'], encodedSHA256=verified['encodedSHA256'],
            encodedBytes=verified['encodedBytes'])
        add(row, Path(location['path']).parent, receipt)
    return available, receipts


def prepare(args):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    require(profile['id'] == profile['hero'] == 'wuyong_erlang' and len(profile['clips']) in (56, 59),
            'Expected the admitted original Wu actor, optionally with exact shared Stun clips')
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    values = json.loads(checked(args.dynasty_values, SETTINGS_VALUES_SHA256, SETTINGS_VALUES_BYTES))
    events, scope, configuration_hashes = source_events(profile, settings, values)
    wanted = {x['sourcePath'] for e in events for x in e['choices']}
    require(len(wanted) == 52, 'Ordinary/shared sound path inventory differs')
    with ZipFile(args.catalog_archive) as archive:
        catalog = archive.read('research/android_bundle_catalog.jsonl')
    require(len(catalog) == 9_100_700 and sha(catalog) == CATALOG_SHA, 'Original full source catalog differs')
    rows = [json.loads(line) for line in catalog.splitlines()]
    paths = {}
    for bundle in rows:
        for item in bundle['paths']:
            path = item['path'].lower()
            if path in wanted:
                require(path not in paths and item['file_id'] == 0, 'Ambiguous source AudioClip path')
                paths[path] = bundle, item
    require(set(paths) == wanted, 'A selected source sound is missing from the catalog')
    # Verify each selected ordinary configuration references the same original
    # motion object already retained by this actor, including shared throws.
    for s in scope:
        bundle = next(r for r in rows if r['file'] == s['sourceBundle'])
        expected = 'assets/gamedata/resources/content/animations/binaries/' + s['fileName'][:-4].lower() + '.bytes'
        matches = [v for v in bundle['paths'] if v['path'].lower() == expected and str(v['path_id']) == s['sourcePathID']]
        require(len(matches) == 1 and matches[0]['file_id'] == 0, 'Configuration references another original motion object')
    reviewed, receipts = reviewed_pcm(args, wanted)
    require(len(wanted - set(reviewed)) == 7, 'Expected exactly seven not-yet-decoded original inputs')
    require(not args.output.exists(), 'Refuse to replace prepared original PCM')
    output = private_output(args.output)
    environments, files = {}, []
    for path in sorted(wanted):
        bundle, item = paths[path]
        if bundle['file'] not in environments:
            sources = [p / bundle['file'] for p in args.bundle_directory if (p / bundle['file']).is_file()]
            require(sources, 'Exact original sound bundle is not local: ' + bundle['file'])
            raw = checked(sources[0], bundle['sha256'], 16_000_000)
            require(len(raw) == bundle['bytes'], 'Original sound bundle size differs')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                environment = UnityPy.load(raw)
            containers = {p.lower(): ref for p, ref in environment.container.items()}
            require(len(containers) == len(environment.container), 'Duplicate source container path')
            environments[bundle['file']] = containers
        pointer = environments[bundle['file']][path]; obj = pointer.deref()
        require(obj.type.name == 'AudioClip' and obj.path_id == item['path_id'], 'Original AudioClip type or pathID differs')
        clip = pointer.read(); resource = clip.m_Resource
        original = get_resource_data(resource.m_Source, clip.object_reader.assets_file, resource.m_Offset, resource.m_Size)
        identity = dict(sourcePath=path, sourceName=clip.m_Name, sourcePathID=str(obj.path_id),
            sourceBundle=bundle['file'], sourceBundleSHA256=bundle['sha256'],
            sourceObjectSHA256=sha(obj.get_raw_data()), encodedSHA256=sha(original), encodedBytes=len(original))
        require(0 < len(original) <= 4_000_000, 'Original encoded sound exceeds its bound')
        if path in reviewed:
            old, parent, provenance = reviewed[path]
            require(all(old.get(k) == v for k, v in identity.items()), 'Existing PCM belongs to another original object')
            pcm = checked(parent / old['name'], old['sha256'], 4_000_000)
            properties = pcm_properties(pcm, clip)
            require(all(old[k] == properties[k] for k in ('bytes', 'sampleRate', 'channels', 'sampleFrames', 'sampleWidth')),
                    'Existing PCM format differs from the source AudioClip')
            name = old['name']
        else:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                samples = clip.samples
            require(len(samples) == 1, 'Original decoder returned ambiguous PCM')
            original_name, pcm = next(iter(samples.items()))
            require(original_name.endswith('.wav'), 'Original decoder did not return WAV')
            properties = pcm_properties(pcm, clip)
            name = 'SF3Erlang_' + re.sub('[^A-Za-z0-9_]+', '_', clip.m_Name)[:70] + '_' + properties['sha256'][:12] + '.wav'
            provenance = dict(decoder='UnityPy AudioClip.samples; original frequency/channels; no gain or resampling')
        require(Path(name).name == name, 'Unsafe PCM basename')
        write_new(output / name, pcm)
        row = dict(name=name, **properties, **identity, reusedExistingPCM=path in reviewed, provenance=provenance)
        write_new(output / (name + '.source-private.json'), encoded(row)); files.append(row)
        print(json.dumps(dict(sourceName=clip.m_Name, reusedExistingPCM=row['reusedExistingPCM'], sha256=row['sha256'])), flush=True)
    by_path = {f['sourcePath']: f['name'] for f in files}
    for e in events:
        for choice in e['choices']:
            choice['file'] = by_path[choice['sourcePath']]
    document = dict(schemaVersion=1, ownerProfileID='wuyong_erlang', catalogSHA256=CATALOG_SHA,
        sourceConfigurationHashes=configuration_hashes, files=files, events=events,
        scope='All Common/Male markers for the admitted Imperial, move, hit, kick and six paired-throw roles; Floor/Female/Monkey routes are not selected.',
        rawFrameRule='max(0, Frame), no subtraction; exact crop origin and native MidFrames+1 retained',
        runtimeAudioBindingCreated=False, normalApplicationPlaybackObserved=False)
    write_new(output / 'SF3_Erlang_Ordinary_Audio.json', encoded(document))
    receipt = dict(profile=record(args.profile), inputs=receipts,
        sourceManifest=record(output / 'SF3_Erlang_Ordinary_Audio.json'),
        originalActorScope=scope, fileCount=len(files), markerGroups=len(events),
        reusedPCM=sum(f['reusedExistingPCM'] for f in files), newlyDecodedPCM=sum(not f['reusedExistingPCM'] for f in files),
        d15PCMDecodedAgain=False, originalBundleDownloads=0, nativeApplicationPlayed=False)
    write_new(output / 'erlang-ordinary-audio-provenance-private.json', encoded(receipt))
    return {k: v for k, v in receipt.items() if k not in ('inputs', 'originalActorScope')}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('profile', 'settings', 'dynasty-values', 'catalog-archive', 'd15-input', 'pangu-plan', 'pangu-locations', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    p.add_argument('--profile-sha256', required=True)
    p.add_argument('--reviewed-pcm', type=Path, action='append', default=[])
    p.add_argument('--bundle-directory', type=Path, action='append', required=True)
    print(json.dumps(prepare(p.parse_args())))


if __name__ == '__main__':
    main()
