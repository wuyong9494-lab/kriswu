#!/usr/bin/env python3
"""Bind the original D15 sword mesh and supported local particle layers.

Fifteen of the twenty high-preset emitters are supported. The three true Noise
emitters and two history Trail emitters remain explicitly unbound.
"""
from __future__ import annotations
import argparse
import gzip
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
from erlang_effect_materials import sha, save_json
from erlang_sword_materials import prepare_materials, MATERIALS

MODEL_SHA = '870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc'
HELD_SHA = '22cf4bd31691a19adeaf92b10e745ca452c4f5d31ac390893a742527caf6b55e'
EFFECT = 'D15_fx_sword_jian_glow(weapon_r)'
PREFAB_ID = -8276785478031651511
MESH_ID = 5887294323812191014
MESH_SHA = '0edd33e67555bbf4ac7734f01e76739f1024aba303533ae887662e9a3fe8b2d9'
SPIRAL_MESH_ID = -5016584381919525391
SPIRAL_MESH_SHA = '8a89cc51d6a66d9a6b1219cb13592caafa18ddbd5464b43ff2eb3b12f79744ff'
SYSTEMS = {5893977911169764681, 8915268038863932745, -7834288011111445175,
           -1693366553794785975, -6545597049206092471, -5291293020077044407}
START_SYSTEMS = {5893977911169764681, 8915268038863932745, -7834288011111445175}
PARTICLE_SYSTEMS = {
    997477216654708041: (0, False, 2),
    950755173834149193: (4, False, 6),
    -6073607809242968759: (0, False, 1),
    3969728038972542281: (0, False, 1),
    7805652981015170377: (0, False, 1),
    -1451493248556544695: (4, True, 6),
    -7112856168580788919: (0, True, 2),
    -8672275354168275639: (0, True, 2),
    -8714483650998121143: (0, True, 2),
}
SPIRAL_SYSTEMS = {k for k, (mode, _, _) in PARTICLE_SYSTEMS.items() if mode == 4}
PLANE_SYSTEMS = set(PARTICLE_SYSTEMS) - SPIRAL_SYSTEMS
BOUND_SYSTEMS = SYSTEMS | set(PARTICLE_SYSTEMS)
NOISE_SYSTEMS = {148819201852362057, -7290008168018162359, 4799608978381983049}
TRAIL_SYSTEMS = {3820729297464905033, -9101295511791219383}
TEXTURE_RECEIPT_SHA = 'd20c9b979142c15d59a2d88a69f25e84154d1dcd58857183f0e1d639b3665b33'
EXTRA_TEXTURES = {13838286893223568, -4782877046576669620, -6541556163830002439, -5666020059328954682}


def plane_geometry():
    # Unity mode0 uses the source billboard plane. Its serialized m_Mesh
    # pointer is inactive; reading that pointer as a mesh would be incorrect.
    return dict(positions=[-.5, -.5, 0, .5, -.5, 0, .5, .5, 0, -.5, .5, 0],
        normals=[0, 0, -1] * 4, uv=[0, 1, 1, 1, 1, 0, 0, 0], indices=[0, 2, 1, 0, 3, 2])


