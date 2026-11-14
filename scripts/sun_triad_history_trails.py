#!/usr/bin/env python3
"""Add four original Ninjato particle-history trails to the private FX document.

These histories are deliberately separate from precomputed particle tracks:
their world points must be emitted from the real, fixed-step weapon attachment
pose at runtime. They retain the original particle lifetime, trail multiplier,
width and every color/alpha key. They do not follow later weapon motion.
"""
from __future__ import annotations
import argparse,gzip,hashlib,json,warnings
from pathlib import Path
import numpy as np
from sun_triad_assets import matrix,require,private_output,write_private
from sun_triad_particle_assets import SourceAssets
from sun_triad_particle_curves import gradient,color,minmax
from sun_triad_particles import emission_schedule,sample_particle

MANUAL='https://docs.unity3d.com/6000.3/Documentation/Manual/PartSysTrailsModule.html'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def gradient_keys(value):
    mode=value['minMaxState']
    if mode==0:
        rgba=color(value,0,0).tolist();return [[0.,*rgba],[1.,*rgba]]
    require(mode==1,'This source history needs an explicit random-gradient adapter')
    g=value['maxGradient'];require(g['m_Mode']==0,'Source history gradient is not linear')
    times={0.,1.}
    times.update(g['ctime'+str(i)]/65535 for i in range(g['m_NumColorKeys']))
    times.update(g['atime'+str(i)]/65535 for i in range(g['m_NumAlphaKeys']))
    return [[time,*gradient(g,time).tolist()] for time in sorted(times)]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('models','effects','candidate'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    output=private_output(args.candidate);assets=SourceAssets(args.models,args.effects,output)
    inventory=json.loads((args.effects/'h17-effects-inventory.json').read_text())
    document=json.loads((output/'SF3_H17_Effects.json').read_text())
    provenance=json.loads((output/'h17-particle-sampling-provenance-private.json').read_text())
    proofs=[];source_ids=set()
    for entry in inventory['entries']:
        if not entry['rootName'].startswith('h17_ninjatoFire_trail_'):continue
        roots=entry['transforms'][0]['components'];controllers=[]
        for ref in roots:
            if ref['type']=='MonoBehaviour':
                data=assets.local[int(ref['pathID'])].read_typetree()
                if 'overrideDuration' in data:controllers.append(data)
        require(len(controllers)==1 and not controllers[0]['overrideDuration'],'Unexpected original history controller')
        controller=controllers[0];worlds={};histories=[]
        for transform in entry['transforms']:
            parent=transform['parentPathID'];local=matrix(transform['position'],transform['rotation'],transform['scale'])
            world=worlds[parent]@local if parent else local;worlds[transform['pathID']]=world
            refs={ref['type']:ref['pathID'] for ref in transform['components']}
            if 'ParticleSystem' not in refs:continue
            identity=refs['ParticleSystem'];source=assets.local[int(identity)].read_typetree();trail=source['TrailModule']
            renderer=assets.local[int(refs['ParticleSystemRenderer'])].read_typetree()
            require(trail['enabled'] and renderer['m_RenderMode']==5 and renderer['m_Enabled'],
                    'Original history renderer type differs')
            require(trail['mode']==0 and trail['ratio']==1 and trail['worldSpace'] and not trail['dieWithParticles']
                    and not trail['sizeAffectsWidth'] and not trail['sizeAffectsLifetime']
                    and not trail['inheritParticleColor'] and not trail['generateLightingData']
                    and trail['textureMode']==0 and trail['ribbonCount']==1,'Unsupported original history semantics')
            enabled=[key for key,value in source.items() if isinstance(value,dict) and value.get('enabled')]
            require(set(enabled)=={'InitialModule','EmissionModule','TrailModule'},'History source has additional active particle modules')
            require(source['moveWithTransform']==0 and source['scalingMode']==1
                    and transform['scale']==[1.,1.,1.] and not source['prewarm'] and not source['looping'],
                    'History requires the original local, non-looping particle source')
            schedule=emission_schedule(source,identity)
            require(len(schedule)==1 and schedule[0][1]==0 and schedule[0][2] is None,'History source is not one explicit birth')
            particle,birth,_=schedule[0];speed=source['simulationSpeed']
            sampled,_=sample_particle(source,renderer,world,transform['scale'],particle,project_gravity=assets.gravity)
            require(trail['lifetime']['minMaxState']==0 and trail['widthOverTrail']['minMaxState']==0,
                    'History lifetime or width needs a curved source adapter')
            width=float(trail['widthOverTrail']['scalar']);tail=particle.life*trail['lifetime']['scalar']/speed
            particle_color=color(source['InitialModule']['startColor'],0,0).tolist()
            require(particle_color==[1,1,1,1],'Original history particle color differs')
            require(len(renderer['m_Materials'])==2,'Original history material slot is missing')
            material=assets.material(renderer['m_Materials'][1]);game_object=assets.local[int(source['m_GameObject']['m_PathID'])].read()
            history=dict(name=transform['name'],sourceParticleSystem=identity,material=material,
                vertexStreams=renderer['m_TrailVertexStreams'],layer=game_object.m_Layer,sortingOrder=renderer['m_SortingOrder'],
                birth=float(minmax(source['startDelay'],0,0)/speed),life=particle.life/speed,tailLife=float(tail),
                minVertexDistance=float(trail['minVertexDistance']),width=width,
                positions=[frame[:4] for frame in sampled['frames']],widthOverTrail=[[0.,width],[1.,width]],
                colorOverLifetime=gradient_keys(trail['colorOverLifetime']),colorOverTrail=gradient_keys(trail['colorOverTrail']),
                particleColor=particle_color,textureMode=trail['textureMode'],
                textureScale=[trail['textureScale']['x'],trail['textureScale']['y']],
                mode=trail['mode'],ribbonCount=trail['ribbonCount'],generateLightingData=trail['generateLightingData'],
                shadowBias=trail['shadowBias'],worldSpace=trail['worldSpace'],dieWithParticles=trail['dieWithParticles'],
                inheritParticleColor=trail['inheritParticleColor'],sizeAffectsWidth=trail['sizeAffectsWidth'],
                sizeAffectsLifetime=trail['sizeAffectsLifetime'],sourceSimulationSpace=source['moveWithTransform'],
                sourceScalingMode=source['scalingMode'],sourceEmitterScale=transform['scale'])
            histories.append(history);source_ids.add(identity)
            proofs.append(dict(effect=entry['rootName'],sourceParticleSystem=identity,
                sourceParticleSystemSHA256=sha(assets.local[int(identity)].get_raw_data()),
                sourceRendererSHA256=sha(assets.local[int(refs['ParticleSystemRenderer'])].get_raw_data()),
                sourceTrailModule=trail,sourceInitialModule=source['InitialModule'],
                sourceEmission=source['EmissionModule'],sourceController=controller,
                sourceScalingMode=source['scalingMode'],sourceEmitterScale=transform['scale'],
                lifetimeRule='Trail point lifetime = original particle lifetime times original TrailModule lifetime multiplier.',
                curveRule='All original gradient color and alpha key times are retained exactly; width is a verified constant.',
                worldHistoryRule='Runtime stores the real attachment-transformed position every simulation tick and never reparents saved world points.',
                sourceReference=MANUAL))
        require(len(histories)==1,'Unexpected source history emitter count')
        document['effects'][entry['rootName']]=dict(sourceName=entry['sourcePath'],tracks=[],historyTrails=histories,
            duration=max(h['birth']+h['life']+h['tailLife'] for h in histories),sourceDurationOverride=None,
            sourceController={k:v for k,v in controller.items() if k not in ('m_GameObject','m_Script','m_Name','m_Enabled')})
    require(len(proofs)==4,'Original Ninjato history prefab inventory differs')
    for key,material in assets.materials.items():
        if key in document['materials']:require(document['materials'][key]==material,'History and particle source material descriptors conflict')
        document['materials'][key]=material
    files={item['name']:item for item in document['files']}
    for key,item in assets.files.items():
        if key in files:require(files[key]==item,'History and particle resource pins conflict')
        files[key]=item
    document['files']=sorted(files.values(),key=lambda item:item['name'])
    provenance['historyTrails']=proofs
    provenance['unadaptedModules']=[item for item in provenance['unadaptedModules'] if item['sourcePathID'] not in source_ids]
    evidence='Four original Ninjato TrailModule prefabs use independent fixed-step world history, original lifetime multipliers, exact gradient keys and source trail material.'
    if evidence not in document['evidence']:document['evidence'].append(evidence)
    raw=json.dumps(document,separators=(',',':'),allow_nan=False).encode();compressed=gzip.compress(raw,mtime=0)
    require(len(raw)<=256_000_000 and len(compressed)<=32_000_000,'History document exceeds bounded decompression limits')
    write_private(output/'SF3_H17_Effects.json',raw);write_private(output/'SF3_H17_Effects.json.gz',compressed)
    write_private(output/'h17-particle-sampling-provenance-private.json',json.dumps(provenance,indent=2,allow_nan=False).encode())
    receipt=dict(file='SF3_H17_Effects.json.gz',bytes=len(compressed),sha256=sha(compressed),decodedBytes=len(raw),decodedSHA256=sha(raw),
        effects=len(document['effects']),historyTrails=len(proofs),materials=len(document['materials']),
        resourceFiles=len(files),resourceBytes=sum(item['bytes'] for item in files.values()),
        histories=[dict(effect=proof['effect'],**{key:document['effects'][proof['effect']]['historyTrails'][0][key]
            for key in ('life','tailLife','width','minVertexDistance','material')}) for proof in proofs])
    write_private(output/'h17-history-trails-receipt-private.json',json.dumps(receipt,indent=2).encode());print(json.dumps(receipt))


if __name__=='__main__':main()
