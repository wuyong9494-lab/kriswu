#!/usr/bin/env python3
"""Prepare Wu's original Palace Stone sounds without re-decoding prior PCM.

The original SceneConfig and native enum select Stone. Every admitted actor
configuration is inspected; Floor alternatives and their duplicate weighting
retain the independent native sound Frame origin. No network or keys are used.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stderr, redirect_stdout
import copy
import io
import json
from pathlib import Path
import re
import struct
from zipfile import ZipFile

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from erlang_source_profile import SETTINGS_SHA, source_window
from prepare_erlang_source_audio import CATALOG_SHA, PREFIX, pcm_properties
from prepare_erlang_ordinary_audio import THROWS
from prepare_pangu_source_audio_inputs import (ANIMATION_FIELDS, named_sound,
    SETTINGS_VALUES_SHA256, SETTINGS_VALUES_BYTES, SETTINGS_SOURCE_SHA256)
from sun_triad_assets import private_output, require

PALACE_BUNDLE = '02b589a405ebe8b7a25d13d1b51263ae.bin'
PALACE_SHA = '25dc8fcefe7b7fe19cb8455f9f6931cb6dbe3f3859638a28794c3920fdb505ef'
SCENE_OBJECT_SHA = '655a58963cb540a7547143fa8ccbb6a3d58601c358a279f66c7e179b15263b76'
METADATA_SHA = '12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c'
STAGE_SHA = '185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8'
HERALDS_VALUES_SHA = '1090a2ce84d6e80b955a2c2167b3bb9f360ec0c74f2367653ee6379c283d8138'
HERALDS_SOURCE_SHA = '64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a'
PCM_RECEIPT_SHA = 'b1557aafc28213d6e2ed9aa975473c2649b94e48a10ced20da07bce6eab43bef'
SECTIONS = ('stringLiteral stringLiteralData string events properties methods '
    'parameterDefaultValues fieldDefaultValues fieldAndParameterDefaultValueData '
    'fieldMarshaledSizes parameters fields genericParameters genericParameterConstraints '
    'genericContainers nestedTypes interfaces vtableMethods interfaceOffsets typeDefinitions '
    'images assemblies fieldRefs referencedAssemblies attributeData attributeDataRange '
    'unresolvedVirtualCallParameterTypes unresolvedVirtualCallParameterRanges '
    'windowsRuntimeTypeNames windowsRuntimeStrings exportedTypeDefinitions').split()


def palace_source_proof(bundle_raw, metadata_raw):
    import UnityPy
    require(len(bundle_raw) == 9_256_159 and sha(bundle_raw) == PALACE_SHA,
            'Original Palace prefab bundle differs')
    require(len(metadata_raw) == 27_877_556 and sha(metadata_raw) == METADATA_SHA,
            'Original native metadata differs')
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        env = UnityPy.load(bundle_raw)
        objects = {o.path_id: o for o in env.objects}
        obj = objects[-8058892632017654769]
        tree = obj.read_typetree()
        game_object = objects[tree['m_GameObject']['m_PathID']].read_typetree()
        script = objects[tree['m_Script']['m_PathID']].read_typetree()
    require(obj.type.name == 'MonoBehaviour' and len(obj.get_raw_data()) == 104
            and sha(obj.get_raw_data()) == SCENE_OBJECT_SHA
            and tree['m_GameObject']['m_FileID'] == tree['m_Script']['m_FileID'] == 0
            and game_object['m_Name'] == 'palace_exterior_raid'
            and script['m_ClassName'] == 'SceneConfig' and script['m_Namespace'] == 'Common.Location',
            'Original Palace SceneConfig identity differs')
    floor = tree['FloorSurfaceSettings']
    require(floor == dict(surfaceY=0.0, floorSurface=[dict(startX=-2000.0, endX=2000.0, surfaceType=2)]),
            'Original Palace floor range or enum differs')
    require(struct.unpack_from('<II', metadata_raw) == (0xFAB11BAF, 39), 'Native metadata format differs')
    sections = {name: struct.unpack_from('<III', metadata_raw, 8 + 12*i) for i, name in enumerate(SECTIONS)}
    def row(section, index, size):
        start, count_bytes, count = sections[section]
        require(count_bytes == count*size and 0 <= index < count, 'Native metadata table bounds differ')
        return metadata_raw[start + index*size:start + (index+1)*size]
    def string(index):
        start, count, _ = sections['string']
        require(0 <= index < count, 'Native metadata string bounds differ')
        end = metadata_raw.index(b'\0', start+index, start+count)
        return metadata_raw[start+index:end].decode('utf-8')
    field_name, field_type, _ = struct.unpack('<iII', row('fields', 24302, 12))
    require(string(field_name) == 'surfaceType' and field_type == 45761, 'FloorSurface enum field differs')
    enum_type = row('typeDefinitions', 6544, 82)
    require(string(struct.unpack_from('<i', enum_type)[0]) == 'ECCNNOBOEAD'
            and struct.unpack_from('<I', enum_type, 8)[0] == 45760, 'Original floor enum type differs')
    defaults = {}
    for index in range(sections['fieldDefaultValues'][2]):
        field, type_index, offset = struct.unpack('<iii', row('fieldDefaultValues', index, 12))
        if 24992 <= field <= 24996:
            require(field not in defaults and type_index == 51738, 'Ambiguous native floor enum default')
            defaults[field] = offset
    require(defaults == dict(zip(range(24992, 24997), range(27752, 27757))), 'Native floor enum offsets differ')
    enum_values = []
    for field, expected in zip(range(24992, 24997), ['None', 'Ground', 'Stone', 'Metal', 'Wood']):
        name, _, _ = struct.unpack('<iII', row('fields', field, 12))
        raw = metadata_raw[sections['fieldAndParameterDefaultValueData'][0] + defaults[field]]
        value = (raw >> 1) ^ -(raw & 1)  # Source metadata compressed signed integer.
        require(string(name) == expected and value == field-24992 and raw == 2*value,
                'Original floor enum value differs')
        enum_values.append(dict(fieldIndex=field, name=expected, dataOffset=defaults[field], encodedByte=raw, value=value))
    return dict(schemaVersion=1, floor='Stone', sourceFloorValue=2,
        scene=dict(bundle=PALACE_BUNDLE, bytes=len(bundle_raw), sha256=PALACE_SHA,
            pathID=str(obj.path_id), objectBytes=104, objectSHA256=SCENE_OBJECT_SHA,
            className='Common.Location.SceneConfig', gameObject='palace_exterior_raid', settings=floor),
        nativeMetadata=dict(bytes=len(metadata_raw), sha256=METADATA_SHA, format=39,
            floorSurfaceTypeIndex=6427, surfaceTypeFieldIndex=24302, surfaceTypeIndex=45761,
            enumTypeIndex=6544, enumName='ECCNNOBOEAD', enumByvalTypeIndex=45760, values=enum_values),
        applicationStage=dict(name='SF3_Palace_Exterior.glb', bytes=9_292_540, sha256=STAGE_SHA),
        scope='Only the authenticated Palace stage; no floor inference for other stages.')


def source_events(profile, settings, dynasty, heralds):
    by_record = {(r['sourceEntry'], r['sourceRecordIndex']): r for r in settings['records']}
    require(len(by_record) == len(settings['records']), 'Ambiguous original named configuration')
    for index in (248, 249):
        values = dynasty[index]
        require(len(values) == len(ANIMATION_FIELDS), 'Original paired animation schema differs')
        c = dict(zip(ANIMATION_FIELDS, copy.deepcopy(values)))
        c['Sounds'] = None if c['Sounds'] is None else [named_sound(v) for v in c['Sounds']]
        by_record['settings_sets_dynasty.bytes', index] = dict(sourceEntry='settings_sets_dynasty.bytes',
            sourceRecordIndex=index, sourceSHA256=SETTINGS_SOURCE_SHA256, configuration=c)
    roles = {name: role for role, name in profile['roles'].items()}
    require(len(roles) == len(profile['roles']), 'Ambiguous actor role')
    events, scope, configurations = [], [], {}
    for clip in profile['clips']:
        role = roles.get(clip['name'])
        source = clip.get('sourceConfiguration')
        if source is None:
            require(role in THROWS, 'Unidentified source motion')
            entry, index, alias = THROWS[role]
            source = by_record[entry, index]
            require(source['configuration']['Animation'] == alias, 'Original paired alias differs')
        elif source['sourceEntry'] == 'settings_sets_heralds.bytes':
            # The newly appended source root reactions have no sound markers.
            index = source['sourceRecordIndex']
            require(index in (102, 103, 104) and source['sourceSHA256'] == HERALDS_SOURCE_SHA,
                    'Unreviewed root reaction configuration')
            original = dict(zip(ANIMATION_FIELDS, heralds[index]))
            require(source['configuration']['Sounds'] is original['Sounds'] is None
                    and all(source['configuration'][k] == original[k] for k in
                        ('Animation', 'FileName', 'FirstFrame', 'EndFrame', 'MidFrames')),
                    'Silent original root reaction or clock differs')
        else:
            require(source == by_record.get((source['sourceEntry'], source['sourceRecordIndex'])),
                    'Actor configuration differs from its original record')
        c = source['configuration']
        first, last, stride = source_window(c, clip['sourceUncroppedFrames'])
        require((first, last) == (clip['sourceFirstIndex'], clip['sourceLastIndex'])
                and clip['frames'] == last-first+1 and clip['playbackTicks'] == (last-first)*stride,
                'Floor sound would use another source crop or clock')
        groups = 0
        for index, sound in enumerate(c['Sounds'] or []):
            alternatives = (sound['Floor'] or {}).get('Stone')
            if not alternatives:
                continue
            raw_frame = sound['Frame']
            require(type(raw_frame) is int and role is not None, 'Unbound Floor sound frame or role')
            frame = max(0, raw_frame); tick = (frame-first)*stride
            require(0 <= tick <= clip['playbackTicks'], 'Original Floor marker is outside its admitted window')
            choices = []
            for identifier in alternatives:
                fields = identifier.split('@')
                require(len(fields) == 3 and fields[1] == 'Battle' and fields[2] in ('Movement', 'WeaponAndArmor')
                        and re.fullmatch(r'[A-Za-z0-9_./-]+', fields[0]) is not None
                        and all(p not in ('', '.', '..') for p in fields[0].split('/')), 'Unbound Floor sound route')
                choices.append(dict(identifier=identifier, sourcePath=PREFIX+fields[0].lower()+'.wav',
                    bus=fields[1], mixerGroup=fields[2]))
            entry = source['sourceEntry']; configurations[entry] = source['sourceSHA256']
            events.append(dict(id=f"floor_{sha(entry.encode())[:8]}_{source['sourceRecordIndex']}_{index}_Stone",
                animationAlias=c['Animation'], sourceMotion=c['FileName'], sourceEntry=entry,
                sourceSHA256=source['sourceSHA256'], sourceRecordIndex=source['sourceRecordIndex'],
                markerIndex=index, route='Floor.Stone', rawFrame=raw_frame, sourceFrame=frame,
                sourceFirstIndex=first, sourceFrameStride=stride, sourceTick=tick, sourceFrames=clip['frames'],
                duration=clip['playbackTicks'], clip=clip['name'], role=role, sourceMotionSHA256=clip['sha256'],
                choices=choices))
            groups += 1
        scope.append(dict(role=role, clip=clip['name'], animationAlias=c['Animation'], sourceEntry=source['sourceEntry'],
            sourceRecordIndex=source['sourceRecordIndex'], floorStoneGroups=groups,
            fileName=c['FileName'], sourceBundle=clip['bundle'], sourcePathID=clip['sourcePathID']))
    require(len(scope) == 62 and len(events) == len({e['id'] for e in events}) == 21,
            'Actual actor Floor marker inventory differs')
    return events, scope, configurations


def prepare(args):
    import UnityPy
    from UnityPy.helpers.ResourceReader import get_resource_data
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    profile = json.loads(checked(args.profile, args.profile_sha256, 48_000_000))
    require(profile['id'] == profile['hero'] == 'wuyong_erlang', 'Expected the admitted original Wu actor')
    settings = json.loads(checked(args.settings, SETTINGS_SHA, 4_000_000))
    dynasty = json.loads(checked(args.dynasty_values, SETTINGS_VALUES_SHA256, SETTINGS_VALUES_BYTES))
    heralds = json.loads(checked(args.heralds_values, HERALDS_VALUES_SHA, 1_500_000))
    events, scope, configurations = source_events(profile, settings, dynasty, heralds)
    wanted = {choice['sourcePath'] for event in events for choice in event['choices']}
    require(len(wanted) == 7, 'Original Floor sound path inventory differs')
    with ZipFile(args.catalog_archive) as archive:
        catalog = archive.read('research/android_bundle_catalog.jsonl')
        palace = archive.read('bundles/'+PALACE_BUNDLE)
    require(len(catalog) == 9_100_700 and sha(catalog) == CATALOG_SHA, 'Original complete catalog differs')
    proof = palace_source_proof(palace, checked(args.native_metadata, METADATA_SHA, 28_000_000))
    require(len(checked(args.stage, STAGE_SHA, 10_000_000)) == 9_292_540, 'Authenticated application stage differs')
    rows = [json.loads(line) for line in catalog.splitlines()]
    by_path = {}
    for bundle in rows:
        for item in bundle['paths']:
            path = item['path'].lower()
            if path in wanted:
                require(path not in by_path and item['file_id'] == 0, 'Ambiguous original Floor AudioClip')
                by_path[path] = bundle, item
    require(set(by_path) == wanted, 'Floor sound is absent from the reviewed source catalog')
    reviewed = json.loads(checked(args.reviewed_pcm, PCM_RECEIPT_SHA, 1_000_000))
    reused = {f['sourcePath']: f for f in reviewed['files'] if f['sourcePath'] in wanted}
    require(len(reused) == 5, 'Expected five existing original Floor PCM inputs')
    require(not args.output.exists(), 'Refuse to replace prepared original PCM')
    output = private_output(args.output)
    environments, files = {}, []
    for path in sorted(wanted):
        bundle, item = by_path[path]; name = bundle['file']
        if name not in environments:
            sources = [p/name for p in args.bundle_directory if (p/name).is_file()]
            require(sources, 'Exact original Floor sound bundle is not local: '+name)
            raw = checked(sources[0], bundle['sha256'], 16_000_000)
            require(len(raw) == bundle['bytes'], 'Original sound bundle size differs')
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                env = UnityPy.load(raw)
            containers = {p.lower(): ref for p, ref in env.container.items()}
            require(len(containers) == len(env.container), 'Duplicate source container path')
            environments[name] = containers
        pointer = environments[name][path]; obj = pointer.deref(); clip = pointer.read(); resource = clip.m_Resource
        require(obj.type.name == 'AudioClip' and obj.path_id == item['path_id'], 'Original AudioClip identity differs')
        original = get_resource_data(resource.m_Source, clip.object_reader.assets_file, resource.m_Offset, resource.m_Size)
        require(0 < len(original) <= 4_000_000, 'Encoded sound exceeds its bound')
        identity = dict(sourcePath=path, sourceName=clip.m_Name, sourcePathID=str(obj.path_id),
            sourceBundle=name, sourceBundleSHA256=bundle['sha256'], sourceObjectSHA256=sha(obj.get_raw_data()),
            encodedSHA256=sha(original), encodedBytes=len(original))
        if path in reused:
            old = reused[path]
            require(all(old.get(k) == v for k, v in identity.items()), 'Existing PCM belongs to another source object')
            pcm = checked(args.reviewed_pcm.parent/old['name'], old['sha256'], 4_000_000)
            properties = pcm_properties(pcm, clip)
            require(all(old[k] == properties[k] for k in ('bytes', 'sampleRate', 'channels', 'sampleFrames', 'sampleWidth')),
                    'Existing PCM format differs')
            filename = old['name']; provenance = record(args.reviewed_pcm)
        else:
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                samples = clip.samples
            require(len(samples) == 1, 'Original decoder returned ambiguous PCM')
            original_name, pcm = next(iter(samples.items()))
            require(original_name.endswith('.wav'), 'Original decoder did not return WAV')
            properties = pcm_properties(pcm, clip)
            filename = 'SF3Erlang_'+re.sub('[^A-Za-z0-9_]+', '_', clip.m_Name)[:70]+'_'+properties['sha256'][:12]+'.wav'
            provenance = dict(decoder='UnityPy AudioClip.samples; original frequency/channels; no gain or resampling')
        require(Path(filename).name == filename, 'Unsafe PCM basename')
        write_new(output/filename, pcm)
        result = dict(name=filename, **properties, **identity, reusedExistingPCM=path in reused, provenance=provenance)
        write_new(output/(filename+'.source-private.json'), encoded(result)); files.append(result)
        print(json.dumps(dict(sourceName=clip.m_Name, reusedExistingPCM=path in reused,
            bytes=properties['bytes'], sha256=properties['sha256'])), flush=True)
    by_path = {f['sourcePath']: f['name'] for f in files}
    for event in events:
        for choice in event['choices']:
            choice['file'] = by_path[choice['sourcePath']]
    proof_raw = encoded(proof)
    write_new(output/'erlang-palace-floor-source.json', proof_raw)
    document = dict(schemaVersion=1, ownerProfileID='wuyong_erlang', catalogSHA256=CATALOG_SHA,
        floor='Stone', floorSourceSHA256=sha(proof_raw), floorSource=proof, files=files, events=events,
        sourceConfigurationHashes=configurations,
        scope='All 21 Floor.Stone marker groups in the authenticated 62-clip actor. Other floor types are not selected.',
        rawFrameRule='max(0, Frame), no subtraction; exact crop origin and native MidFrames+1 retained',
        runtimeAudioBindingCreated=False, normalApplicationPlaybackObserved=False)
    write_new(output/'SF3_Erlang_Floor_Audio.json', encoded(document))
    receipt = dict(profile=record(args.profile), sourceManifest=record(output/'SF3_Erlang_Floor_Audio.json'),
        floorSource=record(output/'erlang-palace-floor-source.json'), originalActorScope=scope,
        inputs=[record(args.settings), record(args.dynasty_values), record(args.heralds_values), record(args.reviewed_pcm)],
        fileCount=7, markerGroups=21, reusedPCM=5, newlyDecodedPCM=2,
        prior75PCMDecodedAgain=False, nativeApplicationPlayed=False)
    write_new(output/'erlang-floor-audio-provenance-private.json', encoded(receipt))
    return {k:v for k,v in receipt.items() if k not in ('inputs', 'originalActorScope')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'settings', 'dynasty-values', 'heralds-values', 'catalog-archive',
                 'native-metadata', 'stage', 'reviewed-pcm', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--profile-sha256', required=True)
    parser.add_argument('--bundle-directory', type=Path, action='append', required=True)
    print(json.dumps(prepare(parser.parse_args())))


if __name__ == '__main__':
    main()
