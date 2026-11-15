#!/usr/bin/env python3
"""Rebind an already sampled original leg effect to the final actor profile.

Only character identity changes in the runtime document. Source tracks,
particle samples, programs, textures and material values remain identical.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
from pathlib import Path
from sun_triad_assets import private_output, require, write_private


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def verify_resources(document, directory):
    for file in document['files']:
        require(Path(file['name']).name == file['name'] and not (directory / file['name']).is_symlink(),
                'Unsafe original leg resource path')
        raw = (directory / file['name']).read_bytes()
        require(len(raw) == file['bytes'] and sha(raw) == file['sha256'], 'Original leg resource changed')


def bind(candidate, receipt_sha, profile_path, profile_sha, output):
    receipt_raw = (candidate / 'd15-stomp-effect-receipt-private.json').read_bytes()
    require(sha(receipt_raw) == receipt_sha, 'Reviewed source effect receipt differs')
    receipt = json.loads(receipt_raw)
    require(receipt['schema'] == 'original-d15-stomp-effect-v1', 'Wrong effect receipt schema')
    source_file = receipt['derivedFile']
    require(source_file['name'] == 'SF3_D15_StompEffects.json.gz', 'Wrong original leg manifest')
    compressed = (candidate / source_file['name']).read_bytes()
    require(len(compressed) == source_file['bytes'] and sha(compressed) == source_file['sha256'], 'Original leg manifest changed')
    document = json.loads(gzip.decompress(compressed))
    verify_resources(document, candidate)
    profile_raw = profile_path.read_bytes()
    require(sha(profile_raw) == profile_sha, 'Final actor profile digest differs')
    profile = json.loads(profile_raw)
    role = 'erlangSummon_stomp'
    require(profile['id'] == document['profileID'] == 'wuyong_erlang'
            and len(profile['sha256']) == 64
            and [t for t in profile.get('summonTracks', []) if t['role'] == role] == [receipt['sourceTrack']]
            and document['erlangSourceModels'][role]['track'] == receipt['sourceTrack'],
            'Final actor is missing the exact independently sampled original leg track')
    output = private_output(output)
    require(not any(output.iterdir()), 'Rebound source effect output must be empty')
    prior_character = document['characterSHA256']
    document['characterSHA256'] = profile['sha256']
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    for file in document['files']:
        original = (candidate / file['name']).read_bytes()
        require(len(original) == file['bytes'] and sha(original) == file['sha256'], 'Original leg resource changed during copy')
        write_private(output / file['name'], original)
    write_private(output / 'SF3_D15_StompEffects.json', raw)
    write_private(output / source_file['name'], compressed)
    receipt.update(profileSHA256=profile_sha, profileIncludesStompTrack=True, characterSHA256=profile['sha256'],
        metadataRebind=dict(priorReceiptSHA256=receipt_sha, priorDerivedSHA256=source_file['sha256'],
            priorCharacterSHA256=prior_character, changedRuntimeFields=['characterSHA256'],
            sourceSamplesChanged=False, sourceResourcesChanged=False),
        derivedFile=dict(name=source_file['name'], bytes=len(compressed), sha256=sha(compressed)))
    write_private(output / 'd15-stomp-effect-receipt-private.json',
        json.dumps(receipt, separators=(',', ':'), allow_nan=False).encode())
    return receipt['derivedFile']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('candidate', 'profile', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('receipt-sha256', 'profile-sha256'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    print(json.dumps(bind(args.candidate, args.receipt_sha256, args.profile, args.profile_sha256, args.output)))


if __name__ == '__main__':
    main()
