#!/usr/bin/env python3
"""Convert verified DFT/Ninjato source geometry privately, with exact skin paths.

Uses the supplied original source bundles and personal-head backup; no network,
credentials, or game executable are used. Raw assets, GLBs, source frames and
candidate catalogs MUST stay outside the repository. Control roles remain
explicit application adaptation. The recovered 60 Hz player uses two ticks
per source-frame interval for default MidFrames=1; exported keys are at 30 FPS.
Original secondary motion arrays are retained.

Math and source-profile compatibility follow the supplied integration backup's
export_distinct_fighters.py. Motion decompression is imported from the reviewed
prepare_fighter_target_motions module, which carries its MIT attribution.
"""
from __future__ import annotations
from pathlib import Path
from zipfile import ZipFile
import argparse, base64, copy, hashlib, io, json, struct, warnings, zlib
import numpy as np
import xml.etree.ElementTree as ET
from prepare_fighter_target_motions import decode_motion, ARCHIVE_SHA256
from sun_triad_source_bones import parse_bones_data, merge_bone_ids, capsule_binding
from sun_triad_materials import original_material, material_descriptor

REPOSITORY = Path(__file__).resolve().parents[1]
PREVIEW_FPS = 30
BUNDLE_FILES = {
    "body": "8c698f01a124be29f09101d5ba3e22e9.bin",
    "helmet": "a7bb4595abac6ca190801afcb30e9ab5.bin",
    "weapon": "9e0ac3ba87e002425eeb76668aab567d.bin",
}
ACTOR_BUNDLE = "00a21255143c2e6368ba9b34e6914d68.bin"
NINJATO_BUNDLE = "2ee15f236c4e114912c05a8561b8c9a3.bin"
H17_BUNDLE = "9893dca6e10355eb9c3c79d1613f08b1.bin"
COMMON = "b9e97e35ddb64ed98261b3baf00829ab.bin"
MODEL_ONLY_CLIPS = {"h17_root_spike_model", "h17_wave_model"}
BASE_ROLES = dict(
    idle="ninjato_stance_idle", enter="ninjato_stance_birth",
    walkForward="m_step_forward", walkBackward="m_step_back",
    guard="b_dualweapon_mid_block", crouch="m_low_stance_idle",
    jump="m_prc_jump_up", hit="h_chest_short_fast", knockdown="h_hit_head_fall",
    getUp="m_stand_up_front_forward", victory="ninjato_stance_win",
    weapon1="ninjato_slash_1", weapon2="ninjato_slash_2", heavy="ninjato_heavy_slash",
    weaponForward="ninjato_super_slash_1", weaponUp="ninjato_upper_slash",
    weaponDown="ninjato_low_slash", weaponBack="ninjato_spinning_slash",
    kick="k_prc_kick_1", kickForward="k_prc_front_kick", kickDown="k_prc_low",
    kickBack="k_prc_spinning_kick", kickJump="k_prc_jump_up",
    shadow="s_ninjato_slash_1_active", shadowStart="s_ninjato_start",
    shadowEnd="s_ninjato_end", shadowPassive="s_ninjato_slash_passive")
PROFILE = dict(id="sun_triad", hero="ember", faction="Herald",
    resourceName="Sun_DeadForestTriad_Ninjato", bodyID="arm__prc_43", helmetID="helm__prc_43",
    weaponID="wpn__ninjato_01_06", bodyBundle=BUNDLE_FILES["body"],
    helmetBundle=BUNDLE_FILES["helmet"], weaponBundle=BUNDLE_FILES["weapon"],
    bodyMeshes=["arm__prc_43_m", "arm__prc_43_m__tie", "helm__prc_43_m"],
    weaponMeshes=["wpn__ninjato_01_06__l", "wpn__ninjato_01_06__r"],
    activeWeaponSides=["left", "right"], personal="Sun_OriginalRig_ActionSet.glb",
    roles=BASE_ROLES, comboLinks=[])
OUT = ROOT = None
CATALOG = []
BUNDLES = {}
BASE_ROWS = []
BONE_CONFIGS = {}
MESH_CULL = {}
MODEL_CONFIG_FILES = {
    'body': ('8c698f01a124be29f09101d5ba3e22e9_-3456081355957107393_config.decoded.clear-private',
             'e647888df0ae2ee71676f085f893bbb543ae5a740c5418c5eba34437295d2532'),
    'weapon': ('9e0ac3ba87e002425eeb76668aab567d_1950985227206358894_config.decoded.clear-private',
               'a81e6496518aa843e08682975f9bb91dba91861553e9ef9cef3d3193390a0c6d'),
}
CONFIG_FILES = {
    'base': ('ipa-553-bones.textasset.clear-private', '0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455'),
    'body': ('8c698f01a124be29f09101d5ba3e22e9_-6441934884723606258_bones.decoded.clear-private', '40f74ca5a754122c431db660182bfd98e4e964c0fc571fdcafdf7071676f2377'),
    'weapon': ('9e0ac3ba87e002425eeb76668aab567d_-705721519862980483_bones.decoded.clear-private', '332a6d6b14122ac59fef7c38ddcc8d54eef7a17d330aef48bc4339ec0372502f'),
    'fullBody': ('ipa-608-bones.textasset.clear-private', '5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8'),
}
C = np.diag([.01, .01, -.01, 1.])
CI = np.linalg.inv(C)
RIGHT = np.eye(4)
RIGHT[:3, :3] = [[0, 0, -1], [0, 1, 0], [1, 0, 0]]


