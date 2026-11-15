#!/usr/bin/env python3
"""Bind a bounded original D15 skill-FX scope to actual actor source events.

This first group contains fifteen original normal-eye emitters. Four stretched
billboards and the separate ground/mirrored prefabs remain explicitly unbound.
No source mesh, material, texture or shader program is replaced.
"""
from __future__ import annotations
import argparse
import gzip
import json
import math
import random
import warnings
from pathlib import Path

from sun_triad_assets import matrix, private_output, require, write_private
from sun_triad_particle_assets import SourceAssets
from sun_triad_particle_curves import minmax
from sun_triad_particle_sort import source_queue
from sun_triad_particles import emission_schedule, sample_particle, seed
from prepare_erlang_hound_effects import BUNDLE, CONFIGURATION_SHA, inventory
from erlang_effect_materials import sha, save_json
from erlang_skill_effect_materials import LASER_MATERIALS

EFFECT = 'D15_fx_laser(head)'
ROLE = 'erlangSummon_eye'
PREFAB_ID = -5192418016562058810
CLIP_SHA = 'c05c657b4eafdbe0e8785ea5672050fece08d4620d52f76e0bd401f77957645f'
MODEL_SHA = '870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc'
MESH_SYSTEMS = {4389738783310277062, 4874788005116766662, 4004109905803078086,
    -4068766315815769658, 437460551336847814, -7681221522103801402,
    6538040511092746694, 3578977847684098502, 8513289964012497350,
    -818232598598915642, -4037953332193531450}
BILLBOARD_SYSTEMS = {-7425472578249299514, -3566723147490924090,
                    -8859074932072453690, -2536699185572353594}
SYSTEMS = MESH_SYSTEMS | BILLBOARD_SYSTEMS
RELEASE = dict(id='d15_create_105', ability='eye', ownerRole='erlangEye', atTick=122,
    modelRole=ROLE, anchor='head.x', offset=[0., 0., 0.], minimumLevel=2)
TEXTURE_INPUT_SHA = '6d37f512a036582a490ea501d59b4859296859369bdd24fc7d4b0016bbfa605a'
MESH_INPUT_SHA = '89ed56828338e7acd5c26f1b39c340fe18d7ab2bb1be2a89548dfdd0a650a648'


