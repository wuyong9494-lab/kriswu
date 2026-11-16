#!/usr/bin/env python3
"""Join the actual D13 physical body and bottle/cloud bindings for match tests.

This is a private integration candidate, not a release manifest. Source poison
buffs and Bloom passives are distinguished from the still-unbound overload,
helmet/armor models, complete particle/audio and full-character acceptance.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from check_serpent_action_source import PROFILE_SHA, NAMED_SHA, checked_json
from check_serpent_state_source import RECEIPT_SHA, documents, require
from prepare_serpent_named_settings import encoded
from sun_triad_assets import private_output

BOTTLE_SHA = '00ac21fb2fa859495b4297f455020f17ccc0c284cf1abd7cd2086b98039bd3e7'
CLOUD_SHA = '8ca89507c8dbc50ebaf6105331099bcff2cc5b0f8531381fe773ece7bbd03cdd'
KINDS = {k.title(): k for k in ('uninterrupt', 'unbreakable', 'blocking', 'throwable', 'invincible')}


def build(args):
    require(not args.output.exists(), 'Use a new private integration directory')
    profile = checked_json(args.profile, PROFILE_SHA)
    named = checked_json(args.named, NAMED_SHA)
    docs = documents(args.source, (1379, 1384, 1389, 1395, 1397, 1400))
    source_records = {(r['sourceEntry'], r['sourceRecordIndex']): r for r in named['records']}
    controls = []
    for clip in profile['clips']:
        binding = clip['sourceConfiguration']
        key = binding['sourceEntry'], binding['sourceRecordIndex']
        # Shared throws/stun/root-victim use the independently verified common
        # contract already pinned by PROFILE_SHA, not the D13 named subset.
        if key in source_records:
            require(binding == source_records[key], 'Named configuration mismatch')
        config = binding['configuration']
        stride = (config['MidFrames'] if config['MidFrames'] is not None else 1) + 1
        first, last = clip['sourceFirstIndex'], clip['sourceLastIndex']
        require(stride in (1, 2) and clip['playbackTicks'] == (last - first) * stride,
                'Invalid source clip clock')
        for interval in config['Intervals'] or []:
            kind = KINDS.get(interval['Name'])
            if kind is None:
                continue
            start = max(first, 0 if interval['Start'] is None else interval['Start'] - 1)
            end = min(last, last if interval['End'] is None else interval['End'] - 1)
            if start > end:
                continue  # No overlap with this explicitly cropped animation.
            controls.append(dict(clip=clip['name'], kind=kind,
                startTick=(start-first)*stride,
                endTick=min(clip['playbackTicks'], (end-first+1)*stride-1)))
    require(len(controls) == len({tuple(c.values()) for c in controls}), 'Duplicate controls')
    binding = dict(schema='d13-ordinary-match-binding-v1', sourceSHA256=RECEIPT_SHA,
        maximumHealth=2000, level=6, rangedUsages=1, raidDamageAmplifier=1.0,
        controls=controls, bottle=checked_json(args.bottle, BOTTLE_SHA),
        cloud=checked_json(args.cloud, CLOUD_SHA))
    result = copy.deepcopy(profile)
    result['serpentBinding'] = binding
    result['schema'] = 'serpent-match-integration-candidate-v1'
    result['recoveryBoundary'].update(ordinaryMatchRuntimeBound=True,
        fullMatchProfile=False, productionActivated=False, audioBound=False,
        ordinaryPoisonBottleAudioBound=True, poisonWeaponAndRangedBuffsBound=True,
        bloomPassivesBound=True, bloomRuntimeBound=False, helmetArmorRuntimeBound=False)
    output = private_output(args.output)
    data = encoded(result)
    path = output/'SF3_Serpent_Match_Integration_Profile.json'
    path.write_bytes(data); path.chmod(0o600)
    receipt = dict(schema='d13-match-integration-receipt-v1',
        sourceProfileSHA256=PROFILE_SHA, sourceNamedSHA256=NAMED_SHA,
        sourceReceiptSHA256=RECEIPT_SHA, authenticatedLocks=sorted(docs),
        profile=dict(file=path.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()),
        controls=len(controls), bodyClips=len(result['clips']),
        unchangedBodyAndPhysicalRules=True,
        applicationNormalization=dict(maximumHealth=2000, raidDamageAmplifier=1.0,
            sourceCentimetersToArenaMillimeters=9.2),
        boundaries=result['recoveryBoundary'])
    (output/'match-integration-receipt-private.json').write_bytes(encoded(receipt))
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'named', 'source', 'bottle', 'cloud', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(build(parser.parse_args())))
