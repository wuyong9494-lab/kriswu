#!/usr/bin/env python3
"""Append the exact record-133 static pose: one frame, one FK sample, tick zero."""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path
import warnings
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from build_erlang_source_assets import CONFIGS, SPEAR, append_motion, checked, encoded, record, sha, write_new
from erlang_source_profile import SETTINGS_SHA
from prepare_fighter_target_motions import ARCHIVE_SHA256
from sun_triad_assets import Writer, glb_read, private_output, require
from sun_triad_source_bones import parse_bones_data

MOTION_SHA='72da7978875aa9b288933add7c045cdc417938a6f9887a55d0e0efddcf7123e1'
ROLE='erlangTransformOut'


def append(args):
    profile_raw=checked(args.profile,args.profile_sha256,48_000_000);profile=json.loads(profile_raw)
    require(profile['id']=='wuyong_erlang' and len(profile['clips'])==55 and ROLE not in profile['roles'],
            'Expected 55-clip Wu candidate without TransformOut')
    model=args.profile.parent/(profile['resourceName']+'.glb')
    checked(model,profile['sha256'],48_000_000);g,b=glb_read(model)
    before=copy.deepcopy(g);writer=Writer();writer.g=g;writer.b=bytearray(b[:g['buffers'][0]['byteLength']])
    old_binary=bytes(writer.b)
    if args.head_profile:
        require(args.head_profile_sha256 is not None,'Head landmarks need their input pin')
        head=json.loads(checked(args.head_profile,args.head_profile_sha256,48_000_000))
        require(head['id']==profile['id'] and head['sourceBoneBindings']==profile['sourceBoneBindings'],
                'Head landmarks use another source rig')
        by_name={c['name']:c for c in head['clips']}
        require(set(by_name)=={c['name'] for c in profile['clips']},'Head landmark clip inventory differs')
        for clip in profile['clips']:
            ref=by_name[clip['name']]
            require({k:v for k,v in clip.items() if k!='tracks'}=={k:v for k,v in ref.items() if k!='tracks'} and
                    {k:v for k,v in clip['tracks'].items() if k!='head'}=={k:v for k,v in ref['tracks'].items() if k!='head'},
                    'Cannot transfer head landmarks between different source motions')
            require(len(ref['tracks']['head'])==2*clip['frames']-1,'Source head sample count differs')
            clip['tracks']['head']=copy.deepcopy(ref['tracks']['head'])
    require(all('head' in c['tracks'] for c in profile['clips']),'Existing clips require verified source head landmarks')
    archive=ZipFile(io.BytesIO(checked(args.source_archive,ARCHIVE_SHA256,256*1024*1024)))
    motions=json.loads(archive.read('research/motion_catalog.json'))['motions']
    matches=[m for m in motions if m['name']=='staff_idle' and m['bundle']==SPEAR]
    require(len(matches)==1 and matches[0]['sha256']==MOTION_SHA,'Exact Imperial source pose is missing')
    info=matches[0]
    require(info['path_id']==8322131337768780943 and info['frames']==62 and info['bytes']==86578,
            'Original source object identity differs')
    bundle=archive.read('bundles/'+SPEAR)
    require(sha(bundle)=='023838c04e05592b3889d174e6d8c4814bd39856c73c7539c2abb1bc64e765da',
            'Imperial source bundle differs')
    import UnityPy
    require(UnityPy.__version__=='1.25.4','Use reviewed UnityPy')
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1'
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        env=UnityPy.load(bundle)
        found=[o for o in env.objects if o.path_id==info['path_id'] and o.type.name=='TextAsset']
        require(len(found)==1,'Original static pose TextAsset is missing')
        data=found[0].read().m_Script
    raw=data.encode('utf8','surrogateescape') if isinstance(data,str) else bytes(data)
    require(len(raw)==info['bytes'] and sha(raw)==MOTION_SHA,'Original source pose bytes differ')
    settings=json.loads(checked(args.settings,SETTINGS_SHA,4_000_000))
    records=[r for r in settings['records'] if r['sourceEntry']=='settings_sets_dynasty.bytes'
             and r['sourceRecordIndex']==133]
    require(len(records)==1,'Exact TransformOut configuration is missing');configuration=records[0]
    c=configuration['configuration']
    require(c['Animation']=='D15_Avatara_Transform_Out' and c['FileName']=='w_imperial_spear/staff_idle.bin'
            and c['FirstFrame'] is None and c['EndFrame']==1 and c['SelfEndFrame']==0
            and c['BlendingFrames']==0 and c['MidFrames'] is None,'Static source clock differs')
    configs={}
    for kind,(name,pin) in CONFIGS.items():
        folder=args.source_configs if kind=='weapon' else args.shared_bones
        config_raw=checked(folder/name,pin,1_000_000);configs[kind]=parse_bones_data(config_raw)
        if kind=='base':
            configs[kind]['masses']={n.get('Name'):float(n.get('Mass','0'))
                for n in ET.fromstring(config_raw).findall('./Bones/Bone')}
    names={r['name']:r['targetNode'] for r in profile['sourceBoneBindings']}
    ids={r['sourceID']:r['name'] for r in profile['sourceBoneBindings'] if r['sourceID'] is not None}
    clip=append_motion(writer,names,ids,configs,info,raw,configuration)
    require(clip['frames']==clip['sourceWindowFrames']==1 and clip['playbackTicks']==clip['sourceEndEventTick']==0,
            'Static pose invented a frame or time')
    for field in ('root','head','pelvis','centerOfMass','toeL','toeR'):
        require(len(clip['tracks'][field])==1,'Static source landmark was duplicated')
    require(len(clip['tracks']['hurtCapsules'])==15,'Original static hurt capsules are incomplete')
    profile['clips'].append(clip);profile['roles'][ROLE]=clip['name']
    require(g['animations'][:-1]==before['animations'] and len(g['animations'])==56,
            'Static append changed an existing source animation')
    require(bytes(writer.b[:len(old_binary)])==old_binary,'Static append changed original media bytes')
    for key in ('nodes','meshes','materials','skins','textures','images','samplers','scenes'):
        require(g[key]==before[key],'Static append changed '+key)
    require(not args.output.exists(),'Refuse to replace a candidate');output=private_output(args.output)
    profile.update(writer.save(output/model.name));write_new(output/'SF3_Erlang_Profile.json',encoded(profile))
    receipt=dict(sourceProfile=record(args.profile),headLandmarkProfile=None if not args.head_profile else record(args.head_profile),
        character=record(output/model.name),profile=record(output/'SF3_Erlang_Profile.json'),
        role=ROLE,clip=clip['name'],originalMotionSHA256=MOTION_SHA,sourceRecordIndex=133,
        originalFrames=62,sourceFirstIndex=0,sourceLastIndex=0,exportedFrames=1,FKsamples=1,
        playbackTicks=0,sourceEndEventTick=0,headSamples=sum(len(c['tracks']['head']) for c in profile['clips']),
        unchangedSourceAnimations=55,decodedOnlyNewSourceMotion=True,duplicatedStaticPoseSamples=False)
    write_new(output/'erlang-transform-out-private.json',encoded(receipt));return receipt


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('profile','source-archive','settings','source-configs','shared-bones','output'):
        p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--profile-sha256',required=True)
    p.add_argument('--head-profile',type=Path);p.add_argument('--head-profile-sha256')
    print(json.dumps(append(p.parse_args())))


if __name__=='__main__':main()
