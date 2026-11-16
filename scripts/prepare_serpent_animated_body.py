#!/usr/bin/env python3
"""Bind original D13/Shuangou actor motions to Liu's verified equipment rig.

Every motion resolves by its full original resource path and original object
identity. Projectile and summoned-model animations are excluded from the body.
Source frame crops, interval records, raw arrays and half-frame FK are retained.
This produces a private animation candidate, not an activated release.
"""
from __future__ import annotations
import argparse,base64,copy,json
from pathlib import Path
import xml.etree.ElementTree as ET
import numpy as np

from build_erlang_source_assets import checked,encoded,local_source,record,sha,write_new
from build_serpent_source_geometry import ID,BONES,load_bones
from erlang_source_profile import source_window,source_end_event_tick
from prepare_erlang_animated_body import verify_geometry_prefix
from sun_triad_assets import (RIGHT,Writer,accessor_read,capsule_point,decode,glb_read,matrix,
    pose_world,private_output,require,world_poses)
from sun_triad_source_bones import capsule_binding,merge_bone_ids

STATIC_SHA='b9d2b7a9696dc5a500bc3d51678e2133c80075d077d82d5b218a3cd4584e26c1'
STATIC_RECEIPT_SHA='84bf812a3802978f90d9224add871fb5435478e72a75420be5935b31f4a9dd03'
NAMED_SHA='612b85ed595e4a29ab686c00370d0c4bd573d6aaaa62384c769a4abb1f2cf09a'
NAMED_RECEIPT_SHA='d933ccd2baaa6b030ccfe67fb2f90c8b9798375d3af7d0944b5225b8c4b67d1f'
RESOURCE='Liu_KingOfSerpents_D13_Animated_Source'
PROFILE='SF3_Serpent_Animation_Source_Profile.json'
DYNASTY='settings_sets_dynasty.bytes'
SHUANGOU='settings_style_shuangou.bytes'
MOVES='moves_settings.bytes'
KICKS='settings_style_kicks.bytes'
SELECTED={
    DYNASTY:(52,53,54,55,56,63,67,70),
    SHUANGOU:tuple(i for i in range(31) if i!=21),
    MOVES:(31,46,47,59,66),
    'settings_blocks.bytes':(15,),
    'settings_hits.bytes':(19,48),
    KICKS:(1,4,6,9,13,16,61,67),
}
ROLE_KEYS={
    'idle':(SHUANGOU,23),'enter':(DYNASTY,52),'walkForward':(MOVES,46),'walkBackward':(MOVES,47),
    'guard':('settings_blocks.bytes',15),'crouch':(MOVES,59),'jump':(MOVES,31),
    'hit':('settings_hits.bytes',19),'knockdown':('settings_hits.bytes',48),'getUp':(MOVES,66),
    'victory':(SHUANGOU,24),'victoryIdle':(SHUANGOU,25),
    'weapon1':(SHUANGOU,0),'weapon2':(SHUANGOU,1),'weapon3':(SHUANGOU,2),
    'weapon4':(SHUANGOU,3),'weapon5':(SHUANGOU,4),'heavy':(SHUANGOU,8),
    'weaponForward':(SHUANGOU,9),'weaponForward2':(SHUANGOU,10),
    'weaponForward3':(SHUANGOU,11),'weaponForward4':(SHUANGOU,12),
    'weaponUp':(SHUANGOU,7),'weaponDown':(SHUANGOU,5),'weaponDown2':(SHUANGOU,6),'weaponBack':(SHUANGOU,19),
    'kick':(KICKS,1),'kick2':(KICKS,4),'kickForward':(KICKS,16),'kickUp':(KICKS,9),
    'kickDown':(KICKS,13),'kickBack':(KICKS,6),'kickJump':(KICKS,67),'kickJumpForward':(KICKS,61),
    'serpentBirth':(DYNASTY,52),'serpentRound':(DYNASTY,53),'serpentIdle':(DYNASTY,54),
    'serpentPoison':(DYNASTY,55),'serpentHelmet':(DYNASTY,56),'serpentArmor':(DYNASTY,63),
    'serpentBottle':(DYNASTY,67),'serpentIntoxication':(DYNASTY,70),
    'shadow':(DYNASTY,55),'ranged':(DYNASTY,67),
    'shuangouShadow':(SHUANGOU,27),'shuangouShadowPassive':(SHUANGOU,28),
}
POINTS={'handL':'hand_l','handR':'hand_r','footL':'foot_l','footR':'foot_r',
        'toeL':'toe_l','toeR':'toe_r','pelvis':'pelvis','head':'head'}