def require(ok, message):
    if not ok:
        raise ValueError(message)


def decode(raw):
    return [dict(frame_count=a["frameCount"], bone_ids=np.array(a["boneIDs"], dtype=np.uint16),
        positions=np.asarray(a["positions"], dtype=np.float32),
        rotations=np.asarray(a["rotations"], dtype=np.float32)) for a in decode_motion(raw)]

def sha(b): return hashlib.sha256(b).hexdigest()

def qmatrix(q):
    q=np.asarray(q,dtype=float);q=q/np.linalg.norm(q);x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
        [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
        [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def quaternion(m):
    # Symmetric eigenproblem is stable at 180 degrees as well as the identity.
    r=m;K=np.array([[r[0,0]-r[1,1]-r[2,2],r[1,0]+r[0,1],r[2,0]+r[0,2],r[2,1]-r[1,2]],
        [r[1,0]+r[0,1],r[1,1]-r[0,0]-r[2,2],r[2,1]+r[1,2],r[0,2]-r[2,0]],
        [r[2,0]+r[0,2],r[2,1]+r[1,2],r[2,2]-r[0,0]-r[1,1],r[1,0]-r[0,1]],
        [r[2,1]-r[1,2],r[0,2]-r[2,0],r[1,0]-r[0,1],np.trace(r)]])/3
    q=np.linalg.eigh(K)[1][:,-1]
    return q if q[3]>=0 else -q

def matrix(p,q,s):
    m=np.eye(4);m[:3,:3]=qmatrix(q)*np.asarray(s);m[:3,3]=p;return m

def glb_read(path):
    raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+size]),raw[28+size:]

def accessor_read(g,b,index):
    a=g['accessors'][index];v=g['bufferViews'][a['bufferView']]
    dt={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
    width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',np.dtype(dt).itemsize*width)
    out=np.ndarray((a['count'],width),dtype=dt,buffer=b,offset=offset,strides=(stride,np.dtype(dt).itemsize)).copy()
    return out[:,0] if width==1 else out

class Writer:
    def __init__(self):
        self.g=dict(asset=dict(version='2.0',generator='Verified original DFT/Ninjato private candidate exporter'),scene=0,
            scenes=[dict(nodes=[])],nodes=[],meshes=[],materials=[],skins=[],textures=[],images=[],
            samplers=[dict(wrapS=10497,wrapT=10497)],bufferViews=[],accessors=[],animations=[])
        self.b=bytearray()
    def block(self,data):
        self.b.extend(b'\0'*(-len(self.b)%4));i=len(self.g['bufferViews'])
        self.g['bufferViews'].append(dict(buffer=0,byteOffset=len(self.b),byteLength=len(data)))
        self.b.extend(data);return i
    def acc(self,data,kind,component=5126):
        a=np.asarray(data,dtype={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}[component])
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[kind]
        require(a.ndim == (1 if width == 1 else 2) and (width == 1 or a.shape[1] == width),
            'Accessor array shape does not match '+kind)
        require(len(a) > 0 and np.isfinite(a).all(), 'Accessor is empty or nonfinite')
        item=dict(bufferView=self.block(a.tobytes()),componentType=component,count=len(a),type=kind)
        if kind in ('SCALAR','VEC3'):item.update(min=np.atleast_1d(a.min(axis=0)).tolist(),max=np.atleast_1d(a.max(axis=0)).tolist())
        i=len(self.g['accessors']);self.g['accessors'].append(item);return i
    def save(self,path):
        self.g['buffers']=[dict(byteLength=len(self.b))]
        validate_container(self.g,self.b)
        j=json.dumps(self.g,separators=(',',':'),allow_nan=False).encode();j+=b' '*(-len(j)%4)
        self.b+=b'\0'*(-len(self.b)%4)
        raw=struct.pack('<4sII',b'glTF',2,28+len(j)+len(self.b))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(self.b),0x004e4942)+self.b
        path.write_bytes(raw);return dict(bytes=len(raw),sha256=sha(raw))


