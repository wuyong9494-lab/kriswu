#!/usr/bin/env python3
"""Sample the two original D15 hound FX using existing authenticated assets.

No source shader, texture, mesh, curve or effect is substituted. One repeatable
realization of the original automatic particle seeds is retained. Unsupported
modules fail, rather than silently becoming a partial effect.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import random
import warnings
from pathlib import Path

import numpy as np

from sun_triad_assets import (matrix, private_output, require, write_private, glb_read,
                              accessor_read, world_poses, pose_world)
from sun_triad_particle_assets import SourceAssets
from sun_triad_particle_curves import minmax
from sun_triad_particles import emission_schedule, sample_particle, seed
from sun_triad_particle_sort import source_queue

BUNDLE = ('4f9476ea1326d7c102950a772ee44020.bin', '971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90')
SHADER_SHA = 'c0b1fe09ba0684e474297ade8dcd7fee7b5d2e780236029c544c1986dea1e972'
CONFIGURATION_SHA = '3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701'
HOUND_GLB_SHA = '22a9292b5fa62ae1a64d91cd7e840632119afd62a7c21d8485b5b9de011bc236'
EFFECTS = {
    'D15_dog_smoke(spine_root_joint)': 4864194305762029017,
    'D15_dog_smoke_startEnd(spine_root_joint)': -7847685210556599889,
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


class HoundAttachmentPose:
    """The exact GLB pose sampled by sourceBoneTransform, in source Unity axes."""
    def __init__(self, path):
        raw = path.read_bytes()
        require(len(raw) == 438144 and sha(raw) == HOUND_GLB_SHA, 'Reviewed original hound GLB differs')
        self.gltf, binary = glb_read(path)
        self.names = {n['name']: i for i, n in enumerate(self.gltf['nodes'])}
        _, self.rest, self.parents = world_poses(self.gltf['nodes'])
        self.bone = self.names['spine_root_joint']
        animations = self.gltf['animations']
        require(len(animations) == 1 and animations[0]['name'] == 'd15_dog_attack', 'Hound FX motion differs')
        self.channels = []
        for c in animations[0]['channels']:
            s = animations[0]['samplers'][c['sampler']]
            require(s.get('interpolation', 'LINEAR') == 'LINEAR', 'Unsupported original hound interpolation')
            times = accessor_read(self.gltf, binary, s['input']).astype(float)
            values = accessor_read(self.gltf, binary, s['output']).astype(float)
            require(len(times) == len(values) == 60, 'Original hound FX crop differs')
            self.channels.append((c['target']['node'], c['target']['path'], times, values))
        self.cache = {}

    def source_rotation(self, model_age):
        require(0 <= model_age <= 110 and np.isfinite(model_age), 'Hound attachment age is outside the source model')
        key = float(np.float32(model_age / 60))
        if key in self.cache:
            return self.cache[key]
        nodes = self.gltf['nodes']
        translation = [np.asarray(n.get('translation', [0, 0, 0]), dtype=float).copy() for n in nodes]
        rotation = [np.asarray(n.get('rotation', [0, 0, 0, 1]), dtype=float).copy() for n in nodes]
        scale = [np.asarray(n.get('scale', [1, 1, 1]), dtype=float).copy() for n in nodes]
        for node, path, times, values in self.channels:
            upper = min(len(times) - 1, int(np.searchsorted(times, key, side='right')))
            lower = max(0, upper - 1)
            fraction = np.clip((key - times[lower]) / (times[upper] - times[lower]), 0, 1) if upper != lower else 0
            a, b = values[lower], values[upper]
            if path == 'rotation':
                a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
                if a @ b < 0: b = -b
                value = a * (1 - fraction) + b * fraction
                rotation[node] = value / np.linalg.norm(value)
            elif path == 'translation': translation[node] = a * (1 - fraction) + b * fraction
            else:
                require(path == 'scale', 'Unsupported original GLB channel')
                scale[node] = a * (1 - fraction) + b * fraction
        local = [value.copy() for value in self.rest]
        for node in {c[0] for c in self.channels}:
            local[node] = matrix(translation[node], rotation[node], scale[node])
        # Runtime holder Ry(-pi/2) plus the original converted GLB basis.
        holder = np.array([[0., 0., -1.], [0., 1., 0.], [1., 0., 0.]])
        reflected = holder @ pose_world(local, self.parents)[self.bone][:3, :3]
        reflected /= np.linalg.norm(reflected, axis=0)
        flip = np.diag([1., 1., -1.])
        value = flip @ reflected @ flip
        require(np.max(abs(value.T @ value - np.eye(3))) < 1e-6, 'Hound source attachment includes unsupported shear')
        self.cache[key] = value
        return value


def inventory(environment, name, identity):
    paths = [(p, o) for p, o in environment.container.items()
             if p.endswith('/' + name.lower() + '.prefab') and o.path_id == identity]
    require(len(paths) == 1, 'Original D15 effect identity differs: ' + name)
    path, pointer = paths[0]
    rows, seen = [], set()

    def walk(go, parent):
        transforms = [c.component.read() for c in go.m_Component if c.component.deref().type.name == 'Transform']
        require(len(transforms) == 1, 'Ambiguous original D15 transform')
        t = transforms[0]
        require(t.object_reader.path_id not in seen, 'Source transform cycle')
        seen.add(t.object_reader.path_id)
        row = dict(name=go.m_Name, pathID=t.object_reader.path_id, parent=parent,
                   position=[t.m_LocalPosition.x, t.m_LocalPosition.y, t.m_LocalPosition.z],
                   rotation=[t.m_LocalRotation.x, t.m_LocalRotation.y, t.m_LocalRotation.z, t.m_LocalRotation.w],
                   scale=[t.m_LocalScale.x, t.m_LocalScale.y, t.m_LocalScale.z],
                   active=bool(go.m_IsActive), layer=int(go.m_Layer),
                   components=[c.component.deref() for c in go.m_Component])
        rows.append(row)
        for child in t.m_Children:
            walk(child.read().m_GameObject.read(), t.object_reader.path_id)

    walk(pointer.read(), None)
    return path, rows


def build(args):
    import UnityPy
    from UnityPy.helpers import TypeTreeHelper
    from UnityPy.streams import EndianBinaryReader
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    output = private_output(args.output)
    require(not any(output.iterdir()), 'D15 effect output must be empty')
    assets = SourceAssets(args.models, args.effects, output, bundle_identity=BUNDLE)
    shader_raw = args.shader_bundle.read_bytes()
    require(sha(shader_raw) == SHADER_SHA, 'Original shader bundle differs')
    shader_environment = UnityPy.load(shader_raw)
    shaders = {str(o.path_id): o for o in shader_environment.objects if o.type.name == 'Shader'}
    material_type = next(o for o in assets.environment.objects if o.type.name == 'Material')
    profile_raw = args.profile.read_bytes()
    profile = json.loads(profile_raw)
    require(profile['id'] == 'wuyong_erlang' and len(profile['sha256']) == 64, 'Wrong character profile')
    hound = [t for t in profile.get('summonTracks', []) if t['role'] == 'erlangSummon_hound']
    require(len(hound) == 1 and hound[0]['sourceSHA256'] == '6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712'
            and hound[0]['frames'] == 60 and hound[0]['sourceEndEventTick'] == 110, 'Original hound profile track differs')
    attachment = HoundAttachmentPose(args.hound_glb)
    queues, proofs, sampled = {}, [], []

    def queue(pointer, descriptor):
        key = descriptor['sourceMaterialSHA256']
        if key in queues:
            return queues[key]
        cab, path_id = assets.key(pointer)
        if cab is None:
            material = assets.local[path_id].read_typetree()
        else:
            record = assets.record('Material', cab, path_id)
            raw = Path(record['rawFile']).read_bytes()
            material = TypeTreeHelper.read_typetree(material_type.serialized_type.node,
                EndianBinaryReader(raw, endian=material_type.reader.endian), byte_size=len(raw), as_dict=True)
            require(json.loads(json.dumps(material)) == json.loads(Path(record['metadataFile']).read_text()),
                    'Source material metadata differs from original object bytes')
        shader = shaders[descriptor['shaderPathID']]
        require(sha(shader.get_raw_data()) == descriptor['sourceShaderSHA256'], 'Original shader object differs')
        forms = shader.read_typetree()['m_ParsedForm']['m_SubShaders']
        require(len(forms) == 1, 'Ambiguous source subshader')
        tags = [v for k, v in forms[0]['m_Tags']['tags'] if k.lower() == 'queue']
        require(len(tags) == 1, 'Missing source queue')
        queues[key] = source_queue(material['m_CustomRenderQueue'], tags[0])
        return queues[key]

    effects = {}
    for name, identity in EFFECTS.items():
        path, rows = inventory(assets.environment, name, identity)
        controllers = [c.read_typetree() for c in rows[0]['components'] if c.type.name == 'MonoBehaviour'
                       and 'overrideDuration' in c.read_typetree()]
        require(len(controllers) == 1, 'D15 source effect controller is ambiguous')
        controller = controllers[0]
        require(not controller['overrideDuration'] and not controller['delayedEffects']
                and all(controller[k] == 0 for k in ('ignoreTimeScale', 'takeInAccountCharacterDirection',
                    '_useMirroring', '_inverseMirroring', '_ignoreFlipByZ', '_flipByAccountCharacterDirection',
                    '_rotateAttachToLocal', '_trackingAccountModelDirection')), 'Unadapted D15 controller behavior')
        worlds, active, tracks = {}, {}, []
        for row in rows:
            local = matrix(row['position'], row['rotation'], row['scale'])
            world = worlds[row['parent']] @ local if row['parent'] is not None else local
            worlds[row['pathID']] = world
            active[row['pathID']] = row['active'] and (active[row['parent']] if row['parent'] is not None else True)
            systems = [c for c in row['components'] if c.type.name == 'ParticleSystem']
            renderers = [c for c in row['components'] if c.type.name == 'ParticleSystemRenderer']
            if not systems:
                continue
            require(len(systems) == len(renderers) == 1, 'Ambiguous D15 emitter/renderer')
            source, renderer = systems[0].read_typetree(), renderers[0].read_typetree()
            if not active[row['pathID']] or not renderer['m_Enabled']:
                continue
            require(not any(source[k]['enabled'] for k in ('NoiseModule', 'ExternalForcesModule', 'SubModule', 'TrailModule', 'ForceModule')),
                    'Original D15 emitter requires another engine module adapter')
            require(source['moveWithTransform'] in (0, 1) and not source['prewarm']
                    and renderer['m_RenderMode'] in (0, 4) and renderer['m_RenderAlignment'] == 0,
                    'Unadapted D15 simulation space, prewarm or renderer mode')
            require(renderer['m_SortMode'] in (0, 2, 3, 4) and renderer['m_SortingLayer'] == renderer['m_SortingLayerID'] == 0
                    and renderer['m_SortingFudge'] == 0, 'Unsupported source sorting policy')
            material_id = assets.material(renderer['m_Materials'][0])
            material = assets.materials[material_id]
            render_queue = queue(renderer['m_Materials'][0], material)
            geometry = assets.geometry(renderer['m_Mesh']) if renderer['m_RenderMode'] == 4 else None
            emitter = str(systems[0].path_id)
            speed = source['simulationSpeed']
            delay0 = minmax(source['startDelay'], 0, random.Random(seed(emitter, 'delay')).random()) / speed
            schedule = emission_schedule(source, emitter)
            emitted = 0
            for particle, birth, period in schedule:
                delay = delay0 + birth / speed
                dynamic = name == 'D15_dog_smoke(spine_root_joint)'
                if dynamic and delay >= 110 / 60:
                    continue
                if dynamic:
                    require(period is None or period / speed > 110 / 60,
                            'Repeated animated birth needs its own attachment sampling')
                    require(source['VelocityModule']['enabled'] and source['VelocityModule']['inWorldSpace'],
                            'Reviewed animated hound world-velocity module differs')
                    # Facing is a world-Y rotation. Only the original vertical
                    # world term may share these samples across both facings.
                    for phase in np.linspace(0, 1, 65):
                        for random_value in (0., .5, 1.):
                            require(all(abs(minmax(source['VelocityModule'][k], phase, random_value)) < 1e-9
                                        for k in ('x', 'z')), 'Nonvertical world wind requires separate facing samples')
                    birth_age = delay * 60
                    parent = (lambda time, birth_age=birth_age, space=source['moveWithTransform']:
                              attachment.source_rotation(min(110., birth_age + time * 60) if space == 0 else birth_age))
                else:
                    parent = None
                data, receipt = sample_particle(source, renderer, world, row['scale'], particle,
                    project_gravity=assets.gravity, parent_rotation_at=parent,
                    sample_until=110 / 60 - delay if dynamic else None)
                floats = material['floats']
                blend = (floats.get('_Blend1', floats.get('_SrcBlend', 1)), floats.get('_Blend2', floats.get('_DstBlend', 0)))
                track = dict(name=row['name'] + '_' + emitter + '_' + str(particle.index) + '_' + str(len(tracks)),
                    layer=row['layer'], material=material_id, texture=material['textures']['_MainTex']['file'],
                    blend='add' if blend[1] == 1 else 'alpha', wrapS=material['textures']['_MainTex']['wrapS'],
                    wrapT=material['textures']['_MainTex']['wrapT'], multiplyTextureAlpha=blend[0] == 5,
                    overlay=False, sortingOrder=renderer['m_SortingOrder'], delay=round(delay, 7),
                    duration=data['frames'][-1][0], vertexStreams=renderer['m_VertexStreams'],
                    sourceRenderMode=renderer['m_RenderMode'], sourceRenderAlignment=renderer['m_RenderAlignment'],
                    sourceSimulationSpace=source['moveWithTransform'], sourceParticleSystem=emitter,
                    sourceSortMode=renderer['m_SortMode'], sourceSortingLayer=0, sourceRenderQueue=render_queue,
                    sourceAgeOffset=0., stableRandom=[particle.r('stableRandom' + str(i)) for i in range(4)], **data)
                if period is not None:
                    track['loopPeriod'] = round(period / speed, 7)
                if geometry is not None:
                    track['geometry'] = geometry
                else:
                    track.pop('orientations'); track.pop('depthScales')
                tracks.append(track)
                emitted += 1
                sampled.append(dict(effect=name, emitter=emitter, sourceAttachmentProjection=dynamic,
                    modelBirthTick=delay * 60, modelEndTick=110 if dynamic else None, **receipt))
            proofs.append(dict(effect=name, sourcePrefab=path, sourcePrefabPathID=str(identity),
                sourceParticleSystem=emitter, sourceParticleSystemSHA256=sha(systems[0].get_raw_data()),
                sourceRendererPathID=str(renderers[0].path_id), sourceRendererSHA256=sha(renderers[0].get_raw_data()),
                sourceSimulationSpace=source['moveWithTransform'], sourceRenderQueue=render_queue,
                sourceSortMode=renderer['m_SortMode'], sourceSortingOrder=renderer['m_SortingOrder'],
                sourceTransforms=[{k: x[k] for k in ('name', 'pathID', 'parent', 'position', 'rotation', 'scale')} for x in rows],
                scheduledTracks=len(schedule), emittedTracks=emitted))
        require(tracks, 'Original D15 effect has no supported tracks')
        effects[name] = dict(sourceName=path, duration=round(max(t['delay'] + t['duration'] for t in tracks), 7),
            tracks=tracks, sourceDurationOverride=None, sourceController={k: v for k, v in controller.items()
                if k not in ('m_GameObject', 'm_Script', 'm_Name', 'm_Enabled')})
        print(json.dumps(dict(effect=name, tracks=len(tracks), samples=sum(len(t['frames']) for t in tracks))), flush=True)
    require(len(proofs) == 9, 'Original two hound effects must resolve nine emitters')
    document = dict(version=1, profileID='wuyong_erlang', characterSHA256=profile['sha256'],
        sourceConfigurationSHA256=CONFIGURATION_SHA, sampleRate=60, worldUnitsPerSourceUnit=.01,
        evidence=['Two original D15 hound effect prefabs; exact source curves, meshes, material variants and textures.',
            'One deterministic realization of original automatic random seeds; no claim of cross-engine pixel equivalence.',
            'Local particles follow the source attachment; world particles retain the attachment at their own original birth time.',
            'Original world-space upward velocity is projected through each actual animated bone pose and emitter scale.',
            'Unsupported force, noise, sub-emitter and trail modules reject this scoped export.'],
        files=sorted(assets.files.values(), key=lambda x: x['name']), materials=assets.materials,
        effects=effects, bindings=[], markers=[])
    raw = json.dumps(document, separators=(',', ':'), allow_nan=False).encode()
    compressed = gzip.compress(raw, mtime=0)
    require(len(raw) < 256_000_000 and len(compressed) < 32_000_000, 'D15 effect export exceeds loader bounds')
    write_private(output / 'SF3_D15_Effects.json', raw)
    write_private(output / 'SF3_D15_Effects.json.gz', compressed)
    receipt = dict(schema='original-d15-hound-effects-v1', sourceBundle=BUNDLE[0], sourceBundleSHA256=BUNDLE[1],
        profileSHA256=sha(profile_raw), characterSHA256=profile['sha256'], houndTrack=hound[0],
        houndPoseGLBSHA256=HOUND_GLB_SHA, observableModelEndTick=110,
        effectsFile=dict(name='SF3_D15_Effects.json.gz', bytes=len(compressed), sha256=sha(compressed)),
        sourceEmitters=proofs, sourceAssets=assets.audit, sourceSamples=sampled, engineParityVerified=False)
    write_private(output / 'd15-hound-fx-receipt-private.json', json.dumps(receipt, separators=(',', ':'), allow_nan=False).encode())
    print(json.dumps(dict(rawBytes=len(raw), bytes=len(compressed), sha256=sha(compressed), materials=len(assets.materials),
        files=len(assets.files), effects=len(effects), emitters=len(proofs), tracks=sum(len(e['tracks']) for e in effects.values())), separators=(',', ':')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('models', 'effects', 'shader-bundle', 'profile', 'hound-glb', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    build(parser.parse_args())


if __name__ == '__main__':
    main()