BOUNDARY=dict(sourceOnly=True,fullMatchProfile=False,runtimeBound=False,
    abilityRulesBound=False,ordinaryThrowsIncluded=False,sourceStunIncluded=False,
    companionModelsBound=False,projectileMotionBound=False,audioBound=False,
    shaderParity=False,nativeRenderingVerified=False,productionActivated=False,testFlightUploaded=False)


def load_named(path):
    document=json.loads(checked(path,NAMED_SHA,2_000_000))
    receipt=json.loads(checked(path.parent/'receipt-private.json',NAMED_RECEIPT_SHA,10_000))
    require(document['schema']=='original-d13-named-animation-source-v1'
            and document['originalValuesAndTypesPreserved'] and not document['defaultsApplied']
            and len(document['records'])==454 and receipt['exactRoundTripVerifiedRecords']==454,
            'Original named source contract differs')
    sources={r['entry']:r['sha256'] for r in receipt['sources']}
    records={}
    for row in document['records']:
        key=(row['sourceEntry'],row['sourceRecordIndex'])
        require(key not in records and row['sourceSHA256']==sources[key[0]],'Named source identity differs')
        records[key]=row
    selected=[records[(entry,index)] for entry,indices in SELECTED.items() for index in indices]
    require(len(selected)==54,'Selected actor record inventory differs')
    require(all(r['configuration']['Mirrored'] is None for r in selected),
            'A mirrored source alias requires its own explicit conversion')
    return selected


def resolve_original(record_,motions,load):
    path=Path(record_['configuration']['FileName'])
    require(path.suffix=='.bin' and '..' not in path.parts,'Unexpected original animation path')
    suffix='/'+str(path.with_suffix('.bytes')).lower()
    candidates=[r for r in motions if r['name']==path.stem]
    found=[]
    for row in candidates:
        e=load(row['bundle'])
        matched=[p for name,p in e.container.items() if name.lower().endswith(suffix)
                 and p.m_PathID==row['path_id']]
        if len(matched)==1:found.append((row,matched[0]))
    require(len(found)==1,'Full original motion path missing or ambiguous: '+str(path))
    info,pointer=found[0];value=pointer.read()
    require(value.m_Name==path.stem,'Source TextAsset name differs')
    raw=value.m_Script.encode('utf8','surrogateescape') if isinstance(value.m_Script,str) else bytes(value.m_Script)
    require(len(raw)==info['bytes'] and sha(raw)==info['sha256'],'Source motion identity differs')
    return info,raw


