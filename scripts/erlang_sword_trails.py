#!/usr/bin/env python3
"""Two exact D15 looping TrailModule sources and their visible particle heads.

Only local input is read by the caller. World-space history is deliberately
not baked here: the runtime samples the real fixed-step sword attachment.
"""
from __future__ import annotations
import json
from pathlib import Path

from sun_triad_assets import require
from sun_triad_history_trails import gradient_keys
from sun_triad_particle_curves import color
from sun_triad_particle_sort import source_queue
from sun_triad_particles import emission_schedule, sample_particle

TRAIL_SYSTEMS = {3820729297464905033, -9101295511791219383}
SOURCE_IDENTITIES = {
    3820729297464905033: ('32547f9dd530dc9f10adc241cbb169a7a6fa30bb137fccf32d0f297204fef93d', -4090667728569622105, 1),
    -9101295511791219383: ('a68262e4f5895ad18f4da2edc9241d98a2da2c428e8a12ada69ca2540c0b08f5', -3196968270162323177, 0),
}


def export_trail(assets, row, source, render, world, proof):
    identity = int(proof['sourceParticleSystem'])
    digest, material_path_id, order = SOURCE_IDENTITIES[identity]
    trail, initial = source['TrailModule'], source['InitialModule']
    require(proof['sourceParticleSystemSHA256'] == digest and
            {k for k, v in source.items() if isinstance(v, dict) and v.get('enabled')} ==
            {'InitialModule', 'EmissionModule', 'TrailModule'}, 'Original sword Trail source differs')
    require(source['simulationSpeed'] == source['lengthInSec'] == 1 and source['looping'] and
            source['moveWithTransform'] == 0 and source['scalingMode'] == 1 and not source['prewarm'] and
            row['scale'] == [1., 1., 1.] and source['startDelay']['minMaxState'] == 0 and
            source['startDelay']['scalar'] == 0, 'Original sword Trail clock or local scaling differs')
    require(trail['mode'] == 0 and trail['ratio'] == 1 and trail['worldSpace'] and not trail['dieWithParticles'] and
            not trail['sizeAffectsWidth'] and not trail['sizeAffectsLifetime'] and trail['inheritParticleColor'] and
            not trail['generateLightingData'] and trail['textureMode'] == 0 and trail['ribbonCount'] == 1 and
            not trail['splitSubEmitterRibbons'] and not trail['attachRibbonsToTransform'] and
            trail['lifetime']['minMaxState'] == trail['widthOverTrail']['minMaxState'] == 0 and
            abs(trail['lifetime']['scalar'] - .33) < 1e-7 and trail['widthOverTrail']['scalar'] == 33 and
            abs(trail['minVertexDistance'] - .2) < 1e-7, 'Unadapted source sword Trail semantics')
    for key, value in [('startLifetime', 1), ('startSpeed', 0), ('startSize', 1),
                       ('startRotation', 0), ('gravityModifier', 0)]:
        require(initial[key]['minMaxState'] == 0 and initial[key]['scalar'] == value,
                'Original Trail particle head requires another motion adapter')
    require(not initial['rotation3D'] and not initial['size3D'] and
            color(initial['startColor'], 0, 0).tolist() == [1, 1, 1, 1] and
            render['m_RenderMode'] == render['m_RenderAlignment'] == 0 and
            render['m_Pivot'] == render['m_Flip'] == dict(x=0., y=0., z=0.) and
            render['m_MinParticleSize'] == 0 and render['m_MaxParticleSize'] == .5 and
            render['m_SortMode'] == render['m_SortingLayer'] == render['m_SortingLayerID'] == render['m_SortingFudge'] == 0 and
            render['m_SortingOrder'] == order and render['m_VertexStreams'] == render['m_TrailVertexStreams'] == [0, 1, 3, 4] and
            render['m_Materials'] == [{'m_FileID': 2, 'm_PathID': material_path_id}] * 2,
            'Original Trail head, two material slots or sorting differs')
    material_id = assets.material(render['m_Materials'][0]); material = assets.materials[material_id]
    require(assets.material(render['m_Materials'][1]) == material_id, 'Original Trail material slots differ')
    binding = next(m for m in assets.shader_document['materials'] if m['sourceObjectSHA256'] == material['sourceMaterialSHA256'])
    original_material = json.loads(Path(binding['metadataFile']).read_text())
    shader = next(s for s in assets.shader_document['shaders'] if s['pathID'] == binding['shaderPathID'])
    subshaders = json.loads(Path(shader['parsedFile']).read_text())['m_SubShaders']
    require(len(subshaders) == 1, 'Ambiguous original Trail subshader')
    queues = [v for k, v in subshaders[0]['m_Tags']['tags'] if k.lower() == 'queue']
    require(len(queues) == 1, 'Original Trail queue missing')
    queue = source_queue(original_material['m_CustomRenderQueue'], queues[0])
    schedule = emission_schedule(source, str(identity))
    require([(p.index, b, period, p.life) for p, b, period in schedule] == [(0, 0., 2., 1.), (1, 1., 2., 1.)],
            'Original Trail must retain one independent particle per second')
    heads, histories, samples = [], [], []
    for particle, birth, period in schedule:
        sampled, sample_proof = sample_particle(source, render, world, row['scale'], particle, project_gravity=assets.gravity)
        require(all(frame[4:11] == [1., 1., 0., 1., 1., 1., 1.] for frame in sampled['frames']),
                'Original Trail head has unexpected size, rotation or color')
        # Mode0/Alignment0 is a camera-view billboard, not the inactive Mesh
        # pointer and not a plane rotated with the sword. Keep its source head.
        sampled.pop('orientations'); sampled.pop('depthScales')
        blend = material['raster']
        name = row['name'] + '_' + str(identity) + '_' + str(particle.index)
        common = dict(sourceParticleSystem=str(identity), material=material_id, layer=row['layer'],
            sortingOrder=order, sourceSortMode=0, sourceSortingLayer=0, sourceRenderQueue=queue, sourceAgeOffset=0.)
        heads.append(dict(**common, name=name + '_head', texture=material['textures']['_MainTex']['file'],
            blend='add' if blend['destination'] == 1 else 'alpha', wrapS=material['textures']['_MainTex']['wrapS'],
            wrapT=material['textures']['_MainTex']['wrapT'], multiplyTextureAlpha=blend['source'] == 5,
            overlay=False, delay=birth, duration=1., loopPeriod=period,
            vertexStreams=render['m_VertexStreams'], sourceRenderMode=0, sourceRenderAlignment=0, sourceSimulationSpace=0,
            stableRandom=[particle.r('stableRandom' + str(i)) for i in range(4)], **sampled))
        histories.append(dict(**common, name=name + '_history', vertexStreams=render['m_TrailVertexStreams'],
            birth=birth, life=1., tailLife=trail['lifetime']['scalar'], loopPeriod=period,
            minVertexDistance=trail['minVertexDistance'], width=trail['widthOverTrail']['scalar'],
            positions=[frame[:4] for frame in sampled['frames']], widthOverTrail=[[0., 33.], [1., 33.]],
            colorOverLifetime=gradient_keys(trail['colorOverLifetime']), colorOverTrail=gradient_keys(trail['colorOverTrail']),
            particleColor=[1., 1., 1., 1.], textureMode=0,
            textureScale=[trail['textureScale']['x'], trail['textureScale']['y']],
            worldSpace=True, dieWithParticles=False, inheritParticleColor=True, sizeAffectsWidth=False,
            sizeAffectsLifetime=False, sourceSimulationSpace=0, sourceScalingMode=1, generateLightingData=False))
        samples.append(sample_proof)
    receipt = dict(**proof, sourceMaterialSHA256=material['sourceMaterialSHA256'], sourceRenderMode=0,
        sourceRenderAlignment=0, sourceLooping=True, samples=samples, sourceTrailModule=trail,
        sourceInitialModule=initial, sourceEmission=source['EmissionModule'],
        sourceReference='https://docs.unity3d.com/6000.3/Documentation/Manual/PartSysTrailsModule.html',
        historyRule='Each particle owns independent fixed-step world points; its death does not reparent or erase unexpired points.',
        lifetimeRule='Trail vertex lifetime is source particle life times the original .330000013 multiplier; source width is 33 cm.')
    return heads, histories, receipt
