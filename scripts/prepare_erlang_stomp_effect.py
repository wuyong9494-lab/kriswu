#!/usr/bin/env python3
"""Prepare the three original mesh emitters that make D15's large leg visible.

This deliberately scoped export does not stand in for ground cracks, laser,
hovering swords or other D15 effects. It uses existing local source bundles.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import random
import warnings
from pathlib import Path

from sun_triad_assets import matrix, private_output, require, write_private
from sun_triad_particle_assets import SourceAssets
from sun_triad_particle_curves import minmax
from sun_triad_particle_sort import source_queue
from sun_triad_particles import emission_schedule, sample_particle, seed
from prepare_erlang_hound_effects import BUNDLE, CONFIGURATION_SHA, inventory
from erlang_effect_materials import prepare_materials, MATERIALS

MODEL_SHA = '870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc'
ROLE = 'erlangSummon_stomp'
EFFECT = 'D15_fx_big_leg'
PREFAB_ID = -8069839089656887436
SYSTEMS = {-929469514926225548, 6055453625588746100, -1006497375095126156}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write_json(path, value):
    write_private(path, json.dumps(value, separators=(',', ':'), allow_nan=False).encode())


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'New stomp output must be empty')
    materials = args.material_sources
    if materials is None:
        materials = output / 'material-source-private'
        prepare_materials(args.models, args.archive, args.shader_bundle, materials)
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE,
        shader_bindings=materials / 'd15-shader-material-bindings-private.json',
        program_bindings=materials / 'd15-metal-material-patches-private.json',
        additional_records=materials / 'd15-additional-material-records-private.json')
    require({int(m['sourcePathID']): m['sourceObjectSHA256'] for m in assets.shader_document['materials']} ==
            {k: v[1] for k, v in MATERIALS.items()}, 'D15 leg material scope differs')
    source_raw = args.model_tracks.read_bytes()
    require(len(source_raw) == 653960 and sha(source_raw) == MODEL_SHA, 'Reviewed source model candidate differs')
    model_document = json.loads(source_raw)
    model = next(m for m in model_document['models'] if m['role'] == ROLE)
    track = next(t for t in model_document['summonTracks'] if t['role'] == ROLE)
    require(model['sourceAnimation'] == 'D15_Avatara_Leg_Model' and model['sourceRecordIndex'] == 100
            and model['effectiveLastTick'] == 18 and track['frames'] == 10, 'Original leg model clock differs')
    profile_raw = args.profile.read_bytes()
    profile = json.loads(profile_raw)
    require(profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64, 'Wrong character profile')
    rule_raw = (args.rules / 'd15-lock-1434-compact-private.json').read_bytes()
    rules = json.loads(rule_raw)
    trigger = next(r for r in rules if r['triggerIndex'] == 1)
    require(trigger['events'] == [{'a1': ['D15_Avatara_Leg_Model', 'enum65537']}]
            and trigger['actions'] == [{'a46': [EFFECT, None, 'magic_joint_root', None, 'enum65537', 1,
                None, None, None, None, False, [0., 0., 0.], None, [0., 0., 0.], None, None]}],
            'Original leg effect source event changed')
    path, rows = inventory(assets.environment, EFFECT, PREFAB_ID)
    controllers = [c.read_typetree() for c in rows[0]['components'] if c.type.name == 'MonoBehaviour'
                   and 'overrideDuration' in c.read_typetree()]
    require(len(controllers) == 1, 'Ambiguous source leg controller')
    controller = controllers[0]
    require(controller['takeInAccountCharacterDirection'] == 1 and not controller['overrideDuration']
            and not controller['delayedEffects'] and all(controller[k] == 0 for k in (
                'ignoreTimeScale', 'reactToDissolveModel', '_useMirroring', '_inverseMirroring',
                '_ignoreFlipByZ', '_flipByAccountCharacterDirection', '_rotateAttachToLocal',
                '_trackingAccountModelDirection')), 'Unadapted leg controller behavior')
    worlds, active, tracks, receipts, observed = {}, {}, [], [], set()
    for row in rows:
        local = matrix(row['position'], row['rotation'], row['scale'])
        world = worlds[row['parent']] @ local if row['parent'] is not None else local
        worlds[row['pathID']] = world
        active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
        systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
        if not systems:
            continue
        renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
        require(len(systems) == len(renderers) == 1, 'Ambiguous source leg emitter')
        system, renderer = systems[0], renderers[0]
        source, render = system.read_typetree(), renderer.read_typetree()
        require(active[row['pathID']] and render['m_Enabled'] and system.path_id in SYSTEMS,
                'Original leg active emitter scope differs')
        observed.add(system.path_id)
        require(not any(source[k]['enabled'] for k in ('NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule', 'ForceModule'))
                and not source['prewarm'] and not source['looping'] and source['moveWithTransform'] == 0
                and render['m_RenderMode'] == 4 and render['m_RenderAlignment'] == 2,
                'Unadapted original leg emitter module or mode')
        require(len(render['m_Materials']) == 1 and render['m_SortMode'] in (0, 2, 3, 4)
                and render['m_SortingLayer'] == render['m_SortingLayerID'] == render['m_SortingFudge'] == 0,
                'Unadapted original leg renderer sorting')
        material_id = assets.material(render['m_Materials'][0])
        material = assets.materials[material_id]
        binding = next(m for m in assets.shader_document['materials'] if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
        source_material = json.loads(Path(binding['metadataFile']).read_text())
        shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == binding['shaderPathID'])
        subshaders = json.loads(Path(shader['parsedFile']).read_text())['m_SubShaders']
        require(len(subshaders) == 1, 'Ambiguous original leg subshader')
        tags = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
        require(len(tags) == 1, 'Original leg render queue is absent')
        queue = source_queue(source_material['m_CustomRenderQueue'], tags[0])
        geometry = assets.geometry(render['m_Mesh'])
        speed, emitter = source['simulationSpeed'], str(system.path_id)
        delay0 = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / speed
        samples = []
        for particle, birth, period in emission_schedule(source, emitter):
            require(period is None, 'Original leg cannot acquire an invented loop')
            sampled, proof = sample_particle(source, render, world, row['scale'], particle, project_gravity=assets.gravity)
            blend = material['raster']
            delay = delay0 + birth / speed
            tracks.append(dict(name=row['name'] + '_' + emitter + '_' + str(particle.index), layer=row['layer'],
                material=material_id, texture=material['textures']['_MainTex']['file'],
                blend='add' if blend['destination'] == 1 else 'alpha', wrapS=material['textures']['_MainTex']['wrapS'],
                wrapT=material['textures']['_MainTex']['wrapT'], multiplyTextureAlpha=blend['source'] == 5,
                overlay=False, sortingOrder=render['m_SortingOrder'], delay=round(delay, 7),
                duration=sampled['frames'][-1][0], vertexStreams=render['m_VertexStreams'],
                sourceRenderMode=4, sourceRenderAlignment=2, sourceSimulationSpace=0,
                sourceParticleSystem=emitter, sourceSortMode=render['m_SortMode'], sourceSortingLayer=0,
                sourceRenderQueue=queue, sourceAgeOffset=0., stableRandom=[particle.r('stableRandom' + str(i)) for i in range(4)],
                geometry=geometry, **sampled))
            samples.append(proof)
        receipts.append(dict(sourceParticleSystem=emitter, sourceParticleSystemSHA256=sha(system.get_raw_data()),
            sourceRendererPathID=str(renderer.path_id), sourceRendererSHA256=sha(renderer.get_raw_data()),
            sourceMaterialSHA256=material['sourceMaterialSHA256'], samples=samples))
    require(observed == SYSTEMS and len(tracks) == 3, 'Original large leg requires all three original mesh emitters')
    binding = dict(id='d15_leg_animation_start', role=ROLE, effect=EFFECT, startTick=0,
        bone='magic_joint_root', attachToLocal=False, follow=[0, 0, 0], shift=[0, 0, 0],
        sourceLock=1434, sourceTrigger=1, sourceRecordIndex=100)
    effect = dict(sourceName=path, duration=round(max(t['delay'] + t['duration'] for t in tracks), 7),
        tracks=tracks, sourceDurationOverride=None,
        sourceController={k: v for k, v in controller.items() if k not in ('m_GameObject', 'm_Script', 'm_Name', 'm_Enabled')})
    document = dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        evidence=['All three original D15 large-leg mesh emitters, original mesh topology and exact keyword-matched shader programs.',
            'Original Follow XYZ=0 retains each observed model creation position; original particle lifetimes remain independent of the short collision model.',
            'One repeatable realization of the original automatic seed; Apple GPU and native parity remain unverified.',
            'Ground cracks and other D15 effects are outside this explicitly scoped manifest.'],
        files=sorted(assets.files.values(), key=lambda f: f['name']), materials=assets.materials,
        effects={EFFECT: effect}, bindings=[], markers=[], erlangModelBindings=[binding],
        erlangSourceModels={ROLE: dict(track=track, sourceAnimation=model['sourceAnimation'], sourceRecordIndex=100,
            bones=model['bones'], endEventTick=18)})
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    require(len(raw) <= 256_000_000 and len(compressed) <= 32_000_000, 'Source leg export exceeds loader bounds')
    write_private(output / 'SF3_D15_StompEffects.json', raw)
    write_private(output / 'SF3_D15_StompEffects.json.gz', compressed)
    receipt = dict(schema='original-d15-stomp-effect-v1', sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
        sourceModelCandidateSHA256=MODEL_SHA, sourceRulesSHA256=sha(rule_raw), sourceTrigger=trigger,
        sourceTransforms=[{k: x[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for x in rows],
        sourceEmitters=receipts, sourceAssets=assets.audit, sourceTrack=track,
        profileSHA256=sha(profile_raw), profileIncludesStompTrack=profile.get('summonTracks', []).count(track) == 1,
        characterSHA256=profile['sha256'], derivedFile=dict(name='SF3_D15_StompEffects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        sourceRulesBinding=binding, engineParityVerified=False)
    write_json(output / 'd15-stomp-effect-receipt-private.json', receipt)
    print(json.dumps(dict(file='SF3_D15_StompEffects.json.gz', bytes=len(compressed), sha256=sha(compressed),
        emitters=len(receipts), tracks=len(tracks), duration=effect['duration'], materials=len(assets.materials), resources=len(assets.files))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models', 'effects', 'model-tracks', 'profile', 'rules', 'archive', 'shader-bundle', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--material-sources', type=Path)
    build(parser.parse_args())


if __name__ == '__main__':
    main()
