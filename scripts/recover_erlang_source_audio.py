#!/usr/bin/env python3
"""Recover D15 audio from exact original objects after a lost private snapshot.

The historical 75-file and seven-floor-file receipts are independent PCM and
marker oracles. Every current clock is derived again from authenticated source
configuration. This creates a new recovery input identity; it never pretends
the missing historical private manifests have been reconstructed byte-for-byte.
"""
from __future__ import annotations

import argparse
import copy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import re

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from bind_erlang_source_audio import bind_marker, MODEL_ROLES, CONFIG_SHA, MEDITATION_TRIGGER_SHA, PALACE_SHA, FLOOR_SOURCE_SHA
from bind_erlang_personal_neck import RECOVERED_PROFILE_SHA, RECOVERED_CHARACTER_SHA
from erlang_source_profile import source_window
from prepare_erlang_source_audio import CATALOG_SHA, DEDICATED_BUNDLE, PREFIX, marker_bindings, pcm_properties
from sun_triad_assets import private_output, require

ROOT = Path(__file__).resolve().parent
NAMED_SHA = '12704648d0fd60929d1bba47a0fe6cd1eb0f3aafd36b7504b8819f57f5bddb08'
COMMON_RECEIPT_SHA = '9d688659a778fe4a75af67399cab4b7a010f2fa4d705097491f49b078d7f11a2'
FLOOR_RECEIPT_SHA = '8fc36d10be806201c97de88232fc0f041288a7e8f2d879486f1ac961266f64b1'
RECOVERED_AUDIO_SHA = '07d582bf8eb888424bb64939c2f469f4dc0e9536e6b58acc5c51fbaed307928e'
NECK_PROFILE_SHA = 'c5bbe34d04d4efb59c46a122b3e1e35b1d196e79b394783fafadea4043103fbd'
NECK_CHARACTER_SHA = 'af7106eea49691b3057772203907a5a350947e68403e0e0e8b69de9c8d082431'
PCM_FIELDS = ('name', 'bytes', 'sha256', 'sampleRate', 'channels', 'sampleFrames', 'sampleWidth', 'pcmSHA256')


def source_events(profile, named):
    dedicated, _ = marker_bindings(named)
    ordinary, floors = [], []
    roles = {clip: role for role, clip in profile['roles'].items()}
    require(len(roles) == len(profile['roles']), 'Ambiguous source actor role')
    for clip in profile['clips']:
        source = clip['sourceConfiguration']; conf = source['configuration']
        role = roles.get(clip['name'])
        first, last, stride = source_window(conf, clip['sourceUncroppedFrames'])
        require((first, last) == (clip['sourceFirstIndex'], clip['sourceLastIndex'])
                and clip['frames'] == last-first+1 and clip['playbackTicks'] == (last-first)*stride,
                'Actor audio would borrow a different source crop or clock')
        for index, sound in enumerate(conf['Sounds'] or []):
            routes = [('Floor.Stone', (sound['Floor'] or {}).get('Stone'))]
            if not conf['Animation'].startswith('D15_'):
                routes.extend([('Common', sound['Common']), ('Male', (sound['Gender'] or {}).get('Male'))])
            for route, identifiers in routes:
                if not identifiers:
                    continue
                require(role is not None and type(sound['Frame']) is int, 'Unbound source audio role or frame')
                raw_frame = sound['Frame']; frame = max(0, raw_frame); tick = (frame-first)*stride
                require(0 <= tick <= clip['playbackTicks'], 'Sound falls outside the real source playback window')
                choices = []
                for identifier in identifiers:
                    fields = identifier.split('@')
                    require(len(fields) == 3 and fields[1] == 'Battle'
                            and fields[2] in ('Movement', 'Voice', 'WeaponAndArmor')
                            and re.fullmatch(r'[A-Za-z0-9_./-]+', fields[0]) is not None
                            and all(p not in ('', '.', '..') for p in fields[0].split('/')), 'Unbound audio identifier')
                    choices.append(dict(identifier=identifier, sourcePath=PREFIX+fields[0].lower()+'.wav',
                                        bus=fields[1], mixerGroup=fields[2]))
                entry = source['sourceEntry']; is_floor = route == 'Floor.Stone'
                identifier = (f"floor_{sha(entry.encode())[:8]}_{source['sourceRecordIndex']}_{index}_Stone" if is_floor else
                              f"ordinary_{sha(entry.encode())[:8]}_{source['sourceRecordIndex']}_{index}_{route}")
                event = dict(id=identifier, animationAlias=conf['Animation'], sourceMotion=conf['FileName'],
                    sourceEntry=entry, sourceSHA256=source['sourceSHA256'], sourceRecordIndex=source['sourceRecordIndex'],
                    markerIndex=index, route=route, rawFrame=raw_frame, sourceFrame=frame, sourceFirstIndex=first,
                    sourceFrameStride=stride, sourceTick=tick, sourceFrames=clip['frames'], duration=clip['playbackTicks'],
                    clip=clip['name'], role=role, sourceMotionSHA256=clip['sha256'], choices=choices)
                (floors if is_floor else ordinary).append(event)
    require(len(ordinary) == 69 and len(floors) == 21, 'Actual recovered actor marker inventory changed')
    events = dedicated+ordinary+floors
    require(len(events) == 119, 'Recovered marker scope differs')
    return events


