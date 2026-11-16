#!/usr/bin/env python3
"""Bind the recovered D15 body, hound, seven models and six sword slots.

Uses the new recovered identities explicitly. Historical converters, release
identities and installed App assets are not rewritten by this private join.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from build_erlang_runtime_rules import body_rules
from extend_erlang_model_runtime_rules import (
    RECOVERED_HELD_SHA, RECOVERED_MODELS_SHA, append_held_swords, extend,
)
from sun_triad_assets import private_output, require

INPUTS = {
    'body': ('continued-20261116/erlang-recovered-combat-body-v1/SF3_Erlang_Recovered_Combat_Profile.json',
             '88e46fab47dbaa2ce5dd280ccf13b13cde406aa6813cfa42735dca98542b861a', 24_000_000),
    'named': ('recovered-erlang-named-animations-v1/erlang-imperial-animation-named-recovered-v1.json',
              '12704648d0fd60929d1bba47a0fe6cd1eb0f3aafd36b7504b8819f57f5bddb08', 4_000_000),
    'hound': ('recovered-erlang-hound-candidate-v1/d15-hound-candidate-private.json',
              'ff2cf317bd2a8adb0a3cd3534704d5688b1807ca7fb4a97a00b057c235e1231f', 200_000),
    'models': ('continued-20261116/recovered-erlang-model-tracks-v1/d15-model-tracks-candidate-private.json',
               RECOVERED_MODELS_SHA, 1_000_000),
    'held': ('continued-20261116/recovered-erlang-sword-held-v1/d15-sword-held-candidate-private.json',
             RECOVERED_HELD_SHA, 1_000_000),
    'rules': ('recovered-erlang-trigger-sources-v1/receipt-private.json',
              '44aa107032803aa8b4ef93a969cc971165fbe9cd63f81774dc1ee21615401ede', 30_000),
}


def validate_bindings(profile):
    """Reject dangling geometry, crop-overrun and release-after-deletion joins."""
    require(profile['id'] == profile['hero'] == 'wuyong_erlang', 'Wrong runtime actor')
    clips = {c['name']: c for c in profile['clips']}
    tracks = {t['role']: t for t in profile['summonTracks']}
    require(len(tracks) == len(profile['summonTracks']) == 15, 'Incomplete or duplicate summon bindings')
    rules = profile['erlangRules']
    require(len(rules['attacks']) == 36 and len(rules['releases']) == 6, 'Incomplete source ability inventory')
    for attack in rules['attacks']:
        # Persistent swords launch from the held-slot state, without replacing
        # the owner's current body animation. They have no body clip role.
        require(attack['role'] in profile['roles'] or
                (attack['role'] == 'erlangSwords' and attack['ability'] == 'swords'
                 and attack['modelRole'] == 'erlangSummon_sword'), 'Attack owner role is missing')
        if attack['modelRole'] is None:
            c = clips[profile['roles'][attack['role']]]
            geometry = c['tracks']
            last = c['playbackTicks']
        else:
            require(attack['modelRole'] in tracks, 'Attack model role is missing')
            geometry = tracks[attack['modelRole']]
            last = len(geometry['root']) - 1
            last = min(last, geometry.get('sourceEndEventTick', last),
                       geometry.get('sourceDeleteEventTick', last))
        parts = {x['id'] for key in ('collisionEdges', 'hurtCapsules') for x in geometry.get(key, [])}
        require(attack['parts'] and set(attack['parts']) <= parts, 'Attack geometry is not bound')
        require(0 <= attack['startTick'] <= attack['endTick'] <= last, 'Attack exceeds source lifetime')
    for release in rules['releases']:
        require(release['modelRole'] in tracks and release['ownerRole'] in profile['roles'],
                'Release source role is missing')
        clip = clips[profile['roles'][release['ownerRole']]]
        require(0 <= release['atTick'] <= clip['sourceEndEventTick'], 'Release follows body end')
    for control in rules['controls']:
        c = clips[profile['roles'][control['role']]]
        require(0 <= control['startTick'] <= control['endTick'] <= c['playbackTicks'],
                'Control exceeds actual source clip')
    slots = rules['swordSlots']
    require(len(slots) == 6 and {s['slot'] for s in slots} == set(range(1, 7)), 'Incomplete sword slots')
    for slot in slots:
        t = tracks[slot['birthRole']]
        require(t['sourceEndEventTick'] == 92 and t.get('sourceDeleteEventTick') is None,
                'Sword birth must transition to idle, not delete')


def join(body, named, dog, models, held):
    require(len(body['clips']) == 62 and 'ordinaryThrows' in body
            and 'erlangRules' not in body and 'summonTracks' not in body,
            'Expected the recovered unbound 62-clip body')
    profile = copy.deepcopy(body)
    profile['erlangRules'], body_evidence = body_rules(profile, named, dog, INPUTS['rules'][1])
    profile['summonTracks'] = [copy.deepcopy(dog['track'])]
    profile, models_evidence = extend(profile, models)
    append_held_swords(profile, models_evidence, held, recovered=True)
    evidence = dict(schema='recovered-d15-runtime-profile-binding-v1',
        inputs={key: dict(path=path, sha256=digest) for key, (path, digest, _) in INPUTS.items()},
        body=body_evidence, models=models_evidence,
        applicationDamageAndImpactAdaptersPreserved=True,
        historicalConverterAndReleasePinsUnchanged=True,
        nativeExecuted=False, visualsAccepted=False, productionActivated=False)
    profile['erlangRules']['sourceSHA256'] = sha(encoded(evidence))
    profile['schema'] = 'erlang-recovered-runtime-profile-v1'
    profile['recoveryBoundary'] = dict(profile['recoveryBoundary'], abilityRulesBound=True,
        abilityRuntimeRulesIncluded=True, summonModelTracksIncluded=True,
        modelCollisionBound=True, swordSlotsBound=True, fullMatchProfile=False,
        runtimeBound=False, nativeRenderingVerified=False)
    validate_bindings(profile)
    require(profile['clips'] == body['clips'] and profile['roles'] == body['roles']
            and profile['ordinaryThrows'] == body['ordinaryThrows']
            and profile['combatRules'] == body['combatRules'], 'Existing combat/body data changed')
    return profile, evidence


def build(args):
    require(not args.output.exists(), 'Use a fresh private runtime output')
    inputs = {key: json.loads(checked(args.recovery_root/path, digest, limit))
              for key, (path, digest, limit) in INPUTS.items()}
    profile, evidence = join(*(inputs[k] for k in ('body', 'named', 'hound', 'models', 'held')))
    output = private_output(args.output)
    model_path = args.recovery_root/Path(INPUTS['body'][0]).parent/(profile['resourceName']+'.glb')
    body_raw = checked(model_path, profile['sha256'], 24_000_000)
    require(len(body_raw) == profile['bytes'], 'Body model size differs')
    write_new(output/model_path.name, body_raw)
    dog = inputs['hound']
    dog_path = args.recovery_root/Path(INPUTS['hound'][0]).parent/dog['modelFile']['name']
    write_new(output/dog_path.name, checked(dog_path, dog['modelFile']['sha256'], 1_000_000))
    write_new(output/'SF3_Erlang_Recovered_Runtime_Profile.json', encoded(profile))
    write_new(output/'erlang-runtime-binding-private.json', encoded(evidence))
    receipt = dict(schema='recovered-d15-runtime-profile-receipt-v1',
        profile=record(output/'SF3_Erlang_Recovered_Runtime_Profile.json'),
        character=record(output/model_path.name), hound=record(output/dog_path.name),
        bindingEvidence=record(output/'erlang-runtime-binding-private.json'),
        sourceAttacks=len(profile['erlangRules']['attacks']),
        sourceReleases=len(profile['erlangRules']['releases']),
        sourceControls=len(profile['erlangRules']['controls']),
        summonTracks=len(profile['summonTracks']), swordSlots=len(profile['erlangRules']['swordSlots']),
        unchangedBodyClips=62, unchangedGeometryAndPersonalPortrait=True,
        boundaries=profile['recoveryBoundary'])
    write_new(output/'runtime-profile-receipt-private.json', encoded(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recovery-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    print(json.dumps(build(parser.parse_args()), allow_nan=False))


if __name__ == '__main__':
    main()
