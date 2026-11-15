#!/usr/bin/env python3
"""Append original Earth and meditation effects without resampling accepted Eye.

Includes original horizontal rings, eye-facing dust, mesh-in-view-space
explosions and the reviewed local-force stone. Three stretched emitters, one
null-mesh emission shape and one birth-direction alignment remain inventoried.
"""
from __future__ import annotations
import argparse
import copy
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
from prepare_erlang_skill_effects import MODEL_SHA, EFFECT as EYE_EFFECT, source_binding as eye_binding
from erlang_effect_materials import sha, save_json
from erlang_skill_effect_materials import IMPACT_MATERIALS, LASER_MATERIALS

BASE_EYE_SHA = 'fc5c49da06415bdefdb294ad78bfbf406b9dab79fcb527ecbd4f9dc926165619'
INPUT_SHAS = {
    'e3efe68e34b26bdbdef781839da0218e2f5d479924ca601c16ab84cba8c3ad5b',
    '82dee16ace122ec5e9823587ab02a4a9df00b159f5d96d2d707221c38f1d2840',
    '24db4ee62c728284c952fe5fd8e45fe81f439d8cf1cd1cc4bd5325843d72e729',
    '7bbe27bdf696a76aa35ef445b04be3b2d18898a0611fcdf18380484c5e935095',
    '6d37f512a036582a490ea501d59b4859296859369bdd24fc7d4b0016bbfa605a',
    '4fa85e517a93e6e0e17b23ee1023c9b4d6e2290dc4d5abbde453c3a53edd3e30',
    '207b8d5b76f565452a46daef14d1e8a581ddbc0d0cec3d9f83718aa9d955883a',
    '30001dce64e4c19e9dfcf15e7ab1e7bd2613f2b43d5a79bf9f65418ed9dddeb7',
    '61431efddfa04d9d7e920c337ef80b3e1fa5f4ec130306b397b5a6f309c04eb6',
}
EARTH = 'D15_fx_floorAttack_(pelvis)'
MEDITATION = 'D15_fx_avatar_start_explos(chest)'
EARTH_SYSTEMS = {5287901173406324130, -6316194589938264670, 8679408912012301730,
    -4702864568908687966, 4868519863712699810, -7602940797112527454,
    2864175961765008802, 1822237901742036386, -76387927279905374,
    -6292074152677255774, 4814904083332552098, 7115202763964831138, -7718219801220196958,
    -8686503464823204446, 3261350741611337122}
MEDITATION_SYSTEMS = {-3441419061833702333, 5743770872533541955, 5640030630918874179,
    1480694095923766339, -3071502713722182589, 6489450101228037187, -4655989811314957245, 2892577479160685635}
EFFECTS = {
    EARTH: (-8545188483580602974, EARTH_SYSTEMS, 19),
    MEDITATION: (-4411947535013125053, MEDITATION_SYSTEMS, 9),
}
FORCE_SYSTEMS = {-6292074152677255774}
EARTH_RELEASE = dict(id='d15_create_103', ability='earth', ownerRole='erlangEarthshaker', atTick=39,
    modelRole='erlangSummon_earth', anchor='pelvis.x', offset=[20., 0., 0.], minimumLevel=2)


