#!/usr/bin/env python3
"""Rebind verified D15 hound FX metadata to the final exact local profile.

Particle samples, original materials, shaders, textures and hound poses are
unchanged. This copies verified files into a new private assembly directory.
"""
from __future__ import annotations
import argparse
import copy
import gzip
import json
from pathlib import Path

from prepare_erlang_hound_effects import BUNDLE, CONFIGURATION_SHA, EFFECTS, HOUND_GLB_SHA, sha
from sun_triad_assets import private_output, require, write_private


def checked(path, digest, maximum):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum,
            'Missing or oversized bound resource: ' + path.name)
    raw = path.read_bytes()
    require(len(digest) == 64 and sha(raw) == digest, 'Resource hash differs: ' + path.name)
    return raw


def bind(document, receipt, profile):
    require(document['version'] == 1 and document['profileID'] == profile['id'] == 'wuyong_erlang'
            and document['sourceConfigurationSHA256'] == CONFIGURATION_SHA
            and set(document['effects']) == set(EFFECTS)
            and document['bindings'] == [] and document['markers'] == []
            and receipt['sourceBundleSHA256'] == BUNDLE[1]
            and receipt['houndPoseGLBSHA256'] == HOUND_GLB_SHA
            and receipt['observableModelEndTick'] == 110, 'Unreviewed D15 hound FX identity')
    require([t for t in profile.get('summonTracks', []) if t['role'] == 'erlangSummon_hound'] == [receipt['houndTrack']],
            'Final physics and source FX hound poses differ')
    digest = profile['sha256']
    require(len(digest) == 64 and all(c in '0123456789abcdef' for c in digest), 'Invalid final character identity')
    result = copy.deepcopy(document)
    result['characterSHA256'] = digest
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('effects', 'profile', 'output'):
        p.add_argument('--' + n, required=True, type=Path)
    p.add_argument('--effects-sha256', required=True)
    p.add_argument('--receipt-sha256', required=True)
    p.add_argument('--profile-sha256', required=True)
    a = p.parse_args()
    original = checked(a.effects, a.effects_sha256, 32_000_000)
    receipt_raw = checked(a.effects.parent / 'd15-hound-fx-receipt-private.json', a.receipt_sha256, 4_000_000)
    profile_raw = checked(a.profile, a.profile_sha256, 32_000_000)
    receipt, profile = json.loads(receipt_raw), json.loads(profile_raw)
    require(receipt['effectsFile'] == dict(name=a.effects.name, bytes=len(original), sha256=sha(original)),
            'Source sampling receipt does not bind supplied FX bytes')
    document = json.loads(gzip.decompress(original))
    result = bind(document, receipt, profile)
    files = []
    for record in result['files']:
        name = record['name']
        require(Path(name).name == name and not name.startswith('.'), 'Unsafe original material resource name')
        content = checked(a.effects.parent / name, record['sha256'], 32_000_000)
        require(len(content) == record['bytes'], 'Original material resource byte count differs')
        files.append((name, content))
    output = private_output(a.output)
    require(not any(output.iterdir()), 'FX bound assembly directory must be empty')
    raw = json.dumps(result, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    write_private(output / 'SF3_D15_Effects.json', raw)
    write_private(output / 'SF3_D15_Effects.json.gz', compressed)
    for name, content in files: write_private(output / name, content)
    audit = dict(schema='bound-d15-hound-effects-v1',
        sourceEffectsSHA256=sha(original), sourceSamplingReceiptSHA256=sha(receipt_raw),
        profileSHA256=sha(profile_raw), characterSHA256=profile['sha256'],
        effectsFile=dict(name='SF3_D15_Effects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        files=result['files'], unchangedParticleSamples=True, sourcePoseGLBSHA256=HOUND_GLB_SHA,
        originalSamplingReceipt=receipt, nativeRenderingVerified=False, publicationPerformed=False)
    write_private(output / 'd15-hound-fx-binding-receipt-private.json',
                  json.dumps(audit, separators=(',', ':'), allow_nan=False).encode())
    print(json.dumps({k: v for k, v in audit.items() if k not in ('originalSamplingReceipt', 'files')}, separators=(',', ':')))


if __name__ == '__main__':
    main()