def validate_container(document,binary):
    """Fail before publication if an embedded accessor or mesh layout is invalid."""
    require(len(document.get('buffers',[]))==1, 'Candidate must have one embedded buffer')
    require(document['buffers'][0].get('byteLength')==len(binary)
        and 'uri' not in document['buffers'][0], 'Candidate buffer is not self contained')
    require(not document.get('extensionsRequired'), 'Required custom extensions are unsupported')
    views=document.get('bufferViews',[])
    for view in views:
        start=view.get('byteOffset',0);size=view.get('byteLength',0)
        require(view.get('buffer')==0 and isinstance(start,int) and start>=0
            and isinstance(size,int) and size>0 and start+size<=len(binary), 'Embedded buffer view is out of bounds')
    widths={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
    sizes={5121:1,5123:2,5125:4,5126:4}
    for accessor in document.get('accessors',[]):
        require('sparse' not in accessor and accessor['bufferView'] in range(len(views)), 'Unsupported candidate accessor')
        require(accessor['type'] in widths and accessor['componentType'] in sizes, 'Invalid accessor component type')
        view=views[accessor['bufferView']];width=widths[accessor['type']]*sizes[accessor['componentType']]
        start=accessor.get('byteOffset',0);stride=view.get('byteStride',width);count=accessor['count']
        require(isinstance(count,int) and count>0 and isinstance(start,int) and start>=0
            and stride>=width and start+(count-1)*stride+width<=view['byteLength'], 'Accessor exceeds its embedded buffer view')
    for value in document.get('images',[]):
        require('uri' not in value and value.get('bufferView') in range(len(views))
            and value.get('mimeType') in ('image/png','image/jpeg'), 'Image is not embedded')
    for mesh in document.get('meshes',[]):
        for primitive in mesh['primitives']:
            attributes=primitive['attributes'];count=document['accessors'][attributes['POSITION']]['count']
            require(all(document['accessors'][a]['count']==count for a in attributes.values()), 'Mesh attribute vertex counts differ')
            for name in ('JOINTS_0','WEIGHTS_0'):
                if name in attributes:
                    require(document['accessors'][attributes[name]]['type']=='VEC4', 'Skin attributes require four lanes')
            if 'indices' in primitive:
                indices=accessor_read(document,binary,primitive['indices'])
                require(np.max(indices)<count, 'Mesh index exceeds its source vertex array')
    for skin in document.get('skins',[]):
        require(len(skin['joints'])==document['accessors'][skin['inverseBindMatrices']]['count'], 'Skin inverse bind count differs')

def world_poses(nodes):
    local=[matrix(n.get('translation',[0,0,0]),n.get('rotation',[0,0,0,1]),n.get('scale',[1,1,1])) for n in nodes]
    parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    return pose_world(local,parents),local,parents

def pose_world(local,parents):
    cache={}
    def f(i):
        if i not in cache:cache[i]=(f(parents[i]) if i in parents else np.eye(4))@local[i]
        return cache[i]
    return np.array([f(i) for i in range(len(local))])


def skin_slots(joints,weights):
    """Preserve source lanes and add only zero-weight lanes required by glTF."""
    joints=np.asarray(joints);weights=np.asarray(weights,dtype=float)
    require(joints.shape==weights.shape and weights.ndim==2 and 1<=weights.shape[1]<=4,
        'Unsupported source skin influence layout')
    require(np.isfinite(weights).all() and (weights>=0).all(), 'Invalid source skin weights')
    require(np.issubdtype(joints.dtype,np.integer) and (joints>=0).all() and (joints<=65535).all(),
        'Invalid source skin joint indices')
    sums=weights.sum(axis=1,keepdims=True)
    require(np.max(abs(sums-1))<.001, 'Source skin weight sum mismatch')
    padding=((0,0),(0,4-weights.shape[1]))
    return np.pad(joints,padding),np.pad(weights/sums,padding)


def capsule_point(vertex,world,names):
    """The exact local source vertex, with the same actor basis as limb tracks."""
    local=np.r_[np.asarray(vertex['localPositionCentimeters'])*[.01,.01,-.01],1.]
    return (RIGHT@world[names[vertex['bone']]]@local)[:3]

def copy_personal_head(writer,path,names,new_world):
    old,b=glb_read(path);material_cache={};texture_cache={};image_cache={}
    old_world,_,_=world_poses(old['nodes']);old_names={n['name']:i for i,n in enumerate(old['nodes'])}
    # World matrix outside the matching actor orientation is not baked into vertices.
    old_root=old['scenes'][old.get('scene',0)]['nodes'][0]
    invouter=np.linalg.inv(old_world[old_root])
    differences={n:float(np.max(abs(invouter@old_world[old_names[n]]-new_world[i]))) for n,i in names.items() if n in old_names}
    require(max(differences[n] for n in ('head','neck','pelvis'))<.001, 'Personal head bind hierarchy differs from source actor')
    def im(i):
        if i not in image_cache:
            x=copy.deepcopy(old['images'][i]);v=old['bufferViews'][x['bufferView']]
            x['bufferView']=writer.block(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])
            image_cache[i]=len(writer.g['images']);writer.g['images'].append(x)
        return image_cache[i]
    def tx(i):
        if i not in texture_cache:
            x=copy.deepcopy(old['textures'][i]);x['source']=im(x['source'])
            if 'sampler' in x:
                x['sampler']=len(writer.g['samplers']);writer.g['samplers'].append(copy.deepcopy(old['samplers'][old['textures'][i]['sampler']]))
            texture_cache[i]=len(writer.g['textures']);writer.g['textures'].append(x)
        return texture_cache[i]
    def mat(i):
        if i not in material_cache:
            x=copy.deepcopy(old['materials'][i])
            def remap(d):
                if isinstance(d,dict):
                    for k,v in d.items():
                        if k.endswith('Texture') and isinstance(v,dict) and 'index' in v:v['index']=tx(v['index'])
                        else:remap(v)
                elif isinstance(d,list):
                    for v in d:remap(v)
            remap(x);material_cache[i]=len(writer.g['materials']);writer.g['materials'].append(x)
        return material_cache[i]
    added=[]
    for node in old['nodes']:
        if 'mesh' not in node or not any(s in node['name'] for s in ('Personal_Head','Neck_Bridge')):continue
        mesh=old['meshes'][node['mesh']];prims=[];skin=old['skins'][node['skin']]
        jointmap=np.array([names[old['nodes'][j]['name']] for j in skin['joints']])
        for primitive in mesh['primitives']:
            p=copy.deepcopy(primitive)
            for k,a in primitive['attributes'].items():
                value=accessor_read(old,b,a);info=old['accessors'][a]
                if k=='JOINTS_0':value=jointmap[value];component=5123
                else:component=info['componentType']
                p['attributes'][k]=writer.acc(value,info['type'],component)
            p['indices']=writer.acc(accessor_read(old,b,primitive['indices']),'SCALAR',5125)
            if 'material' in p:p['material']=mat(p['material'])
            prims.append(p)
        m=len(writer.g['meshes']);writer.g['meshes'].append(dict(name=mesh.get('name',node['name']),primitives=prims))
        added.append(len(writer.g['nodes']));writer.g['nodes'].append(dict(name=node['name'],mesh=m,skin=0))
    require(len(added)==2, 'Expected exact personal head and neck meshes')
    return added,dict(sourceFile=path.name,sourceSHA256=sha(path.read_bytes()),headNeckBindMaximumDifference=max(differences[n] for n in ('head','neck','pelvis')),geometryModified=False)


