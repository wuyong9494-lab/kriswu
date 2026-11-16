#!/usr/bin/env python3
"""Recover the existing D15 Eye/Earth/Meditation whitelist from pinned bytes.

The three original samplers are reused. This rebuilds authenticated source
caches and binds them to the exact recovered neck profile; it does not restore
the historical private receipt bytes or admit any of the nine omitted emitters.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import json
import math
import warnings
from pathlib import Path

from erlang_effect_materials import save_json
from erlang_skill_effect_materials import IMPACT_MATERIALS, LASER_MATERIALS
from prepare_erlang_hound_effects import BUNDLE, CONFIGURATION_SHA
from prepare_erlang_skill_effects import (
    EFFECT as EYE, PREFAB_ID as EYE_PREFAB, SYSTEMS as EYE_SYSTEMS,
    CLIP_SHA as EYE_MOTION_SHA, RELEASE as EYE_RELEASE, sample_effect as sample_eye,
)
from prepare_erlang_impact_effects import EARTH, MEDITATION, EARTH_RELEASE, EFFECTS, sample_effect as sample_impact
from recover_erlang_hound_effects import (
    OriginalObjects, prepare_cache, checked, sha, PROFILE_SHA, CHARACTER_SHA,
)
from sun_triad_assets import private_output, require, write_private
from sun_triad_particle_assets import SourceAssets


MODEL_IDENTITY = (666196, '25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0')
RULE_IDENTITIES = {
    1432: (488554, '816ef8d4b733788a957d10f3d379e60b9dfe7fbcf9ea4ed483576baf1bc2068a'),
    1438: (12026, '1e25fb570a7992137c3f05ce99e0d4eb6b2fd2af5d6f94f4122088e9660eed6c'),
}
ADDITIONAL_SOURCES = {
    '08db602bdc0f7c37fd88caf15e23217e.bin': ('lightning_bundle', 412212, '537fe25fd4f13206e52768c3a33d3843f40435b64a71fb5e4d9e32e4c009fc5d'),
    'afd51a9236fa99ad9c3a982532138ca4.bin': ('ground_texture_bundle', 28340549, 'a35ebc3a36e08ef7321fdeff42cd83bd32b8b834a264e04edac0b2d99848e8c3'),
    'f195a2c213fa33e0387b66bdba43c632.bin': ('ice_texture_bundle', 869815, '5afbcf83431f82480a663accba7e9b49173737a572dc930d88b35e8b5d2134bd'),
}
# The legacy input table also contains this material, but none of the 38
# selected actual renderers references it. It is not substituted into a layer.
UNREFERENCED_INPUT_MATERIAL = -8870619190891733605
MATERIAL_SCOPE = {pid: entry[1] for pid, entry in (LASER_MATERIALS | IMPACT_MATERIALS).items()
                  if pid != UNREFERENCED_INPUT_MATERIAL}
PREFABS = {EYE: EYE_PREFAB, **{name: value[0] for name, value in EFFECTS.items()}}
SYSTEMS = {EYE: EYE_SYSTEMS, **{name: value[1] for name, value in EFFECTS.items()}}


def source_bindings(profile, models, rules):
    require(profile['id'] == profile['hero'] == 'wuyong_erlang' and profile['sha256'] == CHARACTER_SHA,
            'Recovered skill destination actor differs')
    require(models['sourceConfigurationSHA256'] == CONFIGURATION_SHA,
            'Recovered original model configuration differs')
    tracks = {track['role']: track for track in models['summonTracks']}
    roles = ('erlangSummon_eye', 'erlangSummon_earth', 'erlangSummon_meditation')
    for role in roles:
        require([track for track in profile['summonTracks'] if track['role'] == role] == [tracks[role]],
                'Actual skill model or independent clock differs: ' + role)
    def trigger(lock, index):
        document = rules[lock]
        require(document['schema'] == 'restored-d15-original-trigger-fields-v1' and
                document['sourceLock'] == lock and len(document['sets']) == 1,
                'Recovered source rule scope differs')
        found = [row for row in document['sets'][0]['triggers'] if row['triggerIndex'] == index]
        require(len(found) == 1, 'Recovered original trigger is absent or ambiguous')
        return found[0]
    eye_create, eye_fx = trigger(1432, 50), trigger(1432, 53)
    earth_create, earth_fx, med_fx = trigger(1432, 68), trigger(1432, 66), trigger(1438, 1)
    require(eye_create['events'] == eye_fx['events'] == [{'a18': ['enum65537', 'D15_Laser_Fx']}] and
            eye_fx['actions'][0] == {'a46': [EYE, None, 'head', None, 'enum65537', 1,
                None, True, None, None, False, [1., 1., 1.], None, [0., 0., 0.], None, None]} and
            eye_fx['conditions'][1] == {'Not': [{'expr': [{'f65': [{'f74': ['enum65537']}]}, 1., 'op22']}]},
            'Original eye event, attachment or unmirrored condition differs')
    require(earth_create['events'] == earth_fx['events'] ==
                [{'a18': ['enum65537', 'D15_Spear_Ground_Shake_Model_Creation']}] and
            earth_fx['actions'] == [{'a46': [EARTH, None, 'pelvis', None, 'enum65537', 1,
                None, None, None, None, False, None, None, [0., 0., 0.], None, None]}],
            'Original Earth event or captured pelvis differs')
    require(med_fx['events'] == [{'a2': ['enum65537']}] and med_fx['actions'] == [{'a46': [
        MEDITATION, None, 'chest', None, 'enum65539', 1, None, None, None, None, False,
        [0., 0., 0.], None, [0., 3., 0.], None, None]}], 'Original meditation Parent chest event differs')
    # The entire source rule files are SHA-pinned by read_inputs. Preserve the
    # base-costume predicates here as well, so this pure binding cannot erase
    # their conditional difference during a future caller's composition.
    def costume_condition(target):
        return {'Not': [{'And': [{'expr': [{'f239': [target, slot]}, 101741., 'op22']}
                                for slot in ('Armor', 'Helmet', 'Weapon', 'Ranged')]}]}
    require(eye_fx['conditions'] == [costume_condition('enum65537'),
                {'Not': [{'expr': [{'f65': [{'f74': ['enum65537']}]}, 1., 'op22']}]}] and
            earth_fx['conditions'] == [costume_condition('enum65537')] and
            med_fx['conditions'] == [costume_condition('enum65539')], 'Original base-costume conditions differ')
    clips = {}
    for role, name, digest, frames, ticks, end, record, interval, frame in (
        ('erlangEye', 'd15_avatara_laser', EYE_MOTION_SHA, 149, 296, 288, 104, 'D15_Laser_Fx', 62),
        ('erlangEarthshaker', 'd15_avatara_spear_earthshake',
         '341014fb370f15f25c5fa33085de640c0051fd1b55855488b3fff7dcdb98ff0f',
         111, 110, 106, 102, 'D15_Spear_Ground_Shake_Model_Creation', 40)):
        found = [clip for clip in profile['clips'] if clip['name'] == name]
        require(profile['roles'][role] == name and len(found) == 1, 'Original skill actor role differs')
        clip = found[0]; cfg = clip['sourceConfiguration']; motion = cfg['configuration']
        require(clip['sha256'] == digest and clip['frames'] == frames and clip['playbackTicks'] == ticks and
                clip['sourceEndEventTick'] == end and clip['sourceFirstIndex'] == 0 and
                clip['sourceLastIndex'] == frames - 1 and cfg['sourceSHA256'] == CONFIGURATION_SHA and
                cfg['sourceEntry'] == 'settings_sets_dynasty.bytes' and cfg['sourceRecordIndex'] == record and
                [row for row in motion['Intervals'] if row['Name'] == interval][0]['Start'] == frame,
                'Original skill source motion or interval differs')
        clips[role] = clip
    require(clips['erlangEye']['sourceConfiguration']['configuration']['Mirrored'] is None and
            clips['erlangEye']['sourceConfiguration']['configuration']['MidFrames'] is None and
            clips['erlangEarthshaker']['sourceConfiguration']['configuration']['MidFrames'] == 0,
            'Original skill playback stride differs')
    for release in (EYE_RELEASE, EARTH_RELEASE):
        require([row for row in profile['erlangRules']['releases'] if row['modelRole'] == release['modelRole']] == [release],
                'Current skill model release differs from source')
    eye = dict(id='d15_laser_plain_head', role=roles[0], ownerRole='erlangEye', effect=EYE,
        bone='head', attachToLocal=True, follow=[1, 1, 1], shift=[0., 0., 0.],
        sourceLock=1432, sourceTrigger=53, sourceEvent='D15_Laser_Fx', sourceRecordIndex=104,
        sourceClip=clips['erlangEye']['name'], sourceMotionSHA256=EYE_MOTION_SHA,
        sourceIntervalStart=62, release=copy.deepcopy(EYE_RELEASE), track=tracks[roles[0]], sourceModelEndTick=122)
    earth = dict(id='d15_earth_pelvis', role=roles[1], ownerRole='erlangEarthshaker', effect=EARTH,
        bone='pelvis', attachToLocal=False, follow=[0, 0, 0], shift=[0., 0., 0.], sourceTarget='owner',
        sourceLock=1432, sourceTrigger=66, sourceEvent='D15_Spear_Ground_Shake_Model_Creation',
        sourceRecordIndex=102, sourceClip=clips['erlangEarthshaker']['name'],
        sourceMotionSHA256=clips['erlangEarthshaker']['sha256'], sourceIntervalStart=40,
        release=copy.deepcopy(EARTH_RELEASE), track=tracks[roles[1]], sourceModelEndTick=22)
    meditation = dict(id='d15_meditation_parent_chest', role=roles[2], ownerRole=None, effect=MEDITATION,
        bone='chest', attachToLocal=False, follow=[0, 0, 0], shift=[0., .03, 0.], sourceTarget='modelParent',
        sourceLock=1438, sourceTrigger=1, sourceEvent='Initialize', sourceRecordIndex=106,
        sourceClip=None, sourceMotionSHA256=None, sourceIntervalStart=None, release=None,
        track=tracks[roles[2]], sourceModelEndTick=52)
    return {EYE: eye, EARTH: earth, MEDITATION: meditation}, dict(
        eyeCreateTrigger=eye_create, eyeEffectTrigger=eye_fx, earthCreateTrigger=earth_create,
        earthEffectTrigger=earth_fx, meditationEffectTrigger=med_fx)


def read_inputs(profile_path, models_path, rules_directory):
    profile = json.loads(checked(profile_path, (18924288, PROFILE_SHA)))
    checked(profile_path.parent / (profile['resourceName'] + '.glb'), (18594716, CHARACTER_SHA))
    models = json.loads(checked(models_path, MODEL_IDENTITY))
    rules = {lock: json.loads(checked(rules_directory / f'd15-lock-{lock}-source-fields-private.json', identity))
             for lock, identity in RULE_IDENTITIES.items()}
    bindings, proof = source_bindings(profile, models, rules)
    return profile, bindings, proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source-cache', 'mesh-bundle', 'lightning-bundle', 'ground-texture-bundle',
                 'ice-texture-bundle', 'profile', 'model-tracks', 'rules', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    profile, bindings, event_proof = read_inputs(args.profile, args.model_tracks, args.rules)
    extra = {name: (getattr(args, attr), (size, digest))
             for name, (attr, size, digest) in ADDITIONAL_SOURCES.items()}
    objects = OriginalObjects(args.source_cache, args.mesh_bundle, additional_sources=extra)
    output = private_output(args.output)
    require(not any(output.iterdir()), 'Recovered skill output must be empty')
    cache = output / 'source-inputs-private'; cache.mkdir(mode=0o700)
    cache_receipt = prepare_cache(objects, cache, effects=PREFABS, material_scope=MATERIAL_SCOPE,
        expected_emitters=38, selected_systems=SYSTEMS, schema='recovered-d15-skill-source-inputs-v1')
    cache_receipt['files'] = [dict(name=str(path.relative_to(cache)), bytes=path.stat().st_size, sha256=sha(path.read_bytes()))
                              for path in sorted(cache.rglob('*')) if path.is_file()]
    save_json(cache / 'source-cache-recovery-receipt-private.json', cache_receipt)
    destination = output / 'runtime'; destination.mkdir(mode=0o700)
    assets = SourceAssets(args.source_cache, cache, destination, bundle_identity=BUNDLE)
    effect, scope, proof = sample_eye(assets)
    effects, scopes, proofs = {EYE: effect}, {EYE: scope}, {EYE: proof}
    for name, (prefab, systems, count) in EFFECTS.items():
        effects[name], scopes[name], proofs[name] = sample_impact(assets, name, prefab, systems, count)
    for name, effect in effects.items():
        bindings[name]['lifetimeTicks'] = math.ceil(effect['duration'] * 60)
    require(sum(len(scope['boundEmitters']) for scope in scopes.values()) == 38 and
            sum(len(scope['unboundEmitters']) for scope in scopes.values()) == 9 and
            all(scope['completePrefab'] is False for scope in scopes.values()), 'Original partial scope changed')
    document = dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        files=sorted(assets.files.values(), key=lambda row: row['name']), materials=assets.materials,
        effects=effects, bindings=[], markers=[], erlangSkillBindings=list(bindings.values()), erlangSkillScopes=scopes,
        recoveredSourceModelsSHA256=MODEL_IDENTITY[1],
        evidence=['The existing original Eye 15/19, Earth 15/19 and Meditation 8/9 whitelist is sampled without algorithm changes.',
            'Recovered original objects resolve through exact CAB/PPtr identities; full source bundles and source rule documents are pinned.',
            'Current neck actor and all three independent source model clocks match exactly.',
            'Actor head, captured pelvis and model Parent chest are distinct from collision anchors.',
            'Nine omitted emitters, separate eye-ground/mirrored prefabs and other conditional D15 effects remain unbound.',
            'No historical private manifest is impersonated; native shader compilation and rendering are unverified.'])
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    require(len(raw) < 256_000_000 and len(compressed) < 32_000_000, 'Recovered skill output exceeds bounds')
    name = 'SF3_D15_SkillEffects.json'
    write_private(destination / name, raw); write_private(destination / (name + '.gz'), compressed)
    receipt = dict(schema='recovered-d15-skill-runtime-v1', profileSHA256=PROFILE_SHA, characterSHA256=CHARACTER_SHA,
        sourceModelCandidateSHA256=MODEL_IDENTITY[1],
        sourceRuleIdentities={str(lock): dict(bytes=value[0], sha256=value[1]) for lock, value in RULE_IDENTITIES.items()},
        sourceCacheReceiptSHA256=sha((cache / 'source-cache-recovery-receipt-private.json').read_bytes()),
        sourceBindings=bindings, sourceEffects=proofs, sourceAssets=assets.audit, **event_proof,
        derivedFile=dict(name=name + '.gz', bytes=len(compressed), sha256=sha(compressed)),
        fullPrefabsBound=False, nativeRenderingVerified=False, productionPinsChanged=False)
    save_json(output / 'skill-recovery-private.json', receipt)
    print(json.dumps(dict(**receipt['derivedFile'], materials=len(assets.materials), resources=len(assets.files),
        effects={name: dict(tracks=len(effect['tracks']), lifetimeTicks=bindings[name]['lifetimeTicks'],
            boundEmitters=len(scopes[name]['boundEmitters']), unboundEmitters=len(scopes[name]['unboundEmitters']))
            for name, effect in effects.items()})), flush=True)


if __name__ == '__main__':
    main()
