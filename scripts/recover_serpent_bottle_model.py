#!/usr/bin/env python3
"""Recover the actual D13 equipped bottle mesh/rig and cropped flying motion.

Private source-only resource: no guessed cloud pose, damage contact, shader
parity or production activation. Both original mirrored mesh variants remain
independently selectable scenes. The original motion bytes are preserved.
"""
import argparse
import base64
import json
from pathlib import Path
import warnings
import xml.etree.ElementTree as ET
from zipfile import ZipFile
import zlib

import numpy as np

from build_serpent_source_geometry import BONES, BUNDLES, MODELS, RANGED
from check_serpent_action_source import NAMED_SHA, checked_json
from check_serpent_state_source import documents, trigger
from erlang_source_profile import source_end_event_tick, source_window
from prepare_erlang_model_tracks import BUNDLE_CATALOG_SHA, MOTION_CATALOG_SHA, checked, member, sha
from sun_triad_assets import (C, CI, Writer, accessor_read, decode, glb_read, matrix, pose_world,
    private_output, quaternion, require, skin_slots, world_poses, write_private)
from sun_triad_materials import original_material
from sun_triad_source_bones import parse_bones_data
from sun_triad_spirits import source_rig

MOTION_SHA = '62d469b0b69db2393d1468d454b734e97b17c1ed19672adde8e94ce1696145a4'
ALIAS = 'D13_Bottle_Throw_Model'
FILE = 'SF3_D13_Bottle_Source.glb'


def bottle_weights(mesh, handler):
    # Same serialized Unity OneBone contract as the reviewed hook meshes, but
    # a distinct exact-name gate. Do not broaden the existing hook exporter.
    ids=np.asarray(handler.m_BoneIndices,dtype=int)
    channels=mesh.m_VertexData.m_Channels
    require(mesh.m_Name in ('rng__bottle_01_02_l','rng__bottle_01_02_r')
            and len(mesh.m_BindPose)==1 and handler.m_BoneWeights is None
            and ids.shape==(425,1) and np.all(ids==0)
            and channels[12].dimension==0 and channels[13].dimension==1 and channels[13].format==10,
            'Unreviewed bottle OneBone layout')
    return np.ones(ids.shape,dtype=float),ids,'UnityOneBoneImplicitUnitWeight'


