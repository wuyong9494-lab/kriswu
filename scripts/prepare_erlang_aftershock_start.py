#!/usr/bin/env python3
"""Prepare the two original aftershock-start layers outside the runtime bundle.

This source-only export cannot activate a production effect. The original
ground_locator parent transform remains unproved. Particle curves, local
orientation and source materials can be recovered independently of that
attachment; no actor ground position is fabricated here.
"""
from __future__ import annotations

import argparse
import copy
import gzip
import json
import random
import warnings
from pathlib import Path

from erlang_effect_materials import sha, save_json
from erlang_skill_effect_materials import AFTERSHOCK_START_MATERIALS
from prepare_erlang_hound_effects import BUNDLE, inventory
from sun_triad_assets import matrix, private_output, require, write_private
from sun_triad_particle_assets import SourceAssets
from sun_triad_particle_curves import minmax
from sun_triad_particle_sort import source_queue
from sun_triad_particles import emission_schedule, sample_particle, seed


EFFECT = 'D15_axe_earthquake_explosion_start(ground_locator)'
PREFAB_ID = 8240435909269784876
SYSTEMS = {
    -8680226265545438932: 'a7ae18b4e26afd44b8dffaad8bd2f3576a08de75db537c9d2c52f4f8449eadff',
    -34291127408916180: '0469658fbcdfd7c508f984fd6d0f060f2010c2d0d2e93772f8bc5d44b1c8d7e0',
}
DISABLED_ROOT = -8965045093035341524
TIMER = 'SET_D15_AFTERSHOCK_FX_TIMER'
TIMER_TICKS = 100
SOURCE_EVENT = 'D15_Ground_FX'
FILE = 'D15_AftershockStart_Source.json.gz'
INPUTS = {
    ('Material', '-2562211360462363860'): AFTERSHOCK_START_MATERIALS[-2562211360462363860][1],
    ('Texture2D', '5044707271281776510'): '15bc1450f3a72ce1e655f30ba159431d1952acf5942d1ab26f6f26c78493c324',
    ('Texture2D', '482803268541587901'): '0e902dfefd88aa0123ebaab9d87c6f984fdb3fee31379b7d35edf3c43e76c145',
}


def source_lifecycle(rows):
    """Keep the actual three source triggers; compact field 10 is Looped.

    This validates source preparation only. It does not prove the eventual
    ground-locator world transform or permit a runtime binding.
    """
    def trigger(index):
        found = [r for r in rows if r.get('triggerIndex') == index]
        require(len(found) == 1, 'Missing or ambiguous original aftershock trigger')
        return found[0]

    timer, start, stop = (trigger(i) for i in (42, 43, 45))
    require(timer['events'] == start['events'] == [{'a18': ['enum65537', SOURCE_EVENT]}],
            'Original aftershock start event differs')
    timers = [a['a171'] for a in timer['actions'] if 'a171' in a]
    require(timers == [[TIMER, 'enum65537', 1, TIMER_TICKS, None]],
            'Original aftershock duration differs')
    require(start['actions'] == [{'a46': [EFFECT, None, 'ground_locator', None, 'enum65537', 1,
        None, None, None, None, True, [0., 0., 0.], None, [0., 4., 0.], None, None]}],
        'Original aftershock attachment differs')
    require(stop['events'] == [{'a44': ['enum65537', TIMER]}],
            'Original aftershock stop event differs')
    destroys = [a['a49'] for a in stop['actions'] if 'a49' in a]
    require(destroys == [[EFFECT, 'enum65537', None, None, None]],
            'Original aftershock immediate destruction differs')
    return dict(sourceLock=1454, timerTrigger=42, startTrigger=43, stopTrigger=45,
        sourceEvent=SOURCE_EVENT, sourceTimer=TIMER, sourceTimerTicks=TIMER_TICKS,
        sourceAttachToLocal=False, sourceLooped=True, sourceFollow=[0, 0, 0],
        sourceShiftCentimeters=[0., 4., 0.], sourceDestroyFrames=0,
        sourceTriggers=copy.deepcopy([timer, start, stop]),
        groundParentTransformVerified=False, runtimeBound=False)


def validate_particle(source, renderer):
    require(renderer['m_Enabled'] and renderer['m_RenderMode'] == 0 and renderer['m_RenderAlignment'] == 2,
            'Original aftershock local billboard differs')
    require(not source['looping'] and not source['prewarm'] and source['simulationSpeed'] == .5 and
            source['moveWithTransform'] == 0 and source['scalingMode'] == 1,
            'Original aftershock particle clock differs')
    require(not any(source[k]['enabled'] for k in ('ShapeModule', 'VelocityModule', 'ForceModule',
        'NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule')),
        'Unsupported original aftershock particle module')
    require(source['InitialModule']['gravityModifier']['scalar'] == 0 and
            source['InitialModule']['startSpeed']['scalar'] == 0 and
            renderer['m_Pivot'] == {'x': 0., 'y': 0., 'z': 0.} and
            renderer['m_Flip'] == {'x': 0., 'y': 0., 'z': 0.},
            'Original stationary aftershock particle differs')
    require(len(renderer['m_Materials']) == 1 and renderer['m_SortMode'] == 0 and
            renderer['m_SortingLayer'] == renderer['m_SortingLayerID'] == renderer['m_SortingFudge'] == 0 and
            renderer['m_SortingOrder'] == 2 and renderer['m_VertexStreams'] == [0, 1, 3, 4],
            'Original aftershock stream or order differs')