def source_binding(profile, model_path, rules_path):
    """Bind the real release event; the collision model does not supply head FK."""
    model_raw = model_path.read_bytes()
    require(sha(model_raw) == MODEL_SHA, 'Reviewed D15 model input differs')
    source_track = next(t for t in json.loads(model_raw)['summonTracks'] if t['role'] == ROLE)
    require([t for t in profile.get('summonTracks', []) if t['role'] == ROLE] == [source_track],
            'Final actor lacks the exact original eye model track')
    require(profile['roles'].get('erlangEye') == 'd15_avatara_laser', 'Original eye role differs')
    clips = [c for c in profile['clips'] if c['name'] == 'd15_avatara_laser']
    require(len(clips) == 1, 'Original eye clip is ambiguous')
    clip = clips[0]
    require(clip['sha256'] == CLIP_SHA and clip['frames'] == 149 and clip['playbackTicks'] == 296 and
            clip['sourceFirstIndex'] == 0 and clip['sourceLastIndex'] == 148 and
            clip['sourceEndEventTick'] == 288, 'Original eye source clock differs')
    configuration = clip['sourceConfiguration']
    require(configuration['sourceEntry'] == 'settings_sets_dynasty.bytes' and
            configuration['sourceSHA256'] == CONFIGURATION_SHA and configuration['sourceRecordIndex'] == 104,
            'Original eye configuration identity differs')
    motion = configuration['configuration']
    require(motion['Mirrored'] is None and motion['MidFrames'] is None and
            [i for i in motion['Intervals'] if i['Name'] == 'D15_Laser_Fx'][0]['Start'] == 62,
            'Original unmirrored eye interval differs')
    require([r for r in profile['erlangRules']['releases'] if r['modelRole'] == ROLE] == [RELEASE],
            'Runtime eye release does not match the original interval')
    rules_raw = rules_path.read_bytes(); rules = json.loads(rules_raw)
    create = next(r for r in rules if r['triggerIndex'] == 50)
    effect = next(r for r in rules if r['triggerIndex'] == 53)
    require(create['events'] == effect['events'] == [{'a18': ['enum65537', 'D15_Laser_Fx']}],
            'Original model/effect events differ')
    require(effect['actions'][0] == {'a46': [EFFECT, None, 'head', None, 'enum65537', 1,
            None, True, None, None, False, [1., 1., 1.], None, [0., 0., 0.], None, None]},
            'Original head attachment differs')
    require(effect['conditions'][1] == {'Not': [{'expr': [{'f65': [{'f74': ['enum65537']}]}, 1., 'op22']}]},
            'Original non-mirrored branch differs')
    return dict(id='d15_laser_plain_head', role=ROLE, ownerRole='erlangEye', effect=EFFECT,
        bone='head', attachToLocal=True, follow=[1, 1, 1], shift=[0., 0., 0.],
        sourceLock=1432, sourceTrigger=53, sourceEvent='D15_Laser_Fx',
        sourceRecordIndex=104, sourceClip='d15_avatara_laser', sourceMotionSHA256=CLIP_SHA,
        sourceIntervalStart=62, release=RELEASE, track=source_track,
        sourceModelEndTick=122), dict(sourceRulesSHA256=sha(rules_raw),
            sourceCreateTrigger=create, sourceEffectTrigger=effect)


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'New skill output must be empty')
    texture_raw = args.texture_inputs.read_bytes()
    require(sha(texture_raw) == TEXTURE_INPUT_SHA, 'Recovered original laser textures differ')
    texture_inputs = json.loads(texture_raw)
    require(not texture_inputs['missing'] and len(texture_inputs['records']) == 4,
            'Original laser texture recovery is incomplete')
    material_records = json.loads((args.materials / 'd15-skill-additional-materials-private.json').read_bytes())
    additions = output / 'additional-source-objects-private.json'
    save_json(additions, dict(records=material_records['records'] + texture_inputs['records']))
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE,
        shader_bindings=args.materials / 'd15-skill-shader-bindings-private.json',
        program_bindings=args.materials / 'd15-skill-metal-programs-private.json', additional_records=additions)
    require({int(m['sourcePathID']): m['sourceObjectSHA256'] for m in assets.shader_document['materials']} ==
            {k: v[1] for k, v in LASER_MATERIALS.items()}, 'Original laser material scope differs')
    mesh_raw = args.mesh_inputs.read_bytes()
    require(sha(mesh_raw) == MESH_INPUT_SHA, 'Recovered original lightning mesh receipt differs')
    mesh_inputs = json.loads(mesh_raw)
    require(not mesh_inputs['missing'] and len(mesh_inputs['records']) == 1, 'Original lightning mesh is missing')
    mesh = mesh_inputs['records'][0]
    require(mesh['type'] == 'Mesh' and mesh['pathID'] == '-6622822173136016352' and
            mesh['bundleEvidence']['sourceBundle'] == '08db602bdc0f7c37fd88caf15e23217e.bin' and
            mesh['bundleEvidence']['catalogBundleSHA256'] == '537fe25fd4f13206e52768c3a33d3843f40435b64a71fb5e4d9e32e4c009fc5d' and
            sha(Path(mesh['rawFile']).read_bytes()) == mesh['sourceObjectSHA256'] ==
            '476d50be9a7fc74eae8ca77ba85d38afa82945e02b98d7bf0ab4d837dd31b48c', 'Original lightning mesh identity differs')
    assets.mesh_records.append(mesh)
    profile_raw = args.profile.read_bytes(); profile = json.loads(profile_raw)
    require(profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64, 'Wrong skill actor profile')
    binding, event_proof = source_binding(profile, args.model_tracks, args.rules / 'd15-lock-1432-compact-private.json')
    path, rows = inventory(assets.environment, EFFECT, PREFAB_ID)
    controllers = [c.read_typetree() for c in rows[0]['components'] if c.type.name == 'MonoBehaviour'
                   and 'overrideDuration' in c.read_typetree()]
    require(len(controllers) == 1, 'Ambiguous original laser controller')
    controller = controllers[0]
    require(controller['overrideDuration'] == 0 and not controller['delayedEffects'] and
            controller['takeInAccountCharacterDirection'] == 1 and all(controller[k] == 0 for k in
            ('ignoreTimeScale', 'reactToDissolveModel', '_useMirroring', '_inverseMirroring', '_ignoreFlipByZ',
             '_flipByAccountCharacterDirection', '_rotateAttachToLocal', '_trackingAccountModelDirection')),
            'Unadapted laser controller behavior')
    worlds, active, tracks, receipts, omitted, observed = {}, {}, [], [], [], set()
    for row in rows:
        local = matrix(row['position'], row['rotation'], row['scale'])
        world = worlds[row['parent']] @ local if row['parent'] is not None else local
        worlds[row['pathID']] = world
        active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
        systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
        if not systems: continue
        renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
        require(len(systems) == len(renderers) == 1, 'Ambiguous original laser emitter')
        system, renderer = systems[0], renderers[0]
        source, render = system.read_typetree(), renderer.read_typetree()
        require(active[row['pathID']] and render['m_Enabled'], 'Original laser active-emitter inventory differs')
        proof = dict(sourceParticleSystem=str(system.path_id), sourceParticleSystemSHA256=sha(system.get_raw_data()),
            sourceRendererPathID=str(renderer.path_id), sourceRendererSHA256=sha(renderer.get_raw_data()))
        if system.path_id not in SYSTEMS:
            require(render['m_RenderMode'] == 1, 'Uninventoried original laser emitter')
            omitted.append(dict(**proof, sourceName=row['name'], bindingStatus='stretched_billboard_direction_unbound'))
            continue
        observed.add(system.path_id)
        is_mesh = system.path_id in MESH_SYSTEMS
        require(not any(source[k]['enabled'] for k in ('NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule', 'ForceModule'))
                and not source['prewarm'] and not source['looping'] and source['moveWithTransform'] == 0 and
                source['InitialModule']['gravityModifier']['scalar'] == 0 and
                (render['m_RenderMode'], render['m_RenderAlignment']) == ((4, 2) if is_mesh else (0, 0)),
                'Original laser emitter requires an unsupported adapter')
        require(len(render['m_Materials']) == 1 and render['m_SortMode'] in (0, 2, 3, 4) and
                render['m_SortingLayer'] == render['m_SortingLayerID'] == render['m_SortingFudge'] == 0,
                'Original laser sorting differs')
        material_id = assets.material(render['m_Materials'][0]); material = assets.materials[material_id]
        shader_binding = next(m for m in assets.shader_document['materials'] if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
        source_material = json.loads(Path(shader_binding['metadataFile']).read_text())
        shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == shader_binding['shaderPathID'])
        subshaders = json.loads(Path(shader['parsedFile']).read_text())['m_SubShaders']
        require(len(subshaders) == 1, 'Ambiguous original laser subshader')
        tags = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
        require(len(tags) == 1, 'Original laser render queue is absent')
        queue = source_queue(source_material['m_CustomRenderQueue'], tags[0])
        geometry = assets.geometry(render['m_Mesh']) if is_mesh else None
        speed, emitter = source['simulationSpeed'], str(system.path_id)
        delay0 = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / speed
        samples = []
        for particle, birth, period in emission_schedule(source, emitter):
            require(period is None, 'Original nonlooping laser acquired a loop')
            sampled, sample_proof = sample_particle(source, render, world, row['scale'], particle, project_gravity=assets.gravity)
            if not is_mesh:
                sampled.pop('orientations', None); sampled.pop('depthScales', None)
            blend = material['raster']
            track = dict(name=row['name'] + '_' + emitter + '_' + str(particle.index), layer=row['layer'],
                material=material_id, texture=material['textures']['_MainTex']['file'],
                blend='add' if blend['destination'] == 1 else 'alpha', wrapS=material['textures']['_MainTex']['wrapS'],
                wrapT=material['textures']['_MainTex']['wrapT'], multiplyTextureAlpha=blend['source'] == 5,
                overlay=False, sortingOrder=render['m_SortingOrder'], delay=round(delay0 + birth / speed, 7),
                duration=sampled['frames'][-1][0], vertexStreams=render['m_VertexStreams'],
                sourceRenderMode=render['m_RenderMode'], sourceRenderAlignment=render['m_RenderAlignment'], sourceSimulationSpace=0,
                sourceParticleSystem=emitter, sourceSortMode=render['m_SortMode'], sourceSortingLayer=0,
                sourceRenderQueue=queue, sourceAgeOffset=0., stableRandom=[particle.r('stableRandom' + str(i)) for i in range(4)], **sampled)
            if geometry is not None: track['geometry'] = geometry
            tracks.append(track); samples.append(sample_proof)
        receipts.append(dict(**proof, sourceMaterialSHA256=material['sourceMaterialSHA256'], samples=samples))
    require(observed == SYSTEMS and len(omitted) == 4, 'Original laser fifteen-of-nineteen scope differs')
    duration = max(t['delay'] + t['duration'] for t in tracks)
    binding['lifetimeTicks'] = math.ceil(duration * 60)
    effect = dict(sourceName=path, duration=duration, tracks=tracks, sourceController={k: v for k, v in controller.items()
        if k not in ('m_GameObject', 'm_Script', 'm_Name', 'm_Enabled')})
    scope = dict(sourceActiveEmitters=19, boundEmitters=sorted(map(str, SYSTEMS)),
        unboundEmitters=[p['sourceParticleSystem'] for p in omitted], completePrefab=False,
        sourceMirroredVariantBound=False, separateGroundPrefabBound=False)
    document = dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        evidence=['Fifteen original normal-eye emitters are bound: eleven meshes and four standard billboards; four stretched emitters remain unbound.',
            'The original interval starts at source frame 62 / live tick 122 and shares the actual source eye model creation event.',
            'The visual copies the current original actor head world pose with scale removed; the collision-model origin is never used as its head.',
            'The separate ground prefab and mirrored-eye branch are not part of this first group.',
            'Original local particle simulation, curves, mesh geometry, textures and exact shader variants are retained; native pixel parity is unverified.'],
        files=sorted(assets.files.values(), key=lambda f: f['name']), materials=assets.materials,
        effects={EFFECT: effect}, bindings=[], markers=[], erlangSkillBindings=[binding], erlangSkillScopes={EFFECT: scope})
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode(); compressed = gzip.compress(raw, mtime=0)
    require(len(raw) < 256_000_000 and len(compressed) < 32_000_000, 'Source skill export exceeds loader bounds')
    write_private(output / 'SF3_D15_SkillEffects.json', raw); write_private(output / 'SF3_D15_SkillEffects.json.gz', compressed)
    receipt = dict(schema='original-d15-skill-effects-v1', sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
        sourceModelCandidateSHA256=MODEL_SHA, sourceTextureInputSHA256=sha(texture_raw), sourceMeshInputSHA256=sha(mesh_raw),
        sourceTransforms=[{k: r[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for r in rows],
        boundEmitters=receipts, unboundEmitters=omitted, sourceAssets=assets.audit, **event_proof,
        profileSHA256=sha(profile_raw), characterSHA256=profile['sha256'], sourceBinding=binding,
        derivedFile=dict(name='SF3_D15_SkillEffects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        fullPrefabBound=False, engineParityVerified=False)
    save_json(output / 'd15-skill-effects-receipt-private.json', receipt)
    print(json.dumps(dict(**receipt['derivedFile'], sourceEmitters=19, boundEmitters=15, lifetimeTicks=binding['lifetimeTicks'],
        tracks=len(tracks), materials=len(assets.materials), resources=len(assets.files))), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models', 'effects', 'profile', 'model-tracks', 'rules', 'materials', 'texture-inputs', 'mesh-inputs', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    build(parser.parse_args())