def bind_events(profile, events):
    tracks = {t['role']: t for t in profile['summonTracks']}
    models = {alias: dict(role=role, sourceMotionSHA256=tracks[role]['sourceSHA256'])
              for alias, role in MODEL_ROLES.items()}
    result = []
    for event in events:
        marker, pending = bind_marker(event, profile, models)
        require(marker is not None and pending is None, 'A recovered source marker is not bound to its actual clock')
        result.append(marker)
    require(len(result) == len({m['id'] for m in result}) == 119, 'Duplicate or missing audio marker')
    return result


def verify_historical_markers(markers, common, floor):
    current = {m['id']: m for m in markers}
    require(len(current) == len(markers) == 119, 'Incomplete runtime audio inventory')
    for old in common['markers']:
        now = current[old['id']]
        require(all(now.get(key) == value for key, value in old.items()), 'Historical Common/Male marker changed: '+old['id'])
    for old in floor['markers']:
        now = current[old['id']]
        for key, value in old.items():
            actual_key = {'rawFrame': 'originalFrame'}.get(key, key)
            if key == 'markerIndex':
                require(str(value) == old['id'].split('_')[-2], 'Historical floor marker index differs')
            else:
                require(now.get(actual_key) == value, 'Historical floor clock changed: '+old['id'])
    require(len(common['markers']) == 98 and len(floor['markers']) == 21, 'Historical oracle scope differs')


