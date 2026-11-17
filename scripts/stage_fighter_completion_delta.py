#!/usr/bin/env python3
"""Verify and stage only the reviewed D13 addition beside an authenticated base.

No old helper gate or original resource is changed. The caller supplies its
already unwrapped, protected recipient private key; this script never retrieves
a secret or unwraps a key. It authenticates the key's public SPKI, decrypts one
fixed small CMS object and writes an isolated one-file overlay plus the merged
541-file identity. The caller explicitly installs that overlay into its own
protected build staging area. This is not native or physical-device acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile

import prepare_fighter_completion_delta as common


# These authorization pins are reviewed in source, never obtained from the
# envelope's own manifest or an environment/CLI override. A newly randomized
# CMS seal cannot authorize itself even when its plaintext claims the same SHA.
DELTA_MANIFEST = dict(name=common.DELTA_MANIFEST_NAME, bytes=1361,
    sha256='aac614c1d1e2e4c2faf09bb6fa0a98f6577dc7355fc0d3d41ed870cd784657be')
COMPILED_INVENTORY = dict(name=common.COMPILED_NAME, bytes=75826,
    sha256='4c8984617203134c7bf3328f3a6e41520bb823063f94d37013cae11839bc97a1')
CLEAR_ZIP = dict(name=common.CLEAR_NAME, bytes=12627,
    sha256='06d8a5d6e176e9777f0932718dc484ccd12a88805c64746541e9016e7cff10b8')
SEALED_DELTA = dict(name=common.SEALED_NAME, bytes=13253,
    sha256='8bd33a39113cb649aac05530c48c0a29bdf21a75d6e742e6196757fe36fdd630')


def authenticated_metadata(base_path, public):
    base = common.base_manifest(base_path)
    raw = common.checked(public/common.DELTA_MANIFEST_NAME, DELTA_MANIFEST)
    value = common.decode(raw)
    common.require(value == common.delta_document(CLEAR_ZIP, SEALED_DELTA, COMPILED_INVENTORY),
                   'Delta metadata differs from its reviewed authorization')
    compiled_raw = common.checked(public/common.COMPILED_NAME, COMPILED_INVENTORY)
    common.require(compiled_raw == common.encoded(common.compiled_document(base)),
                   'Merged inventory is not the exact original 540 plus the one permitted addition')
    common.checked(public/common.SEALED_NAME, SEALED_DELTA, common.MAX_SEALED)
    return base, common.decode(compiled_raw)


def protected_key_spki(path, expected_spki=common.RECIPIENT_SPKI):
    path = common.regular(path, 16_384, owner_only=True)
    # An encrypted or interactive key fails. The old protected caller, not this
    # delta script, is responsible for supplying an already unwrapped key.
    spki = common.command([common.openssl(), 'pkey', '-in', str(path), '-passin', 'pass:',
                           '-pubout', '-outform', 'DER'])
    common.require(common.digest(spki) == expected_spki, 'Protected recipient SPKI differs')
    return path


def unseal(path, key, expected_sealed, expected_clear, expected_spki=common.RECIPIENT_SPKI):
    common.checked(path, expected_sealed, common.MAX_SEALED)
    common.inspect_seal(path)
    protected_key_spki(key, expected_spki)
    clear = common.command([common.openssl(), 'cms', '-decrypt', '-binary', '-inform', 'DER',
        '-in', str(path), '-inkey', str(key), '-passin', 'pass:'], maximum=common.MAX_CLEAR)
    common.require(len(clear) == expected_clear['bytes'] and common.digest(clear) == expected_clear['sha256'],
                   'Decrypted clear delta differs from its external pin')
    return common.validate_clear(clear)


def file_snapshot(path, expected):
    path = common.regular(path, common.MAX_BASE_FILE)
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        common.require(stat.S_ISREG(before.st_mode) and before.st_size == expected['bytes'],
                       'Base resource size or type differs: '+path.name)
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        after = os.fstat(stream.fileno())
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    common.require(identity(before) == identity(after) and digest == expected['sha256'],
                   'Base resource identity differs: '+path.name)
    return identity(after)


def verified_base(directory, rows):
    directory = Path(directory).absolute()
    common.require(directory.is_dir() and directory.resolve(strict=True) == directory,
                   'Base must be an existing unlinked staged resource directory')
    expected = common.inventory(rows, 540)
    children = list(directory.iterdir())
    common.require(len(children) == 540 and {p.name for p in children} == set(expected),
                   'Base must contain exactly the original 540 staged resources')
    return {name:file_snapshot(directory/name, row) for name,row in expected.items()}


def base_unchanged(directory, snapshot):
    common.require({p.name for p in directory.iterdir()} == set(snapshot), 'Base closure changed during staging')
    for name, expected in snapshot.items():
        p=directory/name; value=p.lstat()
        current=(value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
        common.require(stat.S_ISREG(value.st_mode) and current == expected,
                       'Base changed during staging: '+name)


def stage(args):
    output = args.output.absolute()
    common.require(not output.exists() and not output.is_symlink(), 'Refuse to replace an existing stage output')
    common.require(output.parent.is_dir() and output.parent.resolve(strict=True) == output.parent,
                   'Stage output parent must be an existing unlinked directory')
    common.require(not output.resolve().is_relative_to(Path(__file__).resolve().parents[1]),
                   'Private overlay must remain outside the checkout')
    public = args.delta_directory.absolute()
    common.require(public.is_dir() and public.resolve(strict=True) == public, 'Unlinked delta directory required')
    base, compiled = authenticated_metadata(args.base_manifest, public)
    common.certificate_spki(args.recipient_certificate)
    # Authenticate all public inputs before consulting the protected key.
    protected_key_spki(args.recipient_key)
    base_directory = args.base_directory.absolute()
    snapshot = verified_base(base_directory, base['compiledFiles'])
    payload = unseal(public/common.SEALED_NAME, args.recipient_key, SEALED_DELTA, CLEAR_ZIP)
    staging = Path(tempfile.mkdtemp(prefix='.completion-delta-stage-', dir=output.parent))
    try:
        overlay = staging/'overlay'; overlay.mkdir(mode=0o700)
        common.new_file(overlay/common.ADDITION['name'], payload)
        common.require(common.record(overlay/common.ADDITION['name']) == common.ADDITION,
                       'Staged addition readback differs')
        common.new_file(staging/common.COMPILED_NAME, common.encoded(compiled))
        base_unchanged(base_directory, snapshot)
        receipt = {'schema':'fighter-completion-delta-stage-v1', 'baseManifest':common.BASE_MANIFEST,
            'deltaManifest':DELTA_MANIFEST, 'sealedDelta':SEALED_DELTA, 'clearZIP':CLEAR_ZIP,
            'recipientSPKISHA256':common.RECIPIENT_SPKI, 'baseDirectory':str(base_directory),
            'baseFilesVerified':540, 'overlayFilesVerified':1, 'compiledFilesExpected':541,
            'compiledContentSHA256':compiled['compiledContentSHA256'], 'addition':common.ADDITION,
            'release':common.RELEASE, 'releaseUnchanged':True, 'baseResourcesModified':False,
            'existingCMSPartsModified':False, 'maskDuplicated':False,
            'protectedRecipientDecryptionVerified':True, 'privateKeyCopiedOrWritten':False,
            'nativeAcceptanceExecuted':False, 'uploaded':False, 'workflowTriggered':False}
        common.new_file(staging/'stage-receipt-private.json', common.encoded(receipt))
        os.rename(staging, output)
        return receipt
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('base-manifest','base-directory','delta-directory','recipient-certificate','recipient-key','output'):
        parser.add_argument('--'+name,required=True,type=lambda p:Path(p).absolute())
    receipt=stage(parser.parse_args())
    print(json.dumps({k:receipt[k] for k in ('baseFilesVerified','overlayFilesVerified','compiledFilesExpected',
        'addition','releaseUnchanged','protectedRecipientDecryptionVerified','privateKeyCopiedOrWritten',
        'nativeAcceptanceExecuted','uploaded')},sort_keys=True))


if __name__=='__main__':
    main()