def impact_bindings(profile, model_path, rules):
    model_raw = model_path.read_bytes()
    require(sha(model_raw) == MODEL_SHA, 'Reviewed source model input differs')
    tracks = {t['role']: t for t in json.loads(model_raw)['summonTracks']}
    for role in ('erlangSummon_earth', 'erlangSummon_meditation'):
        require([t for t in profile.get('summonTracks', []) if t['role'] == role] == [tracks[role]],
                'Final actor lacks exact source impact model: ' + role)
    require(profile['roles'].get('erlangEarthshaker') == 'd15_avatara_spear_earthshake', 'Source Earth role differs')
    clip = next(c for c in profile['clips'] if c['name'] == profile['roles']['erlangEarthshaker'])
    require(clip['sha256'] == '341014fb370f15f25c5fa33085de640c0051fd1b55855488b3fff7dcdb98ff0f' and
            clip['frames'] == 111 and clip['playbackTicks'] == 110 and clip['sourceFirstIndex'] == 0 and
            clip['sourceEndEventTick'] == 106, 'Original Earth playback differs')
    cfg = clip['sourceConfiguration']; values = cfg['configuration']
    require(cfg['sourceEntry'] == 'settings_sets_dynasty.bytes' and cfg['sourceSHA256'] == CONFIGURATION_SHA and
            cfg['sourceRecordIndex'] == 102 and values['MidFrames'] == 0 and
            [i for i in values['Intervals'] if i['Name'] == 'D15_Spear_Ground_Shake_Model_Creation'][0]['Start'] == 40,
            'Original Earth interval differs')
    require([r for r in profile['erlangRules']['releases'] if r['modelRole'] == 'erlangSummon_earth'] == [EARTH_RELEASE],
            'Runtime Earth release differs')
    main_raw = (rules / 'd15-lock-1432-compact-private.json').read_bytes(); main = json.loads(main_raw)
    earth_fx = next(r for r in main if r['triggerIndex'] == 66)
    earth_model = next(r for r in main if r['triggerIndex'] == 68)
    require(earth_fx['events'] == earth_model['events'] == [{'a18': ['enum65537', 'D15_Spear_Ground_Shake_Model_Creation']}] and
            earth_fx['actions'] == [{'a46': [EARTH, None, 'pelvis', None, 'enum65537', 1, None, None,
                None, None, False, None, None, [0., 0., 0.], None, None]}], 'Original Earth visual attachment differs')
    med_raw = (rules / 'd15-lock-1438-compact-private.json').read_bytes(); med = json.loads(med_raw)
    med_fx = next(r for r in med if r['triggerIndex'] == 1)
    require(med_fx['events'] == [{'a2': ['enum65537']}] and med_fx['actions'] == [{'a46': [MEDITATION,
        None, 'chest', None, 'enum65539', 1, None, None, None, None, False, [0., 0., 0.],
        None, [0., 3., 0.], None, None]}], 'Original meditation Parent chest initialization differs')
    earth = dict(id='d15_earth_pelvis', role='erlangSummon_earth', ownerRole='erlangEarthshaker', effect=EARTH,
        bone='pelvis', attachToLocal=False, follow=[0, 0, 0], shift=[0., 0., 0.], sourceTarget='owner',
        sourceLock=1432, sourceTrigger=66, sourceEvent='D15_Spear_Ground_Shake_Model_Creation',
        sourceRecordIndex=102, sourceClip=clip['name'], sourceMotionSHA256=clip['sha256'],
        sourceIntervalStart=40, release=EARTH_RELEASE, track=tracks['erlangSummon_earth'], sourceModelEndTick=22)
    meditation = dict(id='d15_meditation_parent_chest', role='erlangSummon_meditation', ownerRole=None, effect=MEDITATION,
        bone='chest', attachToLocal=False, follow=[0, 0, 0], shift=[0., .03, 0.], sourceTarget='modelParent',
        sourceLock=1438, sourceTrigger=1, sourceEvent='Initialize', sourceRecordIndex=106,
        sourceClip=None, sourceMotionSHA256=None, sourceIntervalStart=None, release=None,
        track=tracks['erlangSummon_meditation'], sourceModelEndTick=52)
    return {EARTH: earth, MEDITATION: meditation}, dict(mainRulesSHA256=sha(main_raw), meditationRulesSHA256=sha(med_raw),
        earthCreateTrigger=earth_model, earthEffectTrigger=earth_fx, meditationEffectTrigger=med_fx)


