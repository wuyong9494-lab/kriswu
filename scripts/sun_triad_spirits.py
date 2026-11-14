#!/usr/bin/env python3
"""Build the eight source H17 summoned models on their own original rigs.

Mesh activation comes from the actual ModelObject XML. MirroringDuplicate
meshes are recorded rather than incorrectly rendering both weapon copies.
Animation identities come from the decoded H17 style records, not the host's
cast motion. Only supplied/verified local sources are read; output is private.
"""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, warnings, zlib
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile
import numpy as np
from sun_triad_assets import (Writer, C, CI, RIGHT, matrix, quaternion, skin_slots,
    original_material, world_poses, pose_world, decode, require, private_output, write_private)
from sun_triad_source_bones import parse_bones_data
from sun_triad_materials import embedded_texture, material_descriptor
from prepare_fighter_target_motions import ARCHIVE_SHA256

SPIRITS = {
    'legionary': dict(model='mgc__h17_spirit_legion_sword',bundle='30f756dcaae190f345f79e0cd03aea09.bin',
        configSHA256='541ee809263cc4c0d6fe2fc2a651299e5be36fa27e6a29571bb77049160fad1d',
        bonesSHA256='96147bd41790f74e479daaae65427be92e14d2cdd12834226f54cce52f02a0e7',
        states=['H17_Spirit_Legion_Twohanded_Sword_Heavy_Slash','H17_Spirit_Legion_Block']),
    'dynast': dict(model='mgc__h17_spirit_dynasty2',bundle='80744c93803af32d812c79acd52bfd38.bin',
        configSHA256='550fc951295eae82495337ae47d5140cca16ccc853e1978608abe56dc314fc50',
        bonesSHA256='1698ea28d3fa6c5a01adfdcc0d3726112da904ec5f1c9ca314d02dd1f4eeb828',
        states=['H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close_Back',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium_Back',
                'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long_Back']),
    'herald': dict(model='mgc__h17_spirit_heralds_naginata',bundle='d1ac46be3434c7693e2e9c4bf6fff18a.bin',
        configSHA256='e0d72451be6c90e86ebf7a4015facb3165d38294f5a0781b54068bed8f7ef57b',
        bonesSHA256='fb84530bc8b938dc65c6aef651a80e1b1bf42a9664df1a545962549fec55887d',
        states=['H17_Spirit_Herald_Shadow_Dash']),
}
SPIRIT_ALPHA_SHA256='17d137872b98717b2132465fa4984169188f470df933d75d918c75bcb5891d3c'
SPIRIT_CONFIGURATION_SHA256='cfbb6fb6babc8d4a68980e8cf97aac9b80b4f47b6f8b20433cf6e984b3baf8c9'
SPIRITS.update({
    'dynasty1': dict(model='mgc__h17_spirit_dynasty1',bundle='00a21255143c2e6368ba9b34e6914d68.bin',
        configSHA256='9f6705814e5798ca59b72edd3db6f217bf45f9164cd0afeb66ba810bbdc0bbdb',
        bonesSHA256='fea1829e1e31ba6eca8887db4e87d31197799aa02c34cd4d1c4372b22c39dd9c'),
    'dynasty3': dict(model='mgc__h17_spirit_dynasty3',bundle='9d8489d49dfd5e6fa30dcfe8e67199a6.bin',
        configSHA256='eb34073e5d23398d09ab2b7ee6d176fa861093e902b0d6c3eddbc1523a0ce41a',
        bonesSHA256='1698ea28d3fa6c5a01adfdcc0d3726112da904ec5f1c9ca314d02dd1f4eeb828'),
    'legiondefender': dict(model='mgc__h17_spirit_legion_giant_sword',bundle='6af666abafe9dca52100e3918b8a04e9.bin',
        configSHA256='dae96ecdc4f4c52419521f48fabe3dced535025edb4a8d254146af56b40cb40d',
        bonesSHA256='ca4440f9191905ad2924ccd26969d33eeaab4e1876a5401c1118096d1e2c8df9'),
    'legionhammer': dict(model='mgc__h17_spirit_legion_hammer',bundle='48347f952865bc870a1e4e9f6eced14e.bin',
        configSHA256='e1e7a06460f0d824e982de795be3fd2267ae4f41fe406a4075fdca188519279a',
        bonesSHA256='ac6f81c156d31160fcd946b952b192629906834d7c6a3f91f83957cce85d1a4e'),
    'heraldninjato': dict(model='mgc__h17_spirit_heralds_ninjato',bundle='46807643d37ca8b0fece25171ad27736.bin',
        configSHA256='0f43442f227cc1417bd57a573fd82d16511ea1389ecfc3304cae249817fbc5c3',
        bonesSHA256='58487a93bd795e3b8d6cd9867fdabb01c8aa9c079925faa29e22ec692ae173c1'),
})
# Original CreateNewModel bindings recovered from the H17 production trigger
# sets. A role identifies an actual state/model pair, not just a faction tint.
BINDINGS={
    'legionary': {
        'triadLegionary':'H17_Spirit_Legion_Twohanded_Sword_Heavy_Slash',
        'triadSummon_danceRift1':'H17_Spirit_Rift_1',
        'triadSummon_danceRift2':'H17_Spirit_Rift_2'},
    'herald': {
        'triadHerald':'H17_Spirit_Herald_Shadow_Dash',
        'triadSummon_danceBlast':'H17_Spirit_Precise_Armor'},
    'dynast': {
        'triadDynast':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow',
        'triadSummon_rainMediumFront':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium',
        'triadSummon_rainFarBack':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long_Back'},
    'dynasty1': {
        'triadSummon_rainCloseBack':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close_Back',
        'triadSummon_rainMediumBack':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium_Back',
        'triadSummon_entangledBow':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long'},
    'dynasty3': {
        'triadSummon_rainCloseFront':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close',
        'triadSummon_rainFarFront':'H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long',
        'triadSummon_danceWhirl':'H17_Spirit_Dynasty_Helmet'},
    'legiondefender': {'triadSummon_legionDefender':'H17_Spirit_Legion_Block'},
    'legionhammer': {
        'triadSummon_legionHammer':'H17_Spirit_Legion_Hammer',
        'triadSummon_danceThud':'H17_Spirit_Thud'},
    'heraldninjato': {
        'triadSummon_danceNinjato':'H17_Spirit_Herald_Ninjato_Slash_Miss',
        'triadSummon_ninjatoActiveStart':'H17_Spirit_Herald_Ninjato_Active_Start',
        'triadSummon_ninjatoActiveEnd':'H17_Spirit_Herald_Ninjato_Active_End'},
}
for identity,definition in SPIRITS.items():definition['states']=sorted(set(BINDINGS[identity].values()))


def sha(data):return hashlib.sha256(data).hexdigest()


def source_xml(environment, models, bundle, prefix, name):
    matches=[(path,pointer) for path,pointer in environment.container.items()
             if path.startswith(prefix) and path.endswith('/'+name+'.xml')]
    require(len(matches)==1, 'Original spirit XML path missing or ambiguous: '+name)
    path,pointer=matches[0]
    local=models/(Path(bundle).stem+'_'+str(pointer.path_id)+'_'+name+'.decoded.clear-private')
    raw=local.read_bytes()
    require(len(raw)<=100_000 and b'<!DOCTYPE' not in raw and b'<!ENTITY' not in raw, 'Unexpected source XML')
    return raw,dict(sourcePath=path,sourcePathID=str(pointer.path_id),bytes=len(raw),sha256=sha(raw))


def source_rig(pointer):
    root=pointer.read()
    transforms=[c.component.read() for c in root.m_Component if c.component.deref().type.name=='Transform']
    require(len(transforms)==1,'Ambiguous original spirit rig root')
    rows=[]
    def walk(t,parent):
        name=t.m_GameObject.read().m_Name
        rows.append(dict(name=name,parent=parent,
            translation=[t.m_LocalPosition.x,t.m_LocalPosition.y,t.m_LocalPosition.z],
            rotation=[t.m_LocalRotation.x,t.m_LocalRotation.y,t.m_LocalRotation.z,t.m_LocalRotation.w],
            scale=[t.m_LocalScale.x,t.m_LocalScale.y,t.m_LocalScale.z]))
        for child in t.m_Children:walk(child.read(),name)
    walk(transforms[0],None)
    require(len({r['name'] for r in rows})==len(rows),'Duplicate original spirit rig node')
    return rows


def build(identity, definition, args, archive, bundle_catalog, motion_catalog, settings, output):
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    bundle=definition['bundle'];raw=(args.models/bundle).read_bytes()
    require(sha(raw)==bundle_catalog[bundle]['sha256'],'Original spirit bundle integrity mismatch')
    environment=UnityPy.load(raw)
    prefix='assets/gamedata/resources/content/items/models/'+definition['model']+'/m/'
    configuration,config_audit=source_xml(environment,args.models,bundle,prefix,'config')
    require(sha(configuration)==definition['configSHA256'],'Original spirit ModelObject digest mismatch')
    config=ET.fromstring(configuration)
    require(config.tag=='ModelObject' and config.get('Name')==definition['model'],'Original spirit model identity mismatch')
    bone_raw,bone_audit=source_xml(environment,args.models,bundle,prefix,'bones')
    require(sha(bone_raw)==definition['bonesSHA256'],'Original spirit BonesData digest mismatch')
    bone_data=parse_bones_data(bone_raw)
    prefabs=[(path,pointer) for path,pointer in environment.container.items()
             if path==prefix+'prefabs/skeleton.prefab']
    require(len(prefabs)==1,'Original summoned spirit skeleton is ambiguous')
    rows=source_rig(prefabs[0][1]);names={r['name']:i for i,r in enumerate(rows)}
    paths,hashes={},{}
    for row in rows:
        path=row['name'] if row['parent'] in (None,'skeleton') else paths[row['parent']]+'/'+row['name']
        key=zlib.crc32(path.encode());require(key not in hashes,'Original spirit path hash collision')
        paths[row['name']]=path;hashes[key]=names[row['name']]
    renderers=[];excluded=[]
    for item in config.findall('./Meshes/Mesh'):
        name=item.get('Name');require(bool(name),'Unnamed source spirit mesh')
        if item.get('MirroringDuplicate')=='1' or '__trail_' in name:
            excluded.append(dict(name=name,mirroringDuplicate=item.get('MirroringDuplicate')=='1',
                                 separateSourceTrail='__trail_' in name));continue
        matches=[p for path,p in environment.container.items() if path==prefix+'meshes/'+name.lower()+'.prefab']
        require(len(matches)==1,'Original spirit mesh prefab missing or ambiguous: '+name)
        game_object=matches[0].read()
        found=[x.component.read() for x in game_object.m_Component
               if x.component.deref().type.name=='SkinnedMeshRenderer']
        require(len(found)==1,'Original spirit mesh renderer is ambiguous')
        renderers.append(found[0])
    require(bool(renderers),'Original spirit has no active primary mesh')
    meshdata=[];world_bind={};disagreement=0.;skin_bindings=[]
    for renderer in renderers:
        mesh=renderer.m_Mesh.read();handler=MeshHandler(mesh);handler.process()
        transforms=[component.component.read() for component in renderer.m_GameObject.read().m_Component
                    if component.component.deref().type.name=='Transform']
        require(len(transforms)==1,'Original spirit mesh transform is ambiguous')
        transform=transforms[0]
        source_mesh_transform=matrix(
            [transform.m_LocalPosition.x,transform.m_LocalPosition.y,transform.m_LocalPosition.z],
            [transform.m_LocalRotation.x,transform.m_LocalRotation.y,transform.m_LocalRotation.z,transform.m_LocalRotation.w],
            [transform.m_LocalScale.x,transform.m_LocalScale.y,transform.m_LocalScale.z])
        mesh_space=C@source_mesh_transform@CI
        require(len(mesh.m_BindPose)==len(mesh.m_BoneNameHashes),'Original spirit bind count differs')
        # Source SkinData explicitly remaps equipment imported from a different
        # FBX hierarchy. Its ordered names are the game's binding contract;
        # recomputing CRCs after the prefab reparent would lose that contract.
        bindings=[]
        for component in renderer.m_GameObject.read().m_Component:
            if component.component.deref().type.name=='MonoBehaviour':
                value=component.component.deref().read_typetree()
                if '_bindBonesName' in value:bindings.append((component.component.path_id,value['_bindBonesName'],value['cullMode']))
        require(len(bindings)==1 and len(bindings[0][1])==len(mesh.m_BoneNameHashes),
                'Original spirit SkinData ordered bone binding is missing or ambiguous')
        binding_id,binding_names,cull_mode=bindings[0]
        require(cull_mode in (0,1,2),'Unsupported source spirit mesh cull mode')
        require(all(name in names for name in binding_names),'Original spirit SkinData references an absent rig node')
        require(all(key not in hashes or names[name]==hashes[key]
                    for key,name in zip(mesh.m_BoneNameHashes,binding_names)), 'Original spirit SkinData conflicts with a source path hash')
        indices=np.asarray(handler.m_BoneIndices,dtype=int)
        if handler.m_BoneWeights is None:
            require(indices.shape==(len(handler.m_Vertices),1) and mesh.m_VertexData.m_Channels[12].dimension==0
                    and mesh.m_VertexData.m_Channels[13].dimension==1,'Unexpected implicit source skin weights')
            source_weights=np.ones_like(indices,dtype=float)
        else:source_weights=np.asarray(handler.m_BoneWeights,dtype=float)
        weights=source_weights
        mapping=np.array([names[name] for name in binding_names]);joints,weights=skin_slots(mapping[indices],weights)
        for slot in set(indices[source_weights>1e-7].tolist()):
            bone=int(mapping[slot]);source=mesh.m_BindPose[slot]
            bind=np.array([[getattr(source,f'e{y}{x}') for x in range(4)] for y in range(4)])
            # Imported equipment may retain a prefab scale (the giant-sword
            # guardian body has 0.1). Normalize both its vertices and inverse
            # binds through that exact transform, never a guessed correction.
            world=mesh_space@np.linalg.inv(C@bind@CI)
            if bone in world_bind:disagreement=max(disagreement,float(np.max(abs(world-world_bind[bone]))))
            else:world_bind[bone]=world
        meshdata.append((renderer,mesh,handler,joints,weights,mesh_space,cull_mode))
        skin_bindings.append(dict(mesh=mesh.m_Name,sourceSkinDataPathID=str(binding_id),
            sourceMeshTransform=source_mesh_transform.tolist(),sourceCullMode=cull_mode,
            orderedSourceBoneNames=binding_names,sourceMeshBoneHashes=list(mesh.m_BoneNameHashes),
            matchingCurrentHierarchyHashes=sum(key in hashes for key in mesh.m_BoneNameHashes)))
    require(disagreement<.001,'Original spirit shared bind matrices disagree')
    writer=Writer();g=writer.g;worlds={}
    for index,row in enumerate(rows):
        parent=names.get(row['parent']);previous=worlds[parent] if parent is not None else np.eye(4)
        world=world_bind.get(index,previous@C@matrix(row['translation'],row['rotation'],row['scale'])@CI)
        local=np.linalg.inv(previous)@world;scale=np.linalg.norm(local[:3,:3],axis=0)
        node=dict(name=row['name'],translation=local[:3,3].tolist(),rotation=quaternion(local[:3,:3]/scale).tolist(),scale=scale.tolist())
        children=[i for i,r in enumerate(rows) if r['parent']==row['name']]
        if children:node['children']=children
        g['nodes'].append(node);worlds[index]=world
    inverse=[np.linalg.inv(worlds[i]) for i in range(len(rows))]
    g['skins'].append(dict(name='Original H17 summoned spirit rig',joints=list(range(len(rows))),skeleton=names['skeleton'],
                          inverseBindMatrices=writer.acc([m.T.reshape(16) for m in inverse],'MAT4')))
    mesh_nodes=[];material_cache={}
    for renderer,mesh,handler,joints,weights,mesh_space,cull_mode in meshdata:
        vertices=np.asarray(handler.m_Vertices)[:,:3]*[.01,.01,-.01]
        vertices=(np.c_[vertices,np.ones(len(vertices))]@mesh_space.T)[:,:3]
        normals=(np.asarray(handler.m_Normals)[:,:3]*[1,1,-1])@np.linalg.inv(mesh_space[:3,:3])
        normals/=np.linalg.norm(normals,axis=1)[:,None]
        uv=np.asarray(handler.m_UV0)[:,:2].copy();uv[:,1]=1-uv[:,1]
        attributes=dict(POSITION=writer.acc(vertices,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),TEXCOORD_0=writer.acc(uv,'VEC2'),
                        JOINTS_0=writer.acc(joints,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4'))
        primitives=[]
        for index,triangles in enumerate(handler.get_triangles()):
            indices=np.asarray(triangles,dtype=np.uint32).reshape(-1,3)[:,[0,2,1]].reshape(-1)
            if not len(indices):continue
            source_material=renderer.m_Materials[min(index,len(renderer.m_Materials)-1)].deref()
            material_value=source_material.read()
            alpha_pointer=dict(material_value.m_SavedProperties.m_TexEnvs)['_AlphaTex'].m_Texture
            require(1 <= alpha_pointer.m_FileID <= len(source_material.assets_file.externals),
                    'Original spirit alpha external reference is out of bounds')
            alpha_cab=source_material.assets_file.externals[alpha_pointer.m_FileID-1].path.rsplit('/',1)[-1]
            require(alpha_cab=='CAB-776814e1aecd39348ee7d1bd103cdaca'
                    and alpha_pointer.m_PathID==-6034618301929850897,
                    'Source spirit alpha object identity differs')
            material=original_material(writer,material_value,material_cache.setdefault(cull_mode,{}),
                                       double_sided_override=cull_mode==0)
            g['materials'][material]['name']=material_value.m_Name+'_cull'+str(cull_mode)
            g['materials'][material]['extras']['sourceRaster']['cull']='front' if cull_mode==1 else 'back'
            g['materials'][material]['extras']['sourceAlphaCAB']=alpha_cab
            primitives.append(dict(attributes=attributes,indices=writer.acc(indices,'SCALAR',5125),material=material))
        mesh_index=len(g['meshes']);g['meshes'].append(dict(name=mesh.m_Name,primitives=primitives))
        mesh_nodes.append(len(g['nodes']));g['nodes'].append(dict(name=mesh.m_Name,mesh=mesh_index,skin=0))
    outer=len(g['nodes']);g['nodes'].append(dict(name='SF3_Actor_Meters',children=[0]+mesh_nodes,scale=[.92]*3,
        rotation=[0,-float(np.sqrt(.5)),0,float(np.sqrt(.5))]));g['scenes'][0]['nodes']=[outer]
    from PIL import Image
    alpha_raw=args.source_alpha.read_bytes()
    require(sha(alpha_raw)==SPIRIT_ALPHA_SHA256,'Original spirit alpha texture digest mismatch')
    alpha_image=Image.open(args.source_alpha).convert('RGBA')
    require(alpha_image.size==(256,256),'Original spirit alpha texture dimensions differ')
    alpha_pixels=np.asarray(alpha_image,dtype=np.uint8)
    diffuse=np.zeros_like(alpha_pixels);diffuse[:,:,3]=alpha_pixels[:,:,0]
    sampler=dict(wrapS=10497,wrapT=10497,minFilter=9986,magFilter=9729)
    source_alpha,alpha_receipt=embedded_texture(writer,alpha_image,'mask_quad_001_vert',sampler)
    diffuse_texture,_=embedded_texture(writer,Image.fromarray(diffuse,'RGBA'),
        'mgc__h17_spirit_black_with_original_alpha_red',sampler)
    for material in g['materials']:
        require(material['extras']['sourceMaterial']=='mat_mgc__h17_spirit_base','Unexpected summoned spirit material')
        binding=material['extras']['sourceTextureBindings']['_AlphaTex']
        require(material['extras']['sourceAlphaCAB']=='CAB-776814e1aecd39348ee7d1bd103cdaca'
                and binding['sourcePathID']=='-6034618301929850897',
                'Source spirit alpha reference differs')
        binding.update(texture=source_alpha,sourceName='mask_quad_001_vert',
            sourceBundle='e0827787798b68df283fc2391b8d7f11.bin',width=256,height=256,**alpha_receipt)
        material['pbrMetallicRoughness']['baseColorTexture']=dict(index=diffuse_texture)
        material['extras']['sourceRaster']['mip']='nearest'
        material['extras']['sourceFresnel']=args.fresnel
        material['extras']['sourceAlphaRedCopiedToBaseAlpha']=True
    rest_world,rest,parents=world_poses(g['nodes'])
    basis=RIGHT[:3,:3]@rest_world[parents[names['pelvis']]][:3,:3]
    markers=[]
    for side in ('l','r'):
        foot,toe=names['foot_'+side],names['toe_'+side]
        a,b=rest_world[foot][:3,3],rest_world[toe][:3,3]
        for x in (min(a[0],b[0])-.055,max(a[0],b[0])+.055):
            for z in (min(a[2],b[2])-.055,max(a[2],b[2])+.055):
                markers.append((foot,np.linalg.inv(rest_world[foot])@[x,-.02,z,1]))
    source_ids={i:n for i,n in bone_data['bones'].items() if n in names}
    states={state:settings[state][1] for state in definition['states']};clips=[];loaded={}
    for source_path in sorted(set(states.values())):
        clip=Path(source_path).stem;matches=[row for row in motion_catalog if row['name']==clip]
        # Identical source bytes can occur in the general style and the item
        # override bundle. Never resolve a differing animation by name alone.
        require(matches and len({r['sha256'] for r in matches})==1,
                'Original summoned spirit animation identity is ambiguous: '+clip)
        if source_path.startswith('w_ninjato/'):
            matches=[r for r in matches if r['bundle']=='2ee15f236c4e114912c05a8561b8c9a3.bin']
            require(len(matches)==1,'Original Ninjato motion bundle is missing')
        info=sorted(matches,key=lambda r:r['bundle'])[0];source_bundle=info['bundle']
        if source_bundle not in loaded:
            source=archive.read('bundles/'+source_bundle)
            require(sha(source)==bundle_catalog[source_bundle]['sha256'],'Original spirit motion bundle integrity mismatch')
            loaded[source_bundle]=UnityPy.load(source)
        source_object=next(o for o in loaded[source_bundle].objects if o.path_id==info['path_id'])
        value=source_object.read().m_Script
        raw=value.encode('utf8','surrogateescape') if isinstance(value,str) else bytes(value)
        require(sha(raw)==info['sha256'],'Original spirit motion digest mismatch')
        arrays=decode(raw);require(len(arrays)==2,'Unexpected original spirit motion array count')
        motion=arrays[0];frames=motion['frame_count']
        require(all(int(i) in source_ids for i in motion['bone_ids']),'Original spirit animation has an unresolved source bone: '+clip)
        columns={source_ids[int(i)]:column for column,i in enumerate(motion['bone_ids'])}
        require(all(settings[state][2] is None or settings[state][2]==1
                    for state,path in states.items() if path==source_path),
                'Spirit animation overrides the recovered two-tick source-frame stride')
        times=writer.acc(np.arange(frames)/30.,'SCALAR');animation=dict(name=clip,channels=[],samplers=[],
            extras=dict(sourceSHA256=info['sha256'],sourceFrames=frames,sourceFPS=30,simulationHz=60,
                        sourceMidFrames=1,sourceFrameStride=2,previewFPS=30))
        positions,rotations={},{}
        for name,column in columns.items():
            position=motion['positions'][:,column].astype(float)*[.01,.01,-.01]
            if name=='pelvis':position[:,[0,2]]=0
            rotation=motion['rotations'][:,column].astype(float)*[-1,-1,1,1]
            rotation/=np.linalg.norm(rotation,axis=1)[:,None]
            for frame in range(1,frames):
                if rotation[frame-1]@rotation[frame]<0:rotation[frame]*=-1
            positions[name]=position.astype(np.float32).astype(float)
            rotations[name]=rotation.astype(np.float32).astype(float)
            for path,data,kind in [('translation',position,'VEC3'),('rotation',rotation,'VEC4')]:
                sampler=len(animation['samplers']);animation['samplers'].append(dict(input=times,output=writer.acc(data,kind),interpolation='LINEAR'))
                animation['channels'].append(dict(sampler=sampler,target=dict(node=names[name],path=path)))
        g['animations'].append(animation)
        rawroot=motion['positions'][:,columns['pelvis']].astype(float)*[.01,.01,-.01]
        rootdelta=(rawroot-rawroot[0])@basis.T;roots=[];ground=[]
        for sample in range(2*frames-1):
            a=sample//2;b=min(frames-1,a+1);weight=(sample%2)/2
            local=[m.copy() for m in rest]
            for name in columns:
                position=positions[name][a]*(1-weight)+positions[name][b]*weight
                rotation=rotations[name][a]*(1-weight)+rotations[name][b]*weight
                index=names[name];local[index]=matrix(position,rotation,g['nodes'][index].get('scale',[1,1,1]))
            world=pose_world(local,parents)
            roots.append(rootdelta[a]*(1-weight)+rootdelta[b]*weight)
            low=min((world[foot]@marker)[1] for foot,marker in markers)
            ground.append(float(max(0.,-.035-low)))
        clips.append(dict(name=clip,sourcePath=source_path,frames=frames,sha256=info['sha256'],bundle=source_bundle,
                          sourcePathID=str(info['path_id']),sourceBoneIDs=[int(i) for i in motion['bone_ids']],
                          sourceArrayCount=len(arrays),sourceBytesBase64=base64.b64encode(raw).decode(),
                          root=np.round(roots,7).tolist(),groundLift=np.round(ground,7).tolist()))
    g['extras']=dict(sourceModel=definition['model'],sourceBundle=bundle,sourceSkinPreserved=True,
                    sourceMeshActivation='Original ModelObject XML, excluding MirroringDuplicate and separate trail meshes',
                    sourceFPS=30,simulationHz=60,sourceFrameStride=2,previewFPS=30,horizontalPelvisZeroed=True)
    filename='SF3WE_H17_'+identity.title()+'.glb';result=writer.save(output/filename)
    record=dict(id=identity,sourceModel=definition['model'],name=filename,**result,
        sourceBundle=bundle,sourceBundleSHA256=bundle_catalog[bundle]['sha256'],sourceConfig=config_audit,sourceBones=bone_audit,
        sourcePrefab=prefabs[0][0],sourceSkeletonNodes=len(rows),maximumSharedBindMatrixDifference=disagreement,
        sourceSkinDataBindings=skin_bindings,
        activeSourceMeshes=[item[1].m_Name for item in meshdata],excludedSourceMeshes=excluded,
        sourceAnimationBindings=states,clips=clips,sourceFramesPerSecond=30,previewFramesPerSecond=30,
        sourceRoles=BINDINGS[identity],
        materials=[material_descriptor(m) for m in g['materials']],sourceFresnel=args.fresnel,
        groundLiftBasis='Application floor-contact adapter, using the source foot/toe poses; not original Unity ground collision.',
        sourceBoneBindings=[dict(sourceID=i,name=name,targetNode=names[name],path=paths[name]) for i,name in source_ids.items()])
    write_private(output/('h17-'+identity+'-provenance.json'),json.dumps(record,indent=2).encode())
    return record


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',type=Path,required=True)
    parser.add_argument('--motion-archive',type=Path,required=True)
    parser.add_argument('--source-animation-settings',type=Path,required=True)
    parser.add_argument('--source-spirit-configuration',type=Path,required=True)
    parser.add_argument('--source-alpha',type=Path,required=True)
    parser.add_argument('--character',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();output=private_output(args.output)
    import UnityPy
    require(UnityPy.__version__=='1.25.4','Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1';warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    require(sha(args.motion_archive.read_bytes())==ARCHIVE_SHA256,'Supplied source archive identity mismatch')
    values=json.loads(args.source_animation_settings.read_text());settings={row[0]:row for row in values}
    require(len(settings)==len(values),'Duplicate source H17 animation setting')
    configuration=args.source_spirit_configuration.read_bytes()
    require(sha(configuration)==SPIRIT_CONFIGURATION_SHA256,'Original common spirit trigger configuration differs')
    root=json.loads(configuration)
    require(len(root)==1 and root[0]['fields'][0]=='SET_HERALDS_17_COMMON_SPIRIT_MODEL',
            'Original common spirit trigger identity differs')
    actions=root[0]['fields'][1][0]['fields'][5]
    fresnel=[a['value'] for a in actions if a.get('kind')=='NamedData' and a.get('id')==148]
    require(len(fresnel)==1 and len(fresnel[0])==8 and fresnel[0][1] is True,
            'Original SetFresnel action missing or ambiguous')
    action=fresnel[0]
    args.fresnel=dict(color=action[5],power=1 if action[6] is None else action[6],transitionSeconds=action[4])
    with ZipFile(args.motion_archive) as archive:
        bundles={x['file']:x for x in map(json.loads,archive.read('research/android_bundle_catalog.jsonl').splitlines())}
        motions=json.loads(archive.read('research/motion_catalog.json'))['motions']
        result=[build(identity,definition,args,archive,bundles,motions,settings,output) for identity,definition in SPIRITS.items()]
    index=dict(version=1,candidateOnly=True,sourceSettingsSHA256=sha(args.source_animation_settings.read_bytes()),
               models=[{k:v for k,v in item.items() if k not in ('clips','sourceBoneBindings')} for item in result])
    write_private(output/'h17-three-spirits-candidate.json',json.dumps(index,indent=2).encode())
    document=dict(version=1,profileID='sun_triad',characterSHA256=sha(args.character.read_bytes()),
        sourceConfigurationSHA256=sha(configuration),evidence=[
            'Original H17 production CreateNewModel actions choose eight independently rigged companion models.',
            'Original SkinData ordered bone names bind each mesh; original inverse bind matrices are preserved.',
            'H17 animation settings explicitly bind the 18 summon states and two Ninjato active continuation states.',
            'Rain archers use the original Dynasty1/2/3 identities; the defender uses the original giant-sword model.',
            'Dance is the original Ninjato, Whirl, Blast, Thud, Rift1/Rift2 model sequence, not a cycle of three ordinary souls.',
            'SET_HERALDS_17_COMMON_SPIRIT_MODEL trigger 0 SetFresnel: transition 0.15s, RGB 147/255 208/255 245/255, power default 1.',
            'Original shader variant 3930 adds pow(1-abs(viewNormal.z),power)*FresnelColor and samples AlphaTex.red independently.',
            'Source player 60Hz, MidFrames default 1 plus one gives stride 2; samples include every half source frame.',
            'Pelvis horizontal animation is zeroed; source root.x is applied once by the summon renderer.'],models=[])
    for record in result:
        motions=[dict(roles=sorted(role for role,state in record['sourceRoles'].items()
                                  if Path(record['sourceAnimationBindings'][state]).stem==clip['name']),
            clip=clip['name'],frames=clip['frames'],exportFramesPerSecond=30,sourceSHA256=clip['sha256'],
            sourceBundle=clip['bundle'],root=clip['root'],groundLift=clip['groundLift']) for clip in record['clips']]
        document['models'].append(dict(sourceModel=record['sourceModel'],
            file={k:record[k] for k in ('name','bytes','sha256')},skinRoots=[],materials=record['materials'],
            motions=motions,sourceFresnel=record['sourceFresnel']))
    write_private(output/'SF3_H17_Summons.json',json.dumps(document,separators=(',',':'),allow_nan=False).encode())
    print(json.dumps([dict(id=x['id'],file=x['name'],bytes=x['bytes'],sha256=x['sha256'],clips=len(x['clips']),nodes=x['sourceSkeletonNodes']) for x in result]))


if __name__=='__main__':main()
