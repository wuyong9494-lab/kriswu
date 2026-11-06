#!/usr/bin/env python3
"""Stage only verified interface fixtures for a private pre-upload Metal check.

No original images, test bundles or xcresults may be published as artifacts.
Only aggregate test counts and the normal release identity leave the runner.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import struct
import tempfile


def prepare(source, request, output):
    info = plistlib.loads((source/'App/Info.plist').read_bytes())
    required = info.get('ArenaPrivateInterfaceValidationRequired') is True
    if not required:
        return {'required': False}
    expected = request['private_resource_pack']
    pack = source/'App/Resources/arena-original-resources.arenapack'
    assert pack.is_file() and not pack.is_symlink() and pack.stat().st_size == expected['bytes']
    with pack.open('rb') as stream:
        assert hashlib.file_digest(stream,'sha256').hexdigest() == expected['sha256']
    spec = importlib.util.spec_from_file_location('pack_validation',source/'scripts/assets/build_resource_pack.py')
    module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    assert not output.exists(), 'Private fixture directory already exists'
    with pack.open('rb') as stream:
        assert stream.read(len(module.MAGIC)) == module.MAGIC
        length = struct.unpack('<I',stream.read(4))[0]
        assert 0 < length <= module.MAX_HEADER
        raw_manifest = stream.read(length);manifest = json.loads(raw_manifest)
        module.validate_files(manifest)
        assert manifest['id'] == expected['id']
        table = {}; offset = stream.tell()
        for entry in manifest['files']:
            table[entry['path']] = (entry,offset);offset += entry['bytes']
        assert offset == pack.stat().st_size
        selected = set()
        def read(path, kind):
            entry, offset = table[path]
            assert entry['kind'] == kind
            stream.seek(offset);data = stream.read(entry['bytes'])
            assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            selected.add(path)
            return data
        def scene(path):
            document = json.loads(read(path,'data'))
            assert document['schemaVersion'] == 1
            for texture in document['textures']:
                payload = read(texture['file'],'image')
                assert hashlib.sha256(payload).hexdigest() == texture['sha256']
                assert texture['alphaEncoding'] == 'straight'
            return document
        interface = scene(manifest['interfaceSceneFile'])
        bindings = json.loads(read(manifest['interfaceBindingsFile'],'data'))
        assert bindings['sourceSCSHA256'] == interface['sourceSCSHA256']
        read(manifest['interfaceLocalizationFile'],'data')
        assert len(manifest['themes']) == 8
        for theme in manifest['themes']:
            document = scene(theme['sceneFile'])
            assert document['exports'][theme['sceneExport']]['status'] == 'ready'
            assert document['sourceRect'] == theme['sceneSourceRect'] == [-512,-288,512,288]
            read(theme['backgroundFile'],'image')
        assert len(manifest['fonts']) == 4
        for font in manifest['fonts']:
            read(font['file'],'font')
        output.parent.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.arena-validation-',dir=output.parent) as folder:
            staging = Path(folder)/'ArenaPrivateValidation';staging.mkdir()
            (staging/'manifest.json').write_bytes(raw_manifest)
            for path in sorted(selected):
                entry, offset = table[path];stream.seek(offset);data = stream.read(entry['bytes'])
                assert hashlib.sha256(data).hexdigest() == entry['sha256']
                destination=staging/path;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(data)
            staging.replace(output)
    return {'required':True,'themes':8,'controls':12,'files':len(selected)}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--request',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=prepare(args.source,json.loads(args.request.read_text()),args.output)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'],'a') as out:
            out.write('required='+str(result['required']).lower()+'\n')
    print(json.dumps(result))
