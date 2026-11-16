#!/usr/bin/env python3
"""Recover the exact D13 virtual cloud rig and its original animation.

The reviewed ranged bundle contains the cloud TextAsset even though the old
motion export catalog omitted it. No damage volume is inferred from a mesh:
the original cloud ModelObject deliberately has no meshes. Full particle and
combat presentation are separate consumers of these authenticated transforms.
"""
import argparse
import json
from pathlib import Path
import warnings
import xml.etree.ElementTree as ET

import numpy as np

from check_serpent_action_source import NAMED_SHA, checked_json
from erlang_source_profile import source_end_event_tick, source_window
from sun_triad_assets import C, CI, Writer, accessor_read, decode, glb_read, matrix, pose_world, private_output, quaternion, require, world_poses, write_private
from sun_triad_source_bones import parse_bones_data
from sun_triad_spirits import source_rig
from prepare_erlang_model_tracks import checked, sha

MODEL_BUNDLE_SHA = '21b5e9688a3e68ab10b2cba4c43e1aed766988c44d6cb2379ea206a9eb7a93f3'
MOTION_BUNDLE_SHA = '7946927e5656d327675fb7bd6b60a60032ad54c1b365d20c75fe000b20f82001'
MOTION_SHA = '474b609e89df1a9756a6aa573bb6bc98590329fae763073e997cb2ae0a57da95'
BONES_SHA = '06347f1c97846e9678d2c457f28161628ea767cbe4077e45598086f910c1075c'
CONFIG_SHA = '8154f1dbeb983a8264d3366b62a819f253d729f1a5269e10c851ccf11222989a'
ALIAS = 'D13_Poison_Bomb_Cloud_Model_Attack'
FILE = 'SF3_D13_Cloud_Source.glb'
POINTS = ('root','left','right','top','bottom')


