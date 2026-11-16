#!/usr/bin/env python3
"""Prepare the three original mesh emitters that make D15's large leg visible.

This deliberately scoped export does not stand in for ground cracks, laser,
hovering swords or other D15 effects. It uses existing local source bundles.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
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
from prepare_erlang_model_tracks import checked, model_inputs, same_source_value

MODEL_SHA = '870b6c27c3a8117f2d4e7e45b60c0c7d0c74dd16ddd129b43ab01e4d5b428cfc'
ROLE = 'erlangSummon_stomp'
EFFECT = 'D15_fx_big_leg'
PREFAB_ID = -8069839089656887436
SYSTEMS = {-929469514926225548, 6055453625588746100, -1006497375095126156}
RECOVERED_MODEL_SHA = '25b7efc5cb38d2197ab49fcf58cc255feb8e3d6fa3309a9ab1ab31bb655496d0'
RECOVERED_MODEL_BYTES = 666_196
SOURCE_ONLY_NAME = 'D15_Stomp_SourceOnly.recovered-v1.json'
SOURCE_ONLY_SCHEMA = 'original-d15-stomp-source-only-recovered-v1'
TEXTURE_BUNDLE = ('9d3e616ea68b083cc7b1b8b92e5f72a8.bin', 68_114_260,
                  'feffa7c512ceb35663bf7fdd80910ff0927c0f8b31deabdd8413777383392f2e')
TEXTURES = {
    -4727852512917511309: dict(cab='CAB-901eba28f4c9f491c9323f34153174a5',
        name='caustic_noise_007_grscl', rawBytes=224,
        rawSHA256='a7b94d33b436e107be399a198a73b7dd493b206312d0065fc9d550a82e6b16cd',
        streamSHA256='da1a9435f0c7c6e376abba56e4363426cc5a50f11629ee06051f4f8008ea250f'),
    -8498525634246556637: dict(cab='CAB-1f4b3e1848da14b8ff83ae70be7a8bc6',
        name='VFX_TileNoise_32_contrast', rawBytes=228,
        rawSHA256='49e576b0167a9a90a6cd823945aa88a02c60e861f27d07a81b8d6b2e3c4453fb',
        streamSHA256='60579717193f40549840d78c9850f36081f6ec295377b487714a05219a3becdb'),
}
PROJECT_INPUTS = {
    'source-color-space-private.json': (447, '5eadb53b04b9ab369a600a38a23b6bbd471ad28f050b3303845740677dcb3eee'),
    'source-physics-quality-private.json': (11045, '53f60e17fa1efaddd24186792fb456ada65877751019799127f773ff76afcae2'),
}
MESH_ID = -6222684053069387964
MESH_SHA = '953d2289a5d2ad7e5e6104a02cec6a3449ad8f3447abfb8cc2f3ff0f04d852f3'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def write_json(path, value):
    write_private(path, json.dumps(value, separators=(',', ':'), allow_nan=False).encode())


def texture_metadata_json(value):
    # Unity's empty inline image field is still bytes, not an untyped JSON list.
    # Retain that distinction alongside the complete original object and stream.
    if type(value) is bytes:
        return {'__unity_bytes_hex__': value.hex()}
    if type(value) is dict:
        return {k: texture_metadata_json(v) for k, v in value.items()}
    if type(value) is list:
        return [texture_metadata_json(v) for v in value]
    return value


def recovered_inputs(args):
    """A distinct source-only identity; a fabricated profile cannot bridge it."""
    input_format = getattr(args, 'input_format', 'historical')
    require(input_format in ('historical', 'recovered-v1'), 'Unknown stomp input format')
    if input_format == 'historical':
        require(args.profile is not None, 'Historical export requires its real character profile')
        require(all(getattr(args, n, None) is None for n in ('settings', 'decoded_splits', 'texture_bundle')),
                'Historical and recovered stomp inputs cannot be mixed')
        return None
    require(args.profile is None and args.material_sources is None,
            'Source-only recovery cannot claim a profile or reuse unchecked material metadata')
    require(all(getattr(args, n, None) is not None for n in ('settings', 'decoded_splits', 'texture_bundle')),
            'Recovered stomp requires exact original settings, splits and texture bundle')
    _, rules, recovery = model_inputs(args)
    raw = checked(args.model_tracks, RECOVERED_MODEL_SHA, RECOVERED_MODEL_BYTES)
    model = json.loads(raw)
    require(len(raw) == RECOVERED_MODEL_BYTES
            and model['schema'] == 'original-d15-independent-model-tracks-v1'
            and model['sourceConfigurationSHA256'] == CONFIGURATION_SHA
            and same_source_value(model.get('inputRecovery'), recovery),
            'Recovered stomp model and complete source identities differ')
    rule_path, rule_raw, rule_rows = rules[1434]
    return dict(document=model, ruleRaw=rule_raw, rules=rule_rows, inputRecovery=recovery,
        sourceCandidateReceipt=dict(file=args.model_tracks.name, bytes=len(raw), sha256=sha(raw),
            historicalSHA256=MODEL_SHA, historicalBytesRestored=False),
        sourceRuleReceipt=dict(file=rule_path.name, bytes=len(rule_raw), sha256=sha(rule_raw)))


def checked_texture(raw, metadata, stream, cab, pin):
    """Keep exact raw object, CAB, complete ETC2 chain and native scalar types."""
    require(cab == pin['cab'] and metadata['m_Name'] == pin['name']
            and len(raw) == pin['rawBytes'] and sha(raw) == pin['rawSHA256'],
            'Original stomp texture object identity differs')
    require(all(type(metadata[k]) is int and metadata[k] == value for k, value in (
        ('m_Width', 512), ('m_Height', 512), ('m_TextureFormat', 47), ('m_MipCount', 10))),
        'Original stomp texture dimensions, format or mip type differs')
    require(len(stream) == 349_552 and sha(stream) == pin['streamSHA256'],
            'Original stomp complete texture stream differs')
    offset, mips = 0, []
    for level in range(10):
        size = max(1, 512 >> level)
        count = ((size + 3) // 4) ** 2 * 16
        payload = stream[offset:offset + count]
        require(len(payload) == count, 'Original stomp mip is truncated')
        mips.append(dict(level=level, width=size, height=size, offset=offset,
                         bytes=count, sha256=sha(payload)))
        offset += count
    require(offset == len(stream), 'Original stomp mip chain has unaccounted bytes')
    return mips


def recovered_source_cache(args, output):
    """Resolve two exact original Texture2D objects locally, never fetch a URL."""
    import UnityPy
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    from erlang_effect_materials import D15
    require(args.texture_bundle.name == TEXTURE_BUNDLE[0], 'Wrong recovered texture bundle name')
    texture_raw = checked(args.texture_bundle, TEXTURE_BUNDLE[2], TEXTURE_BUNDLE[1])
    require(len(texture_raw) == TEXTURE_BUNDLE[1], 'Original texture bundle length differs')
    d15_raw = checked(args.models / D15[0], D15[2], D15[1])
    require(len(d15_raw) == D15[1], 'Original D15 effect bundle length differs')
    cache = private_output(output / 'source-inputs-private')
    records, texture_proofs = [], []
    for path_id, bundle_raw, bundle in ((-4727852512917511309, texture_raw, TEXTURE_BUNDLE),
                                       (-8498525634246556637, d15_raw, D15)):
        pin = TEXTURES[path_id]
        objects = [o for o in UnityPy.load(bundle_raw).objects
                   if o.path_id == path_id and o.type.name == 'Texture2D'
                   and o.assets_file.name == pin['cab']]
        require(len(objects) == 1, 'Original stomp texture PPtr is missing or ambiguous')
        obj = objects[0]
        raw, metadata, texture = obj.get_raw_data(), obj.read_typetree(), obj.read()
        stream = bytes(texture.get_image_data())
        mips = checked_texture(raw, metadata, stream, obj.assets_file.name, pin)
        image = texture.image.convert('RGBA')
        require(image.size == (512, 512), 'Decoded original stomp texture size differs')
        png = io.BytesIO(); image.save(png, format='PNG'); png_raw = png.getvalue()
        stem = cache / str(path_id)
        paths = {key: Path(str(stem) + suffix) for key, suffix in (
            ('rawFile', '.raw'), ('metadataFile', '.json'), ('textureFile', '.texture'), ('pngFile', '.png'))}
        write_private(paths['rawFile'], raw); write_json(paths['metadataFile'], texture_metadata_json(metadata))
        write_private(paths['textureFile'], stream); write_private(paths['pngFile'], png_raw)
        record = dict(type='Texture2D', externalCAB=pin['cab'], pathID=str(path_id),
            sourceName=pin['name'], sourceObjectBytes=len(raw), sourceObjectSHA256=sha(raw),
            sourceTextureBytes=len(stream), sourceTextureSHA256=sha(stream), pngSHA256=sha(png_raw),
            metadataSHA256=sha(paths['metadataFile'].read_bytes()), **{k: str(v) for k, v in paths.items()},
            bundleEvidence=dict(file=bundle[0], bytes=bundle[1], sha256=bundle[2], wholeBundleSHA256Verified=True),
            fullMipChain=mips)
        texture_proofs.append(record)
        if path_id == -4727852512917511309:
            records.append(record)
    external = private_output(cache / 'external-objects')
    write_json(external / 'recovered-material-textures-private.json', dict(records=records))
    write_json(external / 'recovered-dependencies-private.json', dict(records=[]))
    write_json(external / 'mesh-arrays-private.json', dict(records=[]))
    settings = private_output(cache / 'shader-source')
    project = []
    for name, (size, digest) in PROJECT_INPUTS.items():
        raw = checked(args.effects / 'shader-source' / name, digest, size)
        require(len(raw) == size, 'Recovered original project record length differs')
        write_private(settings / name, raw)
        project.append(dict(file=name, bytes=size, sha256=digest))
    return cache, dict(textures=texture_proofs, projectInputs=project)


def source_only_document(assets, effect, model, track, recovery):
    """An independent source artifact, deliberately not an App manifest."""
    return dict(schema=SOURCE_ONLY_SCHEMA, inputFormat='recovered-v1', sourceOnly=True,
        runtimeBound=False, nativeParityVerified=False, appleGPUVerified=False,
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        sourceCandidateReceipt=recovery['sourceCandidateReceipt'], inputRecovery=recovery['inputRecovery'],
        evidence=['All three original D15 large-leg emitters, source mesh, materials and complete texture mip chains.',
            'One repeatable realization of the original automatic seed; original 1.4-second particle lifetimes are retained.',
            'No owner, actor profile, character body or runtime model binding is asserted.',
            'Ground cracks and other D15 effects are outside this source-only artifact.'],
        files=sorted(assets.files.values(), key=lambda f: f['name']), materials=assets.materials,
        effects={EFFECT: effect},
        sourceModels={ROLE: dict(track=track, sourceAnimation=model['sourceAnimation'], sourceRecordIndex=100,
            bones=model['bones'], endEventTick=18)})


def build(args):
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    recovery = recovered_inputs(args)
    output = private_output(args.output)
    require(not any(output.iterdir()), 'New stomp output must be empty')
    effects = args.effects
    if recovery is not None:
        effects, recovery['sourceAssetInputs'] = recovered_source_cache(args, output)
    materials = args.material_sources
    if materials is None:
        materials = output / 'material-source-private'
        prepare_materials(args.models, args.archive, args.shader_bundle, materials)
    assets = SourceAssets(args.models, effects, output, bundle_identity=BUNDLE,
        shader_bindings=materials / 'd15-shader-material-bindings-private.json',
        program_bindings=materials / 'd15-metal-material-patches-private.json',
        additional_records=materials / 'd15-additional-material-records-private.json')
    require({int(m['sourcePathID']): m['sourceObjectSHA256'] for m in assets.shader_document['materials']} ==
            {k: v[1] for k, v in MATERIALS.items()}, 'D15 leg material scope differs')
    if recovery is None:
        source_raw = args.model_tracks.read_bytes()
        require(len(source_raw) == 653960 and sha(source_raw) == MODEL_SHA, 'Reviewed source model candidate differs')
        model_document = json.loads(source_raw)
    else:
        model_document = recovery['document']
    model = next(m for m in model_document['models'] if m['role'] == ROLE)
    track = next(t for t in model_document['summonTracks'] if t['role'] == ROLE)
    require(model['sourceAnimation'] == 'D15_Avatara_Leg_Model' and model['sourceRecordIndex'] == 100
            and model['effectiveLastTick'] == 18 and track['frames'] == 10, 'Original leg model clock differs')
    if recovery is None:
        profile_raw = args.profile.read_bytes()
        profile = json.loads(profile_raw)
        require(profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64, 'Wrong character profile')
        rule_raw = (args.rules / 'd15-lock-1434-compact-private.json').read_bytes()
        rules = json.loads(rule_raw)
    else:
        rule_raw, rules = recovery['ruleRaw'], recovery['rules']
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
        if recovery is not None:
            require(assets.key(render['m_Mesh']) == (None, MESH_ID)
                    and sha(assets.local[MESH_ID].get_raw_data()) == MESH_SHA,
                    'Original recovered stomp mesh identity differs')
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
    if recovery is None:
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
        filename = 'SF3_D15_StompEffects.json'
    else:
        document = source_only_document(assets, effect, model, track, recovery)
        filename = SOURCE_ONLY_NAME
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    require(len(raw) <= 256_000_000 and len(compressed) <= 32_000_000, 'Source leg export exceeds loader bounds')
    write_private(output / filename, raw)
    write_private(output / (filename + '.gz'), compressed)
    if recovery is None:
        receipt = dict(schema='original-d15-stomp-effect-v1', sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
            sourceModelCandidateSHA256=MODEL_SHA, sourceRulesSHA256=sha(rule_raw), sourceTrigger=trigger,
            sourceTransforms=[{k: x[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for x in rows],
            sourceEmitters=receipts, sourceAssets=assets.audit, sourceTrack=track,
            profileSHA256=sha(profile_raw), profileIncludesStompTrack=profile.get('summonTracks', []).count(track) == 1,
            characterSHA256=profile['sha256'], derivedFile=dict(name='SF3_D15_StompEffects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
            sourceRulesBinding=binding, engineParityVerified=False)
    else:
        receipt = dict(schema='original-d15-stomp-source-only-recovery-receipt-v1',
            inputFormat='recovered-v1', sourceOnly=True, runtimeBound=False, engineParityVerified=False,
            appleGPUVerified=False, historicalRuntimeManifestBytesRestored=False,
            sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
            sourceCandidateReceipt=recovery['sourceCandidateReceipt'], inputRecovery=recovery['inputRecovery'],
            sourceRuleReceipt=recovery['sourceRuleReceipt'], sourceTrigger=trigger,
            sourceTransforms=[{k: x[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for x in rows],
            sourceEmitters=receipts, sourceAssets=assets.audit, sourceAssetInputs=recovery['sourceAssetInputs'],
            sourceTrack=track, originalSourceEvent=binding,
            derivedFile=dict(name=filename + '.gz', bytes=len(compressed), sha256=sha(compressed)))
    write_json(output / 'd15-stomp-effect-receipt-private.json', receipt)
    print(json.dumps(dict(file=filename + '.gz', bytes=len(compressed), sha256=sha(compressed),
        emitters=len(receipts), tracks=len(tracks), duration=effect['duration'], materials=len(assets.materials), resources=len(assets.files))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models', 'effects', 'model-tracks', 'rules', 'archive', 'shader-bundle', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--profile', type=Path)
    parser.add_argument('--material-sources', type=Path)
    parser.add_argument('--input-format', choices=('historical', 'recovered-v1'), default='historical')
    for name in ('settings', 'decoded-splits', 'texture-bundle'):
        parser.add_argument('--' + name, type=Path)
    build(parser.parse_args())


if __name__ == '__main__':
    main()