def append_motion(writer,names,ids,configs,info,raw,record_,export_name):
    require(sha(raw)==info['sha256'] and len(raw)==info['bytes'],'Motion bytes differ')
    arrays=decode(raw);motion=arrays[0];raw_frames=motion['frame_count']
    require(len(arrays)==2 and raw_frames==info['frames'],'Original motion array layout differs')
    require(set(map(int,motion['bone_ids']))<=set(ids)
            and set(configs['base']['bones'])<=set(map(int,motion['bone_ids'])),
            'Body motion has unbound tracks or is actually a projectile/model')
    first,last,stride=source_window(record_['configuration'],raw_frames)
    frames=last-first+1;require(frames>=2,'No unreviewed static source pose')
    columns={ids[int(key)]:j for j,key in enumerate(motion['bone_ids'])}
    g=writer.g;world0,rest,parents=world_poses(g['nodes'])
    basis=RIGHT[:3,:3] @ world0[parents[names['pelvis']]][:3,:3]
    animation=dict(name=export_name,channels=[],samplers=[],extras=dict(
        sourceSHA256=info['sha256'],sourceRawFrames=raw_frames,sourceFirstIndex=first,
        sourceLastIndex=last,sourceFrameStride=stride,simulationHz=60,exportFramesPerSecond=30,
        sourceAnimation=record_['configuration']['Animation'],sourceOnly=True))
    times=writer.acc(np.arange(frames)/30,'SCALAR');positions={};rotations={}
    for bone,col in columns.items():
        p=motion['positions'][first:last+1,col].astype(float)*[.01,.01,-.01]
        if bone=='pelvis':p[:,[0,2]]=0
        q=motion['rotations'][first:last+1,col].astype(float)*[-1,-1,1,1]
        q/=np.linalg.norm(q,axis=1)[:,None]
        for i in range(1,len(q)):
            if q[i-1]@q[i]<0:q[i]*=-1
        positions[bone]=p.astype(np.float32).astype(float);rotations[bone]=q.astype(np.float32).astype(float)
        for kind,values,width in [('translation',p,'VEC3'),('rotation',q,'VEC4')]:
            sampler=len(animation['samplers'])
            animation['samplers'].append(dict(input=times,output=writer.acc(values,width),interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=sampler,target=dict(node=names[bone],path=kind)))
    g['animations'].append(animation)
    roots=motion['positions'][first:last+1,columns['pelvis']].astype(float)*[.01,.01,-.01]
    delta=(roots-roots[0]) @ basis.T
    attacks=configs['weapon']['capsules'];hurts=configs['fullBody']['capsules']
    masses=sorted((names[n],w) for n,w in configs['base']['masses'].items() if w>0)
    require(len(attacks)==4 and len(hurts)==15 and len(masses)==58
            and abs(sum(w for _,w in masses)-67.2)<1e-8,'Original collision/mass inventory differs')
    tracks={key:[] for key in ('root',*POINTS,'weaponBaseL','weaponTipL','weaponBaseR','weaponTipR','centerOfMass','groundLift')}
    edges=[dict(**capsule_binding(c,'attack'),base=[],tip=[]) for c in attacks]
    shapes=[dict(**capsule_binding(c,'hurt'),base=[],tip=[]) for c in hurts]
    markers=[]
    for side in ('l','r'):
        foot,toe=names['foot_'+side],names['toe_'+side];a,b=world0[foot][:3,3],world0[toe][:3,3]
        for x in (min(a[0],b[0])-.055,max(a[0],b[0])+.055):
            for z in (min(a[2],b[2])-.055,max(a[2],b[2])+.055):
                markers.append((foot,np.linalg.inv(world0[foot])@[x,-.02,z,1]))
    for sample in range(2*frames-1):
        a=sample//2;b=min(a+1,frames-1);f=(sample%2)/2;local=[m.copy() for m in rest]
        for bone in columns:
            p=positions[bone][a]*(1-f)+positions[bone][b]*f
            q=rotations[bone][a]*(1-f)+rotations[bone][b]*f
            local[names[bone]]=matrix(p,q,g['nodes'][names[bone]].get('scale',[1,1,1]))
        world=pose_world(local,parents);tracks['root'].append(delta[a]*(1-f)+delta[b]*f)
        for label,bone in POINTS.items():tracks[label].append((RIGHT @ world[names[bone]][:,3])[:3])
        acc=np.zeros(3,dtype=np.float32);total=np.float32(0)
        for node,mass in masses:
            w=np.float32(mass);point=np.asarray((RIGHT @ world[node][:,3])[:3],dtype=np.float32)
            acc=np.asarray(acc+point*w,dtype=np.float32);total=np.float32(total+w)
        tracks['centerOfMass'].append(acc/total)
        for capsule,shape in zip(attacks+hurts,edges+shapes):
            for end in ('base','tip'):
                point=capsule_point(capsule[end],world,names);shape[end].append(point)
                if capsule['id'].startswith('Shuangou_Attacking_Edge_'):
                    tracks[('weaponBase' if end=='base' else 'weaponTip')+capsule['id'][-1].upper()].append(point)
        low=min((world[foot]@point)[1] for foot,point in markers)
        tracks['groundLift'].append(float(max(0.,-.035-low)))
    tracks={k:np.round(v,7).tolist() for k,v in tracks.items()}
    for shape in edges+shapes:
        for end in ('base','tip'):shape[end]=np.round(shape[end],7).tolist()
    tracks.update(samplesPerSourceFrame=2,collisionEdges=edges,hurtCapsules=shapes)
    require(max(tracks['groundLift'])<=2,'Pose exceeds application floor-lift bound')
    return dict(name=export_name,frames=frames,playbackTicks=(frames-1)*stride,
        sourceEndEventTick=source_end_event_tick(record_['configuration'],raw_frames),
        sourceUncroppedFrames=raw_frames,sourceFirstIndex=first,sourceLastIndex=last,
        sourceConfiguration=record_,sha256=info['sha256'],bundle=info['bundle'],sourcePathID=str(info['path_id']),
        sourceArrayCount=2,sourceBoneIDs=list(map(int,motion['bone_ids'])),
        sourceBytesBase64=base64.b64encode(raw).decode(),tracks=tracks)