def build(profile):
    print('START',profile['id'],flush=True)
    files=[profile['bodyBundle'],profile['helmetBundle'],profile['weaponBundle']]
    for name in files:
        require(sha((OUT/'source-bundles'/name).read_bytes()) == BUNDLES[name]['sha256'], 'Source bundle hash mismatch')
    env=UnityPy.load(*(str(OUT/'source-bundles'/f) for f in files))
    allmeshes={o.read().m_Name:o.read() for o in env.objects if o.type.name=='Mesh'}
    selected=[allmeshes[n] for n in profile['bodyMeshes']+profile['weaponMeshes']]
    renderers={o.read().m_GameObject.read().m_Name:o.read() for o in env.objects if o.type.name=='SkinnedMeshRenderer'}
    prefix='w_ninjato'
    extra, attachment_audit = source_attachment_rows(env)
    rows=copy.deepcopy(BASE_ROWS)+extra;names={r['name']:i for i,r in enumerate(rows)};paths={};hashes={}
    for r in rows:
        p=r['name'] if r['parent'] in (None,'skeleton') else paths[r['parent']]+'/'+r['name'];paths[r['name']]=p
        h=zlib.crc32(p.encode());require(h not in hashes, 'Source bone path hash collision');hashes[h]=names[r['name']]
    # Match actual source skin hashes, including full weapon subtree paths.
    world_bind={};disagreement=0.;meshdata={};hash_audit=[]
    for mesh in selected:
        h=MeshHandler(mesh);h.process();weights=np.asarray(h.m_BoneWeights,dtype=float);ids=np.asarray(h.m_BoneIndices,dtype=int)
        require(len(mesh.m_BindPose)==len(mesh.m_BoneNameHashes), 'Source skin bind/hash lengths differ')
        remap=np.array([hashes[x] for x in mesh.m_BoneNameHashes])
        used=set(ids[weights>1e-7].tolist())
        for j,(key,b) in enumerate(zip(mesh.m_BoneNameHashes,mesh.m_BindPose)):
            if j not in used:continue
            i=hashes[key];raw=np.array([[getattr(b,f'e{y}{x}') for x in range(4)] for y in range(4)])
            m=np.linalg.inv(C@raw@CI)
            if i in world_bind:disagreement=max(disagreement,float(np.max(abs(m-world_bind[i]))))
            else:world_bind[i]=m
        meshdata[mesh.m_Name]=(h,weights,remap[ids])
        hash_audit.append(dict(mesh=mesh.m_Name,boneHashes=list(mesh.m_BoneNameHashes),matchedPaths=[paths[rows[hashes[x]]['name']] for x in mesh.m_BoneNameHashes],usedJointCount=len(used)))
    require(disagreement<.001, 'Source shared bind matrices disagree')
    writer=Writer();g=writer.g;worlds={}
    for i,row in enumerate(rows):
        parent=names.get(row['parent']);p=worlds[parent] if parent is not None else np.eye(4)
        source=C@matrix(row['translation'],row['rotation'],row['scale'])@CI
        world=world_bind.get(i,p@source);local=np.linalg.inv(p)@world
        scale=np.linalg.norm(local[:3,:3],axis=0);q=quaternion(local[:3,:3]/scale)
        node=dict(name=row['name'],translation=local[:3,3].tolist(),rotation=q.tolist(),scale=scale.tolist())
        children=[j for j,x in enumerate(rows) if x['parent']==row['name']]
        if children:node['children']=children
        g['nodes'].append(node);worlds[i]=world
    invbind=np.array([np.linalg.inv(worlds[i]) for i in range(len(rows))])
    g['skins'].append(dict(name='Original SF3 equipment skin',joints=list(range(len(rows))),skeleton=names['skeleton'],
        inverseBindMatrices=writer.acc([m.T.reshape(16) for m in invbind],'MAT4')))
    mesh_nodes=[];material_cache={};counts=dict(vertices=0,triangles=0)
    for mesh in selected:
        h,weights,joints=meshdata[mesh.m_Name]
        vertices=np.asarray(h.m_Vertices,dtype=float)[:,:3]*[.01,.01,-.01]
        normals=np.asarray(h.m_Normals,dtype=float)[:,:3]*[1,1,-1]
        uv=np.asarray(h.m_UV0,dtype=float)[:,:2];uv[:,1]=1-uv[:,1]
        joints,weights=skin_slots(joints,weights)
        attributes=dict(POSITION=writer.acc(vertices,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),TEXCOORD_0=writer.acc(uv,'VEC2'),
            JOINTS_0=writer.acc(joints,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4'))
        renderer=renderers[mesh.m_Name];primitives=[]
        for j,tri in enumerate(h.get_triangles()):
            indices=np.asarray(tri,dtype=np.uint32).reshape(-1,3)[:,[0,2,1]].reshape(-1)
            if not len(indices):continue
            material=original_material(writer,renderer.m_Materials[min(j,len(renderer.m_Materials)-1)].read(),material_cache,
                                       double_sided_override=MESH_CULL.get(mesh.m_Name))
            primitives.append(dict(attributes=attributes,indices=writer.acc(indices,'SCALAR',5125),material=material));counts['triangles']+=len(indices)//3
        mesh_index=len(g['meshes']);g['meshes'].append(dict(name=mesh.m_Name,primitives=primitives));mesh_nodes.append(len(g['nodes']))
        g['nodes'].append(dict(name=mesh.m_Name,mesh=mesh_index,skin=0));counts['vertices']+=len(vertices)
    personal_nodes,personal_audit=copy_personal_head(writer,OUT/'personal'/profile['personal'],names,worlds)
    mesh_nodes+=personal_nodes
    outer=len(g['nodes']);g['nodes'].append(dict(name='SF3_Actor_Meters',children=[0]+mesh_nodes,scale=[.92]*3,
        rotation=[0,-float(np.sqrt(.5)),0,float(np.sqrt(.5))]));g['scenes'][0]['nodes']=[outer]
    rest_world,rest,parents=world_poses(g['nodes']);basis=RIGHT[:3,:3]@rest_world[parents[names['pelvis']]][:3,:3]
    markers=[]
    for side in ['l','r']:
        foot,toe=names['foot_'+side],names['toe_'+side];a,b=rest_world[foot][:3,3],rest_world[toe][:3,3]
        for x in [min(a[0],b[0])-.055,max(a[0],b[0])+.055]:
            for z in [min(a[2],b[2])-.055,max(a[2],b[2])+.055]:markers.append((foot,np.linalg.inv(rest_world[foot])@[x,-.02,z,1]))
    boneids={i:n for i,n in merge_bone_ids(*BONE_CONFIGS.values()).items() if n in names}
    attack_capsules=BONE_CONFIGS['weapon']['capsules']
    hurt_capsules=BONE_CONFIGS['fullBody']['capsules']
    require(len(attack_capsules)==4 and len(hurt_capsules)==15, 'Source capsule inventory changed')
    for capsule in attack_capsules+hurt_capsules:
        require(all(capsule[end]['bone'] in names for end in ('base','tip')), 'Source capsule is not bound to actor')
    blade_capsules={c['id'][-1]:c for c in attack_capsules if c['id'].startswith('Ninjato_Attacking_Edge_')}
    require(set(blade_capsules)=={'l','r'}, 'Original bilateral blade endpoints missing')
    clips=[];loaders={};clipnames=list(dict.fromkeys(list(profile['roles'].values())+profile['extraClips']))
    for name in clipnames:
        found=[r for r in CATALOG if r['name']==name]
        if name.startswith(('ninjato_', 's_ninjato_')): found=[r for r in found if r['bundle']==NINJATO_BUNDLE]
        elif name.startswith('h17_'): found=[r for r in found if r['bundle']==H17_BUNDLE]
        elif len(found)>1: found=[r for r in found if r['bundle']==COMMON]
        require(len(found)==1, 'Source clip identity is missing or ambiguous: '+name)
        info=found[0]
        if info['bundle'] not in loaders:loaders[info['bundle']]=UnityPy.load(str(OUT/'source-bundles'/info['bundle']))
        source=next(o for o in loaders[info['bundle']].objects if o.path_id==info['path_id']).read().m_Script
        raw=source.encode('utf8','surrogateescape') if isinstance(source,str) else bytes(source)
        require(sha(raw)==info['sha256'], 'Source motion integrity mismatch');arrays=decode(raw)
        require(len(arrays)==2, 'Source motion array count changed')
        motion=arrays[0];frames=motion['frame_count'];require(frames==info['frames'], 'Source motion frame count changed')
        require(all(int(i) in boneids for i in motion['bone_ids']), 'Unbound source motion bone in '+name)
        cols={boneids[int(i)]:j for j,i in enumerate(motion['bone_ids'])}
        anim=dict(name=name,channels=[],samplers=[],extras=dict(sourceSHA256=info['sha256'],sourceFrames=frames,
            sourceFPS=30 if info['bundle'] in (NINJATO_BUNDLE,H17_BUNDLE) else None,
            simulationHz=60,defaultMidFrames=1,previewFPS=30,sourceBytesRetainedInProfile=True))
        times=writer.acc(np.arange(frames)/30.,'SCALAR');positions={};rotations={}
        for target,col in cols.items():
            p=motion['positions'][:,col].astype(float)*[.01,.01,-.01]
            if target=='pelvis':p[:,[0,2]]=0
            q=motion['rotations'][:,col].astype(float)*[-1,-1,1,1];q/=np.linalg.norm(q,axis=1)[:,None]
            for j in range(1,len(q)):
                if q[j-1]@q[j]<0:q[j]*=-1
            positions[target]=p.astype(np.float32).astype(float);rotations[target]=q.astype(np.float32).astype(float)
            for kind,v,width in [('translation',p,'VEC3'),('rotation',q,'VEC4')]:
                sampler=len(anim['samplers']);anim['samplers'].append(dict(input=times,output=writer.acc(v,width),interpolation='LINEAR'))
                anim['channels'].append(dict(sampler=sampler,target=dict(node=names[target],path=kind)))
        g['animations'].append(anim)
        rawroots=motion['positions'][:,cols['pelvis']].astype(float)*[.01,.01,-.01]
        rootdelta=(rawroots-rawroots[0])@basis.T
        tracks={k:[] for k in ['root','handL','handR','footL','footR','weaponBaseL','weaponTipL','weaponBaseR','weaponTipR']};tracks.update(samplesPerSourceFrame=2,groundLift=[])
        collision_edges=[dict(**capsule_binding(c,'attack'),base=[],tip=[]) for c in attack_capsules]
        hurt_shapes=[dict(**capsule_binding(c,'hurt'),base=[],tip=[]) for c in hurt_capsules]
        for sample in range(2*frames-1):
            a=sample//2;b=min(frames-1,a+1);f=(sample%2)/2;local=[m.copy() for m in rest]
            for target in cols:
                p=positions[target][a]*(1-f)+positions[target][b]*f
                qa=rotations[target][a];qb=rotations[target][b]
                q=qa*(1-f)+qb*f;i=names[target]
                local[i]=matrix(p,q,g['nodes'][i].get('scale',[1,1,1]))
            world=pose_world(local,parents)
            tracks['root'].append(rootdelta[a]*(1-f)+rootdelta[b]*f)
            for key,n in [('handL','hand_l'),('handR','hand_r'),('footL','foot_l'),('footR','foot_r')]:tracks[key].append((RIGHT@world[names[n]][:,3])[:3])
            for side,capsule in blade_capsules.items():
                tracks['weaponBase'+side.upper()].append(capsule_point(capsule['base'],world,names))
                tracks['weaponTip'+side.upper()].append(capsule_point(capsule['tip'],world,names))
            for capsule,destination in zip(attack_capsules+hurt_capsules,collision_edges+hurt_shapes):
                for endpoint in ('base','tip'):
                    destination[endpoint].append(capsule_point(capsule[endpoint],world,names))
            low=min((world[foot]@marker)[1] for foot,marker in markers)
            tracks['groundLift'].append(float(max(0.,-.035-low)))
        tracks={k:(np.round(v,7).tolist() if isinstance(v,list) else v) for k,v in tracks.items()}
        for capsule in collision_edges+hurt_shapes:
            for endpoint in ('base','tip'): capsule[endpoint]=np.round(capsule[endpoint],7).tolist()
        tracks.update(collisionEdges=collision_edges,hurtCapsules=hurt_shapes)
        clips.append(dict(name=name,frames=frames,sha256=info['sha256'],bundle=info['bundle'],sourcePathID=str(info['path_id']),
            sourceBytesBase64=base64.b64encode(raw).decode(),sourceArrayCount=2,sourceBoneIDs=[int(x) for x in motion['bone_ids']],tracks=tracks))
        print('CLIP',profile['id'],name,frames,flush=True)
    g['extras']=dict(bodyID=profile['bodyID'],weaponID=profile['weaponID'],activeWeaponSides=profile['activeWeaponSides'],
        sourceBodyBundle=profile['bodyBundle'],sourceWeaponBundle=profile['weaponBundle'],sourceSkinPreserved=True,
        sourceFPS=None,previewFPS=30,horizontalPelvisZeroed=True,sourceGameLogicRecovered=False)
    result=writer.save(OUT/(profile['resourceName']+'.glb'))
    bindings=[dict(name=row['name'],parent=row['parent'],path=paths[row['name']],targetNode=names[row['name']],
        sourceID=next((j for j,n in boneids.items() if n==row['name']),None)) for row in rows]
    audit=dict(id=profile['id'],bodyID=profile['bodyID'],weaponID=profile['weaponID'],sourceMeshes=profile['bodyMeshes']+profile['weaponMeshes'],
        sourceBundles=[dict(file=f,sha256=BUNDLES[f]['sha256'],names=BUNDLES[f]['bundle_names']) for f in files],
        sourceAttachments=attachment_audit, originalBoneBindings=bindings,sourceSkinHashMappings=hash_audit,maximumSharedBindMatrixDifference=disagreement,
        personalPortrait=personal_audit,counts=counts,
        sourceBoneConfigs={k:dict(file=v[0],sha256=v[1]) for k,v in CONFIG_FILES.items()},
        sourceModelConfigs={k:dict(file=v[0],sha256=v[1]) for k,v in MODEL_CONFIG_FILES.items()},
        materials=[material_descriptor(m,g) for m in g['materials']],
        weaponLandmarks={k:dict(sourceCapsule=v['id'],base=v['base'],tip=v['tip']) for k,v in blade_capsules.items()},
        landmarkMethod='Original BonesData vertex local positions, transformed by the exact source bone hierarchy at half frames.',
        collisionEdges=attack_capsules,hurtCapsules=hurt_capsules,
        frames=sum(c['frames'] for c in clips),clips=len(clips),geometrySamples=sum(len(c['tracks']['root']) for c in clips),**result)
    write_private(OUT/(profile['resourceName']+'_provenance.json'),json.dumps(audit,indent=2).encode())
    return dict(id=profile['id'],hero=profile['hero'],faction=profile['faction'],resourceName=profile['resourceName'],
        bodyID=profile['bodyID'],weaponID=profile['weaponID'],activeWeaponSides=profile['activeWeaponSides'],roles=profile['roles'],
        **result,clips=clips,sourceSkinNodeCount=len(rows),sourceBoneBindings=bindings,weaponLandmarks=audit['weaponLandmarks'],
        comboLinks=[{'from':x['from_'],'to':x['to'],'sourceFrame':x['sourceFrame']} for x in profile['comboLinks']])



def source_attachment_rows(env):
    """Attach each original /m/prefabs/ subtree by its SkeletonData parent name."""
    rows, audit = [], []
    for path, pointer in sorted(env.container.items()):
        if '/m/prefabs/' not in path:
            continue
        root = pointer.read()
        transforms, data = [], []
        for component in root.m_Component:
            ref = component.component
            if ref.deref().type.name == 'Transform': transforms.append(ref.read())
            elif ref.deref().type.name == 'MonoBehaviour':
                value = ref.deref().read_typetree()
                if '_parentName' in value: data.append(value)
        require(len(transforms) == 1 and len(data) == 1, 'Source attachment contract missing')
        parent = data[0]['_parentName']
        require(data[0]['_additionalPart'] == 1 and parent in {r['name'] for r in BASE_ROWS}, 'Invalid source attachment root')
        def walk(t, parent_name):
            name=t.m_GameObject.read().m_Name
            rows.append(dict(name=name, parent=parent_name,
                translation=[t.m_LocalPosition.x,t.m_LocalPosition.y,t.m_LocalPosition.z],
                rotation=[t.m_LocalRotation.x,t.m_LocalRotation.y,t.m_LocalRotation.z,t.m_LocalRotation.w],
                scale=[t.m_LocalScale.x,t.m_LocalScale.y,t.m_LocalScale.z]))
            for child in t.m_Children: walk(child.read(), name)
        start=len(rows); walk(transforms[0], parent)
        audit.append(dict(sourcePrefab=path, parent=parent, root=rows[start]['name'], nodes=len(rows)-start))
    require(len(audit) == 3, 'Expected one original armor attachment and two weapon attachments')
    require(len({r['name'] for r in BASE_ROWS+rows}) == len(BASE_ROWS)+len(rows), 'Duplicate skeleton names')
    return rows, audit


def private_output(path):
    require(not path.is_symlink(), 'Output cannot be a symlink')
    path=path.resolve()
    require(path != REPOSITORY and REPOSITORY not in path.parents, 'Raw asset output must be outside the repository')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(not path.is_symlink(), 'Output cannot be a symlink')
    return path


def write_private(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(not path.is_symlink(), 'Output cannot be a symlink')
    path.write_bytes(data); path.chmod(0o600)


def stage_inputs(args):
    global OUT, ROOT, CATALOG, BUNDLES, BASE_ROWS, BONE_CONFIGS, MESH_CULL, UnityPy, MeshHandler
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    OUT=private_output(args.output); ROOT=OUT
    warnings.filterwarnings('ignore', category=Warning, module='UnityPy')
    require(UnityPy.__version__ == '1.25.4', 'Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1'
    BONE_CONFIGS={}
    MESH_CULL={}
    for kind,(name,digest) in MODEL_CONFIG_FILES.items():
        raw=(args.models/name).read_bytes()
        require(sha(raw)==digest and b'<!DOCTYPE' not in raw and b'<!ENTITY' not in raw,
                'Original ModelObject identity mismatch: '+kind)
        for mesh in ET.fromstring(raw).findall('./Meshes/Mesh'):
            if mesh.get('CullMode') is not None:
                require(mesh.get('CullMode') in ('true','false'), 'Unknown original mesh cull override')
                MESH_CULL[mesh.get('Name')]=mesh.get('CullMode')=='false'
    for kind,(name,digest) in CONFIG_FILES.items():
        raw=(args.models/name).read_bytes()
        require(sha(raw)==digest, 'Original BonesData identity mismatch: '+kind)
        BONE_CONFIGS[kind]=parse_bones_data(raw)
    write_private(OUT/'source-body-capsules.json',json.dumps(BONE_CONFIGS['fullBody']['capsules'],indent=2).encode())
    require(sha(args.motion_archive.read_bytes()) == ARCHIVE_SHA256, 'Source archive identity mismatch')
    with ZipFile(args.motion_archive) as archive:
        CATALOG=json.loads(archive.read('research/motion_catalog.json'))['motions']
        BUNDLES={r['file']:r for r in map(json.loads,archive.read('research/android_bundle_catalog.jsonl').splitlines())}
        target=[r for r in CATALOG if r['bundle'] == NINJATO_BUNDLE or (r['bundle'] == H17_BUNDLE and r['name'].startswith('h17_'))]
        require(sum(r['bundle']==NINJATO_BUNDLE for r in target)==24 and sum(r['bundle']==H17_BUNDLE for r in target)==23, 'Target motion inventory changed')
        PROFILE['extraClips']=sorted([r['name'] for r in target if r['name'] not in MODEL_ONLY_CLIPS]+['k_prc_kick_2'])
        wanted=set(PROFILE['roles'].values())|set(PROFILE['extraClips'])
        chosen=[r for r in CATALOG if r['name'] in wanted]
        bundle_names={r['bundle'] for r in chosen}
        for name in sorted(bundle_names):
            raw=archive.read('bundles/'+name)
            require(sha(raw)==BUNDLES[name]['sha256'], 'Motion bundle integrity mismatch')
            write_private(OUT/'source-bundles'/name,raw)
        write_private(OUT/'source-model-motion-inventory.json', json.dumps([r for r in target if r['name'] in MODEL_ONLY_CLIPS],indent=2).encode())
    for name in BUNDLE_FILES.values():
        raw=(args.models/name).read_bytes()
        require(sha(raw)==BUNDLES[name]['sha256'], 'Model bundle integrity mismatch')
        write_private(OUT/'source-bundles'/name,raw)
    with ZipFile(args.personal_backup) as archive:
        original=archive.read('OriginalRigReview/characters/Sun_OriginalRig_ActionSet.glb')
        require(sha(original)=='b38d30c4e3afd3bc94b9e62ed40964e8d6fe70548a0f29576dfe07665a2451df','Personal source identity mismatch')
        write_private(OUT/'personal'/PROFILE['personal'],original)
        actor=archive.read('OriginalRigReview/android_bundles/'+ACTOR_BUNDLE)
        require(sha(actor)==BUNDLES[ACTOR_BUNDLE]['sha256'],'Actor skeleton source identity mismatch')
        write_private(OUT/'source-bundles'/ACTOR_BUNDLE,actor)
    env=UnityPy.load(actor)
    candidates=[(path,pointer) for path,pointer in env.container.items() if path.endswith('/skeleton.prefab')]
    require(len(candidates)==1,'Source actor prefab missing or ambiguous')
    root=candidates[0][1].read()
    transform=next(c.component.read() for c in root.m_Component if c.component.deref().type.name=='Transform')
    BASE_ROWS=[]
    def walk(t,parent):
        name=t.m_GameObject.read().m_Name
        BASE_ROWS.append(dict(name=name,parent=parent,
            translation=[t.m_LocalPosition.x,t.m_LocalPosition.y,t.m_LocalPosition.z],
            rotation=[t.m_LocalRotation.x,t.m_LocalRotation.y,t.m_LocalRotation.z,t.m_LocalRotation.w],
            scale=[t.m_LocalScale.x,t.m_LocalScale.y,t.m_LocalScale.z]))
        for child in t.m_Children:walk(child.read(),name)
    walk(transform,None)
    require(len(BASE_ROWS)==64 and len({r['name'] for r in BASE_ROWS})==64,'Source actor hierarchy changed')
    write_private(OUT/'source-actor-skeleton.json',json.dumps(BASE_ROWS,indent=2).encode())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',type=Path,required=True)
    parser.add_argument('--motion-archive',type=Path,required=True)
    parser.add_argument('--personal-backup',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();stage_inputs(args)
    profile=build(PROFILE)
    profile['candidateOnly']=True
    profile['sourceFramesPerSecond']=None
    profile['previewFramesPerSecond']=PREVIEW_FPS
    profile['simulationTicksPerSecond']=60
    profile['defaultSourceFrameStride']=2
    profile['roleBindingBasis']='applicationAdaptation; source animation identity and skinning preserved'
    profile['notYetBoundModelOnlyClips']=sorted(MODEL_ONLY_CLIPS)
    write_private(OUT/(PROFILE['resourceName']+'_profile.json'),json.dumps(profile,separators=(',',':'),allow_nan=False).encode())
    for path in OUT.rglob('*'):
        if path.is_file():path.chmod(0o600)
    print(json.dumps(dict(output=profile['resourceName'],bytes=profile['bytes'],sha256=profile['sha256'],clips=len(profile['clips']),nodes=profile['sourceSkinNodeCount'])))


if __name__=='__main__':
    main()
