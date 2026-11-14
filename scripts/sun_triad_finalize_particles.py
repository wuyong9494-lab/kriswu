#!/usr/bin/env python3
"""Refresh authenticated source shader resources and merge private FX resamples.

This avoids re-sampling unaffected particle histories when a narrowly scoped
source project setting is recovered. Replacements must carry the same source,
character, and configuration identities. Original shader, texture and geometry
dependencies are resolved and verified again from local source bytes.
"""
from __future__ import annotations
import argparse, gzip, hashlib, json, warnings
from pathlib import Path
import numpy as np
from sun_triad_assets import require,private_output,write_private
from sun_triad_particle_assets import SourceAssets


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('models','effects','candidate'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--patch',type=Path,action='append',default=[])
    args=parser.parse_args();warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    output=private_output(args.candidate)
    document=json.loads((output/'SF3_H17_Effects.json').read_text())
    provenance=json.loads((output/'h17-particle-sampling-provenance-private.json').read_text())
    merge_receipts=[]
    for directory in args.patch:
        raw=(directory/'SF3_H17_Effects.json').read_bytes();patch=json.loads(raw)
        receipt=json.loads((directory/'h17-particle-sampling-provenance-private.json').read_text())
        require(all(patch[k]==document[k] for k in ('version','profileID','characterSHA256','sourceConfigurationSHA256',
                                                  'sampleRate','worldUnitsPerSourceUnit')),'Replacement effect identity differs')
        require(receipt['sourceBundleSHA256']==provenance['sourceBundleSHA256'],'Replacement source bundle differs')
        names=set(patch['effects']);require(names and names<=set(document['effects']),'Replacement effects do not match original candidate')
        document['effects'].update(patch['effects'])
        for key in ('particles','unadaptedModules'):
            provenance[key]=[item for item in provenance[key] if item['effect'] not in names]+receipt[key]
        merge_receipts.append(dict(effectNames=sorted(names),resampledDocumentSHA256=sha(raw),
            projectPhysicsQualityEvidence=receipt.get('projectPhysicsQualityEvidence')))

    assets=SourceAssets(args.models,args.effects,output)
    inventory=json.loads((args.effects/'h17-effects-inventory.json').read_text())
    require(provenance['sourceBundleSHA256']==inventory['sourceBundleSHA256'],'Original effect bundle evidence differs')
    entries={entry['rootName']:entry for entry in inventory['entries']}
    frames_total=0;tracks_total=0;max_dimension=0.;material_by_emitter={};validated_geometry=set()
    for name,effect in document['effects'].items():
        require(name in entries and effect['sourceName']==entries[name]['sourcePath'],'Original effect resource path differs')
        renderers={}
        for transform in entries[name]['transforms']:
            refs={item['type']:item['pathID'] for item in transform['components']}
            if 'ParticleSystem' in refs:
                renderers[refs['ParticleSystem']]=assets.local[int(refs['ParticleSystemRenderer'])].read_typetree()
        require(1<=len(effect['tracks'])<=4096 and 0<effect['duration']<=36000,'Effect timeline exceeds bounds')
        for track in effect['tracks']:
            emitter=track['sourceParticleSystem'];require(emitter in renderers,'Particle timeline belongs to another source prefab')
            renderer=renderers[emitter]
            if emitter not in material_by_emitter:material_by_emitter[emitter]=assets.material(renderer['m_Materials'][0])
            require(track['material']==material_by_emitter[emitter],'Source particle material binding differs')
            if renderer['m_RenderMode']==4 and emitter not in validated_geometry:
                require(track.get('geometry')==assets.geometry(renderer['m_Mesh']),'Original source particle mesh changed')
                validated_geometry.add(emitter)
            frames=np.asarray(track['frames'],dtype=float)
            require(frames.ndim==2 and frames.shape[1]==15 and 2<=len(frames)<=14401 and np.isfinite(frames).all(),
                    'Source particle samples exceed format bounds')
            require(frames[0,0]==0 and abs(frames[-1,0]-track['duration'])<1e-6 and np.all(np.diff(frames[:,0])>0),
                    'Source particle sample clock is invalid')
            require(track['delay']>=0 and 0<track['duration']<=36000,'Source particle timing exceeds bounds')
            if 'loopPeriod' in track:require(track['loopPeriod']+1e-6>=track['duration'],'Recurring particle would overwrite a live predecessor')
            for key,width in (('orientations',4),('customData1',4),('customData2',4)):
                if key not in track:continue
                values=np.asarray(track[key]);require(values.shape==(len(frames),width) and np.isfinite(values).all(),
                    'Source particle custom stream lost its common timeline')
                if key=='orientations':require(np.max(abs(np.linalg.norm(values,axis=1)-1))<1e-4,'Invalid source particle orientation')
            if 'depthScales' in track:require(len(track['depthScales'])==len(frames),'Source particle depth timeline differs')
            max_dimension=max(max_dimension,float(np.max(abs(frames[:,4:6]))))
            frames_total+=len(frames);tracks_total+=1
    require(frames_total<=1_000_000,'Particle sample budget exceeded')
    document['materials']=assets.materials;document['files']=sorted(assets.files.values(),key=lambda item:item['name'])
    references=set()
    for material in document['materials'].values():
        references.add(material['program']['file'])
        for texture in material['textures'].values():references.update((texture['file'],texture['dataFile']))
    require(references==set(assets.files),'Effect material references and pinned resource set differ')
    resource_bytes=sum(item['bytes'] for item in assets.files.values())
    require(resource_bytes<=40_000_000 and all(item['bytes']<=6_000_000 for item in assets.files.values()),
            'Original texture/program resource budget exceeded')
    for item in document['files']:
        raw=(output/item['name']).read_bytes()
        require(len(raw)==item['bytes'] and sha(raw)==item['sha256'],'Final resource bytes differ from manifest')
    document['evidence']+=['Original compressed texture formats and every source mip level are retained; PNGs are previews.',
        'Source project Gamma color space, serialized quality anisotropy, original blend/depth/ColorMask and source-unit gravity are applied.']
    raw=json.dumps(document,separators=(',',':'),allow_nan=False).encode();compressed=gzip.compress(raw,mtime=0)
    require(len(raw)<=256_000_000 and len(compressed)<=32_000_000,'Bounded effect decompression limit exceeded')
    require(gzip.decompress(compressed)==raw,'Deterministic gzip content differs')
    write_private(output/'SF3_H17_Effects.json',raw);write_private(output/'SF3_H17_Effects.json.gz',compressed)
    provenance.update(sourceObjects=assets.audit,projectColorSpaceEvidence=assets.color_space,
        projectPhysicsQualityEvidence=assets.physics_quality,resampleMerges=merge_receipts)
    write_private(output/'h17-particle-sampling-provenance-private.json',json.dumps(provenance,indent=2,allow_nan=False).encode())
    receipt=dict(runtimeFile='SF3_H17_Effects.json.gz',bytes=len(compressed),sha256=sha(compressed),
        decodedBytes=len(raw),decodedSHA256=sha(raw),sourcePrefabs=len(inventory['entries']),sampledEffects=len(document['effects']),
        tracks=tracks_total,samples=frames_total,maximumTracksPerEffect=max(len(e['tracks']) for e in document['effects'].values()),
        materials=len(document['materials']),resourceFiles=len(document['files']),resourceBytes=resource_bytes,
        maximumResourceBytes=max(item['bytes'] for item in document['files']),maximumParticleWidthOrHeight=max_dimension,
        notYetSampledPrefabs=sorted(set(entries)-set(document['effects'])),unadaptedModules=provenance['unadaptedModules'])
    write_private(output/'h17-effects-final-receipt-private.json',json.dumps(receipt,indent=2).encode())
    print(json.dumps({k:v for k,v in receipt.items() if k not in ('unadaptedModules',)}))


if __name__=='__main__':main()