def build(args):
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION = '6000.3.11f1'
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    require(not args.output.exists(), 'Use a fresh private output directory')
    root = args.recovery/'continued-20261116'
    named = checked_json(root/'serpent-named-settings-v1/serpent-shuangou-animation-named-v1.json', NAMED_SHA)
    setting = [r for r in named['records'] if r['configuration']['Animation'] == ALIAS]
    require(len(setting) == 1 and setting[0]['sourceRecordIndex'] == 68, 'Wrong bottle animation settings')
    config = setting[0]['configuration']
    require(config['FileName'] == 'unique_moves/sets/d13_bottle_throw_bullet.bin'
            and config['FirstFrame'] == 5 and config['EndFrame'] == 30 and config['SelfEndFrame'] == 0
            and config['MidFrames'] is None and config['Looped'] is None and config['Mirrored'] is None,
            'Unreviewed bottle clock')
    rules = documents(root/'serpent-trigger-source-v1', (1400,1402))
    birth, end = trigger(rules,1402,0), trigger(rules,1402,1)
    require(birth['events'] == [{'a2':['enum65537']}] and birth['actions'] == [{'a6':[ALIAS,None,None]}],
            'Original bottle birth differs')
    require(end['events'] == [{'a0':[ALIAS,'enum65537']}] and end['conditions'] is None
            and len(end['actions']) == 2 and end['actions'][1] == {'a50':[None,None]}
            and end['actions'][0]['a45'][15][7] == 'shd__shadow_ranged_agile_cloud',
            'Original cloud creation/deletion order differs')
    body_release = trigger(rules,1400,3,1)
    require(body_release['events'] == [{'a18':['enum65537','D13_Bottle_Throw_Model']}]
            and body_release['actions'][0]['a45'][:3] == [None,'enum4','Ranged'], 'Not an equipped-model release')

    source = root/'serpent-source-inputs-v1'
    bone_raw = checked(source/BONES['ranged'][0], BONES['ranged'][1], 10_000)
    model_raw = checked(source/MODELS['ranged'][0], MODELS['ranged'][1], 10_000)
    model = ET.fromstring(model_raw); bones = parse_bones_data(bone_raw)
    require([(m.get('Name'),m.get('MirroringDuplicate')) for m in model.findall('./Meshes/Mesh')]
            == [('rng__bottle_01_02_l','0'),('rng__bottle_01_02_r','1')], 'Changed mesh/mirror selection')
    environment = UnityPy.load(checked(root/'serpent-original-bundles-v1'/RANGED, BUNDLES[RANGED][1], 200_000))
    prefix = 'assets/gamedata/resources/content/items/models/top100/rng__bottle_01_02/m/'
    rows = source_rig(environment.container[prefix+'prefabs/r_bottle_01_02.prefab'])
    names = {r['name']:i for i,r in enumerate(rows)}
    require(len(rows) == 7 and set(bones['bones'].values()) <= names.keys(), 'Incomplete original bottle rig')
    paths, hashes = {}, {}
    for row in rows:
        path = row['name'] if row['parent'] in (None,'r_bottle_01_02') else paths[row['parent']]+'/'+row['name']
        paths[row['name']] = path; hashes[zlib.crc32(path.encode())] = names[row['name']]

    with ZipFile(args.archive) as archive:
        catalog = json.loads(member(archive,'research/motion_catalog.json',3_100_000,MOTION_CATALOG_SHA))
        bundles = {r['file']:r for r in (json.loads(x) for x in member(
            archive,'research/android_bundle_catalog.jsonl',9_200_000,BUNDLE_CATALOG_SHA).splitlines())}
        matches = [r for r in catalog['motions'] if r['name'] == 'd13_bottle_throw_bullet']
        require(len(matches) == 1 and matches[0]['sha256'] == MOTION_SHA, 'Unverified bottle motion')
        info = matches[0]
        env = UnityPy.load(member(archive,'bundles/'+info['bundle'],20_000_000,bundles[info['bundle']]['sha256']))
        obj = [o for o in env.objects if o.path_id == info['path_id']]
        require(len(obj) == 1 and obj[0].type.name == 'TextAsset', 'Missing original motion object')
        value = obj[0].read().m_Script
        raw = value.encode('utf8','surrogateescape') if isinstance(value,str) else bytes(value)
        require(sha(raw) == MOTION_SHA and len(raw) == info['bytes'], 'Changed motion bytes')
        cloud_matches = [r for r in catalog['motions'] if r['name'] == 's_rng_agl_cloud_bullet']

    arrays = decode(raw); motion = arrays[0]
    require(len(arrays) == 2 and all(a['frame_count'] == 29 for a in arrays)
            and set(map(int,motion['bone_ids'])) == set(bones['bones']), 'Wrong motion arrays/bones')
    first,last,stride = source_window(config,motion['frame_count'])
    require((first,last,stride) == (4,28,2) and source_end_event_tick(config,29) == 48, 'Wrong native clamped crop')
    writer = Writer(); g = writer.g
    g['asset']['generator'] = 'Verified original D13 bottle source resource; portable material preview'
    for row in rows:
        local = C @ matrix(row['translation'],row['rotation'],row['scale']) @ CI
        node = dict(name=row['name'],translation=local[:3,3].tolist(),rotation=quaternion(local[:3,:3]).tolist())
        children = [names[r['name']] for r in rows if r['parent'] == row['name']]
        if children: node['children'] = children
        g['nodes'].append(node)
    meshes = {o.read().m_Name:o.read() for o in environment.objects if o.type.name == 'Mesh'}
    renderers = {o.read().m_GameObject.read().m_Name:o.read() for o in environment.objects if o.type.name == 'SkinnedMeshRenderer'}
    materials, scenes, mesh_audit, reference_meshes = {}, [], [], []
    for side in ('l','r'):
        name = 'rng__bottle_01_02_'+side; mesh = meshes[name]
        handler = MeshHandler(mesh); handler.process()
        weights,ids,layout = bottle_weights(mesh,handler); ids,weights = skin_slots(ids,weights)
        require(len(mesh.m_BoneNameHashes) == len(mesh.m_BindPose) == 1
                and mesh.m_BoneNameHashes[0] in hashes and np.max(ids) == 0, 'Wrong bottle skin binding')
        bone = hashes[mesh.m_BoneNameHashes[0]]
        require(rows[bone]['name'] == 'gun_joint_'+side, 'Mirrored mesh bound to the wrong bone')
        bind = mesh.m_BindPose[0]
        inverse = C @ np.array([[getattr(bind,f'e{y}{x}') for x in range(4)] for y in range(4)]) @ CI
        skin = len(g['skins'])
        g['skins'].append(dict(joints=[bone],skeleton=names['ranged_root'],
                              inverseBindMatrices=writer.acc([inverse.T.reshape(16)],'MAT4')))
        positions = np.asarray(handler.m_Vertices,float)[:,:3]*[.01,.01,-.01]
        normals = np.asarray(handler.m_Normals,float)[:,:3]*[1,1,-1]
        uv = np.asarray(handler.m_UV0,float)[:,:2]; uv[:,1] = 1-uv[:,1]
        attributes = dict(POSITION=writer.acc(positions,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),
            TEXCOORD_0=writer.acc(uv,'VEC2'),JOINTS_0=writer.acc(ids,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4'))
        renderer = renderers[name]; triangles = handler.get_triangles()
        require(len(renderer.m_Materials) == len(triangles), 'Source submesh materials differ')
        primitives=[]; count=0
        for index, face in enumerate(triangles):
            indices=np.asarray(face,np.uint32).reshape(-1,3)[:,[0,2,1]].reshape(-1);count+=len(indices)//3
            material=original_material(writer,renderer.m_Materials[index].read(),materials)
            primitives.append(dict(attributes=attributes,indices=writer.acc(indices,'SCALAR',5125),material=material))
        mesh_index=len(g['meshes']);g['meshes'].append(dict(name=name,primitives=primitives))
        mesh_node=len(g['nodes']);g['nodes'].append(dict(name=name,mesh=mesh_index,skin=skin,
            extras=dict(sourceMirroringDuplicate=0 if side=='l' else 1)))
        scenes.append(dict(name='Original '+side+' bottle variant',nodes=[0,mesh_node]))
        mesh_audit.append(dict(name=name,bone=rows[bone]['name'],vertices=len(positions),triangles=count,
                               originalBoneHash=mesh.m_BoneNameHashes[0],sourceWeightLayout=layout))
        reference_meshes.append(dict(name=name,bone=rows[bone]['name'],positions=positions.tolist(),
                                     inverseBind=inverse.tolist()))
    g['scenes']=scenes
    times=writer.acc(np.arange(last-first+1)/30,'SCALAR')
    animation=dict(name=ALIAS,channels=[],samplers=[],extras=dict(sourceSHA256=MOTION_SHA,
        sourceFirstIndex=first,sourceLastIndex=last,sourceFrames=29,sourceFrameStride=stride,
        sourceEndEventTick=48,exportFramesPerSecond=30))
    for col,identifier in enumerate(motion['bone_ids']):
        node=names[bones['bones'][int(identifier)]]
        p=motion['positions'][first:last+1,col].astype(float)*[.01,.01,-.01]
        q=motion['rotations'][first:last+1,col].astype(float)*[-1,-1,1,1]
        q/=np.linalg.norm(q,axis=1)[:,None]
        for j in range(1,len(q)):
            if q[j-1]@q[j]<0:q[j]*=-1
        for key,data,width in [('translation',p,'VEC3'),('rotation',q,'VEC4')]:
            sampler=len(animation['samplers']);animation['samplers'].append(dict(input=times,output=writer.acc(data,width),interpolation='LINEAR'))
            animation['channels'].append(dict(sampler=sampler,target=dict(node=node,path=key)))
    g['animations'].append(animation)
    output=private_output(args.output);output.mkdir(parents=True,exist_ok=True)
    result=writer.save(output/FILE);(output/FILE).chmod(0o600)
    document=dict(schema='d13-bottle-source-resource-v1',runtimeBound=False,
        sourceBundle=RANGED,sourceBundleSHA256=BUNDLES[RANGED][1],
        sourceBonesSHA256=BONES['ranged'][1],sourceModelConfigurationSHA256=MODELS['ranged'][1],
        sourceModelConfiguration=model_raw.decode('cp1251'),
        model=dict(file=FILE,**result),meshVariants=mesh_audit,referenceMeshes=reference_meshes,rig=rows,bones=bones,
        sourceConfiguration=setting[0],sourceMotion=info,sourceBytesBase64=base64.b64encode(raw).decode(),
        sourceFirstIndex=first,sourceLastIndex=last,playbackTicks=48,sourceEndEventTick=48,
        sourceBirth=birth,sourceAnimationEnd=end,bodyRelease=body_release,
        modelLocalCoordinates='Source Unity centimeters converted by C; facing and parent Align remain runtime responsibilities.',
        cloudMotionPresentInAuthenticatedCatalog=bool(cloud_matches),
        boundaries=dict(customShaderParity=False,cloudMotionBound=False,cloudCollisionBound=False,
                        bottleAttackIntervals=0,sourceDeletionAndCloudRequestOnly=True,fullMatchProfile=False))
    write_private(output/'bottle-source-private.json',json.dumps(document,ensure_ascii=False,separators=(',',':')).encode())
    return document


def verify(path, document):
    """Read back GLB animation FK against original compressed motion arrays."""
    g,binary=glb_read(path);motion=decode(base64.b64decode(document['sourceBytesBase64'],validate=True))[0]
    _,rest,parents=world_poses(g['nodes']); names={n['name']:i for i,n in enumerate(g['nodes'])}
    ids={int(k):v for k,v in document['bones']['bones'].items()};columns={ids[int(k)]:i for i,k in enumerate(motion['bone_ids'])}
    errors=[]; skin_errors=[]; animation=g['animations'][0];mesh_data=[]
    require(len(animation['channels'])==10 and len(g['scenes'])==2, 'Missing source animation/mesh variants')
    for sampler in animation['samplers']:
        times=accessor_read(g,binary,sampler['input']).reshape(-1)
        require(times.shape==(25,) and np.max(np.abs(times-np.arange(25)/30))<1e-7, 'Wrong exported key times')
    for source in document['referenceMeshes']:
        node=g['nodes'][names[source['name']]];skin=g['skins'][node['skin']]
        require(skin['joints']==[names[source['bone']]], 'Bottle mesh uses wrong mirrored bone')
        attributes=g['meshes'][node['mesh']]['primitives'][0]['attributes']
        p=accessor_read(g,binary,attributes['POSITION']);count=len(p)
        weights=accessor_read(g,binary,attributes['WEIGHTS_0'])
        ids=accessor_read(g,binary,attributes['JOINTS_0'])
        require(count==425 and np.all(ids==0) and np.all(weights[:,0]==1) and np.all(weights[:,1:]==0),
                'Changed exact OneBone mesh weights')
        inverse=accessor_read(g,binary,skin['inverseBindMatrices'])[0].reshape(4,4).T
        mesh_data.append((names[source['bone']],np.c_[np.array(source['positions']),np.ones(count)],
                          np.array(source['inverseBind']),np.c_[p,np.ones(count)],inverse))
    for tick in range(49):
        source_index=4+tick//2; next_index=min(28,source_index+1);weight=(tick%2)*.5
        actual=[m.copy() for m in rest];expected=[m.copy() for m in rest];values={}
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            data=accessor_read(g,binary,sampler['output']);i=tick//2;j=min(24,i+1)
            a=data[i].astype(float);b=data[j].astype(float)
            if channel['target']['path']=='rotation' and a@b<0:b=-b
            values.setdefault(channel['target']['node'],{})[channel['target']['path']]=a*(1-weight)+b*weight
        for name,col in columns.items():
            p=motion['positions'][source_index,col].astype(float)*(1-weight)+motion['positions'][next_index,col].astype(float)*weight
            a=motion['rotations'][source_index,col].astype(float);b=motion['rotations'][next_index,col].astype(float)
            if a@b<0:b=-b
            node=names[name];expected[node]=C@matrix(p,a*(1-weight)+b*weight,[1,1,1])@CI
            actual[node]=matrix(values[node]['translation'],values[node]['rotation'],[1,1,1])
        ew,aw=pose_world(expected,parents),pose_world(actual,parents)
        for name in columns:errors.append(float(np.max(np.abs(ew[names[name]]-aw[names[name]]))))
        for bone,original,inverse,exported,exported_inverse in mesh_data:
            a=(ew[bone]@inverse@original.T).T[:,:3]
            b=(aw[bone]@exported_inverse@exported.T).T[:,:3]
            skin_errors.extend(np.max(np.abs(a-b),axis=1).tolist())
    require(len(errors)==245 and max(errors)<2e-5, 'Exported bottle FK differs from original arrays')
    require(len(skin_errors)==41650 and max(skin_errors)<2e-5, 'Exported bottle skin differs from source mesh/bind data')
    return dict(comparisons=len(errors),maximumMatrixError=max(errors),sourceTicks=49,
                skinnedVertexComparisons=len(skin_errors),maximumSkinErrorMeters=max(skin_errors),
                sourceBoneTracks=5,customShaderParity=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('recovery','archive','output'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();result=build(args)
    verification=verify(args.output/FILE,result)
    write_private(args.output/'bottle-readback-private.json',json.dumps(verification,separators=(',',':')).encode())
    print(json.dumps(dict(model=result['model'],meshes=result['meshVariants'],verification=verification,
                         cloudMotionPresent=result['cloudMotionPresentInAuthenticatedCatalog'])))