def verify_clip(g,binary,clip,names,ids,configs):
    """Read back actual GLB channels against original arrays and profile FK."""
    animation=next(a for a in g['animations'] if a['name']==clip['name'])
    raw=base64.b64decode(clip['sourceBytesBase64'],validate=True)
    require(sha(raw)==clip['sha256'],'Original retained motion differs')
    motion=decode(raw)[0];first,last,stride=source_window(clip['sourceConfiguration']['configuration'],motion['frame_count'])
    frames=last-first+1;columns={names[ids[int(i)]]:j for j,i in enumerate(motion['bone_ids'])}
    curves={};maximum=0.;compared=0
    def compare(a,b,tolerance=2e-6):
        nonlocal maximum,compared
        error=float(np.max(abs(np.asarray(a)-np.asarray(b))))
        require(np.isfinite(error) and error<tolerance,'Written GLB differs from source/track')
        maximum=max(maximum,error);compared+=1
    for channel in animation['channels']:
        node=channel['target']['node'];kind=channel['target']['path'];sampler=animation['samplers'][channel['sampler']]
        values=accessor_read(g,binary,sampler['output']).astype(float);times=accessor_read(g,binary,sampler['input'])
        require(node in columns and kind in ('translation','rotation') and (node,kind) not in curves
                and len(values)==len(times)==frames and sampler['interpolation']=='LINEAR','Invalid source animation channels')
        compare(times,np.arange(frames)/30)
        col=columns[node]
        if kind=='translation':
            expected=motion['positions'][first:last+1,col].astype(float)*[.01,.01,-.01]
            if g['nodes'][node]['name']=='pelvis':expected[:,[0,2]]=0
            compare(values,expected)
        else:
            expected=motion['rotations'][first:last+1,col].astype(float)*[-1,-1,1,1]
            expected/=np.linalg.norm(expected,axis=1)[:,None]
            compare(np.abs((expected*values).sum(axis=1)),np.ones(frames))
        curves[node,kind]=values
    require(set(curves)=={(i,k) for i in columns for k in ('translation','rotation')},'Missing mapped body channel')
    world0,rest,parents=world_poses(g['nodes']);tracks=clip['tracks'];samples=2*frames-1
    require(clip['frames']==frames and clip['playbackTicks']==(last-first)*stride
            and clip['sourceEndEventTick']==source_end_event_tick(clip['sourceConfiguration']['configuration'],motion['frame_count']),
            'Source clock differs')
    masses=sorted((names[n],w) for n,w in configs['base']['masses'].items() if w>0)
    shapes=tracks['collisionEdges']+tracks['hurtCapsules'];caps=configs['weapon']['capsules']+configs['fullBody']['capsules']
    require(len(shapes)==len(caps)==19,'Source capsule inventory differs')
    for key in (*POINTS,'root','centerOfMass','groundLift','weaponBaseL','weaponTipL','weaponBaseR','weaponTipR'):
        require(len(tracks[key])==samples,'Source sample count differs')
    raw_roots=motion['positions'][first:last+1,columns[names['pelvis']]].astype(float)*[.01,.01,-.01]
    basis=RIGHT[:3,:3] @ world0[parents[names['pelvis']]][:3,:3];delta=(raw_roots-raw_roots[0]) @ basis.T
    for sample in range(samples):
        a=sample//2;b=min(a+1,frames-1);f=(sample%2)/2;local=[m.copy() for m in rest]
        for node in columns:
            p=curves[node,'translation'][a]*(1-f)+curves[node,'translation'][b]*f
            q=curves[node,'rotation'][a]*(1-f)+curves[node,'rotation'][b]*f
            local[node]=matrix(p,q,g['nodes'][node].get('scale',[1,1,1]))
        world=pose_world(local,parents);compare(tracks['root'][sample],delta[a]*(1-f)+delta[b]*f)
        for label,bone in POINTS.items():compare(tracks[label][sample],(RIGHT @ world[names[bone]][:,3])[:3])
        acc=np.zeros(3,dtype=np.float32);total=np.float32(0)
        for node,mass in masses:
            w=np.float32(mass);acc=np.asarray(acc+np.asarray((RIGHT @ world[node][:,3])[:3],np.float32)*w,np.float32);total=np.float32(total+w)
        compare(tracks['centerOfMass'][sample],acc/total)
        for capsule,shape in zip(caps,shapes):
            require(capsule['id']==shape['id'],'Capsule source identity differs')
            for end in ('base','tip'):
                point=capsule_point(capsule[end],world,names);compare(shape[end][sample],point)
                if capsule['id'].startswith('Shuangou_Attacking_Edge_'):
                    compare(tracks[('weaponBase' if end=='base' else 'weaponTip')+capsule['id'][-1].upper()][sample],point)
    return dict(clip=clip['name'],samples=samples,comparedValues=compared,maximumErrorMeters=maximum)