def sample_effect(assets, name, prefab_id, included, total):
    path, rows = inventory(assets.environment, name, prefab_id)
    controllers = [c.read_typetree() for c in rows[0]['components'] if c.type.name == 'MonoBehaviour'
                   and 'overrideDuration' in c.read_typetree()]
    require(len(controllers) == 1, 'Ambiguous original impact effect controller')
    controller = controllers[0]
    require(controller['overrideDuration'] == 0 and not controller['delayedEffects'] and all(controller[k] == 0 for k in
        ('ignoreTimeScale', 'reactToDissolveModel', 'takeInAccountCharacterDirection', '_useMirroring', '_inverseMirroring',
         '_ignoreFlipByZ', '_flipByAccountCharacterDirection', '_rotateAttachToLocal', '_trackingAccountModelDirection')),
        'Unsupported original impact effect controller')
    worlds, active, tracks, receipts, omitted, observed = {}, {}, [], [], [], set()
    for row in rows:
        local = matrix(row['position'], row['rotation'], row['scale'])
        world = worlds[row['parent']] @ local if row['parent'] is not None else local
        worlds[row['pathID']] = world
        active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
        systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
        if not systems: continue
        renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
        require(len(systems) == len(renderers) == 1, 'Ambiguous original impact emitter')
        system, renderer = systems[0], renderers[0]; source, render = system.read_typetree(), renderer.read_typetree()
        require(active[row['pathID']] and render['m_Enabled'], 'Original active impact-emitter inventory differs')
        proof = dict(sourceParticleSystem=str(system.path_id), sourceParticleSystemSHA256=sha(system.get_raw_data()),
            sourceRendererPathID=str(renderer.path_id), sourceRendererSHA256=sha(renderer.get_raw_data()))
        if system.path_id not in included:
            if render['m_RenderMode'] == 1:
                reason = 'stretched_billboard_direction_unbound'
            elif system.path_id == -8834466512921012830:
                require(source['ShapeModule']['enabled'] and source['ShapeModule']['type'] == 6 and
                        source['ShapeModule']['m_Mesh'] == {'m_FileID':0,'m_PathID':0}, 'Original null-mesh shape differs')
                reason = 'mesh_shape_has_no_source_mesh'
            elif system.path_id == 2415301125327312290:
                require(source['ShapeModule']['enabled'] and source['ShapeModule']['alignToDirection'],
                        'Original stone birth-alignment scope differs')
                reason = 'shape_birth_alignment_unbound'
            else: raise ValueError('Uninventoried original impact emitter')
            omitted.append(dict(**proof, sourceName=row['name'], bindingStatus=reason))
            continue
        observed.add(system.path_id)
        mode, alignment = render['m_RenderMode'], render['m_RenderAlignment']
        require(mode in (0, 2, 4) and alignment in (0, 2, 3, 4) and
            not any(source[k]['enabled'] for k in ('NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule')) and
            not source['looping'] and not source['prewarm'] and source['moveWithTransform'] == 0 and
            source['InitialModule']['gravityModifier']['scalar'] == 0, 'Unsupported original impact particle module')
        require(source['ForceModule']['enabled'] == (system.path_id in FORCE_SYSTEMS), 'Original force scope differs')
        require(not source['ShapeModule']['enabled'] or not source['ShapeModule']['alignToDirection'],
                'Original shape birth alignment is not yet bound')
        if source['ForceModule']['enabled']:
            require(not source['ForceModule']['inWorldSpace'] and not source['ForceModule']['randomizePerFrame'],
                    'Only recovered local deterministic force curves are bound')
        if mode == 2 or alignment == 3:
            require(not source['InitialModule']['rotation3D'], 'Unbound horizontal/facing 3D rotation')
        require(len(render['m_Materials']) == 1 and render['m_SortMode'] in (0, 1, 2, 3, 4) and
                render['m_SortingLayer'] == render['m_SortingLayerID'] == render['m_SortingFudge'] == 0,
                'Original impact sorting differs')
        material_id = assets.material(render['m_Materials'][0]); material = assets.materials[material_id]
        representative_slot = '_MainTex'
        if representative_slot not in material['textures']:
            require(material_id == 'm_-654479186809044038' and set(material['textures']) == {
                '_StoneColor_Tex','_StoneCracksNoiseScroll_Tex','_StoneCracks_Tex','_StoneGradient_Tex'},
                'Unreviewed material without a primary texture')
            # Track.texture is the inventory reference, not the shader's
            # sampler map. All four original named stone samplers stay bound.
            representative_slot = '_StoneColor_Tex'
        representative = material['textures'][representative_slot]
        bind = next(m for m in assets.shader_document['materials'] if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
        original = json.loads(Path(bind['metadataFile']).read_bytes())
        shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == bind['shaderPathID'])
        subshaders = json.loads(Path(shader['parsedFile']).read_bytes())['m_SubShaders']
        require(len(subshaders) == 1, 'Ambiguous original impact subshader')
        tags = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
        if not tags:
            # The original opaque stone shader omits Queue. ShaderLab's
            # documented default is Geometry/2000, not Transparent/3000.
            require(shader['pathID'] == '4724427473167895249' and
                    material['raster']['source'] == 1 and material['raster']['destination'] == 0 and
                    subshaders[0]['m_Tags']['tags'] == [['RenderType','Opaque']], 'Unreviewed absent shader Queue tag')
            tags = ['Geometry']
        require(len(tags) == 1, 'Original impact render queue is ambiguous')
        queue = source_queue(original['m_CustomRenderQueue'], tags[0])
        geometry = assets.geometry(render['m_Mesh']) if mode == 4 else None
        if mode == 2:
            # Unity's built-in horizontal quad, not a substituted source mesh.
            # Its world X/Z orientation is supplied at draw time, before roll.
            geometry = dict(positions=[-.5,-.5,0,.5,-.5,0,.5,.5,0,-.5,.5,0], normals=[0,0,1]*4,
                uv=[0,1,1,1,1,0,0,0], tangents=[1,0,0,1]*4, indices=[0,1,2,0,2,3])
        sampling_renderer = render.copy()
        if alignment == 3: sampling_renderer['m_RenderAlignment'] = 0  # position/roll only; eye-facing basis is dynamic
        speed, emitter = source['simulationSpeed'], str(system.path_id)
        delay0 = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / speed
        samples = []
        for particle, birth, period in emission_schedule(source, emitter):
            require(period is None, 'Original nonlooping impact acquired a loop')
            sampled, sample_proof = sample_particle(source, sampling_renderer, world, row['scale'], particle,
                project_gravity=assets.gravity, apply_source_force=system.path_id in FORCE_SYSTEMS)
            if geometry is None:
                sampled.pop('orientations', None); sampled.pop('depthScales', None)
            blend = material['raster']
            track = dict(name=row['name'] + '_' + emitter + '_' + str(particle.index), layer=row['layer'],
                material=material_id, texture=representative['file'],
                blend='replace' if blend['destination'] == 0 else 'add' if blend['destination'] == 1 else 'alpha',
                wrapS=representative['wrapS'], wrapT=representative['wrapT'],
                multiplyTextureAlpha=blend['source'] == 5, overlay=False, sortingOrder=render['m_SortingOrder'],
                delay=round(delay0 + birth / speed, 7), duration=sampled['frames'][-1][0], vertexStreams=render['m_VertexStreams'],
                sourceRenderMode=mode, sourceRenderAlignment=alignment, sourceSimulationSpace=0,
                sourceParticleSystem=emitter, sourceSortMode=render['m_SortMode'], sourceSortingLayer=0,
                sourceRenderQueue=queue, sourceAgeOffset=0., stableRandom=[particle.r('stableRandom'+str(i)) for i in range(4)], **sampled)
            if geometry is not None: track['geometry'] = geometry
            tracks.append(track); samples.append(sample_proof)
        receipts.append(dict(**proof, sourceMaterialSHA256=material['sourceMaterialSHA256'],
            sourceRepresentativeTextureSlot=representative_slot,
            sourceForceApplied=source['ForceModule']['enabled'], samples=samples))
    require(observed == included and len(omitted) == total - len(included), 'Original impact scope differs')
    effect = dict(sourceName=path, duration=max(t['delay'] + t['duration'] for t in tracks), tracks=tracks,
        sourceController={k:v for k,v in controller.items() if k not in ('m_GameObject', 'm_Script', 'm_Name', 'm_Enabled')})
    scope = dict(sourceActiveEmitters=total, boundEmitters=sorted(map(str, included)),
        unboundEmitters=[p['sourceParticleSystem'] for p in omitted], completePrefab=False)
    proof = dict(sourceTransforms=[{k:r[k] for k in ('name','pathID','parent','position','rotation','scale')} for r in rows],
        boundEmitters=receipts, unboundEmitters=omitted)
    return effect, scope, proof


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output); require(not any(output.iterdir()), 'New impact output must be empty')
    base_raw = (args.base_eye / 'SF3_D15_SkillEffects.json.gz').read_bytes()
    require(sha(base_raw) == BASE_EYE_SHA, 'Accepted first eye export differs')
    document = json.loads(gzip.decompress(base_raw))
    profile_raw = args.profile.read_bytes(); profile = json.loads(profile_raw)
    require(profile['id'] == document['profileID'] and profile['sha256'] == document['characterSHA256'], 'Actual actor changed')
    base_binding, _ = eye_binding(profile, args.model_tracks, args.rules / 'd15-lock-1432-compact-private.json')
    accepted = document['erlangSkillBindings'][0].copy(); accepted.pop('lifetimeTicks')
    require(accepted == base_binding, 'Accepted eye binding changed')
    bindings, event_proof = impact_bindings(profile, args.model_tracks, args.rules)
    shader_documents = [json.loads((p / 'd15-skill-shader-bindings-private.json').read_bytes()) for p in (args.eye_materials, args.materials)]
    program_documents = [json.loads((p / 'd15-skill-metal-programs-private.json').read_bytes()) for p in (args.eye_materials, args.materials)]
    combined = copy.deepcopy(shader_documents[0])
    combined['materials'] += shader_documents[1]['materials']
    shaders = {s['pathID']: s for d in shader_documents for s in d['shaders']}
    combined['shaders'] = list(shaders.values())
    require({int(m['sourcePathID']): m['sourceObjectSHA256'] for m in combined['materials']} ==
            {k:v[1] for k,v in (LASER_MATERIALS | IMPACT_MATERIALS).items()}, 'Combined original material scope differs')
    material_directory = private_output(output / 'material-source-private')
    for directory, programs in zip((args.eye_materials, args.materials), program_documents):
        for row in programs['materials']:
            p = row['program']; raw = (directory / p['file']).read_bytes()
            require(len(raw) == p['bytes'] and sha(raw) == p['sha256'], 'Original derived shader program differs')
            write_private(material_directory / p['file'], raw)
    save_json(material_directory / 'combined-bindings-private.json', combined)
    save_json(material_directory / 'combined-programs-private.json', dict(version=1, programDirectory=str(material_directory),
        materials=[r for d in program_documents for r in d['materials']]))
    additions, input_proofs = [], []
    for path in args.source_inputs:
        raw = path.read_bytes(); require(sha(raw) in INPUT_SHAS, 'Unreviewed additional impact source input')
        input_proofs.append(dict(file=path.name, sha256=sha(raw), bytes=len(raw)))
        additions += json.loads(raw)['records']
    require({p['sha256'] for p in input_proofs} == INPUT_SHAS and len(input_proofs) == len(INPUT_SHAS),
            'Incomplete or repeated impact source inputs')
    for directory in (args.eye_materials, args.materials):
        additions += json.loads((directory / 'd15-skill-additional-materials-private.json').read_bytes())['records']
    save_json(material_directory / 'additional-records-private.json', dict(records=additions))
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE,
        shader_bindings=material_directory / 'combined-bindings-private.json', program_bindings=material_directory / 'combined-programs-private.json',
        additional_records=material_directory / 'additional-records-private.json')
    for row in additions:
        if row['type'] == 'Mesh' and 'arraysFile' in row:
            require(sha(Path(row['rawFile']).read_bytes()) == row['sourceObjectSHA256'], 'Additional original mesh bytes differ')
            assets.mesh_records.append(row)
    for record in document['files']:
        raw = (args.base_eye / record['name']).read_bytes()
        require(len(raw) == record['bytes'] and sha(raw) == record['sha256'], 'Accepted eye resource differs')
        write_private(output / record['name'], raw); assets.files[record['name']] = record
    assets.materials.update(document['materials'])
    proofs = {}
    for name, (prefab, systems, count) in EFFECTS.items():
        effect, scope, proof = sample_effect(assets, name, prefab, systems, count)
        binding = bindings[name]; binding['lifetimeTicks'] = math.ceil(effect['duration'] * 60)
        document['effects'][name] = effect; document['erlangSkillScopes'][name] = scope
        document['erlangSkillBindings'].append(binding); proofs[name] = proof
    document['files'] = sorted(assets.files.values(), key=lambda f:f['name']); document['materials'] = assets.materials
    document['evidence'] += ['The original Earth visual captures actor pelvis at the tick-39 creation event; its separate +20 m collision anchor is not used.',
        'Meditation explosion is observed from actual model Initialize and captures its Parent chest plus original 3 cm Y shift.',
        'Original source force is integrated only for the reviewed stone; original horizontal/view/facing/velocity orientation modes remain distinct.',
        'Earth binds 15 of 19 emitters and meditation binds 8 of 9; three stretched emitters, a null-mesh shape and a birth-direction alignment remain explicitly unbound.']
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode(); compressed = gzip.compress(raw, mtime=0)
    require(len(raw) < 256_000_000 and len(compressed) < 32_000_000, 'Combined effect export exceeds bounds')
    write_private(output / 'SF3_D15_SkillEffects.json', raw); write_private(output / 'SF3_D15_SkillEffects.json.gz', compressed)
    receipt = dict(schema='original-d15-earth-meditation-fx-v1', baseEyeManifestSHA256=BASE_EYE_SHA,
        sourceBundleSHA256=BUNDLE[1], sourceModelCandidateSHA256=MODEL_SHA, sourceInputs=input_proofs,
        profileSHA256=sha(profile_raw), characterSHA256=profile['sha256'], sourceBindings=bindings,
        sourceEffects=proofs, sourceAssets=assets.audit, **event_proof,
        derivedFile=dict(name='SF3_D15_SkillEffects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        fullPrefabsBound=False, engineParityVerified=False)
    save_json(output / 'd15-impact-effects-receipt-private.json', receipt)
    print(json.dumps(dict(**receipt['derivedFile'], materials=len(document['materials']), resources=len(document['files']),
        effects={name:dict(tracks=len(document['effects'][name]['tracks']),lifetimeTicks=bindings[name]['lifetimeTicks']) for name in EFFECTS})), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models','effects','profile','model-tracks','rules','base-eye','eye-materials','materials','output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--source-inputs', type=Path, nargs='+', required=True)
    build(parser.parse_args())
