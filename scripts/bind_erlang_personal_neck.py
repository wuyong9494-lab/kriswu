#!/usr/bin/env python3
"""Add an explicitly generated personal neck bridge; preserve the whole face.

The supplied portrait has no usable neck segment. Every original portrait
vertex, normal, UV, index, and image remains byte-identical. A small separate
mesh follows the actual source neck/head joints in their original bind space.
It is an application fitting adaptation, not recovered D15 source geometry.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from sun_triad_assets import Writer, accessor_read, glb_read, private_output, require, world_poses


def skin_color(g,b,primitive):
    material=g['materials'][primitive['material']]
    pbr=material['pbrMetallicRoughness']
    image=g['images'][g['textures'][pbr['baseColorTexture']['index']]['source']]
    view=g['bufferViews'][image['bufferView']]
    raw=bytes(b[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])
    pixels=np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'))
    positions=accessor_read(g,b,primitive['attributes']['POSITION'])
    uv=accessor_read(g,b,primitive['attributes']['TEXCOORD_0'])
    # Sample the original lower side/back skin, away from the mouth, eyes and
    # hair. This derives a plain bridge colour; it never changes the portrait.
    selected=(positions[:,1]>=.015)&(positions[:,1]<=.095)&(positions[:,2]<.025)
    require(int(selected.sum())>=20,'No bounded original skin-colour region')
    coords=np.mod(uv[selected],1.)
    x=np.minimum(pixels.shape[1]-1,(coords[:,0]*pixels.shape[1]).astype(int))
    y=np.minimum(pixels.shape[0]-1,(coords[:,1]*pixels.shape[0]).astype(int))
    srgb=np.median(pixels[y,x],axis=0)/255.
    linear=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
    require(np.isfinite(linear).all() and np.min(srgb)>.1,'Original sampled skin colour is unavailable')
    return linear.tolist(),dict(originalMaterial=material.get('name'),textureSHA256=sha(raw),
        sampledOriginalVertices=int(selected.sum()),medianSRGB=srgb.tolist(),linearBaseColor=linear.tolist())


def bridge(neck):
    # These dimensions are declared fitting choices, not original SF3 rules.
    upper=.055;lower=float(neck[1])-.025
    require(-.25<lower<-.08,'Source neck/head distance is outside the fitting scope')
    vertices=[];weights=[];joints=[]
    rings,segments=7,32
    for row in range(rings):
        t=row/(rings-1);height=lower+(upper-lower)*t
        radius_x=.060*(1-t)+.050*t;radius_z=.049*(1-t)+.043*t
        center=np.array(neck[:3])*(1-t)+np.array([0.,upper,.018])*t;center[1]=height
        h=t*t*(3-2*t)
        for col in range(segments):
            angle=2*np.pi*col/segments
            vertices.append(center+[radius_x*np.cos(angle),0,radius_z*np.sin(angle)])
            weights.append([h,1-h,0,0]);joints.append([0,1,0,0])
    triangles=[]
    for row in range(rings-1):
        for col in range(segments):
            a=row*segments+col;b=row*segments+(col+1)%segments;c=a+segments;d=b+segments
            triangles.extend([(a,c,b),(b,c,d)])
    for row,top in [(0,False),(rings-1,True)]:
        center=np.mean(vertices[row*segments:(row+1)*segments],axis=0)
        index=len(vertices);vertices.append(center);weights.append([int(top),int(not top),0,0]);joints.append([0,1,0,0])
        for col in range(segments):
            a=row*segments+col;b=row*segments+(col+1)%segments
            triangles.append((index,b,a) if top else (index,a,b))
    positions=np.asarray(vertices,dtype=np.float32);faces=np.asarray(triangles,dtype=np.uint32)
    normals=np.zeros_like(positions)
    for face in faces:
        a,b,c=positions[face];n=np.cross(b-a,c-a)
        for i in face:normals[i]+=n
    lengths=np.linalg.norm(normals,axis=1)
    require((lengths>1e-8).all(),'Degenerate personal bridge geometry')
    normals/=lengths[:,None]
    weights=np.asarray(weights,dtype=np.float32)
    require(np.max(abs(weights.sum(1)-1))<1e-7,'Invalid personal bridge weights')
    return positions,normals,faces,weights,np.asarray(joints,dtype=np.uint16)


def bind(args):
    raw=checked(args.profile,args.profile_sha256,48_000_000);profile=json.loads(raw)
    model=args.profile.parent/(profile['resourceName']+'.glb')
    checked(model,profile['sha256'],48_000_000)
    require(profile['id']=='wuyong_erlang' and len(profile['clips']) in (55,56)
            and 'imperialHeavyPassiveMirrored' in profile['roles'],'Expected source mirror candidate')
    g,b=glb_read(model);before=copy.deepcopy(g)
    writer=Writer();writer.g=g;writer.b=bytearray(b[:g['buffers'][0]['byteLength']]);original_binary=bytes(writer.b)
    names={n.get('name'):i for i,n in enumerate(g['nodes'])}
    require('Personal_Neck_Bridge' not in names,'Personal bridge already exists')
    portrait=names['WuYong_Personal_Head'];head=names['head'];neck=names['neck']
    require(portrait in g['nodes'][head].get('children',[]) and 'skin' not in g['nodes'][portrait],
            'Original rigid portrait binding differs')
    world,_,_=world_poses(g['nodes']);placement=world[portrait]
    neck_local=np.linalg.inv(placement)@world[neck][:,3]
    primitives=g['meshes'][g['nodes'][portrait]['mesh']]['primitives']
    require(len(primitives)==1,'Unexpected portrait primitive inventory')
    color,material_source=skin_color(g,b,primitives[0])
    positions,normals,faces,weights,joints=bridge(neck_local)
    outer=names['SF3_Actor_Meters'];local=np.linalg.inv(world[outer])@placement
    # Use the same original skin as the six body meshes. Only its head/neck
    # slots receive weights. A second skin with a different bind-shape matrix
    # can make importers reinterpret shared bone binds and move a rigid child.
    # Bake the generated bridge into that existing actor bind space instead.
    require(len(g['skins'])==1,'Expected the unchanged original actor skin')
    source_skin=g['skins'][0]
    slots=[source_skin['joints'].index(i) for i in (head,neck)]
    original_inverse=accessor_read(g,b,source_skin['inverseBindMatrices'])
    for node,slot in zip((head,neck),slots):
        expected=np.linalg.inv(np.linalg.inv(world[outer])@world[node])
        require(np.max(abs(original_inverse[slot].reshape(4,4).T-expected))<.001,
                'Original actor inverse bind differs')
    positions=(np.c_[positions,np.ones(len(positions))]@local.T)[:,:3].astype(np.float32)
    normals=normals@np.linalg.inv(local[:3,:3]);normals/=np.linalg.norm(normals,axis=1)[:,None]
    joints[:,0]=slots[0];joints[:,1]=slots[1]
    material=len(g['materials']);g['materials'].append(dict(name='Personal_Neck_Bridge_Derived_Skin',
        pbrMetallicRoughness=dict(baseColorFactor=color+[1.],metallicFactor=0,roughnessFactor=.72),
        doubleSided=False,extras=dict(generatedPersonalFitting=True,materialSource=material_source)))
    mesh=len(g['meshes']);g['meshes'].append(dict(name='Personal_Neck_Bridge',primitives=[dict(
        attributes=dict(POSITION=writer.acc(positions,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),
            JOINTS_0=writer.acc(joints,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4')),
        indices=writer.acc(faces.reshape(-1),'SCALAR',5125),material=material)],
        extras=dict(generatedPersonalFitting=True,originalSF3Geometry=False)))
    # Keep the existing joint hierarchy and rigid portrait parent untouched.
    # A skinned mesh is a sibling under the actor, not a child of either joint.
    # Its inverse binds already supply the two-joint animation in mesh space.
    node=len(g['nodes']);g['nodes'].append(dict(name='Personal_Neck_Bridge',mesh=mesh,skin=0))
    g['nodes'][outer]['children'].append(node)
    require(g['meshes'][g['nodes'][portrait]['mesh']]==before['meshes'][before['nodes'][portrait]['mesh']],
            'Personal bridge changed a portrait accessor')
    require(bytes(writer.b[:len(original_binary)])==original_binary,'Personal bridge changed original bytes')
    require(g['animations']==before['animations'],'Personal bridge changed source animation')
    require(g['skins']==before['skins'],'Personal bridge changed source inverse binds')
    for key in ('textures','images','samplers'):
        require(g[key]==before[key],'Personal bridge changed original '+key)
    require(not args.output.exists(),'Refuse to replace a private candidate');output=private_output(args.output)
    identity=writer.save(output/model.name);profile.update(identity)
    profile['personalNeckBridge']=dict(generatedGeometry=True,originalPortraitVerticesChanged=0,
        sourceJoints=['head','neck'],vertices=len(positions),triangles=len(faces))
    write_new(output/'SF3_Erlang_Profile.json',encoded(profile))
    portrait_points=accessor_read(before,b,primitives[0]['attributes']['POSITION'])
    receipt=dict(sourceProfile=record(args.profile),character=record(output/model.name),
        profile=record(output/'SF3_Erlang_Profile.json'),originalPortraitVertices=len(portrait_points),
        originalPortraitVerticesChanged=0,changedPortraitVertexPercent=0,
        originalPortraitAttributesIndicesImagesUnchanged=True,allOriginalEmbeddedBytesUnchanged=len(original_binary),
        sourceAnimationCountUnchanged=len(g['animations']),sourceNeckInPortraitBindSpace=neck_local.tolist(),
        generatedGeometry=dict(name='Personal_Neck_Bridge',vertices=len(positions),triangles=len(faces),
            skinJoints=['head','neck'],skinJointNodes=[head,neck],originalSkin=0,skinJointSlots=slots,
            bridgeToOriginalActorBindSpace=local.tolist(),
            upperY=.055,lowerY=float(neck_local[1])-.025,topRadii=[.050,.043],bottomRadii=[.060,.049]),
        material=material_source,boundaries=['Generated neck fitting mesh, not recovered D15 or original portrait geometry.',
            'Plain skin colour derived from original lower side/back portrait texture; original face, UV and image bytes remain unchanged.',
            'Original two-joint bind space and smooth weights provide pose continuity; native renderer acceptance is still required.'])
    write_new(output/'erlang-personal-neck-bridge-private.json',encoded(receipt))
    return {k:v for k,v in receipt.items() if k not in ('generatedGeometry','material','boundaries')}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True);parser.add_argument('--profile-sha256',required=True)
    parser.add_argument('--output',type=Path,required=True)
    print(json.dumps(bind(parser.parse_args())))


if __name__=='__main__':main()
