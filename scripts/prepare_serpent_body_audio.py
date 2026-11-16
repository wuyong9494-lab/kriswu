#!/usr/bin/env python3
"""Bind all remaining D13 body sounds to authenticated local source PCM.

The 66 actual body clips retain the original Common/Male/Floor.Stone routes,
candidate order, duplicate entries and non-subtracting Sound.Frame clock.
Four events already owned by the dedicated poison/bottle timeline are recorded
but excluded from this supplemental timeline. No network or asset substitution.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import re
from zipfile import ZipFile

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from check_serpent_action_source import PROFILE_SHA, NAMED_SHA
from check_serpent_state_source import RECEIPT_SHA
from erlang_source_profile import source_end_event_tick, source_window
from prepare_erlang_source_audio import CATALOG_SHA, PREFIX, pcm_properties
from prepare_serpent_named_settings import (ARCHIVE_PIN, SCHEMA_PIN, SPLIT, SPLIT_SHA,
    SOURCES, AnimationProjection, Storage, member, pinned, typed)
from sun_triad_assets import private_output, require

ROOT = Path(__file__).resolve().parent
DOCUMENT_FILE = 'SF3_Serpent_Body_Audio.json'
RECEIPT_FILE = 'serpent-body-audio-receipt-private.json'
MANIFEST_SHA = '0c595b5c6e79423e3b2dc6ba21ba00e55f55194dc417aba959813a3531f28387'
MATCH_SHA = 'ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53'
CHARACTER_SHA = 'f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70'
EXISTING_AUDIO_SHA = '1ecd028177667cb2412df83d3a65252c064b0b299ccb3e5cd3105d55cd70acee'
REUSED_AUDIO_SHA = '07d582bf8eb888424bb64939c2f469f4dc0e9536e6b58acc5c51fbaed307928e'
FLOOR_RECEIPT_SHA = '8fc36d10be806201c97de88232fc0f041288a7e8f2d879486f1ac961266f64b1'
FLOOR_SOURCE_SHA = 'aed69b0fe5f39de00bd3871a5361f4b8d887e9ba9753302546dcc0cb97e109c3'
PALACE_SHA = '185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8'
SOURCE_PINS = dict(SOURCES, **{
    'settings_sets_heralds.bytes': (399607,
        '64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a', 398)})
CONFIGURATION_HASHES = {name: pin[1] for name, pin in sorted(SOURCE_PINS.items())}
CONTEXT = dict(gender='Male', floor='Stone', stageName='SF3_Palace_Exterior.glb',
    stageSHA256=PALACE_SHA, floorSourceSHA256=FLOOR_SOURCE_SHA)
PCM_FIELDS = ('name', 'bytes', 'sha256', 'pcmSHA256', 'sampleRate', 'channels',
              'sampleFrames', 'sampleWidth')
SOURCE_FIELDS = ('sourcePath', 'sourceName', 'sourcePathID', 'sourceBundle',
                 'sourceBundleSHA256', 'sourceObjectSHA256', 'encodedSHA256', 'encodedBytes')
NEW_PATHS = {PREFIX + f'whoosh/light/8_short_whooshes_of_light_weapon_v{v}_bip.wav'
             for v in (6, 10, 16, 17, 21)} | {
    PREFIX + 'step/stone/9_footsteps_stone_surface_v25.wav'}
PIN_FIELDS = dict(sourceMatchProfileSHA256=MATCH_SHA, sourcePhysicalProfileSHA256=PROFILE_SHA,
    characterSHA256=CHARACTER_SHA, sourceNamedSHA256=NAMED_SHA, sourceReceiptSHA256=RECEIPT_SHA,
    sourceCatalogSHA256=CATALOG_SHA, sourceExistingAudioManifestSHA256=EXISTING_AUDIO_SHA,
    sourceReusedAudioManifestSHA256=REUSED_AUDIO_SHA, sourceDecodedArchiveSHA256=ARCHIVE_PIN[1],
    sourceAnimationSplitSHA256=SPLIT_SHA, sourceNativeSchemaSHA256=SCHEMA_PIN[1],
    sourceFloorReceiptSHA256=FLOOR_RECEIPT_SHA)


def original_configurations(splits_raw, schema_raw):
    """Re-read all seven source pages through the authenticated native schema."""
    projection = AnimationProjection(schema_raw)
    with ZipFile(io.BytesIO(pinned(splits_raw, ARCHIVE_PIN, 'animation archive'))) as outer:
        split = member(outer, SPLIT, 17_000_000)
    require(sha(split) == SPLIT_SHA, 'Original animation split differs')
    result = {}
    with ZipFile(io.BytesIO(split)) as archive:
        for name, (size, digest, count) in SOURCE_PINS.items():
            raw = pinned(member(archive, name, 1_000_000), (size, digest), name)
            storage = Storage(raw)
            require(storage.pos == len(raw), 'Original animation page has trailing bytes')
            rows = storage.value(storage.root)
            require(type(rows) is list and len(rows) == count, 'Original animation count differs')
            for index, row in enumerate(rows):
                value = projection.named(row)
                require(typed(row) == typed(projection.unnamed(value)), 'Lossy native field projection')
                result[name, index] = value
    return result


def read_inputs(args):
    profile = json.loads(checked(args.profile, MATCH_SHA, 24_000_000))
    physical = json.loads(checked(args.physical_profile, PROFILE_SHA, 24_000_000))
    named = json.loads(checked(args.named, NAMED_SHA, 4_000_000))
    require(profile['schema'] == 'serpent-match-integration-candidate-v1'
            and profile['id'] == physical['id'] == 'liu_serpent'
            and profile['hero'] == physical['hero'] == 'liu'
            and profile['sha256'] == physical['sha256'] == CHARACTER_SHA
            and len(profile['clips']) == len(physical['clips']) == 66,
            'Expected the authenticated D13 body and physical profile')
    require(all(profile.get(k) == v for k, v in physical.items()
                if k not in ('schema', 'recoveryBoundary')), 'Match body/physical rules differ')
    require(profile['serpentBinding']['sourceSHA256'] == RECEIPT_SHA
            and profile['serpentBinding']['schema'] == 'd13-ordinary-match-binding-v1',
            'The match has a different D13 source binding')
    character = checked(args.character, CHARACTER_SHA, 20_000_000)
    require(len(character) == profile['bytes'] == 15_561_412, 'Actual D13 actor size differs')
    raw = original_configurations(checked(args.splits, ARCHIVE_PIN[1], 18_000_000),
                                  checked(args.schema, SCHEMA_PIN[1], 20_000))
    named_rows = {(r['sourceEntry'], r['sourceRecordIndex']): r for r in named['records']}
    require(len(named_rows) == len(named['records']) == 454, 'Original named subset differs')
    for clip in profile['clips']:
        source = clip['sourceConfiguration']; key = source['sourceEntry'], source['sourceRecordIndex']
        require(source['sourceSHA256'] == CONFIGURATION_HASHES.get(key[0])
                and key in raw and typed(source['configuration']) == typed(raw[key]),
                'A body configuration differs from the original typed source: ' + clip['name'])
        if key in named_rows:
            require(typed(source) == typed(named_rows[key]), 'Named D13 configuration differs')
        motion = base64.b64decode(clip['sourceBytesBase64'], validate=True)
        require(0 < len(motion) <= 4_000_000 and sha(motion) == clip['sha256'],
                'Embedded original motion identity differs')
    ordinary = json.loads(checked(args.serpent_audio, EXISTING_AUDIO_SHA, 100_000))
    reused = json.loads(checked(args.erlang_audio, REUSED_AUDIO_SHA, 400_000))
    require(ordinary['schema'] == 'd13-ordinary-source-audio-v1'
            and ordinary['sourceProfileSHA256'] == PROFILE_SHA
            and ordinary['sourceNamedSHA256'] == NAMED_SHA
            and ordinary['sourceReceiptSHA256'] == RECEIPT_SHA
            and ordinary['sourceCatalogSHA256'] == CATALOG_SHA
            and ordinary['characterSHA256'] == CHARACTER_SHA
            and len(ordinary['files']) == 14 and len(ordinary['bodyMarkers']) == 4,
            'Existing dedicated D13 timeline differs')
    require(reused['schema'] == 'd15-recovered-source-audio-v1'
            and reused['originalCatalogSHA256'] == CATALOG_SHA and len(reused['files']) == 82,
            'Reviewed reusable PCM receipt differs')
    floor = json.loads(checked(ROOT/'erlang_palace_floor_audio_receipt_20261115.json',
                               FLOOR_RECEIPT_SHA, 100_000))
    require(floor['floorSource']['sha256'] == FLOOR_SOURCE_SHA
            and floor['stage'] == dict(name=CONTEXT['stageName'], bytes=9_292_540, sha256=PALACE_SHA)
            and floor['sourceFloor'] == 'Stone' and floor['sourceFloorValue'] == 2,
            'Authenticated Palace floor binding differs')
    catalog_raw = checked(args.catalog, CATALOG_SHA, 10_000_000)
    require(len(catalog_raw) == 9_100_700, 'Exact original catalog size differs')
    catalog = [json.loads(line) for line in catalog_raw.splitlines()]
    require(len(catalog) == len({r['file'] for r in catalog}) == 2205, 'Original catalog inventory differs')
    return dict(profile=profile, physical=physical, named=named, ordinary=ordinary,
                reused=reused, catalog=catalog, originalConfigurations=raw)


def choices(identifiers):
    require(type(identifiers) is list and 0 < len(identifiers) <= 32,
            'Unbound source candidate list')
    result = []
    for identifier in identifiers:
        require(type(identifier) is str, 'Source candidate contains an invented weight or value')
        parts = identifier.split('@')
        require(len(parts) == 3 and parts[1] == 'Battle'
                and parts[2] in ('Movement', 'Voice', 'WeaponAndArmor')
                and re.fullmatch(r'[A-Za-z0-9_./-]+', parts[0]) is not None
                and all(p not in ('', '.', '..') for p in parts[0].split('/')),
                'Unbound original Sound route')
        result.append(dict(identifier=identifier, sourcePath=PREFIX+parts[0].lower()+'.wav',
                           bus=parts[1], mixerGroup=parts[2]))
    return result


def source_events(profile, ordinary):
    """Select source routes without altering their clocks, choices or ownership."""
    existing = {(m['clip'], m['sourceMotionSHA256'], m['tick'], m['identifier']): m
                for m in ordinary['bodyMarkers']}
    require(len(existing) == len(ordinary['bodyMarkers']) == 4, 'Existing body marker inventory differs')
    clips, markers, excluded, seen = [], [], [], set()
    for clip in profile['clips']:
        source = clip['sourceConfiguration']; conf = source['configuration']
        first, last, stride = source_window(conf, clip['sourceUncroppedFrames'])
        require((first, last) == (clip['sourceFirstIndex'], clip['sourceLastIndex'])
                and clip['frames'] == last-first+1 and clip['playbackTicks'] == (last-first)*stride
                and clip['sourceEndEventTick'] == source_end_event_tick(conf, clip['sourceUncroppedFrames'])
                and (conf['Looped'] is None or type(conf['Looped']) is bool),
                'Body source crop, end event or clock differs')
        identity = dict(clip=clip['name'], animationAlias=conf['Animation'], sourceMotion=conf['FileName'],
            sourceMotionSHA256=clip['sha256'], sourceEntry=source['sourceEntry'],
            sourceSHA256=source['sourceSHA256'], sourceRecordIndex=source['sourceRecordIndex'])
        clock = dict(sourceFirstIndex=first, sourceFrameStride=stride, sourceFrames=clip['frames'],
            playbackTicks=clip['playbackTicks'], sourceEndEventTick=clip['sourceEndEventTick'],
            looped=conf['Looped'] is True)
        sounds = conf['Sounds'] or []
        clips.append(dict(**identity, **clock, sourceLastIndex=last,
            sourceUncroppedFrames=clip['sourceUncroppedFrames'], sourceSoundRowCount=len(sounds),
            sourceConfigurationSHA256=sha(encoded(conf)),
            roles=[role for role, name in profile['roles'].items() if name == clip['name']]))
        for index, sound in enumerate(sounds):
            require(set(sound) == {'Frame', 'Common', 'Gender', 'Floor'} and type(sound['Frame']) is int,
                    'Source Sound layout or Frame differs')
            frame = max(0, sound['Frame']); tick = (frame-first)*stride
            for route, candidates in (('Common', sound['Common']),
                    ('Male', (sound['Gender'] or {}).get('Male')),
                    ('Floor.Stone', (sound['Floor'] or {}).get('Stone'))):
                if not candidates:
                    continue
                require(0 <= tick <= clip['sourceEndEventTick'] <= clip['playbackTicks'],
                        'Sound lies outside the actual source body clock')
                selected = choices(candidates)
                event = dict(id=f"d13_body_{clip['name']}_{index}_{route.replace('.', '_')}",
                    **identity, **clock, markerIndex=index, route=route, rawFrame=sound['Frame'],
                    sourceFrame=frame, tick=tick, choices=selected)
                matches = [(clip['name'], clip['sha256'], tick, c['identifier']) for c in selected]
                owned = [key for key in matches if key in existing]
                if owned:
                    require(route == 'Common' and len(matches) == len(owned) == 1
                            and owned[0] not in seen, 'Partial or duplicate dedicated marker exclusion')
                    seen.add(owned[0]); old = existing[owned[0]]
                    require(old['alias'] == conf['Animation'], 'Existing body alias differs')
                    excluded.append(dict(**event, existingAction=old['action']))
                else:
                    markers.append(event)
    require(len(clips) == len({c['clip'] for c in clips}) == 66
            and len(markers) == len({m['id'] for m in markers}) == 135
            and len(excluded) == 4 and seen == set(existing), 'Actual body audio scope differs')
    require(Counter(m['route'] for m in markers) == {'Common': 92, 'Male': 36, 'Floor.Stone': 7}
            and sum(len(m['choices']) for m in markers+excluded) == 643,
            'Source route/candidate inventory differs')
    return clips, markers, excluded


def selected_catalog(catalog, wanted):
    result = {}
    for bundle in catalog:
        for entry in bundle['paths']:
            if entry['path'] in wanted:
                require(entry['path'] not in result and entry['file_id'] == 0, 'Ambiguous original AudioClip')
                result[entry['path']] = bundle, entry
    require(set(result) == wanted and len(wanted) == 66, 'Exact 66-file source closure differs')
    return result


def source_pcm(args, inputs, wanted):
    """Reuse sixty WAVs, verifying each against its real source object; decode six."""
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    selected = selected_catalog(inputs['catalog'], wanted)
    reusable = {}
    for key, path, digest in (('reused', args.erlang_audio, REUSED_AUDIO_SHA),
                               ('ordinary', args.serpent_audio, EXISTING_AUDIO_SHA)):
        for row in inputs[key]['files']:
            source = row['sourcePath']
            if source in wanted:
                require(source not in reusable, 'Ambiguous reusable source PCM')
                reusable[source] = row, path.parent, digest
    require(len(reusable) == 60 and wanted-set(reusable) == NEW_PATHS,
            'Expected only six previously undecoded source AudioClips')
    environments, files, payloads = {}, [], {}
    for source in sorted(wanted):
        bundle, entry = selected[source]; bundle_name = bundle['file']
        if bundle_name not in environments:
            paths = [p/bundle_name for p in args.bundle_directory if (p/bundle_name).is_file()]
            require(paths, 'Missing exact local source bundle ' + bundle_name)
            raw = checked(paths[0], bundle['sha256'], 16_000_000)
            require(len(raw) == bundle['bytes'], 'Original source bundle size differs')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                environment = UnityPy.load(raw)
            containers = {p.lower(): ref for p, ref in environment.container.items()}
            require(len(containers) == len(environment.container), 'Ambiguous source container')
            environments[bundle_name] = containers
        require(source in environments[bundle_name], 'Original container path missing')
        pointer = environments[bundle_name][source]; obj = pointer.deref()
        require(obj.type.name == 'AudioClip' and obj.path_id == entry['path_id'], 'Wrong AudioClip identity')
        clip = pointer.read(); resource = clip.m_Resource
        encoded_audio = get_resource_data(resource.m_Source, clip.object_reader.assets_file,
                                         resource.m_Offset, resource.m_Size)
        require(0 < len(encoded_audio) <= 4_000_000, 'Encoded AudioClip exceeds its bound')
        identity = dict(sourcePath=source, sourceName=clip.m_Name, sourcePathID=str(obj.path_id),
            sourceBundle=bundle_name, sourceBundleSHA256=bundle['sha256'],
            sourceObjectSHA256=sha(obj.get_raw_data()), encodedSHA256=sha(encoded_audio),
            encodedBytes=len(encoded_audio))
        reused = source in reusable
        if reused:
            old, directory, digest = reusable[source]
            require(all(old.get(k) == v for k, v in identity.items()),
                    'Reusable PCM belongs to a different original object')
            pcm = checked(directory/old['name'], old['sha256'], 4_000_000)
            properties = pcm_properties(pcm, clip)
            require(all(old.get(k) == v for k, v in properties.items()), 'Reusable PCM samples or format differ')
            name = old['name']; provenance = dict(sourcePCMManifestSHA256=digest)
        else:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                samples = clip.samples
            require(len(samples) == 1, 'Ambiguous original PCM decode')
            original_name, pcm = next(iter(samples.items()))
            require(original_name.endswith('.wav'), 'Decoder did not return original WAV')
            properties = pcm_properties(pcm, clip)
            name = ('SF3SerpentBody_' + re.sub('[^A-Za-z0-9_]+', '_', clip.m_Name)[:70]
                    + '_' + properties['sha256'][:12] + '.wav')
            provenance = dict(decoder='UnityPy 1.25.4 AudioClip.samples; no gain, trim or resampling')
        require(Path(name).name == name and name not in payloads, 'Unsafe or duplicate PCM filename')
        files.append(dict(name=name, **properties, **identity, reusedExistingPCM=reused, provenance=provenance))
        payloads[name] = pcm
    require(len(environments) == 4 and len(files) == 66, 'Source audio bundle/file closure differs')
    return files, payloads


def candidate_statistics(markers):
    sequences = Counter(tuple(c['file'] for c in m['choices']) for m in markers)
    return dict(uniqueOrderedFileLists=len(sequences), totalCandidates=sum(len(s)*n for s, n in sequences.items()),
        maximumCandidates=max(map(len, sequences)),
        candidateCountFrequency={str(k): v for k, v in sorted(Counter(len(m['choices']) for m in markers).items())})


def document(inputs, files):
    clips, markers, excluded = source_events(inputs['profile'], inputs['ordinary'])
    by_path = {f['sourcePath']: f['name'] for f in files}
    require(len(by_path) == len(files) == 66, 'Duplicate or incomplete body PCM inventory')
    for event in markers+excluded:
        for choice in event['choices']:
            require(choice['sourcePath'] in by_path, 'Source candidate has no original PCM')
            choice['file'] = by_path[choice['sourcePath']]
    return dict(schema='d13-body-source-audio-v1', profileID='liu_serpent', **PIN_FIELDS,
        sourceConfigurationVersion='1.46.0.16.16733-prod', sourceAudioVersion='Android Xiaomi 1.45.3',
        sourceConfigurationHashes=CONFIGURATION_HASHES, context=CONTEXT,
        files=files, clips=clips, markers=markers, excludedExistingBodyMarkers=excluded,
        allSourceMarkerCount=139, sourceClipCount=66, sourceChoiceOccurrences=643,
        routeMarkerCounts=dict(Counter(m['route'] for m in markers)),
        reusedPCMFiles=60, newlyDecodedPCMFiles=6, candidateStatistics=candidate_statistics(markers),
        rawFrameRule='max(0, Frame); no subtraction; subtract sourceFirstIndex then multiply MidFrames+1',
        candidateRule='Preserve original ordered entries and multiplicity; source has no explicit weights',
        floorGate='Floor.Stone requires the successfully loaded stage SHA256 in context; otherwise omit Floor markers',
        sourceConfigurationsReverifiedAgainstOriginalBytes=66,
        runtimeAudioBindingCreated=False, normalApplicationPlaybackObserved=False)


def verify_document(value, inputs):
    """Reject self-authorized identity, clock, route, omission and duplicate changes."""
    files = value['files']
    require(value == document(inputs, files), 'Supplemental source markers, pins, context or clocks differ')
    paths = {c['sourcePath'] for m in value['markers']+value['excludedExistingBodyMarkers'] for c in m['choices']}
    selected = selected_catalog(inputs['catalog'], paths)
    require({f['sourcePath'] for f in files} == paths
            and len({f['name'] for f in files}) == 66
            and sum(f['reusedExistingPCM'] is True for f in files) == 60,
            'PCM closure or reuse identity differs')
    reviewed = {f['sourcePath']: f for d in (inputs['ordinary'], inputs['reused']) for f in d['files']}
    for file in files:
        row, entry = selected[file['sourcePath']]
        require(file['sourceBundle'] == row['file'] and file['sourceBundleSHA256'] == row['sha256']
                and file['sourcePathID'] == str(entry['path_id']), 'PCM catalog identity differs')
        require(Path(file['name']).name == file['name'] and file['name'].endswith('.wav')
                and file['sampleWidth'] == 2 and file['channels'] in (1, 2)
                and 8_000 <= file['sampleRate'] <= 192_000
                and 0 < file['sampleFrames'] <= 30*file['sampleRate']
                and 44 <= file['bytes'] <= 4_000_000
                and all(re.fullmatch('[0-9a-f]{64}', file[k]) for k in
                    ('sha256', 'pcmSHA256', 'sourceObjectSHA256', 'encodedSHA256')),
                'PCM metadata or bounded format differs')
        if file['reusedExistingPCM']:
            require(file['sourcePath'] in reviewed
                    and all(file[k] == reviewed[file['sourcePath']][k] for k in PCM_FIELDS+SOURCE_FIELDS),
                    'Previously authenticated source PCM identity differs')
        else:
            require(file['sourcePath'] in NEW_PATHS, 'Unexpected new AudioClip')
    require(value['candidateStatistics'] == dict(uniqueOrderedFileLists=19, totalCandidates=639,
            maximumCandidates=6, candidateCountFrequency={'1': 9, '3': 7, '4': 3, '5': 99, '6': 17}),
            'Original candidate order/multiplicity scope differs')
    return dict(clips=66, markers=135, excluded=4, pcmFiles=66, reusedPCM=60, newlyDecodedPCM=6,
                sourceCandidates=643, supplementalCandidates=639, orderedCandidateLists=19)


def read_manifest(path, inputs):
    value = json.loads(checked(path, MANIFEST_SHA, 500_000))
    verify_document(value, inputs)
    return value


def prepare(args):
    require(not args.output.exists(), 'Use a fresh private supplemental-audio directory')
    inputs = read_inputs(args)
    _, markers, excluded = source_events(inputs['profile'], inputs['ordinary'])
    wanted = {c['sourcePath'] for m in markers+excluded for c in m['choices']}
    files, payloads = source_pcm(args, inputs, wanted)
    value = document(inputs, files); result = verify_document(value, inputs)
    manifest_raw = encoded(value)
    require(sha(manifest_raw) == MANIFEST_SHA, 'Authenticated supplemental manifest bytes differ')
    output = private_output(args.output)
    for name, raw in payloads.items():
        write_new(output/name, raw)
    write_new(output/DOCUMENT_FILE, manifest_raw)
    input_names = ('profile', 'physical_profile', 'character', 'named', 'splits', 'schema',
                   'catalog', 'serpent_audio', 'erlang_audio')
    receipt = dict(schema='d13-body-source-audio-receipt-v1',
        inputs={name: dict(path=str(getattr(args, name).resolve()), **record(getattr(args, name)))
                for name in input_names},
        bundleDirectories=[str(p.resolve()) for p in args.bundle_directory],
        manifest=record(output/DOCUMENT_FILE), counts=result,
        pcmBytes=sum(f['bytes'] for f in files), originalConfigurationsVerified=66,
        originalMotionHashesVerified=66, sourceAudioObjectsVerified=66,
        originalSourceBundleCount=4, newlyDecodedSourceBundleCount=2,
        allReusablePCMBytesUnchanged=True, networkBytes=0, originalSixSoundManifestChanged=False,
        concurrencyObservation=dict(scope='One source clip at one source tick',
            uniqueClipTickPairs=len({(m['clip'], m['tick']) for m in value['markers']}),
            maximumMarkersAtSameClipTick=max(Counter((m['clip'], m['tick']) for m in value['markers']).values()),
            uniqueOrderedCandidateLists=value['candidateStatistics']['uniqueOrderedFileLists'],
            potentialPreparedPlayersPerOwner=value['candidateStatistics']['totalCandidates'],
            potentialPreparedPlayersForTwoOwners=2*value['candidateStatistics']['totalCandidates'],
            crossClipOrOwnerTailOverlapMeasured=False, nativePlayerCostMeasured=False),
        normalApplicationPlaybackObserved=False)
    write_new(output/RECEIPT_FILE, encoded(receipt))
    return dict(output=str(output), manifest=receipt['manifest'], counts=result,
                pcmBytes=receipt['pcmBytes'], networkBytes=0)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'physical-profile', 'character', 'named', 'splits', 'schema',
                 'catalog', 'serpent-audio', 'erlang-audio', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--bundle-directory', type=Path, action='append', required=True)
    print(json.dumps(prepare(parser.parse_args())))