def prepare(args):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use the reviewed original AudioClip decoder')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    profile = json.loads(checked(args.profile, RECOVERED_PROFILE_SHA, 24_000_000))
    require(profile['id'] == profile['hero'] == 'wuyong_erlang'
            and profile['sha256'] == RECOVERED_CHARACTER_SHA and len(profile['clips']) == 62,
            'Expected the pinned recovered runtime actor')
    named = json.loads(checked(args.named, NAMED_SHA, 4_000_000))
    common = json.loads(checked(ROOT/'erlang_source_audio_receipt_20261115.json', COMMON_RECEIPT_SHA, 200_000))
    floor = json.loads(checked(ROOT/'erlang_palace_floor_audio_receipt_20261115.json', FLOOR_RECEIPT_SHA, 100_000))
    trigger = json.loads(checked(ROOT/'erlang_source_meditation_audio_20261115.json', MEDITATION_TRIGGER_SHA, 8192))
    catalog_raw = checked(args.catalog, CATALOG_SHA, 10_000_000)
    require(len(catalog_raw) == 9_100_700, 'Original catalog size differs')
    catalog = [json.loads(line) for line in catalog_raw.splitlines()]
    events = source_events(profile, named)
    wanted = {c['sourcePath'] for e in events for c in e['choices']}
    dedicated = next(r for r in catalog if r['file'] == DEDICATED_BUNDLE)
    original_d15 = {p['path'] for p in dedicated['paths'] if p['path'].startswith(PREFIX+'set_d15/')}
    require(len(original_d15) == 14, 'Original dedicated D15 audio scope changed')
    wanted |= original_d15
    require(len(wanted) == 82, 'Recovered source file closure differs')
    selected = {}
    for row in catalog:
        for entry in row['paths']:
            if entry['path'] in wanted:
                require(entry['path'] not in selected and entry['file_id'] == 0, 'Ambiguous original AudioClip')
                selected[entry['path']] = row, entry
    require(set(selected) == wanted, 'Original source sound missing')
    # Historical receipts are fixed independent byte oracles. Re-decode only
    # because the prior private PCM bytes were lost, then require exact identity.
    expected = common['files'] + [{k: v[k] for k in PCM_FIELDS} for v in floor['inputs']]
    by_sha = {f['sha256']: f for f in expected}
    require(len(by_sha) == len(expected) == 82, 'Ambiguous historical PCM identity')
    require(not args.output.exists(), 'Use a fresh private recovered-audio directory')
    output = private_output(args.output)
    environments, files = {}, []
    for path in sorted(wanted):
        row, entry = selected[path]
        if row['file'] not in environments:
            candidates = [directory/row['file'] for directory in args.bundle_directory if (directory/row['file']).is_file()]
            require(candidates, 'Missing exact original sound bundle '+row['file'])
            raw = checked(candidates[0], row['sha256'], 16_000_000)
            require(len(raw) == row['bytes'], 'Original bundle size changed')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                env = UnityPy.load(raw)
            containers = {p.lower(): ref for p, ref in env.container.items()}
            require(len(containers) == len(env.container), 'Duplicate original container')
            environments[row['file']] = containers
        pointer = environments[row['file']][path]; obj = pointer.deref()
        require(obj.type.name == 'AudioClip' and obj.path_id == entry['path_id'], 'Wrong original AudioClip object')
        clip = pointer.read(); resource = clip.m_Resource
        raw = get_resource_data(resource.m_Source, clip.object_reader.assets_file, resource.m_Offset, resource.m_Size)
        require(0 < len(raw) <= 4_000_000, 'Encoded sound exceeds source bound')
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            samples = clip.samples
        require(len(samples) == 1, 'Ambiguous original PCM decode')
        filename, pcm = next(iter(samples.items()))
        require(filename.endswith('.wav'), 'Expected original WAV decode')
        props = pcm_properties(pcm, clip)
        require(props['sha256'] in by_sha, 'Recovered PCM differs from independently recorded historical bytes')
        old = by_sha[props['sha256']]
        require(all(props[k] == old[k] for k in props), 'Recovered PCM samples or format differ from historical evidence')
        name = old['name']; write_new(output/name, pcm)
        files.append(dict(name=name, **props, sourcePath=path, sourceName=clip.m_Name,
            sourcePathID=str(obj.path_id), sourceBundle=row['file'], sourceBundleSHA256=row['sha256'],
            sourceObjectSHA256=sha(obj.get_raw_data()), encodedSHA256=sha(raw), encodedBytes=len(raw)))
        print('RESTORED', name, flush=True)
    require({f['name'] for f in files} == {f['name'] for f in expected}, 'Recovered PCM closure differs')
    lookup = {f['sourcePath']: f['name'] for f in files}
    for event in events:
        for choice in event['choices']:
            choice['file'] = lookup[choice['sourcePath']]
    markers = bind_events(profile, events)
    verify_historical_markers(markers, common, floor)
    document = dict(schema='d15-recovered-source-audio-v1', profileID=profile['id'],
        recoveredProfileSHA256=RECOVERED_PROFILE_SHA, recoveredNamedSHA256=NAMED_SHA,
        originalCatalogSHA256=CATALOG_SHA, historicalCommonReceiptSHA256=COMMON_RECEIPT_SHA,
        historicalFloorReceiptSHA256=FLOOR_RECEIPT_SHA, sourceTriggerManifestSHA256=MEDITATION_TRIGGER_SHA,
        sourceConfigurationHashes=common['sourceConfigurationHashes'], files=files, events=events,
        exactHistoricalPCMFilesRestored=82, exactHistoricalCommonMaleMarkersReverified=98,
        exactHistoricalFloorMarkerClocksReverified=21, historicalPrivateManifestBytesRestored=False,
        decoder='UnityPy 1.25.4 AudioClip.samples; original PCM16, no gain, trim or resampling',
        historicalSourceInputs=common['sourceInputs']+[floor['sourceInput']],
        normalApplicationPlaybackObserved=False)
    write_new(output/'SF3_Erlang_Recovered_Source_Audio.json', encoded(document))
    return dict(input=record(output/'SF3_Erlang_Recovered_Source_Audio.json'), pcmFiles=len(files),
                pcmBytes=sum(f['bytes'] for f in files), markers=len(markers), nativePlaybackObserved=False)


