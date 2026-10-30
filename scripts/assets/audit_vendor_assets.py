#!/usr/bin/env python3
"""Read-only source integrity/format checks, not iOS visual or performance approval.

Requires the existing ffmpeg and Pillow tools. Does not install or run pack code.
"""
import base64
import collections
import concurrent.futures
import hashlib
import json
import math
import pathlib
import struct
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
from PIL import Image
from gltf_contract import unsupported_features

ROOT = pathlib.Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'art/vendor'
COMPONENTS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
              5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_model(path):
    raw = path.read_bytes()
    binary = None
    if path.suffix == '.glb':
        magic, version, length = struct.unpack_from('<4sII', raw)
        assert magic == b'glTF' and version == 2 and length == len(raw)
        offset, document = 12, None
        while offset < len(raw):
            size, kind = struct.unpack_from('<II', raw, offset)
            assert offset + 8 + size <= len(raw)
            data = raw[offset + 8:offset + 8 + size]
            if kind == 0x4E4F534A:
                document = json.loads(data)
            elif kind == 0x004E4942:
                binary = data
            offset += 8 + size
        assert document is not None
    else:
        document = json.loads(raw)
    assert document['asset']['version'] == '2.0'
    external = []

    def resource(uri):
        if uri.startswith('data:'):
            # Existing Arena importer does not handle data URIs.
            raise ValueError('Embedded data URI needs conversion before Arena import')
        parts = urllib.parse.urlsplit(uri)
        assert not parts.scheme and not parts.netloc
        target = (path.parent / urllib.parse.unquote(parts.path)).resolve()
        assert target.is_relative_to(VENDOR.resolve()) and target.is_file()
        external.append(str(target.relative_to(VENDOR.resolve())))
        return target.read_bytes()

    buffers = [resource(b['uri']) if 'uri' in b else binary for b in document.get('buffers', [])]
    for info, data in zip(document.get('buffers', []), buffers):
        assert data is not None and len(data) >= info['byteLength']
    for image in document.get('images', []):
        if 'uri' in image:
            resource(image['uri'])
    views = document.get('bufferViews', [])
    for view in views:
        assert view.get('byteOffset', 0) + view['byteLength'] <= len(buffers[view['buffer']])
    accessors = []
    for accessor in document.get('accessors', []):
        assert 'sparse' not in accessor, 'Sparse accessor needs a separate importer contract'
        view = views[accessor['bufferView']]
        code, size = COMPONENTS[accessor['componentType']]
        width = WIDTHS[accessor['type']]
        stride = view.get('byteStride', size * width)
        start = accessor.get('byteOffset', 0)
        count = accessor['count']
        assert count >= 0 and stride >= size * width
        assert start + max(0, count - 1) * stride + (size * width if count else 0) <= view['byteLength']
        data = buffers[view['buffer']]
        start += view.get('byteOffset', 0)
        values = [struct.unpack_from('<' + code * width, data, start + i * stride) for i in range(count)]
        assert all(math.isfinite(value) for row in values for value in row)
        accessors.append(values)
    triangles = 0
    for mesh in document.get('meshes', []):
        for primitive in mesh['primitives']:
            positions = accessors[primitive['attributes']['POSITION']]
            indices = accessors[primitive['indices']] if 'indices' in primitive else [(i,) for i in range(len(positions))]
            assert len(indices) % 3 == 0 and all(0 <= row[0] < len(positions) for row in indices)
            triangles += len(indices) // 3
    animations = document.get('animations', [])
    for animation in animations:
        for sampler in animation['samplers']:
            times = accessors[sampler['input']]
            assert times and all(a[0] < b[0] for a, b in zip(times, times[1:]))
    return {'path': str(path.relative_to(VENDOR)), 'triangles': triangles,
            'animations': len(animations), 'externalResources': len(external),
            'unsupportedArenaFeatures': unsupported_features(document)}


def decode_audio(path):
    result = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', str(path),
                             '-f', 'null', '-'], capture_output=True, text=True, timeout=30)
    if result.returncode or result.stderr.strip():
        raise ValueError(f'{path}: {result.stderr[-1200:]}')
    return str(path.relative_to(VENDOR))


def main():
    manifest = json.loads((VENDOR / 'manifest.json').read_text())
    hashes, images, vectors, models, audio = set(), [], [], [], []
    opaque_formats = collections.Counter()
    for pack in manifest['packs']:
        for item in pack['files']:
            path = VENDOR / pack['id'] / item['path']
            raw = path.read_bytes()
            assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
            hashes.add(item['sha256'])
            suffix = path.suffix.lower()
            if suffix in ('.png', '.jpg', '.jpeg'):
                with Image.open(path) as image:
                    image.verify()
                with Image.open(path) as image:
                    image.load()
                    images.append({'path': str(path.relative_to(VENDOR)), 'size': list(image.size)})
            elif suffix == '.svg':
                tree = ET.fromstring(raw)
                for element in tree.iter():
                    assert element.tag.split('}')[-1] not in ('script', 'foreignObject')
                    for key, value in element.attrib.items():
                        assert not key.lower().startswith('on')
                        if key.split('}')[-1] == 'href':
                            assert value.startswith('#'), 'SVG external resource is not allowed'
                vectors.append(str(path.relative_to(VENDOR)))
            elif suffix in ('.glb', '.gltf'):
                models.append(read_model(path))
            elif suffix in ('.ogg', '.wav'):
                audio.append(path)
            elif suffix not in ('.txt', '.md', '.bin'):
                opaque_formats[suffix] += 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        decoded = list(executor.map(decode_audio, audio))
    report = {
        'schemaVersion': 1, 'date': manifest['retrievedAt'], 'fileHashesVerified': manifest['fileCount'],
        'uniqueFileHashes': len(hashes), 'decodedImages': len(images), 'parsedSVGs': len(vectors),
        'decodedAudioFiles': len(decoded), 'checkedGLBOrGLTF': len(models),
        'modelsWithUnsupportedArenaFeatures': sum(bool(m['unsupportedArenaFeatures']) for m in models),
        'animatedSourceModels': {m['path']: m['animations'] for m in models if m['animations']},
        'hashOnlyFormats': dict(sorted(opaque_formats.items())),
        'limitations': ['No automatic runtime replacement or new playable characters.',
                        'Format checks are not a full Khronos conformance test.',
                        'No iOS rendering, subjective audio/visual review or physical-device performance approval.',
                        'The source archive contains duplicate formats, color variants and preview files; file count is not unique prop count.'],
        'models': models,
    }
    (ROOT / 'docs/evidence/vendor-asset-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ('models', 'limitations')}))


if __name__ == '__main__':
    main()
