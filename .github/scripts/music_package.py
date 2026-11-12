#!/usr/bin/env python3
"""Private prototype. No network, credentials, encryption, or native build actions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import uuid

MAGIC = b'FIGHTER-MUSIC-PACK-1\0'
PURPOSE = 'asset:SF3_Music_Package_v1'
FILES = (
    ('SF3Music_Palace_Battle.wav', 11288516, '3494fd3137bf361355d04b0d83f7d5c9c3552288b5df7a1005dc227f988ec169'),
    ('SF3Music_Autumn_Lobby.wav', 23040044, '0a90ffdd2c641202fb67c798e6c678fe6fcf32cb80dd6537ba164ef93dfb486f'),
    ('source-audio-manifest.json', 4088, '4bf8948eb20bc13d8ae3c2e0b4757d15f77ec85bf718a3c620c3c8baed2c3b09'),
)
HEADER = json.dumps({'version': 1, 'purpose': PURPOSE, 'files': [
    {'file': n, 'bytes': s, 'sha256': h} for n, s, h in FILES
]}, sort_keys=True, separators=(',', ':')).encode('ascii')
PREFIX = MAGIC + struct.pack('>I', len(HEADER)) + HEADER
ARCHIVE_BYTES = len(PREFIX) + sum(s for _, s, _ in FILES)
# Filled by deterministic preparation, not accepted from an input manifest.
ARCHIVE_SHA256 = '99c484219740a93fb6b21aaadc869be5c2dab8c52a484b43a19ad42dd4946c19'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def open_directory(path):
    """Open each path component without following symlinks. POSIX only."""
    path = Path(path)
    if '..' in path.parts:
        raise ValueError('Parent traversal is forbidden')
    fd = os.open('/' if path.is_absolute() else '.', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts:
            if part in ('/', '.'):
                continue
            new = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = new
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_regular(name, size, directory):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size != size:
            raise ValueError('Unexpected file type or size')
        data = stream.read(size + 1)
        after = os.fstat(stream.fileno())
        if len(data) != size or (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise ValueError('File changed during read')
        return data


def verify_bytes(data):
    # Exact canonical header rejects duplicate/unexpected entries, alternate paths,
    # symlinks/type metadata, offsets, alternate ordering, and attacker-supplied pins.
    if len(data) != ARCHIVE_BYTES or not data.startswith(PREFIX):
        raise ValueError('Archive length or canonical header mismatch')
    if digest(data) != ARCHIVE_SHA256:
        raise ValueError('Pinned archive digest mismatch')
    assets = {}
    offset = len(PREFIX)
    for name, size, expected in FILES:
        payload = data[offset:offset + size]
        if digest(payload) != expected:
            raise ValueError('Resource digest mismatch')
        assets[name] = payload
        offset += size
    if offset != len(data):
        raise ValueError('Trailing data')
    return assets


def verify(path):
    path = Path(path)
    directory = open_directory(path.parent)
    try:
        return verify_bytes(read_regular(path.name, ARCHIVE_BYTES, directory))
    finally:
        os.close(directory)



def prepare(source, output):
    """Validate exactly the pinned inputs before writing a new deterministic pack.

    Source may contain unrelated resources; none are read or included. Output
    parent must exist. No credentials, encryption or resource staging is used.
    """
    source_fd = open_directory(source)
    try:
        parts = [PREFIX]
        for name, size, expected in FILES:
            data = read_regular(name, size, source_fd)
            if digest(data) != expected:
                raise ValueError('Source resource digest mismatch')
            parts.append(data)
        clear = b''.join(parts)
        verify_bytes(clear)
    finally:
        os.close(source_fd)
    output = Path(output)
    directory = open_directory(output.parent)
    temporary = '.music-prepare-' + uuid.uuid4().hex
    created = False
    try:
        # Reject even a dangling symlink, directory or matching existing file.
        try:
            os.stat(output.name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise FileExistsError('Preparation requires a new output filename')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        created = True
        with os.fdopen(fd, 'wb') as stream:
            stream.write(clear)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, output.name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        os.fsync(directory)
    finally:
        if created:
            os.unlink(temporary, dir_fd=directory)
        os.close(directory)


def stage(archive, destination):
    """Validate everything before writes. Never replace existing directory entries.

    Destination must already exist. Concurrent writers must be excluded by the
    caller. An interrupted stage may leave a matching subset; rerunning is safe.
    """
    assets = verify(archive)
    directory = open_directory(destination)
    try:
        missing = []
        for name, size, expected in FILES:
            try:
                data = read_regular(name, size, directory)
            except FileNotFoundError:
                missing.append(name)
                continue
            if digest(data) != expected:
                raise ValueError('Refusing nonmatching existing destination')
        for name in missing:
            temporary = '.music-stage-' + uuid.uuid4().hex
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory)
            try:
                with os.fdopen(fd, 'wb') as stream:
                    stream.write(assets[name])
                    stream.flush()
                    os.fsync(stream.fileno())
                os.link(temporary, name, src_dir_fd=directory, dst_dir_fd=directory,
                        follow_symlinks=False)
                os.fsync(directory)
            finally:
                os.unlink(temporary, dir_fd=directory)
        # Postflight fails closed if a concurrent mutation occurred.
        for name, size, expected in FILES:
            if digest(read_regular(name, size, directory)) != expected:
                raise ValueError('Staged resource changed')
    finally:
        os.close(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'verify', 'stage'))
    parser.add_argument('archive', type=Path)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    if args.command == 'prepare':
        if args.source is None:
            parser.error('prepare requires --source')
        prepare(args.source, args.archive)
    elif args.command == 'stage':
        if args.destination is None:
            parser.error('stage requires an existing --destination')
        stage(args.archive, args.destination)
    else:
        verify(args.archive)
    print('Private three-file music package verified')


if __name__ == '__main__':
    main()
