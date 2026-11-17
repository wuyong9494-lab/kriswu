#!/usr/bin/env python3
"""Seal the one reviewed D13 victory-morph addition without rebuilding the base.

The existing 47 CMS parts, 470 private-file inventory and 540 compiled inventory
are inputs by identity only and are never rewritten. Only public certificate
operations are performed here. The clear one-file ZIP is byte reproducible;
authenticated CMS encryption is randomized and every new seal requires an
independently reviewed stage pin. No private key, workflow or upload is used.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


BASE_MANIFEST = dict(name='resource-manifest.json', bytes=147492,
    sha256='5341f635b644b3bb498662ddbd554aa7d73b172af92f85fe7f2e248264b6dd43')
BASE_SOURCE = '13e23f617d38180120f48870f206779e9d3c1d32'
RELEASE = dict(name='SF3_FighterRelease.json', bytes=35645,
    sha256='527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3')
CERTIFICATE = dict(name='recipient-public.crt', bytes=1529,
    sha256='9d8d67155afdd3068e8593b62ea674c1592350f2de6bde89e64450a7613dd656')
RECIPIENT_SPKI = '3cde0f94a6ee92c436a6419e2a944db9b2e8065aa183955fd1482581d637ba91'
ADDITION = dict(name='SF3_H17_SerpentMorph.json', bytes=12479,
    sha256='f2b3ab352b6a433fa7910fdc4c04508f9d1498c1933e4315269d2b77d10063bd')
BUILD_SETTINGS = {'FIGHTER_ASSET_RELEASE_SHA256': RELEASE['sha256'], 'FIGHTER_XUXIAO_PROFILE_SHA256': ''}
DELTA_MANIFEST_NAME = 'completion-delta-manifest.json'
COMPILED_NAME = 'completion-compiled-inventory.json'
CLEAR_NAME = 'completion-delta-private.zip'
SEALED_NAME = 'completion-delta.cms'
MAX_METADATA = 256_000
MAX_CLEAR = 32_000
MAX_SEALED = 64_000
MAX_BASE_FILE = 128_000_000
MAX_BASE_TOTAL = 384_000_000
ENCRYPTION = {'content': 'AES-256-GCM', 'keyTransport': 'RSA-OAEP', 'oaepDigest': 'SHA256', 'mgfDigest': 'SHA256'}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':')) + '\n').encode()


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def decode(raw):
    require(0 < len(raw) <= MAX_METADATA, 'Metadata size is outside its bound')
    return json.loads(raw, object_pairs_hook=no_duplicate_keys)


def regular(path, maximum, *, owner_only=False):
    path = Path(path).absolute()
    info = path.lstat()
    require(path.resolve(strict=True) == path and stat.S_ISREG(info.st_mode) and
            0 < info.st_size <= maximum, 'Expected a bounded, unlinked regular file: ' + path.name)
    if owner_only:
        require(info.st_uid == os.getuid() and info.st_mode & 0o077 == 0,
                'Recipient key must be caller-owned and inaccessible to group/others')
    return path


def checked(path, expected, maximum=MAX_METADATA):
    path = regular(path, maximum)
    raw = path.read_bytes()
    require(len(raw) == expected['bytes'] and digest(raw) == expected['sha256'],
            'Externally pinned input differs: ' + path.name)
    return raw


def record(path):
    raw = Path(path).read_bytes()
    return dict(name=Path(path).name, bytes=len(raw), sha256=digest(raw))


def safe_name(name):
    require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,191}', name) and
            '..' not in name, 'Invalid resource name')
    return name


def inventory(rows, count):
    require(isinstance(rows, list) and len(rows) == count, 'Unexpected inventory count')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'name', 'bytes', 'sha256'}, 'Unexpected inventory fields')
        name = safe_name(row['name'])
        require(name not in result and type(row['bytes']) is int and 0 < row['bytes'] <= MAX_BASE_FILE and
                isinstance(row['sha256'], str) and re.fullmatch('[a-f0-9]{64}', row['sha256']),
                'Duplicate or invalid inventory record')
        result[name] = row
    require(list(result) == sorted(result), 'Inventory must be in canonical name order')
    require(sum(r['bytes'] for r in result.values()) <= MAX_BASE_TOTAL, 'Inventory exceeds total bound')
    return result


def base_manifest(path):
    data = checked(path, BASE_MANIFEST)
    value = decode(data)
    require(value['schema'] == 'recovered-fighter-native-input-v1' and
            value['sourceBaselineSHA'] == BASE_SOURCE and value['release'] == RELEASE and
            value['buildSettings'] == BUILD_SETTINGS, 'Pinned base identity or release differs')
    private = inventory(value['files'], 470)
    compiled = inventory(value['compiledFiles'], 540)
    require(private.get(RELEASE['name']) == RELEASE and compiled.get(RELEASE['name']) == RELEASE and
            all(compiled.get(name) == row for name, row in private.items()) and
            ADDITION['name'] not in compiled, 'Base closure or addition collision')
    require(len(value['cms']['parts']) == 47, 'Existing CMS part count differs')
    return value


def compiled_document(base):
    old = inventory(base['compiledFiles'], 540)
    require(ADDITION['name'] not in old and base['release'] == RELEASE, 'Cannot replace an old resource or release')
    files = sorted([*old.values(), ADDITION], key=lambda row: row['name'])
    inventory(files, 541)
    identity = digest(encoded({'buildSettings': BUILD_SETTINGS, 'files': files}))
    return {'schema': 'fighter-completion-compiled-inventory-v1', 'baseManifest': BASE_MANIFEST,
        'baseCompiledFileCount': 540, 'compiledFileCount': 541, 'addedFiles': [ADDITION],
        'release': RELEASE, 'buildSettings': BUILD_SETTINGS, 'compiledFiles': files,
        'compiledContentSHA256': identity}


def clear_zip(payload):
    require(len(payload) == ADDITION['bytes'] and digest(payload) == ADDITION['sha256'],
            'Only the externally pinned D13 manifest may enter the delta')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
        info = zipfile.ZipInfo(ADDITION['name'], date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        info.create_system = 3
        info.external_attr = 0o100600 << 16
        info.extra = b''; info.comment = b''
        archive.writestr(info, payload)
    raw = output.getvalue()
    require(len(raw) <= MAX_CLEAR, 'Clear delta exceeds its fixed small bound')
    return raw


def validate_clear(raw):
    require(0 < len(raw) <= MAX_CLEAR, 'Clear delta exceeds its fixed small bound')
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        infos = archive.infolist()
        require(len(infos) == 1 and len({r.filename for r in infos}) == 1 and
                archive.comment == b'', 'The delta must have exactly one unique entry')
        info = infos[0]
        require(info.filename == ADDITION['name'] and not info.is_dir() and info.flag_bits == 0 and
                info.compress_type == zipfile.ZIP_STORED and info.file_size == ADDITION['bytes'] and
                info.compress_size == ADDITION['bytes'] and info.create_system == 3 and
                info.external_attr >> 16 == 0o100600 and info.date_time == (1980, 1, 1, 0, 0, 0) and
                info.extra == b'' and info.comment == b'' and info.header_offset == 0,
                'Invalid, linked, encrypted, compressed or noncanonical delta entry')
        payload = archive.read(info)
    require(len(payload) == ADDITION['bytes'] and digest(payload) == ADDITION['sha256'] and
            raw == clear_zip(payload), 'Clear delta content or canonical ZIP encoding differs')
    return payload


def openssl():
    binary = shutil.which('openssl')
    require(binary is not None, 'OpenSSL 3 with AES-GCM CMS support is required')
    return str(Path(binary).resolve(strict=True))


def command(arguments, *, data=None, maximum=MAX_METADATA):
    # No shell, provider configuration, secrets or interactive password input.
    result = subprocess.run(arguments, input=b'' if data is None else data, capture_output=True,
        env={'PATH': os.defpath, 'LC_ALL': 'C'}, timeout=30)
    require(result.returncode == 0, 'Bounded OpenSSL operation failed: ' + arguments[1])
    require(len(result.stdout) <= maximum and len(result.stderr) <= MAX_METADATA, 'OpenSSL output exceeded its bound')
    return result.stdout


def certificate_spki(path, expected=CERTIFICATE, expected_spki=RECIPIENT_SPKI):
    certificate = checked(path, expected, 16_000)
    binary = openssl()
    # Parse the bytes whose digest was checked, not a second opening of a
    # potentially shared source path.
    public = command([binary, 'x509', '-pubkey', '-noout'], data=certificate)
    spki = command([binary, 'pkey', '-pubin', '-outform', 'DER'], data=public)
    require(digest(spki) == expected_spki, 'Recipient public SPKI differs')
    return expected_spki


def inspect_seal(path):
    regular(path, MAX_SEALED)
    text = command([openssl(), 'cms', '-cmsout', '-print', '-inform', 'DER', '-in', str(path)]).decode('ascii')
    require('id-smime-ct-authEnvelopedData' in text and 'algorithm: aes-256-gcm' in text and
            text.count('algorithm: rsaesOaep') == 1 and text.count(':sha256') == 2 and ':mgf1' in text,
            'Expected authenticated GCM envelope with one RSA-OAEP-SHA256 recipient')
    return {'authenticatedEnvelope': True, 'contentEncryption': 'AES-256-GCM',
        'recipientCount': 1, 'keyTransport': 'RSA-OAEP-SHA256'}


def delta_document(clear_record, sealed_record, compiled_record):
    return {'schema': 'fighter-completion-delta-v1', 'baseManifest': BASE_MANIFEST, 'release': RELEASE,
        'basePrivateFileCount': 470, 'baseCompiledFileCount': 540, 'mergedPrivateFileCount': 471,
        'mergedCompiledFileCount': 541, 'existingCMSPartsReused': 47, 'files': [ADDITION],
        'recipientCertificate': CERTIFICATE, 'recipientSPKISHA256': RECIPIENT_SPKI,
        'encryption': ENCRYPTION, 'clearZIP': clear_record, 'cms': sealed_record,
        'compiledInventory': compiled_record}


def new_file(path, data):
    with path.open('xb') as stream:
        stream.write(data)
    path.chmod(0o600)


def prepare(args):
    output = args.output.absolute()
    require(not output.exists() and not output.is_symlink(), 'Refuse to replace an existing output')
    require(output.parent.is_dir() and output.parent.resolve(strict=True) == output.parent,
            'Output parent must be an existing unlinked directory')
    repository = Path(__file__).resolve().parents[1]
    require(not output.resolve().is_relative_to(repository), 'Private clear delta must remain outside the checkout')
    base = base_manifest(args.base_manifest)
    payload = checked(args.morph, ADDITION, ADDITION['bytes'])
    certificate = checked(args.recipient_certificate, CERTIFICATE, 16_000)
    compiled = encoded(compiled_document(base))
    clear = clear_zip(payload)
    require(validate_clear(clear) == payload, 'Canonical clear round trip differs')
    staging = Path(tempfile.mkdtemp(prefix='.completion-delta-prepare-', dir=output.parent))
    try:
        private = staging/'private'; public = staging/'public'
        private.mkdir(mode=0o700); public.mkdir(mode=0o700)
        # OpenSSL encryption consumes this private, fixed snapshot. A shared
        # source certificate changing after authentication cannot redirect it.
        certificate_path = private/CERTIFICATE['name']
        new_file(certificate_path, certificate)
        certificate_spki(certificate_path)
        clear_path = private/CLEAR_NAME
        new_file(clear_path, clear)
        compiled_path = public/COMPILED_NAME
        new_file(compiled_path, compiled)
        sealed_path = public/SEALED_NAME
        command([openssl(), 'cms', '-encrypt', '-binary', '-aes-256-gcm', '-in', str(clear_path),
            '-out', str(sealed_path), '-outform', 'DER', '-recip', str(certificate_path),
            '-keyopt', 'rsa_padding_mode:oaep', '-keyopt', 'rsa_oaep_md:sha256',
            '-keyopt', 'rsa_mgf1_md:sha256'])
        sealed_path.chmod(0o600)
        seal_inspection = inspect_seal(sealed_path)
        manifest = delta_document(record(clear_path), record(sealed_path), record(compiled_path))
        manifest_path = public/DELTA_MANIFEST_NAME
        new_file(manifest_path, encoded(manifest))
        public_records = [record(public/name) for name in (SEALED_NAME, COMPILED_NAME, DELTA_MANIFEST_NAME)]
        new_file(public/'SHA256SUMS', ''.join(r['sha256']+'  '+r['name']+'\n' for r in public_records).encode())
        receipt = {'schema': 'fighter-completion-delta-preparation-v1', 'baseManifest': BASE_MANIFEST,
            'baseReleaseUnchanged': True, 'baseCompiledInventoryUnchanged': True,
            'baseCMSPartsModified': 0, 'clearZIP': manifest['clearZIP'], 'publicFiles': public_records,
            'addition': ADDITION, 'maskDuplicated': False, 'recipientSPKISHA256': RECIPIENT_SPKI,
            'sealInspection': seal_inspection, 'realRecipientPrivateKeyRead': False,
            'realRecipientDecryptionVerified': False, 'nativeAcceptanceExecuted': False,
            'uploaded': False, 'workflowTriggered': False,
            'reproducibility': 'Clear ZIP and compiled identity are deterministic. CMS randomness requires a new externally reviewed sealed pin on re-encryption.'}
        new_file(private/'preparation-receipt.json', encoded(receipt))
        require(record(args.base_manifest) == BASE_MANIFEST and record(args.morph) == ADDITION,
                'Source inputs changed during preparation')
        os.rename(staging, output)
        return receipt
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base-manifest', 'morph', 'recipient-certificate', 'output'):
        parser.add_argument('--'+name, required=True, type=lambda p: Path(p).absolute())
    receipt = prepare(parser.parse_args())
    print(json.dumps({k:receipt[k] for k in ('addition','clearZIP','publicFiles',
        'baseCMSPartsModified','realRecipientPrivateKeyRead','realRecipientDecryptionVerified','uploaded')}, sort_keys=True))


if __name__ == '__main__':
    main()