def build(args):
    import UnityPy
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed container parser')
    require(not args.output.exists(), 'Use a new private output directory')
    output = private_output(args.output)
    model_raw = checked(args.model_bundle, MODEL_BUNDLE_SHA, 10000)
    motion_bundle = checked(args.motion_bundle, MOTION_BUNDLE_SHA, 600000)
    bones = parse_bones_data(checked(args.bones, BONES_SHA, 1000))
    config = ET.fromstring(checked(args.config, CONFIG_SHA, 1000))
    require(config.find('Meshes') is not None and len(config.find('Meshes')) == 0,
            'The original virtual cloud must not gain a synthetic mesh')
    records = checked_json(args.named, NAMED_SHA)['records']
    record = next(r for r in records if r['sourceRecordIndex'] == 69)
    setting = record['configuration']
    require(setting['Animation'] == ALIAS and setting['Looped'] is True
            and setting['FileName'] == 'ranged/universal/s_rng_agl_cloud_bullet.bin'
            and setting['Align'][3:] == [[200.,0.,0.],['X'],['GrandParent','Nodes','pelvis'],[None,'Nodes','magic_joint_root']]
            and setting['Velocity'] is None, 'Wrong cloud source settings')
    env = UnityPy.load(motion_bundle)
    path = 'assets/gamedata/resources/content/animations/binaries/ranged/universal/s_rng_agl_cloud_bullet.bytes'
    ptr = env.container[path]
    require(ptr.path_id == -7448206328050373201 and ptr.type.name == 'TextAsset', 'Wrong motion object')
    asset = ptr.read(); require(asset.m_Name == 's_rng_agl_cloud_bullet', 'Wrong motion name')
    raw = asset.m_Script.encode('utf8','surrogateescape')
    require(len(raw) == 18182 and sha(raw) == MOTION_SHA, 'Motion bytes differ')
    arrays = decode(raw); motion = arrays[0]
    require(len(arrays) == 2 and all(a['frame_count'] == 151 for a in arrays)
            and list(map(int,motion['bone_ids'])) == [400,401,402,403,404], 'Wrong frame/bone dimensions')
    first,last,stride = source_window(setting,151); end_tick = source_end_event_tick(setting,151)
    require((first,last,stride,end_tick) == (0,150,2,292), 'Source clock differs')
    env = UnityPy.load(model_raw)
    prefab = 'assets/gamedata/resources/content/items/models/shd__shadow_ranged_agile_cloud/m/prefabs/mgc_01.prefab'
    rows = source_rig(env.container[prefab]); names = {r['name']:i for i,r in enumerate(rows)}
    require(len(rows) == 9 and set(bones['bones'].values()) <= names.keys(), 'Incomplete cloud hierarchy')
    writer = Writer(); g = writer.g
    for row in rows:
        local = C @ matrix(row['translation'],row['rotation'],row['scale']) @ CI
        node = dict(name=row['name'],translation=local[:3,3].tolist(),rotation=quaternion(local[:3,:3]).tolist())
        children = [names[r['name']] for r in rows if r['parent'] == row['name']]
        if children: node['children'] = children
        g['nodes'].append(node)
    g['scenes'] = [dict(name='Original virtual poison cloud',nodes=[0])]
    times = writer.acc(np.arange(151)/30,'SCALAR')
    animation = dict(name=ALIAS,channels=[],samplers=[],extras=dict(sourceSHA256=MOTION_SHA,
        sourceFirstIndex=0,sourceLastIndex=150,sourceFrameStride=2,sourceEndEventTick=292,sourceLoopPeriodTicks=293))
    for col,identifier in enumerate(motion['bone_ids']):
        node = names[bones['bones'][int(identifier)]]
        p = motion['positions'][:,col].astype(float)*[.01,.01,-.01]
        q = motion['rotations'][:,col].astype(float)*[-1,-1,1,1];q /= np.linalg.norm(q,axis=1)[:,None]
        for j in range(1,len(q)):
            if q[j-1]@q[j]<0:q[j]*=-1
        for key,data,width in [('translation',p,'VEC3'),('rotation',q,'VEC4')]:
            sampler=len(animation['samplers']);animation['samplers'].append(dict(input=times,output=writer.acc(data,width),interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=sampler,target=dict(node=node,path=key)))
    g['animations'].append(animation)
    # No source render mesh exists; remove empty optional arrays for valid glTF.
    for key in ('meshes','skins','materials','textures','images','samplers'):
        if not g.get(key): g.pop(key,None)
    result=writer.save(output/FILE)
    read_g,binary=glb_read(output/FILE)
    _,rest,parents=world_poses(read_g['nodes'])
    samples=[];errors=[]
    for tick in range(301):
        i,j,w=tick//2,min(150,tick//2+1),(tick%2)*.5
        actual=[v.copy() for v in rest]; expected=[v.copy() for v in rest]; values={}
        for channel in read_g['animations'][0]['channels']:
            sampler=read_g['animations'][0]['samplers'][channel['sampler']]
            data=accessor_read(read_g,binary,sampler['output'])
            a,b=data[i].astype(float),data[j].astype(float)
            if channel['target']['path']=='rotation' and a@b<0:b=-b
            values.setdefault(channel['target']['node'],{})[channel['target']['path']]=a*(1-w)+b*w
        for col,identifier in enumerate(motion['bone_ids']):
            node=names[bones['bones'][int(identifier)]]
            a,b=motion['rotations'][i,col].astype(float),motion['rotations'][j,col].astype(float)
            if a@b<0:b=-b
            p=motion['positions'][i,col].astype(float)*(1-w)+motion['positions'][j,col].astype(float)*w
            expected[node]=C@matrix(p,a*(1-w)+b*w,[1,1,1])@CI
            actual[node]=matrix(values[node]['translation'],values[node]['rotation'],[1,1,1])
        ew,aw=pose_world(expected,parents),pose_world(actual,parents)
        for name in bones['bones'].values():errors.append(float(np.max(np.abs(ew[names[name]]-aw[names[name]]))))
        samples.append({key:(aw[names['magic_joint_'+key]][:3,3]*100).tolist() for key in POINTS})
    require(len(errors)==1505 and max(errors)<2e-5,'Cloud GLB FK differs from original arrays')
    # This is measured original animation behavior, not a fallback frozen pose.
    require(np.all(motion['positions']==motion['positions'][0]) and np.all(motion['rotations']==motion['rotations'][0]),
            'The source cloud pose is no longer constant; review the host contract')
    binding=dict(schema='d13-cloud-motion-binding-v1',modelSHA256=result['sha256'],modelBytes=result['bytes'],
        motionSHA256=MOTION_SHA,bonesSHA256=BONES_SHA,animation=ALIAS,coordinates='source-centimeters-z-converted',
        lastSampleTick=300,loopEndEventTick=292,loopPeriodTicks=293,samples=samples)
    write_private(output/'SF3_D13_Cloud_Motion_Binding.json',json.dumps(binding,separators=(',',':')).encode())
    receipt=dict(schema='d13-cloud-source-recovery-v1',model=result,motionBundleSHA256=MOTION_BUNDLE_SHA,
        modelBundleSHA256=MODEL_BUNDLE_SHA,motionSHA256=MOTION_SHA,bonesSHA256=BONES_SHA,configSHA256=CONFIG_SHA,
        sourceConfiguration=record,sourceMotionObjectPath=path,sourceMotionPathID=-7448206328050373201,
        sourceFrames=151,boneTracks=5,sampledTicks=301,matrixComparisons=len(errors),maximumMatrixError=max(errors),
        allArrayZeroPosesConstant=True,sourceVirtualModelHasNoMeshes=True,particlePresentationBound=False,
        fullFighterRegistration=False)
    write_private(output/'cloud-source-receipt-private.json',json.dumps(receipt,indent=2).encode())
    return {k:v for k,v in receipt.items() if k!='sourceConfiguration'}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('model-bundle','motion-bundle','bones','config','named','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    print(json.dumps(build(parser.parse_args())))