def bind(args):
    require(args.audio_input_sha256 == RECOVERED_AUDIO_SHA
            and args.profile_sha256 == NECK_PROFILE_SHA, 'Unreviewed recovered input identity')
    source = json.loads(checked(args.audio_input, RECOVERED_AUDIO_SHA, 600_000))
    require(source['schema'] == 'd15-recovered-source-audio-v1'
            and source['recoveredProfileSHA256'] == RECOVERED_PROFILE_SHA
            and source['recoveredNamedSHA256'] == NAMED_SHA
            and source['originalCatalogSHA256'] == CATALOG_SHA
            and source['historicalCommonReceiptSHA256'] == COMMON_RECEIPT_SHA
            and source['historicalFloorReceiptSHA256'] == FLOOR_RECEIPT_SHA
            and len(source['files']) == 82, 'Unexpected recovered audio source')
    profile_raw = checked(args.profile, args.profile_sha256, 24_000_000); profile = json.loads(profile_raw)
    require(profile['id'] == profile['hero'] == 'wuyong_erlang'
            and profile['sha256'] == NECK_CHARACTER_SHA and len(profile['clips']) == 62
            and profile['recoveryBoundary']['personalNeckBridgeIncluded'] is True,
            'Expected the recovered original actor with verified personal neck binding')
    character = args.profile.parent/(profile['resourceName']+'.glb')
    checked(character, profile['sha256'], 24_000_000)
    require(character.stat().st_size == profile['bytes'], 'Current actor size differs')
    markers = bind_events(profile, source['events'])
    common = json.loads(checked(ROOT/'erlang_source_audio_receipt_20261115.json', COMMON_RECEIPT_SHA, 200_000))
    floor = json.loads(checked(ROOT/'erlang_palace_floor_audio_receipt_20261115.json', FLOOR_RECEIPT_SHA, 100_000))
    verify_historical_markers(markers, common, floor)
    trigger = json.loads(checked(ROOT/'erlang_source_meditation_audio_20261115.json', MEDITATION_TRIGGER_SHA, 8192))
    files = [{k: f[k] for k in PCM_FIELDS} for f in source['files']]
    triggers = [dict(id='d15_meditation', file=trigger['sourcePCM']['file'], loop=False,
        sourceIdentifier=trigger['sourceIdentifier'], sourceLock=1432, sourceLockSHA256=trigger['sourceLock']['sha256'],
        startTrigger=13, stopTrigger=21, startEvent='meditationStarted', stopEvent='meditationStopped')]
    deferred = copy.deepcopy(common['unplayedInputs'])
    require(({f for m in markers for f in m['files']} | {f['file'] for f in triggers+deferred}) == {f['name'] for f in files},
            'Complete source PCM closure differs')
    document = dict(schemaVersion=5, profileID=profile['id'], profileSHA256=sha(profile_raw),
        characterSHA256=profile['sha256'], sourceConfigurationSHA256=CONFIG_SHA,
        sourceAudioManifestSHA256=args.audio_input_sha256, sourceRecoveredProfileSHA256=RECOVERED_PROFILE_SHA,
        sourceOrdinaryAudioManifestSHA256=None, sourceFloorAudioManifestSHA256=None,
        sourceTriggerManifestSHA256=MEDITATION_TRIGGER_SHA,
        sourceConfigurationHashes=source['sourceConfigurationHashes'], files=files, markers=markers,
        pendingModels=[], deferredTriggers=deferred, triggerSounds=triggers,
        context=dict(gender='Male', floor='Stone', stageName='SF3_Palace_Exterior.glb',
            stageSHA256=PALACE_SHA, floorSourceSHA256=FLOOR_SOURCE_SHA),
        scope='Recovered exact 82 historical PCM files and all 119 actual actor/model markers; Stone only in verified Palace.',
        runtimePlaybackObserved=False, historicalPrivateManifestBytesRestored=False)
    require(not args.output.exists(), 'Use a fresh bound-audio directory')
    output = private_output(args.output)
    for f in files:
        data = checked(args.audio_input.parent/f['name'], f['sha256'], 4_000_000)
        require(len(data) == f['bytes'], 'Recovered original PCM changed')
        write_new(output/f['name'], data)
    write_new(output/'SF3_Erlang_Audio.json', encoded(document))
    write_new(output/'erlang-recovered-audio-binding-private.json', encoded(dict(
        source=record(args.audio_input), profile=record(args.profile), character=record(character),
        audio=record(output/'SF3_Erlang_Audio.json'), markers=119, files=82,
        actorMarkers=108, independentModelMarkers=11, sourceTriggerSounds=1,
        exactHistoricalPCMRestored=True, historicalPrivateManifestBytesRestored=False,
        decodedAgain=False, normalApplicationPlaybackObserved=False)))
    return dict(audio=record(output/'SF3_Erlang_Audio.json'), files=82, markers=119, nativePlaybackObserved=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pre = commands.add_parser('prepare')
    for name in ('profile', 'named', 'catalog', 'output'):
        pre.add_argument('--'+name, type=Path, required=True)
    pre.add_argument('--bundle-directory', type=Path, action='append', required=True)
    binding = commands.add_parser('bind')
    for name in ('profile', 'audio-input', 'output'):
        binding.add_argument('--'+name, type=Path, required=True)
    for name in ('profile-sha256', 'audio-input-sha256'):
        binding.add_argument('--'+name, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args) if args.command == 'prepare' else bind(args), allow_nan=False))


if __name__ == '__main__':
    main()
