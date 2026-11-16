#!/usr/bin/env python3
"""Build Liu's exact D13 equipment rig from verified local originals.

No download, executable, credential or release activation is used. Original
geometry, skin weights, attachment paths and material properties are retained.
Portable paint previews do not claim parity with the original game's shaders.
The source helmet's Headless flag excludes the supplied personal head/neck
from the active scene while preserving both meshes in the private container.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import warnings
import xml.etree.ElementTree as ET
import zlib

import numpy as np

from build_erlang_source_assets import (source_actor_rows, walk_transform,
    checked, encoded, write_new, record)
from sun_triad_assets import (C, CI, Writer, matrix, quaternion, require,
    skin_slots, copy_personal_head, private_output, glb_read, accessor_read,
    world_poses)
from sun_triad_materials import original_material, material_descriptor
from sun_triad_source_bones import parse_bones_data, merge_bone_ids

ID = 'liu_serpent'
RESOURCE = 'Liu_KingOfSerpents_D13'
ACTOR = '00a21255143c2e6368ba9b34e6914d68.bin'
BODY = '33f20d1e8d0d3b0593bd9563d6a6b8f3.bin'
HELMET = 'adec8ebcda70a8d831c9872b12ac1272.bin'
WEAPON = '509ae228a7ddaa97d6a92331cb989b7b.bin'
RANGED = '09a5f73658bc9459c2d713179b29e6dd.bin'
BUNDLES = {
    ACTOR: (266129, 'a4d032522e8fa3dc612c663ecb7f1aa094fe9bc4719c939c45fd558fca8e39a9'),
    BODY: (1925946, '3e0100bd0c65759be4beb639b67150cb117fdc6b129e1785cd8fcaf6e806dde0'),
    HELMET: (455947, '9a7f69be76751c7626bd8b7940f20bdb3beb1dc6b8c65c65fa37fa77e58cf1cc'),
    WEAPON: (189246, '993cd59c754c90dcc5dff46c6929b87b6e59de7acbac072c981f430d6d68a648'),
    RANGED: (154174, '30877397f0d4b59ec5ad0eb01f52ee32b8c40cd263956bd1c79997ad4805f0a6'),
}
MODELS = {
    'body': ('33f20d1e8d0d3b0593bd9563d6a6b8f3_-5066676249466010276_config.clear-private.xml',
             'df14380ae42c3bee9e1c0799f9170f51f238b568d451cf484ad03ccb82a1c1ba'),
    'helmet': ('adec8ebcda70a8d831c9872b12ac1272_-402830455048276887_config.clear-private.xml',
               'd78a4adebbea8eabfdad0cf71de8b64e39605c123591f473727ab0d617f099aa'),
    'weapon': ('509ae228a7ddaa97d6a92331cb989b7b_8493771529340866185_config.clear-private.xml',
               'c7d55c8fbb7cb4dcf123083639dacd135c74b42ed75a9ddb8163dc67b1a057cd'),
    'ranged': ('09a5f73658bc9459c2d713179b29e6dd_1061108968865333557_config.clear-private.xml',
               'd207a8bb90dce8e1dbfee9c52fdd205bf0e12264ae98094b5611e143585ef249'),
}
BONES = {
    'base': ('ipa-553-bones.textasset.clear-private', '0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455'),
    'fullBody': ('ipa-608-bones.textasset.clear-private', '5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8'),
    'weapon': ('509ae228a7ddaa97d6a92331cb989b7b_-36908952542684329_bones.clear-private.xml',
               '5cd22c90e646691488f13a69d04cd68e1a6253a8b6adb5a9b13a87c7bf57f7fd'),
    'ranged': ('09a5f73658bc9459c2d713179b29e6dd_3023681611663319945_bones.clear-private.xml',
               'c056c2b4eadbe10669ef6e40548abf6dabf1675294f601827f085f1757dbceaa'),
}
PERSONAL = ('Liu_OriginalRig_ActionSet.glb', '16381ae1b4d3a8c291ceb883a9bd83474655d90d8e63dcaf1296344a3e3f40d5')
MESHES = {
    BODY: ('arm__agl_41_m', 'arm__agl_41_m_tabard', 'arm__agl_41_m_tie_down', 'arm__agl_41_m_tie_up'),
    HELMET: ('helm__agl_41_m',),
    WEAPON: ('wpn__shuangou_01_04__l', 'wpn__shuangou_01_04__r'),
}
ATTACK_CAPSULES = {'Shuangou_Attacking_Edge_l', 'Shuangou_Attacking_Edge_r',
                   'Shuangou_Handle_Attacking_Edge_l', 'Shuangou_Handle_Attacking_Edge_r'}


def load_models(directory):
    models = {}
    for kind, (name, digest) in MODELS.items():
        raw = checked(directory/name, digest, 100_000)
        require(b'<!DOCTYPE' not in raw and b'<!ENTITY' not in raw, 'External XML is unsupported')
        root = ET.fromstring(raw)
        require(root.tag == 'ModelObject', 'Expected original ModelObject')
        models[kind] = root
    require([(m.get('Name'), m.get('Headless')) for m in models['helmet'].findall('./Meshes/Mesh')]
            == [('helm__agl_41_m', '1')], 'Original helmet headless contract differs')
    require([m.get('Name') for m in models['body'].findall('./Meshes/Mesh')] == list(MESHES[BODY]),
            'Original male armor mesh order differs')
    require([m.get('Name') for m in models['weapon'].findall('./Meshes/Mesh')]
            == list(MESHES[WEAPON])+['wpn__shuangou_01_04__trail_l','wpn__shuangou_01_04__trail_r'],
            'Original dual-hook and trail selection differs')
    return models


def load_bones(directory, shared):
    configs = {}
    for kind, (name, digest) in BONES.items():
        root = shared if kind in ('base', 'fullBody') else directory
        configs[kind] = parse_bones_data(checked(root/name, digest, 100_000))
    require({c['id'] for c in configs['weapon']['capsules']} == ATTACK_CAPSULES
            and len(configs['fullBody']['capsules']) == 15, 'Source collision inventory differs')
    return configs


def attachment_rows(environment, base):
    rows, receipts = [], []
    for path, pointer in sorted(environment.container.items()):
        if '/m/prefabs/' not in path:
            continue
        game = pointer.read(); transforms, data = [], []
        for component in game.m_Component:
            p = component.component
            if p.type.name == 'Transform':
                transforms.append(p.read())
            elif p.type.name == 'MonoBehaviour':
                value = p.read_typetree()
                if '_parentName' in value:
                    data.append(value)
        require(len(transforms) == len(data) == 1 and data[0]['_additionalPart'] == 1,
                'Original hook attachment metadata differs')
        parent = data[0]['_parentName']
        require(parent in ('weapon_l','weapon_r'), 'Hook must attach to its original weapon node')
        start = len(rows); walk_transform(transforms[0], parent, rows)
        receipts.append(dict(prefab=path, parent=parent, root=rows[start]['name'], nodes=len(rows)-start))
    require(len(receipts) == 2 and {x['parent'] for x in receipts} == {'weapon_l','weapon_r'}
            and len(rows) == 16 and len({r['name'] for r in base+rows}) == len(base)+len(rows)
            and {r['name'] for r in rows if r['name'].startswith('Collider_')} == {'Collider_l','Collider_r'},
            'Expected bilateral hook subtrees including the two original collider nodes')
    return rows, receipts


def source_mesh_transform(renderer):
    game=renderer.m_GameObject.read()
    transforms=[c.component.read() for c in game.m_Component if c.component.type.name=='Transform']
    require(len(transforms)==1 and transforms[0].m_Father.m_PathID==0,
            'Expected an independent original mesh prefab transform')
    t=transforms[0]
    return C @ matrix([t.m_LocalPosition.x,t.m_LocalPosition.y,t.m_LocalPosition.z],
        [t.m_LocalRotation.x,t.m_LocalRotation.y,t.m_LocalRotation.z,t.m_LocalRotation.w],
        [t.m_LocalScale.x,t.m_LocalScale.y,t.m_LocalScale.z]) @ CI


def source_weights(mesh, handler):
    """Decode Unity's index-only OneBone layout without inventing a fallback.

    Unity 6000 SkinWeights.OneBone explicitly stores only indices, weight=1:
    https://docs.unity3d.com/6000.0/Documentation/ScriptReference/SkinWeights.OneBone.html
    This branch requires that exact serialized channel layout and one bind bone.
    """
    ids=np.asarray(handler.m_BoneIndices,dtype=int)
    if handler.m_BoneWeights is None:
        channels=mesh.m_VertexData.m_Channels
        require(mesh.m_Name in MESHES[WEAPON] and len(mesh.m_BindPose)==1
                and ids.shape==(len(handler.m_Vertices),1) and np.all(ids==0)
                and channels[12].dimension==0 and channels[13].dimension==1,
                'Absent weights are only allowed for the exact original OneBone hook layout')
        return np.ones(ids.shape,dtype=float),ids,'UnityOneBoneImplicitUnitWeight'
    return np.asarray(handler.m_BoneWeights,dtype=float),ids,'OriginalStoredWeights'


def build_geometry(load, models, configs, personal):
    from UnityPy.helpers.MeshHelper import MeshHandler
    base = source_actor_rows(load(ACTOR)); extra, attachments = attachment_rows(load(WEAPON), base)
    rows = base+extra; names = {r['name']:i for i,r in enumerate(rows)}
    paths, hashes = {}, {}
    for row in rows:
        path = row['name'] if row['parent'] in (None,'skeleton') else paths[row['parent']]+'/'+row['name']
        paths[row['name']] = path; key = zlib.crc32(path.encode())
        require(key not in hashes, 'Source skeleton path hash collision')
        hashes[key] = names[row['name']]
    selected, renderers = [], {}
    for bundle, wanted in MESHES.items():
        environment = load(bundle)
        meshes = {o.read().m_Name:o.read() for o in environment.objects if o.type.name == 'Mesh'}
        for name in wanted:
            require(name in meshes, 'Exact source mesh missing: '+name)
            selected.append(meshes[name])
        for obj in environment.objects:
            if obj.type.name == 'SkinnedMeshRenderer':
                value = obj.read(); name = value.m_GameObject.read().m_Name
                if name in wanted:
                    require(name not in renderers, 'Duplicate source renderer')
                    renderers[name] = value
    require(len(selected) == len(renderers) == 7, 'Expected four armor, one helmet and two hook meshes')
    world_bind, mesh_data, mapping = {}, {}, []; disagreement = 0.
    for mesh in selected:
        h = MeshHandler(mesh); h.process()
        weights,ids,weight_layout=source_weights(mesh,h)
        mesh_transform=source_mesh_transform(renderers[mesh.m_Name])
        require(len(mesh.m_BindPose) == len(mesh.m_BoneNameHashes)
                and all(key in hashes for key in mesh.m_BoneNameHashes), 'Source skin hash/bind mismatch')
        remap = np.array([hashes[key] for key in mesh.m_BoneNameHashes])
        used = set(ids[weights > 1e-7].tolist())
        for j,(key,bind) in enumerate(zip(mesh.m_BoneNameHashes,mesh.m_BindPose)):
            if j not in used: continue
            i = hashes[key]
            raw = np.array([[getattr(bind,f'e{y}{x}') for x in range(4)] for y in range(4)])
            # Unity's bind pose is bone.worldToLocal * mesh.localToWorld.
            # Two source cloth meshes have a real -90deg X prefab rotation.
            # Move both their vertices and inverse binds into actor space.
            world = mesh_transform @ np.linalg.inv(C @ raw @ CI)
            if i in world_bind: disagreement = max(disagreement,float(np.max(abs(world-world_bind[i]))))
            else: world_bind[i] = world
        mesh_data[mesh.m_Name] = (h,weights,remap[ids],mesh_transform)
        mapping.append(dict(mesh=mesh.m_Name,boneHashes=list(mesh.m_BoneNameHashes),
            sourceMeshToActorTransform=mesh_transform.tolist(),sourceWeightLayout=weight_layout,
            matchedPaths=[paths[rows[hashes[key]]['name']] for key in mesh.m_BoneNameHashes]))
    require(disagreement < .001, 'Original shared skin bind poses disagree')
    writer = Writer(); g = writer.g; worlds = {}
    g['asset']['generator'] = 'Verified original D13 King of Serpents equipment and supplied Liu portrait'
    for i,row in enumerate(rows):
        parent = names.get(row['parent']); p = worlds[parent] if parent is not None else np.eye(4)
        source = C @ matrix(row['translation'],row['rotation'],row['scale']) @ CI
        world = world_bind.get(i,p @ source); local = np.linalg.inv(p) @ world
        scale = np.linalg.norm(local[:3,:3],axis=0)
        node = dict(name=row['name'],translation=local[:3,3].tolist(),
            rotation=quaternion(local[:3,:3]/scale).tolist(),scale=scale.tolist())
        children = [j for j,x in enumerate(rows) if x['parent'] == row['name']]
        if children: node['children'] = children
        g['nodes'].append(node); worlds[i] = world
    g['skins'].append(dict(name='Original D13 equipment skin',joints=list(range(len(rows))),
        skeleton=names['skeleton'],inverseBindMatrices=writer.acc(
            [np.linalg.inv(worlds[i]).T.reshape(16) for i in range(len(rows))],'MAT4')))
    overrides = {}
    for root in models.values():
        for mesh in root.findall('./Meshes/Mesh'):
            if mesh.get('CullMode') is not None:
                require(mesh.get('CullMode') in ('true','false'), 'Unknown original cull override')
                overrides[mesh.get('Name')] = mesh.get('CullMode') == 'false'
    mesh_nodes, materials = [], {}; counts = dict(sourceVertices=0,sourceTriangles=0)
    for mesh in selected:
        h,weights,joints,mesh_transform = mesh_data[mesh.m_Name]
        vertices = np.asarray(h.m_Vertices,float)[:,:3]*[.01,.01,-.01]
        normals = np.asarray(h.m_Normals,float)[:,:3]*[1,1,-1]
        vertices=vertices @ mesh_transform[:3,:3].T+mesh_transform[:3,3]
        normals=normals @ np.linalg.inv(mesh_transform[:3,:3])
        normals/=np.linalg.norm(normals,axis=1)[:,None]
        uv = np.asarray(h.m_UV0,float)[:,:2]; uv[:,1] = 1-uv[:,1]
        joints,weights = skin_slots(joints,weights)
        attributes = dict(POSITION=writer.acc(vertices,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),
            TEXCOORD_0=writer.acc(uv,'VEC2'),JOINTS_0=writer.acc(joints,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4'))
        renderer = renderers[mesh.m_Name]; primitives = []
        require(len(renderer.m_Materials) == len(mesh.m_SubMeshes), 'Source renderer/submesh material count differs')
        for j,triangles in enumerate(h.get_triangles()):
            indices = np.asarray(triangles,np.uint32).reshape(-1,3)[:,[0,2,1]].reshape(-1)
            require(len(indices)>0, 'Unexpected empty source submesh')
            material = original_material(writer,renderer.m_Materials[j].read(),materials,
                double_sided_override=overrides.get(mesh.m_Name))
            primitives.append(dict(attributes=attributes,indices=writer.acc(indices,'SCALAR',5125),material=material))
            counts['sourceTriangles'] += len(indices)//3
        m = len(g['meshes']); g['meshes'].append(dict(name=mesh.m_Name,primitives=primitives))
        mesh_nodes.append(len(g['nodes']));g['nodes'].append(dict(name=mesh.m_Name,mesh=m,skin=0))
        counts['sourceVertices'] += len(vertices)
    personal_nodes, personal_receipt = copy_personal_head(writer,personal,names,worlds)
    # Original helmet Headless=1 is a real source policy. Keep the identity mesh
    # recoverable, but do not intersect it with the closed source helmet.
    for index in personal_nodes:
        g['nodes'][index]['extras'] = dict(excludedFromActiveSceneBySourceHelmetHeadless=True)
    outer = len(g['nodes'])
    g['nodes'].append(dict(name='SF3_Actor_Meters',children=[0]+mesh_nodes,scale=[.92]*3,
        rotation=[0,-float(np.sqrt(.5)),0,float(np.sqrt(.5))]))
    g['scenes'][0]['nodes'] = [outer]
    bone_ids = {i:n for i,n in merge_bone_ids(configs['base'],configs['fullBody'],configs['weapon']).items() if n in names}
    bindings = [dict(name=r['name'],parent=r['parent'],path=paths[r['name']],targetNode=names[r['name']],
        sourceID=next((i for i,n in bone_ids.items() if n==r['name']),None)) for r in rows]
    receipt = dict(schema='serpent-original-geometry-v1',id=ID,hero='liu',setID='D13',
        bodyID='arm__agl_41',helmetID='helm__agl_41',weaponID='wpn__shuangou_01_04',rangedID='rng__bottle_01_02',
        activeWeaponSides=['left','right'],originalActorNodeCount=len(base),originalAttachmentNodeCount=len(extra),
        originalBoneBindings=bindings,sourceAttachments=attachments,sourceSkinHashMappings=mapping,
        maximumSharedBindMatrixDifference=disagreement,counts=counts,sourceMeshes=[m.m_Name for m in selected],
        personalPortrait=dict(**personal_receipt,sourceHeadless=True,activeInScene=False,preservedMeshNodes=personal_nodes),
        sourceMeshFlags={kind:[dict(m.attrib) for m in root.findall('./Meshes/Mesh')] for kind,root in models.items()},
        sourceCapsules=configs['weapon']['capsules'],materials=[material_descriptor(m,g) for m in g['materials']],
        originalMaterialShaderParity=False,clothSimulationRecovered=False,
        rangedPropOrTrailActivated=False,originalGameLogicRecovered=False,nativeRendered=False,
        productionCharacterActivated=False,testFlightUploaded=False)
    g['extras'] = dict(id=ID,setID='D13',bodyID=receipt['bodyID'],helmetID=receipt['helmetID'],
        weaponID=receipt['weaponID'],sourceSkinPreserved=True,sourceHelmetHeadless=True,
        personalHeadPreserved=True,originalShaderParity=False,sourceOnly=True)
    return writer,names,bone_ids,receipt


def readback(path, receipt):
    g,b = glb_read(path); worlds,_,_ = world_poses(g['nodes'])
    skin = g['skins'][0]; matrices = accessor_read(g,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    root = g['scenes'][0]['nodes'][0]; inverse_outer = np.linalg.inv(worlds[root])
    maximum = max(float(np.max(abs(inverse_outer @ worlds[node] @ matrices[i]-np.eye(4))))
                  for i,node in enumerate(skin['joints']))
    active=set()
    def visit(i):
        require(i not in active,'Scene tree contains a cycle or repeated node');active.add(i)
        for j in g['nodes'][i].get('children',[]):visit(j)
    visit(root)
    require(maximum < .00002 and len(skin['joints'])==80,'Exported skin bind readback differs')
    require(len([i for i in active if 'mesh' in g['nodes'][i]])==7
            and not (set(receipt['personalPortrait']['preservedMeshNodes']) & active),
            'Source headless helmet scene selection differs')
    return dict(inverseBindMaximumDifference=maximum,activeMeshCount=7,preservedInactivePersonalMeshCount=2,
        nodeCount=len(g['nodes']),meshCount=len(g['meshes']),jointCount=80,animations=len(g['animations']))


def build(args):
    import UnityPy
    require(not args.output.exists(),'Use a fresh private output directory')
    require(UnityPy.__version__=='1.25.4','Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1';warnings.filterwarnings('ignore',module='UnityPy')
    models=load_models(args.configs);configs=load_bones(args.configs,args.shared_bones)
    personal=args.configs/PERSONAL[0];checked(personal,PERSONAL[1],8_000_000)
    cache={}
    def load(name):
        if name not in cache:
            path=args.actor if name==ACTOR else args.source_bundles/name
            size,digest=BUNDLES[name];raw=checked(path,digest,size)
            require(len(raw)==size,'Exact source bundle size differs');cache[name]=UnityPy.load(raw)
        return cache[name]
    # The ranged object is an independent projectile rig, not an attachment to
    # the actor. Verify its bytes without silently grafting it onto the body.
    load(RANGED)
    writer,names,bone_ids,receipt=build_geometry(load,models,configs,personal)
    out=private_output(args.output);model=out/(RESOURCE+'_Static_Source.glb')
    writer.save(model);model.chmod(0o600)
    receipt.update(character=record(model),readback=readback(model,receipt),
        sourceBundles=[dict(file=n,bytes=size,sha256=digest) for n,(size,digest) in BUNDLES.items()],
        sourceModels={k:dict(file=n,sha256=d) for k,(n,d) in MODELS.items()},
        sourceBones={k:dict(file=n,sha256=d) for k,(n,d) in BONES.items()})
    write_new(out/'receipt-private.json',encoded(receipt))
    print(json.dumps(dict(output=str(out),character=receipt['character'],readback=receipt['readback'],
        counts=receipt['counts'],productionCharacterActivated=False),indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('source-bundles','configs','shared-bones','actor','output'):
        parser.add_argument('--'+key,type=Path,required=True)
    build(parser.parse_args())


if __name__=='__main__':main()