def source_models(profile, model_path, held_path):
    model_raw, held_raw = model_path.read_bytes(), held_path.read_bytes()
    require(sha(model_raw) == MODEL_SHA and sha(held_raw) == HELD_SHA, 'Reviewed source sword model candidate differs')
    model, held = json.loads(model_raw), json.loads(held_raw)
    attack = next(m for m in model['models'] if m['role'] == 'erlangSummon_sword')
    tracks = {t['role']: t for t in model['summonTracks'] + held['summonTracks']}
    result = {}
    for source in held['models'] + [attack]:
        role, motion = source['role'], source['motion']
        rotate = role == 'erlangSummon_swordRotate'
        require(source['sourceConfigurationSHA256'] == CONFIGURATION_SHA and
                motion['firstIndex'] == 0 and motion['frames'] == (1 if rotate else 51),
                'Original sword crop changed')
        track = None if rotate else tracks[role]
        if not rotate:
            require([t for t in profile.get('summonTracks', []) if t['role'] == role] == [track],
                    'Final actor lacks this exact original sword track: ' + role)
        root = source['bones']['magic_joint_root']
        require(len(root) == (1 if rotate else 101), 'Original sword root sample count changed')
        result[role] = dict(sourceAnimation=source['sourceAnimation'], sourceRecordIndex=source['sourceRecordIndex'],
            track=track, root=root, frames=motion['frames'],
            lastTick=0 if rotate else 70 if role == 'erlangSummon_sword' else 92)
    require(len(result) == 9, 'All six births, idle, one-sample rotate and attack are required')
    return result


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'New sword output must be empty')
    materials = args.material_sources
    if materials is None:
        materials = output / 'material-source-private'
        prepare_materials(args.models, args.archive, args.shader_bundle, args.cached_materials, materials)
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE,
        shader_bindings=materials / 'd15-sword-shader-bindings-private.json',
        program_bindings=materials / 'd15-sword-metal-programs-private.json',
        additional_records=materials / 'd15-sword-additional-materials-private.json')
    texture_raw = args.extra_textures.read_bytes()
    require(len(texture_raw) == 8854 and sha(texture_raw) == TEXTURE_RECEIPT_SHA,
            'Reviewed sword texture recovery receipt differs')
    texture_inputs = json.loads(texture_raw)
    require(not texture_inputs['missing'] and len(texture_inputs['records']) == 4 and
            {int(r['pathID']) for r in texture_inputs['records']} == EXTRA_TEXTURES and
            all(r['type'] == 'Texture2D' and r['externalCAB'] == 'CAB-901eba28f4c9f491c9323f34153174a5'
                for r in texture_inputs['records']), 'Original sword texture object identity differs')
    assets.records.extend(texture_inputs['records'])
    require({int(m['sourcePathID']): m['sourceObjectSHA256'] for m in assets.shader_document['materials']} ==
            {k: v[1] for k, v in MATERIALS.items()}, 'Original sword material scope differs')
    profile_raw = args.profile.read_bytes(); profile = json.loads(profile_raw)
    require(profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64, 'Wrong actor profile')
    models = source_models(profile, args.model_tracks, args.held_tracks)
    rule_raw = (args.rules / 'd15-lock-1447-compact-private.json').read_bytes()
    rules = json.loads(rule_raw)
    trigger = next(r for r in rules if r['triggerIndex'] == 1)
    require(trigger['events'] == [{'a2': ['enum65537']}] and
            trigger['actions'] == [{'a46': [EFFECT, None, 'magic_joint_root', None, 'enum65537', 1,
                None, True, None, None, False, [1., 1., 1.], None, [0., 0., 0.], None, None]}],
            'Original sword model initialization binding differs')
    require(trigger['conditions'] == [{'Not': [{'expr': [{'f171': [quality]}, 1., 'op22']}
            for quality in ('min', 'low', 'medium')]}], 'Original high-preset branch differs')
    path, rows = inventory(assets.environment, EFFECT, PREFAB_ID)
    controllers = [c.read_typetree() for c in rows[0]['components'] if c.type.name == 'MonoBehaviour'
                   and 'overrideDuration' in c.read_typetree()]
    require(len(controllers) == 1, 'Ambiguous original sword effect controller')
    controller = controllers[0]
    require(controller['overrideDuration'] == 1 and controller['duration'] == 9999 and not controller['delayedEffects']
            and all(controller[k] == 0 for k in ('ignoreTimeScale', 'reactToDissolveModel', 'takeInAccountCharacterDirection',
                '_useMirroring', '_inverseMirroring', '_ignoreFlipByZ', '_flipByAccountCharacterDirection',
                '_rotateAttachToLocal', '_trackingAccountModelDirection')), 'Unadapted sword controller behavior')
    require(sha(assets.local[MESH_ID].get_raw_data()) == MESH_SHA, 'Original sword mesh differs')
    require(sha(assets.local[SPIRAL_MESH_ID].get_raw_data()) == SPIRAL_MESH_SHA, 'Original sword spiral mesh differs')
    worlds, active, tracks, receipts, omitted, observed = {}, {}, [], [], [], set()
    for row in rows:
        local = matrix(row['position'], row['rotation'], row['scale'])
        world = worlds[row['parent']] @ local if row['parent'] is not None else local
        worlds[row['pathID']] = world
        active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
        systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
        if not systems: continue
        renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
        require(len(systems) == len(renderers) == 1, 'Ambiguous original sword emitter')
        system, renderer = systems[0], renderers[0]
        source, render = system.read_typetree(), renderer.read_typetree()
        require(active[row['pathID']] and render['m_Enabled'], 'Original sword active-emitter inventory differs')
        proof = dict(sourceParticleSystem=str(system.path_id), sourceParticleSystemSHA256=sha(system.get_raw_data()),
            sourceRendererPathID=str(renderer.path_id), sourceRendererSHA256=sha(renderer.get_raw_data()))
        if system.path_id not in BOUND_SYSTEMS:
            require(system.path_id in NOISE_SYSTEMS | TRAIL_SYSTEMS,
                    'Original sword unsupported-emitter inventory differs')
            require(source['NoiseModule']['enabled'] if system.path_id in NOISE_SYSTEMS else source['TrailModule']['enabled'],
                    'Original omitted source module differs')
            omitted.append(dict(**proof, sourceName=row['name'], enabledModules=[k for k, v in source.items()
                if isinstance(v, dict) and v.get('enabled')],
                bindingStatus='unbound_original_noise_module' if system.path_id in NOISE_SYSTEMS else 'unbound_original_history_trail'))
            continue
        observed.add(system.path_id)
        mode, looping, expected_count = PARTICLE_SYSTEMS.get(system.path_id,
            (4, system.path_id not in START_SYSTEMS, 1 if system.path_id in START_SYSTEMS else 2))
        require(not any(source[k]['enabled'] for k in ('NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule',
                'ForceModule', 'VelocityModule')) and not source['prewarm'] and source['moveWithTransform'] == 0 and
                render['m_RenderMode'] == mode and render['m_RenderAlignment'] == 2,
                'Original sword emitter behavior differs')
        if mode == 4:
            require(render['m_Mesh'] == {'m_FileID': 0,
                'm_PathID': SPIRAL_MESH_ID if system.path_id in SPIRAL_SYSTEMS else MESH_ID},
                'Original sword emitter mesh differs')
        require(source['looping'] == looping and source['lengthInSec'] == 1 and
                len(render['m_Materials']) == 1 and render['m_SortMode'] in (0, 2, 3, 4) and
                render['m_SortingLayer'] == render['m_SortingLayerID'] == render['m_SortingFudge'] == 0,
                'Original sword emitter clock or sorting differs')
        material_id = assets.material(render['m_Materials'][0]); material = assets.materials[material_id]
        binding = next(m for m in assets.shader_document['materials'] if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
        source_material = json.loads(Path(binding['metadataFile']).read_text())
        shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == binding['shaderPathID'])
        subshaders = json.loads(Path(shader['parsedFile']).read_text())['m_SubShaders']
        require(len(subshaders) == 1, 'Ambiguous original sword subshader')
        tags = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
        require(len(tags) == 1, 'Original sword render queue is absent')
        queue = source_queue(source_material['m_CustomRenderQueue'], tags[0])
        geometry = assets.geometry(render['m_Mesh']) if mode == 4 else plane_geometry()
        speed, emitter = source['simulationSpeed'], str(system.path_id)
        delay0 = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / speed
        samples = []
        for particle, birth, period in emission_schedule(source, emitter):
            sampled, sample_proof = sample_particle(source, render, world, row['scale'], particle, project_gravity=assets.gravity)
            blend = material['raster']
            track = dict(name=row['name'] + '_' + emitter + '_' + str(particle.index), layer=row['layer'],
                material=material_id, texture=material['textures']['_MainTex']['file'],
                blend='add' if blend['destination'] == 1 else 'alpha', wrapS=material['textures']['_MainTex']['wrapS'],
                wrapT=material['textures']['_MainTex']['wrapT'], multiplyTextureAlpha=blend['source'] == 5,
                overlay=False, sortingOrder=render['m_SortingOrder'], delay=round(delay0 + birth / speed, 7),
                duration=sampled['frames'][-1][0], vertexStreams=render['m_VertexStreams'],
                sourceRenderMode=mode, sourceRenderAlignment=2, sourceSimulationSpace=0,
                sourceParticleSystem=emitter, sourceSortMode=render['m_SortMode'], sourceSortingLayer=0,
                sourceRenderQueue=queue, sourceAgeOffset=0., stableRandom=[particle.r('stableRandom' + str(i)) for i in range(4)],
                geometry=geometry, **sampled)
            if period is not None: track['loopPeriod'] = round(period / speed, 7)
            tracks.append(track); samples.append(sample_proof)
        require(len(samples) == expected_count, 'Original sword emitter particle count differs')
        receipts.append(dict(**proof, sourceMaterialSHA256=material['sourceMaterialSHA256'],
            sourceRenderMode=mode, sourceRenderAlignment=2, sourceLooping=looping, samples=samples))
    require(observed == BOUND_SYSTEMS and len(tracks) == 32 and len(omitted) == 5,
            'Original sword fifteen-of-twenty scope differs')
    effect = dict(sourceName=path, duration=max(t['delay'] + t['duration'] for t in tracks), tracks=tracks,
        sourceDurationOverride=9999., sourceController={k: v for k, v in controller.items()
        if k not in ('m_GameObject', 'm_Script', 'm_Name', 'm_Enabled')})
    source_binding = dict(sourceLock=1447, sourceTrigger=1, bone='magic_joint_root', attachToLocal=True,
        follow=[1, 1, 1], shift=[0, 0, 0], requiredQuality='high', sourceDurationSeconds=9999.)
    document = dict(version=1, profileID=profile['id'], characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        evidence=['Fifteen original high-preset emitters are bound: six sword meshes, two spiral meshes, and seven source planes.',
            'Three true Noise emitters and two history Trail emitters remain explicitly unbound; this is not a complete prefab claim.',
            'Two emitters named noise have NoiseModule disabled and retain their actual texture/curve animation without invented noise.',
            'Original magic_joint_root poses, source local attachment, exact mesh, materials and shader variants are retained.',
            'Model birth clock is independent of source role/state changes; Rotate retains exactly one original sample.',
            'The adapter does not claim native pixel parity or synthesize source SHOW/DestroyEffect events from cast phases.'],
        files=sorted(assets.files.values(), key=lambda f: f['name']), materials=assets.materials,
        effects={EFFECT: effect}, bindings=[], markers=[], erlangSwordModels=models,
        erlangSwordBinding=source_binding,
        erlangSwordScope=dict(version=2, sourceActiveEmitters=20,
            boundMeshEmitters=sorted(map(str, SYSTEMS | SPIRAL_SYSTEMS)), boundPlaneEmitters=sorted(map(str, PLANE_SYSTEMS)),
            unboundEmitters=[p['sourceParticleSystem'] for p in omitted], completePrefab=False))
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode(); compressed = gzip.compress(raw, mtime=0)
    require(len(raw) < 256_000_000 and len(compressed) < 32_000_000, 'Source sword export exceeds loader bounds')
    write_private(output / 'SF3_D15_SwordEffects.json', raw); write_private(output / 'SF3_D15_SwordEffects.json.gz', compressed)
    receipt = dict(schema='original-d15-sword-particle-effects-v2', sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
        sourceModelCandidateSHA256=MODEL_SHA, sourceHeldCandidateSHA256=HELD_SHA,
        sourceTextureReceiptSHA256=TEXTURE_RECEIPT_SHA,
        sourceRulesSHA256=sha(rule_raw), sourceTrigger=trigger, sourceMeshPathID=str(MESH_ID), sourceMeshSHA256=MESH_SHA,
        sourceSpiralMeshPathID=str(SPIRAL_MESH_ID), sourceSpiralMeshSHA256=SPIRAL_MESH_SHA,
        sourceTransforms=[{k: r[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for r in rows],
        boundEmitters=receipts, unboundEmitters=omitted, sourceAssets=assets.audit,
        profileSHA256=sha(profile_raw), characterSHA256=profile['sha256'], sourceBinding=source_binding,
        derivedFile=dict(name='SF3_D15_SwordEffects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        fullPrefabBound=False, engineParityVerified=False)
    save_json(output / 'd15-sword-effect-receipt-private.json', receipt)
    print(json.dumps(dict(**receipt['derivedFile'], models=len(models), sourceEmitters=20, boundEmitters=15,
        tracks=len(tracks), materials=len(assets.materials), resources=len(assets.files))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models', 'effects', 'model-tracks', 'held-tracks', 'profile', 'rules', 'archive', 'shader-bundle', 'cached-materials', 'extra-textures', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--material-sources', type=Path)
    build(parser.parse_args())


if __name__ == '__main__': main()
