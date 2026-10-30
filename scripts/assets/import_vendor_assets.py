#!/usr/bin/env python3
"""Import pinned, licensed static packs; never execute files from a pack.

Usage: import_vendor_assets.py ARCHIVE_DIRECTORY
Source definitions and archive SHA-256 values live in art/vendor/sources.json.
This only stages source assets outside the Xcode App target.
"""
import collections
import hashlib
import io
import json
import pathlib
import stat
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEST = ROOT / 'art/vendor'
SKIP = {'.url': 'publisher website shortcut',
        '.unitypackage': 'Unity-only duplicate packaging; PNG sources are imported'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def import_pack(source, archives):
    archive = archives / source['archive']['filename']
    if archive.is_file():
        archive_data = archive.read_bytes()
    else:
        # Large source archives are stored in byte-exact parts to fit the
        # repository connector's request size. Verify the original ZIP hash.
        parts = sorted(archives.glob(archive.name + '.part[0-9][0-9][0-9]'))
        expected = [archive.with_name(archive.name + f'.part{i:03}')
                    for i in range(1, len(parts) + 1)]
        if not parts or parts != expected:
            raise ValueError(f"Missing archive parts: {source['id']}")
        archive_data = b''.join(part.read_bytes() for part in parts)
    if digest(archive_data) != source['archive']['sha256']:
        raise ValueError(f"Archive hash mismatch: {source['id']}")
    files, excluded = [], []
    prefix = source.get('stripPrefix', '')
    destination = DEST / source['id']
    seen = set()
    with zipfile.ZipFile(io.BytesIO(archive_data)) as z:
        if sum(i.file_size for i in z.infolist()) > 200_000_000:
            raise ValueError('Unexpected archive expansion')
        for info in z.infolist():
            if info.is_dir():
                continue
            path = pathlib.PurePosixPath(info.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in info.filename:
                raise ValueError(f'Unsafe archive path: {info.filename}')
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError(f'Archive symlink: {info.filename}')
            if not info.filename.startswith(prefix):
                raise ValueError(f'Unexpected source prefix: {info.filename}')
            relative = info.filename[len(prefix):]
            if not relative or relative in seen:
                raise ValueError(f'Duplicate/empty path: {relative}')
            seen.add(relative)
            data = z.read(info)  # Includes CRC verification.
            item = {'path': relative, 'bytes': len(data), 'sha256': digest(data)}
            suffix = pathlib.PurePosixPath(relative).suffix.lower()
            if suffix in SKIP:
                excluded.append(dict(item, reason=SKIP[suffix]))
                continue
            if suffix not in {'.png', '.jpg', '.jpeg', '.svg', '.glb', '.gltf', '.bin',
                              '.obj', '.mtl', '.dae', '.fbx', '.stl', '.ogg', '.wav',
                              '.ttf', '.otf', '.xml', '.ai', '.txt', '.md'}:
                raise ValueError(f'Unreviewed format: {relative}')
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() and target.read_bytes() != data:
                raise ValueError(f'Would overwrite a different asset: {target}')
            target.write_bytes(data)
            files.append(item)
    licenses = [item for item in files if 'license' in pathlib.Path(item['path']).name.lower()]
    if not licenses or not any('CC0' in (destination / item['path']).read_text(encoding='utf-8-sig')
                               for item in licenses):
        raise ValueError(f"Missing explicit CC0 license: {source['id']}")
    return dict(source, status='source-staged-not-in-app', fileCount=len(files),
                bytes=sum(item['bytes'] for item in files),
                extensions=dict(sorted(collections.Counter(pathlib.Path(item['path']).suffix.lower()
                                                           for item in files).items())),
                licenseFiles=[item['path'] for item in licenses], files=files, excluded=excluded)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    sources = json.loads((DEST / 'sources.json').read_text())
    packs = [import_pack(source, pathlib.Path(sys.argv[1])) for source in sources['packs']]
    manifest = dict(schemaVersion=1, retrievedAt=sources['retrievedAt'],
                    scope='11 verified official free packs; not an exhaustive internet archive',
                    runtimeIntegration='none; App target is unchanged by this import',
                    packCount=len(packs), fileCount=sum(p['fileCount'] for p in packs),
                    bytes=sum(p['bytes'] for p in packs), packs=packs)
    (DEST / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: manifest[k] for k in ('packCount', 'fileCount', 'bytes')}))


if __name__ == '__main__':
    main()
