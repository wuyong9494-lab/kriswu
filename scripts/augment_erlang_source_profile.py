#!/usr/bin/env python3
"""Add source toe FK and final bindings without changing or decoding the GLB."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import numpy as np

from build_erlang_source_assets import checked, write_new, encoded, record, sha
from erlang_source_profile import SETTINGS_SHA, combat_rules, source_end_event_tick
from sun_triad_assets import RIGHT, accessor_read, glb_read, matrix, pose_world, private_output, require, world_poses


def landmark_tracks(profile, model, binary, fields):
    names = {row['name']:row['targetNode'] for row in profile['sourceBoneBindings']}
    require(len(names) == len(profile['sourceBoneBindings']) and
            all(model['nodes'][index]['name'] == name for name,index in names.items()),
            'Actor source bone identity differs')
    require(all(bone in names for bone in fields.values()), 'Original landmark bones are required')
    _, rest, parents = world_poses(model['nodes'])
    animations = {a['name']:a for a in model['animations']}
    require(len(animations) == len(model['animations']), 'Duplicate original animation')
    count = 0
    for clip in profile['clips']:
        animation = animations[clip['name']]
        require(animation['extras']['sourceSHA256'] == clip['sha256'], 'Original motion identity differs')
        rate=animation['extras'].get('exportFramesPerSecond',30)
        require(rate==30 or rate==60 and animation['extras'].get('sourceMirrorApplied') is True,
                'Unbound source export grid')
        export_frames=clip['frames'] if rate==30 else 2*clip['frames']-1
        channels = {}
        for channel in animation['channels']:
            node, kind = channel['target']['node'], channel['target']['path']
            require(kind in ('translation','rotation','scale') and (node,kind) not in channels,
                    'Duplicate or unsupported animation channel')
            sampler = animation['samplers'][channel['sampler']]
            require(sampler.get('interpolation','LINEAR') == 'LINEAR', 'Unbound original interpolation')
            times = accessor_read(model,binary,sampler['input'])
            values = accessor_read(model,binary,sampler['output'])
            require(len(times) == len(values) == export_frames and
                    np.max(abs(times-np.arange(export_frames)/rate)) < .0001, 'Exported source grid differs')
            channels[node,kind] = values.astype(float)
        result = {field:[] for field in fields}
        for sample in range(2*clip['frames']-1):
            if rate==60:first=last=sample;weight=0
            else:
                first, half = divmod(sample,2); last=min(clip['frames']-1,first+1); weight=half/2
            local = [m.copy() for m in rest]
            for node in {key[0] for key in channels}:
                transform = {}
                for kind,default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]:
                    values = channels.get((node,kind))
                    if values is None:
                        transform[kind] = model['nodes'][node].get(kind,default)
                    else:
                        a,b=values[first],values[last]
                        if kind=='rotation' and a@b < 0: b=-b
                        transform[kind] = a*(1-weight)+b*weight
                local[node]=matrix(transform['translation'],transform['rotation'],transform['scale'])
            world=pose_world(local,parents)
            for label,bone in fields.items():
                result[label].append((RIGHT@world[names[bone]][:,3])[:3])
        for label,values in result.items():
            require(np.isfinite(values).all(), 'Invalid original toe pose')
            clip['tracks'][label]=np.round(values,7).tolist()
        count += len(next(iter(result.values())))
    return count


def augment(args):
    raw=checked(args.profile,args.profile_sha256,40_000_000)
    profile=json.loads(raw)
    require(profile['id']==profile['hero']=='wuyong_erlang' and profile['resourceName']=='WuYong_Erlang_D15',
            'Unexpected character profile')
    source=args.profile.parent/(profile['resourceName']+'.glb')
    model_raw=checked(source,profile['sha256'],40_000_000)
    require(len(model_raw)==profile['bytes'],'Character byte count differs')
    g,b=glb_read(source)
    original=copy.deepcopy(profile)
    fields={'head':'head'} if args.head_only else {'toeL':'toe_l','toeR':'toe_r'}
    count=landmark_tracks(profile,g,b,fields)
    for old,new in zip(original['clips'],profile['clips']):
        require({k:v for k,v in new['tracks'].items() if k not in fields}==
                {k:v for k,v in old['tracks'].items() if k not in fields},
                'Landmark binding modified a successful existing track')
    attacks=[]
    if not args.head_only:
        require(args.settings is not None,'Source settings required for toe/profile binding')
        settings=json.loads(checked(args.settings,SETTINGS_SHA,4_000_000))
        profile['combatRules'],attacks=combat_rules(profile,settings)
        for clip in profile['clips']:
            if clip.get('sourceConfiguration'):
                clip['sourceEndEventTick']=source_end_event_tick(
                    clip['sourceConfiguration']['configuration'],clip['sourceUncroppedFrames'])
    if args.erlang_rules:
        rule_raw=args.erlang_rules.read_bytes();require(0<len(rule_raw)<=4_000_000,'D15 rules exceed bound')
        rules=json.loads(rule_raw)
        require(rules.get('sourceVersion')=='1.46.0.16.16733-prod','D15 source version differs')
        profile['erlangRules']=rules
    require(not args.output.exists(),'Refuse to replace a candidate')
    output=private_output(args.output)
    write_new(output/source.name,model_raw)
    write_new(output/'SF3_Erlang_Profile.json',encoded(profile))
    receipt=dict(sourceProfileSHA256=sha(raw),character=record(output/source.name),
        profile=record(output/'SF3_Erlang_Profile.json'),clips=len(profile['clips']),landmarkFields=list(fields),samplesPerField=count,
        unchangedExistingTrackValues=True,unchangedGLB=True,
        landmarkProjection='Same original rig, local quaternion half frames, FK, RIGHT/metre basis as feet and pelvis; already baked 60 Hz mirror keys are sampled directly.',
        originalPhysicalAttackBindings=attacks)
    write_new(output/'erlang-profile-augmentation-private.json',encoded(receipt))
    return {k:v for k,v in receipt.items() if k!='originalPhysicalAttackBindings'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('profile','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--settings',type=Path)
    p.add_argument('--head-only',action='store_true')
    p.add_argument('--profile-sha256',required=True)
    p.add_argument('--erlang-rules',type=Path)
    print(json.dumps(augment(p.parse_args())))


if __name__=='__main__':main()
