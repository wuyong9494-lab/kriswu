#!/usr/bin/env python3
"""Sample exact companion BonesData capsules from already verified private GLBs.

This does not regenerate a model or invent capsules for ranged projectiles.
Original shared body capsules are added only when the source animation names
that exact attacking part and its original bone IDs agree with the actor rig.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
import numpy as np
from sun_triad_assets import (glb_read, accessor_read, world_poses, pose_world,
    matrix, capsule_point, private_output, write_private, require, CONFIG_FILES)
from sun_triad_source_bones import parse_bones_data, capsule_binding


def sample(document, binary, motion, capsules):
    names={n['name']:i for i,n in enumerate(document['nodes'])}
    require(all(c[end]['bone'] in names for c in capsules for end in ('base','tip')),
            'Original companion capsule references an absent skeleton node')
    _,rest,parents=world_poses(document['nodes'])
    animation=next(a for a in document['animations'] if a['name']==motion['clip'])
    channels=[]
    for channel in animation['channels']:
        sampler=animation['samplers'][channel['sampler']]
        require(sampler['interpolation']=='LINEAR','Unexpected companion interpolation')
        values=accessor_read(document,binary,sampler['output']).astype(float)
        require(len(values)==motion['frames'],'Companion source frame count changed')
        channels.append((channel['target']['node'],channel['target']['path'],values))
    output=[]
    for capsule in capsules:
        kind='hurt' if capsule['sourceAttributes'].get('Defense') else 'attack'
        output.append(dict(**capsule_binding(capsule,kind),base=[],tip=[]))
    for sample_index in range(2*motion['frames']-1):
        a=sample_index//2;b=min(motion['frames']-1,a+1);fraction=(sample_index%2)*.5
        values={}
        for node,path,array in channels:
            first,second=array[a],array[b]
            if path=='rotation' and first@second<0:second=-second
            values.setdefault(node,{})[path]=first*(1-fraction)+second*fraction
        local=[m.copy() for m in rest]
        for node,fields in values.items():
            source=document['nodes'][node]
            local[node]=matrix(fields.get('translation',source.get('translation',[0,0,0])),
                fields.get('rotation',source.get('rotation',[0,0,0,1])),
                fields.get('scale',source.get('scale',[1,1,1])))
        world=pose_world(local,parents)
        for capsule,destination in zip(capsules,output):
            for endpoint in ('base','tip'):
                destination[endpoint].append(np.round(capsule_point(capsule[endpoint],world,names),7).tolist())
    return output


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',type=Path,required=True)
    parser.add_argument('--spirits',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--source-attack-settings',type=Path,required=True)
    args=parser.parse_args();output=private_output(args.output)
    manifest=json.loads((args.spirits/'SF3_H17_Summons.json').read_text())
    attacks={r['animation']:r for r in json.loads(args.source_attack_settings.read_text())['records']}
    body_name,body_digest=CONFIG_FILES['fullBody'];body_raw=(args.models/body_name).read_bytes()
    require(hashlib.sha256(body_raw).hexdigest()==body_digest,'Shared source body BonesData digest mismatch')
    body=parse_bones_data(body_raw);body_capsules={c['id']:c for c in body['capsules']}
    records=[]
    for definition in manifest['models']:
        provenance=[json.loads(path.read_text()) for path in args.spirits.glob('h17-*-provenance.json')]
        matches=[p for p in provenance if p['sourceModel']==definition['sourceModel']]
        require(len(matches)==1,'Ambiguous companion provenance')
        record=matches[0];source_bones=record['sourceBones']
        filename=Path(record['sourceBundle']).stem+'_'+source_bones['sourcePathID']+'_bones.decoded.clear-private'
        raw=(args.models/filename).read_bytes()
        require(hashlib.sha256(raw).hexdigest()==source_bones['sha256'],'Companion BonesData digest mismatch')
        bone_data=parse_bones_data(raw);capsules=bone_data['capsules']
        path=args.spirits/definition['file']['name']
        require(hashlib.sha256(path.read_bytes()).hexdigest()==definition['file']['sha256'],'Companion GLB digest mismatch')
        document,binary=glb_read(path)
        for motion in definition['motions']:
            aliases=[record['sourceRoles'][role] for role in motion['roles']]
            require(all(name in attacks for name in aliases),'Original source attack settings are incomplete')
            required_parts={part for name in aliases for attack in attacks[name]['Attacks'] for part in attack['AttackingParts'] or []}
            selected=list(capsules);existing={c['id'] for c in selected};shared=[]
            for part in sorted(required_parts-existing):
                require(part in body_capsules,'Original companion attack part has no source capsule: '+part)
                capsule=body_capsules[part]
                for endpoint in ('base','tip'):
                    bone=capsule[endpoint]['bone'];source_id=next(i for i,n in body['bones'].items() if n==bone)
                    require(bone_data['bones'].get(source_id)==bone,'Shared body capsule source ID differs in companion rig')
                selected.append(capsule);shared.append(part)
            shapes=sample(document,binary,motion,selected)
            records.append(dict(sourceModel=definition['sourceModel'],roles=motion['roles'],clip=motion['clip'],
                frames=motion['frames'],sourceSHA256=motion['sourceSHA256'],sourceBoneConfigurationSHA256=source_bones['sha256'],
                sharedBodyConfigurationSHA256=body_digest if shared else None,sharedSourceBodyParts=shared,
                tracks=dict(samplesPerSourceFrame=2,root=motion['root'],groundLift=motion['groundLift'],
                    collisionEdges=[c for c in shapes if 'side' in c],hurtCapsules=[c for c in shapes if 'defense' in c])))
    result=dict(version=1,profileID='sun_triad',characterSHA256=manifest['characterSHA256'],
        sourceManifestSHA256=hashlib.sha256((args.spirits/'SF3_H17_Summons.json').read_bytes()).hexdigest(),
        coordinateBasis='Same right-facing actor basis and meter units as the host weapon tracks; horizontal root applied separately.',
        sourceDeclaredCapsulesOnly=True,sharedBodyPartsRequireOriginalAttackSetting=True,motions=records)
    path=output/'SF3_H17_Summon_Tracks.json'
    write_private(path,json.dumps(result,separators=(',',':'),allow_nan=False).encode())
    print(json.dumps(dict(file=str(path),bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        motions=len(records),roles=sum(len(r['roles']) for r in records),
        capsuleTracks=sum(len(r['tracks']['collisionEdges'])+len(r['tracks']['hurtCapsules']) for r in records))))


if __name__=='__main__':main()