def sample_effect(assets):
    path, rows = inventory(assets.environment, EFFECT, PREFAB_ID)
    controllers = [c for c in rows[0]['components'] if c.type.name == 'MonoBehaviour' and
                   'overrideDuration' in c.read_typetree()]
    require(len(controllers) == 1, 'Ambiguous original aftershock controller')
    controller_object = controllers[0]; controller = controller_object.read_typetree()
    require(controller['overrideDuration'] == 1 and controller['duration'] == 5 and
            not controller['delayedEffects'] and all(controller[k] == 0 for k in (
                'ignoreTimeScale', 'reactToDissolveModel', 'takeInAccountCharacterDirection', '_useMirroring',
                '_inverseMirroring', '_ignoreFlipByZ', '_flipByAccountCharacterDirection',
                '_rotateAttachToLocal', '_trackingAccountModelDirection')),
            'Unsupported original aftershock controller')
    worlds, active, tracks, proofs, disabled = {}, {}, [], [], []
    observed = set()
    # A local billboard is an original unit quad transformed by the sampled
    # emitter/particle quaternion. It must not become a camera-facing quad.
    quad = dict(positions=[-.5,-.5,0,.5,-.5,0,.5,.5,0,-.5,.5,0], normals=[0,0,1]*4,
        uv=[0,1,1,1,1,0,0,0], tangents=[1,0,0,1]*4, indices=[0,1,2,0,2,3])
    for row in rows:
        local = matrix(row['position'], row['rotation'], row['scale'])
        world = worlds[row['parent']] @ local if row['parent'] is not None else local
        worlds[row['pathID']] = world
        active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
        systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
        if not systems: continue
        renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
        require(len(systems) == len(renderers) == 1, 'Ambiguous original aftershock emitter')
        obj, renderer_object = systems[0], renderers[0]
        source, renderer = obj.read_typetree(), renderer_object.read_typetree()
        proof = dict(sourceParticleSystem=str(obj.path_id), sourceParticleSystemSHA256=sha(obj.get_raw_data()),
            sourceRendererPathID=str(renderer_object.path_id), sourceRendererSHA256=sha(renderer_object.get_raw_data()))
        if obj.path_id == DISABLED_ROOT:
            require(not renderer['m_Enabled'] and not source['EmissionModule']['enabled'],
                    'Original disabled aftershock root acquired emissions')
            disabled.append(proof); continue
        require(active[row['pathID']] and obj.path_id in SYSTEMS and
                proof['sourceParticleSystemSHA256'] == SYSTEMS[obj.path_id], 'Original aftershock source identity differs')
        require(obj.path_id not in observed, 'Repeated original aftershock emitter')
        observed.add(obj.path_id); validate_particle(source, renderer)
        material_id = assets.material(renderer['m_Materials'][0]); material = assets.materials[material_id]
        require(int(material_id[2:]) in AFTERSHOCK_START_MATERIALS and
                material['sourceMaterialSHA256'] == AFTERSHOCK_START_MATERIALS[int(material_id[2:])][1],
                'Original aftershock material differs')
        representative = material['textures']['_MainTex']
        binding = next(m for m in assets.shader_document['materials']
            if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
        original_material = json.loads(Path(binding['metadataFile']).read_bytes())
        shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == binding['shaderPathID'])
        subshaders = json.loads(Path(shader['parsedFile']).read_bytes())['m_SubShaders']
        require(len(subshaders) == 1, 'Ambiguous original aftershock subshader')
        tags = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
        require(len(tags) == 1, 'Original aftershock Queue tag is ambiguous')
        queue = source_queue(original_material['m_CustomRenderQueue'], tags[0])
        emitter = str(obj.path_id)
        delay = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / .5
        require(delay == 0, 'Original aftershock birth delay differs')
        births = list(emission_schedule(source, emitter))
        require(len(births) == 1 and births[0][1:] == (0, None), 'Original aftershock single burst differs')
        particle = births[0][0]
        sampled, sample_proof = sample_particle(source, renderer, world, row['scale'], particle,
            project_gravity=assets.gravity, sample_until=TIMER_TICKS / 60)
        blend = material['raster']
        track = dict(name=row['name']+'_'+emitter+'_0', layer=row['layer'], material=material_id,
            texture=representative['file'], blend='replace' if blend['destination'] == 0 else 'add' if blend['destination'] == 1 else 'alpha',
            wrapS=representative['wrapS'], wrapT=representative['wrapT'], multiplyTextureAlpha=blend['source'] == 5,
            overlay=False, sortingOrder=2, delay=0., duration=sampled['frames'][-1][0],
            vertexStreams=renderer['m_VertexStreams'], sourceRenderMode=0, sourceRenderAlignment=2,
            sourceSimulationSpace=0, sourceParticleSystem=emitter, sourceSortMode=0, sourceSortingLayer=0,
            sourceRenderQueue=queue, sourceAgeOffset=0., geometry=copy.deepcopy(quad),
            stableRandom=[particle.r('stableRandom'+str(i)) for i in range(4)], **sampled)
        tracks.append(track)
        proofs.append(dict(**proof, sourceMaterialSHA256=material['sourceMaterialSHA256'],
            sourceParticleLifetime=particle.life, sourceSimulationSpeed=.5, sourceFullLifetimeSeconds=particle.life/.5,
            sampledUntilLiveTick=TIMER_TICKS, sample=sample_proof))
    require(observed == set(SYSTEMS) and len(disabled) == 1, 'Original aftershock active scope differs')
    return dict(sourceName=path, duration=TIMER_TICKS/60, tracks=tracks, sourceDurationOverride=5.,
        sourceController={k:v for k,v in controller.items() if k not in ('m_GameObject','m_Script','m_Name','m_Enabled')}), dict(
        sourceControllerPathID=str(controller_object.path_id), sourceControllerSHA256=sha(controller_object.get_raw_data()),
        sourceTransforms=[{k:r[k] for k in ('name','pathID','parent','position','rotation','scale')} for r in rows],
        activeEmitters=proofs, disabledEmitters=disabled)


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    rules_raw = args.rules.read_bytes(); lifecycle = source_lifecycle(json.loads(rules_raw))
    sources = [json.loads(p.read_bytes()) for p in args.source_inputs]
    records = [r for source in sources for r in source['records'] if (r['type'], str(r['pathID'])) in INPUTS]
    require({(r['type'], str(r['pathID'])) for r in records} == set(INPUTS), 'Missing original aftershock source input')
    for record in records:
        expected = INPUTS[(record['type'], str(record['pathID']))]
        require(record['sourceObjectSHA256'] == expected and sha(Path(record['rawFile']).read_bytes()) == expected,
                'Original aftershock input bytes differ')
    bindings = json.loads((args.materials / 'd15-skill-shader-bindings-private.json').read_bytes())
    require({int(m['sourcePathID']):m['sourceObjectSHA256'] for m in bindings['materials']} ==
            {k:v[1] for k,v in AFTERSHOCK_START_MATERIALS.items()}, 'Original aftershock material scope differs')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'New aftershock source output must be empty')
    source_records = output / 'additional-records-private.json'; save_json(source_records, dict(records=records))
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE,
        shader_bindings=args.materials/'d15-skill-shader-bindings-private.json',
        program_bindings=args.materials/'d15-skill-metal-programs-private.json', additional_records=source_records)
    effect, proof = sample_effect(assets)
    document = dict(schema='original-d15-aftershock-start-source-v1', sourceBundleSHA256=BUNDLE[1],
        sourceOnly=True, runtimeBound=False, groundParentTransformVerified=False, sampleRate=60,
        worldUnitsPerSourceUnit=.01, sourceActiveEmitters=2, boundSourceEmitters=sorted(map(str,SYSTEMS)),
        sourceLifecycle=lifecycle, effect=effect, materials=assets.materials,
        files=sorted(assets.files.values(),key=lambda r:r['name']),
        boundary='Particle/source preparation only. Not an App manifest; original FME+0xc8 parent transform remains unproved.')
    raw=json.dumps(document,separators=(',',':'),allow_nan=False).encode();compressed=gzip.compress(raw,mtime=0)
    require(len(raw)<8_000_000 and len(compressed)<4_000_000, 'Aftershock source output exceeds bounds')
    write_private(output/FILE,compressed)
    receipt=dict(schema='original-d15-aftershock-start-source-receipt-v1', sourceBundleSHA256=BUNDLE[1],
        sourceRulesSHA256=sha(rules_raw),sourceLifecycle=lifecycle,sourceEffect=proof,sourceAssets=assets.audit,
        derivedFile=dict(name=FILE,bytes=len(compressed),sha256=sha(compressed)),
        runtimeBound=False,groundParentTransformVerified=False,engineParityVerified=False)
    save_json(output/'aftershock-start-source-receipt-private.json',receipt)
    print(json.dumps(dict(**receipt['derivedFile'],sourceEmitters=2,sourceTracks=len(effect['tracks']),
        runtimeBound=False,groundParentTransformVerified=False)),flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('models','effects','materials','rules','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--source-inputs',type=Path,nargs='+',required=True)
    build(parser.parse_args())
