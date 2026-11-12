#!/usr/bin/env python3
"""Offline-prepared adapter. Running seal/unseal requires separate authorization."""
import argparse
import json
import os
from pathlib import Path
import re
import types
import uuid
import music_package as pack

ENVELOPE_SOURCE_SHA256 = '925c25094359c4df9cc901a54e11e4374ea471e7cb8680b77380360767b15d79'
ENVELOPE_SOURCE_BYTES = 8975
PREFIX = b'FIGHTER1\0' + pack.PURPOSE.encode('ascii') + b'\0'
CIPHER_BYTES = len(PREFIX) + 16 + ((pack.ARCHIVE_BYTES // 16 + 1) * 16) + 32


def read_file(path, size):
    path = Path(path)
    directory = pack.open_directory(path.parent)
    try:
        return pack.read_regular(path.name, size, directory)
    finally:
        os.close(directory)


def load_envelope(path):
    # Execute precisely the bytes verified here, not a path reopened after hashing.
    # The helper has no key reads at module scope. It only consumes the secure
    # environment when seal/unseal is deliberately called later.
    data = read_file(path, ENVELOPE_SOURCE_BYTES)
    if pack.digest(data) != ENVELOPE_SOURCE_SHA256:
        raise ValueError('Envelope implementation identity mismatch')
    module = types.ModuleType('pinned_fighter_private_model')
    module.__file__ = str(Path(path).absolute())
    exec(compile(data, module.__file__, 'exec'), module.__dict__)
    return module


def verify_cipher(data, approved_sha256):
    if not isinstance(approved_sha256, str) or not re.fullmatch('[0-9a-f]{64}', approved_sha256):
        raise ValueError('An independently approved ciphertext SHA-256 is required')
    if len(data) != CIPHER_BYTES or not data.startswith(PREFIX + b'Salted__'):
        raise ValueError('Ciphertext size or envelope format mismatch')
    if pack.digest(data) != approved_sha256:
        raise ValueError('Approved ciphertext digest mismatch')


def publish_new(path, data):
    path = Path(path)
    directory = pack.open_directory(path.parent)
    temporary = '.music-envelope-' + uuid.uuid4().hex
    created = False
    try:
        try:
            os.stat(path.name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise FileExistsError('Output must not already exist')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        created = True
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path.name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        os.fsync(directory)
    finally:
        if created:
            os.unlink(temporary, dir_fd=directory)
        os.close(directory)


def seal(clear_path, output, envelope_path):
    clear = read_file(clear_path, pack.ARCHIVE_BYTES)
    pack.verify_bytes(clear)
    envelope = load_envelope(envelope_path)
    cipher = envelope.seal(clear, pack.PURPOSE)
    identity = pack.digest(cipher)
    verify_cipher(cipher, identity)
    # Check authenticated round-trip and clear pins before publishing ciphertext.
    restored = envelope.unseal(cipher, pack.PURPOSE)
    pack.verify_bytes(restored)
    publish_new(output, cipher)
    return {'bytes': len(cipher), 'sha256': identity, 'purpose': pack.PURPOSE}


def authenticate(cipher_path, approved_sha256, envelope_path, clear_output=None):
    # Exact size is enforced before reading. Approved digest and format precede
    # helper loading, key consumption, and authenticated decryption.
    cipher = read_file(cipher_path, CIPHER_BYTES)
    verify_cipher(cipher, approved_sha256)
    envelope = load_envelope(envelope_path)
    clear = envelope.unseal(cipher, pack.PURPOSE)
    pack.verify_bytes(clear)
    if clear_output is not None:
        publish_new(clear_output, clear)
    return {'bytes': len(cipher), 'sha256': approved_sha256,
            'clear_bytes': pack.ARCHIVE_BYTES, 'clear_sha256': pack.ARCHIVE_SHA256}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('seal', 'authenticate', 'unseal'))
    parser.add_argument('input', type=Path)
    parser.add_argument('--envelope-source', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--approved-cipher-sha256')
    args = parser.parse_args()
    if args.command == 'seal':
        if args.output is None or args.approved_cipher_sha256 is not None:
            parser.error('seal requires --output and does not accept an incoming digest')
        result = seal(args.input, args.output, args.envelope_source)
    else:
        if args.approved_cipher_sha256 is None:
            parser.error('authenticate/unseal requires --approved-cipher-sha256')
        if (args.command == 'unseal') != (args.output is not None):
            parser.error('Only unseal requires --output; authenticate writes no clear file')
        result = authenticate(args.input, args.approved_cipher_sha256,
                              args.envelope_source, args.output)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never print raw crypto errors, secret values or payloads.
        raise SystemExit('Private music envelope operation failed; no successful result is claimed') from None
