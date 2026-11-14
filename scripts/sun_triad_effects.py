#!/usr/bin/env python3
"""Extract the verified original H17 audio and effect inventory privately.

No network or source asset decryption is performed. Output stays outside the
repository; it is an integration candidate, not an assertion of event binding.
The WAVs retain the source sample rate and channels without gain or trimming.
"""
from __future__ import annotations
import argparse, base64, gzip, hashlib, io, json, math, re, warnings, wave
from pathlib import Path
from sun_triad_assets import private_output, write_private, require

AUDIO = ('f181ae0b66a3473ba34ca6809c7ca0f5.bin',
         '2c8e156d9f50d9a85438e07d83cfdde7fd00a861d7da5b801a31c522d6fa2196')
EFFECTS = ('528f39092b1ff478b8be70b35866e99d.bin',
           'f8623b6aeff0dbdee43818437043096ab5afb217e7564c3298f182e420e9f9d7')
SOUL = ('46807643d37ca8b0fece25171ad27736.bin',
        '23b7c6a79c507285134495e42300402cd58139c64682e0d88af93dfa369407b0')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked_load(models, identity):
    import UnityPy
    raw = (models / identity[0]).read_bytes()
    require(sha(raw) == identity[1], 'Source effect bundle identity mismatch')
    return UnityPy.load(raw)


def audio_inventory(models, output):
    from UnityPy.helpers.ResourceReader import get_resource_data
    environment = checked_load(models, AUDIO)
    paths = {p.path_id: name for name, p in environment.container.items()}
    records = []
    for obj in environment.objects:
        if obj.type.name != 'AudioClip':
            continue
        clip = obj.read()
        require(re.fullmatch(r'h17_[a-z0-9_]+', clip.m_Name), 'Unexpected original audio basename')
        samples = clip.samples
        require(len(samples) == 1, 'Source audio clip yielded an ambiguous sample set')
        original_name, data = next(iter(samples.items()))
        require(original_name == clip.m_Name + '.wav', 'Original audio decoder did not produce WAV')
        with wave.open(io.BytesIO(data), 'rb') as decoded:
            channels, frequency, frames, width = (decoded.getnchannels(), decoded.getframerate(),
                                                  decoded.getnframes(), decoded.getsampwidth())
            require(decoded.getcomptype() == 'NONE' and width == 2, 'Expected unmodified PCM16 decode')
        require(channels == clip.m_Channels and frequency == clip.m_Frequency,
                'Source audio format changed during decoding')
        require(abs(frames / frequency - clip.m_Length) < 2 / frequency,
                'Source audio duration changed during decoding')
        name = 'SF3WE_' + original_name
        write_private(output / name, data)
        resource = clip.m_Resource
        encoded = get_resource_data(resource.m_Source, clip.object_reader.assets_file,
                                    resource.m_Offset, resource.m_Size)
        records.append(dict(name=name, bytes=len(data), sha256=sha(data), sourceName=clip.m_Name,
                            sourcePath=paths[obj.path_id], sourcePathID=str(obj.path_id),
                            sourceCompression=clip.m_CompressionFormat,
                            encodedBytes=len(encoded), encodedSHA256=sha(encoded),
                            sampleRate=frequency, channels=channels, sampleFrames=frames,
                            sampleWidth=width, durationSeconds=frames / frequency))
    require(len(records) == 33, 'Original H17 audio clip inventory changed')
    records.sort(key=lambda x: x['name'])
    document = dict(version=1, sourceBundle=AUDIO[0], sourceBundleSHA256=AUDIO[1],
                    decoding='UnityPy 1.25.4 fmod_toolkit to PCM16; no gain, resampling, or trimming',
                    bindingStatus='Source names and identities only; exact event markers supplied separately',
                    files=records, totalBytes=sum(x['bytes'] for x in records))
    write_private(output / 'h17-audio-inventory.json', json.dumps(document, indent=2).encode())
    return document


def serializable(value):
    if isinstance(value, bytes):
        return dict(bytesBase64=base64.b64encode(value).decode())
    if isinstance(value, float) and not math.isfinite(value):
        return dict(nonfiniteSourceValue=repr(value))
    if isinstance(value, dict):
        return {str(k): serializable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [serializable(x) for x in value]
    return value


def effect_inventory(models, output):
    environment = checked_load(models, EFFECTS)
    entries = []
    for path, pointer in sorted(environment.container.items(), key=lambda item: item[0]):
        if not path.endswith('.prefab'):
            continue
        root = pointer.read()
        transform = [x.component.read() for x in root.m_Component
                     if x.component.deref().type.name == 'Transform']
        require(len(transform) == 1, 'Original effect prefab root is ambiguous')
        rows, counts, seen = [], {}, set()
        def walk(value, parent):
            require(value.object_reader.path_id not in seen, 'Original effect tree cycle')
            seen.add(value.object_reader.path_id)
            game_object = value.m_GameObject.read()
            refs = []
            for component in game_object.m_Component:
                obj = component.component.deref()
                counts[obj.type.name] = counts.get(obj.type.name, 0) + 1
                refs.append(dict(type=obj.type.name, pathID=str(obj.path_id)))
            rows.append(dict(name=game_object.m_Name, pathID=str(value.object_reader.path_id),
                parentPathID=parent,
                position=[value.m_LocalPosition.x, value.m_LocalPosition.y, value.m_LocalPosition.z],
                rotation=[value.m_LocalRotation.x, value.m_LocalRotation.y, value.m_LocalRotation.z, value.m_LocalRotation.w],
                scale=[value.m_LocalScale.x, value.m_LocalScale.y, value.m_LocalScale.z], components=refs))
            for child in value.m_Children:
                walk(child.read(), str(value.object_reader.path_id))
        walk(transform[0], None)
        entries.append(dict(sourcePath=path, sourcePathID=str(pointer.path_id), rootName=root.m_Name,
                            transforms=rows, componentCounts=counts))
    require(bool(entries), 'No original H17 effect prefabs')
    source_objects = []
    for obj in environment.objects:
        if obj.type.name in {'ParticleSystem', 'ParticleSystemRenderer', 'MeshRenderer',
                            'Material', 'MonoBehaviour', 'ParticleSystemForceField'}:
            source_objects.append(dict(type=obj.type.name, pathID=str(obj.path_id),
                                       data=serializable(obj.read_typetree())))
    source_raw = json.dumps(source_objects, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(source_raw, mtime=0)
    write_private(output / 'h17-unity-effects-source.json.gz', compressed)
    document = dict(version=1, sourceBundle=EFFECTS[0], sourceBundleSHA256=EFFECTS[1],
                    entries=entries, particleSourceFile='h17-unity-effects-source.json.gz',
                    particleSourceBytes=len(compressed), particleSourceSHA256=sha(compressed),
                    rendererStatus='Original source parameters retained; no generic effect substitution')
    write_private(output / 'h17-effects-inventory.json', json.dumps(document, indent=2).encode())
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    audio = audio_inventory(args.models, output)
    effects = effect_inventory(args.models, output)
    print(json.dumps(dict(audioClips=len(audio['files']), audioBytes=audio['totalBytes'],
                          effectPrefabs=len(effects['entries']))))


if __name__ == '__main__':
    main()