def build(args):
    require(not args.output.exists(),'Use a fresh private output')
    selected=load_named(args.settings)
    raw=checked(args.geometry,STATIC_SHA,8_000_000)
    receipt=json.loads(checked(args.geometry_receipt,STATIC_RECEIPT_SHA,40_000))
    require(receipt['character']==dict(file=args.geometry.name,bytes=len(raw),sha256=STATIC_SHA),
            'Geometry receipt does not bind model')
    static,binary=glb_read(args.geometry)
    require(len(static['nodes'])==90 and len(static['skins'][0]['joints'])==80 and not static['animations'],
            'Static source rig differs')
    writer=Writer();writer.g=copy.deepcopy(static);writer.b=bytearray(binary[:static['buffers'][0]['byteLength']])
    original_binary=bytes(writer.b);bindings=receipt['originalBoneBindings'];names={r['name']:r['targetNode'] for r in bindings}
    configs=load_bones(args.source_configs,args.shared_bones)
    configs.pop('ranged')
    base_raw=checked(args.shared_bones/BONES['base'][0],BONES['base'][1],10_000)
    configs['base']['masses']={b.get('Name'):float(b.get('Mass','0')) for b in ET.fromstring(base_raw).findall('./Bones/Bone')}
    ids={i:n for i,n in merge_bone_ids(*configs.values()).items() if n in names}
    require(ids=={r['sourceID']:r['name'] for r in bindings if r['sourceID'] is not None},'Static/source bone ID map differs')
    bundles,motions,load=local_source(args);pending=[];seen=set();aliases={}
    for r in selected:
        info,source=resolve_original(r,motions,load);name=info['name']
        if name in seen:name+='__'+r['configuration']['Animation'].lower()
        require(name not in seen,'Duplicate source export alias');seen.add(name)
        aliases[r['sourceEntry'],r['sourceRecordIndex']]=name;pending.append((r,info,source,name))
    clips=[]
    for r,info,source,name in pending:
        clip=append_motion(writer,names,ids,configs,info,source,r,name);clips.append(clip)
        print('SERPENT_MOTION',name,clip['frames'],flush=True)
    roles={role:aliases[key] for role,key in ROLE_KEYS.items()}
    writer.g['asset']['generator']='Original D13/Shuangou animated Liu candidate'
    writer.g['extras'].update(sourceNamedSHA256=NAMED_SHA,sourceAnimationCount=len(clips),**BOUNDARY)
    out=private_output(args.output);model=out/(RESOURCE+'.glb');identity=writer.save(model);model.chmod(0o600)
    actual,binary=glb_read(model);verify_geometry_prefix(static,original_binary,actual,binary)
    readback=[verify_clip(actual,binary,c,names,ids,configs) for c in clips]
    profile=dict(schema='serpent-recovered-body-animation-profile-v1',id=ID,hero='liu',faction='Dynasty',
        resourceName=RESOURCE,bodyID='arm__agl_41',helmetID='helm__agl_41',weaponID='wpn__shuangou_01_04',
        rangedID='rng__bottle_01_02',activeWeaponSides=['left','right'],roles=roles,clips=clips,
        sourceSkinNodeCount=80,sourceBoneBindings=bindings,comboLinks=[],recoveryBoundary=BOUNDARY,**identity)
    write_new(out/PROFILE,encoded(profile))
    report=dict(schema='serpent-recovered-body-animation-receipt-v1',character=record(model),profile=record(out/PROFILE),
        sourceGeometry=record(args.geometry),sourceGeometryReceipt=record(args.geometry_receipt),sourceNamed=record(args.settings),
        motionCount=len(clips),humanD13Aliases=8,sourceOnlyModelAliasesExcluded=11,
        unchangedGeometryMaterialsSkinsAndPersonalPortrait=True,unchangedStaticBinaryBytes=len(original_binary),
        sourceBundles=[{k:bundles[n][k] for k in ('file','bytes','sha256')} for n in sorted({i['bundle'] for _,i,_,_ in pending})],
        readback=readback,comparedValues=sum(r['comparedValues'] for r in readback),
        maximumErrorMeters=max(r['maximumErrorMeters'] for r in readback),boundary=BOUNDARY)
    write_new(out/'animated-body-receipt-private.json',encoded(report))
    return {k:report[k] for k in ('character','profile','motionCount','comparedValues','maximumErrorMeters','boundary')}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('geometry','geometry-receipt','settings','source-archive','source-bundles','source-configs','shared-bones','output'):
        p.add_argument('--'+key,type=Path,required=True)
    print(json.dumps(build(p.parse_args()),indent=2))


if __name__=='__main__':main()
