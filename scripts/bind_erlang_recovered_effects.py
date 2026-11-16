#!/usr/bin/env python3
"""Bind previously recovered D15 leg/sword media to the verified current actor.

Source particle samples, original shaders/textures, independent model poses and
three unbound sword emitters are preserved. No source media are re-extracted,
no production identity is changed, and no native pixel-parity claim is made.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import json
from pathlib import Path
import zlib

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from recover_erlang_source_audio import NECK_PROFILE_SHA, NECK_CHARACTER_SHA
from sun_triad_assets import private_output, require

INPUTS = {
    'stomp': dict(directory='recovered-erlang-stomp-source-only-v2',
        file='D15_Stomp_SourceOnly.recovered-v1.json.gz', bytes=200863,
        sha256='e25174fe3d41a530a3fce6e2a1386efb7d0b82e4bfa864ad315a9bd75237abbe',
        receipt='d15-stomp-effect-receipt-private.json',
        receiptSHA256='9954628860e88cc8a47cd28ee0c61cc084d9f9d6db4d822815c48a4774cdb019',
        schema='original-d15-stomp-source-only-recovered-v1', output='SF3_D15_StompEffects.json'),
    'sword': dict(directory='recovered-erlang-sword-source-only-v1',
        file='D15_Sword_SourceOnly.recovered-v1.json.gz', bytes=709484,
        sha256='16f4003fc5130d80f65909a4e25daa026ad8ce130f9009736ae2aeb644aa0204',
        receipt='d15-sword-effect-receipt-private.json',
        receiptSHA256='245d64669edd31d5e7e5707ad60a4081d2e91424b235c6ddc67ed2a5a2e3af86',
        schema='original-d15-sword-source-only-recovered-v1', output='SF3_D15_SwordEffects.json'),
}
CONFIGURATION_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'


def unpack(raw):
    stream = zlib.decompressobj(16 + zlib.MAX_WBITS)
    result = stream.decompress(raw, 8_000_001)
    require(len(result) <= 8_000_000 and stream.eof and not stream.unused_data
            and not stream.unconsumed_tail, 'Invalid or oversized recovered source gzip')
    return json.loads(result)


def join(kind, source, receipt, profile):
    pin = INPUTS[kind]
    require(source['schema'] == pin['schema'] and source['sourceOnly'] is True
            and source['runtimeBound'] is False and source['sourceConfigurationSHA256'] == CONFIGURATION_SHA
            and source['sampleRate'] == 60 and source['worldUnitsPerSourceUnit'] == .01,
            'Unexpected source-only recovered FX generation')
    require(profile['id'] == profile['hero'] == 'wuyong_erlang'
            and profile['sha256'] == NECK_CHARACTER_SHA and len(profile['clips']) == 62
            and profile['recoveryBoundary']['personalNeckBridgeIncluded'] is True,
            'Expected the actual current recovered actor')
    tracks = {t['role']: t for t in profile['summonTracks']}
    for role, model in source['sourceModels'].items():
        require(model['track'] == tracks.get(role), 'Source FX and current collision/model clock differ: '+role)
    document = dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        files=copy.deepcopy(source['files']), materials=copy.deepcopy(source['materials']),
        effects=copy.deepcopy(source['effects']), bindings=[], markers=[],
        evidence=['Previously verified recovered particle samples and all original resources remain byte-identical.',
            'Independent source model tracks match the current recovered actor exactly; no body-pose proxy is used.',
            'This is a private integration candidate; private Metal compilation, native rendering and production activation are pending.'],
        recoveredSourceManifestSHA256=pin['sha256'])
    if kind == 'stomp':
        require(set(source['sourceModels']) == {'erlangSummon_stomp'}
                and source['sourceModels']['erlangSummon_stomp']['track'] == receipt['sourceTrack'],
                'Recovered source leg track differs')
        binding = dict(id='d15_leg_animation_start', role='erlangSummon_stomp', effect='D15_fx_big_leg', startTick=0,
            bone='magic_joint_root', attachToLocal=False, follow=[0, 0, 0], shift=[0, 0, 0],
            sourceLock=1434, sourceTrigger=1, sourceRecordIndex=100)
        require(receipt['originalSourceEvent'] == binding, 'Original leg creation event changed')
        effect = source['effects']['D15_fx_big_leg']
        require(len(effect['tracks']) == 3 and abs(effect['duration']-1.4) < 1e-6,
                'Recovered original leg emitter scope changed')
        document['erlangSourceModels'] = copy.deepcopy(source['sourceModels'])
        document['erlangModelBindings'] = [binding]
    else:
        require(len(source['sourceModels']) == 9 and source['sourceModels']['erlangSummon_swordRotate']['track'] is None,
                'Sword birth/idle/rotate/attack scope differs')
        binding = dict(sourceLock=1447, sourceTrigger=1, bone='magic_joint_root', attachToLocal=True,
            follow=[1, 1, 1], shift=[0, 0, 0], requiredQuality='high', sourceDurationSeconds=9999.)
        require(receipt['originalSourceEvent'] == binding, 'Original sword source attachment changed')
        scope = source['sourceScope']
        require(scope['version'] == 3 and scope['sourceActiveEmitters'] == 20 and scope['completePrefab'] is False
                and len(scope['unboundEmitters']) == 3 and len(scope['boundMeshEmitters']) == 8
                and len(scope['boundPlaneEmitters']) == 7 and len(scope['boundTrailEmitters']) == 2,
                'Do not erase the three original unbound sword emitters')
        document['erlangSwordModels'] = copy.deepcopy(source['sourceModels'])
        document['erlangSwordBinding'] = binding
        document['erlangSwordScope'] = copy.deepcopy(scope)
        document['evidence'].append('Three original Noise emitters remain unbound; native source HIDE fade is unverified.')
    return document


def build(args):
    profile_raw = checked(args.profile, NECK_PROFILE_SHA, 24_000_000)
    profile = json.loads(profile_raw)
    body = args.profile.parent/(profile['resourceName']+'.glb')
    checked(body, NECK_CHARACTER_SHA, 24_000_000)
    require(body.stat().st_size == profile['bytes'], 'Current source actor size differs')
    require(not args.output.exists(), 'Use a new private recovered-FX output')
    # Validate every source before emitting any integration resource.
    prepared = []
    for kind, pin in INPUTS.items():
        directory = args.recovered_root/pin['directory']
        compressed = checked(directory/pin['file'], pin['sha256'], 1_000_000)
        require(len(compressed) == pin['bytes'], 'Source-only FX size changed')
        receipt = json.loads(checked(directory/pin['receipt'], pin['receiptSHA256'], 200_000))
        require(receipt['derivedFile'] == dict(name=pin['file'], bytes=pin['bytes'], sha256=pin['sha256']),
                'Source-only FX receipt does not describe the exact bytes')
        source = unpack(compressed); document = join(kind, source, receipt, profile)
        resources = []
        require(len(source['files']) == (9 if kind == 'stomp' else 39), 'Source resource inventory differs')
        for row in source['files']:
            name = row['name']
            require(Path(name).name == name and re_safe_name(name), 'Unsafe original source resource')
            data = checked(directory/name, row['sha256'], 32_000_000)
            require(len(data) == row['bytes'], 'Source resource size differs')
            resources.append((name, data))
        prepared.append((kind, pin, source, document, resources))
    output = private_output(args.output); results = []
    for kind, pin, source, document, resources in prepared:
        target = output/kind; target.mkdir(mode=0o700)
        for name, data in resources:
            write_new(target/name, data)
        raw = encoded(document); compressed = gzip.compress(raw, mtime=0)
        write_new(target/pin['output'], raw)
        write_new(target/(pin['output']+'.gz'), compressed)
        # Read the actual final bytes independently before describing a binding.
        written = unpack((target/(pin['output']+'.gz')).read_bytes())
        for key in ('effects', 'materials', 'files'):
            require(written[key] == source[key], 'Rebinding changed original sampled source data')
        results.append(dict(kind=kind, output=record(target/(pin['output']+'.gz')),
            files=len(resources), sourceManifestSHA256=pin['sha256'], sourceReceiptSHA256=pin['receiptSHA256'],
            originalSamplesAndResourcesUnchanged=True, nativeMetalVerified=False, nativeRendered=False,
            completePrefab=kind == 'stomp'))
    receipt = dict(schema='d15-recovered-fx-actor-binding-v1', profile=record(args.profile), character=record(body),
        groups=results, productionIdentityChanged=False, nativeRenderingVerified=False,
        historicalRuntimeManifestBytesRestored=False,
        remaining=['Sword Noise emitters and source HIDE fade.',
                   'Hound and eye/earth/meditation/aftershock source binding and original material completeness.',
                   'Native private Metal/rendering and complete release identity.'])
    write_new(output/'erlang-recovered-fx-binding-private.json', encoded(receipt))
    return receipt


def re_safe_name(name):
    import re
    return re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,191}', name) is not None and '..' not in name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'recovered-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
