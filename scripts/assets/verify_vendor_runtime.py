#!/usr/bin/env python3
"""Validate the shipped bundle selection, dependencies and source provenance offline."""
import hashlib
import json
from pathlib import Path
import struct
import wave
from gltf_contract import unsupported_features

ROOT = Path(__file__).resolve().parents[2]

def verify():
    directory = ROOT / 'App/ArenaVendor'
    manifest = json.loads((directory / 'arena-vendor-runtime.json').read_text())
    sources = json.loads((ROOT / 'art/vendor/manifest.json').read_text())
    expected = {p['id'] for p in sources['packs']}
    assert len(expected) == 11
    assert {f['pack'] for f in manifest['files']} == expected, 'Every source pack needs a runtime use'
    assert len({f['file'] for f in manifest['files']}) == len(manifest['files']), 'Resource name collision'
    for entry in manifest['files']:
        path = directory / entry['file']
        data = path.read_bytes()
        assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256'], path
        pack = next(p for p in sources['packs'] if p['id'] == entry['pack'])
        source = next(f for f in pack['files'] if f['path'] == entry['source'])
        assert source['sha256'] == entry['sourceSHA256'], 'Lost source provenance'
        assert entry['usage'], 'Unassigned runtime resource'
        if path.suffix in ('.glb', '.gltf'):
            if path.suffix == '.glb':
                magic, version, length, size, chunk = struct.unpack_from('<4sIIII', data)
                assert magic == b'glTF' and version == 2 and length == len(data) and chunk == 0x4e4f534a
                document = json.loads(data[20:20 + size])
            else:
                document = json.loads(data)
            assert not unsupported_features(document), path
            for item in document.get('buffers', []) + document.get('images', []):
                if 'uri' in item:
                    dependency = directory / item['uri']
                    assert dependency.resolve().is_relative_to(directory.resolve()) and dependency.is_file(), dependency
        elif path.suffix == '.wav':
            with wave.open(str(path)) as audio:
                assert audio.getnchannels() == 1 and audio.getframerate() == 44100 and audio.getsampwidth() == 2
                assert audio.getnframes() > 0
                assert len(audio.readframes(audio.getnframes())) == audio.getnframes() * 2
    assert (directory / 'ArenaVendor-LICENSES.txt').stat().st_size > 0
    print(f'Verified {len(expected)} packs, {len(manifest["files"])} runtime files, complete dependency and source hashes')

if __name__ == '__main__':
    verify()
