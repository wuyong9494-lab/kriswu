#!/usr/bin/env python3
"""Add verified data to a private pack without dropping any existing payload.

The original is read-only. The replacement is published locally only after a
second complete archive verification. This command does not upload anything.
"""
import argparse
import copy
import gzip
import hashlib
import json
import os
import struct
from pathlib import Path
from build_resource_pack import MAGIC, MAX_HEADER, VERSION_LIMITS, validate_files, verify


def extend(original, additions, root, output, pack_id):
    assert original.resolve() != output.resolve(), 'Never overwrite the source pack'
    root = root.resolve()
    spec = json.loads(additions.read_text())
    assert set(spec) <= {'files', 'fonts', 'interfaceSceneFile', 'interfaceBindingsFile', 'interfaceLocalizationFile', 'themeScenes'}, 'Unreviewed manifest field'
    opener = gzip.open if original.suffix == '.gz' else open
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.partial')
    try:
        with opener(original, 'rb') as source:
            assert source.read(len(MAGIC)) == MAGIC
            length = struct.unpack('<I', source.read(4))[0]
            assert 0 < length <= MAX_HEADER
            previous = json.loads(source.read(length))
            validate_files(previous)
            manifest = copy.deepcopy(previous)
            manifest['id'] = pack_id
            manifest['schemaVersion'] = 2
            manifest['files'] += spec['files']
            manifest['fonts'] = manifest.get('fonts', []) + spec.get('fonts', [])
            for key in ['interfaceSceneFile', 'interfaceBindingsFile', 'interfaceLocalizationFile']:
                if key in spec:
                    assert key not in previous or previous[key] == spec[key], 'Cannot replace existing interface metadata'
                    manifest[key] = spec[key]
            # Add timeline bindings to existing themes without replacing their
            # stills, IDs, music or ordering. Existing bindings are immutable.
            theme_scenes = spec.get('themeScenes', {})
            assert isinstance(theme_scenes, dict)
            theme_ids = {theme['id'] for theme in manifest['themes']}
            assert set(theme_scenes) <= theme_ids, 'Unknown theme binding'
            for theme in manifest['themes']:
                if theme['id'] not in theme_scenes:
                    continue
                scene = theme_scenes[theme['id']]
                assert set(scene) == {'sceneFile', 'sceneExport', 'sceneSourceRect'}, 'Unreviewed theme scene field'
                for key, value in scene.items():
                    assert key not in theme or theme[key] == value, 'Cannot replace existing theme metadata'
                    theme[key] = value
            assert len({f['id'] for f in manifest['fonts']}) == len(manifest['fonts'])
            validate_files(manifest)
            header = json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()
            assert len(header) <= VERSION_LIMITS[2]['header']
            with temporary.open('wb') as destination:
                destination.write(MAGIC + struct.pack('<I', len(header)) + header)
                def transfer(stream, item):
                    digest = hashlib.sha256()
                    remaining = item['bytes']
                    while remaining:
                        data = stream.read(min(remaining, 1 << 20))
                        assert data, 'Truncated payload: ' + item['path']
                        remaining -= len(data)
                        digest.update(data)
                        destination.write(data)
                    assert digest.hexdigest() == item['sha256'], 'Payload digest: ' + item['path']
                for item in previous['files']:
                    transfer(source, item)
                assert source.read(1) == b'', 'Trailing original payload'
                for item in spec['files']:
                    path = root / item['path']
                    assert path.is_file() and not path.is_symlink() and root in path.resolve().parents
                    assert path.stat().st_size == item['bytes']
                    with path.open('rb') as stream:
                        transfer(stream, item)
                destination.flush()
                os.fsync(destination.fileno())
        result = verify(temporary)
        temporary.replace(output)
        result.update(path=str(output), preserved_files=len(previous['files']), added_files=len(spec['files']))
        return result
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['original', 'additions', 'root', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--pack-id', required=True)
    args = parser.parse_args()
    print(json.dumps(extend(args.original, args.additions, args.root, args.output, args.pack_id), indent=2))
